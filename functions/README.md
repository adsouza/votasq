# votasq-functions

Cloud Functions producers for the Votasq notification queue. See
`docs/superpowers/specs/2026-05-21-notifications-design.md` for the
end-to-end design.

## Layout

```
src/
├── index.ts              # exports all triggers for deploy discovery
├── lib/
│   ├── types.ts          # TS mirrors of the Dart Freezed schemas
│   ├── notify.ts         # deterministicId, writeNotification,
│   │                       resurfaceUnread, retractIfUnread
│   └── preferences.ts    # readPreferences, resolveOptIn (mirrors the
│                           Dart helper's defaults: inApp/push on,
│                           email off)
└── triggers/
    ├── vote.ts           # voteReceived  (onDocumentWritten voters)
    ├── fork.ts           # problemForked (onDocumentCreated problems)
    ├── link.ts           # problemLinked (onDocumentWritten problems,
    │                       diffs linkedProblemIds)
    └── revision.ts       # problemRevised + forkAdopted
                            (onDocumentCreated versions)
```

## Scripts

```sh
npm install
npm run build       # tsc → lib/
npm run build:watch # tsc --watch (rebuilds lib/ on every src/ change)
npm run typecheck   # tsc --noEmit
npm test            # vitest run
```

## Running the emulator with live rebuilds

The Firebase Functions emulator reads from `lib/` (the tsc output), not
from `src/`, and doesn't re-read it after startup. So edits under `src/`
are invisible until lib/ is regenerated. To avoid stopping and restarting
the emulator on every change, use the repo's wrapper script which runs
`tsc --watch` alongside the emulator:

```sh
tool/emulators.sh                 # auth + firestore + functions (default)
tool/emulators.sh auth,firestore  # custom subset
```

Ctrl+C stops both the emulator and the background watcher.

## Tests

The pure-function tests under `src/lib/*.test.ts` exercise the cross-
language invariants — deterministic notification ids and the channel
defaults that must match the Dart `resolveNotificationOptIn` helper.

End-to-end trigger tests (which require the Firestore emulator and so a
Java runtime) are a planned follow-up; the trigger handlers currently
rely on `tsc` + code review for verification.

## Schema drift

The TypeScript interfaces in `src/lib/types.ts` mirror the Dart Freezed
models in `packages/shared/lib/src/models/notification*.dart`. When you
change a shape on either side, update the other. The channel defaults in
`src/lib/preferences.ts` mirror those in
`packages/shared/lib/src/models/notification_preferences.dart`.
