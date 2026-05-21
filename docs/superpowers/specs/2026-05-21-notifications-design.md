# Notifications Infrastructure — v1 Design

## Context

Votasq users have no way to learn about activity that affects them. We want to introduce a per-user notification queue, stored as a Firestore subcollection under each user, that can be drained by multiple delivery channels: in-app UI and FCM push in v1, with email planned later.

v1 notification types:

- `voteReceived` — someone (else) votes on your problem
- `problemForked` — someone (else) creates a new problem that lists yours as `inspoProblemId`
- `problemLinked` — someone (else) lists your problem in their problem's `linkedProblemIds`
- `problemRevised` — a problem you've voted on gets a new revision (recipients are the voters, not the owner who made the revision)
- `forkAdopted` — the owner of an original problem creates a new revision that incorporates field values from your fork, notifying you (the fork's owner). Detection depends on how the recent "copy fork field values into new revisions" feature (commit `c7e5154`) marks the source fork on the new revision — implementer to verify; expected to be a field such as `copiedFromProblemId` on the `ProblemRevision` doc.

The codebase has no existing notification, inbox, or messaging surface, though FCM is already configured (`messagingSenderId` in `firebase_options.dart`) and unused.

## High-level shape

- **Storage:** `users/{uid}/notifications/{notificationId}` subcollection.
- **Producer:** Cloud Functions only. Firestore triggers fire on the relevant document writes and write notifications using admin credentials. Client and Dart Frog server never write notification docs.
- **In-app consumer:** the recipient's authenticated client reads + updates `readAt` directly via the Firebase SDK (mirrors existing direct-Firestore patterns).
- **Push consumer:** a Cloud Function fans new notifications out to FCM tokens registered under `users/{uid}/fcmTokens/`.
- **State:** a single shared `readAt` timestamp. Channels do not write per-channel delivery flags on the notification doc; per-channel bookkeeping (FCM send results, future email cursor) lives in each channel worker's state.
- **Idempotency:** deterministic doc ids derived from `(type, subject, actor)` collapse duplicate triggers and retries into a single notification.

```
┌─────────────────────────┐  onCreate / onUpdate / onDelete    ┌────────────────┐
│ voters/{uid}            │────────────────────────────────────▶│ Cloud Function│
│ problems/{pid}          │  (Firestore triggers)               │ writeNotif    │
│ versions/{v}            │                                     │ helper        │
└─────────────────────────┘                                     └───────┬────────┘
                                                                        │ admin write
                                                                        ▼
┌─────────────────────────────────┐    onCreate     ┌───────────────────────────┐
│ users/{uid}/notifications/{nid} │────────────────▶│ Cloud Function fanOutPush │
└────────────┬────────────────────┘                 │  (reads fcmTokens, prefs) │
             │                                      └─────────┬─────────────────┘
             │ Firebase SDK listener                          │
             ▼                                                ▼
┌─────────────────────┐                              ┌────────────────────────┐
│ NotificationsCubit  │                              │ FCM (APNs/Android/Web) │
│ NotificationsPage   │                              └────────────────────────┘
└─────────────────────┘
```

## Triggers in v1

| Type | Firestore trigger | Recipient(s) | Behavior |
|---|---|---|---|
| `voteReceived` | `onDocumentWritten(problems/{pid}/voters/{actorUid})` | problem owner | See "Vote lifecycle" below; skip if `actorUid == ownerId` |
| `problemForked` | `onDocumentCreated(problems/{forkId})` when `inspoProblemId != null` | owner of `inspoProblemId` | Skip if actor == original owner |
| `problemLinked` | `onDocumentWritten(problems/{linkerId})` for each id newly added to `linkedProblemIds` | owner of each linked problem | Skip self-links and links to your own problems |
| `problemRevised` | `onDocumentCreated(problems/{pid}/versions/{version})` | each voter under `problems/{pid}/voters` | Skip the problem owner (who made the revision) |
| `forkAdopted` | `onDocumentCreated(problems/{originalId}/versions/{version})` when the revision references a fork (e.g., `copiedFromProblemId` set) | owner of the referenced fork problem | Skip if fork owner == original owner |

### Vote lifecycle (the interesting one)

The `voters/{actorUid}` doc carries a vote *count*. Trigger uses `onDocumentWritten` so it sees `before` and `after`:

- **Create (count goes 0 → N):** Write notification (deterministic id; idempotent).
- **Update where count *increased*:** Clear `readAt` and bump `updatedAt` on the existing notification, so it resurfaces as unread.
- **Update where count *decreased but > 0*:** No-op.
- **Update where count → 0** or **Delete:** Treat as retraction. Delete the existing notification **only if `readAt == null`**. If already read, leave it in history.

## Shared models (Freezed)

`packages/shared/lib/src/models/notification.dart`:

```dart
@freezed
class Notification with _$Notification {
  const factory Notification({
    required String id,
    required String recipientUid,
    required NotificationPayload payload,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? readAt,
  }) = _Notification;

  factory Notification.fromJson(Map<String, dynamic> json) =>
      _$NotificationFromJson(json);
}

@Freezed(unionKey: 'type')
sealed class NotificationPayload with _$NotificationPayload {
  const factory NotificationPayload.voteReceived({
    required String problemId,
    required String actorUid,
  }) = VoteReceivedPayload;

  const factory NotificationPayload.problemForked({
    required String originalProblemId,
    required String forkProblemId,
    required String actorUid,
  }) = ProblemForkedPayload;

  const factory NotificationPayload.problemLinked({
    required String linkedProblemId,
    required String linkerProblemId,
    required String actorUid,
  }) = ProblemLinkedPayload;

  const factory NotificationPayload.problemRevised({
    required String problemId,
    required int newVersion,
  }) = ProblemRevisedPayload;

  const factory NotificationPayload.forkAdopted({
    required String forkProblemId,
    required String originalProblemId,
    required int newVersion,
  }) = ForkAdoptedPayload;

  factory NotificationPayload.fromJson(Map<String, dynamic> json) =>
      _$NotificationPayloadFromJson(json);
}
```

`packages/shared/lib/src/models/notification_preferences.dart`:

```dart
@freezed
class NotificationPreferences with _$NotificationPreferences {
  const factory NotificationPreferences({
    @Default({}) Map<String, ChannelPreferences> perType,
  }) = _NotificationPreferences;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      _$NotificationPreferencesFromJson(json);
}

@freezed
class ChannelPreferences with _$ChannelPreferences {
  const factory ChannelPreferences({
    bool? inApp,
    bool? email,
    bool? push,
  }) = _ChannelPreferences;

  factory ChannelPreferences.fromJson(Map<String, dynamic> json) =>
      _$ChannelPreferencesFromJson(json);
}
```

Preferences live as a `notificationPreferences` field on the existing `users/{uid}` doc — no separate subcollection.

Defaults (applied in code on read, not stored):

| Type | inApp | push | email |
|---|---|---|---|
| voteReceived | true | true | false |
| problemForked | true | true | false |
| problemLinked | true | true | false |
| problemRevised | true | true | false |
| forkAdopted | true | true | false |

Email defaults to false because no email worker exists yet; flipping it does nothing today. The schema is set so when email lands, no migration is needed. Missing keys mean "use the default for that type/channel".

Export both new models from the shared library entry point. Run `melos gen` after creating.

## Deterministic doc ids

| Type | Doc id |
|---|---|
| `voteReceived` | `voteReceived__{problemId}__{actorUid}` |
| `problemForked` | `problemForked__{forkProblemId}` |
| `problemLinked` | `problemLinked__{linkedProblemId}__{linkerProblemId}` |
| `problemRevised` | `problemRevised__{problemId}__v{newVersion}` |
| `forkAdopted` | `forkAdopted__{forkProblemId}__{originalProblemId}__v{newVersion}` |

Functions use `.create()` on initial write so a second emission for the same logical event silently no-ops (catch `ALREADY_EXISTS`). On vote-count increase, Function uses `.update()` to clear `readAt` and bump `updatedAt`.

## Cloud Functions

New top-level `functions/` directory (TypeScript + `firebase-functions` v2 — Dart on Functions is not first-class). Layout:

```
functions/
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts                  # exports
    ├── lib/
    │   ├── notify.ts             # writeNotification, resurfaceUnread, retractIfUnread, deterministicId
    │   ├── preferences.ts        # readPreferences, isChannelEnabled
    │   └── types.ts              # TS mirrors of Notification, NotificationPreferences
    ├── l10n/                     # ARB files synced from apps/client/lib/l10n/arb/
    │   ├── app_en.arb
    │   ├── app_es.arb
    │   └── ... (all locales)
    ├── triggers/
    │   ├── vote.ts               # onDocumentWritten('problems/{pid}/voters/{uid}')
    │   ├── fork.ts               # onDocumentCreated('problems/{forkId}')
    │   ├── link.ts               # onDocumentWritten('problems/{linkerId}'), inspects linkedProblemIds diff
    │   ├── revision.ts           # onDocumentCreated('problems/{pid}/versions/{version}'); emits problemRevised AND forkAdopted when applicable
    │   └── push.ts               # onDocumentCreated('users/{uid}/notifications/{nid}')
    └── callables/
        └── markAllNotificationsRead.ts  # callable: batched server-side mark-all-read
```

`writeNotification` consults preferences first; if `inApp` is false for that type, it skips the write. `push.ts` consults preferences and skips if `push` is false for that type. TS interfaces mirror the Dart Freezed JSON shape; kept in sync by convention.

### FCM push delivery (`push.ts`)

- Triggers on notification create.
- Reads the recipient's `notificationPreferences` and skips if push is disabled for the type.
- Streams `users/{uid}/fcmTokens/*` (one doc per device).
- Renders title + body server-side by loading the same ARB files the client uses (synced into `functions/src/l10n/` via a build step or git-tracked copy). Selects locale from `users/{uid}.locale`; falls back to `en` if missing or unsupported. A small ICU-message substituter handles placeholder interpolation (full ICU plural/select support is not needed for v1's strings). All locales share one source of truth with the client.
- Sends via `getMessaging().sendEachForMulticast(...)`.
- On `messaging/registration-token-not-registered` per-token errors, deletes that token doc.

## Client integration

New feature directory: `apps/client/lib/notifications/`.

### Cubit + view

- `cubit/notifications_cubit.dart` — mirrors `apps/client/lib/problems/cubit/problems_cubit.dart`. Subscribes to `users/{currentUid}/notifications` ordered by **`updatedAt desc`**, cursor-paginated. Exposes `markAsRead(id)` which updates `readAt = serverTimestamp` (security rules permit only that field).
- `cubit/notifications_count_cubit.dart` — small cubit holding the unread badge count. Uses Firestore aggregation **`count()` query** on `users/{uid}/notifications where readAt == null`, refreshed on app focus and on `markAsRead` invocations.
- `view/notifications_page.dart` — list of cards, one card widget per payload variant. Uses Dart sealed-class pattern matching:
  ```dart
  Widget build(BuildContext context) => switch (notification.payload) {
        VoteReceivedPayload(:final problemId, :final actorUid) => VoteReceivedCard(...),
        ProblemForkedPayload(...) => ProblemForkedCard(...),
        ProblemLinkedPayload(...) => ProblemLinkedCard(...),
        ProblemRevisedPayload(...) => ProblemRevisedCard(...),
        ForkAdoptedPayload(...) => ForkAdoptedCard(...),
      };
  ```
- `view/notifications_badge.dart` — small badge widget for the app shell that shows the unread count from `NotificationsCountCubit`.

### Repository

- Extend `apps/client/lib/services/firestore_repository.dart` with:
  - `Stream<List<Notification>> watchNotifications(String uid, {DocumentSnapshot? after, int limit})`
  - `Future<int> unreadNotificationCount(String uid)` (uses `.count()` aggregation)
  - `Future<void> markNotificationRead(String uid, String notificationId)`
  - `Future<void> markAllNotificationsRead()` — invokes the callable Cloud Function
  - `Future<void> registerFcmToken(String uid, String token, {required String platform})`
  - `Future<void> unregisterFcmToken(String uid, String token)`

### Display text and locale

- All in-app notification text is rendered at view time from ARB keys (e.g., `notifications.voteReceived.title`, `notifications.voteReceived.body`) with structured params. Actor names and problem snippets are fetched live from existing `users/{uid}` and `problems/{pid}` docs.
- For FCM, the Function renders title + body server-side using the **same ARB files** the client uses, selected by the recipient's `locale` field on `users/{uid}` (add this field; default to `en` when missing). The ARBs are synced into `functions/src/l10n/` via a build script or as tracked copies — one source of truth across all locales.

### FCM client setup

- Add `firebase_messaging` to `apps/client/pubspec.yaml`.
- On sign-in / app start: request notification permission (iOS/macOS/web), obtain FCM token, write to `users/{uid}/fcmTokens/{tokenHash}` with `{token, platform, createdAt, lastUsedAt}`. Refresh `lastUsedAt` on each app open and rotate on token change.
- On sign-out: delete this device's token doc.
- iOS: add APNs capability and Background Modes (Remote notifications) in `apps/client/ios/Runner.xcodeproj`. Provisioning profile needs Push entitlement.
- Web: register a service worker (`apps/client/web/firebase-messaging-sw.js`).
- Foreground handler: when a notification arrives while app is open, surface a toast or update the badge; no native banner.

## Security rules

Both `firestore.rules` and `firestore.indexes.json` already exist at the repo root and must be extended (not replaced). Add to `firestore.rules`:

```
match /users/{uid} {
  // Existing user-doc rules continue; we only need the notification subcollection
  // and to allow the user to update their own notificationPreferences and locale.
  allow update: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.diff(resource.data).changedKeys()
                     .hasOnly(['notificationPreferences', 'locale',
                               'votes', 'lastActiveAt', 'displayName']);

  match /notifications/{nid} {
    allow read: if request.auth != null && request.auth.uid == uid;
    allow update: if request.auth != null
                  && request.auth.uid == uid
                  && request.resource.data.diff(resource.data)
                       .changedKeys().hasOnly(['readAt']);
    allow create, delete: if false;  // Functions only
  }

  match /fcmTokens/{tokenId} {
    allow read, write, delete: if request.auth != null && request.auth.uid == uid;
  }
}
```

Verify the existing rules file's `users` rule allows the listed update fields (`votes`, `lastActiveAt`, `displayName`) or adjust to match what's already permitted.

## Firestore indexes

Extend the existing `firestore.indexes.json`:

- `users/{uid}/notifications` composite on `updatedAt DESC, __name__ DESC` (cursor pagination).
- The `readAt == null` aggregation count query needs no extra index for a single-field equality on a single subcollection; if Firestore prompts for one, add it then.

## Mark-as-read affordances

- **Individual mark-read:** the existing direct-Firestore `update({readAt: serverTimestamp})` path, gated by the security rule.
- **Bulk mark-all-read:** a callable Cloud Function `markAllNotificationsRead` that verifies `request.auth.uid`, queries the caller's unread notifications, and writes them in batches via admin SDK (handles the 500-write batch limit by chunking). Client UI surfaces this as a single button.

## Out of scope (explicitly deferred)

- **Email channel** — schema slot exists; no worker.
- **Per-type and per-channel toggles in the UI** — schema lands now; settings screen lands when we need it.
- **Retention / TTL** — no auto-delete. Vote retractions self-collapse for unread; rest is unbounded growth (acceptable at current scale).
- **Server-side Firebase ID token verification on Dart Frog** — known gap, separate task.

## Verification

- **Emulator tests** (extends `apps/server/e2e/` pattern; adds Functions emulator):
  - Create `voters/{uid}` doc → assert `users/{ownerUid}/notifications/voteReceived__{pid}__{actorUid}` exists with right payload.
  - Update the voter doc to increment vote count → assert the same notification, `readAt == null`, `updatedAt` bumped.
  - Stamp `readAt` on the notification → update voter doc, decrement to 0 → assert notification still exists (already read).
  - With a fresh notification (`readAt == null`), delete the voter doc → assert the notification is gone.
  - Same trigger fired twice in quick succession (simulate retry) → exactly one notification.
  - Skip-self: `actorUid == ownerUid` → no notification written.
  - Fork: create a problem with `inspoProblemId` set to a problem owned by user B → assert B has the fork notification.
  - Link: update a problem to include a new id in `linkedProblemIds` → assert the linked problem's owner gets a notification. Removing the link does *not* delete the notification (intentional asymmetry — only votes retract).
  - Revision fan-out: create a version under a problem with 3 voters (one is the owner) → exactly 2 voter notifications, no owner notification.
  - Fork adoption: with a fork owned by User F linked to original owned by User O, create a new revision on the original with `copiedFromProblemId == forkId` → assert User F gets a `forkAdopted` notification.
  - Bulk mark-read: with 5 unread notifications, invoke the `markAllNotificationsRead` callable → all 5 have `readAt` set; count() aggregation returns 0.
  - Preferences: set `notificationPreferences.voteReceived.inApp = false` for a user → a vote on their problem creates no notification.
  - Push: with a registered fake FCM token, create a notification → assert Function attempted FCM send (mock the FCM SDK).
- **Security rules** (Firestore emulator + `@firebase/rules-unit-testing`):
  - User A cannot read User B's notifications.
  - User A cannot create or delete their own notifications.
  - User A can update only `readAt`; any other field is rejected.
- **Client unit tests** for `NotificationsCubit` and `NotificationsCountCubit` using `bloc_test` + mock Firestore (mirrors existing problem cubit tests in `apps/client/test/problems/`).
- **Manual smoke test** end-to-end:
  - Run client + emulators (Auth, Firestore, Functions).
  - Sign in as User A, vote on User B's problem. Sign in as User B, observe the in-app notification appear in real time.
  - Register a real FCM token on a device, repeat the vote, observe the push.

## Files changed / created

**New:**
- `packages/shared/lib/src/models/notification.dart`
- `packages/shared/lib/src/models/notification_preferences.dart`
- `functions/` (whole new directory tree, including `src/l10n/` ARB copies and `src/callables/markAllNotificationsRead.ts`)
- `apps/client/lib/notifications/` (cubit, state, view, widgets)
- `apps/client/web/firebase-messaging-sw.js`

**Modified:**
- `packages/shared/lib/shared.dart` (export new models)
- `apps/client/pubspec.yaml` (add `firebase_messaging` and `cloud_functions`)
- `apps/client/lib/services/firestore_repository.dart` (add notification + token methods; callable invocation)
- `apps/client/lib/l10n/arb/app_en.arb` and the sibling ARBs (notification copy)
- `apps/client/ios/Runner.xcodeproj` (push entitlement, background modes)
- `apps/client/lib/auth/` (request notification permission post-sign-in; register/unregister token)
- `firestore.rules` (extend with `notifications`, `fcmTokens` rules and add `notificationPreferences`/`locale` to permitted user-doc fields)
- `firestore.indexes.json` (add `updatedAt DESC` composite for `users/{uid}/notifications`)
- `ARCHITECTURE.md` (add notifications tier + data flow)
- `melos.yaml` / repo root tooling (wire `functions/` build and ARB-sync into setup steps if needed)

## Implementation slices (suggested PR breakdown)

1. **Shared models + security rules + indexes + ARB strings** — `Notification`, `NotificationPreferences`, English ARB keys. No behaviour yet.
2. **In-app reader path** — `NotificationsCubit` + view + repository methods + count badge. Tested with hand-written test docs.
3. **Cloud Functions: trigger writers** — `vote`, `fork`, `link`, `revision`, `forkAdopted` handlers + the deterministic-id helper. End-to-end emulator coverage.
4. **Bulk mark-read callable** — small, isolated.
5. **FCM token registration + `push.ts` + ARB sync + iOS entitlements** — push delivery; can be its own PR.
