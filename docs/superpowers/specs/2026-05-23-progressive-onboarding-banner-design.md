# Progressive Onboarding Banner — Design

**Status:** Draft 2026-05-23 (rev 4 — votesCastCount becomes server-derived)
**Owner:** @adsouza
**Related commit:** abf4d27 (`feat(client): persistent sign-in banner + double-tap hint toast`)

## Problem

New users were missing the sign-in toast (it timed out before they noticed it)
and weren't discovering that double-tapping a problem opens its detail page.
Commit `abf4d27` promoted the sign-in CTA to a persistent banner and reused the
toast slot for the double-tap hint. That's better, but it stops there — once
the user signs in, the banner vanishes and the double-tap hint only lives in
the toast surface, which a focused user can still miss.

This spec extends the banner into a **progressive onboarding surface** that
walks the user through tips in sequence, suppressing each tip once the user
has demonstrably learned it.

## Goals

1. After sign-in, the banner walks the user through a tip sequence:
   **vote-for-problems** → **double-tap-for-details** → hidden.
2. Each hint (and the matching toast for double-tap) suppresses once the
   user has demonstrated knowledge of that affordance — measured against
   how long they've been away from the app.
3. The suppression rule degrades gracefully for returning users: a user
   coming back after a long absence sees a tip again, even if they used
   the corresponding affordance heavily in a previous session.

## Non-goals

- Generalized onboarding framework. This spec ships one tip sequence
  (sign-in → double-tap → hidden). Future tips can layer onto the same
  pattern but we don't pre-build that abstraction.
- Anonymous-user tracking. The counter lives on the user doc and only
  applies post-sign-in.
- Server-mediated writes. Increments are client-direct under Firestore
  rules — same pattern as `lastActiveAt` and `votes`.

## User experience

The banner renders in priority order — the first tip whose skip rule
fails is the one shown. `daysSince` here means
`daysSinceLastSession` (defined in **State layer**, frozen at sign-in).

```
Auth status      | Tip checks (in order)               | Banner shown
─────────────────┼─────────────────────────────────────┼──────────────────────
unauthenticated  | (n/a)                               | sign-in tip
authenticated    | votesCastCount        <= daysSince  | vote tip
authenticated    | problemDetailsViewCount <= daysSince| double-tap tip
authenticated    | both counts > daysSince             | (none — graduates)
```

Banner sits below the AppBar and above `AddProblemRow`. The two coexist
vertically whenever the user is authenticated and a tip is active. Only
the *double-tap* hint also has a toast surface; the toast is gated by the
same rule as its banner state — a graduated user sees neither.

### Worked examples

