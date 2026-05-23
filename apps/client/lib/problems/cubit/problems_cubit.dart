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
  bool _isLoadingMore = false;

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
    if (_isLoadingMore || !state.hasMore || state.lastDocument == null) return;
    _isLoadingMore = true;
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
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Create a new problem with the given description.
  /// If [geoscope] is provided it overrides the current viewing geoscope.
  ///
  /// Optimistically prepends the new problem to local state. The watch
  /// stream may not emit when the new doc falls past the first page's
  /// `limit`, so this keeps the UI in sync regardless. Dedupes by id
  /// because on web the Firestore listener fires synchronously from
  /// local cache before `await` returns, so a blind prepend would
  /// duplicate the new problem at the top and at its sorted position.
  Future<void> addProblem({
    required String description,
    required String ownerId,
    required String userLanguage,
    String? geoscope,
    String goal = '',
  }) async {
    try {
      final created = await _repo.addProblem(
        description: description,
        goal: goal,
        ownerId: ownerId,
        geoscope: geoscope ?? state.geoscope,
        userLanguage: userLanguage,
      );
      final others = state.problems.where((p) => p.id != created.id).toList();
      emit(state.copyWith(problems: [created, ...others]));
    } on LanguageMismatchException {
      rethrow;
    } on Exception catch (e, st) {
      log('addProblem failed: $e', stackTrace: st);
    }
  }

  /// Switch to a different geoscope, resetting the problem list.
  void changeGeoscope(String geoscope) {
    emit(ProblemsState(geoscope: geoscope));
    subscribe();
  }

  /// Vote on a problem.
  Future<void> vote({
    required String problemId,
    required String userId,
  }) async {
    try {
      await _repo.vote(problemId: problemId, userId: userId);
    } on Exception catch (e, st) {
      log('vote failed: $e', stackTrace: st);
    }
  }

  /// Flag a problem as objectionable on behalf of [userId]. Optimistically
  /// hides it from the local list (the page-level filter drops problems whose
  /// `complaints` contain the viewer's uid) instead of waiting on the watch
  /// stream. No-op if the user has already flagged this problem.
  Future<void> flagProblem({
    required Problem problem,
    required String userId,
  }) async {
    if (problem.complaints.contains(userId)) return;
    try {
      await _repo.addComplaint(problemId: problem.id, userId: userId);
      applyLocalUpdate(
        problem.copyWith(complaints: [...problem.complaints, userId]),
      );
    } on Exception catch (e, st) {
      log('flagProblem failed: $e', stackTrace: st);
    }
  }

  /// Toggle a problem's `hidden` flag (owner-only at the rules layer).
  /// On hide, optimistically drops the problem from the local list so a
  /// back-navigation to the listing doesn't briefly show the stale entry
  /// before the watch snapshot reconciles. On unhide, applies a local
  /// update if the problem is still in the visible page (the watch
  /// stream will refresh it independently).
  Future<void> setHidden({
    required Problem problem,
    required bool hidden,
  }) async {
    try {
      await _repo.setHidden(problemId: problem.id, hidden: hidden);
      if (hidden) {
        emit(
          state.copyWith(
            problems: state.problems.where((p) => p.id != problem.id).toList(),
          ),
        );
      } else {
        applyLocalUpdate(problem.copyWith(hidden: false));
      }
    } on Exception catch (e, st) {
      log('setHidden failed: $e', stackTrace: st);
    }
  }

  /// Update an existing problem.
  Future<void> updateProblem(
    Problem problem, {
    String? userLanguage,
  }) async {
    try {
      await _repo.updateProblem(problem, userLanguage: userLanguage);
      applyLocalUpdate(problem);
    } on LanguageMismatchException {
      rethrow;
    } on Exception catch (e, st) {
      log('updateProblem failed: $e', stackTrace: st);
    }
  }

  /// Replace [problem] in the local list when present. Use this after a
  /// successful out-of-band write (e.g. from the detail page, which goes
  /// through the repo directly) so the list reflects the edit immediately
  /// on return instead of relying on the Firestore watch stream's delivery
  /// latency. A no-op if the problem isn't in the current page of results.
  void applyLocalUpdate(Problem problem) {
    final index = state.problems.indexWhere((p) => p.id == problem.id);
    if (index == -1) return;
    final updated = [...state.problems];
    updated[index] = problem;
    emit(state.copyWith(problems: updated));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
