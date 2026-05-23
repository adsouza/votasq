# Progressive Onboarding Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing single-tip sign-in banner into a progressive onboarding surface that walks the user through sign-in → vote → double-tap-for-details, suppressing each tip once the user demonstrates the affordance against time-since-last-session.

**Architecture:** Two new int fields on `users/{uid}` — `problemDetailsViewCount` (client-incremented via a new Firestore rule branch on each double-tap) and `votesCastCount` (server-materialized by a new Cloud Function watching voter-doc writes). UserCubit (renamed from AuthCubit) snapshots `lastActiveAt` once at sign-in to define "days since last session," then exposes `needsVoteHint` / `needsDoubleTapHint` getters that gate the banner and toast.

**Tech Stack:** Dart 3 / Flutter 3 (client), Dart Frog (server, indirectly via shared User model), Cloud Functions for Firebase v2 with TypeScript + Vitest (functions), Firestore (rules + indexes), Freezed (User model), bloc/flutter_bloc (state), `googleapis` (backfill script).

**Spec:** [docs/superpowers/specs/2026-05-23-progressive-onboarding-banner-design.md](../specs/2026-05-23-progressive-onboarding-banner-design.md)

---

## Files Touched

### Created
- `functions/scripts/backfill_votes_cast_count.ts` — one-shot ops script (TypeScript chosen for tooling simplicity; see Task 14 note).
- `functions/scripts/backfill_votes_cast_count.test.ts` — vitest unit test for the script's count logic.
- `functions/src/triggers/votes_cast_count.ts` — new Cloud Function trigger.
- `functions/src/triggers/votes_cast_count.test.ts` — vitest tests for the trigger.
- `apps/client/lib/auth/cubit/user_cubit.dart` — renamed from `auth_cubit.dart`, extended.
- `apps/client/lib/auth/cubit/user_state.dart` — renamed from `auth_state.dart`, extended.
- `apps/client/test/auth/cubit/user_cubit_test.dart` — renamed from `auth_cubit_test.dart`, extended.

### Modified
- `packages/shared/lib/src/models/user.dart` — add two fields with `@Default(0)`.
- `firestore.rules` — new `problemDetailsViewCount` update branch + optional zero-init create checks for both new fields.
- `firestore.indexes.json` — add `voters` collection-group index on `uid`.
- `apps/client/lib/services/firestore_repository.dart` — extend `_docToUser`, `ensureUserDoc`; replace `watchUserVotes` with `watchUserDoc`; add `incrementProblemDetailsViewCount`.
- `apps/client/test/services/firestore_repository_test.dart` — round-trip tests for the two new fields.
- `apps/client/lib/auth/auth.dart` — update barrel exports.
- `apps/client/lib/problems/view/problems_page.dart` — three-state banner, toast gate, double-tap wiring.
- `apps/client/lib/problems/widgets/problem_read_tile.dart` — add `onViewDetails` prop.
- `apps/client/test/problems/view/problems_page_test.dart` — banner + double-tap + toast tests.
- All 24 files under `apps/client/lib/l10n/arb/app_*.arb` — rename `doubleTapHintToast` → `doubleTapHint`, add `voteHint`.
- `apps/server/e2e/firestore_rules_e2e_test.dart` — new rule cases.
- `functions/src/index.ts` — export the new trigger.
- ~10 other client files containing `AuthCubit` / `AuthState` references — mechanical rename.

### Deleted
- `apps/client/lib/auth/cubit/auth_cubit.dart` (replaced by user_cubit.dart).
- `apps/client/lib/auth/cubit/auth_state.dart` (replaced by user_state.dart).
- `apps/client/test/auth/cubit/auth_cubit_test.dart` (replaced by user_cubit_test.dart).

---

## Implementation Notes

- **Optimistic vote-cast bump is deferred.** The spec mentions a `UserCubit.recordVoteCast()` for instant UI graduation. Plumbing that across `ProblemsCubit` and `problem_detail_page.dart` adds cubit-to-cubit coupling that the codebase otherwise avoids. The Cloud Function-driven `watchUserDoc` update arrives within ~1s, which is acceptable for a once-per-graduation event. Add the optimistic path in a follow-up if user testing flags the flicker.
- **Tasks 1–4 follow a "data foundations first" order**: shared model → rules → indexes → repo. Each commit leaves the project compilable and tests green.
- **The rename (tasks 5–7) lands after the new fields** so the renamed cubit can immediately project the new fields from the doc stream — one commit per concern rather than entangled diffs.
- **Cloud Function (task 12) and migration tool (task 14) ship in the same PR as the client code.** Deployment order (rules → indexes → backfill → function → client) is documented in the spec and is an ops concern, not a code-organization concern.

---

## Task 1: Add new fields to shared User model

**Files:**
- Modify: `packages/shared/lib/src/models/user.dart`
- Regen: `packages/shared/lib/src/models/user.freezed.dart`, `packages/shared/lib/src/models/user.g.dart`

- [ ] **Step 1: Edit the freezed model**

Replace the body of [packages/shared/lib/src/models/user.dart](packages/shared/lib/src/models/user.dart) with:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
/// Represents a user with a vote budget and onboarding-tip counters.
abstract class User with _$User {
  /// Creates a user.
  const factory User({
    required String uid,
    required DateTime lastActiveAt,
    required int votes,
    String? displayName,
    @Default(0) int problemDetailsViewCount,
    @Default(0) int votesCastCount,
  }) = _User;

