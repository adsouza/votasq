# Server one-off scripts

## `backfill_hidden.dart`

Stamps `hidden: false` onto every `problems/*` doc missing the field.
Idempotent. Run before shipping the client that filters `where('hidden',
isEqualTo: false)`, otherwise the listing goes empty.

```sh
cd apps/server
gcloud auth application-default login    # one-time
export GOOGLE_CLOUD_PROJECT=votasq        # or staging project
dart run tool/backfill_hidden.dart --dry-run   # preview
dart run tool/backfill_hidden.dart             # apply
```

Output: `scanned=N patched=M dryRun=bool project=...`.