- **Brand new user, first session:** votesCastCount=0,
  problemDetailsViewCount=0, daysSince=0. `0 <= 0` for both → vote tip
  shows (it's first in the priority order).
- **First-session user who votes once but hasn't double-tapped:**
  votesCastCount=1, problemDetailsViewCount=0, daysSince=0. Vote check
  `1 <= 0` is false → vote tip graduates; double-tap check `0 <= 0` →
  double-tap tip shows.
- **Returning user, used both 10× last session, back next day:**
  votesCastCount=10, problemDetailsViewCount=10, daysSince=1. Both
  `10 <= 1` are false → no banner.
- **Returning user, voted 10× a month ago:** votesCastCount=10,
  daysSince=30. `10 <= 30` → vote tip re-appears as a refresher.
- **User mid-session crosses a threshold:** if they start with
  votesCastCount=0, daysSince=2 and vote three times during the session,
  count becomes 3. `3 <= 2` is false → vote tip hides reactively; if
  problemDetailsViewCount still satisfies its check, double-tap tip slides
  into the same slot without a reload.

## Data model

### Wire shape

User doc gains two fields:

```
problemDetailsViewCount: int64   // default 0
votesCastCount:          int64   // default 0
```

### Freezed model (`packages/shared/lib/src/models/user.dart`)

```dart
@freezed
abstract class User with _$User {
  const factory User({
    required String uid,
    required DateTime lastActiveAt,
    required int votes,
    String? displayName,
    @Default(0) int problemDetailsViewCount,
    @Default(0) int votesCastCount,
  }) = _User;
  // ...
}
```

`@Default(0)` makes the freezed model deserialization robust to docs
that pre-date this feature. **For `problemDetailsViewCount`** that
default is also the truthful migration value (we have no historical
record of detail-page views). **For `votesCastCount`** the default
would be a *lie* — existing users have voted in the past, and stamping
`0` would re-show them the vote tip indefinitely. We backfill the
real value before the new client ships; see **Migration** below.

## Firestore rules

Two changes to `firestore.rules` in the `users/{userId}` block.

### New update branch: problemDetailsViewCount increment

```ruby
// problemDetailsViewCount increment + lastActiveAt touch in one write
(
  request.resource.data.diff(resource.data).affectedKeys()
    .hasOnly(['problemDetailsViewCount', 'lastActiveAt'])
  && request.resource.data.problemDetailsViewCount is int
  && request.resource.data.problemDetailsViewCount ==
     resource.data.get('problemDetailsViewCount', 0) + 1
  && request.resource.data.lastActiveAt is timestamp
)
```

Strict `+1` enforcement keeps a malicious client from fast-forwarding
themselves out of the banner. Bundling `lastActiveAt` into the same write
avoids a separate touch per double-tap.

### Vote-decrement branch: unchanged

The client's vote write keeps its current shape — decrement
`users/{uid}.votes`, increment `problems/{pid}.votes`, write
`problems/{pid}/voters/{uid}` (all under the *existing* rule branches).
`votesCastCount` is **not** in the vote-write payload; it's stamped
server-side by the Cloud Function (see **Cloud Function:
votesCastCount materialization** below). Benefits of keeping the
increment off the client write:

- No coupling between the vote action and a tip-graduation field.
- Stale clients (deployed before this change) keep voting normally;
  their users still graduate from the vote tip because the function
  fires on the voter doc regardless of which client wrote it.
- No rule extension needed in the vote path.

### Create branch: optional zero-init for both counters

The `hasAll([...])` list does *not* require either new field. If
they're present in the create payload, the rule checks they're `int`
and `== 0`:

```ruby
&& (
  !('problemDetailsViewCount' in request.resource.data.keys())
  || (
    request.resource.data.problemDetailsViewCount is int
    && request.resource.data.problemDetailsViewCount == 0
  )
)
&& (
  !('votesCastCount' in request.resource.data.keys())
  || (
    request.resource.data.votesCastCount is int
    && request.resource.data.votesCastCount == 0
  )
)
```

## Repository layer

`apps/client/lib/services/firestore_repository.dart`:

- **`ensureUserDoc`** stamps `problemDetailsViewCount: 0` *and*
  `votesCastCount: 0` on the wire when creating a new user doc. This
  avoids the CLAUDE.md "freezed `@Default` doesn't apply to
  manually-built maps passed to `.set()`" trap.
- **`_docToUser`** reads both new fields field-by-field with `?? 0`
  fallbacks. Symmetric write-side discipline: a forgotten read here
  would silently drop server values into the freezed default.
- **Replace `watchUserVotes(uid) → Stream<int>`** with
  **`watchUserDoc(uid) → Stream<User>`**. The cubit now needs more than
  votes; one subscription beats two (or three).
- **New: `incrementProblemDetailsViewCount(uid) → Future<void>`** —
  `update({problemDetailsViewCount: FieldValue.increment(1), lastActiveAt: now})`.
  Fire-and-forget from the caller's perspective.
- **The existing vote-decrement write is unchanged.** `votesCastCount`
  is materialized by a Cloud Function — see below.

## Cloud Function: votesCastCount materialization

`functions/src/triggers/vote.ts` already hosts `onVoterWritten`, which
watches `problems/{pid}/voters/{actorUid}` for the notifications
producer. We add a parallel function in the same file (or co-located
sibling) that materializes the `votesCastCount` on the user doc:

```ts
export const onVoterWrittenForVotesCastCount = onDocumentWritten(
  "problems/{pid}/voters/{actorUid}",
  async (event) => {
    const actorUid = event.params.actorUid as string;
    const before = event.data?.before;
    const after = event.data?.after;
    const beforeVotes = (before?.get("votes") as number | undefined) ?? 0;
    const afterVotes = (after?.get("votes") as number | undefined) ?? 0;

    const delta = afterVotes - beforeVotes;
    if (delta <= 0) return; // monotonic: never decrement on unvote/delete

    await getFirestore()
      .doc(`users/${actorUid}`)
      .update({votesCastCount: FieldValue.increment(delta)});
  },
);
```

Design notes:

- **Trigger source:** the voter doc, not the user doc. Decouples
  `votesCastCount` from the user-doc vote-decrement write, so stale
  clients still produce graduation events.
- **Delta math:** the voter doc's `votes` field carries a per-problem
  vote count (the existing rule on `voters/{voterId}` permits only
  increments). `afterVotes - beforeVotes` is the number of new votes
  cast in this write. `before` is missing on create (`beforeVotes = 0`),
  so a brand-new voter doc with `votes: 1` increments `votesCastCount`
  by exactly 1.
- **Monotonic:** if a voter doc is ever deleted, `afterVotes = 0` and
  `delta < 0` — we deliberately skip the decrement. Tip graduation
  reflects *demonstrated knowledge*; un-voting doesn't undo learning.
- **Admin SDK bypass:** the function runs with admin credentials,
  bypassing the rules. No rule branch needs to permit writing
  `votesCastCount` to an arbitrary value.
- **Idempotency caveat:** Cloud Functions guarantee *at-least-once*
  delivery. A duplicated invocation would double-count. In practice
  voter writes are rare enough that we accept this risk; if it becomes
  a problem we can switch to a `_doc.create()` of a single-event marker
  per voter-write (the function reads the latest voter doc and
  re-derives, idempotent).

### Local UI freshness

The Cloud Function runs asynchronously; the user may see the vote tip
linger for a second or two after their first vote completes. To avoid
this flicker, `UserCubit` listens for completed vote actions (via the
existing vote-action hook in `ProblemsCubit`, or by exposing a
`recordVoteCast()` method on `UserCubit`) and **optimistically** bumps
its local `votesCastCount` by 1. The `watchUserDoc` stream confirms
once Firestore catches up. If the function fails, the optimistic value
gets corrected by the next stream emission (which still shows the
pre-bump value).

## State layer

### Renames

The cubit now owns more than auth status — votes, view count, and a
session-start snapshot. The class name and file path change to reflect
that broader scope. `AuthRepository` and the `AuthStatus` enum keep their
names: the repository is genuinely an auth wrapper, and `AuthStatus`
names the auth *dimension* within `UserState`.

| Before                        | After                            |
|-------------------------------|----------------------------------|
| `apps/client/lib/auth/cubit/auth_cubit.dart`  | `user_cubit.dart`   |
| `apps/client/lib/auth/cubit/auth_state.dart`  | `user_state.dart`   |
| `class AuthCubit`             | `class UserCubit`                |
| `class AuthState`             | `class UserState`                |
| `apps/client/lib/auth/auth.dart` (barrel)     | updated exports     |

119 call-sites across 11 files get mechanical type renames.

### `UserState` fields

```dart
class UserState {
  const UserState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.remainingVotes,
    this.problemDetailsViewCount,       // null until user doc read
    this.votesCastCount,                // null until user doc read
    this.sessionStartLastActiveAt,      // null until first snapshot
  });

  final AuthStatus status;
  final String? userId;
  final int? remainingVotes;
  final int? problemDetailsViewCount;
  final int? votesCastCount;
  final DateTime? sessionStartLastActiveAt;

  /// `null` while loading, otherwise the static gap captured at sign-in.
  int? get _daysSinceLastSession {
    final snap = sessionStartLastActiveAt;
    if (snap == null) return null;
    return DateTime.now().difference(snap).inDays;
  }

  bool get needsVoteHint {
    final count = votesCastCount;
    final days = _daysSinceLastSession;
    if (count == null || days == null) return false;
    return count <= days;
  }

  bool get needsDoubleTapHint {
    final count = problemDetailsViewCount;
    final days = _daysSinceLastSession;
    if (count == null || days == null) return false;
    return count <= days;
  }

  // copyWith extended for the three new fields...
}
```

All three new fields reset to `null` on sign-out. Both `needs*Hint`
getters return `false` while loading — no flicker during the first
frames where the user doc hasn't streamed in yet.

### `UserCubit` snapshot logic

Today `_initUserVotes` calls `ensureUserDoc`, then `grantVotesAndTouch`,
then subscribes to votes. The new sequence:

1. `ensureUserDoc` returns the existing doc's `lastActiveAt` (or `now()`
   for a freshly-created doc). The cubit emits this once as
   `sessionStartLastActiveAt` and **never updates it** for the remainder
   of the session.
