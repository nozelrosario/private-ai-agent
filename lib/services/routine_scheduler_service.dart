import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/autonomous_routine.dart';
import 'routine_service.dart';
import 'screen_automation_service.dart';
import 'telegram_service.dart';

class RoutineSchedulerService {
  static final RoutineSchedulerService _instance =
      RoutineSchedulerService._internal();
  factory RoutineSchedulerService() => _instance;
  RoutineSchedulerService._internal();

  static const _channel = MethodChannel('com.privateagent/accessibility');
  final ScreenAutomationService _screenService = ScreenAutomationService();
  final RoutineService _routineService = RoutineService();

  bool _initialized = false;
  bool _isRoutineRunning = false;
  String? _activeRunningRoutineId;

  /// Callback to execute routine with TaskExecutor when triggered
  Future<String> Function(AutonomousRoutine routine, {bool wasLockedInitially})?
      onExecuteRoutineCallback;

  /// Callback to cancel execution
  VoidCallback? onCancelExecutionCallback;

  bool get isRoutineRunning => _isRoutineRunning;
  String? get activeRunningRoutineId => _activeRunningRoutineId;

  Future<void> init({
    Future<String> Function(AutonomousRoutine routine, {bool wasLockedInitially})?
        onExecuteRoutine,
    VoidCallback? onCancelExecution,
  }) async {
    if (onExecuteRoutine != null) onExecuteRoutineCallback = onExecuteRoutine;
    if (onCancelExecution != null) onCancelExecutionCallback = onCancelExecution;

    if (_initialized) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onRoutineTriggered':
          final routineId = call.arguments['routine_id'] as String? ?? '';
          if (routineId.isNotEmpty) {
            unawaited(triggerRoutine(routineId));
          }
          break;
        case 'onRoutineStopped':
          cancelActiveRoutine();
          break;
        case 'onBackgroundServiceStopped':
          debugPrint('Background service stopped by user notification action');
          break;
      }
    });

    _initialized = true;

    // Check if an alarm triggered cold start with a pending routine
    final pendingRoutine = await _screenService.getPendingRoutine();
    if (pendingRoutine != null && pendingRoutine.isNotEmpty) {
      unawaited(triggerRoutine(pendingRoutine));
    }

    await syncAllSchedules();
  }

  /// Synchronize all routine alarms based on their current enabled and schedule states
  Future<void> syncAllSchedules() async {
    await _routineService.init();
    final routines = _routineService.getAllRoutines();
    bool hasActiveSchedules = false;
    for (final routine in routines) {
      if (routine.isEnabled && routine.schedule.isEnabled) {
        hasActiveSchedules = true;
        await scheduleRoutine(routine);
      } else {
        await cancelRoutine(routine.id);
      }
    }

    if (hasActiveSchedules) {
      await _screenService.startBackgroundService();
    }
  }

  /// Schedule the next alarm trigger for a given routine
  Future<void> scheduleRoutine(AutonomousRoutine routine) async {
    if (!routine.isEnabled || !routine.schedule.isEnabled) {
      await cancelRoutine(routine.id);
      return;
    }

    final delaySeconds = calculateNextTriggerDelaySeconds(routine.schedule);
    try {
      await _channel.invokeMethod('scheduleRoutineAlarm', {
        'routineId': routine.id,
        'delaySeconds': delaySeconds,
      });
      debugPrint(
          'Scheduled routine "${routine.name}" to trigger in ${delaySeconds}s');
    } catch (e) {
      debugPrint('Failed to schedule routine alarm: $e');
    }
  }

  /// Cancel any scheduled alarm for a routine
  Future<void> cancelRoutine(String routineId) async {
    try {
      await _channel.invokeMethod('cancelRoutineAlarm', {
        'routineId': routineId,
      });
    } catch (e) {
      debugPrint('Failed to cancel routine alarm: $e');
    }
  }

  /// Calculates seconds until the next execution based on schedule and active window
  static int calculateNextTriggerDelaySeconds(RoutineSchedule schedule,
      [DateTime? now]) {
    final current = now ?? DateTime.now();

    if (schedule.type == ScheduleType.interval) {
      if (schedule.isWithinActiveWindow(current)) {
        return schedule.intervalMinutes * 60;
      } else {
        // Find seconds until the next activeHourStart
        final startHour = schedule.activeHourStart ?? 9;
        var nextActive = DateTime(
          current.year,
          current.month,
          current.day,
          startHour,
          0,
        );
        if (nextActive.isBefore(current)) {
          nextActive = nextActive.add(const Duration(days: 1));
        }
        final diff = nextActive.difference(current).inSeconds;
        return diff > 0 ? diff : schedule.intervalMinutes * 60;
      }
    } else {
      // Daily specific time
      final targetHour = schedule.dailyHour ?? 9;
      final targetMin = schedule.dailyMinute ?? 0;
      var targetTime = DateTime(
        current.year,
        current.month,
        current.day,
        targetHour,
        targetMin,
      );
      if (targetTime.isBefore(current) || targetTime.isAtSameMomentAs(current)) {
        targetTime = targetTime.add(const Duration(days: 1));
      }
      return targetTime.difference(current).inSeconds;
    }
  }

  /// Trigger execution of a routine (called by AlarmManager or manual run)
  Future<String> triggerRoutine(
    String routineId, {
    bool isManual = false,
  }) async {
    if (_isRoutineRunning) {
      debugPrint('Another routine is already running. Skipping $routineId');
      return 'Busy';
    }

    await _routineService.init();
    final routine = _routineService.getRoutineById(routineId);
    if (routine == null) return 'Routine not found';

    // 1. Idle Screen Gating: check if user is actively using the screen
    if (!isManual) {
      final userActive = await _screenService.isUserInteracting(windowMs: 30000);
      if (userActive) {
        debugPrint(
            'User actively using device. Postponing routine "${routine.name}" by 5 minutes');
        await _routineService.recordRunResult(
          routine.id,
          status: 'postponed',
          failureReason: 'Postponed due to active user interaction',
        );
        unawaited(TelegramService.notifyRoutineActivity(
          routineName: routine.name,
          event: 'postponed',
          reason: 'User is actively interacting with the device',
        ));
        // Postpone for 5 minutes
        await _channel.invokeMethod('scheduleRoutineAlarm', {
          'routineId': routine.id,
          'delaySeconds': 300,
        });
        return 'Postponed';
      }
    }

    // Notify Telegram about routine being triggered by schedule
    if (!isManual) {
      unawaited(TelegramService.notifyRoutineActivity(
        routineName: routine.name,
        event: 'triggered',
        goalPrompt: routine.goalPrompt,
      ));
    }

    _isRoutineRunning = true;
    _activeRunningRoutineId = routineId;

    bool wasLockedInitially = false;

    try {
      // 2. Check lockscreen state
      wasLockedInitially = await _screenService.isKeyguardLocked();

      // 3. Waking screen if display is off
      final isInteractive = await _screenService.isScreenInteractive();
      if (!isInteractive || wasLockedInitially) {
        await _screenService.wakeScreen();
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      // 4. Start native Foreground Service with ongoing notification & Emergency Stop
      await _channel.invokeMethod(
        'startRoutineForegroundService',
        {'title': 'Executing: ${routine.name}'},
      );

      // 5. Run the actual loop via callback
      String result = 'Executed';
      if (onExecuteRoutineCallback != null) {
        result = await onExecuteRoutineCallback!(
          routine,
          wasLockedInitially: wasLockedInitially,
        );
      }

      final isSuccess = !result.toLowerCase().contains('failed') &&
          !result.toLowerCase().contains('cancelled') &&
          !result.toLowerCase().contains('timeout');

      await _routineService.recordRunResult(
        routine.id,
        status: isSuccess ? 'success' : 'failed',
        failureReason: isSuccess ? null : result,
      );

      if (!isManual) {
        unawaited(TelegramService.notifyRoutineActivity(
          routineName: routine.name,
          event: isSuccess ? 'completed' : 'failed',
          result: result,
        ));
      }

      return result;
    } catch (e) {
      debugPrint('Error executing routine ${routine.name}: $e');
      await _routineService.recordRunResult(
        routine.id,
        status: 'failed',
        failureReason: e.toString(),
      );
      if (!isManual) {
        unawaited(TelegramService.notifyRoutineActivity(
          routineName: routine.name,
          event: 'failed',
          reason: e.toString(),
        ));
      }
      return 'Error: $e';
    } finally {
      // 6. Security restoration: re-lock if originally locked
      if (wasLockedInitially) {
        try {
          await _screenService.pressHome();
          await Future.delayed(const Duration(milliseconds: 1000));
          await _screenService.lockScreen();
        } catch (_) {}
      }

      // 7. Stop Execution Mode and return to persistent background listener & release WakeLock
      try {
        await _channel.invokeMethod('stopRoutineForegroundService', {'returnToListener': true});
      } catch (_) {}

      _isRoutineRunning = false;
      _activeRunningRoutineId = null;

      // 8. Reschedule next recurring interval
      await scheduleRoutine(routine);
    }
  }

  /// Emergency cancel currently active routine
  void cancelActiveRoutine() {
    if (_isRoutineRunning) {
      onCancelExecutionCallback?.call();
    }
  }
}
