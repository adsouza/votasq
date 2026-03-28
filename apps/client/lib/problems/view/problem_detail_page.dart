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
    try {
      final problem = await context.read<FirestoreRepository>().getProblem(
        widget.problemId,
      );
      if (!mounted) return;
      if (problem == null) {
        setState(() {
          _loading = false;
          _error = context.l10n.problemNotFound;
        });
        return;
      }
      final voters = await context
          .read<FirestoreRepository>()
          .getVotersForProblem(
            problem.id,
            excludeUid: problem.ownerId,
            anonymous: context.l10n.voterAnonymous,
          );
      if (!mounted) return;
      setState(() {
        _problem = problem;
        _voters = voters;
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

  Future<void> _save() async {
    final problem = _problem;
    if (problem == null || !hasEnoughWords(_controller.text)) return;
    final newDescription = _controller.text.trim();
    final newGoal = _goalController.text.trim();
    final newGeoscope = _geoscope ?? problem.geoscope;
    if (newDescription != problem.description ||
        newGoal != problem.goal ||
        newGeoscope != problem.geoscope) {
      try {
        final userLang = Localizations.localeOf(context).languageCode;
        await context.read<FirestoreRepository>().updateProblem(
          problem.copyWith(
            description: newDescription,
            goal: newGoal,
            geoscope: newGeoscope,
          ),
          userLanguage: userLang,
        );
      } on LanguageMismatchException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.languageMismatchError(
                  e.descriptionLang,
                  e.goalLang,
                ),
              ),
            ),
          );
        }
        return;
      } on Exception catch (e) {
        log('Failed to save problem: $e');
      }
    }
    if (mounted) context.pop();
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.problemDetailPageTitle)),
          body: isOwner ? _buildEditBody(problem) : _buildReadOnlyBody(problem),
        ),
      ),
    );
  }
}
