import 'dart:async';
import 'dart:developer';
import 'dart:math' show max, min;

import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/notifications/notifications.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/problems/widgets/add_problem_row.dart';
import 'package:client/problems/widgets/flag_complaint_dialog.dart';
import 'package:client/problems/widgets/geoscope_picker.dart';
import 'package:client/problems/widgets/problem_edit_tile.dart';
import 'package:client/problems/widgets/problem_read_tile.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository;
import 'package:client/services/translation_repository.dart';
import 'package:client/settings/settings.dart';
import 'package:client/widgets/toast.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared/shared.dart';

class ProblemsPage extends StatelessWidget {
  const ProblemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final repo = context.read<FirestoreRepository>();
        final geoscope = context.read<GeoscopeCubit>().state.selectedGeoscope;
        return ProblemsCubit(repo)..changeGeoscope(geoscope);
      },
      child: const _ProblemsPageCoordinator(),
    );
  }
}

class _ProblemsPageCoordinator extends StatefulWidget {
  const _ProblemsPageCoordinator();

  @override
  State<_ProblemsPageCoordinator> createState() =>
      _ProblemsPageCoordinatorState();
}

class _ProblemsPageCoordinatorState extends State<_ProblemsPageCoordinator> {
  Future<void> _openPicker() async {
    context.read<GeoscopeCubit>().acknowledgeSelectionPrompt();
    await showGeoscopePicker(context);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<GeoscopeCubit, GeoscopeState>(
          listenWhen: (prev, curr) =>
              prev.selectedGeoscope != curr.selectedGeoscope,
          listener: (context, geoscopeState) {
            context.read<ProblemsCubit>().changeGeoscope(
              geoscopeState.selectedGeoscope,
            );
          },
        ),
        BlocListener<GeoscopeCubit, GeoscopeState>(
          listenWhen: (prev, curr) =>
              !prev.needsSelection && curr.needsSelection,
          listener: (_, _) => unawaited(_openPicker()),
        ),
      ],
      child: const ProblemsView(),
    );
  }
}

class ProblemsView extends StatefulWidget {
  const ProblemsView({super.key});

  @override
  State<ProblemsView> createState() => _ProblemsViewState();
}

class _ProblemsViewState extends State<ProblemsView> {
  final _itemScrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();
  // True while a programmatic scroll-to is animating/settling, so the
  // auto-pager in [_onPositions] doesn't treat the resulting bottom-parked
  // viewport as "the user scrolled to the end" and cascade-load the list.
  bool _isProgrammaticScroll = false;
  int _scrollToken = 0;
  static final _editTapRegionGroupId = Object();
  String? _editingProblemId;
  bool _showOnlyOwned = false;
  bool _showOnlyWithGoals = false;

  @override
  void initState() {
    super.initState();
    _positionsListener.itemPositions.addListener(_onPositions);
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  /// Auto-page when scrolled near the end. [ItemPositionsListener] fires on
  /// every layout (not just scroll), so we only page when the list actually
  /// overflows the viewport — otherwise a fully-visible short list would
  /// request more forever.
  void _onPositions() {
    if (!mounted || _isProgrammaticScroll) return;
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final cubit = context.read<ProblemsCubit>();
    if (!cubit.state.hasMore) return;
    final minIndex = positions.map((p) => p.index).reduce(min);
    final maxIndex = positions.map((p) => p.index).reduce(max);
    final overflows =
        minIndex > 0 ||
        positions.any((p) => p.index == minIndex && p.itemLeadingEdge < 0);
    if (!overflows) return;
    final userId = context.read<UserCubit>().state.userId;
    final maxAgeDays = context.read<RecencyFilterCubit>().state;
    final itemCount = _applyFilters(
      cubit.state.problems,
      userId,
      maxAgeDays,
    ).length;
    if (maxIndex >= itemCount - 3) {
      unawaited(cubit.loadMore());
    }
  }

  /// Bring the just-created or just-upvoted problem into view — but gently:
  /// if it's already on screen we leave the viewport alone. Deferred to after
  /// the frame so item positions reflect the post-reorder layout.
  void _handleScrollRequest(ProblemsState state) {
    final request = state.scrollRequest;
    if (request == null) return;
    final userId = context.read<UserCubit>().state.userId;
    final maxAgeDays = context.read<RecencyFilterCubit>().state;
    final index = _applyFilters(
      state.problems,
      userId,
      maxAgeDays,
    ).indexWhere((p) => p.id == request.problemId);
    if (index == -1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureVisibleGently(index);
    });
  }