2. `grantVotesAndTouch` runs as before. The server-side `lastActiveAt`
   may move forward; our local snapshot stays anchored.
3. The `watchUserDoc` subscription projects each emitted `User` into the
   state: `votes` → `remainingVotes`, `problemDetailsViewCount` →
   `problemDetailsViewCount`, `votesCastCount` → `votesCastCount`. The
   streamed `lastActiveAt` is **ignored** (snapshot is frozen by step 1).

This means `daysSinceLastSession` is a static "how big was the gap before
they came back," computed once at sign-in and frozen until sign-out.
Mid-session double-taps can flip `needsDoubleTapHint` from `true` to
`false` reactively; they never push it back to `true`.

## UI layer

### l10n

Two changes across all 24 ARB files:

- Rename `doubleTapHintToast` → `doubleTapHint` (same string now serves
  both the banner and the toast).
- Add `voteHint` — English text: *"Tap the up-arrow chip beside a problem
  to vote for it."* (Exact wording subject to translation; placeholder
  used here.)

### Banner

`_HintBanner` (private widget in `problems_page.dart`) takes a `message`
string and renders the existing orange/indigo palette. Thin wrappers:
`_SignInHintBanner`, `_VoteHintBanner`, `_DoubleTapHintBanner` pick the
l10n key.

