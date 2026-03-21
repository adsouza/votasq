import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:client/auth/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid-123';
}

void main() {
  late AuthRepository authRepo;

  setUp(() {
    authRepo = _MockAuthRepository();
    when(
      () => authRepo.authStateChanges,
    ).thenAnswer((_) => const Stream<User?>.empty());
  });

  group('AuthCubit', () {
    test('initial state is unknown with null userId', () {
      final cubit = AuthCubit(authRepo);
      expect(cubit.state.status, AuthStatus.unknown);
      expect(cubit.state.userId, isNull);
      addTearDown(cubit.close);
    });

    blocTest<AuthCubit, AuthState>(
      'emits authenticated when auth stream fires user',
      build: () {
        final user = _MockUser();
        when(
          () => authRepo.authStateChanges,
        ).thenAnswer((_) => Stream.value(user));
        return AuthCubit(authRepo);
      },
      expect: () => [
        isA<AuthState>()
            .having((s) => s.status, 'status', AuthStatus.authenticated)
            .having((s) => s.userId, 'userId', 'test-uid-123'),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'emits unauthenticated when auth stream fires null',
      build: () {
        when(
          () => authRepo.authStateChanges,
        ).thenAnswer((_) => Stream<User?>.value(null));
        return AuthCubit(authRepo);
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
        return AuthCubit(authRepo);
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
        return AuthCubit(authRepo);
      },
      act: (cubit) => cubit.signOut(),
      verify: (_) {
        verify(() => authRepo.signOut()).called(1);
      },
    );
  });
}