  void _ensureVisibleGently(int index) {
    if (!_itemScrollController.isAttached) return;
    final positions = _positionsListener.itemPositions.value;
    final visible = positions
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .map((p) => p.index);
    if (visible.isNotEmpty) {
      final minVisible = visible.reduce(min);
      final maxVisible = visible.reduce(max);
      if (index >= minVisible && index <= maxVisible) return; // already in view
      // Scrolling up → settle the target near the top. Scrolling down (the
      // just-created bottom item) → request alignment 1.0; the controller
      // clamps to maxScrollExtent, landing it flush at the bottom and fully
      // visible regardless of tile height, rather than half-off-screen.
      _animateTo(index, index < minVisible ? 0.1 : 1.0);
      return;
    }
    _animateTo(index, 0.5);
  }

  /// Programmatically scroll to [index]. Holds [_isProgrammaticScroll] for the
  /// duration of the animation so the resulting bottom-parked viewport doesn't
  /// trip [_onPositions]'s auto-pager — otherwise scrolling to a freshly
  /// created 1-vote problem (which sorts to the bottom) would cascade-load the
  /// whole list. Once it settles, item positions stop changing, so the pager
  /// stays quiet until the user scrolls themselves. The token guards against a
  /// stale completion clearing the flag mid-way through a newer scroll.
  void _animateTo(int index, double alignment) {
    final token = ++_scrollToken;
    _isProgrammaticScroll = true;
    unawaited(
      _itemScrollController
          .scrollTo(
            index: index,
            alignment: alignment,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          )
          .whenComplete(() {
            if (mounted && token == _scrollToken) {
              _isProgrammaticScroll = false;
            }
          }),
    );
  }

  void _copyProblemLink(Problem problem) {
    const webBase = 'http://votasq.quikchange.net';
    final base = kIsWeb ? Uri.base : Uri.parse(webBase);
    final url = base.resolve('/problems/${problem.id}').toString();
    unawaited(Clipboard.setData(ClipboardData(text: url)));
    showSuccessToast(context.l10n.problemLinkCopied);
  }

  void _startEdit(Problem problem) {
    setState(() {
      _editingProblemId = problem.id;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingProblemId = null;
    });
  }

  void _sendFeedback(AppLocalizations l10n) {
    BetterFeedback.of(context).show((feedback) async {
      try {
        await context.read<FeedbackRepository>().submit(
          text: feedback.text,
          screenshot: feedback.screenshot,
          userId: context.read<UserCubit>().state.userId!,
        );
        if (mounted) {
          showSuccessToast(l10n.feedbackSuccess);
        }
      } on Exception catch (e) {
        log('Feedback submission failed: $e');
        if (mounted) {
          showErrorToast(l10n.feedbackError);
        }
      }
    });
  }

  Future<void> _confirmComplaint(Problem problem) async {
    final confirmed = await showFlagComplaintConfirmDialog(context);
    if (confirmed != true || !mounted) return;
    final userId = context.read<UserCubit>().state.userId!;
    unawaited(
      context.read<ProblemsCubit>().flagProblem(
        problem: problem,
        userId: userId,
      ),
    );
    if (mounted) {
      showSuccessToast(context.l10n.complaintSubmitted);
    }
  }

