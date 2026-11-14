# Feature Specification: Autonomous Routines & Background Scheduler (Controlled AI Loops)

**Branch:** `feature/autonomous-routines-scheduler`  
**Target:** Background AI Automation, WhatsApp Auto-Responder, Periodic Monitoring, Guarded Autonomy

---

## 1. Executive Summary

This specification defines the architecture, data models, execution loop, safety guardrails, and Android scheduling infrastructure for **Autonomous Routines (Scheduled Macros)** in PrivateAgent. 

This capability allows the agent to run periodic, multi-step goal loops unattended (e.g. checking WhatsApp for unread messages and auto-replying based on a designated Persona's instructions and tone) while enforcing strict bounds, idempotency, and remote user supervision.

---

## 2. Core Decisions & Architectural Pillars

| Component | Design Decision | Rationale |
|---|---|---|
| **Core Entity** | Dedicated `AutonomousRoutine` data model | Decouples high-level recurring goals, success conditions, and schedules from atomic `CustomSkill` SOP recipes and `AgentPersona` identities. |
| **Loop & Verification** | Dual-stage execution loop with LLM Success Evaluator + hard caps | Agent acts, then an evaluation pass inspects screen state against explicit `successCriteria`. Bounded by max 10 steps, 180s timeout, and a persistent Emergency Stop notification. |
| **Screen State & Gating** | Unattended Unlock + Active-Screen Gating | If screen is off/locked, fires `WakeLock` and executes `unlockSkillId`. If user is actively touching/using the phone, defers run by 5 minutes. Re-locks phone after completion if previously locked. |
| **De-duplication & Memory** | Hybrid: Visual Unread + Persistent Run Ledger | Targets unread badges in WhatsApp; logs every interaction (contact, snippet hash, reply, timestamp) in `RoutineLedgerService` to prevent double-replying. |
| **Execution Safety** | Configurable: Autonomous vs. Supervised | Supervised mode drafts replies and requires user approval (Android Notification / Telegram button) before sending. Autonomous mode executes directly with full audit trail. |
| **Android Scheduler** | Native `AlarmManager` (Exact + WakeLock) + Transient Foreground Service | Zero battery consumption while asleep; wakes phone at exact intervals, runs macro under a visible foreground service notification with Emergency Stop, then sleeps. |
| **Remote Control** | Telegram Bot Integration | Remotely inspect status (`/macros`), force run (`/run <name>`), stop (`/stop`), or approve drafts. |
| **UI Studio** | 3-Tab Hub in *Personas & Skills* (`skills_personas_screen.dart`) | Integrated seamlessly with Personas & Skills, featuring a Dual-Mode Visual Form & Synchronized JSON Editor (`routine_editor_screen.dart`). |

---

## 3. Data Model (`AutonomousRoutine`)

```dart
class AutonomousRoutine {
  final String id;
  final String name;
  final String description;
  final String personaId;           // Linked AgentPersona
  final String? unlockSkillId;      // Optional skill to unlock phone if locked
  final String goalPrompt;          // e.g. "Check WhatsApp unread messages..."
  final String successCriteria;     // e.g. "All unread messages replied to..."
  final RoutineExecutionMode executionMode; // autonomous | supervised
  final RoutineSchedule schedule;   // interval | daily_time
  final RoutineGuardrails guardrails; // maxSteps, timeoutSeconds, pauseOnFailures
  final bool isEnabled;
  final DateTime? lastRunTime;
  final String? lastRunStatus;
}
```

---

## 4. Run Ledger Schema (`RoutineLedgerEntry`)

To prevent infinite loops or duplicate messages:
```dart
class RoutineLedgerEntry {
  final String id;
  final String routineId;
  final DateTime timestamp;
  final String targetAppPackage;    // e.g. "com.whatsapp"
  final String senderIdentifier;    // Contact name or group title
  final String messageSnippetHash;  // Hash of incoming message text
  final String agentReply;          // Drafted/sent reply
  final String status;              // "sent", "pending_approval", "skipped"
}
```

---

## 5. End-to-End Execution Flow

```
┌──────────────────────────────────────────────┐
│ AlarmManager: Exact Alarm Fires (Interval)   │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ MacroWakeReceiver & Active Screen Check      │
│  - Is phone actively used by user?           │
│    YES ──► Postpone 5 mins & release lock    │
│    NO  ──► Acquire WakeLock                  │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Screen Lock Detection & Unlock Phase         │
│  - Is Keyguard locked?                       │
│    YES ──► Run unlockSkillId (PIN / Gesture) │
│    NO  ──► Proceed                           │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Launch MacroForegroundService                │
│  - Show ongoing notification + [STOP] button │
│  - Bind Persona context & scoped skills      │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Autonomous Loop (TaskExecutor)               │
│  1. Read screen accessibility tree           │
│  2. Decide action (Open WhatsApp, check msgs)│
│  3. Consult RoutineLedgerService (skip seen) │
│  4. Draft response in Persona voice          │
│  5. If Supervised: request approval          │
│     If Autonomous: send reply & log ledger   │
│  6. LLM Evaluator: Is successCriteria met?   │
│     NO & steps < maxSteps ──► Repeat         │
│     YES / maxSteps / timeout ──► Complete    │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Teardown & Security Restoration              │
│  - Press Home                                │
│  - If phone was originally locked, re-lock   │
│  - Release WakeLock & stop ForegroundService │
│  - Dispatch summary to Telegram / History Log│
└──────────────────────────────────────────────┘
```

---

## 6. Phased Implementation Roadmap

- [ ] **Phase 1: Models & Persistence**
  - Implement `AutonomousRoutine`, `RoutineSchedule`, `RoutineGuardrails`, `RoutineLedgerEntry`.
  - Implement `RoutineService` and `RoutineLedgerService` with JSON serialization & catalog export/import.
- [ ] **Phase 2: Android Native Background & Alarm Integration**
  - Create `MacroAlarmScheduler.kt` using `AlarmManager.setExactAndAllowWhileIdle()`.
  - Create `MacroWakeReceiver.kt` with `WakeLock` handling and user-interaction detection.
  - Create `MacroForegroundService.kt` with sticky notification and emergency cancellation intent.
  - Expose MethodChannel methods between Flutter and Android.
- [ ] **Phase 3: Execution Engine & Evaluator**
  - Extend `TaskExecutor` with routine execution support, pre-run unlock invocation, and post-run state restoration.
  - Implement LLM Success Evaluator prompt step.
  - Wire ledger deduplication logic into task execution.
- [ ] **Phase 4: Remote Telegram Integration**
  - Add `/macros`, `/run <name>`, and `/stop` commands in `TelegramService`.
  - Add supervised mode confirmation prompts with inline buttons.
- [ ] **Phase 5: User Interface & Visual Studio**
  - Add "Routines" tab in `skills_personas_screen.dart`.
  - Create `routine_editor_screen.dart` with dual-mode Visual Composer + Synchronized JSON Editor.
  - Add scheduled routine card to `home_screen.dart`.
- [ ] **Phase 6: Testing & Quality Assurance**
  - Unit tests for routine serialization, schedule calculation, and ledger hashing.
  - Verify wake-up, unlock, WhatsApp routine, and lock-restoration on test device.