  /// Deserializes a [User] from JSON.
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

- [ ] **Step 2: Regenerate**

Run: `melos gen`
Expected: `shared: SUCCESS` with no errors.

- [ ] **Step 3: Run shared tests**

Run: `flutter test packages/shared/test 2>/dev/null || cd packages/shared && dart test`
Expected: All existing tests pass — freezed `@Default(0)` on a new optional field is backwards-compatible.

- [ ] **Step 4: Commit**

```bash
git add packages/shared/lib/src/models/user.dart
git commit -m "feat(shared): add problemDetailsViewCount + votesCastCount to User model"
```

---

## Task 2: Add the firestore.rules branches

**Files:**
- Modify: `firestore.rules:131-173` (the `users/{userId}` block)

- [ ] **Step 1: Replace the users block**

Open [firestore.rules](firestore.rules). Replace lines 131–173 with:

```ruby
    match /users/{userId} {
      allow read: if true;
      allow create: if
        request.auth != null
        && request.auth.uid == userId
        && request.resource.data.keys().hasAll(['uid', 'votes', 'lastActiveAt'])
        && request.resource.data.uid == request.auth.uid
        && request.resource.data.votes is int
        && request.resource.data.votes == 3 // Must match initialVoteBudget
        && request.resource.data.lastActiveAt is timestamp
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
        );
      allow update: if
        request.auth != null
        && request.auth.uid == userId
        && request.resource.data.uid == resource.data.uid
        && (
          // Vote decrement
          (
            request.resource.data.votes is int
            && request.resource.data.votes == resource.data.votes - 1
            && request.resource.data.votes >= 0
          )
          ||
          // Vote grant on resume (time-based, with lastActiveAt update)
          (
            request.resource.data.votes is int
            && request.resource.data.lastActiveAt is timestamp
            && request.resource.data.votes > resource.data.votes
            && request.resource.data.votes - resource.data.votes < 10
          )
          ||
          // lastActiveAt touch (votes unchanged)
          (
            request.resource.data.votes == resource.data.votes
            && request.resource.data.lastActiveAt is timestamp
          )
          ||
          // Notification preferences and/or locale update (votes unchanged)
          (
            request.resource.data.diff(resource.data).affectedKeys()
              .hasOnly(['notificationPreferences', 'locale', 'lastActiveAt'])
            && request.resource.data.votes == resource.data.votes
          )
          ||
          // problemDetailsViewCount increment + lastActiveAt touch.
          // Strict +1 enforcement keeps a malicious client from
          // fast-forwarding themselves out of the banner.
          (
            request.resource.data.diff(resource.data).affectedKeys()
              .hasOnly(['problemDetailsViewCount', 'lastActiveAt'])
            && request.resource.data.problemDetailsViewCount is int
            && request.resource.data.problemDetailsViewCount ==
               resource.data.get('problemDetailsViewCount', 0) + 1
            && request.resource.data.lastActiveAt is timestamp
          )
        );
```

(Subcollections `notifications/`, `fcmTokens/` immediately follow — leave them unchanged.)

- [ ] **Step 2: Commit**

```bash
git add firestore.rules
git commit -m "feat(rules): permit problemDetailsViewCount increment; constrain new-field zero-init"
```

---

## Task 3: Rule e2e tests for the new branches

**Files:**
- Modify: `apps/server/e2e/firestore_rules_e2e_test.dart` (append a new `group` near end)

- [ ] **Step 1: Append the new test group**

Append the following just before the final closing `}` of `main()` in [apps/server/e2e/firestore_rules_e2e_test.dart](apps/server/e2e/firestore_rules_e2e_test.dart):

```dart
  group('firestore.rules — users onboarding counters', () {
    // Seeds a user doc at users/{uid} via the server's admin path
    // (bypasses rules) so the update-branch tests have something to mutate.
    Future<void> seedUser(
      String uid, {
      int votes = 3,
      int problemDetailsViewCount = 0,
      int votesCastCount = 0,
    }) async {
      // Reuse the existing test harness's admin client — wherever the file's
      // earlier setUpAll wires `_adminFirestore`, call its set() here.
      await _adminFirestore.collection('users').doc(uid).set({
        'uid': uid,
        'votes': votes,
        'lastActiveAt': DateTime.now().toUtc(),
        'problemDetailsViewCount': problemDetailsViewCount,
        'votesCastCount': votesCastCount,
      });
    }

    test('create with problemDetailsViewCount: 0 succeeds', () async {
      final uid = 'u-pdvc-0';
      final res = await createUserAsAuthed(uid, {
        'uid': uid,
        'votes': 3,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
        'problemDetailsViewCount': 0,
      });
      expect(res.statusCode, 200);
    });

    test('create with problemDetailsViewCount: 5 is rejected', () async {
      final uid = 'u-pdvc-bad';
      final res = await createUserAsAuthed(uid, {
        'uid': uid,
        'votes': 3,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
        'problemDetailsViewCount': 5,
      });
      expect(res.statusCode, 403);
    });

    test('create with votesCastCount: 0 succeeds', () async {
      final uid = 'u-vcc-0';
      final res = await createUserAsAuthed(uid, {
        'uid': uid,
        'votes': 3,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
        'votesCastCount': 0,
      });
      expect(res.statusCode, 200);
    });

    test('create with votesCastCount: 5 is rejected', () async {
      final uid = 'u-vcc-bad';
      final res = await createUserAsAuthed(uid, {
        'uid': uid,
        'votes': 3,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
        'votesCastCount': 5,
      });
      expect(res.statusCode, 403);
    });

    test('problemDetailsViewCount +1 with lastActiveAt touch succeeds', () async {
      const uid = 'u-pdvc-inc';
      await seedUser(uid, problemDetailsViewCount: 2);
      final res = await updateUserAsAuthed(uid, {
        'problemDetailsViewCount': 3,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect(res.statusCode, 200);
    });

    test('problemDetailsViewCount +2 is rejected', () async {
      const uid = 'u-pdvc-inc2';
      await seedUser(uid, problemDetailsViewCount: 2);
      final res = await updateUserAsAuthed(uid, {
        'problemDetailsViewCount': 4,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect(res.statusCode, 403);
    });

    test('problemDetailsViewCount increment that also changes votes is rejected', () async {
      const uid = 'u-pdvc-mixed';
      await seedUser(uid, votes: 3, problemDetailsViewCount: 2);
      final res = await updateUserAsAuthed(uid, {
        'problemDetailsViewCount': 3,
        'votes': 2, // unrelated vote change in the same write
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect(res.statusCode, 403);
    });

    test('problemDetailsViewCount increment without auth is rejected', () async {
      const uid = 'u-pdvc-anon';
      await seedUser(uid, problemDetailsViewCount: 2);
      final res = await updateUserAsAnon(uid, {
        'problemDetailsViewCount': 3,
        'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect(res.statusCode, 403);
    });

    test('client direct write to votesCastCount is rejected', () async {
      const uid = 'u-vcc-direct';
      await seedUser(uid, votesCastCount: 4);
      final res = await updateUserAsAuthed(uid, {
        'votesCastCount': 5,
      });
      expect(res.statusCode, 403);
    });
  });
```

The helpers `createUserAsAuthed`, `updateUserAsAuthed`, `updateUserAsAnon`, and the `_adminFirestore` reference are conventions already used in `firestore_rules_e2e_test.dart` — match the file's existing helper signatures. If those exact names don't exist yet, locate the equivalents (e.g. via grepping for `request.method` / token-bearing HTTP helpers in the same file) and adapt.

- [ ] **Step 2: Run tests against emulator**

In one terminal: `firebase emulators:start --only auth,firestore`
In another, from the project root: `dart test apps/server/e2e/firestore_rules_e2e_test.dart --tags e2e`
Expected: all new tests pass.

- [ ] **Step 3: Commit**

```bash
git add apps/server/e2e/firestore_rules_e2e_test.dart
git commit -m "test(rules): cover problemDetailsViewCount + votesCastCount rule branches"
```

---

## Task 4: Update firestore.indexes.json

**Files:**
- Modify: `firestore.indexes.json`

- [ ] **Step 1: Append the collection-group index**

Add inside the `"indexes"` array of [firestore.indexes.json](firestore.indexes.json):

```json
{
  "collectionGroup": "voters",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "uid", "order": "ASCENDING" }
  ]
}
```

- [ ] **Step 2: Deploy indexes locally to verify shape**

Run: `firebase deploy --only firestore:indexes --dry-run 2>&1 | tail -10`
Expected: "indexes ... validated successfully" (no error about malformed JSON / unknown fields).

- [ ] **Step 3: Commit**

```bash
git add firestore.indexes.json
git commit -m "feat(firestore): add voters collection-group index on uid"
```

---

## Task 5: Repository round-trip tests for new User fields

**Files:**
- Modify: `apps/client/test/services/firestore_repository_test.dart`

- [ ] **Step 1: Add round-trip tests**

Locate the existing group testing `ensureUserDoc` / `_docToUser` in [apps/client/test/services/firestore_repository_test.dart](apps/client/test/services/firestore_repository_test.dart). Add the following tests inside that group (match the file's existing helper for constructing a `FakeFirebaseFirestore`):

```dart
    test('ensureUserDoc writes problemDetailsViewCount: 0 on the wire', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreRepository(firestore);
      final newUser = User(
        uid: 'u1',
        votes: 3,
        lastActiveAt: DateTime.utc(2026, 5, 23),
      );

      await repo.ensureUserDoc(newUser);

      final doc = await firestore.collection('users').doc('u1').get();
      expect(doc.data()!['problemDetailsViewCount'], 0);
      expect(doc.data()!['votesCastCount'], 0);
    });

    test('_docToUser reads back seeded problemDetailsViewCount + votesCastCount', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('u2').set({
        'uid': 'u2',
        'votes': 3,
        'lastActiveAt': Timestamp.fromDate(DateTime.utc(2026, 5, 23)),
        'problemDetailsViewCount': 7,
        'votesCastCount': 11,
      });
      final repo = FirestoreRepository(firestore);

      final user = await repo.fetchUserDoc('u2'); // tiny helper added next

      expect(user!.problemDetailsViewCount, 7);
      expect(user.votesCastCount, 11);
    });

    test('incrementProblemDetailsViewCount advances the field and touches lastActiveAt',
        () async {
      final firestore = FakeFirebaseFirestore();
      final t0 = DateTime.utc(2026, 5, 23, 12);
      await firestore.collection('users').doc('u3').set({
        'uid': 'u3',
        'votes': 3,
        'lastActiveAt': Timestamp.fromDate(t0),
        'problemDetailsViewCount': 4,
      });
      final repo = FirestoreRepository(firestore);

      await repo.incrementProblemDetailsViewCount('u3');

      final doc = await firestore.collection('users').doc('u3').get();
      expect(doc.data()!['problemDetailsViewCount'], 5);
      expect((doc.data()!['lastActiveAt'] as Timestamp).toDate().isAfter(t0), isTrue);
    });
```

- [ ] **Step 2: Run tests — expect failures**

Run: `flutter test apps/client/test/services/firestore_repository_test.dart`
Expected: all three new tests FAIL — `fetchUserDoc` and `incrementProblemDetailsViewCount` don't exist yet; `ensureUserDoc` doesn't write the new fields.

- [ ] **Step 3: Commit (just the failing tests)**

```bash
git add apps/client/test/services/firestore_repository_test.dart
git commit -m "test(repo): add failing round-trip tests for User onboarding counters"
```

---

## Task 6: Implement FirestoreRepository changes

**Files:**
- Modify: `apps/client/lib/services/firestore_repository.dart`

- [ ] **Step 1: Extend `ensureUserDoc` to stamp both new counters**

In [apps/client/lib/services/firestore_repository.dart:423-429](apps/client/lib/services/firestore_repository.dart), replace the `data` map literal:

```dart
    final data = {
      'uid': user.uid,
      'votes': user.votes,
      'lastActiveAt': user.lastActiveAt,
      'problemDetailsViewCount': user.problemDetailsViewCount,
      'votesCastCount': user.votesCastCount,
      if (user.displayName != null) 'displayName': user.displayName,
    };
```

- [ ] **Step 2: Extend `_docToUser` to read both new fields**

Replace the body of `_docToUser` at line 433–441:

```dart
  User _docToUser(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return User(
      uid: doc.id,
      votes: (data['votes'] as num).toInt(),
      lastActiveAt: (data['lastActiveAt'] as Timestamp).toDate(),
      displayName: data['displayName'] as String?,
      problemDetailsViewCount:
          (data['problemDetailsViewCount'] as num?)?.toInt() ?? 0,
      votesCastCount: (data['votesCastCount'] as num?)?.toInt() ?? 0,
    );
  }
```

- [ ] **Step 3: Add `fetchUserDoc` (small helper for tests + general use) and `incrementProblemDetailsViewCount`**

Add these methods near the existing `touchLastActiveAt` (line 489):

```dart
  /// One-shot fetch of a user doc as a freezed [User]. Returns `null` if
  /// the doc doesn't exist. Useful for the session-start snapshot in
  /// [UserCubit] and for repository tests.
  Future<User?> fetchUserDoc(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return null;
    return _docToUser(doc);
  }

  /// Increment the user's detail-view counter by exactly 1 and touch
  /// `lastActiveAt` in the same write, matching the rule branch added
  /// for this field. Fire-and-forget from the caller's perspective.
  Future<void> incrementProblemDetailsViewCount(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'problemDetailsViewCount': FieldValue.increment(1),
      'lastActiveAt': DateTime.now().toUtc(),
    });
  }
```

- [ ] **Step 4: Add `watchUserDoc` (keep `watchUserVotes` for now — Task 7 removes it)**

Insert a new method just below the existing `watchUserVotes` (around line 503):

```dart
  /// Real-time stream of the entire user doc. UserCubit uses this in
  /// preference to the older `watchUserVotes` so it can project
  /// onboarding counters too. Once the cubit migration in Task 7 lands,
  /// `watchUserVotes` can go away.
  Stream<User?> watchUserDoc(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? _docToUser(doc) : null);
  }
```

- [ ] **Step 5: Run repo tests — expect green**

Run: `flutter test apps/client/test/services/firestore_repository_test.dart`
Expected: all tests pass (including the three new ones).

- [ ] **Step 6: Run wider analyze + format**

Run: `flutter analyze apps packages 2>&1 | tail -20` — there will be errors about `watchUserVotes` no longer existing. That's expected and fixed in Task 7.
Run: `melos format`
Expected: format clean.

- [ ] **Step 7: Commit**

```bash
git add apps/client/lib/services/firestore_repository.dart
git commit -m "feat(repo): wire User onboarding counters; watchUserDoc replaces watchUserVotes"
```

---

## Task 7: Rename Auth* → User* across the whole client (one compilable commit)

This task merges three smaller renames (state class, cubit class, call sites) into one atomic commit, so the project compiles after every commit. The steps below are bite-sized; only Step 11 commits.

**Files:**
- Delete: `apps/client/lib/auth/cubit/auth_state.dart`
- Delete: `apps/client/lib/auth/cubit/auth_cubit.dart`
- Create: `apps/client/lib/auth/cubit/user_state.dart`
- Create: `apps/client/lib/auth/cubit/user_cubit.dart`
- Move: `apps/client/test/auth/cubit/auth_cubit_test.dart` → `user_cubit_test.dart`
- Modify: `apps/client/lib/auth/auth.dart`
- Modify: ~10 other files referencing `AuthCubit` / `AuthState`

- [ ] **Step 1: Write the new state file**

Create [apps/client/lib/auth/cubit/user_state.dart](apps/client/lib/auth/cubit/user_state.dart):

```dart
enum AuthStatus { unknown, authenticated, unauthenticated }

class UserState {
  const UserState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.remainingVotes,
    this.problemDetailsViewCount,
    this.votesCastCount,
    this.sessionStartLastActiveAt,
  });

  final AuthStatus status;
  final String? userId;
  final int? remainingVotes;

  /// Live count from the user-doc subscription; null until first read.
  final int? problemDetailsViewCount;

  /// Live count from the user-doc subscription; null until first read.
  final int? votesCastCount;

  /// `lastActiveAt` value captured the moment this session began —
  /// frozen for the rest of the session so banner / toast suppression
  /// math doesn't shift as the server's lastActiveAt advances.
  final DateTime? sessionStartLastActiveAt;

  /// Static integer gap between session start and now. Null while
  /// loading. Computed at read-time but anchored to the frozen snapshot.
  int? get _daysSinceLastSession {
    final snap = sessionStartLastActiveAt;
    if (snap == null) return null;
    return DateTime.now().difference(snap).inDays;
  }

  /// True iff the user is authenticated AND has cast few enough votes
  /// (relative to the session-start gap) that we should still surface
  /// the vote tip. Returns false while loading so the banner doesn't
  /// flicker into and out of the vote state on cold start.
  bool get needsVoteHint {
    if (status != AuthStatus.authenticated) return false;
    final count = votesCastCount;
    final days = _daysSinceLastSession;
    if (count == null || days == null) return false;
    return count <= days;
  }

  /// Same shape as [needsVoteHint] but for the double-tap hint.
  bool get needsDoubleTapHint {
    if (status != AuthStatus.authenticated) return false;
    final count = problemDetailsViewCount;
    final days = _daysSinceLastSession;
    if (count == null || days == null) return false;
    return count <= days;
  }

  UserState copyWith({
    AuthStatus? status,
    String? Function()? userId,
    int? Function()? remainingVotes,
    int? Function()? problemDetailsViewCount,
    int? Function()? votesCastCount,
    DateTime? Function()? sessionStartLastActiveAt,
  }) {
    return UserState(
      status: status ?? this.status,
      userId: userId != null ? userId() : this.userId,
      remainingVotes:
          remainingVotes != null ? remainingVotes() : this.remainingVotes,
      problemDetailsViewCount: problemDetailsViewCount != null
          ? problemDetailsViewCount()
          : this.problemDetailsViewCount,
      votesCastCount: votesCastCount != null
          ? votesCastCount()
          : this.votesCastCount,
      sessionStartLastActiveAt: sessionStartLastActiveAt != null
          ? sessionStartLastActiveAt()
          : this.sessionStartLastActiveAt,
    );
  }
}
```

- [ ] **Step 2: Write the new cubit file**

Create [apps/client/lib/auth/cubit/user_cubit.dart](apps/client/lib/auth/cubit/user_cubit.dart):

```dart
import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/auth/cubit/user_state.dart';
import 'package:client/auth/data/auth_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:shared/shared.dart' as shared;

class UserCubit extends Cubit<UserState> {
  UserCubit(this._authRepository, this._firestoreRepository)
    : super(const UserState()) {
    _subscription = _authRepository.authStateChanges.listen(
      (user) {
        if (user != null) {
          emit(
            state.copyWith(
              status: AuthStatus.authenticated,
              userId: () => user.uid,
            ),
          );
          unawaited(_initUserDoc(user.uid, user.displayName));
        } else {
          unawaited(_userDocSubscription?.cancel());
          _userDocSubscription = null;
          emit(
            state.copyWith(
              status: AuthStatus.unauthenticated,
              userId: () => null,
              remainingVotes: () => null,
              problemDetailsViewCount: () => null,
              votesCastCount: () => null,
              sessionStartLastActiveAt: () => null,
            ),
          );
        }
      },
      onError: (Object e, StackTrace st) {
        log('authStateChanges error: $e', stackTrace: st);
        unawaited(_userDocSubscription?.cancel());
        _userDocSubscription = null;
        emit(
          state.copyWith(
            status: AuthStatus.unauthenticated,
            userId: () => null,
            remainingVotes: () => null,
            problemDetailsViewCount: () => null,
            votesCastCount: () => null,
            sessionStartLastActiveAt: () => null,
          ),
        );
      },
    );
  }

  final AuthRepository _authRepository;
  final FirestoreRepository _firestoreRepository;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<shared.User?>? _userDocSubscription;

  Future<void> _initUserDoc(String userId, String? displayName) async {
    try {
      // ensureUserDoc creates the doc if missing and returns the
      // *existing* lastActiveAt for already-onboarded users — exactly
      // the snapshot we want to freeze for the session.
      final existing = await _firestoreRepository.ensureUserDoc(
        shared.User(
          uid: userId,
          votes: shared.initialVoteBudget,
          lastActiveAt: DateTime.now().toUtc(),
          displayName: displayName,
        ),
      );
      emit(
        state.copyWith(
          sessionStartLastActiveAt: () => existing.lastActiveAt,
        ),
      );

      // Refresh votes / touch lastActiveAt server-side. Our local
      // sessionStartLastActiveAt is already frozen, so this can't
      // shift the banner suppression math.
      unawaited(_firestoreRepository.grantVotesAndTouch(userId));

      await _userDocSubscription?.cancel();
      _userDocSubscription = _firestoreRepository
          .watchUserDoc(userId)
          .listen(
            (user) {
              if (user == null) return;
              emit(
                state.copyWith(
                  remainingVotes: () => user.votes,
                  problemDetailsViewCount: () => user.problemDetailsViewCount,
                  votesCastCount: () => user.votesCastCount,
                  // Deliberately NOT updating sessionStartLastActiveAt
                  // here — it's frozen by the assignment above.
                ),
              );
            },
            onError: (Object e, StackTrace st) {
              log('watchUserDoc error: $e', stackTrace: st);
            },
          );
    } on Exception catch (e, st) {
      log('_initUserDoc failed: $e', stackTrace: st);
    }
  }

  Future<void> signIn() async {
    try {
      await _authRepository.signInWithGoogle();
    } on Exception catch (e, st) {
      log('signIn failed: $e', stackTrace: st);
    }
  }

  Future<void> signOut() async {
    try {
      await _authRepository.signOut();
    } on Exception catch (e, st) {
      log('signOut failed: $e', stackTrace: st);
    }
  }

  @override
  Future<void> close() async {
    await _userDocSubscription?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 3: Delete the old state and cubit files**

```bash
git rm apps/client/lib/auth/cubit/auth_state.dart \
       apps/client/lib/auth/cubit/auth_cubit.dart
```

- [ ] **Step 4: Update the barrel**

Edit [apps/client/lib/auth/auth.dart](apps/client/lib/auth/auth.dart):

```dart
export 'cubit/user_cubit.dart';
export 'cubit/user_state.dart';
export 'data/auth_repository.dart';
```

- [ ] **Step 5: Sweep all client call sites**

List the files that reference the old type names:

```bash
grep -rln "AuthCubit\|AuthState\b\|authCubit\b" apps/client/lib apps/client/test --include="*.dart" 2>/dev/null
```

Expected: ~11 files outside `apps/client/lib/auth/cubit/`.

Single-shot replacement (the `\b`s matter — without them, `AuthStatus` and identifiers like `authCubitProvider` would get mangled):

```bash
grep -rln "AuthCubit\|AuthState\b\|authCubit\b" apps/client/lib apps/client/test --include="*.dart" \
  | xargs sed -i '' \
      -e 's/AuthCubit/UserCubit/g' \
      -e 's/AuthState\b/UserState/g' \
      -e 's/authCubit\b/userCubit/g'
```

The third replacement covers the lowercase variable name commonly used in tests (e.g., `late AuthCubit authCubit;` becomes `late UserCubit userCubit;`). `authRepo` stays as-is — that variable holds an `AuthRepository`, which keeps its name.

- [ ] **Step 6: Rename the cubit test file**

```bash
git mv apps/client/test/auth/cubit/auth_cubit_test.dart \
       apps/client/test/auth/cubit/user_cubit_test.dart
```

- [ ] **Step 7: Quick spot-check on the moved test file**

Open the moved file in your editor. Update any `import 'package:client/auth/cubit/auth_cubit.dart'` lines to `package:client/auth/cubit/user_cubit.dart`, and any `import '.../auth_state.dart'` similarly. The sed-replace above only touches symbol names, not file paths.

Also update the **mock setup** for the user-doc subscription. The existing tests mock `firestoreRepo.watchUserVotes(any())` returning a `Stream<int>` — replace those `when()` lines with the new shape:

```dart
when(() => firestoreRepo.watchUserDoc(any())).thenAnswer(
  (_) => Stream<shared.User?>.empty(),
);
when(() => firestoreRepo.ensureUserDoc(any())).thenAnswer(
  (_) async => shared.User(
    uid: 'u1',
    votes: 3,
    lastActiveAt: DateTime.utc(2026, 5, 20),
  ),
);
```

Variable names like `authRepo` / `firestoreRepo` in the existing tests are intentionally untouched by the sed-replace (lowercase, with `Repo` suffix). Keep them as-is — the rename only applies to the type identifiers `AuthCubit` / `AuthState`.

- [ ] **Step 7b: Remove the now-dead `watchUserVotes` from FirestoreRepository**

After the cubit migration, nothing in the codebase references `watchUserVotes`. Verify:

```bash
grep -rn "watchUserVotes" apps/client packages 2>/dev/null
```

Expected: no matches (the cubit was migrated in Step 2 of this task, and Task 6 left the method in the repo as a temporary bridge). If empty, delete the method body from [apps/client/lib/services/firestore_repository.dart](apps/client/lib/services/firestore_repository.dart). If matches remain, fix those callers before continuing.

- [ ] **Step 8: Run analyze**

Run: `flutter analyze apps packages 2>&1 | tail -10`
Expected: "No issues found!"

- [ ] **Step 9: Run all client tests**

Run: `cd apps/client && flutter test`
Expected: all 263 tests pass (functionality not yet changed — pure rename + new fields that default to null).

- [ ] **Step 10: Format**

Run: `melos format`

- [ ] **Step 11: Commit**

```bash
git add -A apps/client
git commit -m "refactor(client): rename Auth* -> User*; add onboarding-counter state and watchUserDoc subscription"
```

---

## Task 8: UserCubit tests for snapshot + new field projection

**Files:**
- Modify: `apps/client/test/auth/cubit/user_cubit_test.dart`

- [ ] **Step 1: Add new test cases**

Inside the existing `group('UserCubit', ...)` block in [apps/client/test/auth/cubit/user_cubit_test.dart](apps/client/test/auth/cubit/user_cubit_test.dart), add:

```dart
    blocTest<UserCubit, UserState>(
      'sessionStartLastActiveAt is captured from the existing doc',
      build: () {
        when(() => firestoreRepo.ensureUserDoc(any())).thenAnswer(
          (_) async => shared.User(
            uid: 'u1',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 20),
            problemDetailsViewCount: 4,
            votesCastCount: 2,
          ),
        );
        when(() => firestoreRepo.grantVotesAndTouch(any()))
            .thenAnswer((_) async {});
        when(() => firestoreRepo.watchUserDoc(any())).thenAnswer(
          (_) => Stream<shared.User?>.empty(),
        );
        when(() => authRepo.authStateChanges).thenAnswer(
          (_) => Stream.value(_fakeFirebaseUser(uid: 'u1')),
        );
        return UserCubit(authRepo, firestoreRepo);
      },
      wait: const Duration(milliseconds: 50),
      verify: (cubit) {
        expect(
          cubit.state.sessionStartLastActiveAt,
          DateTime.utc(2026, 5, 20),
        );
      },
    );

