# Flutter SwiftPM Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Flutter Swift Package Manager (SwiftPM) support for the iOS and macOS targets of `apps/client/`, in hybrid mode where CocoaPods remains as a fallback for plugins lacking `Package.swift`.

**Architecture:** This migration is tooling-driven, not code-driven. We make small manual edits (Podfile cleanup, melos setup script, CLAUDE.md note), then enable Flutter's SwiftPM flag, then let Flutter's build pipeline rewrite `project.pbxproj` and shrink `Podfile.lock` automatically. The Dart and Flutter source code in `apps/client/lib/` is never touched. Verification is build-and-launch based: each task ends with a concrete command and exact expected behavior.

**Tech Stack:** Flutter 3.41 (with SwiftPM support), Xcode (project file editing is auto-generated), CocoaPods (retained as fallback), Melos (workspace orchestration).

**Spec:** [docs/superpowers/specs/2026-05-01-swiftpm-migration-design.md](../specs/2026-05-01-swiftpm-migration-design.md)

---

## Pre-flight: capture baseline

Before any change, prove the current state builds and runs cleanly. If it doesn't, the migration must not start — we'd be chasing a problem that already exists.

### Task 0: Pre-flight baseline

**Files:**

- No edits. Reads only.

- [ ] **Step 1: Confirm Flutter SwiftPM flag is currently disabled**

Run:

```bash
flutter config | grep -i swift-package-manager
```

Expected output (one of):

- `enable-swift-package-manager: (Not set)` — fine, treat as disabled.
- `enable-swift-package-manager: false` — fine, explicitly disabled.

If the flag is already `true`, the migration is partially done. Stop and ask the user before proceeding.

- [ ] **Step 2: Confirm clean working tree**

Run:

```bash
git status --short
```

Expected: empty output (no modifications, no untracked files).

If non-empty, stop and ask the user to commit, stash, or clean before proceeding.

- [ ] **Step 3: Pre-flight build iOS (debug, development flavor)**

Run:

```bash
cd apps/client && flutter clean && flutter pub get
flutter build ios --debug --flavor development --no-codesign --target lib/main_development.dart
```

Expected: build succeeds, terminal shows `Built build/ios/iphoneos/Runner.app`.

If build fails, stop. Migration cannot proceed until baseline is green.

- [ ] **Step 4: Pre-flight build macOS (debug, development flavor)**

Run (still in `apps/client/`):

```bash
flutter build macos --debug --flavor development --target lib/main_development.dart
```

Expected: build succeeds, terminal shows `Built build/macos/Build/Products/Debug/votasq.app` (or similar product name).

If build fails, stop.

- [ ] **Step 5: Pre-flight `flutter test`**

Run (still in `apps/client/`):

```bash
flutter test
```

Expected: all tests pass.

If any tests fail, stop. Migration must start from a green baseline.

- [ ] **Step 6: Snapshot Podfile.lock pod counts for later comparison**

Run from repo root:

```bash
grep -c "^  - " apps/client/ios/Podfile.lock
grep -c "^  - " apps/client/macos/Podfile.lock
```

Record both counts (e.g., "iOS: 178 pods, macOS: 73 pods"). After migration, these counts should drop substantially. Record them in the commit message of the post-migration commit, or in a scratch note for comparison.

No commit at this task — no changes were made.

---

## Phase 1: Manual edits

These edits happen *before* enabling SwiftPM, so the diff stays clean and reviewable. Each is committed separately.

### Task 1: Remove redundant macOS deployment-target override

The `post_install` hook in `apps/client/macos/Podfile` sets `MACOSX_DEPLOYMENT_TARGET = '10.15'` on every pod target. The project-level setting in `Runner.xcodeproj/project.pbxproj` already enforces 10.15, and CocoaPods inherits the project's deployment target by default. The override is redundant; we remove it as cleanup. This is independent of SwiftPM; we just take the opportunity.

**Files:**

- Modify: `apps/client/macos/Podfile` (lines 38-45 today)

- [ ] **Step 1: Confirm the project-level setting matches**

Run:

```bash
grep "MACOSX_DEPLOYMENT_TARGET" apps/client/macos/Runner.xcodeproj/project.pbxproj | sort -u
```

Expected: a single line ending in `MACOSX_DEPLOYMENT_TARGET = 10.15;` (with leading indentation from the .pbxproj). The `sort -u` ensures only one line if all configurations agree on 10.15.

If you see any value other than 10.15, or multiple distinct lines (meaning configurations disagree), stop. The override is not redundant; do not remove it without first reconciling the project-level setting.

- [ ] **Step 2: Edit the Podfile**

In `apps/client/macos/Podfile`, replace:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.15'
    end
  end
