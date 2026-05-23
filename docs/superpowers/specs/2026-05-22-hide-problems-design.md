# Hide problems from the main listing

**Status:** Design approved 2026-05-22.

## Goal

Let the owner of a problem hide it so it stops appearing in the main listing
for everybody. The hide is reversible: the owner can later unhide. The detail
page (`/problems/<id>`) keeps loading for anyone with the URL, so existing
links, bookmarks, and notifications still resolve. The owner's affordance to
unhide lives on that detail page — when the problem is hidden, the detail page
renders a banner with a "Show in listing" button in place of the "Hide from
listing" button.

## Non-goals

- A "My hidden problems" list, profile page, or list-page toggle. The owner
  reaches their hidden problems via the URLs they already have.
- Cascade behaviour: hidden problems still emit notifications to subscribers,
  remain valid link targets in the linking UI, and still appear in
  `voters` / `versions` / `translations` subcollections. Hiding only affects
  the main listing query.
- Server HTTP route (`apps/server/routes/api/problems/[id]/index.dart`). The
  client moved off it ("Direct Firestore access layer, replacing the HTTP API
  service" — see `firestore_repository.dart`). The new field passes through
  `Problem.fromJson` if a caller sends it, but the route is not used by
  production code paths and gets no new enforcement here.
- A broader rules audit of the existing "Full problem update" branch (which
  currently does not auth-check `description` or `goal`). Out of scope; only
  add the minimal guard required for the new field.

## Data model

`packages/shared/lib/src/models/problem.dart`:

```dart
@Default(false) bool hidden,
```

Regenerate freezed/json files via `melos gen`.

## List query

`apps/client/lib/services/firestore_repository.dart` — extend
`_geoscopedQuery`:

```dart
Query<Map<String, dynamic>> _geoscopedQuery(String geoscope) => _problemsRef
    .where('geoscope', whereIn: geoscopeAncestors(geoscope))
    .where('solved', isEqualTo: false)
    .where('hidden', isEqualTo: false)
    .orderBy('votes', descending: true)
    .orderBy(FieldPath.documentId);
```

Both `watchProblems` and `getProblems` inherit the new filter.

`Firestore.where('hidden', isEqualTo: false)` excludes documents where the
field is *absent*. Existing problem docs do not have a `hidden` field, so they
would vanish from the list. A one-time backfill (see "Backfill" below) writes
`{hidden: false}` to every existing doc before the new client ships.

## Composite index

`firestore.indexes.json` — add:

```json
{
  "collectionGroup": "problems",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "geoscope", "order": "ASCENDING" },
    { "fieldPath": "solved",   "order": "ASCENDING" },
    { "fieldPath": "hidden",   "order": "ASCENDING" },
    { "fieldPath": "votes",    "order": "DESCENDING" },
    { "fieldPath": "__name__", "order": "ASCENDING" }
  ]
}
```

The existing `(geoscope, solved, votes desc, __name__)` index becomes unused
after this change. Remove it from `firestore.indexes.json` in the same change
so the deployed indexes match the queried shape.

## Firestore rules

`firestore.rules` — two changes inside `match /problems/{problemId}`:

### Add a "hide toggle" update branch

```
// Hide / unhide. Only the owner may flip `hidden`, and only `hidden` may
// change in the write. A `description`/`goal` edit that also changes
// `hidden` must go through two writes.
(
  request.auth != null
  && request.auth.uid == resource.data.ownerId
  && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['hidden'])
  && request.resource.data.hidden is bool
)
```

### Constrain the existing "Full problem update" branch

Append a guard so the full-update path cannot smuggle a `hidden` change
(which would bypass the ownership check above):

```
&& request.resource.data.hidden == resource.data.get('hidden', false)
```

`resource.data.get('hidden', false)` covers existing docs that have not yet
been backfilled.

### E2E rules tests

New `group('firestore.rules — problem hidden flag', ...)` in
`apps/server/e2e/firestore_rules_e2e_test.dart`:

1. Owner can set `hidden: true` on their own problem.
2. Owner can set `hidden: false` (unhide) on their own problem.
3. Authed non-owner attempting to set `hidden` is rejected.
4. Unauthed write setting `hidden` is rejected.
5. A "hide toggle" write that also changes `description` (i.e. affects more
   keys than just `hidden`) is rejected.
6. A "full problem update" write that flips `hidden` is rejected.

Follow the existing test style in that file: real ID tokens from the auth
emulator, direct REST writes to the Firestore emulator, the test pushes the
current rules file into the emulator at `setUpAll`.

## Backfill

Existing `problems` documents do not have a `hidden` field, so the new
`where('hidden', isEqualTo: false)` clause excludes them. Backfill is part of
the rollout.

**Approach.** A small one-off Dart script at
`apps/server/tool/backfill_hidden.dart`, run by hand against production via
`gcloud auth application-default login` + `dart run`. Iterates the `problems`
collection through `googleapis` (same client `apps/server/lib/src/db.dart`
uses), patches any document missing `hidden` with `{hidden: false}`, batches
in groups of 100, idempotent (re-runs are no-ops).

**Release sequence (encoded in the implementation plan).**

1. Deploy the new composite index (`firebase deploy --only firestore:indexes`)
   and wait for it to build. Old client keeps working — extra index fields
   don't break the old query.
2. Run the backfill script against production. Old client keeps working —
   `hidden: false` on an old doc is invisible to it.
3. Deploy the new rules (`firebase deploy --only firestore:rules`). Old
   client keeps working — the new rule branch is additive; the
   full-update-branch tightening only affects writes that include `hidden`,
   which the old client never sends.
4. Ship the new client.

## Client repository

`apps/client/lib/services/firestore_repository.dart` — new method:

```dart
Future<void> setHidden({
  required String problemId,
  required bool hidden,
}) => _problemsRef.doc(problemId).update({'hidden': hidden});
```

Targeted single-field update so the rules' "hide toggle" branch matches
exactly.

## Client cubit

`apps/client/lib/problems/cubit/problems_cubit.dart` — new method:

```dart
Future<void> setHidden({
  required Problem problem,
  required bool hidden,
}) async {
  try {
    await _repo.setHidden(problemId: problem.id, hidden: hidden);
    final updated = problem.copyWith(hidden: hidden);
    if (hidden) {
      // Optimistically drop from the list so an immediate back-navigation
      // doesn't briefly show the stale entry before the watch snapshot
      // catches up. Mirrors flagProblem's optimistic removal.
      emit(state.copyWith(
        problems: state.problems.where((p) => p.id != problem.id).toList(),
      ));
    } else {
      // Unhide doesn't necessarily put it back into the visible page (it
      // may sit past the limit). Let the watch stream reconcile.
      applyLocalUpdate(updated);
    }
  } on Exception catch (e, st) {
    log('setHidden failed: $e', stackTrace: st);
  }
}
```

## Detail page UI

`apps/client/lib/problems/view/problem_detail_page.dart` — owner-only changes
inside `_buildEditBody`:

- When `!problem.hidden`: render a "Hide from listing" `OutlinedButton.icon`
  in the bottom action row of the edit body (alongside the existing edit
  controls). Tapping it calls `ProblemsCubit.setHidden(problem, true)`. No
  confirmation dialog and no snackbar — the page itself flips to the
  hidden-state UI below, which is the undo affordance.

- When `problem.hidden` and viewer is the owner: render a `MaterialBanner`
  (or equivalent prominent surface) at the top of the edit body:

  > **This problem is hidden from the main listing.** Nobody — including
  > you — sees it on the listing. People can still reach it through direct
  > links and notifications.
  >
  > [Show in listing]

  The "Show in listing" button calls `ProblemsCubit.setHidden(problem,
  false)`. After the write succeeds, the banner disappears and the
  "Hide from listing" button returns.

- When `problem.hidden` and viewer is **not** the owner: render the same
  banner surface at the top of the read-only body, but with no action and
  slightly different copy:

  > **The owner has hidden this problem from the main listing.** You can
  > still see it here because you followed a direct link.

  All other interactions (vote, flag, link, fork) remain available —
  "hidden" only suppresses listing discovery, not access. This matches the
  rules: read stays `allow read: if true`, and no other rule branch checks
  `hidden`.

- When `!problem.hidden`: no banner; only the owner sees the "Hide from
  listing" button.

The owner-vs-non-owner branching uses the existing `isOwner` variable in
the page build method. The banner-vs-button surface is rendered by both
`_buildEditBody` (owner path) and `_buildReadOnlyBody` (non-owner path);
factor the banner widget into a small private widget so the copy and
styling stay in sync between the two paths.

The detail page maintains its own local `_problem` state already, so an
in-place state flip via `setHidden` should re-render without a full reload.
The page already exposes a way to update `_problem` after writes (see how
edits are applied today); reuse that path.

## l10n strings

New keys to add to **every** ARB file under `apps/client/lib/l10n/arb/`, not
just `app_en.arb`. Supported locales (24 total): `ar`, `bn`, `de`, `en`,
`es`, `fa`, `fr`, `hi`, `id`, `ja`, `ko`, `mr`, `pa`, `pt`, `ru`, `sw`,
`ta`, `te`, `th`, `tr`, `uk`, `ur`, `vi`, `zh`.

(Note: this departs from the most-recent ARB-touching feature
`feat(problems): typed specialization/generalization link tags`, which
shipped only `app_en.arb` strings. Per explicit instruction, this spec
translates every new string into every supported locale at landing time.)

New keys:

- `hideProblemButton` — "Hide from listing"
- `unhideProblemButton` — "Show in listing"
- `problemHiddenOwnerBannerTitle` — "This problem is hidden from the main listing."
- `problemHiddenOwnerBannerBody` — "Nobody — including you — sees it on the listing. People can still reach it through direct links and notifications."
- `problemHiddenViewerBannerTitle` — "The owner has hidden this problem from the main listing."
- `problemHiddenViewerBannerBody` — "You can still see it here because you followed a direct link."

Each key also needs an `@key` description entry in `app_en.arb` per the
existing ARB convention; the description acts as the translator brief.
The translations for the other 23 locales are added with the same key
names but no `@key` metadata (matching the existing structure of the
non-English ARBs).

## Client tests

- `apps/client/test/problems/cubit/problems_cubit_test.dart`
  - `setHidden(true)` calls repo, drops the problem from `state.problems`.
  - `setHidden(false)` calls repo, applies local update without dropping.
  - Repo error is logged and does not crash.
- `apps/client/test/problems/view/problem_detail_page_test.dart`
  - Owner sees the "Hide from listing" button when `!hidden`, no banner.
  - Owner sees the owner-variant banner + "Show in listing" button when
    `hidden`, no "Hide" button.
  - Non-owner sees the viewer-variant banner (no action button) when
    `hidden`, and no banner when `!hidden`.
  - Non-owner sees no "Hide from listing" / "Show in listing" button in
    either state.
  - Tapping the owner's "Hide" / "Show in listing" button calls the cubit
    method with the right args.

## Risks and how the plan handles them

- **Forgotten backfill** → existing problems vanish from the list. Mitigated
  by the explicit "Release sequence" above being part of the implementation
  plan, plus the backfill script being idempotent (safe to re-run).
- **Index propagation lag** → new query fails until the index finishes
  building. Mitigated by deploying the index first and waiting on the
  Firebase console / `firebase firestore:indexes` before proceeding.
- **Rules audit creep** → the existing "Full problem update" branch is loose
  on auth for `description`/`goal`. Out of scope here; we only add the
  minimal `hidden ==` guard so the new field cannot be flipped via that path.
  Captured as a follow-up note, not addressed in this spec.