    blocTest<UserCubit, UserState>(
      'subsequent stream lastActiveAt does NOT advance the snapshot',
      build: () {
        final ctrl = StreamController<shared.User?>();
        addTearDown(ctrl.close);
        when(() => firestoreRepo.ensureUserDoc(any())).thenAnswer(
          (_) async => shared.User(
            uid: 'u1',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 20),
          ),
        );
        when(() => firestoreRepo.grantVotesAndTouch(any()))
            .thenAnswer((_) async {});
        when(() => firestoreRepo.watchUserDoc(any()))
            .thenAnswer((_) => ctrl.stream);
        when(() => authRepo.authStateChanges).thenAnswer(
          (_) => Stream.value(_fakeFirebaseUser(uid: 'u1')),
        );
        final cubit = UserCubit(authRepo, firestoreRepo);
        Future.delayed(const Duration(milliseconds: 20), () {
          ctrl.add(shared.User(
            uid: 'u1',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 23), // moved forward
          ));
        });
        return cubit;
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        // Frozen at the value from ensureUserDoc, not the stream emission.
        expect(
          cubit.state.sessionStartLastActiveAt,
          DateTime.utc(2026, 5, 20),
        );
      },
    );

    blocTest<UserCubit, UserState>(
      'projects problemDetailsViewCount and votesCastCount from the stream',
      build: () {
        when(() => firestoreRepo.ensureUserDoc(any())).thenAnswer(
          (_) async => shared.User(
            uid: 'u1',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 20),
          ),
        );
        when(() => firestoreRepo.grantVotesAndTouch(any()))
            .thenAnswer((_) async {});
        when(() => firestoreRepo.watchUserDoc(any())).thenAnswer(
          (_) => Stream.value(shared.User(
            uid: 'u1',
            votes: 2,
            lastActiveAt: DateTime.utc(2026, 5, 23),
            problemDetailsViewCount: 7,
            votesCastCount: 5,
          )),
        );
        when(() => authRepo.authStateChanges).thenAnswer(
          (_) => Stream.value(_fakeFirebaseUser(uid: 'u1')),
        );
        return UserCubit(authRepo, firestoreRepo);
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state.problemDetailsViewCount, 7);
        expect(cubit.state.votesCastCount, 5);
        expect(cubit.state.remainingVotes, 2);
      },
    );

    test('needsVoteHint matches the spec table', () {
      // Sign-in just now -> daysSince=0
      final now = DateTime.now().toUtc();
      expect(
        const UserState().needsVoteHint,
        isFalse,
        reason: 'unknown auth status',
      );
      expect(
        UserState(
          status: AuthStatus.authenticated,
          votesCastCount: 0,
          sessionStartLastActiveAt: now,
        ).needsVoteHint,
        isTrue,
        reason: '0 <= 0',
      );
      expect(
        UserState(
          status: AuthStatus.authenticated,
          votesCastCount: 1,
          sessionStartLastActiveAt: now,
        ).needsVoteHint,
        isFalse,
        reason: '1 > 0',
      );
      expect(
        UserState(
          status: AuthStatus.authenticated,
          votesCastCount: 10,
          sessionStartLastActiveAt: now.subtract(const Duration(days: 30)),
        ).needsVoteHint,
        isTrue,
        reason: '10 <= 30 (returning user refresher)',
      );
    });
