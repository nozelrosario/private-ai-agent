# PrivateAgent Knowledge Base

Welcome to the **PrivateAgent** Knowledge Base. This documentation serves as the single source of truth for the project's architecture, codebase structure, automation engine, and deployment workflows.

---

## 📚 Knowledge Base Index

1. **[Master Architecture & Codebase Guide](file:///sdcard/Projects/nozelrosario/private-ai-agent/docs/KNOWLEDGE_BASE.md)**
   - System Overview & Core Philosophy
   - Complete File-by-File Inventory (`lib/`, `android/`, `local_plugins/`)
   - Core Subsystems (Accessibility, LLM Action Grammar, Skill Memory, Recovery Engine)
   - Storage Locations & File Formats
2. **[CI/CD & APK Release Guide](file:///sdcard/Projects/nozelrosario/private-ai-agent/docs/CI_CD_RELEASE_GUIDE.md)**
   - GitHub Workflow Analysis (`.github/workflows/android-release.yml`)
   - Why GitHub Releases are currently missing & how to fix it
   - Fork Configuration Guide for `nozelrosario/private-ai-agent`
   - Release creation process (`git tag` & `workflow_dispatch`)
   - APK signing details (Debug vs Custom Keystore)
3. **[Architecture & Workflow Diagrams](file:///sdcard/Projects/nozelrosario/private-ai-agent/docs/ARCHITECTURE_DIAGRAMS.md)**
   - High-Level Architecture Diagram
   - Perception-Cognition-Action Feedback Loop
   - Telegram Remote Access Workflow
   - CI/CD Build and Release Pipeline Diagram

---

## ⚡ Quick Architecture Overview

```
                                  ┌───────────────────────────┐
                                  │      User Command         │
                                  │ (Chat / Voice / Telegram) │
                                  └─────────────┬─────────────┘
                                                │
                                                ▼
┌───────────────────────────┐      ┌───────────────────────────┐
│       Skill Memory        │◄────►│       TaskExecutor        │
│   (Jaccard Fast-Replay)   │      │ (Adaptive Feedback Loop)  │
└───────────────────────────┘      └─────────────┬─────────────┘
                                                │
                     ┌──────────────────────────┴──────────────────────────┐
                     ▼                                                     ▼
        ┌─────────────────────────┐                           ┌─────────────────────────┐
        │ Screen Perception Layer │                           │       LLM Reasoner      │
        │ - AccessibilityNodeTree │                           │ - OpenAI / DeepSeek     │
        │ - Bounds & Coordinates  │                           │ - NVIDIA NIM / GLM-5.2  │
        │ - Screen Compressor     │                           │ - Local Ollama          │
        └────────────┬────────────┘                           └────────────┬────────────┘
                     │                                                     │
                     └──────────────────────────┬──────────────────────────┘
                                                ▼
                                  ┌───────────────────────────┐
                                  │     Execution Engine      │
                                  │ - Accessibility Gestures  │
                                  │ - RecoveryEngine Diagnoser│
                                  │ - Shizuku ADB Shell       │
                                  └───────────────────────────┘
```

---

## 🛠 Project Structure at a Glance

```
private-ai-agent/
├── .github/workflows/
│   └── android-release.yml      # GitHub Actions CI build & release workflow
├── android/
│   ├── app/src/main/
│   │   ├── AndroidManifest.xml  # Android permissions & service declarations
│   │   ├── kotlin/.../
│   │   │   ├── AgentAccessibilityService.kt  # Native UI tree parser & gesture dispatcher
│   │   │   └── MainActivity.kt               # Flutter engine channel registry
│   │   └── res/xml/
│   │       └── accessibility_service_config.xml
│   └── app/build.gradle.kts     # Android build configuration (Java 17, minSdk 26)
├── docs/
│   ├── KNOWLEDGE_BASE.md        # Deep-dive architecture and file documentation
│   ├── CI_CD_RELEASE_GUIDE.md   # GitHub Actions release setup for forked repo
│   └── ARCHITECTURE_DIAGRAMS.md # Mermaid architecture & flow diagrams
├── lib/
│   ├── main.dart                # Application entrypoint & theme management
│   ├── overlay_main.dart        # Floating background overlay window isolate
│   ├── config/
│   │   └── feature_flags.dart   # Feature toggles (floating overlay switch)
│   ├── models/                  # Data classes (AgentAction, ChatMessage, SavedSkill)
│   ├── screens/                 # UI screens (Home, Onboarding, Settings, History)
│   ├── services/                # Automation, AI, Voice, Telegram, Shizuku, Logging
│   └── widgets/                 # Reusable UI components (MessageBubble)
├── local_plugins/               # Vendored plugins (flutter_overlay_window)
└── pubspec.yaml                 # Dependencies and asset declarations
```

---

## 🚀 Quick Release Cheatsheet

To generate a new release APK once your fork's CI/CD is configured:
```bash
# 1. Update version in pubspec.yaml (e.g. 1.0.3+2022)
git commit -am "chore: bump version to v1.0.3"
git push origin main

# 2. Push release tag
git tag v1.0.3
git push origin v1.0.3
```
*Artifacts (`app-universal-release.apk`, split ABIs, and SHA256 checksums) will be automatically compiled and attached to your GitHub Releases page.*
