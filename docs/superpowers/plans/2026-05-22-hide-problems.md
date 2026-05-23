# Hide Problems Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let problem owners flip a `hidden` bool that suppresses their problem from the listing query for all viewers, while keeping the detail page reachable by direct URL and showing an owner-action ("Show in listing") or passive viewer banner accordingly.

**Architecture:** Single new field `hidden` on `Problem`, server-side filtered out of the listing query via Firestore composite index. Owner-only `hidden` writes enforced by a dedicated rules branch; existing "Full problem update" branch guarded so it cannot smuggle a `hidden` change. Backfill script writes `hidden: false` to existing docs before the new client ships. UI surfaces a hide button or banner conditional on viewer-is-owner and the doc's `hidden` value.

**Tech Stack:** Dart/Flutter monorepo (Melos workspace), Freezed + json_serializable, BLoC/`flutter_bloc`, cloud_firestore, Firebase Auth, Dart Frog server, googleapis Firestore client, fake_cloud_firestore for unit tests, real Auth+Firestore emulator for rules e2e tests, very_good_test runner, mocktail, bloc_test.

**Spec:** [docs/superpowers/specs/2026-05-22-hide-problems-design.md](../specs/2026-05-22-hide-problems-design.md)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `packages/shared/lib/src/models/problem.dart` | Modify | Add `hidden` field |
| `packages/shared/lib/src/models/problem.freezed.dart` | Regenerate | (build_runner output) |
| `packages/shared/lib/src/models/problem.g.dart` | Regenerate | (build_runner output) |
| `firestore.indexes.json` | Modify | Add new composite index; drop now-unused index |
| `firestore.rules` | Modify | Add hide-toggle update branch; guard full-update branch |
| `apps/server/e2e/firestore_rules_e2e_test.dart` | Modify | New group: `firestore.rules — problem hidden flag` |
| `apps/server/tool/backfill_hidden.dart` | Create | One-off script: stamp `hidden: false` on every existing doc missing the field |
| `apps/server/tool/README.md` | Create | Document how/when to run the script |
| `apps/client/lib/services/firestore_repository.dart` | Modify | Add `hidden == false` to `_geoscopedQuery`; new `setHidden` method |
| `apps/client/test/services/firestore_repository_test.dart` | Modify | Tests for `setHidden` and the new query filter |
| `apps/client/lib/problems/cubit/problems_cubit.dart` | Modify | New `setHidden` cubit method |
| `apps/client/test/problems/cubit/problems_cubit_test.dart` | Modify | Tests for the new cubit method |
| `apps/client/lib/problems/view/problem_detail_page.dart` | Modify | Hide button (owner) + banner widget (owner + viewer variants) |
| `apps/client/test/problems/view/problem_detail_page_test.dart` | Modify | Widget tests for button/banner visibility |
| `apps/client/lib/l10n/arb/app_en.arb` | Modify | 6 new keys with `@key` metadata |
| `apps/client/lib/l10n/arb/app_{ar,bn,de,es,fa,fr,hi,id,ja,ko,mr,pa,pt,ru,sw,ta,te,th,tr,uk,ur,vi,zh}.arb` | Modify | Translated values for the 6 keys (23 locales) |

The `pre-commit` hook automatically syncs `apps/client/lib/l10n/arb/` to `functions/l10n/`. Don't hand-edit `functions/l10n/*.arb` — your commits will include those files automatically.

---

## Task 1: Add `hidden` field to the Problem model

**Files:**
- Modify: `packages/shared/lib/src/models/problem.dart`
- Regenerate: `packages/shared/lib/src/models/problem.freezed.dart`
- Regenerate: `packages/shared/lib/src/models/problem.g.dart`

- [ ] **Step 1: Add the field**

Edit `packages/shared/lib/src/models/problem.dart`. After the `@Default(false) bool solved,` line (currently line 22) insert:

```dart
    @Default(false) bool hidden,
```

Final hand-written model class:

```dart
const factory Problem({
  required String id,
  required String description,
  required DateTime createdAt,
  required DateTime lastUpdatedAt,
  required String ownerId,
  @Default('') String goal,
  @Default('/') String geoscope,
  String? lang,
  @Default(1) int votes,
  @Default([]) List<String> complaints,
  @Default(false) bool solved,
  @Default(false) bool hidden,
  @Default(1) int version,
  // Source ProblemRevision that inspired this problem (set when forked).
  // ... (existing inspoProblemId/inspoVersion/linkedProblemIds/typedLinks unchanged)
  String? inspoProblemId,
  int? inspoVersion,
  @Default([]) List<String> linkedProblemIds,
  @Default(<ProblemLink>[]) List<ProblemLink> typedLinks,
}) = _Problem;
```

- [ ] **Step 2: Regenerate freezed/json files**

Run from repo root: `melos gen`

