import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/autonomous_routine.dart';

class RoutineService {
  static final RoutineService _instance = RoutineService._internal();
  factory RoutineService() => _instance;
  RoutineService._internal();

  List<AutonomousRoutine> _routines = [];
  bool _isLoaded = false;
  final ValueNotifier<int> routinesChangedNotifier = ValueNotifier(0);

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/autonomous_routines.json');
  }

  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content) as List;
          _routines = decoded
              .map((item) =>
                  AutonomousRoutine.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error loading routines: $e');
    }

    if (_routines.isEmpty) {
      _routines = _getDefaultRoutines();
      await _saveAll();
    }

    _isLoaded = true;
    routinesChangedNotifier.value++;
  }

  List<AutonomousRoutine> getAllRoutines() {
    return List.unmodifiable(_routines);
  }

  List<AutonomousRoutine> getActiveRoutines() {
    return _routines.where((r) => r.isEnabled).toList();
  }

  AutonomousRoutine? getRoutineById(String id) {
    try {
      return _routines.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRoutine(AutonomousRoutine routine) async {
    await init();
    final idx = _routines.indexWhere((r) => r.id == routine.id);
    if (idx >= 0) {
      _routines[idx] = routine;
    } else {
      _routines.add(routine);
    }
    await _saveAll();
    routinesChangedNotifier.value++;
  }

  Future<void> deleteRoutine(String id) async {
    await init();
    _routines.removeWhere((r) => r.id == id);
    await _saveAll();
    routinesChangedNotifier.value++;
  }

  Future<void> toggleRoutine(String id, bool isEnabled) async {
    await init();
    final idx = _routines.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _routines[idx] = _routines[idx].copyWith(isEnabled: isEnabled);
      await _saveAll();
      routinesChangedNotifier.value++;
    }
  }

  Future<void> recordRunResult(
    String id, {
    required String status,
    String? failureReason,
  }) async {
    await init();
    final idx = _routines.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      final routine = _routines[idx];
      final isSuccess = status == 'success';
      final newFailures = isSuccess ? 0 : routine.consecutiveFailures + 1;
      final shouldPause = newFailures >= routine.guardrails.pauseOnConsecutiveFailures;

      _routines[idx] = routine.copyWith(
        lastRunTime: DateTime.now(),
        lastRunStatus: status,
        consecutiveFailures: newFailures,
        lastFailureReason: failureReason,
        isEnabled: shouldPause ? false : routine.isEnabled,
      );
      await _saveAll();
      routinesChangedNotifier.value++;
    }
  }

  String exportCatalogJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_routines.map((r) => r.toJson()).toList());
  }

  Future<int> importCatalogJson(String jsonStr) async {
    await init();
    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) {
      throw const FormatException('Expected a JSON array of routines');
    }
    int importedCount = 0;
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final routine = AutonomousRoutine.fromJson(item);
        final existingIdx = _routines.indexWhere((r) => r.id == routine.id);
        if (existingIdx >= 0) {
          _routines[existingIdx] = routine;
        } else {
          _routines.add(routine);
        }
        importedCount++;
      }
    }
    await _saveAll();
    routinesChangedNotifier.value++;
    return importedCount;
  }

  Future<void> _saveAll() async {
    try {
      final file = await _localFile;
      final jsonStr = jsonEncode(_routines.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Error saving routines: $e');
    }
  }

  List<AutonomousRoutine> _getDefaultRoutines() {
    return [
      const AutonomousRoutine(
        id: 'whatsapp_auto_responder',
        name: 'WhatsApp Unread Checker & Auto-Responder',
        description:
            'Periodically checks WhatsApp for unread messages and replies politely according to persona instructions.',
        personaId: 'personal_assistant',
        goalPrompt:
            'Open WhatsApp. Look for chats with unread messages. Open each unread chat, read the recent message, and reply politely if a response is expected. Do not reply to messages you have already responded to. Return to the chat list when done.',
        successCriteria:
            'All unread messages evaluated and handled, and WhatsApp navigated back to the chat list or home screen.',
        executionMode: RoutineExecutionMode.autonomous,
        schedule: RoutineSchedule(
          type: ScheduleType.interval,
          intervalMinutes: 30,
          activeHourStart: 9,
          activeHourEnd: 21,
          isEnabled: false, // Default off until user configures
        ),
        guardrails: RoutineGuardrails(
          maxStepsPerRun: 12,
          maxDurationSeconds: 180,
          pauseOnConsecutiveFailures: 3,
        ),
        isEnabled: false,
      ),
    ];
  }
}
