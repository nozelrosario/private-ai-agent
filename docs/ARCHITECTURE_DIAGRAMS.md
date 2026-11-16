# Architecture & Workflow Diagrams

This document contains visual diagrams mapping out the key processes, architecture, and data flows within PrivateAgent.

---

## 1. High-Level System Architecture

```mermaid
graph TB
    subgraph Client_Inputs [User Input Channels]
        Voice[Voice Recognition STT]
        ChatUI[Flutter Chat Interface]
        Telegram[Telegram Bot Polling]
    end

    subgraph Flutter_Framework [Flutter App Core - lib/]
        HomeScreen[HomeScreen / Mode Switcher]
        ActionHandler[ActionHandler]
        TaskExecutor[TaskExecutor Engine]
        SkillMemory[SkillMemoryService]
        Recovery[RecoveryEngine]
        AiService[AiService]
    end

    subgraph Native_Android [Android Native Layer - android/]
        Bridge[MainActivity MethodChannel Bridge]
        AccessService[AgentAccessibilityService.kt]
        ShizukuService[Shizuku / ADB API]
        SystemIntents[Android System Intents: Dialer, SMS, Alarms, Apps]
    end

    subgraph Cloud_AI [AI Model Providers]
        DeepSeek[DeepSeek API]
        Nvidia[NVIDIA NIM Catalog]
        Groq[Groq / Llama 3.3]
        LocalLLM[Ollama / Local LM Studio]
    end

    Client_Inputs --> HomeScreen
    HomeScreen --> ActionHandler
    ActionHandler --> TaskExecutor
    TaskExecutor <--> SkillMemory
    TaskExecutor <--> Recovery
    TaskExecutor <--> AiService
    AiService <--> Cloud_AI

    TaskExecutor --> Bridge
    ActionHandler --> SystemIntents
    Bridge <--> AccessService
    TaskExecutor <--> ShizukuService
    AccessService --> AndroidOS[Android OS UI & Target Applications]
```

---

## 2. Autonomous Perception-Cognition-Action Feedback Loop

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Flutter (TaskExecutor)
    participant Nat as AgentAccessibilityService
    participant LLM as AI Provider (DeepSeek / NVIDIA)
    participant Screen as Android Device UI

    User->>App: "Open Settings and turn on WiFi"
    App->>App: Check Skill Memory (Jaccard Similarity)
    alt Memory Match Found (Reliable Skill)
        App->>Nat: Replay recorded ActionSteps
        Nat->>Screen: Dispatch gestures / clicks
    else Autonomous LLM Reasoning
        loop Until is_complete == true (up to Max Steps)
            App->>Nat: dumpScreen()
            Nat->>Screen: Traverse AccessibilityNodeInfo Hierarchy
            Screen-->>Nat: Raw Node Tree (Bounds, Text, Types)
            Nat-->>App: Filtered Node Map with Screen Coordinates
            App->>App: Compress screen & tag interactive elements
            App->>LLM: Send Screen Dump + Task Context
            LLM-->>App: JSON {"action": "click_text", "params": {"text": "Network & internet"}}
            App->>App: Loop & Duplicate Detection
            alt Action Execution
                App->>Nat: clickByText() or clickAt(x, y)
                Nat->>Screen: Dispatch Accessibility Action / GestureDescription
            else Action Failure
                App->>App: RecoveryEngine.diagnose() (Scroll / Dismiss Keyboard / Wait)
            end
            App->>App: Adaptive Delay (1.0s - 3.0s)
        end
        App->>App: Save ActionSteps to SkillMemoryService
        App->>User: Notify "Task Completed"
    end