  List<Problem> _applyFilters(
    List<Problem> problems,
    String? userId,
    int maxAgeDays,
  ) {
    var filtered = problems;
    if (userId != null) {
      filtered = filtered.where((p) => !p.complaints.contains(userId)).toList();
    }
    if (_showOnlyOwned && userId != null) {
      filtered = filtered.where((p) => p.ownerId == userId).toList();
    }
    if (_showOnlyWithGoals) {
      filtered = filtered.where((p) => p.goal.isNotEmpty).toList();
    }
    if (maxAgeDays > 0) {
      final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
      filtered = filtered
          .where((p) => p.lastUpdatedAt.isAfter(cutoff))
          .toList();
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // At >=600dp (Material's compact/medium boundary) there's room to
    // surface the "Add problem" affordance directly in the AppBar for
    // authenticated users. Below that, it stays tucked in the hamburger
    // menu so the long title isn't crowded.
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return BlocListener<ProblemsCubit, ProblemsState>(
      listenWhen: (prev, curr) =>
          curr.scrollRequest != null &&
          prev.scrollRequest?.seq != curr.scrollRequest?.seq,
      listener: (context, state) => _handleScrollRequest(state),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 80,
          titleSpacing: 0,
          title: BlocBuilder<ProblemsCubit, ProblemsState>(
            builder: (context, state) {
              // watch (not read) so the filtered count reacts to sign-in /
              // sign-out (userId) and to the recency-filter slider changing.
              final userId = context.watch<UserCubit>().state.userId;
              final maxAgeDays = context.watch<RecencyFilterCubit>().state;
              final filtered = _applyFilters(
                state.problems,
                userId,
                maxAgeDays,
              );
              return Text(
                '${filtered.length} ${l10n.problemsAppBarTitle}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
          leading: TapRegion(
            groupId: _editTapRegionGroupId,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              iconSize: 32,
              onSelected: (value) {
                if (value == 'change_location') {
                  unawaited(showGeoscopePicker(context));
                } else if (value == 'toggle_owned') {
                  setState(() {
                    _showOnlyOwned = !_showOnlyOwned;
                  });
                } else if (value == 'toggle_with_goals') {
                  setState(() {
                    _showOnlyWithGoals = !_showOnlyWithGoals;
                  });
                } else if (value == 'toggle_auto_translate') {
                  unawaited(context.read<AutoTranslateCubit>().toggle());
                } else if (value == 'text_size') {
                  unawaited(showTextSizeDialog(context));
                } else if (value == 'recency_filter') {
                  unawaited(showRecencyFilterDialog(context));
                } else if (value == 'add_problem') {
                  context.go('/new');
                } else if (value == 'send_feedback') {
                  _sendFeedback(l10n);
                } else if (value == 'sign_out') {
                  unawaited(context.read<UserCubit>().signOut());
                }
              },
              itemBuilder: (context) {
                final isAuthenticated =
                    context.read<UserCubit>().state.userId != null;
                final recencyDays = context.read<RecencyFilterCubit>().state;
                final geoState = context.read<GeoscopeCubit>().state;
                final currentGeoscopeId = geoState.selectedGeoscope;
                final currentGeoscopeLabel = currentGeoscopeId == '/'
                    ? '🌐 ${l10n.geoscopeGlobal}'
                    : (geoState.availableGeoscopes
                              .where((g) => g.id == currentGeoscopeId)
                              .firstOrNull
                              ?.label ??
                          currentGeoscopeId);
                // When authenticated AND we have horizontal room, the
                // add-problem affordance lives in the AppBar instead — see
                // `actions:` below. The menu entry is suppressed in that
                // case so the action isn't presented twice.
                final showAddInMenu = !(isAuthenticated && wide);
                return [
                  PopupMenuItem(
                    value: 'recency_filter',
                    child: ListTile(
                      leading: const Icon(Icons.update),
                      // Off → offer ("Show only…"); on → active ("Showing
                      // only…"), with the window in the subtitle.
                      title: Text(
                        recencyDays > 0
                            ? l10n.recencyFilterMenuItem
                            : l10n.recencyFilterMenuItemOff,
                      ),
                      subtitle: Text(
                        RecencyFilterDialog.labelFor(l10n, recencyDays),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (showAddInMenu)
                    PopupMenuItem(
                      value: 'add_problem',
                      child: ListTile(
                        leading: const Icon(Icons.add_circle),
                        title: Text(l10n.addProblemTooltip),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (isAuthenticated)
                    PopupMenuItem(
                      value: 'toggle_owned',
                      child: ListTile(
                        leading: Icon(
                          _showOnlyOwned
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                        ),
                        title: Text(l10n.showOnlyOwnedMenuItem),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'toggle_with_goals',
                    child: ListTile(
                      leading: Icon(
                        _showOnlyWithGoals
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                      ),
                      title: Text(l10n.showOnlyWithGoalsMenuItem),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (context
                      .read<TranslationRepository>()
                      .canTranslateOnDevice)
                    PopupMenuItem(
                      value: 'toggle_auto_translate',
                      child: ListTile(
                        leading: Icon(
                          context.read<AutoTranslateCubit>().state
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                        ),
                        title: Text(l10n.autoTranslateMenuItem),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'change_location',
                    child: ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(l10n.geoscopeChangeMenuItem),
                      subtitle: Text(currentGeoscopeLabel),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'text_size',
                    child: ListTile(
                      leading: const Icon(Icons.format_size),
                      title: Text(l10n.textSizeMenuItem),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (isAuthenticated) ...[
                    PopupMenuItem(
                      value: 'send_feedback',
                      child: ListTile(
                        leading: Transform.translate(
                          offset: const Offset(0, -4),
                          child: const Text(
                            '🗣️',
                            style: TextStyle(fontSize: 24, height: 1),
                          ),
                        ),
                        title: Text(l10n.feedbackButton),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sign_out',
                      child: ListTile(
                        leading: const Icon(Icons.logout),
                        title: Text(l10n.signOutButton),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      enabled: false,
                      child: Text(
                        (context.read<UserCubit>().state.remainingVotes ?? 0) >
                                0
                            ? l10n.menuVotesRemaining(
                                context.read<UserCubit>().state.remainingVotes!,
                              )
                            : l10n.menuVotesReplenishHint,
                      ),
                    ),
                  ],
                ];
              },
            ),
          ),
          actions: [
            BlocBuilder<UserCubit, UserState>(
              builder: (context, authState) {
                if (authState.status == AuthStatus.authenticated) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wide)
                        IconButton(
                          tooltip: l10n.addProblemTooltip,
                          icon: const Icon(Icons.add_circle),
                          onPressed: () => context.go('/new'),
                        ),
                      const NotificationsBadge(),
                    ],
                  );
                }
                return IconButton(
                  tooltip: l10n.signInButtonTooltip,
                  icon: const Icon(Icons.login),
                  onPressed: () => context.read<UserCubit>().signIn(),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            BlocBuilder<UserCubit, UserState>(
              builder: (context, userState) {
                final authed = userState.status == AuthStatus.authenticated;

                final Widget? hint;
                if (userState.status == AuthStatus.unauthenticated) {
                  hint = const _SignInHintBanner();
                } else if (authed && userState.needsVoteHint) {
                  hint = const _VoteHintBanner();
                } else if (authed && userState.needsTapForDetailsHint) {
                  hint = const _TapForDetailsHintBanner();
                } else {
                  hint = null;
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?hint,
                    if (authed)
                      BlocBuilder<GeoscopeCubit, GeoscopeState>(
                        builder: (context, geoState) => AddProblemRow(
                          defaultGeoscope: geoState.selectedGeoscope,
                          onSubmit:
                              ({
                                required description,
                                required goal,
                                required geoscope,
                              }) async {
                                final userId = context
                                    .read<UserCubit>()
                                    .state
                                    .userId!;
                                final userLang = Localizations.localeOf(
                                  context,
                                ).languageCode;
                                await context.read<ProblemsCubit>().addProblem(
                                  description: description,
                                  goal: goal,
                                  ownerId: userId,
                                  userLanguage: userLang,
                                  geoscope: geoscope,
                                );
                              },
                        ),
                      ),
                  ],
                );
              },
            ),
            Expanded(
              child: BlocBuilder<ProblemsCubit, ProblemsState>(
                builder: (context, state) {
                  return switch (state.status) {
                    ProblemsStatus.initial || ProblemsStatus.loading
                        when state.problems.isEmpty =>
                      const Center(child: CircularProgressIndicator()),
                    ProblemsStatus.failure when state.problems.isEmpty =>
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.l10n.failedToLoadProblems),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () =>
                                  context.read<ProblemsCubit>().subscribe(),
                              child: Text(context.l10n.retryButton),
                            ),
                          ],
                        ),
                      ),
                    _ => Builder(
                      builder: (context) {
                        // watch (not read) so showEditButton /
                        // showComplaintButton on each tile react to
                        // sign-in / sign-out without a separate rebuild
                        // trigger. The vote chip inside ProblemReadTile
                        // already watches UserCubit; this is the matching
                        // subscription for the owner-driven props.
                        final userId = context.watch<UserCubit>().state.userId;
                        final maxAgeDays = context
                            .watch<RecencyFilterCubit>()
                            .state;
                        final filtered = _applyFilters(
                          state.problems,
                          userId,
                          maxAgeDays,
                        );
                        return ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _positionsListener,
                          itemCount: filtered.length + (state.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= filtered.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final problem = filtered[index];
                            if (_editingProblemId == problem.id) {
                              return ProblemEditTile(
                                problem: problem,
                                tapRegionGroupId: _editTapRegionGroupId,
                                onCancel: _cancelEdit,
                                onSubmit:
                                    (
                                      updatedProblem, {
                                      required userLanguage,
                                    }) async {
                                      await context
                                          .read<ProblemsCubit>()
                                          .updateProblem(
                                            updatedProblem,
                                            userLanguage: userLanguage,
                                          );
                                    },
                              );
                            }
                            final isOwner =
                                userId != null && userId == problem.ownerId;
                            return ProblemReadTile(
                              problem: problem,
                              showEditButton: isOwner,
                              showComplaintButton: userId != null && !isOwner,
                              onEdit: () => _startEdit(problem),
                              onCopyLink: () => _copyProblemLink(problem),
                              onComplaint: () => _confirmComplaint(problem),
                              onViewDetails: () {
                                if (userId != null) {
                                  unawaited(
                                    context
                                        .read<FirestoreRepository>()
                                        .incrementProblemDetailsViewCount(
                                          userId,
                                        ),
                                  );
                                }
                                unawaited(
                                  context.push('/problems/${problem.id}'),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Common styling for an onboarding-tip banner: light-green surface,
/// indigo text, full-width, centered. The banner is a persistent
/// onboarding nudge; toasts are ephemeral, with [showSuccessToast]
/// sharing the green hue and [showErrorToast] using light-orange to
/// signal failure.
class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.green.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF1A237E),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SignInHintBanner extends StatelessWidget {
  const _SignInHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.signInHintBanner);
}

class _VoteHintBanner extends StatelessWidget {
  const _VoteHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.voteHint);
}

class _TapForDetailsHintBanner extends StatelessWidget {
  const _TapForDetailsHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.tapForDetailsHint);
}
