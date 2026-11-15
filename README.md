# PrivateAgent

PrivateAgent is an open-source Android automation agent built with Flutter. It utilizes the DeepSeek API and native Android Accessibility Services to interpret screen layouts and execute multi-step tasks across any installed application via natural language commands.

## Architecture

The system operates on a continuous feedback loop:
1. The user issues a command (via voice, text, or Telegram remote access).
2. The agent captures the current screen hierarchy, calculating the exact spatial coordinates of all interactive elements.
3. The layout data is transmitted to the AI provider alongside the current task context and the result of the previous action.
4. The AI determines the next optimal action (e.g., clicking specific coordinates, inputting text, scrolling).
5. The native Android layer executes the action.
6. The loop repeats until the task is marked as complete.

## Capabilities

- **Screen Reading:** Parses the Android UI tree to map clickable, scrollable, and editable elements.
- **Coordinate-Based Interaction:** Simulates physical screen taps based on coordinate geometry, mitigating issues with missing text labels or inaccessible icons.
- **Custom Skills & Macro Recipes:** Create deterministic multi-step recipes with parameter placeholders (e.g., `Type "{message}" to {recipient}`) to complete device routines in fewer LLM steps with zero token waste.
- **Agent Personas:** Scope skills to specialized personas (e.g., *Personal Assistant*, *Device Operator*, *Media Specialist*) with tailored system prompts to eliminate ambiguity.
- **Teach Mode (by Demonstration):** Interactively record on-screen taps, scrolls, and keystrokes directly on your device to create custom skills automatically.
- **Confirmation Checkpoints:** Enforce security on sensitive steps (payments, data changes, outgoing messages) requiring explicit user confirmation before proceeding.
- **Autonomous Routines & Background Scheduler:** Schedule periodic, unattended multi-step AI loops (e.g. checking WhatsApp messages and auto-replying based on persona tone) with strict safety bounds, anti-loop deduplication ledger, and native Android `AlarmManager` wakeups.
- **Remote Access & 24/7 Background Listener:** Integrates with the Telegram Bot API via a persistent background listener service, allowing users to issue commands, run routines, approve checkpoints, and monitor task execution progress remotely even when the device is locked.
- **Voice Control:** Native speech-to-text integration for hands-free operation.

## Custom Skills, Personas & Teach Mode

PrivateAgent includes modular automation tools designed to make device control faster, cheaper, and safer:

### 1. Custom Skills & Workflow Recipes
- Combine structured native actions (`tap`, `input_text`, `launch_app`, `wait`) with natural language triggers.
- Support dynamic variables and parameter extraction (e.g., `{contact}`, `{query}`).
- Provide fast, deterministic execution when standard operational procedures (SOPs) are already known.

### 2. Scoped Agent Personas
- Create and switch between specialized personas from the Home Screen chips or the **Personas & Skills** hub.
- Configure custom persona descriptions, prompt modifiers, and linked skills.
- Scoping prevents cross-domain skill confusion by exposing only relevant skills to the active agent.

### 3. Teach by Demonstration (Teach Mode)
- Tap the **Teach Skill** button to begin an interactive demonstration session.
- Perform the desired actions on your screen; PrivateAgent captures native accessibility events (`TYPE_VIEW_CLICKED`, `TYPE_VIEW_SCROLLED`) and translates them into an editable recipe draft.

### 4. Selective Confirmation Checkpoints
- Flag critical or irreversible actions with `requiresConfirmation: true`.
- The automation engine pauses before executing sensitive actions and prompts for explicit user approval.

### 5. Dual-Mode Visual Studio & JSON Editor
- **Interactive Visual Composer:** Effortlessly assemble multi-step automation recipes with visual action cards (App Launcher, UI Element Tap, Coordinate Tap, Text Input, Wait/Delay, Scroll Direction, Key Press) and dynamic parameter variable chips.
- **Bi-directional JSON Synchronization:** Switch tabs in real-time between visual forms and formatted JSON code. Power users can inspect, edit, or paste complete recipes and agent personas directly.
- **In-Settings Management & Backup:** Select active personas, launch creation studios, and perform full JSON catalog backups/imports directly from the Settings screen.

