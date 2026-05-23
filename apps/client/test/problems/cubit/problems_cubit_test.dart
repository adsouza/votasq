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
    lastUpdatedAt: now,
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
          (_) => Stream.value(
            (problems: [_problem()], lastDoc: _FakeDocumentSnapshot()),
          ),
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
      'addProblem optimistically prepends the new problem to state',
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
        isA<ProblemsState>().having(
          (s) => s.problems.map((p) => p.id).toList(),
          'problems order',
          ['new', 'existing'],
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
              ({List<Problem> problems, DocumentSnapshot? lastDoc})
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
          controller.add(
            (
              problems: [existing, created],
              lastDoc: _FakeDocumentSnapshot(),
            ),
          );
          await Future<void>.delayed(Duration.zero);
          return created;
        });

        final cubit = ProblemsCubit(repo)..subscribe();
        addTearDown(cubit.close);
        controller.add(
          (problems: [existing], lastDoc: _FakeDocumentSnapshot()),
        );
        await Future<void>.delayed(Duration.zero);

        await cubit.addProblem(
          description: 'a new problem',
          ownerId: 'user1',
          userLanguage: 'en',
        );

        expect(
          cubit.state.problems.map((p) => p.id).toList(),
          ['new', 'existing'],
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
