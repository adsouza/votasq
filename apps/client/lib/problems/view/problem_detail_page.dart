import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/problem_translation.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository, LanguageMismatchException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';
import 'package:word_count/word_count.dart';

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
      setState(() {
        _problem = problem;
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

  static bool _hasEnoughWords(String text) =>
      text.length >= 20 && wordsCount(text.trim()) >= 3;

  Future<void> _save() async {
    final problem = _problem;
    if (problem == null || !_hasEnoughWords(_controller.text)) return;
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

  List<Widget> _buildGeoscopeDropdown({
    required String geoscope,
    required String currentValue,
    required ValueChanged<String> onChanged,
    bool enabled = true,
  }) {
    if (geoscope == '/') return [];
    final l10n = context.l10n;
    final geoState = context.read<GeoscopeCubit>().state;
    final ancestorIds = FirestoreRepository.geoscopeAncestors(
      geoscope,
    ).reversed.toList();
    final labelMap = {
      for (final g in geoState.availableGeoscopes) g.id: g.label,
    };

    final items = ancestorIds.map((id) {
      final label = id == '/'
          ? '🌐 ${l10n.geoscopeGlobal}'
          : (labelMap[id] ?? id);
      return DropdownMenuItem(value: id, child: Text(label));
    }).toList();

    final effectiveValue = ancestorIds.contains(currentValue)
        ? currentValue
        : ancestorIds.first;

    return [
      const SizedBox(width: 8),
      DropdownButton<String>(
        value: effectiveValue,
        items: items,
        selectedItemBuilder: (_) => ancestorIds.map((id) {
          final label = id == '/'
              ? '🌐 ${l10n.geoscopeGlobal}'
              : (labelMap[id] ?? id);
          return Text(label);
        }).toList(),
        onChanged: enabled
            ? (value) {
                if (value == null) return;
                onChanged(value);
              }
            : null,
      ),
    ];
  }

  String _geoscopeLabel(String geoscope) {
    if (geoscope == '/') return '🌐 ${context.l10n.geoscopeGlobal}';
    final available = context.read<GeoscopeCubit>().state.availableGeoscopes;
    for (final g in available) {
      if (g.id == geoscope) return g.label;
    }
    return geoscope.split('/').last;
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
                          label: Text(_geoscopeLabel(problem.geoscope)),
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
                                await context.read<FirestoreRepository>().vote(
                                  problemId: problem.id,
                                  userId: userId,
                                );
                                if (mounted) {
                                  setState(() {
                                    _problem = problem.copyWith(
                                      votes: problem.votes + 1,
                                    );
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
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: l10n.editProblemHint,
                ),
                onSubmitted: _hasEnoughWords(value.text)
                    ? (_) => _save()
                    : null,
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              return TextField(
                controller: _goalController,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: l10n.editGoalHint,
                ),
                onSubmitted: _hasEnoughWords(value.text)
                    ? (_) => _save()
                    : null,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(l10n.geoscopeLabel),
              ..._buildGeoscopeDropdown(
                geoscope: context.read<GeoscopeCubit>().state.selectedGeoscope,
                currentValue: _geoscope ?? problem.geoscope,
                onChanged: (value) => setState(() {
                  _geoscope = value;
                }),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final hasWords = _hasEnoughWords(_controller.text);
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