```

The existing test file already mocks `authRepo.authStateChanges` and `firestoreRepo` setups — use the same `_fakeFirebaseUser(uid: ...)` helper (or equivalent) already in the file when constructing the signed-in stream value.

- [ ] **Step 2: Run tests**

Run: `flutter test apps/client/test/auth/cubit/user_cubit_test.dart`
Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add apps/client/test/auth/cubit/user_cubit_test.dart
git commit -m "test(cubit): cover session-start snapshot and onboarding-counter projection"
```

---

## Task 9: l10n — rename one key, add another, in all 24 ARBs

**Files:**
- Modify: all 24 `apps/client/lib/l10n/arb/app_*.arb`
- Regen: `apps/client/lib/l10n/gen/app_localizations*.dart`

- [ ] **Step 1: English ARB**

In [apps/client/lib/l10n/arb/app_en.arb](apps/client/lib/l10n/arb/app_en.arb), find the entry for `doubleTapHintToast` (added in commit `abf4d27`). Replace:

```json
    "doubleTapHintToast": "Double-tap on problems for details.",
    "@doubleTapHintToast": {
        "description": "Toast message hinting that double-tapping a problem opens its detail page"
    },
```

with:

```json
    "doubleTapHint": "Double-tap on problems for details.",
    "@doubleTapHint": {
        "description": "Hint message (banner and toast) telling the user that double-tapping a problem opens its detail page"
    },
    "voteHint": "Tap the up-arrow chip beside a problem to vote for it.",
    "@voteHint": {
        "description": "Hint banner shown to authenticated users who haven't voted enough times yet — telling them they can vote by tapping the chip"
    },
```

