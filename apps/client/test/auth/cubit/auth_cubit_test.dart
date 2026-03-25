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
      () => firestoreRepo.watchUserVotes(any()),
    ).thenAnswer((_) => Stream.value(initialVoteBudget));
  });

  group('AuthCubit', () {
    test('initial state is unknown with null userId', () {
      final cubit = AuthCubit(authRepo, firestoreRepo);
      expect(cubit.state.status, AuthStatus.unknown);
      expect(cubit.state.userId, isNull);
      addTearDown(cubit.close);
    });

    blocTest<AuthCubit, AuthState>(
      'emits authenticated when auth stream fires user',
      build: () {
        final user = _MockFirebaseUser();
        when(
          () => authRepo.authStateChanges,
        ).thenAnswer((_) => Stream.value(user));
        return AuthCubit(authRepo, firestoreRepo);
      },
      expect: () => [
        isA<AuthState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having((s) => s.userId, 'userId', 'test-uid-123'),
        isA<AuthState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having((s) => s.userId, 'userId', 'test-uid-123')
            .having(
              (s) => s.remainingVotes,
              'remainingVotes',
              initialVoteBudget,
            ),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'emits unauthenticated when auth stream fires null',
      build: () {
        when(
          () => authRepo.authStateChanges,
        ).thenAnswer((_) => Stream<firebase.User?>.value(null));
        return AuthCubit(authRepo, firestoreRepo);
      },
      expect: () => [
        isA<AuthState>()
            .having((s) => s.status, 'status', AuthStatus.unauthenticated)
            .having((s) => s.userId, 'userId', isNull),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'signIn delegates to repository',
      build: () {
        when(
          () => authRepo.signInWithGoogle(),
        ).thenThrow(Exception('not implemented'));
        return AuthCubit(authRepo, firestoreRepo);
      },
      act: (cubit) => cubit.signIn(),
      verify: (_) {
        verify(() => authRepo.signInWithGoogle()).called(1);
      },
    );

    blocTest<AuthCubit, AuthState>(
      'signOut delegates to repository',
      build: () {
        when(() => authRepo.signOut()).thenAnswer((_) async {});
        return AuthCubit(authRepo, firestoreRepo);
      },
      act: (cubit) => cubit.signOut(),
      verify: (_) {
        verify(() => authRepo.signOut()).called(1);
      },
    );
  });
}