Body `Column` becomes (sketch):

```dart
BlocBuilder<UserCubit, UserState>(
  builder: (context, userState) {
    final authed = userState.status == AuthStatus.authenticated;

    final Widget? hint;
    if (userState.status == AuthStatus.unauthenticated) {
      hint = const _SignInHintBanner();
    } else if (authed && userState.needsVoteHint) {
      hint = const _VoteHintBanner();
    } else if (authed && userState.needsDoubleTapHint) {
      hint = const _DoubleTapHintBanner();
    } else {
      hint = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hint != null) hint,
        if (authed)
          BlocBuilder<GeoscopeCubit, GeoscopeState>(
            builder: (context, geoState) => AddProblemRow(...),
          ),
      ],
    );
  },
),
```

Priority order is enforced by the `if/else if` ladder: vote hint comes
before double-tap, matching "between sign-in and double-tap" from the
goals.

### Toast

`_ProblemsPageCoordinator._maybeShowDoubleTapToast` gains one gate:

```dart
if (!context.read<UserCubit>().state.needsDoubleTapHint) return;
```

One coherent "do they need this hint?" predicate gates both surfaces.

### Double-tap → increment

`ProblemReadTile` currently inlines `onDoubleTap: () => context.push(...)`.
Replace with a `final VoidCallback? onViewDetails` prop. `ProblemsView`
wires it as:

```dart
onViewDetails: () {
  final userId = context.read<UserCubit>().state.userId;
  if (userId != null) {
    unawaited(
      context.read<FirestoreRepository>()
        .incrementProblemDetailsViewCount(userId),
    );
  }
  context.push('/problems/${problem.id}');
},
```

Fire-and-forget: navigation does not block on the write. Anonymous users
skip the increment (no user doc to update), which is correct — the hint
logic only applies post-sign-in.

### Vote → counter increment

No change to the client-side vote write. `votesCastCount` updates are
materialized server-side by the Cloud Function (see **Cloud Function:
votesCastCount materialization**). The cubit performs an optimistic
local bump on a successful vote action so the UI graduates instantly
without waiting for the function's round-trip.

## Testing

Mirrors existing patterns in the codebase.

1. **`apps/server/e2e/firestore_rules_e2e_test.dart`** — new cases:
   - `problemDetailsViewCount` increment: (a) `+1` with `lastActiveAt`
     succeeds for the doc owner; (b) `+2` rejected; (c) increment with
     `votes` change in the same write rejected; (d) increment without auth
     rejected; (e) create with `problemDetailsViewCount: 0` succeeds,
     with `!= 0` rejected.
   - `votesCastCount` create-time check: (f) create with
     `votesCastCount: 0` succeeds, with `!= 0` rejected. (No rule
     change to update branches for this field — the function writes it
     via admin SDK.)
   - `votesCastCount` direct-write rejection: (g) a client attempting
     `update({votesCastCount: anything})` outside of any existing
     branch is rejected, confirming only the function (via admin
     bypass) can write it.
