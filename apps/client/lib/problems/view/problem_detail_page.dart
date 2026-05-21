import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/widgets/geoscope_widgets.dart';
import 'package:client/problems/widgets/problem_text_utils.dart';
import 'package:client/problems/widgets/problem_translation.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository, LanguageMismatchException;
import 'package:client/widgets/toast.dart';
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
  List<Problem>? _linkedProblems;
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
      List<Problem>? linkedProblems;
      try {
        if (problem.linkedProblemIds.isNotEmpty) {
          linkedProblems = await Future.wait(
            problem.linkedProblemIds.map(repo.getProblem),
          ).then((list) => list.whereType<Problem>().toList());
        } else {
          linkedProblems = [];
        }
      } on Exception catch (e) {
        log('Failed to load linked problems: $e');
      }
      if (!mounted) return;
      setState(() {
        _problem = problem;
        _voters = voters;
        _forks = forks;
        _linkedProblems = linkedProblems;
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
    final router = GoRouter.of(context);
    final errorMessage = context.l10n.forkProblemError;
    try {
      final fork = await repo.forkProblem(
        sourceProblemId: problem.id,
        ownerId: ownerId,
      );
      if (!mounted) return;
      unawaited(router.push('/problems/${fork.id}'));
    } on Exception catch (e) {
      log('Failed to fork problem: $e');
      showToast(errorMessage);
    }
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem == null || !hasEnoughWords(_controller.text)) return;
    // Capture context-dependent values before any async gap. Safe here
    // because _save is only invoked from a button tap, which can't happen
    // before the first build completes.
    final l10n = context.l10n;
    final repo = context.read<FirestoreRepository>();
    // ProblemsCubit is provided by the parent route; we notify it after a
    // successful save so the list reflects the edit on return without
    // waiting for the Firestore watch stream. Defensive: if for some
    // reason the cubit isn't in scope (tests, future route restructure),
    // skip the notification.
    ProblemsCubit? problemsCubit;
    try {
      problemsCubit = context.read<ProblemsCubit>();
    } on Object {
      problemsCubit = null;
    }
    final userLang = Localizations.localeOf(context).languageCode;

    final newDescription = _controller.text.trim();
    final newGoal = _goalController.text.trim();
    final newGeoscope = _geoscope ?? problem.geoscope;
    final hasChanges =
        newDescription != problem.description ||
        newGoal != problem.goal ||
        newGeoscope != problem.geoscope;

    if (hasChanges) {
      final updated = problem.copyWith(
        description: newDescription,
        goal: newGoal,
        geoscope: newGeoscope,
      );
      try {
        await repo.updateProblem(updated, userLanguage: userLang);
      } on LanguageMismatchException catch (e) {
        if (!mounted) return;
        showToast(l10n.languageMismatchError(e.descriptionLang, e.goalLang));
        return;
      } on Exception catch (e) {
        log('Failed to save problem: $e');
        if (!mounted) return;
        showToast(l10n.saveProblemError);
        return;
      }
      if (!mounted) return;
      // Reflect the saved values locally so subsequent change-detection
      // works against fresh state, and push the same update into the list
      // cubit so the previous page doesn't show stale data on return.
      setState(() {
        _problem = updated;
      });
      problemsCubit?.applyLocalUpdate(updated);
    }
    if (!mounted) return;
    showToast(l10n.problemSavedToast);
  }

  Widget _buildInspoBacklink(Problem problem) {
    final sourceId = problem.inspoProblemId;
    if (sourceId == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => context.push('/problems/$sourceId'),
        icon: const Icon(Icons.call_merge, size: 16),
        label: Text(context.l10n.forkedFromOriginalLink),
      ),
    );
  }

  Widget _buildForksList() {
    final problem = _problem;
    final forks = _forks;
    if (problem == null || forks == null || forks.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final userId = context.read<AuthCubit>().state.userId;
    final isOwner = userId != null && userId == problem.ownerId;
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
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        children: [
          for (final fork in forks)
            _ForkRow(
              current: problem,
              fork: fork,
              canCompare: isOwner,
              onUseField: _useForkField,
            ),
        ],
      ),
    );
  }

  /// Replace one field of [_problem] with the corresponding value from a
  /// fork, persist the change as a new revision, and reflect the result
  /// locally. Called by [_ForkRow] when the owner taps "Use this here".
  Future<void> _useForkField(Problem updated) async {
    final l10n = context.l10n;
    final repo = context.read<FirestoreRepository>();
    ProblemsCubit? problemsCubit;
    try {
      problemsCubit = context.read<ProblemsCubit>();
    } on Object {
      problemsCubit = null;
    }
    final userLang = Localizations.localeOf(context).languageCode;
    try {
      await repo.updateProblem(updated, userLanguage: userLang);
    } on LanguageMismatchException catch (e) {
      if (!mounted) return;
      showToast(l10n.languageMismatchError(e.descriptionLang, e.goalLang));
      return;
    } on Exception catch (e) {
      log('Failed to apply fork field: $e');
      if (!mounted) return;
      showToast(l10n.saveProblemError);
      return;
    }
    if (!mounted) return;
    // Mirror updateProblem's server-side `newVersion = version + 1` so a
    // subsequent "Use this here" tap doesn't pass the stale version and
    // overwrite the revision we just wrote at `versions/{newVersion}`.
    final saved = updated.copyWith(version: updated.version + 1);
    setState(() {
      _problem = saved;
      _controller.text = saved.description;
      _goalController.text = saved.goal;
      _geoscope = saved.geoscope;
    });
    problemsCubit?.applyLocalUpdate(saved);
    showToast(l10n.problemSavedToast);
  }

  Widget _buildLinkedProblemsList() {
    final linked = _linkedProblems;
    if (linked == null || linked.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final userId = context.read<AuthCubit>().state.userId;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ExpansionTile(
        title: Text(
          l10n.linkedProblemsHeading(linked.length),
          style: theme.textTheme.titleMedium,
        ),
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        children: [
          for (final p in linked)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                p.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: p.goal.isNotEmpty
                  ? Text(
                      p.goal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              trailing: userId != null
                  ? IconButton(
                      tooltip: l10n.unlinkProblemTooltip,
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _unlink(p.id),
                    )
                  : null,
              onTap: () => context.push('/problems/${p.id}'),
            ),
        ],
      ),
    );
  }

  Future<void> _unlink(String targetId) async {
    final repo = context.read<FirestoreRepository>();
    try {
      await repo.unlinkProblem(targetId);
      if (!mounted) return;
      await _load();
    } on Exception catch (e) {
      log('Failed to unlink problem: $e');
      if (mounted) {
        showToast(context.l10n.unlinkProblemError);
      }
    }
  }

  Future<void> _showLinkProblemDialog(BuildContext context) async {
    final problem = _problem;
    if (problem == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _LinkProblemDialog(
        currentProblem: problem,
        linkedProblemIds: problem.linkedProblemIds,
      ),
    );
    if (result == true && mounted) {
      await _load();
    }
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
          _buildLinkedProblemsList(),
          _buildVoterList(),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => context.go('/'),
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
          _buildLinkedProblemsList(),
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
                    onPressed: () => context.go('/'),
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
                onPressed: () => context.go('/'),
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
              if (userId != null)
                IconButton(
                  tooltip: l10n.linkProblemButton,
                  icon: const Icon(Icons.link),
                  onPressed: () => _showLinkProblemDialog(context),
                ),
            ],
          ),
          body: SingleChildScrollView(
            child: isOwner
                ? _buildEditBody(problem)
                : _buildReadOnlyBody(problem),
          ),
        ),
      ),
    );
  }
}

