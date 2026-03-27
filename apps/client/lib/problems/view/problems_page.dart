import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/problems/widgets/problem_translation.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository, LanguageMismatchException;
import 'package:client/services/translation_repository.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';
import 'package:word_count/word_count.dart';

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
  final _addController = TextEditingController();
  final _addGoalController = TextEditingController();
  final _editController = TextEditingController();
  final _editGoalController = TextEditingController();
  final _addFocusNode = FocusNode();
  final _addRowFocusNode = FocusNode();
  final _editFocusNode = FocusNode();
  static final _editTapRegionGroupId = Object();
  String? _editingProblemId;
  String? _addProblemGeoscope;
  String? _editProblemGeoscope;
  bool _showOnlyOwned = false;
  bool _showOnlyWithGoals = false;
  bool _addGoalVisible = false;
  bool _submitting = false;

  String _geoscopeLabel(String geoscope) {
    if (geoscope == '/') return '🌐 ${context.l10n.geoscopeGlobal}';
    final available = context.read<GeoscopeCubit>().state.availableGeoscopes;
    for (final g in available) {
      if (g.id == geoscope) return g.label;
    }
    return geoscope.split('/').last.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSignInHintIfUnauthenticated();
    });
  }

  void _showSignInHintIfUnauthenticated() {
    final userId = context.read<AuthCubit>().state.userId;
    if (userId != null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.signInHintToast),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _addController.dispose();
    _addGoalController.dispose();
    _addFocusNode.dispose();
    _addRowFocusNode.dispose();
    _editController.dispose();
    _editGoalController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isNearBottom) {
      unawaited(context.read<ProblemsCubit>().loadMore());
    }
  }

  static bool _hasEnoughWords(String text) =>
      text.length >= 20 && wordsCount(text.trim()) >= 3;

  Future<void> _submitProblem() async {
    if (_submitting || !_hasEnoughWords(_addController.text)) return;
    final text = _addController.text.trim();
    final goalText = _addGoalController.text.trim();
    final userId = context.read<AuthCubit>().state.userId!;
    final userLang = Localizations.localeOf(context).languageCode;

    setState(() => _submitting = true);
    try {
      await context.read<ProblemsCubit>().addProblem(
        description: text,
        goal: goalText,
        ownerId: userId,
        userLanguage: userLang,
        geoscope: _addProblemGeoscope,
      );
      // Success — clear fields.
      _addController.clear();
      _addGoalController.clear();
      setState(() {
        _addProblemGeoscope = null;
        _addGoalVisible = false;
      });
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
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onAddDescriptionChanged() {
    _updateAddGoalVisibility();
  }

  /// Show the goal field when the description has enough words and anything
  /// in the add-problem row is focused. We defer the check by one frame so
  /// that focus has settled on the new target when tabbing between fields.
  void _updateAddGoalVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasWords = _hasEnoughWords(_addController.text);
      final rowHasFocus = _addRowFocusNode.hasFocus;
      final shouldShow = hasWords && rowHasFocus;
      if (shouldShow != _addGoalVisible) {
        setState(() => _addGoalVisible = shouldShow);
      }
    });
  }

  Widget _buildAddProblemRow(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _addGoalController.clear();
            _addFocusNode.unfocus();
            setState(() => _addGoalVisible = false);
          }
        },
        child: Focus(
          focusNode: _addRowFocusNode,
          onFocusChange: (_) => _updateAddGoalVisibility(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _addController,
                  builder: (context, value, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _addController,
                          focusNode: _addFocusNode,
                          readOnly: _submitting,
                          maxLength: 80,
                          decoration: InputDecoration(
                            hintText: l10n.addProblemHint,
                          ),
                          onChanged: (_) => _onAddDescriptionChanged(),
                          onSubmitted:
                              _hasEnoughWords(_addController.text) &&
                                  !_submitting
                              ? (_) => _submitProblem()
                              : null,
                        ),
                        if (_addGoalVisible)
                          TextField(
                            controller: _addGoalController,
                            readOnly: _submitting,
                            maxLength: 80,
                            decoration: InputDecoration(
                              hintText: l10n.addGoalHint,
                            ),
                            onSubmitted:
                                _hasEnoughWords(_addController.text) &&
                                    !_submitting
                                ? (_) => _submitProblem()
                                : null,
                          ),
                      ],
                    );
                  },
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _addController,
                builder: (context, value, child) {
                  final hasWords = _hasEnoughWords(_addController.text);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._buildGeoscopeDropdown(
                        geoscope: context
                            .read<GeoscopeCubit>()
                            .state
                            .selectedGeoscope,
                        currentValue:
                            _addProblemGeoscope ??
                            context
                                .read<GeoscopeCubit>()
                                .state
                                .selectedGeoscope,
                        onChanged: (value) => setState(() {
                          _addProblemGeoscope = value;
                        }),
                        enabled: hasWords,
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: l10n.addProblemTooltip,
                        child: ElevatedButton(
                          onPressed: hasWords && !_submitting
                              ? _submitProblem
                              : null,
                          child: Text(l10n.addProblemButton),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a geoscope dropdown for the given [geoscope] value.
  /// [currentValue] is the currently selected ID, [onChanged] is called when
  /// the user picks a new level. Returns an empty list if the geoscope is
  /// global (`"/"`), hiding the dropdown entirely.
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
          : (labelMap[id] ?? id.split('/').last.toUpperCase());
      return DropdownMenuItem(value: id, child: Text(label));
    }).toList();

    // If currentValue isn't in the ancestor list (e.g. problem was created
    // under a different geoscope), fall back to the most granular ancestor.
    final effectiveValue = ancestorIds.contains(currentValue)
        ? currentValue
        : ancestorIds.first;

    return [
      const SizedBox(width: 8),
      Tooltip(
        message: l10n.geoscopeDropdownTooltip,
        child: DropdownButton<String>(
          value: effectiveValue,
          menuWidth: 240,
          items: items,
          selectedItemBuilder: (_) => ancestorIds.map((id) {
            if (id == '/') return const Text('🌐');
            return Text(id.split('/').last);
          }).toList(),
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  onChanged(value);
                }
              : null,
        ),
      ),
    ];
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
      _editProblemGeoscope = problem.geoscope;
      _editController.text = problem.description;
      _editGoalController.text = problem.goal;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingProblemId = null;
      _editProblemGeoscope = null;
    });
  }

  Future<void> _submitEdit(Problem problem) async {
    if (_submitting || !_hasEnoughWords(_editController.text)) return;
    final newDescription = _editController.text.trim();
    final newGoal = _editGoalController.text.trim();
    final newGeoscope = _editProblemGeoscope ?? problem.geoscope;
    if (newDescription != problem.description ||
        newGoal != problem.goal ||
        newGeoscope != problem.geoscope) {
      final userLang = Localizations.localeOf(context).languageCode;
      setState(() => _submitting = true);
      try {
        await context.read<ProblemsCubit>().updateProblem(
          problem.copyWith(
            description: newDescription,
            goal: newGoal,
            geoscope: newGeoscope,
          ),
          userLanguage: userLang,
        );
      } on LanguageMismatchException catch (e) {
        if (mounted) {
          setState(() => _submitting = false);
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
      } finally {
        if (mounted && _submitting) setState(() => _submitting = false);
      }
    }
    _cancelEdit();
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
        const SnackBar(content: Text('Complaint submitted')),
      );
    }
  }

  Widget _buildReadTile(
    Problem problem, {
    required bool showEditButton,
    required bool showComplaintButton,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: ProblemTranslation(
        problemId: problem.id,
        lang: problem.lang,
        originalDescription: problem.description,
        originalGoal: problem.goal,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            GestureDetector(
              onDoubleTap: () => context.go('/problems/${problem.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TranslatedField(
                    problem.description,
                    fieldSelector: (tp) => tp.description,
                  ),
                  if (problem.goal.isNotEmpty)
                    TranslatedField(
                      problem.goal,
                      fieldSelector: (tp) => tp.goal,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            if (problem.geoscope != '/')
              Tooltip(
                message:
                    '${l10n.geoscopeLabel}'
                    ' ${_geoscopeLabel(problem.geoscope)}',
                child: Chip(
                  label: Text(
                    problem.geoscope.split('/').last,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            Builder(
              builder: (context) {
                final authState = context.watch<AuthCubit>().state;
                final userId = authState.userId;
                if (userId != null && (authState.remainingVotes ?? 0) > 0) {
                  return Tooltip(
                    message: l10n.voteButtonTooltip,
                    child: ActionChip(
                      avatar: const Icon(
                        Icons.arrow_circle_up_rounded,
                        size: 16,
                      ),
                      label: Text(
                        '${problem.votes}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () {
                        unawaited(
                          context.read<ProblemsCubit>().vote(
                            problemId: problem.id,
                            userId: userId,
                          ),
                        );
                      },
                    ),
                  );
                }
                return Tooltip(
                  message: l10n.votesChipTooltip,
                  child: Chip(
                    label: Text(
                      '${problem.votes}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              },
            ),
            const ProblemTranslateButton(),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: l10n.copyProblemLink,
            child: IconButton(
              icon: const Icon(Icons.link, size: 20),
              onPressed: () => _copyProblemLink(problem),
            ),
          ),
          if (showEditButton)
            Tooltip(
              message: l10n.editProblemButton,
              child: TextButton(
                onPressed: () => _startEdit(problem),
                child: const Text('🖊️'),
              ),
            )
          else if (showComplaintButton)
            Tooltip(
              message: l10n.flagProblemButton,
              child: TextButton(
                onPressed: () => _confirmComplaint(problem),
                child: const Text('🙈'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditTile(Problem problem) {
    final l10n = context.l10n;
    return TapRegion(
      groupId: _editTapRegionGroupId,
      onTapOutside: (_) => _cancelEdit(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _cancelEdit();
            }
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _editController,
                  builder: (context, value, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _editController,
                          focusNode: _editFocusNode,
                          readOnly: _submitting,
                          maxLength: 80,
                          decoration: InputDecoration(
                            hintText: l10n.editProblemHint,
                          ),
                          onSubmitted:
                              _hasEnoughWords(_editController.text) &&
                                  !_submitting
                              ? (_) => _submitEdit(problem)
                              : null,
                        ),
                        TextField(
                          controller: _editGoalController,
                          readOnly: _submitting,
                          maxLength: 80,
                          decoration: InputDecoration(
                            hintText: l10n.editGoalHint,
                          ),
                          onSubmitted:
                              _hasEnoughWords(_editController.text) &&
                                  !_submitting
                              ? (_) => _submitEdit(problem)
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _editController,
                builder: (context, value, child) {
                  final hasWords = _hasEnoughWords(_editController.text);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._buildGeoscopeDropdown(
                        geoscope: context
                            .read<GeoscopeCubit>()
                            .state
                            .selectedGeoscope,
                        currentValue: _editProblemGeoscope ?? problem.geoscope,
                        onChanged: (value) => setState(() {
                          _editProblemGeoscope = value;
                        }),
                        enabled: hasWords,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: hasWords && !_submitting
                            ? () => _submitEdit(problem)
                            : null,
                        child: const Text('✓'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGeoscopePicker(BuildContext context) {
    final l10n = context.l10n;
    final geoscopeCubit = context.read<GeoscopeCubit>();
    final geoState = geoscopeCubit.state;
    const superstateIds = {'us', 'in', 'eu'};
    final allGeo = geoState.availableGeoscopes;
    final labelMap = {for (final g in allGeo) g.id: g.label};
    final superstates = allGeo
        .where((g) => superstateIds.contains(g.id))
        .toList();

    final activeParts = geoState.selectedGeoscope == '/'
        ? <String>[]
        : geoState.selectedGeoscope.split('/');
    String? selectedSuperstate;
    String? selectedCountry;
    if (activeParts.isNotEmpty) {
      final firstSeg = activeParts.first;
      if (superstateIds.contains(firstSeg)) {
        selectedSuperstate = firstSeg;
        if (activeParts.length >= 2) {
          selectedCountry = activeParts.sublist(0, 2).join('/');
        }
      } else if (activeParts.length >= 2) {
        selectedCountry = firstSeg;
      }
    }

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              // Build States section.
              List<({String id, String label})> stateItems;
              if (selectedSuperstate != null) {
                final prefix = '$selectedSuperstate/';
                stateItems = allGeo
                    .where(
                      (g) =>
                          g.id.startsWith(prefix) &&
                          g.id.split('/').length == 2,
                    )
                    .toList();
              } else {
                final seen = <String>{};
                stateItems = [];
                for (final g in allGeo) {
                  final firstSeg = g.id.split('/').first;
                  if (!superstateIds.contains(firstSeg) && seen.add(firstSeg)) {
                    stateItems.add((
                      id: firstSeg,
                      label: labelMap[firstSeg] ?? firstSeg,
                    ));
                  }
                }
              }

              // Build Metro areas section.
              List<({String id, String label})> metroItems;
              if (selectedCountry != null) {
                final prefix = '$selectedCountry/';
                metroItems = allGeo
                    .where((g) => g.id.startsWith(prefix))
                    .toList();
              } else if (selectedSuperstate != null) {
                final prefix = '$selectedSuperstate/';
                metroItems = allGeo
                    .where(
                      (g) =>
                          g.id.startsWith(prefix) &&
                          g.id.split('/').length >= 3,
                    )
                    .toList();
              } else {
                metroItems = allGeo.where((g) {
                  final parts = g.id.split('/');
                  return parts.length >= 3 ||
                      (parts.length == 2 &&
                          !superstateIds.contains(parts.first));
                }).toList();
              }

              final activeId = geoscopeCubit.state.selectedGeoscope;

              return ListView(
                children: [
                  // Global option.
                  ListTile(
                    title: Text('🌐 ${l10n.geoscopeGlobal}'),
                    trailing: activeId == '/' ? const Icon(Icons.check) : null,
                    onTap: () {
                      unawaited(geoscopeCubit.selectGeoscope('/'));
                      Navigator.of(context).pop();
                    },
                  ),
                  const Divider(),

                  // Superstates header.
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      top: 8,
                      bottom: 4,
                    ),
                    child: Text(
                      'Superstates',
                      style: Theme.of(sheetContext).textTheme.labelSmall,
                    ),
                  ),
                  for (final s in superstates)
                    ListTile(
                      title: Text(s.label),
                      trailing: activeId == s.id
                          ? const Icon(Icons.check)
                          : selectedSuperstate == s.id
                          ? const Icon(Icons.expand_more)
                          : null,
                      onTap: () {
                        if (selectedSuperstate == s.id) {
                          setSheetState(() {
                            selectedSuperstate = null;
                            selectedCountry = null;
                          });
                          unawaited(geoscopeCubit.selectGeoscope('/'));
                        } else {
                          setSheetState(() {
                            if (selectedSuperstate != s.id) {
                              selectedCountry = null;
                            }
                            selectedSuperstate = s.id;
                          });
                          unawaited(geoscopeCubit.selectGeoscope(s.id));
                        }
                      },
                    ),

                  // States section.
                  if (stateItems.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'States',
                        style: Theme.of(sheetContext).textTheme.labelSmall,
                      ),
                    ),
                    for (final m in stateItems)
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 32,
                          right: 16,
                        ),
                        title: Text(m.label),
                        trailing: activeId == m.id
                            ? const Icon(Icons.check)
                            : selectedCountry == m.id
                            ? const Icon(Icons.expand_more)
                            : null,
                        onTap: () {
                          if (selectedCountry == m.id) {
                            setSheetState(() {
                              selectedCountry = null;
                            });
                            unawaited(
                              geoscopeCubit.selectGeoscope(
                                selectedSuperstate ?? '/',
                              ),
                            );
                          } else {
                            unawaited(geoscopeCubit.selectGeoscope(m.id));
                            final hasMetro = allGeo.any(
                              (g) => g.id.startsWith('${m.id}/'),
                            );
                            if (hasMetro) {
                              setSheetState(() {
                                selectedCountry = m.id;
                              });
                            } else {
                              Navigator.of(context).pop();
                            }
                          }
                        },
                      ),
                  ],

                  // Metro areas section.
                  if (metroItems.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'Metro areas',
                        style: Theme.of(sheetContext).textTheme.labelSmall,
                      ),
                    ),
                    for (final b in metroItems)
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 48,
                          right: 16,
                        ),
                        title: Text(b.label),
                        trailing: activeId == b.id
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () {
                          if (activeId == b.id) {
                            unawaited(
                              geoscopeCubit.selectGeoscope(
                                selectedCountry ?? selectedSuperstate ?? '/',
                              ),
                            );
                            setSheetState(() {});
                          } else {
                            unawaited(geoscopeCubit.selectGeoscope(b.id));
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
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
            var filtered = state.problems;
            if (userId != null) {
              filtered = filtered
                  .where(
                    (p) => !p.complaints.contains(userId),
                  )
                  .toList();
            }
            if (_showOnlyOwned && userId != null) {
              filtered = filtered.where((p) => p.ownerId == userId).toList();
            }
            if (_showOnlyWithGoals) {
              filtered = filtered.where((p) => p.goal.isNotEmpty).toList();
            }
            return Text(
              '${filtered.length} ${l10n.problemsAppBarTitle}',
            );
          },
        ),
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          onSelected: (value) {
            if (value == 'change_location') {
              _showGeoscopePicker(context);
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
                builder: (context, _) => _buildAddProblemRow(context),
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
                        const Text('Failed to load problems'),
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
                      var filtered = state.problems;
                      if (userId != null) {
                        filtered = filtered
                            .where((p) => !p.complaints.contains(userId))
                            .toList();
                      }
                      if (_showOnlyOwned && userId != null) {
                        filtered = filtered
                            .where((p) => p.ownerId == userId)
                            .toList();
                      }
                      if (_showOnlyWithGoals) {
                        filtered = filtered
                            .where((p) => p.goal.isNotEmpty)
                            .toList();
                      }
                      final visible = filtered;
                      return ListView.builder(
                        controller: _scrollController,
                        itemCount: visible.length + (state.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= visible.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final problem = visible[index];
                          if (_editingProblemId == problem.id) {
                            return _buildEditTile(problem);
                          }
                          final isOwner =
                              userId != null && userId == problem.ownerId;
                          return _buildReadTile(
                            problem,
                            showEditButton: isOwner,
                            showComplaintButton: userId != null && !isOwner,
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
