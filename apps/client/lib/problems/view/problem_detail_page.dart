import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/geoscope_widgets.dart';
import 'package:client/problems/widgets/problem_text_utils.dart';
import 'package:client/problems/widgets/problem_translation.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository, LanguageMismatchException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

class ProblemDetailPage extends StatefulWidget {
  const ProblemDetailPage({required this.problemId, super.key});

  final String problemId;

  @override
  State<ProblemDetailPage> createState() => _ProblemDetailPageState();
}

class _ProblemDetailPageState extends State<ProblemDetailPage> {
  final _controller = TextEditingController();
  final _goalController = TextEditingController();
  Problem? _problem;
  List<({String name, int votes})>? _voters;
  List<Problem>? _forks;
  bool _loading = true;
  String? _error;
  String? _geoscope;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Capturing the repo is fine here (Provider's read doesn't depend on
    // Localizations). But `context.l10n` would crash if used before the
    // first build completes, so we defer those reads to after the first
    // await + mounted check.
    final repo = context.read<FirestoreRepository>();
    try {
      final problem = await repo.getProblem(widget.problemId);
      if (!mounted) return;
      if (problem == null) {
        setState(() {
          _loading = false;
          _error = context.l10n.problemNotFound;
        });
        return;
      }
      final voters = await repo.getVotersForProblem(
        problem.id,
        excludeUid: problem.ownerId,
        anonymous: context.l10n.voterAnonymous,
      );
      if (!mounted) return;
      // Fork-list failure is non-fatal — the section just won't render.
      List<Problem>? forks;
      try {
        forks = await repo.getForksOfProblem(problem.id);
      } on Exception catch (e) {
        log('Failed to load forks: $e');
      }
      if (!mounted) return;
      setState(() {
        _problem = problem;
        _voters = voters;
        _forks = forks;
        _controller.text = problem.description;
        _goalController.text = problem.goal;
        _geoscope = problem.geoscope;
        _loading = false;
      });
    } on Exception catch (e) {
      log('Failed to load problem: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.l10n.problemNotFound;
        });
      }
    }
  }

  Future<void> _fork(Problem problem, String ownerId) async {
    final repo = context.read<FirestoreRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final errorMessage = context.l10n.forkProblemError;
    try {
      final fork = await repo.forkProblem(
        sourceProblemId: problem.id,
        ownerId: ownerId,
      );
      if (!mounted) return;
      router.go('/problems/${fork.id}');
    } on Exception catch (e) {
      log('Failed to fork problem: $e');
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem == null || !hasEnoughWords(_controller.text)) return;
    // Capture context-dependent values before any async gap. Safe here
    // because _save is only invoked from a button tap, which can't happen
    // before the first build completes.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final repo = context.read<FirestoreRepository>();
    final userLang = Localizations.localeOf(context).languageCode;

    final newDescription = _controller.text.trim();
    final newGoal = _goalController.text.trim();
    final newGeoscope = _geoscope ?? problem.geoscope;
    final hasChanges =
        newDescription != problem.description ||
        newGoal != problem.goal ||
        newGeoscope != problem.geoscope;

    if (hasChanges) {
      try {
        await repo.updateProblem(
          problem.copyWith(
            description: newDescription,
            goal: newGoal,
            geoscope: newGeoscope,
          ),
          userLanguage: userLang,
        );
      } on LanguageMismatchException catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.languageMismatchError(e.descriptionLang, e.goalLang),
            ),
          ),
        );
        return;
      } on Exception catch (e) {
        log('Failed to save problem: $e');
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.saveProblemError)),
        );
        return;
      }
      if (!mounted) return;
      // Reflect the saved values locally so subsequent change-detection
      // works against fresh state.
      setState(() {
        _problem = problem.copyWith(
          description: newDescription,
          goal: newGoal,
          geoscope: newGeoscope,
        );
      });
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.problemSavedToast)),
    );
  }

  Widget _buildInspoBacklink(Problem problem) {
    final sourceId = problem.inspoProblemId;
    if (sourceId == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => context.go('/problems/$sourceId'),
        icon: const Icon(Icons.call_merge, size: 16),
        label: Text(context.l10n.forkedFromOriginalLink),
      ),
    );
  }

  Widget _buildForksList() {
    final forks = _forks;
    if (forks == null || forks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ExpansionTile(
        title: Text(
          l10n.forksHeading(forks.length),
          style: theme.textTheme.titleMedium,
        ),
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        children: [
          for (final fork in forks)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                fork.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => context.go('/problems/${fork.id}'),
            ),
        ],
      ),
    );
  }

  Widget _buildVoterList() {
    final voters = _voters;
    if (voters == null || voters.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(l10n.votersHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final voter in voters)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Flexible(child: Text(voter.name)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${voter.votes}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReadOnlyBody(Problem problem) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInspoBacklink(problem),
          ProblemTranslation(
            problemId: problem.id,
            lang: problem.lang,
            originalDescription: problem.description,
            originalGoal: problem.goal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TranslatedField(
                  problem.description,
                  fieldSelector: (tp) => tp.description,
                  style: theme.textTheme.headlineSmall,
                ),
                if (problem.goal.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TranslatedField(
                    problem.goal,
                    fieldSelector: (tp) => tp.goal,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (problem.geoscope != '/')
                      Tooltip(
                        message: l10n.geoscopeLabel.replaceAll(
                          RegExp(r'[:：\s]+$|^[:：\s]+'),
                          '',
                        ),
                        child: Chip(
                          label: Text(geoscopeLabel(context, problem.geoscope)),
                          backgroundColor: theme.colorScheme.tertiaryContainer,
                        ),
                      ),
                    Builder(
                      builder: (context) {
                        final authState = context.watch<AuthCubit>().state;
                        final userId = authState.userId;
                        if (userId != null &&
                            (authState.remainingVotes ?? 0) > 0) {
                          return Tooltip(
                            message: l10n.voteButtonTooltip,
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.arrow_circle_up_rounded,
                                size: 16,
                              ),
                              label: Text('${problem.votes}'),
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              onPressed: () async {
                                final repo = context
                                    .read<FirestoreRepository>();
                                final anonName = context.l10n.voterAnonymous;
                                await repo.vote(
                                  problemId: problem.id,
                                  userId: userId,
                                );
                                if (!mounted) return;
                                final voters = await repo.getVotersForProblem(
                                  problem.id,
                                  excludeUid: problem.ownerId,
                                  anonymous: anonName,
                                );
                                if (mounted) {
                                  setState(() {
                                    _problem = problem.copyWith(
                                      votes: problem.votes + 1,
                                    );
                                    _voters = voters;
                                  });
                                }
                              },
                            ),
                          );
                        }
                        return Tooltip(
                          message: l10n.votesChipTooltip,
                          child: Chip(
                            label: Text('${problem.votes}'),
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                          ),
                        );
                      },
                    ),
                    const ProblemTranslateButton(),
                  ],
                ),
              ],
            ),
          ),
          _buildForksList(),
          _buildVoterList(),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => context.pop(),
            child: Text(l10n.problemDetailBackButton),
          ),
        ],
      ),
    );
  }

  Widget _buildEditBody(Problem problem) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInspoBacklink(problem),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              return TextField(
                controller: _controller,
                maxLength: maxProblemTextLength,
                decoration: InputDecoration(
                  hintText: l10n.editProblemHint,
                ),
                onSubmitted: hasEnoughWords(value.text) ? (_) => _save() : null,
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              return TextField(
                controller: _goalController,
                maxLength: maxProblemTextLength,
                decoration: InputDecoration(
                  hintText: l10n.editGoalHint,
                ),
                onSubmitted: hasEnoughWords(value.text) ? (_) => _save() : null,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(l10n.geoscopeLabel),
              ...buildGeoscopeDropdown(
                context,
                geoscope: context.read<GeoscopeCubit>().state.selectedGeoscope,
                currentValue: _geoscope ?? problem.geoscope,
                compact: false,
                onChanged: (value) => setState(() {
                  _geoscope = value;
                }),
              ),
            ],
          ),
          _buildForksList(),
          _buildVoterList(),
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final hasWords = hasEnoughWords(_controller.text);
              return Row(
                children: [
                  FilledButton(
                    onPressed: hasWords ? _save : null,
                    child: Text(l10n.problemDetailSaveButton),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => context.pop(),
                    child: Text(l10n.problemDetailBackButton),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.problemDetailPageTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _problem == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.problemDetailPageTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? l10n.problemNotFound),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => context.pop(),
                child: Text(l10n.problemDetailBackButton),
              ),
            ],
          ),
        ),
      );
    }

    final problem = _problem!;
    final userId = context.read<AuthCubit>().state.userId;
    final isOwner = userId != null && userId == problem.ownerId;
    final canFork = userId != null && !isOwner;

    // Note: no `autofocus: true` on the Focus wrapper. It used to be there so
    // Escape would pop without a prior tap, but it interacts badly with route
    // remounts (e.g. fork → navigate to fork): the outer Focus re-grabs
    // primary focus during the transition and Flutter Web/desktop's
    // HardwareKeyboard state can desync, throwing a "key already pressed"
    // assertion and breaking subsequent typing in TextFields. Escape still
    // works once the user has interacted with anything on the page.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
      },
      child: Focus(
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.problemDetailPageTitle),
            actions: [
              if (canFork)
                IconButton(
                  tooltip: l10n.forkProblemTooltip,
                  icon: const Icon(Icons.call_split),
                  onPressed: () => _fork(problem, userId),
                ),
            ],
          ),
          body: isOwner ? _buildEditBody(problem) : _buildReadOnlyBody(problem),
        ),
      ),
    );
  }
}