/// One row in the forks list. Owns the per-fork "expanded" state so each
/// fork can be opened independently. When the viewer owns the parent
/// problem and at least one of (description, goal, geoscope) differs
/// between the parent and this fork, a compare icon is shown; tapping it
/// expands an inline panel that lets the owner copy any differing field
/// into the parent problem as a new revision.
class _ForkRow extends StatefulWidget {
  const _ForkRow({
    required this.current,
    required this.fork,
    required this.canCompare,
    required this.onUseField,
  });

  final Problem current;
  final Problem fork;
  final bool canCompare;

  /// Invoked with [current] copied to include the fork's value for one or
  /// more fields. The callback persists the change and updates ambient
  /// state.
  final Future<void> Function(Problem updated) onUseField;

  @override
  State<_ForkRow> createState() => _ForkRowState();
}

class _ForkRowState extends State<_ForkRow> {
  bool _expanded = false;

  List<_ForkFieldDiff> _computeDiffs() {
    final l10n = context.l10n;
    final diffs = <_ForkFieldDiff>[];
    final descDiffers = widget.fork.description != widget.current.description;
    final goalDiffers = widget.fork.goal != widget.current.goal;
    final geoDiffers = widget.fork.geoscope != widget.current.geoscope;
    // updateProblem requires description and goal to share a language;
    // when the fork's lang doesn't match the current problem's, copying
    // a single text field would leave the result mixed-language and
    // trigger LanguageMismatchException. In that case we bundle the
    // text fields into one diff entry so they're replaced together.
    // Geoscope is language-independent and stays a separate entry.
    final compatibleLangs = widget.fork.lang == widget.current.lang;

    if (compatibleLangs) {
      if (descDiffers) {
        diffs.add(
          _ForkFieldDiff(
            fields: [
              (
                label: l10n.problemDescriptionFieldLabel,
                display: widget.fork.description,
              ),
            ],
            apply: () =>
                widget.current.copyWith(description: widget.fork.description),
          ),
        );
      }
      if (goalDiffers) {
        diffs.add(
          _ForkFieldDiff(
            fields: [
              (
                label: l10n.problemGoalFieldLabel,
                display: widget.fork.goal,
              ),
            ],
            apply: () => widget.current.copyWith(goal: widget.fork.goal),
          ),
        );
      }
    } else if (descDiffers || goalDiffers) {
      diffs.add(
        _ForkFieldDiff(
          fields: [
            (
              label: l10n.problemDescriptionFieldLabel,
              display: widget.fork.description,
            ),
            (
              label: l10n.problemGoalFieldLabel,
              display: widget.fork.goal,
            ),
          ],
          apply: () => widget.current.copyWith(
            description: widget.fork.description,
            goal: widget.fork.goal,
          ),
        ),
      );
    }

    if (geoDiffers) {
      diffs.add(
        _ForkFieldDiff(
          fields: [
            (
              label: l10n.problemGeoscopeFieldLabel,
              display: geoscopeLabel(context, widget.fork.geoscope),
            ),
          ],
          apply: () => widget.current.copyWith(geoscope: widget.fork.geoscope),
        ),
      );
    }
    return diffs;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final diffs = _computeDiffs();
    final showCompareIcon = widget.canCompare && diffs.isNotEmpty;
    final panelOpen = _expanded && showCompareIcon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            widget.fork.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: showCompareIcon
              ? IconButton(
                  tooltip: panelOpen
                      ? l10n.hideForkCompareTooltip
                      : l10n.compareForkTooltip,
                  icon: Icon(
                    panelOpen ? Icons.expand_less : Icons.compare_arrows,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                )
              : null,
          onTap: () => context.push('/problems/${widget.fork.id}'),
        ),
        if (panelOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final diff in diffs)
                  _ForkFieldDiffRow(diff: diff, onUse: widget.onUseField),
              ],
            ),
          ),
      ],
    );
  }
}

