import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/translatable_text.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter/material.dart';
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

  static bool _hasEnoughWords(String text) => wordsCount(text.trim()) >= 3;

  Future<void> _save() async {
    final problem = _problem;
    if (problem == null || !_hasEnoughWords(_controller.text)) return;
    final newDescription = _controller.text.trim();
    final newGeoscope = _geoscope ?? problem.geoscope;
    if (newDescription != problem.description ||
        newGeoscope != problem.geoscope) {
      try {
        final userLang = Localizations.localeOf(context).languageCode;
        await context.read<FirestoreRepository>().updateProblem(
          problem.copyWith(
            description: newDescription,
            geoscope: newGeoscope,
          ),
          userLanguage: userLang,
        );
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
      final label = id == '/' ? l10n.geoscopeGlobal : (labelMap[id] ?? id);
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
          final label = id == '/' ? l10n.geoscopeGlobal : (labelMap[id] ?? id);
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
    if (geoscope == '/') return context.l10n.geoscopeGlobal;
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
          TranslatableText(
            problem.description,
            lang: problem.lang,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              if (problem.geoscope != '/')
                Chip(
                  label: Text(_geoscopeLabel(problem.geoscope)),
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                ),
              Chip(
                label: Text('${problem.votes}'),
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
            ],
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.problemDetailPageTitle)),
      body: isOwner ? _buildEditBody(problem) : _buildReadOnlyBody(problem),
    );
  }
}
