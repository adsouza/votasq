import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:client/auth/auth.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockFirebaseUser extends Mock implements firebase.User {
  @override
  String get uid => 'test-uid-123';
}

void main() {
  late AuthRepository authRepo;
  late FirestoreRepository firestoreRepo;

  setUpAll(() {
    registerFallbackValue(
      User(uid: '', votes: 0, lastActiveAt: DateTime.utc(2026)),
    );
  });

  setUp(() {
    authRepo = _MockAuthRepository();
    firestoreRepo = _MockFirestoreRepository();
    when(
      () => authRepo.authStateChanges,
    ).thenAnswer((_) => const Stream<firebase.User?>.empty());
    when(
      () => firestoreRepo.ensureUserDoc(any()),
    ).thenAnswer(
      (_) async => User(
        uid: 'test-uid-123',
        votes: initialVoteBudget,
        lastActiveAt: DateTime.utc(2024),
      ),
    );
    when(
      () => firestoreRepo.watchUserDoc(any()),
    ).thenAnswer(
      (_) => Stream.value(
        User(
          uid: 'test-uid-123',
          votes: initialVoteBudget,
          lastActiveAt: DateTime.utc(2024),
        ),
      ),
    );
    when(
      () => firestoreRepo.grantVotesAndTouch(any()),
    ).thenAnswer((_) async {});
  });

  group('UserCubit', () {
    test('initial state is unknown with null userId', () {
      final cubit = UserCubit(authRepo, firestoreRepo);
      expect(cubit.state.status, AuthStatus.unknown);
      expect(cubit.state.userId, isNull);
      addTearDown(cubit.close);
    });

    blocTest<UserCubit, UserState>(
      'emits authenticated when auth stream fires user',
      build: () {
        final user = _MockFirebaseUser();
        when(
          () => authRepo.authStateChanges,
        ).thenAnswer((_) => Stream.value(user));
        return UserCubit(authRepo, firestoreRepo);
      },
      expect: () => [
        // 1) auth state fires: authenticated + userId
        isA<UserState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having((s) => s.userId, 'userId', 'test-uid-123')
            .having((s) => s.remainingVotes, 'remainingVotes', isNull),
        // 2) ensureUserDoc returns: sessionStartLastActiveAt frozen
        isA<UserState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having((s) => s.userId, 'userId', 'test-uid-123')
            .having(
              (s) => s.sessionStartLastActiveAt,
              'sessionStartLastActiveAt',
              DateTime.utc(2024),
            ),
        // 3) watchUserDoc emits: remainingVotes + counters
        isA<UserState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having((s) => s.userId, 'userId', 'test-uid-123')
            .having(
              (s) => s.remainingVotes,
              'remainingVotes',
              initialVoteBudget,
            ),
      ],
    );

    blocTest<UserCubit, UserState>(
      'emits unauthenticated when auth stream fires null',
      build: () {
        when(
          () => authRepo.authStateChanges,
        ).thenAnswer((_) => Stream<firebase.User?>.value(null));
        return UserCubit(authRepo, firestoreRepo);
      },
      expect: () => [
        isA<UserState>()
            .having((s) => s.status, 'status', AuthStatus.unauthenticated)
            .having((s) => s.userId, 'userId', isNull),
      ],
    );

    blocTest<UserCubit, UserState>(
      'signIn delegates to repository',
      build: () {
        when(
          () => authRepo.signInWithGoogle(),
        ).thenThrow(Exception('not implemented'));
        return UserCubit(authRepo, firestoreRepo);
      },
      act: (cubit) => cubit.signIn(),
      verify: (_) {
        verify(() => authRepo.signInWithGoogle()).called(1);
      },
    );

    blocTest<UserCubit, UserState>(
      'signOut delegates to repository',
      build: () {
        when(() => authRepo.signOut()).thenAnswer((_) async {});
        return UserCubit(authRepo, firestoreRepo);
      },
      act: (cubit) => cubit.signOut(),
      verify: (_) {
        verify(() => authRepo.signOut()).called(1);
      },
    );

    blocTest<UserCubit, UserState>(
      'sessionStartLastActiveAt is captured from the existing doc',
      build: () {
        when(() => firestoreRepo.ensureUserDoc(any())).thenAnswer(
          (_) async => User(
            uid: 'test-uid-123',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 20),
            problemDetailsViewCount: 4,
            votesCastCount: 2,
          ),
        );
        when(
          () => firestoreRepo.grantVotesAndTouch(any()),
        ).thenAnswer((_) async {});
        when(() => firestoreRepo.watchUserDoc(any())).thenAnswer(
          (_) => const Stream<User?>.empty(),
        );
        when(() => authRepo.authStateChanges).thenAnswer(
          (_) => Stream.value(_MockFirebaseUser()),
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
        final ctrl = StreamController<User?>();
        addTearDown(ctrl.close);
        when(() => firestoreRepo.ensureUserDoc(any())).thenAnswer(
          (_) async => User(
            uid: 'test-uid-123',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 20),
          ),
        );
        when(
          () => firestoreRepo.grantVotesAndTouch(any()),
        ).thenAnswer((_) async {});
        when(
          () => firestoreRepo.watchUserDoc(any()),
        ).thenAnswer((_) => ctrl.stream);
        when(() => authRepo.authStateChanges).thenAnswer(
          (_) => Stream.value(_MockFirebaseUser()),
        );
        final cubit = UserCubit(authRepo, firestoreRepo);
        Future.delayed(const Duration(milliseconds: 20), () {
          ctrl.add(
            User(
              uid: 'test-uid-123',
              votes: 3,
              lastActiveAt: DateTime.utc(2026, 5, 23), // moved forward
            ),
          );
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
          (_) async => User(
            uid: 'test-uid-123',
            votes: 3,
            lastActiveAt: DateTime.utc(2026, 5, 20),
          ),
        );
        when(
          () => firestoreRepo.grantVotesAndTouch(any()),
        ).thenAnswer((_) async {});
        when(() => firestoreRepo.watchUserDoc(any())).thenAnswer(
          (_) => Stream.value(
            User(
              uid: 'test-uid-123',
              votes: 2,
              lastActiveAt: DateTime.utc(2026, 5, 23),
              problemDetailsViewCount: 7,
              votesCastCount: 5,
            ),
          ),
        );
        when(() => authRepo.authStateChanges).thenAnswer(
          (_) => Stream.value(_MockFirebaseUser()),
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
  });
}