/// A single entry in the fork-comparison panel. Usually one field, but
/// description and goal are bundled together when the fork's language
/// differs from the current problem's — see `_computeDiffs` for why.
class _ForkFieldDiff {
  _ForkFieldDiff({required this.fields, required this.apply});

  final List<({String label, String display})> fields;
  final Problem Function() apply;
}

class _ForkFieldDiffRow extends StatelessWidget {
  const _ForkFieldDiffRow({required this.diff, required this.onUse});

  final _ForkFieldDiff diff;
  final Future<void> Function(Problem updated) onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < diff.fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Text(
                    diff.fields[i].label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    diff.fields[i].display,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => onUse(diff.apply()),
            child: Text(l10n.useForkFieldButton),
          ),
        ],
      ),
    );
  }
}

class _LinkProblemDialog extends StatefulWidget {
  const _LinkProblemDialog({
    required this.currentProblem,
    required this.linkedProblemIds,
  });

  final Problem currentProblem;
  final List<String> linkedProblemIds;

  @override
  State<_LinkProblemDialog> createState() => _LinkProblemDialogState();
}

class _LinkProblemDialogState extends State<_LinkProblemDialog> {
  final _searchController = TextEditingController();
  final _uuidRegex = RegExp(
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    '[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  List<Problem> _allProblems = [];
  List<Problem> _searchResults = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadInitialProblems());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialProblems() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<FirestoreRepository>();
      final list = await repo.getGlobalProblemsForSearch();
      if (mounted) {
        setState(() {
          _allProblems = list;
          _loading = false;
          _filterResults();
        });
      }
    } on Exception catch (e) {
      log('Failed to load global problems: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        unawaited(_performSearch());
      }
    });
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(_filterResults);
      return;
    }

    final match = _uuidRegex.firstMatch(query);
    if (match != null) {
      final extractedUuid = match.group(0)!;
      if (!mounted) return;
      setState(() => _loading = true);
      try {
        final repo = context.read<FirestoreRepository>();
        final problem = await repo.getProblem(extractedUuid);
        if (mounted) {
          setState(() {
            _loading = false;
            if (problem != null) {
              _searchResults = [problem];
            } else {
              _searchResults = [];
            }
            _excludeCurrentAndLinked();
          });
        }
      } on Exception catch (e) {
        log('Failed to fetch problem by UUID: $e');
        if (mounted) {
          setState(() {
            _loading = false;
            _searchResults = [];
          });
        }
      }
    } else {
      if (mounted) {
        setState(_filterResults);
      }
    }
  }

  void _filterResults() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _searchResults = List.from(_allProblems);
    } else {
      _searchResults = _allProblems.where((p) {
        final descMatch = p.description.toLowerCase().contains(query);
        final goalMatch = p.goal.toLowerCase().contains(query);
        return descMatch || goalMatch;
      }).toList();
    }
    _excludeCurrentAndLinked();
  }

  void _excludeCurrentAndLinked() {
    _searchResults = _searchResults.where((p) {
      final isSelf = p.id == widget.currentProblem.id;
      final isAlreadyLinked = widget.linkedProblemIds.contains(p.id);
      return !isSelf && !isAlreadyLinked;
    }).toList();
  }

  Future<void> _link(Problem target) async {
    final repo = context.read<FirestoreRepository>();
    final l10n = context.l10n;
    try {
      await repo.linkProblems(widget.currentProblem.id, target.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      log('Failed to link problem: $e');
      showToast(l10n.linkProblemError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.linkProblemDialogTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.linkProblemSearchHint,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        'No problems found',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final problem = _searchResults[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          title: Text(
                            problem.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: problem.goal.isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    problem.goal,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.link),
                            tooltip: l10n.linkProblemButton,
                            color: theme.colorScheme.primary,
                            onPressed: () => _link(problem),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
