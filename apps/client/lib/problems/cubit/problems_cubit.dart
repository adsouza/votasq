import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:shared/shared.dart';

class ProblemsCubit extends Cubit<ProblemsState> {
  ProblemsCubit(this._repo) : super(const ProblemsState());

  final FirestoreRepository _repo;
  StreamSubscription<dynamic>? _subscription;
  static const _pageSize = 20;

  /// Subscribe to real-time updates for the first page of problems.
  void subscribe() {
    emit(state.copyWith(status: ProblemsStatus.loading));
    unawaited(_subscription?.cancel());
    _subscription = _repo
        .watchProblems(geoscope: state.geoscope)
        .listen(
          (result) {
            emit(
              state.copyWith(
                status: ProblemsStatus.success,
                problems: result.problems,
                lastDocument: () => result.lastDoc,
                hasMore: result.problems.length >= _pageSize,
              ),
            );
          },
          onError: (Object e, StackTrace st) {
            log('subscribe failed: $e', stackTrace: st);
            emit(state.copyWith(status: ProblemsStatus.failure));
          },
        );
  }

  /// Load the next page of problems (appends to existing list).
  Future<void> loadMore() async {
    if (!state.hasMore || state.lastDocument == null) return;
    try {
      final result = await _repo.getProblems(
        geoscope: state.geoscope,
        startAfter: state.lastDocument,
      );
      emit(
        state.copyWith(
          problems: [...state.problems, ...result.problems],
          lastDocument: () => result.lastDoc,
          hasMore: result.problems.length >= _pageSize,
        ),
      );
    } on Exception catch (e, st) {
      log('loadMore failed: $e', stackTrace: st);
      emit(state.copyWith(status: ProblemsStatus.failure));
    }
  }

  /// Create a new problem with the given description.
  Future<void> addProblem({
    required String description,
    required String ownerId,
  }) async {
    try {
      await _repo.addProblem(
        description: description,
        ownerId: ownerId,
        geoscope: state.geoscope,
      );
    } on Exception catch (e, st) {
      log('addProblem failed: $e', stackTrace: st);
    }
  }

  /// Switch to a different geoscope, resetting the problem list.
  void changeGeoscope(String geoscope) {
    emit(ProblemsState(geoscope: geoscope));
    subscribe();
  }

  /// Update an existing problem.
  Future<void> updateProblem(Problem problem) async {
    try {
      await _repo.updateProblem(problem);
    } on Exception catch (e, st) {
      log('updateProblem failed: $e', stackTrace: st);
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