- [ ] **Step 2: All 23 other ARBs**

For each of `app_ar.arb` through `app_zh.arb` (non-English):

- Rename `doubleTapHintToast` → `doubleTapHint` (keep the existing translated value).
- Add `voteHint` with a locale-appropriate translation of "Tap the up-arrow chip beside a problem to vote for it."

The English text and existing `doubleTapHint*` translations were committed at `abf4d27`; consult that commit's diff for translator style hints. Suggested vote-hint translations (one-line each, drop into each `_.arb`):

| Locale | voteHint |
|--------|----------|
| ar | اضغط على الشريحة التي عليها سهم لأعلى بجوار المشكلة للتصويت لها. |
| bn | ভোট দিতে সমস্যার পাশে উপরের তীরচিহ্ন চিপে ট্যাপ করুন। |
| de | Tippen Sie auf den Chip mit dem Aufwärtspfeil neben einem Problem, um es zu wählen. |
| es | Toca el chip con la flecha hacia arriba junto a un problema para votar por él. |
| fa | برای رأی دادن، روی تراشه با فلش رو به بالا کنار مشکل ضربه بزنید. |
| fr | Appuyez sur la puce avec la flèche vers le haut à côté d'un problème pour voter pour lui. |
| hi | किसी समस्या के लिए वोट देने के लिए उसके बगल वाले अप-एरो चिप पर टैप करें। |
| id | Ketuk chip panah ke atas di sebelah masalah untuk memilihnya. |
| ja | 上向き矢印のチップをタップして問題に投票してください。 |
| ko | 문제 옆의 위쪽 화살표 칩을 탭하여 투표하세요. |
| mr | समस्येला मत देण्यासाठी त्याच्या बाजूच्या वर बाण असलेल्या चिपवर टॅप करा. |
| pa | ਕਿਸੇ ਸਮੱਸਿਆ ਨੂੰ ਵੋਟ ਦੇਣ ਲਈ ਉਸ ਦੇ ਨਾਲ ਉੱਪਰ ਵੱਲ ਤੀਰ ਵਾਲੀ ਚਿੱਪ ਨੂੰ ਟੈਪ ਕਰੋ। |
| pt | Toque no chip com a seta para cima ao lado de um problema para votar nele. |
| ru | Нажмите на чип со стрелкой вверх рядом с проблемой, чтобы проголосовать за неё. |
| sw | Bofya kichipu chenye mshale wa juu kando ya tatizo ili kupiga kura. |
| ta | சிக்கலுக்கு வாக்களிக்க, அதன் அருகே மேல்நோக்கிய அம்பு குறி உள்ள சிப்பை தட்டவும். |
| te | సమస్యకు ఓటు వేయడానికి, దాని పక్కన పైకి బాణం ఉన్న చిప్‌ను నొక్కండి. |
| th | แตะที่ชิปลูกศรขึ้นข้างปัญหาเพื่อโหวต |
| tr | Bir soruna oy vermek için yanındaki yukarı oklu çipe dokunun. |
| uk | Натисніть на чип зі стрілкою вгору поруч із проблемою, щоб проголосувати за неї. |
| ur | کسی مسئلے کو ووٹ دینے کے لیے اس کے ساتھ اوپر کے تیر والی چپ پر ٹیپ کریں۔ |
| vi | Nhấn vào chip có mũi tên hướng lên cạnh vấn đề để bình chọn cho nó. |
| zh | 点击问题旁边带向上箭头的标签来投票。 |

