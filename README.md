# Votasq

A shared task queue that allows people to vote on the priority of tasks.
Votasq is a Dart/Flutter monorepo with three main components:

| Package           | Description                                                    |
|-------------------|----------------------------------------------------------------|
| `packages/shared` | Freezed data models shared between client and server           |
| `apps/client`     | Flutter multi-platform client (macOS, GNU/Linux, Android, Web) |
| `apps/server`     | Dart Frog REST API backed by Google Cloud Firestore            |

## Prerequisites

- **Dart SDK** >= 3.11.0
- **Flutter SDK** >= 3.41.0
- **Melos** — installed via `dart pub get` at the repo root (declared as a dev dependency)
- **Very Good CLI** — `flutter pub global activate very_good_cli`
- **Dart Frog CLI** — `dart pub global activate dart_frog_cli`
- **Google Cloud CLI** (`gcloud`) — for local server development and deployment
- **Firebase CLI** (`firebase`) — for running the Firestore emulator
- **Java** — required by the Firebase Firestore emulator, sadly.

## Getting Started

```sh
# Clone the repo
git clone https://github.com/adsouza/votasq.git
cd votasq

# Bootstrap the workspace (resolves dependencies and links packages)
melos setup
```

### Code Generation

After changing any Freezed models in `packages/shared`,
regenerate the serialization code with `melos gen`.

## Running Locally

### Server

The server needs a GCP project ID and Firestore credentials.
For local development, authenticate with the Google Cloud CLI:

```sh
export GOOGLE_CLOUD_PROJECT=votasq
gcloud auth application-default login

cd apps/server
dart_frog dev  # Starts on http://localhost:8080
```

Alternatively, you can run the server against the **Firestore emulator**
to avoid needing a real GCP project:

```sh
# Terminal 1 — start the emulator
firebase emulators:start --only firestore

# Terminal 2 — start the server pointing at the emulator
export GOOGLE_CLOUD_PROJECT=votasq-test
export FIRESTORE_EMULATOR_HOST=localhost:8081
cd apps/server
dart_frog dev
```

### Client

```sh
cd apps/client
flutter run --flavor development --target lib/main_development.dart
```

The client has three flavors (`development`, `staging`, `production`) with
corresponding entry points (`lib/main_development.dart`, etc.). In debug mode
the client connects to `localhost:8080`.

## Testing

### Unit and Widget Tests

```sh
# Run all tests across the workspace
very_good test --recursive --no-optimization --coverage --test-randomize-ordering-seed random
```

### End-to-End Integration Tests

The server has E2E tests that run against the Firebase Firestore emulator.
These are tagged with `e2e` and excluded from normal test runs.

```sh
# Terminal 1 — start the emulator
firebase emulators:start --only firestore

# Terminal 2 — run the E2E tests
dart test apps/server/test/routes/problems_e2e_test.dart -t e2e
```

### Linting and Formatting

```sh
dart format --set-exit-if-changed apps packages
flutter analyze apps packages
```

## REST API

| Method | Endpoint                               | Description                                                  |
|--------|----------------------------------------|--------------------------------------------------------------|
| `GET`  | `/`                                    | Serves the Flutter web client                                |
| `GET`  | `/problems?pageSize=N&pageToken=TOKEN` | List problems (paginated, sorted by votes descending)        |
| `POST` | `/problems`                            | Create a problem — send `{"description": "..."}`             |
| `GET`  | `/problems/:id`                        | Get a single problem                                         |
| `PUT`  | `/problems/:id`                        | Update a problem — send `{"description": "...", "votes": N}` |

## Build and Deploy

### Build Client Artifacts

```sh
melos build:client     # Builds APK + macOS release
```

### Deploy Server to Cloud Run

```sh
melos deploy:server    # Deploys via gcloud run deploy
```

The production Docker build is a multi-stage process:

1. Builds the Flutter web client.
2. Copies the web output into the server's `public/` directory, generates the Dart Frog production build,
and compiles it to a native executable.
3. Produces a minimal `scratch` image containing only the binary and web assets.

## CI/CD

GitHub Actions workflows in `.github/workflows/`:

- **main.yaml** — Runs on every push/PR to `main`: semantic PR check, spell
  check, dependency resolution, formatting, analysis, and tests with coverage.
- **release.yaml** — Triggered by `v*` tags: builds Android, Web, macOS, and
  Linux artifacts and publishes them as a GitHub Release.
- **license_check.yaml** — Validates that all dependencies use allowed licenses
  (MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0) when `pubspec.yaml` files change.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed diagrams covering the
monorepo structure, request lifecycle, pagination, state management, and
deployment pipeline.