### 6. Autonomous Routines & Background Scheduler (Controlled AI Loops)
- **Periodic Automation Loops:** Schedule autonomous multi-step goals (e.g., checking WhatsApp for unread messages, reading context, and drafting/sending auto-replies).
- **Dual-Stage Success Evaluator:** Actions iterate until a dedicated LLM evaluation auditor verifies that the screen state fulfills the routine's explicit `successCriteria`.
- **Anti-Looping Run Ledger:** Employs deterministic FNV-1a hashing and local ledger tracking to prevent duplicate auto-replies across periodic cycles.
- **Active-User Touch Gating:** Automatically detects if the user is actively using the device and defers routine execution by 5 minutes rather than stealing focus.
- **Unattended Lock Lifecycle:** Wakes locked screens, executes pre-execution unlock skills, and automatically re-locks the device upon completion if it was locked initially.
- **Persistent Background Listener & Android Alarms:** Runs a persistent low-power `START_STICKY` Foreground Service and `AlarmManager.setExactAndAllowWhileIdle()` so Telegram commands and scheduled routines trigger reliably 24/7 without being suspended by Android Doze. Auto-restarts on device reboot via `BootReceiver` and supports one-tap Battery Optimization exemption in Settings.
- **Supervised vs Autonomous Modes:** Choose between full auto-reply or supervised approval checkpoints requiring explicit confirmation before outgoing messages are sent.
- **Telegram Routine Activity Notifications:** Automatically dispatches alerts to your Telegram chat when scheduled routines are triggered, postponed, or finished with execution outcomes.
- **Rich Intent & Reasoning Execution History:** Tapping any task in History displays interactive timeline cards with the LLM's intent, reasoning, action parameters, and evaluator verdicts, plus a 1-tap "Copy Trace" export for prompt tweaking.
- **Direct Storage Import & Export:** Export and import skills, personas, and routines directly as `.json` files to/from device storage, SD card, or Downloads using native Android SAF and MediaStore APIs.

## Installation

Download the latest APK directly from the [Releases Page](https://github.com/nozelrosario/private-ai-agent/releases).

Choose `app-universal-release.apk` when it is available. It supports ARM64,
32-bit ARM, and x86_64 devices in one package. If a release only provides split
APKs, most modern Android phones—including Snapdragon devices—must use
`app-arm64-v8a-release.apk`.

PrivateAgent supports Android 8.0 (API 26) and newer. Current release builds are
also checked for Android 15/16's 16 KB native-library alignment requirement.

## Knowledge Base & Documentation

For comprehensive technical documentation, architectural diagrams, file breakdown, and release setup guides:
- [Master Technical Knowledge Base](file:///sdcard/Projects/nozelrosario/private-ai-agent/KNOWLEDGE_BASE.md)
- [Architecture & Workflow Diagrams](file:///sdcard/Projects/nozelrosario/private-ai-agent/docs/ARCHITECTURE_DIAGRAMS.md)
- [CI/CD & APK Release Guide](file:///sdcard/Projects/nozelrosario/private-ai-agent/docs/CI_CD_RELEASE_GUIDE.md)

## Setup Instructions (How to use for FREE)

This app requires an AI brain to operate. You can use it **100% for free** by using OpenRouter's free models.

1. Install the APK on your Android device (API 30+ recommended).
2. Go to [OpenRouter.ai](https://openrouter.ai/) and create a free account.
3. Generate a free API Key.
4. Launch PrivateAgent and go to the **Settings** screen.
5. Tap the **"OpenRouter"** quick-select chip under Base URL.
6. Paste your API Key.
7. Type `openai/gpt-oss-120b:free` (or any other free model) into the Model field.
8. Enable the **"PrivateAgent Screen Control"** service in your Android Accessibility Settings.

### “Restricted setting” when enabling Screen Control

Android may block accessibility access for apps installed from an APK. This is
an operating-system safety restriction:

1. Open **Settings → Apps → PrivateAgent**.
2. Open the three-dot menu in the top-right corner.
3. Tap **Allow restricted settings** and confirm.
4. Return to PrivateAgent and open **Accessibility Settings** again.
5. Enable **PrivateAgent Screen Control**.

PrivateAgent now shows these instructions and provides shortcuts to both App
Info and Accessibility Settings during onboarding.

## Telegram Integration

To enable remote access:
1. Acquire a bot token from BotFather on Telegram.
2. Input the token in the PrivateAgent Settings screen and enable the integration toggle.
3. The application will maintain a persistent background listener service connected to the Telegram API to receive commands even when the device is locked.
4. (Optional but recommended) In **Settings > 24/7 Background Service & Power**, tap **Exempt** to grant Battery Optimization exemption, ensuring Android Doze does not throttle network or Dart timers while sleeping.

### Supported Remote Commands:
- Natural language instructions (e.g., `"Open Spotify and play my playlist"`, `"Send SMS to John saying I'm on my way"`).
- `/macros` or `/routines`: List all configured autonomous routines, schedules, and last execution statuses.
- `/run <name>`: Force run an autonomous routine immediately.
- `/stop`: Emergency stop for any running routine or task.
- Interactive Checkpoints: Reply `YES` to approve or `NO` to reject outgoing messages when routines run in Supervised mode.

## License

This project is open-source and available for modification.
