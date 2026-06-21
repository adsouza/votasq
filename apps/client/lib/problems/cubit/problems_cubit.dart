import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:shared/shared.dart';

class ProblemsCubit extends Cubit<ProblemsState> {
  ProblemsCubit(this._repo, {int eagerLoadCap = 99, int pageSize = 9})
    : _eagerLoadCap = eagerLoadCap,
      _pageSize = pageSize,
      super(const ProblemsState());

  final FirestoreRepository _repo;
  StreamSubscription<dynamic>? _subscription;
  final int _pageSize;

  /// Upper bound on how many problems the post-subscribe background loader
  /// eagerly fetches while loading the >1-vote tier (it normally stops at the
  /// 1-vote tier first; this caps pathological cases — a huge multi-vote tier).
  /// Beyond it the user can still page further by scrolling. See [_eagerLoad].
  ///
  /// Note: because the live window already loads [_pageSize] problems, a cap
  /// at or below that makes the background loader a no-op — the loaded list is
  /// then just the realtime window.
  final int _eagerLoadCap;

  bool _isLoadingMore = false;

  /// Once pagination has advanced past the live window, the paginated cursor
  /// (`lastDocument`) and `hasMore` are owned by [loadMore]; the watch stream
  /// must not reset them back to the first page's tail on every emit.
  bool _hasPaginated = false;

  /// Guards [_eagerLoad] so it's only kicked off once per subscription.
  bool _eagerKickedOff = false;
  bool _eagerLoading = false;

  /// Monotonic sequence backing [ProblemScrollRequest] so repeated requests
  /// for the same problem still register as a state change for the view.
  int _scrollSeq = 0;

