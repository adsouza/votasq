import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

// DocumentSnapshot is @sealed but we need a testable stand-in for state.
// ignore: subtype_of_sealed_class
class _FakeDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {}

Problem _problem({
  String id = '1',
  String description = 'test problem one',
  String goal = '',
  String ownerId = 'user1',
  String geoscope = '/',
  int votes = 1,
  DateTime? lastUpdatedAt,
}) {
  final now = DateTime.utc(2024);
  return Problem(
    id: id,
    description: description,
    goal: goal,
    ownerId: ownerId,
    geoscope: geoscope,
    votes: votes,
    createdAt: now,
    lastUpdatedAt: lastUpdatedAt ?? now,
  );
}

void main() {
  late FirestoreRepository repo;

  setUpAll(() {
    registerFallbackValue(_problem());
  });

  setUp(() {
    repo = _MockFirestoreRepository();
  });

  group('ProblemsCubit', () {
    test('initial state is correct', () {
      final cubit = ProblemsCubit(repo);
      expect(cubit.state.status, ProblemsStatus.initial);
      expect(cubit.state.problems, isEmpty);
      expect(cubit.state.geoscope, '/');
      expect(cubit.state.hasMore, isTrue);
      addTearDown(cubit.close);
    });

    blocTest<ProblemsCubit, ProblemsState>(
      'subscribe emits loading then success',
      build: () {
        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) => Stream.value((
            problems: [_problem()],
            lastDoc: _FakeDocumentSnapshot(),
            isFromCache: false,
          )),
        );
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.subscribe(),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.status,
          'status',
          ProblemsStatus.loading,
        ),
        isA<ProblemsState>()
            .having((s) => s.status, 'status', ProblemsStatus.success)
            .having((s) => s.problems, 'problems', hasLength(1)),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'subscribe emits failure on error',
      build: () {
        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) => Stream.error(Exception('fail')),
        );
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.subscribe(),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.status,
          'status',
          ProblemsStatus.loading,
        ),
        isA<ProblemsState>().having(
          (s) => s.status,
          'status',
          ProblemsStatus.failure,
        ),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'orders same-vote problems by lastUpdatedAt DESC (most recent first)',
      build: () {
        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) => Stream.value((
            problems: [
              _problem(
                id: 'older',
                votes: 5,
                lastUpdatedAt: DateTime.utc(2024),
              ),
              _problem(
                id: 'newer',
                votes: 5,
                lastUpdatedAt: DateTime.utc(2024, 6),
              ),
            ],
            lastDoc: _FakeDocumentSnapshot(),
            isFromCache: false,
          )),
        );
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.subscribe(),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.status,
          'status',
          ProblemsStatus.loading,
        ),
        isA<ProblemsState>().having(
          (s) => s.problems.map((p) => p.id).toList(),
          'newest within the vote tier first',
          ['newer', 'older'],
        ),
      ],
    );

    test(
      'eager-load stops at the 1-vote tier (those problems load on scroll)',
      () async {
        // A full live window (9) of multi-vote problems => hasMore.
        final window = [
          for (var i = 0; i < 9; i++) _problem(id: 'w$i', votes: 5),
        ];
        // The first background page reaches the 1-vote tier. The loader should
        // stop here and NOT fetch a second page — the rest of the 1-vote tier
        // loads only when the user scrolls.
        final page1 = [
          for (var i = 0; i < 8; i++) _problem(id: 'a$i', votes: 2),
          _problem(id: 'one'), // 1 vote (helper default)
        ];
        var calls = 0;
        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) => Stream.value((
            problems: window,
            lastDoc: _FakeDocumentSnapshot(),
            isFromCache: false,
          )),
        );
        when(
          () => repo.getProblems(
            geoscope: any(named: 'geoscope'),
            startAfter: any(named: 'startAfter'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer((_) async {
          calls++;
          return (problems: page1, lastDoc: _FakeDocumentSnapshot());
        });

        final cubit = ProblemsCubit(repo)..subscribe();
        addTearDown(cubit.close);

        for (var i = 0; i < 15; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // Exactly one background fetch: it stopped at the page that reached the
        // 1-vote tier instead of paging further into it.
        expect(calls, 1);
        expect(cubit.state.problems.any((p) => p.id == 'one'), isTrue);
      },
    );

    test(
      'eager-load and pagination wait for a server snapshot, ignoring cache',
      () async {
        // Regression: against prod (web persistence ON) the first watch
        // snapshot is served from the offline cache. Seeding the cursor/eager
        // loader from a stale cache snapshot stalled pagination (~12 stuck).
        // The emulator runs with persistence disabled, so this never showed
        // in earlier tests.
        final window = [
          for (var i = 0; i < 20; i++)
            _problem(id: 'w${i.toString().padLeft(2, '0')}', votes: 5),
        ];
        final page = [_problem(id: 'p0', votes: 4), _problem(id: 'fresh')];
        final controller =
            StreamController<
              ({
                List<Problem> problems,
                DocumentSnapshot? lastDoc,
                bool isFromCache,
              })
            >();
        addTearDown(controller.close);
        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) => controller.stream);
        when(
          () => repo.getProblems(
            geoscope: any(named: 'geoscope'),
            startAfter: any(named: 'startAfter'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => (problems: page, lastDoc: _FakeDocumentSnapshot()),
        );

        final cubit = ProblemsCubit(repo)..subscribe();
        addTearDown(cubit.close);

        // Cache snapshot: shown for a fast paint, but must NOT page.
        controller.add((
          problems: window,
          lastDoc: _FakeDocumentSnapshot(),
          isFromCache: true,
        ));
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(cubit.state.problems, hasLength(20));
        verifyNever(
          () => repo.getProblems(
            geoscope: any(named: 'geoscope'),
            startAfter: any(named: 'startAfter'),
            pageSize: any(named: 'pageSize'),
          ),
        );

        // Server snapshot: now the eager loader runs and reaches the tier.
        controller.add((
          problems: window,
          lastDoc: _FakeDocumentSnapshot(),
          isFromCache: false,
        ));
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(cubit.state.problems.any((p) => p.id == 'fresh'), isTrue);
        verify(
          () => repo.getProblems(
            geoscope: any(named: 'geoscope'),
            startAfter: any(named: 'startAfter'),
            pageSize: any(named: 'pageSize'),
          ),
        ).called(1);
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'loadMore appends problems',
      build: () {
        when(
          () => repo.getProblems(
            geoscope: any(named: 'geoscope'),
            startAfter: any(named: 'startAfter'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => (
            problems: [_problem(id: '2', description: 'second problem here')],
            lastDoc: _FakeDocumentSnapshot(),
          ),
        );
        return ProblemsCubit(repo);
      },
      seed: () => ProblemsState(
        status: ProblemsStatus.success,
        problems: [_problem()],
        lastDocument: _FakeDocumentSnapshot(),
      ),
      act: (cubit) => cubit.loadMore(),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.problems,
          'problems',
          hasLength(2),
        ),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'loadMore does nothing when hasMore is false',
      build: () => ProblemsCubit(repo),
      seed: () => ProblemsState(
        status: ProblemsStatus.success,
        problems: [_problem()],
        hasMore: false,
      ),
      act: (cubit) => cubit.loadMore(),
      expect: () => <ProblemsState>[],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'changeGeoscope resets state and resubscribes',
      build: () {
        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) => const Stream.empty());
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.changeGeoscope('us/nyc'),
      expect: () => [
        isA<ProblemsState>()
            .having((s) => s.geoscope, 'geoscope', 'us/nyc')
            .having((s) => s.problems, 'problems', isEmpty),
        isA<ProblemsState>()
            .having((s) => s.status, 'status', ProblemsStatus.loading)
            .having((s) => s.geoscope, 'geoscope', 'us/nyc'),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'addProblem calls repo with state geoscope',
      build: () {
        when(
          () => repo.addProblem(
            description: any(named: 'description'),
            goal: any(named: 'goal'),
            ownerId: any(named: 'ownerId'),
            geoscope: any(named: 'geoscope'),
            userLanguage: any(named: 'userLanguage'),
          ),
        ).thenAnswer((_) async => _problem(description: 'a new problem'));
        return ProblemsCubit(repo);
      },
      seed: () => const ProblemsState(geoscope: 'us/nyc'),
      act: (cubit) => cubit.addProblem(
        description: 'a new problem',
        ownerId: 'user1',
        userLanguage: 'en',
      ),
      verify: (_) {
        verify(
          () => repo.addProblem(
            description: 'a new problem',
            ownerId: 'user1',
            geoscope: 'us/nyc',
            userLanguage: 'en',
          ),
        ).called(1);
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'addProblem inserts the new problem at its sorted position and '
      'requests a scroll to it',
      build: () {
        when(
          () => repo.addProblem(
            description: any(named: 'description'),
            goal: any(named: 'goal'),
            ownerId: any(named: 'ownerId'),
            geoscope: any(named: 'geoscope'),
            userLanguage: any(named: 'userLanguage'),
          ),
        ).thenAnswer(
          // Both are 1-vote, so they sort by id ASC: 'existing' before 'new'.
          // The new problem lands at the bottom of the 1-vote tier rather than
          // being artificially prepended.
          (_) async => _problem(id: 'new', description: 'a new problem'),
        );
        return ProblemsCubit(repo);
      },
      seed: () => ProblemsState(problems: [_problem(id: 'existing')]),
      act: (cubit) => cubit.addProblem(
        description: 'a new problem',
        ownerId: 'user1',
        userLanguage: 'en',
      ),
      expect: () => [
        isA<ProblemsState>()
            .having(
              (s) => s.problems.map((p) => p.id).toList(),
              'problems order',
              ['existing', 'new'],
            )
            .having(
              (s) => s.scrollRequest?.problemId,
              'scroll target',
              'new',
            ),
      ],
    );

    // Reproduces the web-only doubling: on web the Firestore JS SDK fires
    // the watch listener synchronously from the local cache before
    // `await repo.addProblem(...)` returns, so the cubit's subscribe
    // handler has already inserted the new problem (at its sorted
    // position) by the time `addProblem` reaches its prepend. A blind
    // prepend would then duplicate the doc. We model that ordering by
    // pushing a snapshot onto the watch stream from inside the mocked
    // addProblem call.
    test(
      'addProblem does not duplicate when watch stream already emitted the '
      'new problem',
      () async {
        final existing = _problem(id: 'existing', votes: 5);
        final created = _problem(
          id: 'new',
          description: 'a new problem',
        );
        final controller =
            StreamController<
              ({
                List<Problem> problems,
                DocumentSnapshot? lastDoc,
                bool isFromCache,
              })
            >();
        addTearDown(controller.close);

        when(
          () => repo.watchProblems(
            geoscope: any(named: 'geoscope'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) => controller.stream);

        when(
          () => repo.addProblem(
            description: any(named: 'description'),
            goal: any(named: 'goal'),
            ownerId: any(named: 'ownerId'),
            geoscope: any(named: 'geoscope'),
            userLanguage: any(named: 'userLanguage'),
          ),
        ).thenAnswer((_) async {
          // Simulate the web JS SDK firing the listener from cache
          // (snapshot lists existing first by votes DESC, then the new
          // problem at its sorted position) before this future resolves.
          controller.add((
            problems: [existing, created],
            lastDoc: _FakeDocumentSnapshot(),
            isFromCache: false,
          ));
          await Future<void>.delayed(Duration.zero);
          return created;
        });

        final cubit = ProblemsCubit(repo)..subscribe();
        addTearDown(cubit.close);
        controller.add((
          problems: [existing],
          lastDoc: _FakeDocumentSnapshot(),
          isFromCache: false,
        ));
        await Future<void>.delayed(Duration.zero);

        await cubit.addProblem(
          description: 'a new problem',
          ownerId: 'user1',
          userLanguage: 'en',
        );

        // existing has 5 votes, new has 1, so the honest sort is
        // [existing, new] — and there's exactly one copy of 'new'.
        expect(
          cubit.state.problems.map((p) => p.id).toList(),
          ['existing', 'new'],
        );
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'addProblem passes goal to repo',
      build: () {
        when(
          () => repo.addProblem(
            description: any(named: 'description'),
            goal: any(named: 'goal'),
            ownerId: any(named: 'ownerId'),
            geoscope: any(named: 'geoscope'),
            userLanguage: any(named: 'userLanguage'),
          ),
        ).thenAnswer((_) async => _problem(goal: 'reduce traffic jams'));
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.addProblem(
        description: 'a new problem',
        goal: 'reduce traffic jams',
        ownerId: 'user1',
        userLanguage: 'en',
      ),
      verify: (_) {
        verify(
          () => repo.addProblem(
            description: 'a new problem',
            goal: 'reduce traffic jams',
            ownerId: 'user1',
            geoscope: '/',
            userLanguage: 'en',
          ),
        ).called(1);
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'addProblem uses override geoscope when provided',
      build: () {
        when(
          () => repo.addProblem(
            description: any(named: 'description'),
            goal: any(named: 'goal'),
            ownerId: any(named: 'ownerId'),
            geoscope: any(named: 'geoscope'),
            userLanguage: any(named: 'userLanguage'),
          ),
        ).thenAnswer((_) async => _problem());
        return ProblemsCubit(repo);
      },
      seed: () => const ProblemsState(geoscope: 'us/nyc'),
      act: (cubit) => cubit.addProblem(
        description: 'a new problem',
        ownerId: 'user1',
        userLanguage: 'en',
        geoscope: '/',
      ),
      verify: (_) {
        verify(
          () => repo.addProblem(
            description: 'a new problem',
            ownerId: 'user1',
            geoscope: '/',
            userLanguage: any(named: 'userLanguage'),
          ),
        ).called(1);
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'addProblem handles repo exception gracefully',
      build: () {
        when(
          () => repo.addProblem(
            description: any(named: 'description'),
            goal: any(named: 'goal'),
            ownerId: any(named: 'ownerId'),
            geoscope: any(named: 'geoscope'),
            userLanguage: any(named: 'userLanguage'),
          ),
        ).thenThrow(Exception('fail'));
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.addProblem(
        description: 'a new problem',
        ownerId: 'user1',
        userLanguage: 'en',
      ),
      expect: () => <ProblemsState>[],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'vote calls repo',
      build: () {
        when(
          () => repo.vote(
            problemId: any(named: 'problemId'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async {});
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.vote(problemId: '1', userId: 'user1'),
      verify: (_) {
        verify(
          () => repo.vote(problemId: '1', userId: 'user1'),
        ).called(1);
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'vote handles repo exception gracefully',
      build: () {
        when(
          () => repo.vote(
            problemId: any(named: 'problemId'),
            userId: any(named: 'userId'),
          ),
        ).thenThrow(Exception('fail'));
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.vote(problemId: '1', userId: 'user1'),
      expect: () => <ProblemsState>[],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'vote optimistically increments, re-sorts, and requests a scroll',
      build: () {
        when(
          () => repo.vote(
            problemId: any(named: 'problemId'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async {});
        return ProblemsCubit(repo);
      },
      seed: () => ProblemsState(
        status: ProblemsStatus.success,
        problems: [
          _problem(id: 'low'), // 1 vote (the helper default)
          _problem(id: 'high', votes: 3),
        ],
      ),
      act: (cubit) => cubit.vote(problemId: 'low', userId: 'user1'),
      expect: () => [
        isA<ProblemsState>()
            .having(
              (s) => s.problems.map((p) => '${p.id}:${p.votes}').toList(),
              'reordered with the bumped vote',
              ['high:3', 'low:2'],
            )
            .having((s) => s.scrollRequest?.problemId, 'scroll target', 'low'),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'vote reverts the optimistic bump when the repo write fails',
      build: () {
        when(
          () => repo.vote(
            problemId: any(named: 'problemId'),
            userId: any(named: 'userId'),
          ),
        ).thenThrow(Exception('fail'));
        return ProblemsCubit(repo);
      },
      seed: () => ProblemsState(
        status: ProblemsStatus.success,
        problems: [
          _problem(id: 'low'), // 1 vote (the helper default)
          _problem(id: 'high', votes: 3),
        ],
      ),
      act: (cubit) => cubit.vote(problemId: 'low', userId: 'user1'),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.problems.map((p) => '${p.id}:${p.votes}').toList(),
          'optimistic bump',
          ['high:3', 'low:2'],
        ),
        isA<ProblemsState>().having(
          (s) => s.problems.map((p) => '${p.id}:${p.votes}').toList(),
          'reverted',
          ['high:3', 'low:1'],
        ),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'updateProblem calls repo',
      build: () {
        when(() => repo.updateProblem(any())).thenAnswer((_) async {});
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.updateProblem(_problem()),
      verify: (_) {
        verify(() => repo.updateProblem(any())).called(1);
      },
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'updateProblem handles repo exception gracefully',
      build: () {
        when(() => repo.updateProblem(any())).thenThrow(Exception('fail'));
        return ProblemsCubit(repo);
      },
      act: (cubit) => cubit.updateProblem(_problem()),
      expect: () => <ProblemsState>[],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'updateProblem swaps the local copy of the saved problem',
      build: () {
        when(() => repo.updateProblem(any())).thenAnswer((_) async {});
        return ProblemsCubit(repo);
      },
      seed: () => ProblemsState(
        problems: [
          _problem(id: 'a', description: 'old A'),
          _problem(id: 'b', description: 'B'),
        ],
      ),
      act: (cubit) =>
          cubit.updateProblem(_problem(id: 'a', description: 'new A')),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.problems.map((p) => p.description).toList(),
          'descriptions',
          ['new A', 'B'],
        ),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'applyLocalUpdate replaces a matching problem in the list',
      build: () => ProblemsCubit(repo),
      seed: () => ProblemsState(
        problems: [
          _problem(id: 'a', description: 'old A'),
          _problem(id: 'b', description: 'B'),
        ],
      ),
      act: (cubit) =>
          cubit.applyLocalUpdate(_problem(id: 'a', description: 'new A')),
      expect: () => [
        isA<ProblemsState>().having(
          (s) => s.problems.map((p) => p.description).toList(),
          'descriptions',
          ['new A', 'B'],
        ),
      ],
    );

    blocTest<ProblemsCubit, ProblemsState>(
      'applyLocalUpdate is a no-op when the problem is not in the list',
      build: () => ProblemsCubit(repo),
      seed: () => ProblemsState(
        problems: [_problem(id: 'a', description: 'A')],
      ),
      act: (cubit) =>
          cubit.applyLocalUpdate(_problem(id: 'missing', description: 'X')),
      expect: () => <ProblemsState>[],
    );

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
          problems: [
            _problem(id: 'a'),
            _problem(id: 'b'),
          ],
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
          problems: [
            _problem(id: 'a'),
            _problem(id: 'b'),
          ],
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
  });
}