- [ ] **Step 3: Regenerate localizations**

Run: `melos gen`
Expected: gen file lists `String get doubleTapHint;` and `String get voteHint;` and no longer lists `doubleTapHintToast`.

- [ ] **Step 4: Update the one Dart reference**

In [apps/client/lib/problems/view/problems_page.dart](apps/client/lib/problems/view/problems_page.dart), find `context.l10n.doubleTapHintToast` (one call inside `_maybeShowDoubleTapToast`). Change to `context.l10n.doubleTapHint`.

- [ ] **Step 5: Analyze + format**

Run: `flutter analyze apps packages 2>&1 | tail -5`
Run: `melos format`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib/l10n/arb apps/client/lib/problems/view/problems_page.dart
git commit -m "i18n(client): rename doubleTapHintToast -> doubleTapHint; add voteHint"
```

---

## Task 10: New Cloud Function to materialize votesCastCount

**Files:**
- Create: `functions/src/triggers/votes_cast_count.ts`
- Create: `functions/src/triggers/votes_cast_count.test.ts`
- Modify: `functions/src/index.ts`

- [ ] **Step 1: Write the failing test**

Create [functions/src/triggers/votes_cast_count.test.ts](functions/src/triggers/votes_cast_count.test.ts):

```ts
import {describe, expect, it, beforeEach, vi} from "vitest";

// firebase-functions-test offline mode lets us invoke the function
// without a live emulator. Mirrors the pattern used by other trigger
// tests in this codebase.
import firebaseFunctionsTest from "firebase-functions-test";

const testEnv = firebaseFunctionsTest();

// Mock the admin firestore so we can assert against update calls without
// a real backend. We capture the most recent doc + update payload.
const updateMock = vi.fn();
const docMock = vi.fn(() => ({update: updateMock}));
vi.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({doc: docMock}),
  FieldValue: {
    increment: (n: number) => ({__op: "increment", n}),
  },
}));

beforeEach(() => {
  updateMock.mockReset();
  docMock.mockClear();
});

describe("onVoterWrittenForVotesCastCount", () => {
  it("voter-create with votes:1 increments votesCastCount by 1", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 1},
      "problems/p1/voters/u1",
    );
    const change = testEnv.makeChange(null, after);
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({data: change, params: {pid: "p1", actorUid: "u1"}});

    expect(docMock).toHaveBeenCalledWith("users/u1");
    expect(updateMock).toHaveBeenCalledWith({
      votesCastCount: {__op: "increment", n: 1},
    });
  });

  it("voter-update from votes:3 to votes:5 increments votesCastCount by 2", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 5}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).toHaveBeenCalledWith({
      votesCastCount: {__op: "increment", n: 2},
    });
  });

  it("voter-update with no votes change is a no-op", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).not.toHaveBeenCalled();
  });

  it("voter-update where votes decreased is a no-op (monotonic)", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 5}, "problems/p1/voters/u1",
    );
    const after = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, after),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).not.toHaveBeenCalled();
  });

  it("voter-delete is a no-op", async () => {
    const {onVoterWrittenForVotesCastCount} = await import("./votes_cast_count");
    const before = testEnv.firestore.makeDocumentSnapshot(
      {uid: "u1", votes: 3}, "problems/p1/voters/u1",
    );
    const wrapped = testEnv.wrap(onVoterWrittenForVotesCastCount);
    await wrapped({
      data: testEnv.makeChange(before, null),
      params: {pid: "p1", actorUid: "u1"},
    });

    expect(updateMock).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test — expect failure**

Run: `cd functions && npm test -- votes_cast_count`
Expected: failure — `votes_cast_count.ts` doesn't exist yet.

- [ ] **Step 3: Write the function**

Create [functions/src/triggers/votes_cast_count.ts](functions/src/triggers/votes_cast_count.ts):

```ts
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

/**
 * `votesCastCount` materializer.
 *
 * Watches every write to `problems/{pid}/voters/{actorUid}` and propagates
 * the delta into `users/{actorUid}.votesCastCount`. Deliberately monotonic:
 * a voter doc deletion or a `votes` decrement does NOT decrement the user's
 * counter — tip graduation reflects *demonstrated knowledge*, which doesn't
 * un-happen.
 *
 * Runs with admin credentials, bypassing Firestore rules — no rule branch
 * needs to permit writing votesCastCount to an arbitrary value.
 *
 * Sibling to onVoterWritten (which handles the voteReceived notification
 * producer); kept in a separate file because the two have unrelated
 * downstream effects and we want failures in one not to mask the other.
 */
export const onVoterWrittenForVotesCastCount = onDocumentWritten(
  "problems/{pid}/voters/{actorUid}",
  async (event) => {
    const actorUid = event.params.actorUid as string;
    const before = event.data?.before;
    const after = event.data?.after;

    const beforeVotes = (before?.get("votes") as number | undefined) ?? 0;
    const afterVotes = (after?.get("votes") as number | undefined) ?? 0;

    const delta = afterVotes - beforeVotes;
    if (delta <= 0) return;

    await getFirestore()
      .doc(`users/${actorUid}`)
      .update({votesCastCount: FieldValue.increment(delta)});
  },
);
```

- [ ] **Step 4: Re-run test — expect pass**

Run: `cd functions && npm test -- votes_cast_count`
Expected: all 5 cases pass.

- [ ] **Step 5: Export from index**

Append to [functions/src/index.ts](functions/src/index.ts):

```ts
export {onVoterWrittenForVotesCastCount} from "./triggers/votes_cast_count";
```

- [ ] **Step 6: Lint + build**

Run: `cd functions && npm run build`
Expected: build success.

- [ ] **Step 7: Commit**

```bash
git add functions/src/triggers/votes_cast_count.ts \
        functions/src/triggers/votes_cast_count.test.ts \
        functions/src/index.ts
git commit -m "feat(functions): materialize votesCastCount from voter doc writes"
```

---

## Task 11: Banner refactor — split into 3 wrappers; render priority order

**Files:**
- Modify: `apps/client/lib/problems/view/problems_page.dart`

- [ ] **Step 1: Replace the `_SignInHintBanner` block with `_HintBanner` + 3 wrappers**

In [apps/client/lib/problems/view/problems_page.dart](apps/client/lib/problems/view/problems_page.dart), replace the existing widget definition (around line 596) with:

```dart
/// Common styling for an onboarding-tip banner: light-orange surface,
/// indigo text, full-width, centered. Echoes the toast palette so the
/// banner reads as part of the same "system hint" surface.
class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF1A237E),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SignInHintBanner extends StatelessWidget {
  const _SignInHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.signInHintBanner);
}

class _VoteHintBanner extends StatelessWidget {
  const _VoteHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.voteHint);
}

class _DoubleTapHintBanner extends StatelessWidget {
  const _DoubleTapHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.doubleTapHint);
}
```

- [ ] **Step 2: Rewrite the body Column's banner slot**

Find the existing `body: Column(children: [BlocBuilder<UserCubit, UserState>(...)])` (around line 487 after Task 9's rename). Replace the entire `BlocBuilder<UserCubit, UserState>` and its child up through `AddProblemRow` (the first `Column.children` entry only) with:

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
                      builder: (context, geoState) => AddProblemRow(
                        defaultGeoscope: geoState.selectedGeoscope,
                        onSubmit:
                            ({
                              required description,
                              required goal,
                              required geoscope,
                            }) async {
                              final userId =
                                  context.read<UserCubit>().state.userId!;
                              final userLang = Localizations.localeOf(
                                context,
                              ).languageCode;
                              await context.read<ProblemsCubit>().addProblem(
                                description: description,
                                goal: goal,
                                ownerId: userId,
                                userLanguage: userLang,
                                geoscope: geoscope,
                              );
                            },
                      ),
                    ),
                ],
              );
            },
          ),
