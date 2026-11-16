import 'dart:convert';

enum RoutineExecutionMode {
  autonomous,
  supervised,
}

enum ScheduleType {
  interval,
  dailyTime,
}

class RoutineSchedule {
  final ScheduleType type;
  final int intervalMinutes; // e.g. 15, 30, 60
  final int? dailyHour; // 0-23
  final int? dailyMinute; // 0-59
  final int? activeHourStart; // e.g. 9 (9 AM)
  final int? activeHourEnd; // e.g. 21 (9 PM)
  final bool isEnabled;

  const RoutineSchedule({
    this.type = ScheduleType.interval,
    this.intervalMinutes = 30,
    this.dailyHour,
    this.dailyMinute,
    this.activeHourStart,
    this.activeHourEnd,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'interval_minutes': intervalMinutes,
        'daily_hour': dailyHour,
        'daily_minute': dailyMinute,
        'active_hour_start': activeHourStart,
        'active_hour_end': activeHourEnd,
        'is_enabled': isEnabled,
      };

  factory RoutineSchedule.fromJson(Map<String, dynamic> json) =>
      RoutineSchedule(
        type: json['type'] == 'dailyTime'
            ? ScheduleType.dailyTime
            : ScheduleType.interval,
        intervalMinutes: json['interval_minutes'] as int? ?? 30,
        dailyHour: json['daily_hour'] as int?,
        dailyMinute: json['daily_minute'] as int?,
        activeHourStart: json['active_hour_start'] as int?,
        activeHourEnd: json['active_hour_end'] as int?,
        isEnabled: json['is_enabled'] as bool? ?? true,
      );

  RoutineSchedule copyWith({
    ScheduleType? type,
    int? intervalMinutes,
    int? dailyHour,
    int? dailyMinute,
    int? activeHourStart,
    int? activeHourEnd,
    bool? isEnabled,
  }) {
    return RoutineSchedule(
      type: type ?? this.type,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      dailyHour: dailyHour ?? this.dailyHour,
      dailyMinute: dailyMinute ?? this.dailyMinute,
      activeHourStart: activeHourStart ?? this.activeHourStart,
      activeHourEnd: activeHourEnd ?? this.activeHourEnd,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  /// Whether current local time falls inside the configured active hours window
  bool isWithinActiveWindow([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (activeHourStart == null || activeHourEnd == null) return true;
    final hour = current.hour;
    if (activeHourStart! <= activeHourEnd!) {
      return hour >= activeHourStart! && hour < activeHourEnd!;
    } else {
      // Overnight window (e.g. 22:00 to 06:00)
      return hour >= activeHourStart! || hour < activeHourEnd!;
    }
  }
}

class RoutineGuardrails {
  final int maxStepsPerRun;
  final int maxDurationSeconds;
  final int pauseOnConsecutiveFailures;

  const RoutineGuardrails({
    this.maxStepsPerRun = 10,
    this.maxDurationSeconds = 180,
    this.pauseOnConsecutiveFailures = 3,
  });

  Map<String, dynamic> toJson() => {
        'max_steps_per_run': maxStepsPerRun,
        'max_duration_seconds': maxDurationSeconds,
        'pause_on_consecutive_failures': pauseOnConsecutiveFailures,
      };

  factory RoutineGuardrails.fromJson(Map<String, dynamic> json) =>
      RoutineGuardrails(
        maxStepsPerRun: json['max_steps_per_run'] as int? ?? 10,
        maxDurationSeconds: json['max_duration_seconds'] as int? ?? 180,
        pauseOnConsecutiveFailures:
            json['pause_on_consecutive_failures'] as int? ?? 3,
      );

  RoutineGuardrails copyWith({
    int? maxStepsPerRun,
    int? maxDurationSeconds,
    int? pauseOnConsecutiveFailures,
  }) {
    return RoutineGuardrails(
      maxStepsPerRun: maxStepsPerRun ?? this.maxStepsPerRun,
      maxDurationSeconds: maxDurationSeconds ?? this.maxDurationSeconds,
      pauseOnConsecutiveFailures:
          pauseOnConsecutiveFailures ?? this.pauseOnConsecutiveFailures,
    );
  }
}

class AutonomousRoutine {
  final String id;
  final String name;
  final String description;
  final String personaId;
  final String? unlockSkillId;
  final String goalPrompt;
  final String successCriteria;
  final RoutineExecutionMode executionMode;
  final RoutineSchedule schedule;
  final RoutineGuardrails guardrails;
  final bool isEnabled;
  final DateTime? lastRunTime;
  final String? lastRunStatus; // 'success', 'failed', 'postponed', 'cancelled'
  final int consecutiveFailures;
  final String? lastFailureReason;

  const AutonomousRoutine({
    required this.id,
    required this.name,
    required this.description,
    required this.personaId,
    this.unlockSkillId,
    required this.goalPrompt,
    required this.successCriteria,
    this.executionMode = RoutineExecutionMode.autonomous,
    this.schedule = const RoutineSchedule(),
    this.guardrails = const RoutineGuardrails(),
    this.isEnabled = true,
    this.lastRunTime,
    this.lastRunStatus,
    this.consecutiveFailures = 0,
    this.lastFailureReason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'persona_id': personaId,
        'unlock_skill_id': unlockSkillId,
        'goal_prompt': goalPrompt,
        'success_criteria': successCriteria,
        'execution_mode': executionMode.name,
        'schedule': schedule.toJson(),
        'guardrails': guardrails.toJson(),
        'is_enabled': isEnabled,
        'last_run_time': lastRunTime?.toIso8601String(),
        'last_run_status': lastRunStatus,
        'consecutive_failures': consecutiveFailures,
        'last_failure_reason': lastFailureReason,
      };

  factory AutonomousRoutine.fromJson(Map<String, dynamic> json) =>
      AutonomousRoutine(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Autonomous Routine',
        description: json['description'] as String? ?? '',
        personaId: json['persona_id'] as String? ?? 'general_assistant',
        unlockSkillId: json['unlock_skill_id'] as String?,
        goalPrompt: json['goal_prompt'] as String? ?? '',
        successCriteria: json['success_criteria'] as String? ?? '',
        executionMode: json['execution_mode'] == 'supervised'
            ? RoutineExecutionMode.supervised
            : RoutineExecutionMode.autonomous,
        schedule: json['schedule'] != null
            ? RoutineSchedule.fromJson(json['schedule'] as Map<String, dynamic>)
            : const RoutineSchedule(),
        guardrails: json['guardrails'] != null
            ? RoutineGuardrails.fromJson(
                json['guardrails'] as Map<String, dynamic>)
            : const RoutineGuardrails(),
        isEnabled: json['is_enabled'] as bool? ?? true,
        lastRunTime: json['last_run_time'] != null
            ? DateTime.tryParse(json['last_run_time'] as String)
            : null,
        lastRunStatus: json['last_run_status'] as String?,
        consecutiveFailures: json['consecutive_failures'] as int? ?? 0,
        lastFailureReason: json['last_failure_reason'] as String?,
      );

  AutonomousRoutine copyWith({
    String? id,
    String? name,
    String? description,
    String? personaId,
    String? unlockSkillId,
    String? goalPrompt,
    String? successCriteria,
    RoutineExecutionMode? executionMode,
    RoutineSchedule? schedule,
    RoutineGuardrails? guardrails,
    bool? isEnabled,
    DateTime? lastRunTime,
    String? lastRunStatus,
    int? consecutiveFailures,
    String? lastFailureReason,
  }) {
    return AutonomousRoutine(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      personaId: personaId ?? this.personaId,
      unlockSkillId: unlockSkillId ?? this.unlockSkillId,
      goalPrompt: goalPrompt ?? this.goalPrompt,
      successCriteria: successCriteria ?? this.successCriteria,
      executionMode: executionMode ?? this.executionMode,
      schedule: schedule ?? this.schedule,
      guardrails: guardrails ?? this.guardrails,
      isEnabled: isEnabled ?? this.isEnabled,
      lastRunTime: lastRunTime ?? this.lastRunTime,
      lastRunStatus: lastRunStatus ?? this.lastRunStatus,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastFailureReason: lastFailureReason ?? this.lastFailureReason,
    );
  }

  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }
}
