# GitHub Actions CI/CD & Dual-Channel Release Guide

> **Repository:** `nozelrosario/private-ai-agent`  
> **Workflow File:** [android-release.yml](file:///sdcard/Projects/nozelrosario/private-ai-agent/.github/workflows/android-release.yml)

---

## 1. Dual-Channel Release Pipeline (Beta & Stable)

PrivateAgent employs a dual-channel release pipeline using Android product flavors (`stable` vs `beta`), allowing side-by-side coexistence on the same device and safe testing of work-in-progress features without disrupting production users.

| Channel | Trigger Branch / Condition | Flavor | Package ID (`applicationId`) | App Label | GitHub Distribution Target |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Stable** | `main` branch (push tag `v*` or manual run) | `stable` | `com.orailnoor.privateagent` | `PrivateAgent` | Official GitHub Release (Latest) + Actions Artifact |
| **Beta** | `develop` branch (push) or manual run on any branch | `beta` | `com.orailnoor.privateagent.beta` | `PrivateAgent Beta` | GitHub **Pre-release** (`v*-beta.*`) + Actions Artifact |

---

## 2. Triggering Builds

### Automatic Triggers:
1. **Stable Production Release:**
   - Tag commit on `main` and push: `git tag v1.0.X && git push origin v1.0.X`.
   - The CI builds the `stable` flavor and attaches APKs to an official public release.
2. **Beta Pre-release:**
   - Push to `develop`: `git push origin develop`.
   - The CI builds the `beta` flavor with diagonal "BETA" launcher icons, in-app "BETA" badge, and uploads to GitHub Pre-releases + workflow artifacts.

### Manual Triggers (`workflow_dispatch`):
You can trigger a build from **any branch** (including feature branches):
1. Navigate to the **Actions** tab on GitHub &rarr; select **Android Release & Beta Pipeline**.
2. Click **Run workflow**.
3. Select your desired branch (e.g., `develop`, `feature/xyz`, or `main`).
4. Select the **Release Channel** dropdown (`beta` or `stable`).
5. Choose whether to publish as a GitHub Pre-release (default: `true`).
6. Click **Run workflow**.

---

## 3. Side-by-Side Android Coexistence

Because the `beta` flavor uses `applicationIdSuffix = ".beta"`:
- Both apps can be installed on the same phone simultaneously without overwriting each other.
- The Beta version has a dedicated diagonal "BETA" banner across launcher icons (`android/app/src/beta/res/mipmap-*`).
- Shizuku provider authority automatically isolates to `com.orailnoor.privateagent.beta.shizuku`.
- Accessibility service label is isolated to `PrivateAgent Beta Screen Control`.

---

## 4. Forked Repository GitHub Configuration

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

## 5. APK Signing & In-Place Upgrades

### Persistent Release Keystore Signing (Current Setup)
In `android/app/build.gradle.kts`, release builds resolve signing credentials in the following order:
1. **CI environment variables**: `KEYSTORE_PATH`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD` (decoded from GitHub Actions secrets in `.github/workflows/android-release.yml`).
2. **Local developer keystore**: `android/key.properties` (gitignored alongside `**/*.jks` / `**/*.keystore` via `android/.gitignore`).
3. **Local-only debug fallback**: Outside CI (`CI != "true"`), if neither environment variables nor `android/key.properties` exist, release builds fall back to `signingConfigs.getByName("debug")` so local `flutter run --release` continues to work. In CI (`CI == "true"`), missing signing credentials fail the build immediately.

> [!IMPORTANT]
> GitHub Actions `ubuntu-latest` runners are ephemeral and do not preserve `~/.android/debug.keystore`. Signing release APKs with `debug` keys in CI generates a brand-new random certificate on every run, causing Android to reject updates with *"App not installed as package conflicts with an existing package"* (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

### Configuring Repository Secrets for Forks / New Environments
1. Generate a persistent Android release keystore (keep an encrypted offline backup; losing it prevents future in-place upgrades):
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
4. Optional local signing: place `release.jks` under `android/` and create `android/key.properties`:
   ```properties
   storePassword=<KEYSTORE_PASSWORD>
   keyPassword=<KEY_PASSWORD>
   keyAlias=privateagent
   storeFile=release.jks
   ```

### Upgrade Notes for End Users
- **Migrating from legacy debug-signed builds:** Any installation built before persistent release signing was enabled must be uninstalled **once** before installing the newly signed APK. All subsequent updates within the same channel (`stable` or `beta`) will install and overwrite in-place.
- **Keep the same APK variant when updating:** Flutter `--split-per-abi` adds ABI offsets (`+1000` for `armeabi-v7a`, `+2000` for `arm64-v8a`, `+3000` for `x86_64`), whereas `universal` APKs use the un-offset `versionCode`. Updating from a split-ABI APK (e.g., `arm64-v8a`) to a `universal` APK can trigger a `versionCode` downgrade error; stick to the same variant (`universal` -> `universal` or `arm64-v8a` -> `arm64-v8a`).