```

- [ ] **Step 3: Add the toast suppression gate**

In `_maybeShowDoubleTapToast` (around line 119), insert this check after the existing `if (!_isHomeCurrent) return;` line:

```dart
    if (!context.read<UserCubit>().state.needsDoubleTapHint) return;
```

- [ ] **Step 4: Run analyze + format**

Run: `flutter analyze apps packages 2>&1 | tail -5`
Run: `melos format`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/problems/view/problems_page.dart
git commit -m "feat(client): progressive onboarding banner + toast hint gate"
```

---

## Task 12: ProblemReadTile gets onViewDetails prop; wire increment from ProblemsView

**Files:**
- Modify: `apps/client/lib/problems/widgets/problem_read_tile.dart`
- Modify: `apps/client/lib/problems/view/problems_page.dart`

- [ ] **Step 1: Add the prop**

In [apps/client/lib/problems/widgets/problem_read_tile.dart](apps/client/lib/problems/widgets/problem_read_tile.dart) (around line 15–31), update the constructor + fields:

```dart
class ProblemReadTile extends StatelessWidget {
  const ProblemReadTile({
    required this.problem,
    required this.showEditButton,
    required this.showComplaintButton,
    required this.onEdit,
    required this.onCopyLink,
    required this.onComplaint,
    required this.onViewDetails,
    super.key,
  });

  final Problem problem;
  final bool showEditButton;
  final bool showComplaintButton;
  final VoidCallback onEdit;
  final VoidCallback onCopyLink;
  final VoidCallback onComplaint;
  final VoidCallback onViewDetails;
```

- [ ] **Step 2: Use the prop in the GestureDetector**

At line 54 (`onDoubleTap: () => context.push('/problems/${problem.id}'),`), replace with:

```dart
              onDoubleTap: onViewDetails,
```

- [ ] **Step 3: Wire from ProblemsView**

In [apps/client/lib/problems/view/problems_page.dart](apps/client/lib/problems/view/problems_page.dart), find the `ProblemReadTile(...)` construction (around line 581) and add the new prop:

```dart
                          return ProblemReadTile(
                            problem: problem,
                            showEditButton: isOwner,
                            showComplaintButton: userId != null && !isOwner,
                            onEdit: () => _startEdit(problem),
                            onCopyLink: () => _copyProblemLink(problem),
                            onComplaint: () => _confirmComplaint(problem),
                            onViewDetails: () {
                              if (userId != null) {
                                unawaited(
                                  context
                                      .read<FirestoreRepository>()
                                      .incrementProblemDetailsViewCount(userId),
                                );
                              }
                              context.push('/problems/${problem.id}');
                            },
                          );
```

- [ ] **Step 4: Run analyze + format**

Run: `flutter analyze apps packages 2>&1 | tail -5`
Run: `melos format`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/problems/widgets/problem_read_tile.dart \
        apps/client/lib/problems/view/problems_page.dart
git commit -m "feat(client): increment problemDetailsViewCount on double-tap"
```

---

## Task 13: Widget tests for the banner + double-tap increment + toast gate

**Files:**
- Modify: `apps/client/test/problems/view/problems_page_test.dart`

- [ ] **Step 1: Add the new test cases**

In [apps/client/test/problems/view/problems_page_test.dart](apps/client/test/problems/view/problems_page_test.dart), add (inside the existing `ProblemsView` group):

```dart
    testWidgets('banner shows sign-in tip when unauthenticated', (tester) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.unauthenticated),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('Sign in via the icon'), findsOneWidget);
      expect(find.textContaining('vote for it'), findsNothing);
      expect(find.textContaining('Double-tap'), findsNothing);
    });

    testWidgets('banner shows vote tip when needsVoteHint is true', (tester) async {
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 0,
          problemDetailsViewCount: 0,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('vote for it'), findsOneWidget);
      expect(find.textContaining('Double-tap'), findsNothing);
    });

    testWidgets('banner shows double-tap tip when vote graduated', (tester) async {
      // votesCastCount=5 > daysSince=0 → vote tip graduates;
      // problemDetailsViewCount=0 <= daysSince=0 → double-tap tip wins.
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 5,
          problemDetailsViewCount: 0,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('Double-tap'), findsOneWidget);
      expect(find.textContaining('vote for it'), findsNothing);
    });

    testWidgets('banner shows nothing once both tips graduate', (tester) async {
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 99,
          problemDetailsViewCount: 99,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('Sign in'), findsNothing);
      expect(find.textContaining('vote for it'), findsNothing);
      expect(find.textContaining('Double-tap'), findsNothing);
    });

    testWidgets('double-tap fires incrementProblemDetailsViewCount and navigates',
        (tester) async {
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 99,
          problemDetailsViewCount: 99,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(description: 'tap me')],
        ),
      );
      when(() => firestoreRepo.incrementProblemDetailsViewCount(any()))
          .thenAnswer((_) async {});
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.text('tap me'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('tap me')); // second tap → double-tap
      await tester.pumpAndSettle();

      verify(() =>
              firestoreRepo.incrementProblemDetailsViewCount('u1'))
          .called(1);
      // Navigation: verify via the router mock used elsewhere in this file.
    });