Expected: regenerates `problem.freezed.dart` and `problem.g.dart` (and other packages' codegen, no-op there). No errors.

- [ ] **Step 3: Format**

Run: `melos format`

Expected: no changes or trivially formats the freezed output.

- [ ] **Step 4: Analyze**

Run: `flutter analyze apps packages`

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add packages/shared/lib/src/models/problem.dart \
        packages/shared/lib/src/models/problem.freezed.dart \
        packages/shared/lib/src/models/problem.g.dart
git commit -m "feat(shared): add hidden flag to Problem model"
```

---

## Task 2: Update Firestore composite indexes

**Files:**
- Modify: `firestore.indexes.json`

- [ ] **Step 1: Replace the geoscope+solved index with geoscope+solved+hidden**

Open `firestore.indexes.json`. Replace the third index object (the existing `(geoscope, solved, votes desc, __name__)` index) with:

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

Leave the other two indexes alone.

- [ ] **Step 2: Verify the JSON parses**

Run: `python3 -c "import json; json.load(open('firestore.indexes.json'))"`

Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add firestore.indexes.json
git commit -m "feat(firestore): add geoscope+solved+hidden composite index"
```

> The new index must be deployed (`firebase deploy --only firestore:indexes`) and built *before* the new client ships. Deployment is a manual rollout step captured in Task 13.

---

## Task 3: Write failing e2e rules tests for hidden

**Files:**
- Modify: `apps/server/e2e/firestore_rules_e2e_test.dart`

These tests will fail until Task 4 updates `firestore.rules` — that's the TDD red step.

- [ ] **Step 1: Add a second-user helper and the `hidden` test group**

At the bottom of `main()` in `apps/server/e2e/firestore_rules_e2e_test.dart`, after the last existing `group(...)` block but before the file's closing brace, add:

```dart
  group('firestore.rules — problem hidden flag', () {
    // Mint a second authed user so we can exercise "non-owner cannot set
    // hidden". Done lazily inside this group (not setUpAll) to keep the
    // top-level setup focused.
    Future<({String uid, String idToken})> signUpSecondUser() async {
      final signUpUrl = Uri.parse(
        'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signUp'
        '?key=fake-api-key',
      );
      final resp = await client.post(
        signUpUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'returnSecureToken': true}),
      );
      if (resp.statusCode != 200) {
        fail('second signUp failed: ${resp.statusCode} ${resp.body}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (
        uid: body['localId'] as String,
        idToken: body['idToken'] as String,
      );
    }

    test('owner: can set hidden=true on their own problem', () async {
      await seedProblem('h1');
      final resp = await patchProblem(
        'h1',
        {'hidden': {'booleanValue': true}},
        updateMask: ['hidden'],
      );
      expect(resp.statusCode, 200, reason: resp.body);
    });

    test('owner: can set hidden=false (unhide)', () async {
      await seedProblem('h2');
      // First hide it.
      final hide = await patchProblem(
        'h2',
        {'hidden': {'booleanValue': true}},
        updateMask: ['hidden'],
      );
      expect(hide.statusCode, 200, reason: hide.body);
      // Then unhide.
      final unhide = await patchProblem(
        'h2',
        {'hidden': {'booleanValue': false}},
        updateMask: ['hidden'],
      );
      expect(unhide.statusCode, 200, reason: unhide.body);
    });

    test('non-owner authed user cannot set hidden', () async {
      await seedProblem('h3');
      final other = await signUpSecondUser();

      final url = Uri.parse(
        '${docUri('problems/h3')}?updateMask.fieldPaths=hidden',
      );
      final resp = await client.patch(
        url,
        headers: {
          'Authorization': 'Bearer ${other.idToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fields': {'hidden': {'booleanValue': true}},
        }),
      );
      expect(
        resp.statusCode,
        403,
        reason: 'Expected 403 for non-owner hide write. Got '
            '${resp.statusCode}: ${resp.body}',
      );
    });

    test('unauthed write setting hidden is rejected', () async {
      await seedProblem('h4');
      final resp = await patchProblem(
        'h4',
        {'hidden': {'booleanValue': true}},
        updateMask: ['hidden'],
        auth: false,
      );
      expect(resp.statusCode, 403, reason: resp.body);
    });

    test('hide-toggle write that also changes description is rejected', () async {
      await seedProblem('h5');
      // The hide-toggle branch requires affectedKeys().hasOnly(['hidden']),
      // so a write that also touches description must fail through that
      // branch. The full-update branch should also reject it (the new
      // guard forbids hidden changes there). Net: 403.
      final resp = await patchProblem(
        'h5',
        {
          'hidden': {'booleanValue': true},
          'description': sVal('changed description'),
        },
        updateMask: ['hidden', 'description'],
      );
      expect(resp.statusCode, 403, reason: resp.body);
    });

    test('full-update write that flips hidden is rejected', () async {
      await seedProblem('h6');
      // Send a full-update-shaped payload that also flips hidden. The
      // full-update branch will be guarded by hidden==get('hidden', false),
      // so this must fail.
      final now = DateTime.now().toUtc();
      final resp = await patchProblem(
        'h6',
        {
          'description': sVal('updated'),
          'goal': sVal(''),
          'geoscope': sVal('/'),
          'votes': iVal(1),
          'solved': {'booleanValue': false},
          'version': iVal(2),
          'lastUpdatedAt': tsVal(now),
          'hidden': {'booleanValue': true},
        },
        updateMask: [
          'description', 'goal', 'geoscope', 'votes', 'solved',
          'version', 'lastUpdatedAt', 'hidden',
        ],
      );
      expect(resp.statusCode, 403, reason: resp.body);
    });
  });
```

- [ ] **Step 2: Start the emulators (in a separate terminal)**

```bash
firebase emulators:start --only auth,firestore
```

Leave it running.

- [ ] **Step 3: Run the new tests and confirm they fail**

From repo root (the tests use relative paths so you must be at the repo root):

```bash
dart test apps/server/e2e/firestore_rules_e2e_test.dart \
  --tags e2e \
  -N "firestore.rules — problem hidden flag"
```

Expected: tests FAIL because the rules haven't been changed yet. The owner-can-hide tests will likely fail with 403 (no rule branch permits the write), and the rejection tests may pass or fail depending on which existing branch the emulator happens to evaluate first. **The point of this step is to confirm the test code itself is wired up and being executed.** If tests don't run at all (compile errors, "no tests matched"), fix that before proceeding.

- [ ] **Step 4: Commit**

```bash
git add apps/server/e2e/firestore_rules_e2e_test.dart
git commit -m "test(e2e): rules tests for problem hidden flag (red)"
```

---

## Task 4: Update firestore.rules to make the hidden tests pass

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the hide-toggle branch and guard the full-update branch**

Open `firestore.rules`. Inside `match /problems/{problemId}`, find the `allow update: if` block (starts around line 20).

After the existing "Problem linking / clustering update" branch (the one that uses `affectedKeys().hasOnly(['linkedProblemIds', 'typedLinks'])`), and before the final "Full problem update" branch, insert a new `||` clause:

```
        ||
        // Hide / unhide. Only the owner may flip `hidden`, and only
        // `hidden` may change in the write. A description/goal edit
        // that also wants to change `hidden` must use two writes.
        (
          request.auth != null
          && request.auth.uid == resource.data.ownerId
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['hidden'])
          && request.resource.data.hidden is bool
        )
```

Then, inside the "Full problem update" branch (the final clause), add a final guard so that branch cannot smuggle a hidden change:

```
          && request.resource.data.hidden == resource.data.get('hidden', false)
```

The `resource.data.get('hidden', false)` form treats docs that haven't been backfilled yet as `hidden: false`, so an existing doc without the field can still be edited via the full-update path so long as the new state of `hidden` also reads as `false`.

For reference, the final shape of the full-update branch becomes:

```
        // Full problem update
        (
          request.resource.data.description is string
          && request.resource.data.description.size() > 0
          && request.resource.data.description.size() <= 80
          && request.resource.data.geoscope is string
          && request.resource.data.geoscope.size() > 0
          && request.resource.data.geoscope.size() <= 72
          && (request.resource.data.geoscope == resource.data.geoscope
              || (request.auth != null && request.auth.uid == resource.data.ownerId))
          && request.resource.data.votes is int
          && request.resource.data.votes >= 0
          && request.resource.data.solved is bool
          && request.resource.data.version is int
          && request.resource.data.version > resource.data.version
          && request.resource.data.hidden == resource.data.get('hidden', false)
        );
```

- [ ] **Step 2: Re-run the failing tests**

The e2e test pushes the new rules into the emulator at `setUpAll` time, so no emulator restart is needed.

```bash
dart test apps/server/e2e/firestore_rules_e2e_test.dart \
  --tags e2e \
  -N "firestore.rules — problem hidden flag"
```

Expected: all 6 tests in the new group PASS.

- [ ] **Step 3: Run the entire rules-test file to confirm no regressions**

```bash
dart test apps/server/e2e/firestore_rules_e2e_test.dart --tags e2e
```

Expected: every test passes — including the pre-existing typed-link cases.

- [ ] **Step 4: Commit**

```bash
git add firestore.rules
git commit -m "feat(rules): gate hidden writes to the owner; block via full-update branch"
```

---

## Task 5: Backfill script for existing problems

**Files:**
- Create: `apps/server/tool/backfill_hidden.dart`
- Create: `apps/server/tool/README.md`

The new client's listing query filters `where('hidden', isEqualTo: false)`, which excludes docs missing the field. This script idempotently stamps `hidden: false` onto every existing doc that lacks it.

- [ ] **Step 1: Confirm the directory and a googleapis usage example**

Run:
```bash
ls apps/server/tool 2>/dev/null || mkdir apps/server/tool
```

Then look at the existing `Db` class for the auth + project pattern:
```bash
grep -n "FirestoreApi\|fromApplicationDefaultCredentials\|projectId\|FieldFilter\|RunQuery" apps/server/lib/src/db.dart | head -20
```

This shows you which `googleapis` types and authentication path the server uses; mirror that in the script so the script honours the same `GOOGLE_CLOUD_PROJECT` env var and ADCs.

- [ ] **Step 2: Write the script**

Create `apps/server/tool/backfill_hidden.dart`:

```dart
// One-off backfill: stamps `hidden: false` onto every `problems/*` doc
// that does not have the field set. Idempotent — safe to re-run.
//
// Why: when the client's listing query filters `where('hidden',
// isEqualTo: false)`, Firestore excludes docs where the field is missing.
// Without this backfill, every existing problem would vanish from the
// list on the day the new client ships.
//
// Run from `apps/server/`:
//   gcloud auth application-default login   # one-time
//   export GOOGLE_CLOUD_PROJECT=votasq      # or votasq-dev for staging
//   dart run tool/backfill_hidden.dart [--dry-run]
//
// The script lists all `problems` docs page by page, and for each doc
// that has no `hidden` field, issues an update that sets `hidden: false`
// with an updateMask scoped to the `hidden` field only (so the write
// passes through the new hide-toggle rules branch even when the script
// runs as a regular user — though it actually runs with Application
// Default Credentials, which bypass rules).

import 'dart:io';

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart' as auth_io;

const _scopes = <String>[FirestoreApi.datastoreScope];
const _pageSize = 200;

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final projectId = Platform.environment['GOOGLE_CLOUD_PROJECT'];
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('GOOGLE_CLOUD_PROJECT must be set.');
    exit(2);
  }

  final authClient = await auth_io.clientViaApplicationDefaultCredentials(
    scopes: _scopes,
  );
  final api = FirestoreApi(authClient);

  final parent = 'projects/$projectId/databases/(default)/documents';
  String? pageToken;
  var scanned = 0;
  var patched = 0;

  try {
    do {
      final page = await api.projects.databases.documents.list(
        parent,
        'problems',
        pageSize: _pageSize,
        pageToken: pageToken,
      );

      for (final doc in page.documents ?? const <Document>[]) {
        scanned++;
        final fields = doc.fields ?? const <String, Value>{};
        if (fields.containsKey('hidden')) continue;

        if (dryRun) {
          patched++;
          continue;
        }

        await api.projects.databases.documents.patch(
          Document(fields: {'hidden': Value(booleanValue: false)}),
          doc.name!,
          updateMask_fieldPaths: ['hidden'],
        );
        patched++;
      }

      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
  } finally {
    authClient.close();
  }

  stdout.writeln(
    'scanned=$scanned patched=$patched dryRun=$dryRun project=$projectId',
  );
}
```

- [ ] **Step 3: Write the README**

Create `apps/server/tool/README.md`:

```markdown
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
```

- [ ] **Step 4: Verify the script compiles**

```bash
cd apps/server && dart analyze tool/backfill_hidden.dart && cd ../..
```

Expected: no issues.

- [ ] **Step 5: Smoke-test against the local Firestore emulator**

With the emulator running from Task 3 (or restart it):

```bash
firebase emulators:start --only auth,firestore   # if not already running
```

Seed a couple of docs without `hidden` via the emulator REST API (or reuse an existing test fixture script if one exists). Then in another terminal:

```bash
cd apps/server
export GOOGLE_CLOUD_PROJECT=votasq-rules-test
export FIRESTORE_EMULATOR_HOST=localhost:8081
dart run tool/backfill_hidden.dart --dry-run
dart run tool/backfill_hidden.dart
dart run tool/backfill_hidden.dart   # second run should patch 0 (idempotent)
cd ../..
```

Expected: first run reports `patched > 0`; second run reports `patched=0`. Confirm by inspecting one of the seeded docs via the emulator UI at `http://localhost:4000/firestore` — it should now have `hidden: false`.

If you don't have a quick way to seed pre-backfill docs, skip the live emulator test and rely on the rules-tests in Task 4 plus a visual review of the script. Document the skip in the commit message.

- [ ] **Step 6: Commit**

```bash
git add apps/server/tool/backfill_hidden.dart apps/server/tool/README.md
git commit -m "feat(server): one-off backfill for hidden:false on existing problems"
```

---

## Task 6: Client repository — query filter + `setHidden`

**Files:**
- Modify: `apps/client/lib/services/firestore_repository.dart`
- Modify: `apps/client/test/services/firestore_repository_test.dart`

- [ ] **Step 1: Write the failing repo tests**

In `apps/client/test/services/firestore_repository_test.dart`, find the existing `group('addComplaint', ...)` block. Immediately after that group's closing `});`, add:

```dart
    group('setHidden', () {
      test('sets hidden=true on the doc', () async {
        await seedProblem(id: 'h1');
        await repo.setHidden(problemId: 'h1', hidden: true);
        final doc = await firestore.collection('problems').doc('h1').get();
        expect(doc.data()!['hidden'], isTrue);
      });

      test('sets hidden=false on the doc', () async {
        await seedProblem(id: 'h2');
        await repo.setHidden(problemId: 'h2', hidden: true);
        await repo.setHidden(problemId: 'h2', hidden: false);
        final doc = await firestore.collection('problems').doc('h2').get();
        expect(doc.data()!['hidden'], isFalse);
      });

      test('does not touch other fields', () async {
        await seedProblem(id: 'h3', description: 'untouched');
        await repo.setHidden(problemId: 'h3', hidden: true);
        final doc = await firestore.collection('problems').doc('h3').get();
        expect(doc.data()!['description'], 'untouched');
      });
    });

    group('watchProblems / getProblems hidden filter', () {
      test('excludes problems with hidden=true', () async {
        await seedProblem(id: 'visible');
        await seedProblem(id: 'hidden');
        await firestore
            .collection('problems')
            .doc('hidden')
            .update({'hidden': true});

        final result = await repo.getProblems(geoscope: '/');
        expect(result.problems.map((p) => p.id), ['visible']);
      });

      test('includes problems with hidden=false', () async {
        await seedProblem(id: 'v1');
        await firestore
            .collection('problems')
            .doc('v1')
            .update({'hidden': false});

        final result = await repo.getProblems(geoscope: '/');
        expect(result.problems.map((p) => p.id), ['v1']);
      });
    });
```

Also update the `seedProblem` helper (currently at lines 110–131) to write `hidden: false` by default so seeded docs match the new query filter. Add a `hidden` parameter for test flexibility:

```dart
    Future<void> seedProblem({
      required String id,
      String description = 'Test problem description',
      String goal = '',
      String ownerId = 'owner1',
      String geoscope = '/',
      int votes = 1,
      bool solved = false,
      bool hidden = false,
    }) async {
      final now = DateTime.now().toUtc();
      await firestore.collection('problems').doc(id).set({
        'description': description,
        'goal': goal,
        'ownerId': ownerId,
        'geoscope': geoscope,
        'votes': votes,
        'solved': solved,
        'hidden': hidden,
        'version': 1,
        'createdAt': now,
        'lastUpdatedAt': now,
      });
    }
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
cd apps/client
flutter test test/services/firestore_repository_test.dart \
  --plain-name "setHidden"
flutter test test/services/firestore_repository_test.dart \
  --plain-name "watchProblems / getProblems hidden filter"
cd ../..
```

Expected: `setHidden` tests fail because the method doesn't exist (compile error). The filter tests fail because the query doesn't filter `hidden` yet — both rows are returned.

- [ ] **Step 3: Implement the changes in `firestore_repository.dart`**

Edit `apps/client/lib/services/firestore_repository.dart`. Update `_geoscopedQuery` to add the `hidden` filter (current shape is at lines 55–59):

```dart
  /// Unsolved, non-hidden problems matching the given geoscope or any
  /// ancestor, ordered by votes DESC then doc ID ASC.
  Query<Map<String, dynamic>> _geoscopedQuery(String geoscope) => _problemsRef
      .where('geoscope', whereIn: geoscopeAncestors(geoscope))
      .where('solved', isEqualTo: false)
      .where('hidden', isEqualTo: false)
      .orderBy('votes', descending: true)
      .orderBy(FieldPath.documentId);
```

Add a new public method after the existing `vote` method (or in a similar slot — match the file's existing ordering):

```dart
  /// Owner-only single-field write that flips a problem's `hidden` flag.
  /// Targets just the one field so the rules' hide-toggle branch
  /// (`affectedKeys().hasOnly(['hidden'])`) matches the wire payload.
  Future<void> setHidden({
    required String problemId,
    required bool hidden,
  }) => _problemsRef.doc(problemId).update({'hidden': hidden});
```

- [ ] **Step 4: Run the repo tests and confirm they pass**

```bash
cd apps/client
flutter test test/services/firestore_repository_test.dart
cd ../..
```

Expected: all tests in this file pass, including the new groups.

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/services/firestore_repository.dart \
        apps/client/test/services/firestore_repository_test.dart
git commit -m "feat(client): filter hidden problems from listing; add setHidden"
```

---

## Task 7: Cubit — `setHidden` method + tests

**Files:**
- Modify: `apps/client/lib/problems/cubit/problems_cubit.dart`
- Modify: `apps/client/test/problems/cubit/problems_cubit_test.dart`

- [ ] **Step 1: Write the failing cubit tests**

In `apps/client/test/problems/cubit/problems_cubit_test.dart`, scroll to the end of the `group('ProblemsCubit', ...)` block. Immediately before the group's closing `});`, append:

```dart
    group('setHidden', () {
      blocTest<ProblemsCubit, ProblemsState>(
        'setHidden(true) calls repo and drops the problem from state',
        build: () {
          when(
            () => repo.setHidden(
              problemId: any(named: 'problemId'),
              hidden: any(named: 'hidden'),
            ),
          ).thenAnswer((_) async {});
          return ProblemsCubit(repo);
        },
        seed: () => ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(id: 'a'), _problem(id: 'b')],
        ),
        act: (cubit) => cubit.setHidden(
          problem: _problem(id: 'a'),
          hidden: true,
        ),
        expect: () => [
          isA<ProblemsState>().having(
            (s) => s.problems.map((p) => p.id).toList(),
            'problems ids',
            ['b'],
          ),
        ],
        verify: (_) {
          verify(
            () => repo.setHidden(problemId: 'a', hidden: true),
          ).called(1);
        },
      );

      blocTest<ProblemsCubit, ProblemsState>(
        'setHidden(false) calls repo and applies local update without dropping',
        build: () {
          when(
            () => repo.setHidden(
              problemId: any(named: 'problemId'),
              hidden: any(named: 'hidden'),
            ),
          ).thenAnswer((_) async {});
          return ProblemsCubit(repo);
        },
        seed: () => ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(id: 'a'), _problem(id: 'b')],
        ),
        act: (cubit) => cubit.setHidden(
          problem: _problem(id: 'a'),
          hidden: false,
        ),
        // The problem under id 'a' was already not-hidden in the local
        // state, so applyLocalUpdate emits a state with the same shape.
        expect: () => [
          isA<ProblemsState>().having(
            (s) => s.problems.map((p) => p.id).toList(),
            'problems ids',
            ['a', 'b'],
          ),
        ],
        verify: (_) {
          verify(
            () => repo.setHidden(problemId: 'a', hidden: false),
          ).called(1);
        },
      );

      blocTest<ProblemsCubit, ProblemsState>(
        'setHidden swallows repo errors',
        build: () {
          when(
            () => repo.setHidden(
              problemId: any(named: 'problemId'),
              hidden: any(named: 'hidden'),
            ),
          ).thenThrow(Exception('boom'));
          return ProblemsCubit(repo);
        },
        seed: () => ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(id: 'a')],
        ),
        act: (cubit) => cubit.setHidden(
          problem: _problem(id: 'a'),
          hidden: true,
        ),
        expect: () => <ProblemsState>[],
      );
    });
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
cd apps/client
flutter test test/problems/cubit/problems_cubit_test.dart \
  --plain-name "setHidden"
cd ../..
```

Expected: compile error / method not found — the cubit doesn't have `setHidden` yet.

- [ ] **Step 3: Implement `setHidden` on the cubit**

Edit `apps/client/lib/problems/cubit/problems_cubit.dart`. Add a new method after the existing `flagProblem` method:

```dart
  /// Toggle a problem's `hidden` flag (owner-only at the rules layer).
  /// On hide, optimistically drops the problem from the local list so a
  /// back-navigation to the listing doesn't briefly show the stale entry
  /// before the watch snapshot reconciles. On unhide, applies a local
  /// update if the problem is still in the visible page (the watch
  /// stream will refresh it independently).
  Future<void> setHidden({
    required Problem problem,
    required bool hidden,
  }) async {
    try {
      await _repo.setHidden(problemId: problem.id, hidden: hidden);
      if (hidden) {
        emit(
          state.copyWith(
            problems:
                state.problems.where((p) => p.id != problem.id).toList(),
          ),
        );
      } else {
        applyLocalUpdate(problem.copyWith(hidden: false));
      }
    } on Exception catch (e, st) {
      log('setHidden failed: $e', stackTrace: st);
    }
  }
```

- [ ] **Step 4: Run the cubit tests and confirm they pass**

```bash
cd apps/client
flutter test test/problems/cubit/problems_cubit_test.dart
cd ../..
```

Expected: all cubit tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/problems/cubit/problems_cubit.dart \
        apps/client/test/problems/cubit/problems_cubit_test.dart
git commit -m "feat(client): cubit setHidden with optimistic local removal"
```

---

## Task 8: Add l10n strings (English first, then 23 translations)

**Files:**
- Modify: `apps/client/lib/l10n/arb/app_en.arb` (plus `@key` metadata)
- Modify: `apps/client/lib/l10n/arb/app_{ar,bn,de,es,fa,fr,hi,id,ja,ko,mr,pa,pt,ru,sw,ta,te,th,tr,uk,ur,vi,zh}.arb`

The repo's policy (see `~/.claude/projects/-Users-adsouza-Code-votasq/memory/arb_translation_policy.md`) is that new l10n strings ship in all 24 locales, not English-only. The pre-commit hook syncs ARBs to `functions/l10n/` automatically.

- [ ] **Step 1: Add English strings to `app_en.arb`**

Add the following 6 keys (with `@key` description metadata) to `apps/client/lib/l10n/arb/app_en.arb`. Place them near other problem-detail strings (search for `"problemDetailPageTitle"` to find the cluster).

```json
"hideProblemButton": "Hide from listing",
"@hideProblemButton": {
  "description": "Label of the button on the problem detail page that hides the problem from the main listing. Only visible to the problem's owner when the problem is not yet hidden."
},
"unhideProblemButton": "Show in listing",
"@unhideProblemButton": {
  "description": "Label of the button on the problem detail page that unhides a previously hidden problem so it reappears in the main listing. Only visible to the problem's owner when the problem is currently hidden."
},
"problemHiddenOwnerBannerTitle": "This problem is hidden from the main listing.",
"@problemHiddenOwnerBannerTitle": {
  "description": "Banner title shown to the owner on the detail page of a problem they have hidden."
},
"problemHiddenOwnerBannerBody": "Nobody — including you — sees it on the listing. People can still reach it through direct links and notifications.",
"@problemHiddenOwnerBannerBody": {
  "description": "Banner body shown to the owner on the detail page of a hidden problem. Clarifies the consequences of hiding."
},
"problemHiddenViewerBannerTitle": "The owner has hidden this problem from the main listing.",
"@problemHiddenViewerBannerTitle": {
  "description": "Banner title shown to any non-owner viewer of a hidden problem's detail page."
},
"problemHiddenViewerBannerBody": "You can still see it here because you followed a direct link.",
"@problemHiddenViewerBannerBody": {
  "description": "Banner body shown to non-owner viewers of a hidden problem's detail page. Explains why they can still see the page."
}
```

- [ ] **Step 2: Translate each key into every other locale**

For each ARB file in `apps/client/lib/l10n/arb/app_*.arb` except `app_en.arb` (23 files in total: `ar, bn, de, es, fa, fr, hi, id, ja, ko, mr, pa, pt, ru, sw, ta, te, th, tr, uk, ur, vi, zh`), add the same 6 keys with appropriately-translated values. Do **not** include `@key` metadata in non-English ARBs (matches the existing convention — only `app_en.arb` carries descriptions).

Process per locale:

  1. Open the locale's ARB.
  2. Read 3–5 nearby keys to learn the register/tone for that locale (formal vs informal, contractions, punctuation, etc.).
  3. Translate the 6 keys consistent with that register. The English uses an em-dash; in locales where em-dashes are uncommon (e.g. Chinese, Japanese), substitute the locale-appropriate equivalent (e.g. a comma or a Japanese 「、」).
  4. Save.

Do NOT paste the English value as a placeholder.

If you are uncertain about a translation, generate a best-effort version and flag the locale in the commit message body. A native-speaker review pass can follow up; the build does not block on translation accuracy, only on key presence and ARB JSON validity.

- [ ] **Step 3: Verify ARB JSON validity**

```bash
for f in apps/client/lib/l10n/arb/app_*.arb; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" || echo "BROKEN: $f"
done
```

Expected: no `BROKEN` lines.

- [ ] **Step 4: Regenerate l10n bindings and verify analyze**

```bash
cd apps/client
flutter gen-l10n
flutter analyze
cd ../..
```

Expected: l10n generation succeeds; analyze reports no issues. If `flutter gen-l10n` complains that a key is missing from some locale, you skipped that file — go back and add it.

- [ ] **Step 5: Format**

```bash
melos format
```

- [ ] **Step 6: Commit**

The pre-commit hook will copy the ARB updates into `functions/l10n/`. Stage everything together:

```bash
git add apps/client/lib/l10n/arb/ functions/l10n/
git commit -m "$(cat <<'EOF'
feat(l10n): strings for problem hide / unhide UI in all 24 locales

Adds hideProblemButton, unhideProblemButton, and four banner strings
covering the owner-facing and viewer-facing variants. Non-English
translations are LLM-generated; native-speaker review welcome.
EOF
)"
```

---

## Task 9: Detail page UI — hide button + banner widget

**Files:**
- Modify: `apps/client/lib/problems/view/problem_detail_page.dart`
- Modify: `apps/client/test/problems/view/problem_detail_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Open `apps/client/test/problems/view/problem_detail_page_test.dart`. Find the existing `testWidgets('shows read-only view for non-owner', ...)` test (around line 162) and the `testWidgets('shows editable view for owner', ...)` test (around line 178). Append a new `group('hidden flag', () { ... })` after the existing visibility tests in the same containing group.

```dart
    group('hidden flag', () {
      testWidgets('owner sees Hide button when problem is not hidden', (
        tester,
      ) async {
        await _pumpDetail(
          tester,
          problem: _problem(id: 'p1', hidden: false),
          userId: 'owner1',
        );
        expect(
          find.byKey(const Key('hideProblemButton')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('hiddenBanner')), findsNothing);
      });

      testWidgets('owner sees owner banner and Show-in-listing when hidden', (
        tester,
      ) async {
        await _pumpDetail(
          tester,
          problem: _problem(id: 'p1', hidden: true),
          userId: 'owner1',
        );
        expect(
          find.byKey(const Key('hiddenBanner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('unhideProblemButton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('hideProblemButton')),
          findsNothing,
        );
      });

      testWidgets('non-owner sees viewer banner only, no buttons', (
        tester,
      ) async {
        await _pumpDetail(
          tester,
          problem: _problem(id: 'p1', hidden: true),
          userId: 'other-user',
        );
        expect(
          find.byKey(const Key('hiddenBanner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('hideProblemButton')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('unhideProblemButton')),
          findsNothing,
        );
      });

      testWidgets('non-owner sees no banner when problem is not hidden', (
        tester,
      ) async {
        await _pumpDetail(
          tester,
          problem: _problem(id: 'p1', hidden: false),
          userId: 'other-user',
        );
        expect(find.byKey(const Key('hiddenBanner')), findsNothing);
      });

      testWidgets('tapping Hide calls cubit.setHidden(problem, true)', (
        tester,
      ) async {
        when(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: any(named: 'hidden'),
          ),
        ).thenAnswer((_) async {});

        await _pumpDetail(
          tester,
          problem: _problem(id: 'p1', hidden: false),
          userId: 'owner1',
        );
        await tester.tap(find.byKey(const Key('hideProblemButton')));
        await tester.pumpAndSettle();
        verify(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: true,
          ),
        ).called(1);
      });

      testWidgets('tapping Show-in-listing calls cubit.setHidden(false)', (
        tester,
      ) async {
        when(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: any(named: 'hidden'),
          ),
        ).thenAnswer((_) async {});

        await _pumpDetail(
          tester,
          problem: _problem(id: 'p1', hidden: true),
          userId: 'owner1',
        );
        await tester.tap(find.byKey(const Key('unhideProblemButton')));
        await tester.pumpAndSettle();
        verify(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: false,
          ),
        ).called(1);
      });
    });
```

Before running, you'll likely need to:

  a. Update the `_problem` helper at the top of the test file to accept a `hidden` parameter (defaulting to `false`).
  b. Confirm the test file has a helper named `_pumpDetail` (or equivalent) — if not, extract the existing setup into one to keep the new tests concise. Check what the existing visibility tests use; reuse that pattern.
  c. Register a fallback value for `Problem` in `setUpAll` (the cubit test file shows the pattern: `registerFallbackValue(_problem())`).
  d. The `problemsCubit` mock needs the new `setHidden` method stubbed — `_MockProblemsCubit extends MockCubit<ProblemsState> implements ProblemsCubit` should suffice via mocktail.

- [ ] **Step 2: Run tests and confirm they fail**

```bash
cd apps/client
flutter test test/problems/view/problem_detail_page_test.dart \
  --plain-name "hidden flag"
cd ../..
```

Expected: tests fail because the widget keys don't exist yet.

- [ ] **Step 3: Implement the banner widget**

In `apps/client/lib/problems/view/problem_detail_page.dart`, add a private banner widget near the bottom of the file (after the existing `_ForkRow` class is a good neighbour):

```dart
/// Banner shown on a hidden problem's detail page. Renders different copy
/// for the owner (who also gets a "Show in listing" action) vs anyone
/// else (who gets a passive explanatory variant).
class _ProblemHiddenBanner extends StatelessWidget {
  const _ProblemHiddenBanner({
    required this.isOwner,
    required this.onUnhide,
  });

  final bool isOwner;
  final Future<void> Function() onUnhide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Container(
      key: const Key('hiddenBanner'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOwner
                ? l10n.problemHiddenOwnerBannerTitle
                : l10n.problemHiddenViewerBannerTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isOwner
                ? l10n.problemHiddenOwnerBannerBody
                : l10n.problemHiddenViewerBannerBody,
            style: theme.textTheme.bodyMedium,
          ),
          if (isOwner) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                key: const Key('unhideProblemButton'),
                onPressed: onUnhide,
                child: Text(l10n.unhideProblemButton),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Wire the banner and Hide button into the detail page**

Find the `build` method in `_ProblemDetailViewState` (the body around line 778 / 806 — where `isOwner` is computed and `_buildEditBody` / `_buildReadOnlyBody` are dispatched). Replace the `body: SingleChildScrollView(...)` section so that:

  - When `problem.hidden` is true, the banner appears at the top of the scroll view regardless of viewer.
  - The owner's edit body gains a "Hide from listing" outlined button when `!problem.hidden`.
  - When the problem is hidden, the owner sees the banner only — the rest of the edit body still renders so they can still see the content.

Concretely:

```dart
body: SingleChildScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (problem.hidden)
        _ProblemHiddenBanner(
          isOwner: isOwner,
          onUnhide: () => _setHidden(problem, false),
        ),
      if (isOwner)
        _buildEditBody(problem)
      else
        _buildReadOnlyBody(problem),
    ],
  ),
),
```

Add the `_setHidden` helper method on the state class:

```dart
Future<void> _setHidden(Problem problem, bool hidden) async {
  await context.read<ProblemsCubit>().setHidden(
        problem: problem,
        hidden: hidden,
      );
  if (!mounted) return;
  setState(() {
    _problem = problem.copyWith(hidden: hidden);
  });
}
```

Inside `_buildEditBody`, find the bottom action row (search for where other owner-only buttons live — the existing edit-mode controls; if there's no obvious row, add a new `Padding` + `Row` at the end). Add:

```dart
if (!problem.hidden)
  OutlinedButton.icon(
    key: const Key('hideProblemButton'),
    icon: const Icon(Icons.visibility_off_outlined),
    label: Text(context.l10n.hideProblemButton),
    onPressed: () => _setHidden(problem, true),
  ),
```

> If `_buildEditBody`'s layout doesn't have an obvious "actions" cluster, place the Hide button immediately above the existing footer (whatever sits at the visual bottom of the edit body). The exact placement is a layout choice — pick something consistent with the existing visual rhythm and document the choice in the commit message.

- [ ] **Step 5: Run the tests and confirm they pass**

```bash
cd apps/client
flutter test test/problems/view/problem_detail_page_test.dart
cd ../..
```

Expected: every test in the file passes, including the new `hidden flag` group.

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib/problems/view/problem_detail_page.dart \
        apps/client/test/problems/view/problem_detail_page_test.dart
git commit -m "feat(client): hide/unhide button + banner on problem detail page"
```

---

## Task 10: Full verification

**Files:** none — verification only.

- [ ] **Step 1: Format everything**

```bash
melos format
```

Expected: no changes (or trivial formatting if codegen output drifted). If there are changes, commit them as `chore: melos format`.

- [ ] **Step 2: Analyze**

```bash
flutter analyze apps packages
```

Expected: no issues. If any, fix before proceeding.

- [ ] **Step 3: Run the full unit-test suite**

```bash
very_good test --recursive --no-optimization --coverage \
  --test-randomize-ordering-seed random
```

Expected: all tests pass.

- [ ] **Step 4: Run the e2e rules suite (emulator must be running)**

```bash
firebase emulators:start --only auth,firestore   # in a separate terminal
dart test apps/server/e2e/firestore_rules_e2e_test.dart --tags e2e
```

Expected: all tests pass.

- [ ] **Step 5: If anything was committed in steps 1–4 as a fix, push them now (one commit per fix, no squashing)**

Then you're done — proceed to rollout (Task 11).

---

## Task 11: Rollout

**Files:** none — this is a deployment sequence, not a code change.

This task is the "do not skip the order" step. Out of order, the listing goes empty for users mid-rollout.

- [ ] **Step 1: Deploy the new composite index**

```bash
firebase deploy --only firestore:indexes
```

Wait for the index to finish building. Check the Firebase Console → Firestore → Indexes; the new `geoscope+solved+hidden+votes+__name__` index should show as `Enabled`. This usually takes a few minutes on small collections.

The old client keeps working during this step — extra index columns don't break the existing query.

- [ ] **Step 2: Run the backfill in dry-run mode against production**

```bash
cd apps/server
export GOOGLE_CLOUD_PROJECT=votasq
gcloud auth application-default login   # if not already done
dart run tool/backfill_hidden.dart --dry-run
cd ../..
```

Expected: a `scanned=N patched=M` line. `M` should equal the count of existing problems (i.e. every doc needs the backfill). If `M` is suspiciously small or zero, investigate before applying.

- [ ] **Step 3: Apply the backfill**

```bash
cd apps/server
dart run tool/backfill_hidden.dart
cd ../..
```

Expected: same `scanned=N patched=M` line, with `M` matching the dry-run prediction. Re-run once more; the second pass should report `patched=0` (idempotent).

The old client keeps working during this step — `hidden: false` on a doc is invisible to a client that doesn't know about the field.

- [ ] **Step 4: Deploy the new firestore.rules**

```bash
firebase deploy --only firestore:rules
```

The old client keeps working during this step — the new "hide toggle" branch is purely additive, and the full-update tightening only matters for writes that include `hidden` (which the old client never sends).

- [ ] **Step 5: Ship the new client (Android, Web, macOS, etc. per release process)**

Through whatever the current release flow is for this app. The client release goes last.

- [ ] **Step 6: Spot-check production**

After release: log in as a test owner account on a deployed build, create a problem, hide it from the detail page, navigate back to the listing — it should be gone. Unhide from the detail page (via direct URL) — it should reappear in the listing after the next snapshot.

---

## Self-review (kept for posterity)

- **Spec coverage:** every spec section maps to a task. Model → Task 1. Index → Task 2. Rules → Tasks 3–4. Backfill → Tasks 5, 11. Client query/repo → Task 6. Cubit → Task 7. L10n → Task 8. Detail-page UI → Task 9. Tests for each → integrated into the same task as the implementation. Rollout sequence → Task 11.
- **Placeholders:** no "TBD" / "implement later" / "handle edge cases" without code.
- **Type consistency:** `setHidden({required String problemId, required bool hidden})` on the repo and `setHidden({required Problem problem, required bool hidden})` on the cubit are intentionally different signatures — the cubit takes the whole `Problem` because it needs `problem.id` AND a way to compute the optimistic local-state shape. Cross-checked.
- **Out-of-order risk:** Task 11's ordering note covers the rollout failure mode. Tasks 1–10 are mostly linear; Task 6 (repo) is the first task that breaks the old query if shipped without the backfill, but that's handled by the rollout sequence.