end
```

with:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end
end
```

The inner `target.build_configurations.each` loop is what we're removing.

- [ ] **Step 3: Verify macOS still builds with the simplified Podfile**

Run:

```bash
cd apps/client && flutter clean && flutter pub get
flutter build macos --debug --flavor development --target lib/main_development.dart
```

Expected: build succeeds, same as Task 0 Step 4.

- [ ] **Step 4: Commit**

```bash
git add apps/client/macos/Podfile
git commit -m "chore: drop redundant macOS deployment-target Podfile override

The project-level MACOSX_DEPLOYMENT_TARGET in Runner.xcodeproj already
enforces 10.15, so the per-pod post_install override was a no-op.
Removed as cleanup; behavior unchanged."
```

### Task 2: Update melos setup script

Add `flutter config --enable-swift-package-manager` to the `melos setup` script so contributors don't need to remember the manual command.

**Files:**

- Modify: `pubspec.yaml` (the `melos.scripts.setup` block)

- [ ] **Step 1: Edit pubspec.yaml**

In `pubspec.yaml`, replace:

```yaml
    setup:
      run: melos bootstrap
      description: Initialize the workspace and link packages.
```

with:

```yaml
    setup:
      run: |
        melos bootstrap
        flutter config --enable-swift-package-manager
      description: Initialize the workspace and link packages, and enable Flutter Swift Package Manager support.
```

- [ ] **Step 2: Verify the script parses and runs**

Run from repo root:

```bash
melos setup
```

Expected: `melos bootstrap` runs to completion, then `flutter config --enable-swift-package-manager` runs and prints something like `Setting "enable-swift-package-manager" value to "true".`

- [ ] **Step 3: Confirm the flag is now enabled**

Run:

```bash
flutter config | grep enable-swift-package-manager
```

Expected: `enable-swift-package-manager: true`

This is the moment SwiftPM becomes active for this user. Subsequent `flutter build` calls will route plugins through SwiftPM where supported.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml
git commit -m "build: enable Flutter Swift Package Manager via melos setup

Adds 'flutter config --enable-swift-package-manager' to the setup
script. The flag is per-machine, so each contributor needs it set
locally. Idempotent — re-running setup is safe."
```

### Task 3: Document local setup in CLAUDE.md

Update `.claude/CLAUDE.md` to mention the SwiftPM enablement so a fresh session (or new contributor) knows about it without reading the spec.

**Files:**

- Modify: `.claude/CLAUDE.md` (the `### Setup` section, around lines 15-19)

- [ ] **Step 1: Edit CLAUDE.md**

In `.claude/CLAUDE.md`, replace:

```markdown
### Setup

```sh
melos setup                # Bootstrap workspace and link packages
```

```

with:

```markdown
### Setup

```sh
melos setup                # Bootstrap workspace, link packages, enable SwiftPM
```

`melos setup` enables Flutter Swift Package Manager support via `flutter config --enable-swift-package-manager`. The Apple platforms (iOS, macOS) build in hybrid mode where SwiftPM and CocoaPods coexist — most plugins resolve via SwiftPM, with the Podfile retained as a fallback.

```

- [ ] **Step 2: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs: note SwiftPM hybrid build in CLAUDE.md setup section"
```

---

## Phase 2: Let Flutter rewrite the Apple project files

With SwiftPM enabled (Task 2), the next clean build triggers Flutter's SwiftPM tooling, which edits `project.pbxproj`, the workspace data file, and shrinks `Podfile.lock`. We do iOS first (one platform's diff at a time keeps review tractable).

### Task 4: Migrate iOS to SwiftPM

**Files:**

- Auto-modify: `apps/client/ios/Runner.xcodeproj/project.pbxproj` (Flutter rewrites)
- Auto-modify: `apps/client/ios/Runner.xcworkspace/contents.xcworkspacedata` (Flutter may rewrite)
- Auto-modify: `apps/client/ios/Podfile` (Flutter may inject SwiftPM helper line)
- Auto-modify: `apps/client/ios/Podfile.lock` (shrinks)

- [ ] **Step 1: Clear stale CocoaPods state**

Run:

```bash
cd apps/client/ios
pod deintegrate
rm -rf Pods Podfile.lock
cd ../..
```

Expected: `pod deintegrate` reports the integration was removed; `Pods/` and `Podfile.lock` are gone. (`Pods/` is gitignored, so this is invisible to git.)

- [ ] **Step 2: Clear Xcode DerivedData for the iOS Runner**

Run:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
```

Expected: command succeeds (silently). This prevents stale linked artifacts from masking real link-time failures.

- [ ] **Step 3: Run a clean iOS build with SwiftPM enabled**

Run:

```bash
cd apps/client && flutter clean && flutter pub get
flutter build ios --debug --flavor development --no-codesign --target lib/main_development.dart
```

Expected:

- Build succeeds and prints `Built build/ios/iphoneos/Runner.app`.
- A new `apps/client/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/` directory exists (this is the SwiftPM bridge — gitignored via `Flutter/ephemeral/`).
- `apps/client/ios/Podfile.lock` exists and is substantially smaller than the pre-migration baseline.

If build fails: capture the exact error and stop. Common causes:

- A plugin with a buggy `Package.swift` — the error message will name it. Hybrid mode should keep it on CocoaPods automatically; if it doesn't, this is a Flutter tooling bug worth filing.
- Deployment target mismatch — error mentions a specific iOS version. Should not happen given pre-migration verification, but if it does, check the named pod's `.podspec` minimum.

- [ ] **Step 4: Run a release iOS build**

Run (still in `apps/client/`):

```bash
flutter build ios --release --flavor production --no-codesign --target lib/main_production.dart
```

Expected: succeeds, prints `Built build/ios/iphoneos/Runner.app`.

- [ ] **Step 5: Compare new Podfile.lock pod count vs baseline**

Run from repo root:

```bash
grep -c "^  - " apps/client/ios/Podfile.lock
```

Expected: substantially smaller than the iOS baseline from Task 0 Step 6 (typically a 60-80% drop, since Firebase/Google Sign-In/shared_preferences all migrate). If the count is the same as baseline, no plugins migrated — investigate before committing.

- [ ] **Step 6: Run iOS Xcode test target**

Run from repo root:

```bash
xcodebuild test \
  -workspace apps/client/ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build phase succeeds, test phase runs `RunnerTests.testExample` (a no-op), and the overall result is `** TEST SUCCEEDED **`.

If `iPhone 15` simulator isn't installed, substitute any available iOS simulator name (`xcrun simctl list devices` shows what's available).

- [ ] **Step 7: Smoke-launch on iOS simulator**

Run (in a separate terminal, with a simulator booted):

```bash
cd apps/client && flutter run --flavor development --target lib/main_development.dart -d <simulator-id>
```

Use `flutter devices` to find the simulator ID. Expected:

- App installs and launches.
- No native crash on Firebase initialization.
- The initial UI renders (sign-in or main screen depending on auth state).

Press `q` to quit when verified. This is a hand-eye check, not automated.

- [ ] **Step 8: Review the project.pbxproj diff**

Run:

```bash
git diff --stat apps/client/ios/
git diff apps/client/ios/Runner.xcodeproj/project.pbxproj | head -100
```

Visually verify the diff:

- New entries reference `FlutterGeneratedPluginSwiftPackage` (the SwiftPM bridge).
- Deletions reference pod-related build phases or framework references.
- **No** unexpected changes to `CODE_SIGN_*`, `PRODUCT_BUNDLE_IDENTIFIER`, `*.entitlements` paths, or `INFOPLIST_*` settings.

If you see unexpected changes outside the SwiftPM scope, stop. Do not commit.

- [ ] **Step 9: Commit iOS migration**

```bash
git add apps/client/ios/
git commit -m "build(ios): migrate Flutter plugins to Swift Package Manager

Hybrid mode: plugins with Package.swift resolve via SwiftPM; remaining
plugins still install via Podfile. Pod count dropped from <baseline>
to <new count> in Podfile.lock.

Auto-generated Xcode project edits reviewed; no signing/entitlements drift."
```

Replace `<baseline>` and `<new count>` with the actual numbers from Task 0 Step 6 and Task 4 Step 5.

### Task 5: Migrate macOS to SwiftPM

Identical pattern to Task 4, on the macOS target.

**Files:**

- Auto-modify: `apps/client/macos/Runner.xcodeproj/project.pbxproj`
- Auto-modify: `apps/client/macos/Runner.xcworkspace/contents.xcworkspacedata`
- Auto-modify: `apps/client/macos/Podfile`
- Auto-modify: `apps/client/macos/Podfile.lock`

- [ ] **Step 1: Clear stale CocoaPods state**

Run:

```bash
cd apps/client/macos
pod deintegrate
rm -rf Pods Podfile.lock
cd ../..
```

Expected: same as Task 4 Step 1, but for macOS.

- [ ] **Step 2: Clear Xcode DerivedData**

This was done in Task 4 Step 2; the `Runner-*` glob covers both platforms. Re-run for safety:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
```

- [ ] **Step 3: Run a clean macOS debug build**

Run:

```bash
cd apps/client && flutter clean && flutter pub get
flutter build macos --debug --flavor development --target lib/main_development.dart
```

Expected:

