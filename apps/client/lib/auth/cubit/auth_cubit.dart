import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/auth/cubit/auth_state.dart';
import 'package:client/auth/data/auth_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:shared/shared.dart' as shared;

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository, this._firestoreRepository)
    : super(const AuthState()) {
    _subscription = _authRepository.authStateChanges.listen(
      (user) {
        if (user != null) {
          emit(
            state.copyWith(
              status: AuthStatus.authenticated,
              userId: () => user.uid,
            ),
          );
          unawaited(_initUserVotes(user.uid, user.displayName));
        } else {
          unawaited(_userVotesSubscription?.cancel());
          _userVotesSubscription = null;
          emit(
            state.copyWith(
              status: AuthStatus.unauthenticated,
              userId: () => null,
              remainingVotes: () => null,
            ),
          );
        }
      },
      onError: (Object e, StackTrace st) {
        log('authStateChanges error: $e', stackTrace: st);
        unawaited(_userVotesSubscription?.cancel());
        _userVotesSubscription = null;
        emit(
          state.copyWith(
            status: AuthStatus.unauthenticated,
            userId: () => null,
            remainingVotes: () => null,
          ),
        );
      },
    );
  }

  final AuthRepository _authRepository;
  final FirestoreRepository _firestoreRepository;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<int>? _userVotesSubscription;

  Future<void> _initUserVotes(String userId, String? displayName) async {
    try {
      await _firestoreRepository.ensureUserDoc(
        shared.User(
          uid: userId,
          votes: shared.initialVoteBudget,
          lastActiveAt: DateTime.now().toUtc(),
          displayName: displayName,
        ),
      );
      await _userVotesSubscription?.cancel();
      _userVotesSubscription = _firestoreRepository
          .watchUserVotes(userId)
          .listen(
            (votes) => emit(
              state.copyWith(remainingVotes: () => votes),
            ),
            onError: (Object e, StackTrace st) {
              log('watchUserVotes error: $e', stackTrace: st);
            },
          );
    } on Exception catch (e, st) {
      log('ensureUserDoc failed: $e', stackTrace: st);
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
    await _userVotesSubscription?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
