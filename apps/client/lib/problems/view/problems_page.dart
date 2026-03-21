import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:feedback/feedback.dart';
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
  final _editController = TextEditingController();
  final _editFocusNode = FocusNode();
  static final _editTapRegionGroupId = Object();
  String? _editingProblemId;
  String? _addProblemGeoscope;
  String? _editProblemGeoscope;

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
    _addController.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isNearBottom) {
      unawaited(context.read<ProblemsCubit>().loadMore());
    }
  }

  static bool _hasEnoughWords(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length >= 3;

  void _submitProblem() {
    if (!_hasEnoughWords(_addController.text)) return;
    final text = _addController.text.trim();
    final userId = context.read<AuthCubit>().state.userId!;
    unawaited(
      context.read<ProblemsCubit>().addProblem(
        description: text,
        ownerId: userId,
        geoscope: _addProblemGeoscope,
      ),
    );
    _addController.clear();
    setState(() {
      _addProblemGeoscope = null;
    });
  }

  Widget _buildAddProblemRow(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _addController,
              builder: (context, value, child) {
                return TextField(
                  controller: _addController,
                  maxLength: 80,
                  decoration: InputDecoration(
                    hintText: l10n.addProblemHint,
                  ),
                  onSubmitted: _hasEnoughWords(_addController.text)
                      ? (_) => _submitProblem()
                      : null,
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
                        context.read<GeoscopeCubit>().state.selectedGeoscope,
                    onChanged: (value) => setState(() {
                      _addProblemGeoscope = value;
                    }),
                    enabled: hasWords,
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l10n.addProblemTooltip,
                    child: ElevatedButton(
                      onPressed: hasWords ? _submitProblem : null,
                      child: Text(l10n.addProblemButton),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
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
      final label = id == '/' ? l10n.geoscopeGlobal : (labelMap[id] ?? id);
      return DropdownMenuItem(value: id, child: Text(label));
    }).toList();

    // If currentValue isn't in the ancestor list (e.g. problem was created
    // under a different geoscope), fall back to the most granular ancestor.
    final effectiveValue = ancestorIds.contains(currentValue)
        ? currentValue
        : ancestorIds.first;

    return [
      const SizedBox(width: 8),
      DropdownButton<String>(
        value: effectiveValue,
        items: items,
        selectedItemBuilder: (_) => ancestorIds.map((id) {
          if (id == '/') return Text(l10n.geoscopeGlobal);
          return Text(id.split('/').last);
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

  void _startEdit(Problem problem) {
    setState(() {
      _editingProblemId = problem.id;
      _editProblemGeoscope = problem.geoscope;
      _editController.text = problem.description;
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

  void _submitEdit(Problem problem) {
    if (!_hasEnoughWords(_editController.text)) return;
    final newDescription = _editController.text.trim();
    final newGeoscope = _editProblemGeoscope ?? problem.geoscope;
    if (newDescription != problem.description ||
        newGeoscope != problem.geoscope) {
      unawaited(
        context.read<ProblemsCubit>().updateProblem(
          problem.copyWith(
            description: newDescription,
            geoscope: newGeoscope,
          ),
        ),
      );
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
    return ListTile(
      title: Text('${problem.description} (${problem.votes})'),
      trailing: showEditButton
          ? Tooltip(
              message: l10n.editProblemButton,
              child: TextButton(
                onPressed: () => _startEdit(problem),
                child: const Text('🖊️'),
              ),
            )
          : showComplaintButton
          ? Tooltip(
              message: l10n.flagProblemButton,
              child: TextButton(
                onPressed: () => _confirmComplaint(problem),
                child: const Text('🙈'),
              ),
            )
          : null,
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
                    return TextField(
                      controller: _editController,
                      focusNode: _editFocusNode,
                      maxLength: 80,
                      decoration: InputDecoration(
                        hintText: l10n.editProblemHint,
                      ),
                      onSubmitted: _hasEnoughWords(_editController.text)
                          ? (_) => _submitEdit(problem)
                          : null,
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
                        onPressed: hasWords ? () => _submitEdit(problem) : null,
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
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) {
          final items = [
            (id: '/', label: l10n.geoscopeGlobal),
            ...geoState.availableGeoscopes,
          ];
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              final isSelected = item.id == geoState.selectedGeoscope;
              return ListTile(
                title: Text(item.label),
                trailing: isSelected ? const Icon(Icons.check) : null,
                onTap: () {
                  unawaited(geoscopeCubit.selectGeoscope(item.id));
                  Navigator.of(context).pop();
                },
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
        title: Text(l10n.problemsAppBarTitle),
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          onSelected: (value) {
            if (value == 'change_location') {
              _showGeoscopePicker(context);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'change_location',
              child: ListTile(
                leading: const Icon(Icons.location_on),
                title: Text(l10n.geoscopeChangeMenuItem),
                contentPadding: EdgeInsets.zero,
              ),
            ),
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
              return TextButton(
                onPressed: () => context.read<AuthCubit>().signIn(),
                child: Text(l10n.signInButton),
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
                      final visible = userId == null
                          ? state.problems
                          : state.problems
                                .where(
                                  (p) => !p.complaints.contains(userId),
                                )
                                .toList();
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
