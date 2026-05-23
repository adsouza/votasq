# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Votasq is a shared task queue where people vote on task priority. It's a Dart/Flutter monorepo with three packages:

- **packages/shared** — Freezed data models shared between client and server
- **apps/client** — Flutter multi-platform client (iOS, Android, Web, macOS, Windows)
- **apps/server** — Dart Frog REST API backed by Google Cloud Firestore

## Common Commands

### Setup

```sh
melos setup                # Bootstrap workspace, link packages, enable SwiftPM, activate git hooks
```

`melos setup` enables Flutter Swift Package Manager support via `flutter config --enable-swift-package-manager`.
The Apple platforms (iOS, macOS) build in hybrid mode where SwiftPM and CocoaPods coexist — most plugins resolve via SwiftPM, with the Podfile retained as a fallback.

It also points `core.hooksPath` at the tracked `.githooks/` directory. The `pre-push` hook there runs `melos format` and `flutter analyze apps packages` to catch CI failures before they reach GitHub. Bypass with `git push --no-verify` if you must.

### Code Generation (required after changing models in packages/shared)

```sh
melos gen                  # Runs build_runner across all packages that need it
```

### Format, Analyze, Test (mirrors CI)

Run `melos format` after every change. (Plain `dart format apps packages` descends into vendored SwiftPM checkouts under `apps/client/build/` and is noisy.)

Also do this after making nontrivial changes:

```sh
flutter analyze apps packages
very_good test --recursive --no-optimization --coverage --test-randomize-ordering-seed random
```

### Run Locally

```sh
# Client (development flavor)
cd apps/client && flutter run --flavor development --target lib/main_development.dart

# Server
export GOOGLE_CLOUD_PROJECT=votasq
cd apps/server && gcloud auth application-default login && dart_frog dev
```

### E2E Tests

Requires Firebase emulators (Auth on :9099, Firestore on :8081) to be running. **Must be run from the project root** (tests read `firestore.rules` and use relative `workingDirectory: 'apps/server'`):

```sh
firebase emulators:start --only auth,firestore   # in a separate terminal
dart test apps/server/e2e/ --tags e2e
```

Two test files live here:

- `problems_e2e_test.dart` — exercises the Dart Frog server's `/problems` HTTP API end-to-end (writes bypass rules via the server's Admin-credentials path).
- `firestore_rules_e2e_test.dart` — exercises `firestore.rules` directly via the Firestore REST API with a real ID token from the Auth emulator, so rule changes are validated against the actual rules engine (the client's `fake_cloud_firestore` unit tests don't model rules). Pushes the current rules file into the emulator at setup time, so it's self-contained even if the emulator was started before a rules edit.

### Build & Deploy

```sh
melos build:client         # Build APK + macOS release
melos deploy:server        # Deploy server to Cloud Run
```

### Release

```sh
melos run release -- vX.Y.Z "Annotated tag message"
```

Updates `apps/client/pubspec.yaml` to `X.Y.Z+1` (matching the tag), commits, pushes main, creates a signed annotated tag, and pushes the tag — which triggers `.github/workflows/release.yaml` to build Android, Web, and macOS artifacts and publish a GitHub Release. Pre-flight checks: clean tree, on `main`, up-to-date with origin, tag doesn't exist, `melos format` + `flutter analyze` pass. See `tool/release.sh` for the full sequence.

## Gotchas

### Changes to `firestore.rules` need an e2e test case

The client's unit tests use `fake_cloud_firestore`, which does **not** enforce security rules. A rules mistake (omitted field in an allowlist, wrong `affectedKeys` predicate, missing `request.auth` check) passes every unit test and only fails against a real emulator or production. We've shipped this class of bug before.

When you change `firestore.rules`, add or update a case in `apps/server/e2e/firestore_rules_e2e_test.dart` that exercises the new path. The test goes through the Firestore REST API with a real ID token from the Auth emulator, so rules are evaluated exactly as in production. ~10 lines per scenario; permanent regression protection.

The Firestore emulator caches rules at startup and does not reliably hot-reload on file edit. The e2e test pushes the current rules file into the emulator via the `:securityRules` PUT endpoint at setUpAll time, so the test is self-contained — but if you're testing rules manually against a long-running emulator, restart it or you'll be debugging stale rules.

### Adding a new field to a Firestore doc with a query filter

When a new field on a Firestore document type becomes part of a `where(...)` filter (or any index), **audit every doc-create site in `firestore_repository.dart` (and any server-side writer) to confirm each one stamps the field on the wire**. Freezed's `@Default(...)` annotations only fill in fields when *reading* (`fromJson`); they have no effect on doc maps built by hand and passed to `.set(...)`.

We shipped the `hidden` flag with this exact gap in May 2026: `addProblem` and `forkProblem` built their `problemData` map without `hidden`, every new problem was missing the field, and Firestore's `where('hidden', isEqualTo: false)` filter excluded them — every newly-created problem silently vanished from the listing. The freezed model and the query-filter test both passed because the test helpers (`seedProblem` in `firestore_repository_test.dart`) wrote complete docs by hand, papering over the production wire shape.

Mitigation pattern, in order of strength:

1. **Add the field to every writer.** Grep for `_problemsRef.doc(...).set(` (and equivalent for other collections) and add the new field to every map literal.
2. **Tighten the `firestore.rules` create branch** to require the field with a specific initial value (e.g. `&& request.resource.data.hidden == false`). The rule then enforces the invariant at the database, not just at the client.
3. **Add a round-trip integration test** that calls the create method (e.g. `addProblem`) and then queries via the filtered method (e.g. `getProblems`), asserting the new doc appears. The existing layer-specific tests (rules e2e, repo unit, cubit, widget) each test their own slice — only a round-trip catches wire-shape gaps.

### Test fixtures can paper over production widget-tree / wire-shape gaps

Two debug sessions in May 2026 hit the same meta-bug: a test fixture provided something at the test root that wasn't actually there in production, masking the failure.

- **Provider scope:** widget tests scaffolded `BlocProvider<ProblemsCubit>` at the test root, but in production the cubit is provided **inside `ProblemsPage`'s build method**. The detail page (`/problems/:id`) is a separate GoRouter route reached from outside that subtree — `context.read<ProblemsCubit>()` threw `ProviderNotFoundException` in prod but never in tests.
- **Wire shape:** `seedProblem` in `firestore_repository_test.dart` defaults `hidden: false` when it writes seed docs, so query-filter tests passed even though `addProblem`'s real wire payload was missing the field.

When adding a feature that touches multiple layers, write at least one **integration test** that exercises the production widget hierarchy / wire shape end-to-end — not just mocked unit tests for each layer. If you find yourself adding a convenience to a test fixture (a default value, a provider at the root), ask whether that convenience holds in production. If it doesn't, the test isn't testing what you think it is.

### Running the mac (or iOS) app against the local emulator

Two macOS-specific footguns the web flavor doesn't have. Both surface the same way: `[cloud_firestore/unavailable] The service is currently unavailable.` in the Flutter run console plus an empty listing.

**(1) Emulator host must be a literal IPv4 address.** macOS resolves `localhost` to both `::1` (IPv6, listed first by `dscacheutil`) and `127.0.0.1` (IPv4). The Firebase Local Emulator Suite binds only to `127.0.0.1`, and the Firestore Flutter plugin on Apple platforms uses gRPC, which doesn't reliably happy-eyeballs from IPv6 to IPv4 — a failed `::1` attempt surfaces as "unavailable" instead of falling back. `_emulatorHost()` in `apps/client/lib/bootstrap.dart` already returns `'127.0.0.1'` for non-web, non-Android platforms; don't change it back to `'localhost'`. (Auth and Functions emulators happen to work via `localhost` because their plugins use URLSession which does fall back, but Firestore's gRPC doesn't.)

**(2) App Check debug token must be registered in Firebase Console.** When the `firebase_app_check` plugin is loaded (which it always is — it's in `pubspec.yaml`), the Firestore Apple SDK automatically attempts to fetch an App Check token before each request. `bootstrap.dart` activates `AppleDebugProvider` for all native runs including emulator, but the debug UUID it generates (printed to the run console on first launch as `Firebase App Check Debug Token: <UUID>`) must be registered in **Firebase Console → App Check → the macOS app row → Manage debug tokens**. Without registration, the exchange returns HTTP 403 and the Firestore SDK closes the WatchStream — emulator listing stays empty, prod listing eventually limps along because Firestore enforcement is off (but the console floods with App Check failures). Same registered token works for both prod-mac and emulator-mac because they share the macOS Firebase app config.

See `apps/client/macos/README.md` for the debug-token registration walkthrough.

### Keep CI's `flutter-version` aligned with your local Flutter

CI pins `flutter-version` in three workflow files (`.github/workflows/main.yaml`, `license_check.yaml`, `release.yaml`). The bundled `dart format` (and `dart analyze`) varies by SDK version, so a stale CI pin against a newer local Flutter produces formatter disagreements that pre-push checks can't catch — `melos format` uses your local SDK. When you bump local Flutter, bump those three files together.

If you do hit a formatter disagreement, download just the matching Dart SDK from https://dart.dev/get-dart/archive (~200MB vs a full Flutter at ~6GB) and run `<sdk>/bin/dart format --output=show --set-exit-if-changed <file>` to see exactly what CI wants.

## Architecture

Update the `ARCHITECTURE.md` file in the project root dir after making architectural changes.

### Monorepo Structure

Uses Dart's `workspace` feature (pubspec.yaml) with Melos for script orchestration.
The `shared` package is referenced as `shared: any` by both client and server and resolved via workspace.

### Client (BLoC Pattern)

- State management via `bloc`/`flutter_bloc` — feature code lives in `apps/client/lib/problems/` with cubit, state, and view layers
- Three app flavors: development, staging, production (separate `main_*.dart` entry points)
- Internationalization via ARB files in `apps/client/lib/l10n/` (English + several other langs)
- Linting: `very_good_analysis` + `bloc_lint`

### Server (Dart Frog)

- Routes in `apps/server/routes/` map directly to REST endpoints:
  - `GET/POST /problems` — list (paginated) and create
  - `GET/PUT /problems/[id]` — read and update votes
- Firestore access via `googleapis` library (not FlutterFire) with Application Default Credentials
- Database logic in `apps/server/lib/src/db.dart`

### Shared Models

- Freezed + json_serializable for immutable models with JSON serialization
- Generated files (`*.freezed.dart`, `*.g.dart`) must be regenerated via `melos gen` after model changes

## CI

GitHub Actions (`.github/workflows/main.yaml`): semantic PR check, spell check, format, analyze, test.
Release workflow builds Android, Web, macOS, and Linux artifacts on version tags (`v*`).
