# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Votasq is a shared task queue where people vote on task priority. It's a Dart/Flutter monorepo with three packages:

- **packages/shared** — Freezed data models shared between client and server
- **apps/client** — Flutter multi-platform client (iOS, Android, Web, macOS, Windows)
- **apps/server** — Dart Frog REST API backed by Google Cloud Firestore

## Common Commands

### Setup

```sh
melos setup                # Bootstrap workspace and link packages
```

### Code Generation (required after changing models in packages/shared)

```sh
melos gen                  # Runs build_runner across all packages that need it
```

### Format, Analyze, Test (mirrors CI)

```sh
dart format --set-exit-if-changed apps packages
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

### Build & Deploy

```sh
melos build:client         # Build APK + macOS release
melos deploy:server        # Deploy server to Cloud Run
```

## Architecture

### Monorepo Structure

Uses Dart's `workspace` feature (pubspec.yaml) with Melos for script orchestration. The `shared` package is referenced as `shared: any` by both client and server and resolved via workspace.

### Client (BLoC Pattern)

- State management via `bloc`/`flutter_bloc` — feature code lives in `apps/client/lib/problems/` with cubit, state, and view layers
- Three app flavors: development, staging, production (separate `main_*.dart` entry points)
- Internationalization via ARB files in `apps/client/lib/l10n/` (English + Spanish)
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

GitHub Actions (`.github/workflows/main.yaml`): semantic PR check, spell check, format, analyze, test. Release workflow builds Android, Web, macOS, and Linux artifacts on version tags (`v*`).