2. **`apps/client/test/services/firestore_repository_test.dart`** —
   round-trip tests for both new fields:
   (a) `ensureUserDoc` writes both as `0` on the wire (write-side drop
   catcher); (b) `_docToUser` reads back seeded non-zero values for both
   (read-side drop catcher); (c) `incrementProblemDetailsViewCount`
   advances `problemDetailsViewCount`.
3. **`functions/src/triggers/vote.test.ts`** (or sibling file
   matching the existing TS test convention) — for the new function:
   (a) voter-create with `votes: 1` increments `votesCastCount` by 1;
   (b) voter-update from `votes: 3 → 5` increments by 2;
   (c) voter-update with no votes change is a no-op;
   (d) voter-delete is a no-op (monotonic);
   (e) voter-update where `votes` decreased is a no-op.
4. **`apps/client/test/auth/cubit/user_cubit_test.dart`** (renamed file) —
   (a) `sessionStartLastActiveAt` is emitted from the existing doc's
   `lastActiveAt` on first read; (b) subsequent stream emissions of
   `lastActiveAt` do **not** advance the snapshot;
   (c) `problemDetailsViewCount` and `votesCastCount` reflect the stream;
   (d) the optimistic-bump hook advances local `votesCastCount` after a
   successful vote, and is corrected by the subsequent stream emission
   if the function lags.
5. **`apps/client/test/problems/view/problems_page_test.dart`** —
   (a) banner shows sign-in tip when unauthenticated;
   (b) banner shows vote tip when authenticated, `needsVoteHint == true`;
   (c) banner shows double-tap tip when authed, vote graduated, and
   `needsDoubleTapHint == true`; (d) banner shows nothing in the
   post-graduation state; (e) `AddProblemRow` renders below whichever
   banner is active; (f) double-tap fires
   `incrementProblemDetailsViewCount` and navigates; (g) toast suppression
   respects `needsDoubleTapHint`; (h) priority order is enforced — when
   both `needsVoteHint` and `needsDoubleTapHint` are true, the vote tip
   wins.

## Migration

Existing user docs need `votesCastCount` populated from their actual
voting history. A user who's cast 12 votes over the years should land
with `votesCastCount: 12`, not `0` — otherwise they'll see the vote tip
on next launch despite obviously knowing how to vote.

The data is recoverable: each existing vote is recorded in a
`problems/{problemId}/voters/{userId}` subcollection doc whose `votes`
field counts how many times that user voted for that problem. The sum
across the user's `voters` docs is exactly their lifetime vote count.

### Backfill script

A one-shot Dart script under `tool/backfill_votes_cast_count.dart`:

1. Authenticates via Application Default Credentials (same pattern as the
   Dart Frog server) — this **bypasses Firestore rules**, which is what
   we want, because none of the rules' update branches permit writing an
   arbitrary `votesCastCount` value (only `+1` from a vote write).
2. Iterates `users/`:
   - For each `userId`, runs the collection-group query
     `collectionGroup('voters').where('uid', isEqualTo: userId).get()`.
   - Sums the `votes` field across the returned docs (each represents one
     problem the user voted on, with a per-problem vote count).
   - Writes `users/{userId}.votesCastCount = sum`. Idempotent — re-runs
     write the same value.
3. Logs progress; exits non-zero on any per-user failure (so an
   interrupted run can be resumed by re-running it).

The collection-group query requires an index entry in
`firestore.indexes.json`:

```json
{
  "collectionGroup": "voters",
  "queryScope": "COLLECTION_GROUP",
  "fields": [{ "fieldPath": "uid", "order": "ASCENDING" }]
}
```

The index is **only used by the backfill** — the app itself never runs
this query at runtime (it relies on the `votesCastCount` field after
backfill). We could remove the index post-migration to save Firestore
costs, but the cost of a single-field collection-group index on the
existing `voters` corpus is negligible, so we keep it for ops
flexibility.

### Deployment order

To minimize race windows between the backfill and live writes:

1. **Deploy `firestore.rules`** with the new `problemDetailsViewCount`
   increment branch and the optional zero-init checks in the create
   branch. (No change to the vote-decrement branch.)
