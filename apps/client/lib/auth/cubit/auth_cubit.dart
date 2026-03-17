import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/auth/cubit/auth_state.dart';
import 'package:client/auth/data/auth_repository.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository) : super(const AuthState()) {
    _subscription = _authRepository.authStateChanges.listen(
      (user) {
        if (user != null) {
          emit(
            state.copyWith(
              status: AuthStatus.authenticated,
              userId: () => user.uid,
            ),
          );
        } else {
          emit(
            state.copyWith(
              status: AuthStatus.unauthenticated,
              userId: () => null,
            ),
          );
        }
      },
      onError: (Object e, StackTrace st) {
        log('authStateChanges error: $e', stackTrace: st);
        emit(
          state.copyWith(
            status: AuthStatus.unauthenticated,
            userId: () => null,
          ),
        );
      },
    );
  }

  final AuthRepository _authRepository;
  StreamSubscription<dynamic>? _subscription;

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
    await _subscription?.cancel();
    return super.close();
  }
}
