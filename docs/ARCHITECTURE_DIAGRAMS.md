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

## 4. CI/CD Release Automation Pipeline

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
