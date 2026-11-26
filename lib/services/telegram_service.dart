import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'action_handler.dart';
import 'ai_service.dart';
import 'routine_service.dart';
import 'routine_scheduler_service.dart';
import 'screen_automation_service.dart';
import '../models/autonomous_routine.dart';

class TelegramService {
  final ActionHandler _actionHandler;
  final AiService _aiService;
  
  String _botToken = '';
  bool _isEnabled = false;
  int _lastUpdateId = 0;
  bool _isPolling = false;
  Timer? _pollingTimer;
  String? _lastActiveChatId;
  Completer<bool>? _pendingConfirmationCompleter;
  final Set<String> _processedMessageIds = {};

  /// Optional UI callback to display Telegram commands and progress in HomeScreen
  void Function(String role, String text)? onUiMessage;

  TelegramService(this._actionHandler, this._aiService);

  String get botToken => _botToken;
  bool get isEnabled => _isEnabled;
  String? get lastActiveChatId => _lastActiveChatId;

  /// Request approval from user via Telegram for supervised checkpoint actions
  Future<bool> requestConfirmation(String prompt) async {
    if (_lastActiveChatId == null || _botToken.isEmpty) return false;
    await _sendMessage(
      _lastActiveChatId!,
      '⚠️ SUPERVISED CHECKPOINT REQUIRED:\n$prompt\n\nReply with YES to approve or NO to reject.',
    );
    _pendingConfirmationCompleter = Completer<bool>();
    Timer(const Duration(seconds: 90), () {
      if (_pendingConfirmationCompleter != null &&
          !_pendingConfirmationCompleter!.isCompleted) {
        _pendingConfirmationCompleter!.complete(false);
      }
    });
    return _pendingConfirmationCompleter!.future;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _botToken = prefs.getString('telegram_bot_token') ?? '';
    _isEnabled = prefs.getBool('telegram_enabled') ?? false;
    _lastActiveChatId = prefs.getString('telegram_last_chat_id');

    // Wire native Telegram message receiver from persistent background service
    RoutineSchedulerService().onTelegramMessageCallback = (chatId, text, {String? messageId}) {
      unawaited(_handleIncomingMessage(chatId, text, messageId: messageId));
    };

    if (_isEnabled && _botToken.isNotEmpty) {
      await startPolling();
    }
  }

  /// Drain any pending Telegram messages queued natively before Dart was ready
  Future<void> checkPendingMessages() async {
    final pendingList = await ScreenAutomationService().getPendingTelegramMessages();
    for (final pendingMsg in pendingList) {
      final cId = pendingMsg['chatId'];
      final msgText = pendingMsg['text'];
      final msgId = pendingMsg['messageId'];
      if (cId != null && msgText != null && cId.isNotEmpty && msgText.isNotEmpty) {
        unawaited(_handleIncomingMessage(cId, msgText, messageId: msgId));
      }
    }
  }

  Future<void> saveSettings({
    required String botToken,
    required bool isEnabled,
    String? chatId,
  }) async {
    _botToken = botToken;
    _isEnabled = isEnabled;
    if (chatId != null && chatId.isNotEmpty) {
      _lastActiveChatId = chatId;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_bot_token', _botToken);
    await prefs.setBool('telegram_enabled', _isEnabled);
    if (_lastActiveChatId != null) {
      await prefs.setString('telegram_last_chat_id', _lastActiveChatId!);
    }

    if (_isEnabled && _botToken.isNotEmpty) {
      await startPolling();
    } else {
      stopPolling();
    }
    await ScreenAutomationService().reloadTelegramPoller(
      botToken: _botToken,
      telegramEnabled: _isEnabled,
    );
  }

  Future<void> startPolling() async {
    if (_isPolling) return;
    _isPolling = true;
    await ScreenAutomationService().startBackgroundService(
      botToken: _botToken,
      telegramEnabled: _isEnabled,
    );
    await ScreenAutomationService().reloadTelegramPoller(
      botToken: _botToken,
      telegramEnabled: _isEnabled,
    );
  }

  void stopPolling() {
    _isPolling = false;
    _pollingTimer?.cancel();
    ScreenAutomationService().reloadTelegramPoller(
      botToken: _botToken,
      telegramEnabled: false,
    );
  }

  Future<void> _pollUpdates() async {
    if (!_isPolling || _botToken.isEmpty) return;

    try {
      final url = Uri.parse('https://api.telegram.org/bot$_botToken/getUpdates');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'offset': _lastUpdateId + 1,
          'timeout': 15, // Short long-poll timeout
          'allowed_updates': ['message'],
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          final results = data['result'] as List;
          for (final update in results) {
            _lastUpdateId = update['update_id'];
            if (update['message'] != null && update['message']['text'] != null) {
              final text = update['message']['text'];
              final chatId = update['message']['chat']['id'];
              
              // Process message asynchronously so we don't block the polling loop
              _handleIncomingMessage(chatId.toString(), text);
            }
          }
        }
      }
    } catch (e) {
      print('Telegram polling error: $e');
    }

