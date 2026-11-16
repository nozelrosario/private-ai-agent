import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/models/autonomous_routine.dart';
import 'package:private_agent/models/routine_ledger_entry.dart';
import 'package:private_agent/services/routine_scheduler_service.dart';

void main() {
  group('AutonomousRoutine & Schedule Models', () {
    test('Serializes and deserializes AutonomousRoutine with schedule and guardrails', () {
      const routine = AutonomousRoutine(
        id: 'whatsapp_test_1',
        name: 'WhatsApp Auto-Responder',
        description: 'Auto-reply to unread WhatsApp messages',
        personaId: 'personal_assistant',
        unlockSkillId: 'skill_unlock_phone',
        goalPrompt: 'Check unread messages and reply politely.',
        successCriteria: 'All unread messages replied to and returned to chat list.',
        executionMode: RoutineExecutionMode.supervised,
        schedule: RoutineSchedule(
          type: ScheduleType.interval,
          intervalMinutes: 15,
          activeHourStart: 9,
          activeHourEnd: 21,
          isEnabled: true,
        ),
        guardrails: RoutineGuardrails(
          maxStepsPerRun: 12,
          maxDurationSeconds: 240,
          pauseOnConsecutiveFailures: 4,
        ),
        isEnabled: true,
      );

      final jsonMap = routine.toJson();
      final roundtrip = AutonomousRoutine.fromJson(jsonMap);

      expect(roundtrip.id, 'whatsapp_test_1');
      expect(roundtrip.name, 'WhatsApp Auto-Responder');
      expect(roundtrip.personaId, 'personal_assistant');
      expect(roundtrip.unlockSkillId, 'skill_unlock_phone');
      expect(roundtrip.executionMode, RoutineExecutionMode.supervised);
      expect(roundtrip.schedule.intervalMinutes, 15);
      expect(roundtrip.schedule.activeHourStart, 9);
      expect(roundtrip.schedule.activeHourEnd, 21);
      expect(roundtrip.guardrails.maxStepsPerRun, 12);
      expect(roundtrip.guardrails.maxDurationSeconds, 240);
      expect(roundtrip.guardrails.pauseOnConsecutiveFailures, 4);
      expect(roundtrip.isEnabled, isTrue);
    });

    test('RoutineSchedule.isWithinActiveWindow correctly evaluates time boundaries', () {
      const schedule = RoutineSchedule(
        activeHourStart: 9,
        activeHourEnd: 18,
      );

      final inside = DateTime(2026, 11, 15, 14, 30); // 2:30 PM
      final before = DateTime(2026, 11, 15, 8, 45); // 8:45 AM
      final after = DateTime(2026, 11, 15, 19, 0); // 7:00 PM

      expect(schedule.isWithinActiveWindow(inside), isTrue);
      expect(schedule.isWithinActiveWindow(before), isFalse);
      expect(schedule.isWithinActiveWindow(after), isFalse);
    });

    test('calculateNextTriggerDelaySeconds returns interval seconds when within window', () {
      const schedule = RoutineSchedule(
        type: ScheduleType.interval,
        intervalMinutes: 20,
        activeHourStart: 8,
        activeHourEnd: 20,
      );

      final now = DateTime(2026, 11, 15, 10, 0); // 10:00 AM (inside)
      final delay = RoutineSchedulerService.calculateNextTriggerDelaySeconds(schedule, now);

      expect(delay, 20 * 60); // 1200 seconds
    });

    test('calculateNextTriggerDelaySeconds calculates time until active window start when outside', () {
      const schedule = RoutineSchedule(
        type: ScheduleType.interval,
        intervalMinutes: 20,
        activeHourStart: 9,
        activeHourEnd: 18,
      );

      final now = DateTime(2026, 11, 15, 7, 0); // 7:00 AM (2 hours before 9:00 AM)
      final delay = RoutineSchedulerService.calculateNextTriggerDelaySeconds(schedule, now);

      expect(delay, 2 * 3600); // 7200 seconds
    });

    test('calculateNextTriggerDelaySeconds calculates daily specific time', () {
      const schedule = RoutineSchedule(
        type: ScheduleType.dailyTime,
        dailyHour: 15,
        dailyMinute: 30,
      );

      final now = DateTime(2026, 11, 15, 14, 30); // 1 hour before 15:30
      final delay = RoutineSchedulerService.calculateNextTriggerDelaySeconds(schedule, now);

      expect(delay, 3600);
    });
  });

  group('RoutineLedgerEntry & Anti-looping Hashing', () {
    test('computeHash produces identical deterministic hashes ignoring case/whitespace', () {
      final hash1 = RoutineLedgerEntry.computeHash('Alice', 'Hello, are you available?');
      final hash2 = RoutineLedgerEntry.computeHash(' alice ', '  hello, are you available?  ');
      final hashDifferent = RoutineLedgerEntry.computeHash('Bob', 'Hello, are you available?');

      expect(hash1, hash2);
      expect(hash1, isNot(hashDifferent));
    });

    test('Serializes and deserializes RoutineLedgerEntry', () {
      final entry = RoutineLedgerEntry(
        id: 'entry_1',
        routineId: 'whatsapp_auto_responder',
        timestamp: DateTime(2026, 11, 15, 10, 30),
        targetAppPackage: 'com.whatsapp',
        senderIdentifier: 'Alice Smith',
        messageSnippet: 'Meeting at 3 PM?',
        agentReply: 'Yes, that works perfectly for me!',
        status: 'sent',
      );

      final jsonMap = entry.toJson();
      final roundtrip = RoutineLedgerEntry.fromJson(jsonMap);

      expect(roundtrip.id, 'entry_1');
      expect(roundtrip.routineId, 'whatsapp_auto_responder');
      expect(roundtrip.targetAppPackage, 'com.whatsapp');
      expect(roundtrip.senderIdentifier, 'Alice Smith');
      expect(roundtrip.messageSnippet, 'Meeting at 3 PM?');
      expect(roundtrip.agentReply, 'Yes, that works perfectly for me!');
      expect(roundtrip.status, 'sent');
      expect(roundtrip.messageSnippetHash, entry.messageSnippetHash);
    });
  });

  group('Task Execution History Trace & Observability', () {
    test('Structured trace items serialize and preserve reasoning, action, params, and result', () {
      final trace = [
        {
          'info': 'Starting routine "WhatsApp Check"',
          'timestamp': '2026-11-15T12:00:00.000Z',
        },
        {
          'step': 1,
          'action': 'open_app',
          'params': {'app_name': 'WhatsApp'},
          'reasoning': 'Opening WhatsApp to check for incoming messages',
          'result': 'Open app "WhatsApp" succeeded',
          'status': 'success',
          'timestamp': '2026-11-15T12:00:03.000Z',
        },
        {
          'step': 2,
          'action': 'click_text',
          'params': {'text': 'Alice'},
          'reasoning': 'Tapping chat with Alice to read unread message',
          'result': 'Click "Alice" succeeded',
          'status': 'success',
          'timestamp': '2026-11-15T12:00:05.000Z',
        },
      ];

      final encoded = jsonEncode(trace);
      final decoded = jsonDecode(encoded) as List<dynamic>;

      expect(decoded.length, 3);
      final step2 = decoded[2] as Map<String, dynamic>;
      expect(step2['step'], 2);
      expect(step2['action'], 'click_text');
      expect(step2['reasoning'], 'Tapping chat with Alice to read unread message');
      expect(step2['status'], 'success');
    });
  });
}
