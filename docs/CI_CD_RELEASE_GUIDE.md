# GitHub Actions CI/CD & APK Release Guide

> **Repository:** `nozelrosario/private-ai-agent`  
> **Workflow File:** [android-release.yml](file:///sdcard/Projects/nozelrosario/private-ai-agent/.github/workflows/android-release.yml)

---

## 1. Current State of the GitHub Workflow

The workflow file `.github/workflows/android-release.yml` is configured to build Android APK packages automatically.

### Trigger Conditions
- **Manual Trigger (`workflow_dispatch`)**: Can be manually triggered from the GitHub repository **Actions** tab.
- **Git Tag Push (`push: tags: - "v*"`)**: Automatically triggers when any tag starting with `v` (e.g., `v1.0.3`, `v2.0.0`) is pushed to GitHub.

### Build Pipeline Steps
1. Checks out repository source code (`actions/checkout@v4`).
2. Configures Java 17 Temurin distribution (`actions/setup-java@v4`).
3. Sets up Flutter stable channel with caching (`subosito/flutter-action@v2`).
4. Runs `flutter pub get` and executes unit tests (`flutter test`).
5. Compiles:
   - **Universal Release APK**: `flutter build apk --release` &rarr; `dist/app-universal-release.apk`
   - **Architecture-Specific Split APKs**: `flutter build apk --release --split-per-abi`
     - `dist/app-arm64-v8a-release.apk` (modern 64-bit ARM smartphones)
     - `dist/app-armeabi-v7a-release.apk` (older 32-bit ARM devices)
     - `dist/app-x86_64-release.apk` (Android emulators and x86 devices)
6. Computes cryptographic checksums: `sha256sum *.apk > SHA256SUMS.txt`.
7. Uploads the build folder as a GitHub Actions workflow artifact named `private-agent-android`.

---

## 2. Why GitHub Releases Are NOT Automatically Created Right Now

In commit `ce84a4710ffecea0ab1b3d9a1c16ae5d7794b199` (*"ci: keep release uploads manually signed"*), the original upstream author made two breaking changes:
1. Changed `permissions: contents: write` down to `permissions: contents: read`.
2. **Removed** the GitHub Release publication step:
   ```yaml
   - name: Attach APKs to GitHub release
     if: startsWith(github.ref, 'refs/tags/')
     uses: softprops/action-gh-release@v2
     with:
       files: dist/*
   ```

### Consequences
- Pushing a new version tag (e.g., `v1.0.3`) builds the APKs on GitHub's Ubuntu runners, but **no GitHub Release is created** on the Releases page.
- The compiled APKs are stored only as temporary workflow run artifacts, which:
  - Expire after 90 days.
  - Require the user to be logged in to GitHub and download a `.zip` file containing the APKs.

---

## 3. Step-by-Step Setup for Your Forked Repository

Because this repository was forked to `git@github.com:nozelrosario/private-ai-agent.git`, follow these steps to configure automated releases:

### Step 1: Enable GitHub Actions on your Fork
By default, GitHub disables Actions on newly forked repositories for security:
1. Go to your repository on GitHub: `https://github.com/nozelrosario/private-ai-agent`.
2. Click the **Actions** tab.
3. Click the green button: **"I understand my workflows, go ahead and enable them"**.

### Step 2: Grant Workflow Write Permissions in Repository Settings
To allow the workflow to create releases and publish APK files:
1. Go to **Settings** &rarr; **Actions** &rarr; **General**.
2. Scroll down to **Workflow permissions**.
3. Select **Read and write permissions**.
4. Check **"Allow GitHub Actions to create and approve pull requests"** (optional but recommended).
5. Click **Save**.

### Step 3: Update `.github/workflows/android-release.yml`
Update the workflow to restore `permissions: contents: write` and add the `action-gh-release` step.

Here is the exact recommended configuration:

```yaml
name: Android Release

on:
  workflow_dispatch:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Resolve dependencies
        run: flutter pub get

      - name: Run tests
        run: flutter test

      - name: Build universal APK
        run: |
          flutter build apk --release
          mkdir -p dist
          cp build/app/outputs/flutter-apk/app-release.apk dist/app-universal-release.apk

      - name: Build architecture-specific APKs
        run: |
          flutter build apk --release --split-per-abi
          cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk dist/
          cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk dist/
          cp build/app/outputs/flutter-apk/app-x86_64-release.apk dist/
          cd dist
          sha256sum *.apk > SHA256SUMS.txt

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: private-agent-android
          path: dist/*

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v2
        with:
          files: dist/*
          generate_release_notes: true
          draft: false
          prerelease: false
```

---

## 4. How to Generate and Publish a New Release

### Procedure to Release a New Version:
1. **Update the App Version**:
   In `pubspec.yaml`, increment the version (e.g. from `1.0.2+2021` to `1.0.3+2022`).
2. **Commit and Push Changes**:
   ```bash
   git add pubspec.yaml
   git commit -m "chore: bump version to v1.0.3"
   git push origin main
   ```
3. **Create and Push a Git Tag**:
   ```bash
   git tag v1.0.3
   git push origin v1.0.3
   ```
4. **Monitor the Build**:
   - Go to `https://github.com/nozelrosario/private-ai-agent/actions`.
   - Watch the **Android Release** workflow run.
5. **View Published Release**:
   - Once complete (typically ~4-6 minutes), visit `https://github.com/nozelrosario/private-ai-agent/releases`.
   - The release `v1.0.3` will be live with:
     - `app-universal-release.apk`
     - `app-arm64-v8a-release.apk`
     - `app-armeabi-v7a-release.apk`
     - `app-x86_64-release.apk`
     - `SHA256SUMS.txt`
     - Automatically generated release changelog.

---

## 5. APK Signing Considerations

### Default Sideload Signing (Current Setup)
In `android/app/build.gradle.kts`:
```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
    }
}
```
- **How it works**: The release build uses the standard Android debug keystore.
- **Benefits**: Builds out-of-the-box on GitHub Actions with zero keystores or secret configuration required. Anyone can download and install the APK via Android sideloading.
- **Drawbacks**: If users update from an APK built on a different machine or keystore, Android will show an "App not installed as package conflicts with an existing package" signature mismatch error.

### (Optional) Official Custom Keystore Signing
If you wish to sign your APKs with a permanent private keystore:
1. Generate an Android release keystore:
   ```bash
   keytool -genkey -v -keystore release.jks -alias privateagent -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Base64 encode the keystore:
   ```bash
   base64 -w 0 release.jks > keystore_base64.txt
   ```
3. Add the following repository secrets under **GitHub Repository &rarr; Settings &rarr; Secrets and variables &rarr; Actions**:
   - `KEYSTORE_BASE64`: contents of `keystore_base64.txt`
   - `KEYSTORE_PASSWORD`: keystore password
   - `KEY_ALIAS`: `privateagent`
   - `KEY_PASSWORD`: alias password
4. Update `build.gradle.kts` and the workflow to decode the keystore before running `flutter build`.
