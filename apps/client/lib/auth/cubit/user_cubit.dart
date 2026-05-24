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