    // Continue polling
    if (_isPolling) {
      _pollingTimer = Timer(const Duration(seconds: 1), _pollUpdates);
    }
  }

  Future<void> _handleIncomingMessage(String chatId, String text, {String? messageId}) async {
    if (messageId != null && messageId.isNotEmpty) {
      if (!_processedMessageIds.add(messageId)) {
        return;
      }
      if (_processedMessageIds.length > 200) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }
    }

    _lastActiveChatId = chatId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_last_chat_id', chatId);
    final trimmed = text.trim();

    // Check if answering a pending supervised confirmation checkpoint
    if (_pendingConfirmationCompleter != null &&
        !_pendingConfirmationCompleter!.isCompleted) {
      if (trimmed.toLowerCase() == 'yes' ||
          trimmed.toLowerCase() == 'approve') {
        _pendingConfirmationCompleter!.complete(true);
        await _sendMessage(chatId, '✅ Action approved. Continuing routine.');
        return;
      } else if (trimmed.toLowerCase() == 'no' ||
          trimmed.toLowerCase() == 'reject') {
        _pendingConfirmationCompleter!.complete(false);
        await _sendMessage(chatId, '❌ Action rejected. Skipping.');
        return;
      }
    }

    // Handle routine commands
    if (trimmed == '/macros' || trimmed == '/routines') {
      final routines = RoutineService().getAllRoutines();
      if (routines.isEmpty) {
        await _sendMessage(chatId, '📋 No autonomous routines configured yet.');
        return;
      }
      final buffer = StringBuffer('📋 Autonomous Routines:\n\n');
      for (final r in routines) {
        final status = r.isEnabled ? '🟢 ACTIVE' : '⚪ DISABLED';
        final last = r.lastRunStatus != null
            ? ' (Last: ${r.lastRunStatus})'
            : '';
        buffer.writeln('• *${r.name}* [${r.id}]');
        buffer.writeln(
            '  $status | ${r.schedule.intervalMinutes}m interval$last');
      }
      buffer.writeln('\nUse `/run <name>` to execute or `/stop` to cancel.');
      await _sendMessage(chatId, buffer.toString());
      return;
    }

    if (trimmed.startsWith('/run ') || trimmed.startsWith('/macro ')) {
      final query = trimmed.split(' ').sublist(1).join(' ').trim().toLowerCase();
      final routines = RoutineService().getAllRoutines();
      final target = routines.firstWhere(
        (r) =>
            r.id.toLowerCase() == query ||
            r.name.toLowerCase().contains(query),
        orElse: () => const AutonomousRoutine(
          id: '',
          name: '',
          description: '',
          personaId: '',
          goalPrompt: '',
          successCriteria: '',
        ),
      );

      if (target.id.isEmpty) {
        await _sendMessage(chatId,
            '❌ Routine "$query" not found. Type /macros to list available routines.');
        return;
      }

      onUiMessage?.call('user', '📩 [Telegram] $trimmed');
      await _sendMessage(
          chatId, '🚀 Triggering routine: *${target.name}* autonomously...');
      final result = await RoutineSchedulerService().triggerRoutine(
        target.id,
        isManual: true,
      );
      onUiMessage?.call('assistant', '🏁 Routine finished: $result');
      await _sendMessage(chatId, '🏁 Routine finished with result: $result');
      return;
    }

    if (trimmed == '/stop') {
      RoutineSchedulerService().cancelActiveRoutine();
      await _sendMessage(
          chatId, '🛑 Emergency stop signal sent to active routine.');
      return;
    }

    // Surface incoming command in UI & elevate wake/execution lock FIRST before network calls
    onUiMessage?.call('user', '📩 [Telegram] $text');
    final screenService = ScreenAutomationService();
    await screenService.setKeepScreenOn(true);
    await screenService.startExecutionMode('Telegram: ${trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed}');
    unawaited(_sendMessage(chatId, '🤖 Received: "$text". Working on it...'));

    bool wasLockedInitially = false;
    try {
      wasLockedInitially = await screenService.isKeyguardLocked();

      // 1. Send text to AI
      final aiResponse = await _aiService.sendMessage(text);

      // 2. Parse the action
      final action = _aiService.parseAction(aiResponse);

      if (action != null) {
        final isInteractive = await screenService.isScreenInteractive();
        if (!isInteractive || wasLockedInitially) {
          await screenService.wakeScreen();
          await screenService.dismissKeyguard();
          await Future.delayed(const Duration(milliseconds: 500));
          if (await screenService.isKeyguardLocked()) {
            // Uncover OS lockscreen underneath MainActivity so accessibility swipe can dismiss swipe-lock
            await screenService.setShowWhenLocked(false);
            await Future.delayed(const Duration(milliseconds: 400));
            await screenService.swipe(540, 1800, 540, 400);
            await Future.delayed(const Duration(milliseconds: 700));
          }
        }

        if (await screenService.isKeyguardLocked()) {
          const lockedMsg =
              '🔒 Device is locked with a secure PIN/Pattern and could not be unlocked automatically.';
          onUiMessage?.call('assistant', lockedMsg);
          await _sendMessage(chatId, lockedMsg);
          return;
        }

        // 3. Execute the action
        final result = await _actionHandler.execute(
          action,
          aiService: _aiService,
          onProgress: (msg) {
            onUiMessage?.call('assistant', '⏳ $msg');
            _sendMessage(chatId, '⏳ $msg');
          },
        );
        final doneMsg = '✅ ${result.details ?? "Done"}';
        onUiMessage?.call('assistant', doneMsg);
        await _sendMessage(chatId, doneMsg);
      } else {
        // It's a plain text response
        onUiMessage?.call('assistant', '💬 $aiResponse');
        await _sendMessage(chatId, '💬 $aiResponse');
      }
    } catch (e) {
      final errMsg = '❌ Error: $e';
      onUiMessage?.call('assistant', errMsg);
      await _sendMessage(chatId, errMsg);
    } finally {
      if (wasLockedInitially) {
        try {
          await screenService.pressHome();
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (_) {}
      }
      await screenService.setKeepScreenOn(false);
      await screenService.stopExecutionMode(returnToListener: true);
      if (wasLockedInitially) {
        try {
          await Future.delayed(const Duration(milliseconds: 300));
          await screenService.lockScreen();
        } catch (_) {}
      }
      await screenService.setShowWhenLocked(true);
    }
  }

  Future<void> _sendMessage(String chatId, String text) async {
    if (_botToken.isEmpty) return;
    final client = http.Client();
    try {
      final url = Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage');
      await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      print('Failed to send telegram message: $e');
    } finally {
      client.close();
    }
  }

  /// Notify the user via Telegram about autonomous routine activities
  static Future<void> notifyRoutineActivity({
    required String routineName,
    required String event, // 'triggered', 'postponed', 'completed', 'failed'
    String? goalPrompt,
    String? reason,
    String? result,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('telegram_enabled') ?? false;
      final botToken = prefs.getString('telegram_bot_token') ?? '';
      final chatId = prefs.getString('telegram_last_chat_id');

      if (!isEnabled || botToken.isEmpty || chatId == null || chatId.isEmpty) {
        return;
      }

      String message;
      switch (event) {
        case 'triggered':
          message = '⏰ Scheduled Routine Triggered\n\n'
              '📌 Routine: $routineName\n'
              '🎯 Goal: ${goalPrompt ?? "Autonomous routine"}\n'
              '⏳ Status: Executing in background...';
          break;
        case 'postponed':
          message = '⏳ Scheduled Routine Postponed\n\n'
              '📌 Routine: $routineName\n'
              '⚠️ Reason: ${reason ?? "User is actively using the screen."}\n'
              '🔁 Will retry in 5 minutes.';
          break;
        case 'completed':
          message = '✅ Scheduled Routine Completed\n\n'
              '📌 Routine: $routineName\n'
              '🏁 Result: ${result ?? "Done."}';
          break;
        case 'failed':
          message = '❌ Scheduled Routine Failed\n\n'
              '📌 Routine: $routineName\n'
              '⚠️ Details: ${reason ?? result ?? "Routine did not complete."}';
          break;
        default:
          message = '🤖 Routine Update: $routineName ($event)';
      }

      final url = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': message,
        }),
      );
    } catch (e) {
      print('Failed to send Telegram routine notification: $e');
    }
  }

  void dispose() {
    stopPolling();
  }
}