- Build succeeds; product appears under `build/macos/Build/Products/Debug/`.
- `apps/client/macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/` exists.
- `apps/client/macos/Podfile.lock` is substantially smaller than baseline.

- [ ] **Step 4: Run a macOS release build**

Run (still in `apps/client/`):

```bash
flutter build macos --release --flavor production --target lib/main_production.dart
```

Expected: succeeds.

- [ ] **Step 5: Compare new Podfile.lock pod count vs baseline**

Run:

```bash
grep -c "^  - " apps/client/macos/Podfile.lock
```

Expected: substantially smaller than the macOS baseline from Task 0 Step 6.

- [ ] **Step 6: Run macOS Xcode test target**

Run:

```bash
xcodebuild test \
  -workspace apps/client/macos/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Smoke-launch on macOS**

Run:

```bash
cd apps/client && flutter run --flavor development --target lib/main_development.dart -d macos
```

Expected: app launches as a native macOS window, Firebase initializes, initial UI renders. Press `q` to quit.

- [ ] **Step 8: Review the project.pbxproj diff**

Run:

```bash
git diff --stat apps/client/macos/
git diff apps/client/macos/Runner.xcodeproj/project.pbxproj | head -100
```

Same expectations as Task 4 Step 8: SwiftPM-related additions, pod-related deletions, no signing/entitlements drift.

- [ ] **Step 9: Commit macOS migration**

```bash
git add apps/client/macos/
git commit -m "build(macos): migrate Flutter plugins to Swift Package Manager

Hybrid mode: plugins with Package.swift resolve via SwiftPM; remaining
plugins still install via Podfile. Pod count dropped from <baseline>
to <new count> in Podfile.lock.

Auto-generated Xcode project edits reviewed; no signing/entitlements drift."
```

Replace `<baseline>` and `<new count>` with the macOS numbers.

---

## Phase 3: Final verification

A whole-repo sanity sweep before declaring done.

### Task 6: Repo-wide checks

**Files:**

- No edits.

- [ ] **Step 1: Format check**

Run from repo root:

```bash
dart format --set-exit-if-changed apps packages
```

Expected: exit 0, no diffs reported. (No Dart code was touched, so this should be trivially clean. Catches accidental edits.)

- [ ] **Step 2: Analyze**

Run:

```bash
flutter analyze apps packages
```

Expected: no issues found.

- [ ] **Step 3: Full test suite**

Run:

```bash
cd apps/client && flutter test
```

Expected: all tests pass — same set as Task 0 Step 5.

- [ ] **Step 4: Confirm working tree is clean**

Run from repo root:

```bash
git status --short
```

Expected: empty output. All migration changes are committed.

- [ ] **Step 5: Confirm SwiftPM ephemeral packages are gitignored**

Run:

```bash
git check-ignore apps/client/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage 2>/dev/null && echo "iOS ignored: OK" || echo "iOS NOT IGNORED — fix gitignore"
git check-ignore apps/client/macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage 2>/dev/null && echo "macOS ignored: OK" || echo "macOS NOT IGNORED — fix gitignore"
```

Expected: both print `... ignored: OK`. The existing `Flutter/ephemeral/` line in each `.gitignore` should already cover the new `Packages/` subdirectory via prefix match; this step verifies it.

If either reports NOT IGNORED, add an explicit `Flutter/ephemeral/Packages/` line to the corresponding `.gitignore` file and commit.

- [ ] **Step 6: Final commit (if needed)**

If Step 5 required a `.gitignore` fix:

```bash
git add apps/client/ios/.gitignore apps/client/macos/.gitignore
git commit -m "build: explicitly gitignore SwiftPM ephemeral packages"
```

Otherwise, no commit needed.

- [ ] **Step 7: Summary check**

Run:

```bash
git log --oneline main..HEAD
```

Expected commits (in some order, possibly with the final gitignore commit if needed):

1. `chore: drop redundant macOS deployment-target Podfile override`
2. `build: enable Flutter Swift Package Manager via melos setup`
3. `docs: note SwiftPM hybrid build in CLAUDE.md setup section`
4. `build(ios): migrate Flutter plugins to Swift Package Manager`
5. `build(macos): migrate Flutter plugins to Swift Package Manager`

Migration is complete.

---

## Rollback procedure

If any task in Phase 2 fails irrecoverably:

```bash
flutter config --no-enable-swift-package-manager
git reset --hard <pre-migration commit>
cd apps/client/ios && pod install
cd ../macos && pod install
```

Replace `<pre-migration commit>` with the SHA of the commit before Task 1 (use `git log` to find it). The reset is destructive but local; pre-existing `Pods/` directories regenerate on `pod install`. The repo returns to its baseline.