```

- [ ] **Step 2: Run tests**

Run: `flutter test apps/client/test/problems/view/problems_page_test.dart`
Expected: all green (existing 30 + 5 new).

- [ ] **Step 3: Commit**

```bash
git add apps/client/test/problems/view/problems_page_test.dart
git commit -m "test(client): cover progressive banner, double-tap counter increment, toast gate"
```

---

## Task 14: Backfill script and its unit test

**Note on language choice:** The spec aspirationally located this script at `tool/backfill_votes_cast_count.dart`. In practice TypeScript under `functions/scripts/` is meaningfully simpler — `firebase-admin/firestore` is already a project dep, vitest is already configured, and there's no need to bootstrap a separate Dart pubspec just for one script. We deviate from the spec on language while preserving behavior.

**Files:**
- Create: `functions/scripts/backfill_votes_cast_count.ts`
- Create: `functions/scripts/backfill_votes_cast_count.test.ts`
- Modify: `functions/package.json` (add `backfill` npm script)
- Modify: `functions/tsconfig.json` (include `scripts/` in build if not already)

- [ ] **Step 1: Write the failing unit test**

Create [functions/scripts/backfill_votes_cast_count.test.ts](functions/scripts/backfill_votes_cast_count.test.ts):

```ts
import {describe, expect, it} from "vitest";

import {computeVotesCastCounts, type UserRow, type VoterRow} from "./backfill_votes_cast_count";

describe("computeVotesCastCounts", () => {
  it("user with no voter docs gets 0", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 0});
  });

  it("user with one voter doc votes:1 gets 1", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [{uid: "u1", votes: 1}];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 1});
  });

  it("user with multiple multi-vote voter docs sums correctly", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [
      {uid: "u1", votes: 3},
      {uid: "u1", votes: 7},
      {uid: "u1", votes: 1},
    ];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 11});
  });

  it("does not mistakenly attribute voter docs to other users", () => {
    const users: UserRow[] = [{uid: "u1"}, {uid: "u2"}];
    const voters: VoterRow[] = [{uid: "u1", votes: 5}];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 5, u2: 0});
  });

  it("ignores voter docs whose uid doesn't match any user", () => {
    const users: UserRow[] = [{uid: "u1"}];
    const voters: VoterRow[] = [{uid: "u-ghost", votes: 99}];
    expect(computeVotesCastCounts(users, voters)).toEqual({u1: 0});
  });
});
```

- [ ] **Step 2: Run test — expect failure**

Run: `cd functions && npm test -- backfill_votes_cast_count`
Expected: failure — file doesn't exist.

- [ ] **Step 3: Write the script**

Create [functions/scripts/backfill_votes_cast_count.ts](functions/scripts/backfill_votes_cast_count.ts):

```ts
// One-shot backfill: populate `users/{uid}.votesCastCount` from each
// user's `problems/.../voters/{uid}` history. Run BEFORE deploying the
// new Cloud Function that maintains votesCastCount going forward.
//
// Usage (against production Firestore via Application Default Credentials):
//
//   gcloud auth application-default login
//   cd functions && npm run backfill
//
// Idempotent — safe to re-run.

import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

export type UserRow = {uid: string};
export type VoterRow = {uid: string; votes: number};

/**
 * Pure count-aggregation: takes the full user and voter lists, returns
 * a map of `uid -> total lifetime votes cast`. Side-effect-free so we
 * can unit-test it without a Firestore mock.
 */
export function computeVotesCastCounts(
  users: ReadonlyArray<UserRow>,
  voters: ReadonlyArray<VoterRow>,
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const u of users) {
    counts[u.uid] = 0;
  }
  for (const v of voters) {
    if (counts[v.uid] === undefined) continue; // ghost vote, no user doc
    counts[v.uid] += v.votes;
  }
  return counts;
}

/** Production entry point: reads from Firestore, computes, writes back. */
export async function main(): Promise<void> {
  if (getApps().length === 0) initializeApp();
  const firestore = getFirestore();

  console.log("Reading users/ ...");
  const usersSnap = await firestore.collection("users").get();
  const users: UserRow[] = usersSnap.docs.map((d) => ({uid: d.id}));

  console.log(`Reading voters/ (collection group) ... ${users.length} users`);
  const votersSnap = await firestore.collectionGroup("voters").get();
  const voters: VoterRow[] = votersSnap.docs.map((d) => ({
    uid: (d.get("uid") as string) ?? "",
    votes: (d.get("votes") as number | undefined) ?? 0,
  }));

  const counts = computeVotesCastCounts(users, voters);

  let touched = 0;
  for (const [uid, sum] of Object.entries(counts)) {
    await firestore.collection("users").doc(uid).update({
      votesCastCount: sum,
    });
    touched++;
  }
  console.log(`Done. ${touched} user(s) updated.`);
}

// Invoke when run as a CLI script (not when imported by tests).
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
```

- [ ] **Step 4: Add npm script**

Edit [functions/package.json](functions/package.json). Inside `"scripts"`, add:

```json
"backfill": "tsx scripts/backfill_votes_cast_count.ts"
```

If `tsx` isn't already a dev-dep (check `devDependencies`), add it:

```bash
cd functions && npm install --save-dev tsx
```

- [ ] **Step 5: Re-run test — expect pass**

Run: `cd functions && npm test -- backfill_votes_cast_count`
Expected: all 5 cases pass.

- [ ] **Step 6: Smoke-test against the emulator (optional but recommended)**

In one terminal: `firebase emulators:start --only firestore`
In another:

```bash
cd functions
GOOGLE_CLOUD_PROJECT=votasq FIRESTORE_EMULATOR_HOST=localhost:8081 npm run backfill
```

Expected: completes without error, even with an empty users collection (touched: 0).

- [ ] **Step 7: Commit**

```bash
git add functions/scripts/backfill_votes_cast_count.ts \
        functions/scripts/backfill_votes_cast_count.test.ts \
        functions/package.json functions/package-lock.json
git commit -m "feat(functions): backfill script for users/{uid}.votesCastCount"
```

---

## Task 15: Run the full suite + analyze; final cleanup commit if needed

**Files:** any leftover format/lint issues.

- [ ] **Step 1: Full client test run**

Run: `cd apps/client && flutter test`
Expected: all green.

- [ ] **Step 2: Full analyze**

Run: `flutter analyze apps packages 2>&1 | tail -5`
Expected: "No issues found!"

- [ ] **Step 3: Format**

Run: `melos format`
Expected: format clean (0 changed).

- [ ] **Step 4: Functions test + build**

Run: `cd functions && npm test && npm run build`
Expected: all green, build success.

- [ ] **Step 5: E2E test (rules)**

In one terminal: `firebase emulators:start --only auth,firestore`
In another, from the project root: `dart test apps/server/e2e/firestore_rules_e2e_test.dart --tags e2e`
Expected: all rule tests pass, including the new ones from Task 3.

- [ ] **Step 6: Commit anything cleanup-related (or skip if nothing to commit)**

If formatter or analyzer asked for changes that surface only with the full project compiled, fix them and:

```bash
git add -A
git commit -m "chore: post-feature lint/format cleanup"
```

If nothing changed, skip this step.

---

## Post-implementation: deployment hand-off

The code changes are complete. Follow the deployment order from
[the spec's Migration section](../specs/2026-05-23-progressive-onboarding-banner-design.md#deployment-order):

1. Deploy `firestore.rules`.
2. Deploy `firestore.indexes.json` (await index build).
3. From `functions/`, run `npm run backfill` against the prod project (ADC-authenticated).
4. `firebase deploy --only functions:onVoterWrittenForVotesCastCount`.
5. Release the new client (web + Android + macOS).

If the gap between step 3 and step 4 takes more than a few minutes during business hours, re-run the backfill after step 4 to recover any votes cast during the gap.
