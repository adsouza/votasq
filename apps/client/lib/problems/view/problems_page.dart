import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/notifications/notifications.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/problems/widgets/add_problem_row.dart';
import 'package:client/problems/widgets/geoscope_picker.dart';
import 'package:client/problems/widgets/problem_edit_tile.dart';
import 'package:client/problems/widgets/problem_read_tile.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository;
import 'package:client/services/translation_repository.dart';
import 'package:client/widgets/toast.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';
import 'package:toastification/toastification.dart';

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

/// Coordinates the double-tap-for-details hint toast with the geoscope picker
/// so the toast isn't immediately obscured by the picker on first launch. The
/// toast fires once per session, when (a) the geoscope cubit has settled and
/// (b) no picker is currently shown. The sign-in CTA that used to live in
/// this toast is now rendered as a persistent banner below the app bar via
/// [_SignInHintBanner].
class _ProblemsPageCoordinator extends StatefulWidget {
  const _ProblemsPageCoordinator();

  @override
  State<_ProblemsPageCoordinator> createState() =>
      _ProblemsPageCoordinatorState();
}

class _ProblemsPageCoordinatorState extends State<_ProblemsPageCoordinator> {
  bool _pickerActive = false;
  bool _doubleTapToastShown = false;
  ToastificationItem? _doubleTapToastItem;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Re-attempt the toast when the user pops a child route (e.g. /new),
    // since no geoscope transition fires on that navigation alone.
    // Also dismiss any live toast when a child route is pushed on top —
    // toastification's overlay persists across navigations, so the toast
    // would otherwise linger on /new for the remainder of its duration.
    _router = GoRouter.of(context)..routerDelegate.addListener(_onRouterChange);
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRouterChange);
    super.dispose();
  }

  /// Whether the current top-of-stack location is this page. We read from
  /// go_router's router delegate rather than `ModalRoute.of(context).isCurrent`
  /// because the navigator widget hasn't rebuilt yet at the moment route
  /// listeners fire — `currentConfiguration` reflects the intended state,
  /// which is what we want to gate on.
  bool get _isHomeCurrent =>
      _router.routerDelegate.currentConfiguration.uri.path == '/';

  void _onRouterChange() {
    if (!mounted) return;
    if (!_isHomeCurrent) {
      final item = _doubleTapToastItem;
      if (item != null) {
        toastification.dismiss(item);
        _doubleTapToastItem = null;
      }
      return;
    }
    _maybeShowDoubleTapToast();
  }

  Future<void> _openPicker() async {
    context.read<GeoscopeCubit>().acknowledgeSelectionPrompt();
    setState(() => _pickerActive = true);
    try {
      await showGeoscopePicker(context);
    } finally {
      if (mounted) {
        setState(() => _pickerActive = false);
        _maybeShowDoubleTapToast();
      }
    }
  }

  /// Try to show the double-tap-for-details toast. Returns silently when not
  /// yet appropriate (picker active, geoscope still loading, child route on
  /// top) so the next state transition can re-attempt.
  void _maybeShowDoubleTapToast() {
    if (!mounted) return;
    if (_doubleTapToastShown) return;
    if (_pickerActive) return;
    // The toast text refers to "problems" — the list shown on this page.
    // Skip when a child route (e.g. /new) is on top so the hint lands
    // alongside the list it's describing.
    if (!_isHomeCurrent) return;
    if (!context.read<UserCubit>().state.needsDoubleTapHint) return;
    final geoState = context.read<GeoscopeCubit>().state;
    if (geoState.status != GeoscopeStatus.success) return;
    if (geoState.needsSelection) return;

    _doubleTapToastShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Re-check: the user may have navigated away in the frame between
      // scheduling and now. Reset the flag so a return can re-attempt.
      if (!_isHomeCurrent) {
        _doubleTapToastShown = false;
        return;
      }
      _doubleTapToastItem = showToast(
        context.l10n.doubleTapHint,
        duration: const Duration(seconds: 5),
      );
    });
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
        // Show the toast once the geoscope cubit settles (problems are then
        // visible and the hint applies to them).
        BlocListener<GeoscopeCubit, GeoscopeState>(
          listenWhen: (prev, curr) =>
              prev.status != GeoscopeStatus.success &&
              curr.status == GeoscopeStatus.success,
          listener: (_, _) => _maybeShowDoubleTapToast(),
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
  final _scrollController = ScrollController();
  static final _editTapRegionGroupId = Object();
  String? _editingProblemId;
  bool _showOnlyOwned = false;
  bool _showOnlyWithGoals = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isNearBottom) {
      unawaited(context.read<ProblemsCubit>().loadMore());
    }
  }

  void _copyProblemLink(Problem problem) {
    const webBase = 'http://votasq.quikchange.net';
    final base = kIsWeb ? Uri.base : Uri.parse(webBase);
    final url = base.resolve('/problems/${problem.id}').toString();
    unawaited(Clipboard.setData(ClipboardData(text: url)));
    showToast(context.l10n.problemLinkCopied);
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
          showToast(l10n.feedbackSuccess);
        }
      } on Exception catch (e) {
        log('Feedback submission failed: $e');
        if (mounted) {
          showToast(l10n.feedbackError);
        }
      }
    });
  }

  Future<void> _confirmComplaint(Problem problem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag as abusive?'),
        content: const Text(
          'Are you sure you want to report this problem as abusive? '
          'It will be hidden from your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final userId = context.read<UserCubit>().state.userId!;
    unawaited(
      context.read<ProblemsCubit>().flagProblem(
        problem: problem,
        userId: userId,
      ),
    );
    if (mounted) {
      showToast(context.l10n.complaintSubmitted);
    }
  }

  List<Problem> _applyFilters(List<Problem> problems, String? userId) {
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
    return filtered;
  }

  bool get _isNearBottom {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= maxScroll * 0.9;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        titleSpacing: 0,
        title: BlocBuilder<ProblemsCubit, ProblemsState>(
          builder: (context, state) {
            // watch (not read) so the filtered count reacts to sign-in /
            // sign-out — _applyFilters with _showOnlyOwned uses userId.
            final userId = context.watch<UserCubit>().state.userId;
            final filtered = _applyFilters(state.problems, userId);
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
              return [
                PopupMenuItem(
                  value: 'add_problem',
                  child: ListTile(
                    leading: const Icon(Icons.add),
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
                if (context.read<TranslationRepository>().canTranslateOnDevice)
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
                      (context.read<UserCubit>().state.remainingVotes ?? 0) > 0
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
                return const NotificationsBadge();
              }
              return Tooltip(
                message: l10n.signInButtonTooltip,
                child: TextButton(
                  onPressed: () => context.read<UserCubit>().signIn(),
                  child: SizedBox(
                    width: 64,
                    child: Text(
                      l10n.signInButton,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
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
              } else if (authed && userState.needsDoubleTapHint) {
                hint = const _DoubleTapHintBanner();
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
                  ProblemsStatus.failure when state.problems.isEmpty => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.failedToLoadProblems),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () =>
                              context.read<ProblemsCubit>().subscribe(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  _ => Builder(
                    builder: (context) {
                      // watch (not read) so showEditButton / showComplaintButton
                      // on each tile react to sign-in / sign-out without a
                      // separate rebuild trigger. The vote chip inside
                      // ProblemReadTile already watches UserCubit; this is the
                      // matching subscription for the owner-driven props.
                      final userId = context.watch<UserCubit>().state.userId;
                      final filtered = _applyFilters(state.problems, userId);
                      return ListView.builder(
                        controller: _scrollController,
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
    );
  }
}

/// Common styling for an onboarding-tip banner: light-orange surface,
/// indigo text, full-width, centered. Echoes the toast palette so the
/// banner reads as part of the same "system hint" surface.
class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
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

class _DoubleTapHintBanner extends StatelessWidget {
  const _DoubleTapHintBanner();

  @override
  Widget build(BuildContext context) =>
      _HintBanner(message: context.l10n.doubleTapHint);
}
