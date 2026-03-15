# Architecture

Votasq is a shared task queue where people vote on the priority of tasks.
It is structured as a Dart monorepo with three packages that share a single data model.

```mermaid
graph TD
    subgraph Monorepo
        shared[packages/shared]
        client[apps/client]
        server[apps/server]
    end

    client -- "depends on" --> shared
    server -- "depends on" --> shared
    client -- "HTTP / JSON" --> server
    server -- "Firestore REST API" --> Firestore[(Cloud Firestore)]
```

The root `pubspec.yaml` declares a Dart
[workspace](https://dart.dev/tools/pub/workspaces) containing all 3 packages.
Melos orchestrates cross-package scripts (`melos setup`, `melos gen`, etc.).

---

## Shared Package

`packages/shared` defines the data models used by both client and server.
It has no Flutter dependency and no runtime logic beyond serialization.

The core model is **Problem**:

```mermaid
classDiagram
    class Problem {
        <<freezed>>
        +String id
        +String description
        +int votes = 1
        +toJson() Map~String, dynamic~
        +fromJson(Map~String, dynamic~)$ Problem
    }
```

The `@freezed` annotation generates immutability, equality, `copyWith`, and
pattern matching. `json_serializable` generates `toJson` / `fromJson`. Both
produce code in `.freezed.dart` and `.g.dart` files that must be regenerated
after model changes (`melos gen`).

---

## Server

The server is a [Dart Frog](https://dartfrog.vgv.dev) application that exposes a
REST API and serves the Flutter web client as static files.

### Request lifecycle

```mermaid
sequenceDiagram
    participant C as Client
    participant R as Dart Frog Router
    participant M as Middleware
    participant H as Route Handler
    participant D as Db
    participant F as Cloud Firestore

    C->>R: HTTP request
    R->>M: matched route
    M->>H: injects Future<Db> via provider
    H->>D: await context.read<Future<Db>>()
    D->>F: googleapis REST call
    F-->>D: Firestore response
    D-->>H: Problem / list
    H-->>C: JSON response
```

### File-based routing

Dart Frog maps the filesystem to routes automatically:

| File                         | Endpoint                                                    |
|------------------------------|-------------------------------------------------------------|
| `routes/index.dart`          | `GET /` — serves `public/index.html` (Flutter web build)    |
| `routes/problems/index.dart` | `GET /problems` — paginated list, `POST /problems` — create |
| `routes/problems/[id].dart`  | `GET /problems/:id` — read, `PUT /problems/:id` — update    |

Each file exports an `onRequest` function that switches on HTTP method.

### Middleware & dependency injection

`routes/_middleware.dart` provides a lazily-initialized `Future<Db>` to all
route handlers via Dart Frog's `provider<T>()`. The `Db` instance is created
once on first request and reused for the lifetime of the server process.

### Database layer (`lib/src/db.dart`)

`Db` wraps the official `googleapis` Firestore REST client.
It authenticates via Application Default Credentials — automatic on Cloud Run,
and via `gcloud auth application-default login` locally.

```mermaid
graph LR
    Db -->|"clientViaApplicationDefaultCredentials()"| ADC[Application Default Credentials]
    ADC -->|Cloud Run| SA[Service Account]
    ADC -->|Local dev| GCloud["gcloud CLI credentials"]
    Db -->|"FirestoreApi"| Firestore[(Cloud Firestore)]
```

Key operations:

- **saveProblem** — creates or overwrites a document in the `problems` collection
- **getProblem** — fetches a single document by ID
- **getProblems** — runs a `StructuredQuery` ordered by `votes DESC, __name__ ASC`
  with cursor-based pagination

### Pagination

The server uses Firestore cursor-based pagination over a composite index
(`votes DESC`, `__name__ ASC`, defined in `firestore.indexes.json`).

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server
    participant F as Firestore

    C->>S: GET /problems?pageSize=20
    S->>F: StructuredQuery (limit 20)
    F-->>S: 20 documents
    S-->>C: { data: [...], nextPageToken: "base64..." }

    C->>S: GET /problems?pageSize=20&pageToken=base64...
    S->>F: StructuredQuery (limit 20, startAt cursor)
    F-->>S: next 20 documents
    S-->>C: { data: [...], nextPageToken: "base64..." }
```

The page token is a base64-encoded JSON object `{ v: votes, r: documentRef }`
representing the last item on the previous page. When `results.length < pageSize`,
no token is returned, signaling the end of the list.

### GCP project resolution (`lib/src/resolve_project_id.dart`)

1. Checks the `GOOGLE_CLOUD_PROJECT` environment variable
2. Falls back to the GCP metadata server (`metadata.google.internal`)
3. Throws if neither is available

---

## Client

The Flutter client targets iOS, Android, Web, macOS, and Windows.
It uses the BLoC pattern for state management.

### Layer diagram

```mermaid
graph TD
    UI["ProblemsPage / ProblemsView<br/>(Flutter widgets)"]
    Cubit["ProblemsCubit<br/>(state management)"]
    State["ProblemsState<br/>(status, problems, nextPageToken)"]
    API["ApiService<br/>(HTTP client)"]
    Server["Dart Frog Server"]

    UI -->|"reads state via BlocBuilder"| State
    UI -->|"calls loadProblems / loadMore"| Cubit
    Cubit -->|"emits"| State
    Cubit -->|"calls"| API
    API -->|"HTTP GET/POST/PUT"| Server
```

### State machine

```mermaid
stateDiagram-v2
    [*] --> initial
    initial --> loading : loadProblems()
    loading --> success : data received
    loading --> failure : exception
    success --> success : loadMore() appends
    success --> failure : loadMore() exception
    failure --> loading : retry / loadProblems()
```

`ProblemsState` holds the current `ProblemsStatus` enum (`initial`, `loading`,
`success`, `failure`), the loaded `List<Problem>`, and an optional
`nextPageToken`. The computed getter `hasMore` drives infinite scroll —
when the user scrolls past 90% of the list, `loadMore()` fetches the next page
and appends the results.

### Flavor system

Three entry points configure the app for different environments:

| Entry point                 | Flavor      |
|-----------------------------|-------------|
| `lib/main_development.dart` | development |
| `lib/main_staging.dart`     | staging     |
| `lib/main_production.dart`  | production  |

All call `bootstrap()` which sets up BLoC observer and error logging.
`ApiService` picks its base URL at runtime: `localhost:8080` in debug mode,
the Cloud Run URL in release builds.

### Internationalization

ARB files in `lib/l10n/arb/` define localized strings (English + Spanish).
Flutter generates `AppLocalizations` at build time. Access in widgets via the
`context.l10n` extension.

---

## Build & Deployment

### Docker build (production)

The Dockerfile produces a minimal container that serves both the API and the
Flutter web client from a single binary.

```mermaid
graph LR
    subgraph "Stage 1: flutter-build"
        A1[Flutter SDK] --> A2["flutter build web --release"]
    end

    subgraph "Stage 2: build"
        B1[Dart SDK] --> B2["dart_frog build"]
        B2 --> B3["dart compile exe"]
        A2 -.->|"COPY web output to<br/>server/public/"| B2
    end

    subgraph "Stage 3: scratch"
        C1["Native binary + web assets"]
    end

    B3 --> C1
```

1. **Stage 1** builds the Flutter web client (production flavor)
2. **Stage 2** copies the web output into `apps/server/public/`, generates the
   Dart Frog production code, and compiles it to a native executable
3. **Stage 3** copies only the binary, web assets, and runtime libs into a
   `scratch` image — the final image contains no SDK

The server's `GET /` route serves `public/index.html`, so the web client is
bundled directly into the server container.

### Cloud Run deployment

`melos deploy:server` runs `gcloud run deploy` from the repo root,
which triggers Cloud Build to execute the Dockerfile and
deploy the resulting container to Cloud Run in `us-central1`.

### CI/CD

```mermaid
graph TD
    subgraph "CI (main.yaml) — push/PR to main"
        CI1[Semantic PR check] --> CI2[Spell check]
        CI2 --> CI3[Install deps]
        CI3 --> CI4[Format check]
        CI4 --> CI5[Analyze]
        CI5 --> CI6[Test with coverage]
    end

    subgraph "Release (release.yaml) — v* tags"
        R1[Android APK + AAB]
        R2[Web tarball]
        R3[macOS zip]
        R4[Linux tarball]
        R1 & R2 & R3 & R4 --> R5[Create GitHub Release]
    end
```

A separate `license_check.yaml` workflow validates that all dependencies use
allowed licenses (MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0) whenever
`pubspec.yaml` files change.
