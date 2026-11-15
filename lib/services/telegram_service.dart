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

    if (_isEnabled && _botToken.isNotEmpty) {
      startPolling();
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
      startPolling();
    } else {
      stopPolling();
    }
  }

  void startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    ScreenAutomationService().startBackgroundService();
    _pollUpdates();
  }

  void stopPolling() {
    _isPolling = false;
    _pollingTimer?.cancel();
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
          'timeout': 30, // Long polling timeout
          'allowed_updates': ['message'],
        }),
      );

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

  Future<void> _handleIncomingMessage(String chatId, String text) async {
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

      await _sendMessage(
          chatId, '🚀 Triggering routine: *${target.name}* autonomously...');
      final result = await RoutineSchedulerService().triggerRoutine(
        target.id,
        isManual: true,
      );
      await _sendMessage(chatId, '🏁 Routine finished with result: $result');
      return;
    }

    if (trimmed == '/stop') {
      RoutineSchedulerService().cancelActiveRoutine();
      await _sendMessage(
          chatId, '🛑 Emergency stop signal sent to active routine.');
      return;
    }

    // Acknowledge receipt
    await _sendMessage(chatId, '🤖 Received: "$text". Working on it...');

    try {
      // 1. Send text to AI
      final aiResponse = await _aiService.sendMessage(text);
      
      // 2. Parse the action
      final action = _aiService.parseAction(aiResponse);

      if (action != null) {
        // 3. Execute the action
        final result = await _actionHandler.execute(
          action,
          aiService: _aiService,
          onProgress: (msg) {
            // Send progress updates back to telegram
            _sendMessage(chatId, '⏳ $msg');
          },
        );
        await _sendMessage(chatId, '✅ ${result.details ?? "Done"}');
      } else {
        // It's a plain text response
        await _sendMessage(chatId, '💬 $aiResponse');
      }
    } catch (e) {
      await _sendMessage(chatId, '❌ Error: $e');
    }
  }

  Future<void> _sendMessage(String chatId, String text) async {
    if (_botToken.isEmpty) return;
    try {
      final url = Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
        }),
      );
    } catch (e) {
      print('Failed to send telegram message: $e');
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