  /// Listing sort: votes DESC, then lastUpdatedAt DESC (most recently touched
  /// first within a vote tier), then document id ASC as a stable tiebreak —
  /// identical to the server-side `orderBy` in [FirestoreRepository] so locally
  /// reconciled state matches what a fresh query would return.
  static int _byRank(Problem a, Problem b) {
    final byVotes = b.votes.compareTo(a.votes);
    if (byVotes != 0) return byVotes;
    final byUpdated = b.lastUpdatedAt.compareTo(a.lastUpdatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.id.compareTo(b.id);
  }

  /// Union of [a] and [b] keyed by id (entries from [a] win on conflict so
  /// optimistic local mutations survive), sorted by [_byRank].
  static List<Problem> _merged(Iterable<Problem> a, Iterable<Problem> b) {
    final byId = <String, Problem>{};
    for (final p in a) {
      byId[p.id] = p;
    }
    for (final p in b) {
      byId.putIfAbsent(p.id, () => p);
    }
    return byId.values.toList()..sort(_byRank);
  }

  /// Merge a fresh live-window snapshot into the existing (possibly paginated)
  /// list instead of replacing it wholesale.
  ///
  /// The watch query covers only the top [_pageSize] problems, so [window] is
  /// authoritative for that prefix but says nothing about items below it. We
  /// therefore:
  ///   * take the window's copies for ids it contains (they're freshest),
  ///   * keep existing items that sort strictly *after* the window's last item
  ///     (the paginated tail and freshly created 1-vote problems), and
  ///   * drop existing items that fall within the window's range but are
  ///     absent from it — they left the listing (solved/hidden/deleted).
  ///
  /// Problem votes only ever increment, so an in-flight snapshot that predates
  /// a local optimistic upvote must not clobber it; we floor each window item's
  /// votes at any higher local value.
  List<Problem> _reconcileWithWindow(
    List<Problem> existing,
    List<Problem> window,
  ) {
    if (window.isEmpty) {
      // A spurious empty window shouldn't wipe a loaded tail; only an
      // unpaginated empty window means the listing is genuinely empty.
      return _hasPaginated ? existing : const <Problem>[];
    }
    final existingById = {for (final p in existing) p.id: p};
    final reconciledWindow = window.map((w) {
      final local = existingById[w.id];
      if (local != null && local.votes > w.votes) {
        return w.copyWith(votes: local.votes);
      }
      return w;
    }).toList();
    final windowIds = window.map((p) => p.id).toSet();
    final threshold = window.last;
    final tail = existing.where(
      (p) => !windowIds.contains(p.id) && _byRank(p, threshold) > 0,
    );
    return [...reconciledWindow, ...tail]..sort(_byRank);
  }

  /// Subscribe to real-time updates for the first page of problems.
  void subscribe() {
    // Reset per-subscription pagination state. A retry/resubscribe (e.g. the
    // failure-retry button) calls this without first resetting state, so the
    // previous subscription's cursor/hasMore would otherwise survive into the
    // new subscription's cache-snapshot phase — where the listener
    // deliberately doesn't reseed the cursor — and leak stale pagination.
    // Existing problems are kept for a fast paint.
    emit(
      state.copyWith(
        status: ProblemsStatus.loading,
        lastDocument: () => null,
        hasMore: true,
      ),
    );
    _hasPaginated = false;
    _eagerKickedOff = false;
    unawaited(_subscription?.cancel());
    _subscription = _repo
        .watchProblems(geoscope: state.geoscope, limit: _pageSize)
        .listen(
          (result) {
            // An offline-cache snapshot may be stale: seeding the paginated
            // cursor from it produces a `startAfterDocument` that resumes at
            // the wrong place and stalls pagination, and the one-shot eager
            // loader would latch onto it permanently. So show the cache's
            // problems for a fast paint, but only seed the cursor/hasMore and
            // kick off the eager loader from a server-confirmed snapshot.
            // (The Firestore emulator runs with persistence disabled, so this
            // cache path never appeared in testing — only against prod.)
            final authoritative = !result.isFromCache;
            final ownCursor = _hasPaginated || !authoritative;
            emit(
              state.copyWith(
                status: ProblemsStatus.success,
                problems: _reconcileWithWindow(state.problems, result.problems),
                lastDocument: ownCursor ? null : () => result.lastDoc,
                hasMore: ownCursor ? null : result.problems.length >= _pageSize,
              ),
            );
            if (!_eagerKickedOff && authoritative) {
              _eagerKickedOff = true;
              unawaited(_eagerLoad());
            }
          },
          onError: (Object e, StackTrace st) {
            log('subscribe failed: $e', stackTrace: st);
            emit(state.copyWith(status: ProblemsStatus.failure));
          },
        );
  }

  /// After the first (server) snapshot, page through the listing in the
  /// background so problems with more than 1 vote are loaded without the user
  /// scrolling, stopping once it reaches the 1-vote tier (those load on scroll)
  /// or hits [_eagerLoadCap]. Yields between pages so it doesn't compete with
  /// user scrolling.
  ///
  /// The 1-vote check is on `state.problems` rather than the last fetched page:
  /// safe because problem votes only ever increment, so a cache-seeded entry is
  /// never a *stale* 1-vote that could trip this early (a doc that was >1 vote
  /// can't have dropped to 1).
  Future<void> _eagerLoad() async {
    if (_eagerLoading) return;
    _eagerLoading = true;
    try {
      while (state.hasMore &&
          state.problems.length < _eagerLoadCap &&
          !state.problems.any((p) => p.votes <= 1)) {
        final before = state.problems.length;
        await loadMore();
        if (state.problems.length <= before) break; // no progress; bail
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _eagerLoading = false;
    }
  }

  /// Load the next page of problems (merges into the existing list).
  Future<void> loadMore() async {
    if (_isLoadingMore || !state.hasMore || state.lastDocument == null) return;
    _isLoadingMore = true;
    _hasPaginated = true;
    try {
      final result = await _repo.getProblems(
        geoscope: state.geoscope,
        startAfter: state.lastDocument,
        pageSize: _pageSize,
      );
      emit(
        state.copyWith(
          problems: _merged(state.problems, result.problems),
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
  /// Inserts the new problem at its honest sorted position (the top of the
  /// 1-vote tier) rather than artificially at the top of the list, and asks
  /// the view to scroll it into view. Starting low means the owner's first
  /// upvote moves it *up* (intuitive) instead of the old behaviour where the
  /// artificial top placement made voting look like a demotion. Dedupes by id
  /// because on web the Firestore listener fires synchronously from local
  /// cache before `await` returns.
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
      emit(
        state.copyWith(
          problems: _merged(
            state.problems.where((p) => p.id != created.id),
            [created],
          ),
          scrollRequest: ProblemScrollRequest(
            problemId: created.id,
            seq: ++_scrollSeq,
          ),
        ),
      );
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
  ///
  /// Optimistically increments the vote locally and re-sorts so the problem
  /// climbs immediately, then asks the view to keep it in view (the view only
  /// scrolls if it would otherwise leave the viewport). Reverts on failure.
  /// Safe because problem votes only ever increment.
  Future<void> vote({
    required String problemId,
    required String userId,
  }) async {
    final index = state.problems.indexWhere((p) => p.id == problemId);
    final original = index == -1 ? null : state.problems[index];
    if (original != null) {
      final bumped = [...state.problems];
      bumped[index] = original.copyWith(votes: original.votes + 1);
      bumped.sort(_byRank);
      emit(
        state.copyWith(
          problems: bumped,
          scrollRequest: ProblemScrollRequest(
            problemId: problemId,
            seq: ++_scrollSeq,
          ),
        ),
      );
    }
    try {
      await _repo.vote(problemId: problemId, userId: userId);
    } on Exception catch (e, st) {
      log('vote failed: $e', stackTrace: st);
      if (original != null) {
        final idx = state.problems.indexWhere((p) => p.id == problemId);
        if (idx != -1) {
          final reverted = [...state.problems]
            ..[idx] = original
            ..sort(_byRank);
          emit(state.copyWith(problems: reverted));
        }
      }
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