```

---

## 3. Telegram Remote Control Architecture

```mermaid
flowchart TD
    subgraph Telegram_Cloud [Telegram Cloud]
        UserTG([User on Telegram App])
        TGApi[Telegram Bot API: getUpdates / sendMessage]
    end

    subgraph Device_Background [PrivateAgent Device Process]
        Poller[TelegramService: Long-Polling Loop]
        MsgParser[Action Parser]
        Exec[TaskExecutor / ActionHandler]
        Feedback[Send Progress Updates]
    end

    UserTG -->|Sends message| TGApi
    TGApi -->|Poll HTTP response| Poller
    Poller -->|Raw Text| MsgParser
    MsgParser -->|Structured Command| Exec
    Exec -->|Live status update| Feedback
    Feedback -->|POST /sendMessage| TGApi
    TGApi -->|Push message| UserTG
    Exec -->|Final Result| Feedback
```

---

## 4. Autonomous Routine Background Execution & Screen Lifecycle

```mermaid
sequenceDiagram
    autonumber
    participant AM as Android AlarmManager
    participant MWR as MacroWakeReceiver
    participant MFS as MacroForegroundService
    participant AAS as AgentAccessibilityService
    participant TE as TaskExecutor
    participant RLS as RoutineLedgerService
    participant LLM as LLM Provider
    participant App as Target App (e.g. WhatsApp)

    AM->>MWR: Trigger Exact Alarm (Routine Schedule)
    MWR->>AAS: isUserActivelyInteracting(30s)?
    alt User is touching screen
        MWR->>AM: Postpone by 5 minutes
        MWR-->>MWR: Exit (Do not interrupt user)
    else Screen is idle or locked
        MWR->>MWR: Acquire WakeLock
        MWR->>MFS: Start Foreground Service + Ongoing Notification
        MWR->>TE: executeAutonomousRoutine(routine)
        
        opt Screen was locked
            TE->>AAS: Wake display & Replay unlockSkill
            TE->>AAS: Verify Keyguard is unlocked
        end

        loop Action Loop (bounded by maxSteps & timeout)
            TE->>AAS: dumpScreen()
            AAS-->>TE: Accessibility Tree & Coordinates
            
            opt Step > 0
                TE->>LLM: Evaluate Screen against SuccessCriteria
                LLM-->>TE: criteria_met?
                opt Criteria Met
                    TE-->>TE: Break loop (Success)
                end
            end

            TE->>RLS: Fetch recent processed message hashes
            RLS-->>TE: Deduplication Context
            TE->>LLM: Decide next action (click/type/scroll)
            LLM-->>TE: Action JSON (e.g. type_text)

            opt Supervised Mode
                TE->>MWR: Request user confirmation (Notification / Telegram)
                MWR-->>TE: Approved
            end

            TE->>AAS: Dispatch action
            AAS->>App: Inject gesture / text
            
            opt Sent outgoing message
                TE->>RLS: Record entry (sender, snippet hash, reply)
            end
        end

        opt Screen was locked initially
            TE->>AAS: pressHome()
            TE->>AAS: lockScreen() (Restore Security)
        end

        TE->>MFS: Stop Foreground Service
        TE->>MWR: Release WakeLock
        TE->>AM: Schedule next recurring run
    end
```

---

## 5. CI/CD Release Automation Pipeline

```mermaid
flowchart LR
    Dev([Developer]) -->|Push Git Tag v1.0.3| GH[GitHub Repository]
    
    subgraph GitHub_Actions [GitHub Actions Runner: ubuntu-latest]
        Checkout[Checkout Code]
        SetupEnv[Setup Java 17 + Flutter Stable]
        Tests[Run flutter test]
        BuildUniversal[Build Universal APK]
        BuildSplits[Build Split ABI APKs: arm64, armeabi, x86_64]
        Checksums[Generate SHA256SUMS.txt]
        PublishRelease[softprops/action-gh-release@v2]
    end

    GH --> Checkout
    Checkout --> SetupEnv
    SetupEnv --> Tests
    Tests --> BuildUniversal
    BuildUniversal --> BuildSplits
    BuildSplits --> Checksums
    Checksums --> PublishRelease

    subgraph GitHub_Releases [Public Release Page]
        ReleaseAsset[Release v1.0.3 with APKs & SHA256]
    end

    PublishRelease --> ReleaseAsset
```
