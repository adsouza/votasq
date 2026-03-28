import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
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
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (prev, curr) =>
            prev.status != curr.status &&
            curr.status == AuthStatus.unauthenticated,
        listener: (context, authState) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.signInHintToast),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
              ),
            );
          });
        },
        child: BlocListener<GeoscopeCubit, GeoscopeState>(
          listenWhen: (prev, curr) =>
              prev.selectedGeoscope != curr.selectedGeoscope,
          listener: (context, geoscopeState) {
            context.read<ProblemsCubit>().changeGeoscope(
              geoscopeState.selectedGeoscope,
            );
          },
          child: const ProblemsView(),
        ),
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.problemLinkCopied)),
    );
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
    final userId = context.read<AuthCubit>().state.userId!;
    unawaited(
      context.read<FirestoreRepository>().addComplaint(
        problemId: problem.id,
        userId: userId,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.complaintSubmitted)),
      );
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
        title: BlocBuilder<ProblemsCubit, ProblemsState>(
          builder: (context, state) {
            final userId = context.read<AuthCubit>().state.userId;
            final filtered = _applyFilters(state.problems, userId);
            return Text(
              '${filtered.length} ${l10n.problemsAppBarTitle}',
            );
          },
        ),
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          onSelected: (value) {
            if (value == 'change_location') {
              showGeoscopePicker(context);
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
            }
          },
          itemBuilder: (context) => [
            if (context.read<AuthCubit>().state.userId != null)
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
            if (context.read<AuthCubit>().state.userId != null) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  (context.read<AuthCubit>().state.remainingVotes ?? 0) > 0
                      ? l10n.menuVotesRemaining(
                          context.read<AuthCubit>().state.remainingVotes!,
                        )
                      : l10n.menuVotesReplenishHint,
                ),
              ),
            ],
          ],
        ),
        actions: [
          BlocBuilder<AuthCubit, AuthState>(
            builder: (context, authState) {
              if (authState.status != AuthStatus.authenticated) {
                return const SizedBox.shrink();
              }
              return TapRegion(
                groupId: _editTapRegionGroupId,
                child: IconButton(
                  icon: const Text('🗣️', style: TextStyle(fontSize: 24)),
                  tooltip: l10n.feedbackButton,
                  onPressed: () {
                    BetterFeedback.of(context).show((feedback) async {
                      try {
                        await context.read<FeedbackRepository>().submit(
                          text: feedback.text,
                          screenshot: feedback.screenshot,
                          userId: context.read<AuthCubit>().state.userId!,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.feedbackSuccess),
                            ),
                          );
                        }
                      } on Exception catch (e) {
                        log('Feedback submission failed: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.feedbackError),
                            ),
                          );
                        }
                      }
                    });
                  },
                ),
              );
            },
          ),
          BlocBuilder<AuthCubit, AuthState>(
            builder: (context, authState) {
              if (authState.status == AuthStatus.authenticated) {
                return IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: l10n.signOutButton,
                  onPressed: () => context.read<AuthCubit>().signOut(),
                );
              }
              return Tooltip(
                message: l10n.signInButtonTooltip,
                child: TextButton(
                  onPressed: () => context.read<AuthCubit>().signIn(),
                  child: Text(l10n.signInButton),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          BlocBuilder<AuthCubit, AuthState>(
            builder: (context, authState) {
              if (authState.status != AuthStatus.authenticated) {
                return const SizedBox.shrink();
              }
              return BlocBuilder<GeoscopeCubit, GeoscopeState>(
                builder: (context, geoState) => AddProblemRow(
                  defaultGeoscope: geoState.selectedGeoscope,
                  onSubmit:
                      ({
                        required description,
                        required goal,
                        required geoscope,
                      }) async {
                        final userId = context.read<AuthCubit>().state.userId!;
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
                      final userId = context.read<AuthCubit>().state.userId;
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