2. **Deploy `firestore.indexes.json`** (the new collection-group index
   on `voters.uid`).
3. **Run `tool/backfill_votes_cast_count.dart`**. At this point no
   process — neither old clients nor the (not-yet-deployed) Cloud
   Function — is writing `votesCastCount`. The backfill is the sole
   writer.
4. **Deploy the Cloud Function** (`onVoterWrittenForVotesCastCount`).
   From this point forward, every voter doc write produces a matching
   `votesCastCount` increment.
5. **Deploy the new client.** New binaries read `votesCastCount` and
   perform the optimistic local bump; the existing vote-write path is
   unchanged, so even ungraded users get correct graduation behavior
   from step 4 onward.

Race window: between steps 3 and 4, votes cast by old clients write
voter docs but the function isn't deployed yet to update
`votesCastCount`. Those votes are missed by the counter. Mitigation
options:

- Run the backfill again after step 4 to recover. (Idempotent —
  re-running writes computed values that incorporate the gap-period
  voter writes.)
- Schedule steps 3 and 4 close together during a low-traffic window.

Either is acceptable; a few users' counts being off by 1–2 won't
meaningfully affect tip graduation.

### Testing the backfill

`tool/backfill_votes_cast_count_test.dart` (unit test):

- Seed an in-memory Firestore (or use `fake_cloud_firestore`) with a few
  users and a varied voter-doc topology (some users with 0 votes, some
  with multi-vote entries across multiple problems).
- Run the backfill logic against the fake.
- Assert each user's `votesCastCount` matches the expected sum.

Manual verification against a staging Firestore is the integration check
(the backfill is too I/O-shaped for an emulator e2e test to add much
beyond the unit test).



- **Wire-shape gap on create.** Both new fields have freezed `@Default(0)`.
  Per the CLAUDE.md hide-problems incident, defaults don't apply to
  hand-built `.set()` maps. Mitigation: explicit field-stamps in
  `ensureUserDoc` for both fields, rules check on create, round-trip
  tests (1e/1f + 2a). Note: `ensureUserDoc` only runs for *new* user
  docs; existing users get `votesCastCount` from the backfill (see
  **Migration**).
- **Backfill drift.** If the backfill is run while live clients are
  voting (deployment-order violation), a few `+1` increments may race
  with the backfill's `set`. Mitigation is procedural (deployment
  order documented in **Migration**) rather than coded. Worst case is
  an off-by-one count for users active during the deploy gap, which
  self-heals on subsequent votes.
- **Read-side field drop.** `_docToUser` is hand-rolled. Mitigation:
  explicit field-reads with `?? 0` for both new fields, round-trip
  tests (2b).
- **Cloud Function lag.** The function runs after the client commits
  the vote write. There's a sub-second window where the cubit sees the
  voter doc updated but `votesCastCount` not yet. Mitigation: the
  cubit optimistically bumps `votesCastCount` locally on a successful
  vote action; the stream emission corrects it once the function
  completes. Covered by test 4d.
- **Cloud Function at-least-once delivery.** Functions can fire more
  than once for the same write. A duplicated invocation would
  double-count. In practice voter writes are rare per-user and the
  graduation rule is forgiving (`<= daysSince`), so a small
  over-count just means earlier graduation. Acceptable; documented in
  the Cloud Function section.
- **`daysSinceLastSession` semantics during a long-running session.**
  `lastActiveAt` updates server-side from `grantVotesAndTouch`, vote
  writes, and other paths. The local snapshot is captured *before* those
  touches and frozen for the session, so the banner doesn't flap as the
  session ages. Documented in the cubit code and covered by test 4b.
- **Anonymous user double-tap.** Anonymous users have no user doc; the
  callback no-ops the write. Test (5f) covers signed-in; anonymous case
  is exercised by the existing tap-region tests.

## Out of scope (deferred follow-ups)

- A more granular tip ledger (per-tip view counts, dismissal timestamps).
- Server-side aggregated graduation thresholds (e.g., "after 30s active
  reading time"). The current count-vs-days heuristic is sufficient.
- A11y review of the banner (color contrast, screen-reader semantics).
  The existing toast palette is already shipped; banner inherits it
  unchanged.
