# Server one-off scripts

## `backfill_hidden.dart`

Stamps `hidden: false` onto every `problems/*` doc missing the field.
Idempotent. Run before shipping the client that filters `where('hidden',
isEqualTo: false)`, otherwise the listing goes empty.

**Production:**

```sh
cd apps/server
gcloud auth application-default login    # one-time
export GOOGLE_CLOUD_PROJECT=votasq        # or staging project
dart run tool/backfill_hidden.dart --dry-run   # preview
dart run tool/backfill_hidden.dart             # apply
```

**Local emulator** (no ADCs needed — the standard
`FIRESTORE_EMULATOR_HOST` env var is honoured):

```sh
cd apps/server
export FIRESTORE_EMULATOR_HOST=localhost:8081
export GOOGLE_CLOUD_PROJECT=votasq        # any id works for the emulator
dart run tool/backfill_hidden.dart --dry-run
dart run tool/backfill_hidden.dart
```

Output: `scanned=N patched=M dryRun=bool project=... mode=prod|emulator@host`.
