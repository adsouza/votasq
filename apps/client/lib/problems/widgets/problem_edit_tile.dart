import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/geoscope_widgets.dart';
import 'package:client/problems/widgets/problem_text_utils.dart';
import 'package:client/services/firestore_repository.dart'
    show LanguageMismatchException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared/shared.dart';

/// An inline edit tile that replaces the read tile when the owner taps edit.
/// Owns its own controllers, focus node, and submission state.
class ProblemEditTile extends StatefulWidget {
  const ProblemEditTile({
    required this.problem,
    required this.tapRegionGroupId,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final Problem problem;
  final Object tapRegionGroupId;
  final VoidCallback onCancel;

  /// Called with the updated problem and the user's language code. The parent
  /// forwards this to `ProblemsCubit.updateProblem`.
  final Future<void> Function(
    Problem updatedProblem, {
    required String userLanguage,
  })
  onSubmit;

  @override
  State<ProblemEditTile> createState() => _ProblemEditTileState();
}

class _ProblemEditTileState extends State<ProblemEditTile> {
  final _editController = TextEditingController();
  final _editGoalController = TextEditingController();
  final _editFocusNode = FocusNode();
  String? _editProblemGeoscope;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _editController.text = widget.problem.description;
    _editGoalController.text = widget.problem.goal;
    _editProblemGeoscope = widget.problem.geoscope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    _editGoalController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitEdit() async {
    if (_submitting || !hasEnoughWords(_editController.text)) return;
    final newDescription = _editController.text.trim();
    final newGoal = _editGoalController.text.trim();
    final newGeoscope = _editProblemGeoscope ?? widget.problem.geoscope;
    if (newDescription != widget.problem.description ||
        newGoal != widget.problem.goal ||
        newGeoscope != widget.problem.geoscope) {
      final userLang = Localizations.localeOf(context).languageCode;
      setState(() => _submitting = true);
      try {
        await widget.onSubmit(
          widget.problem.copyWith(
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
        if (mounted && _submitting) {
          setState(() => _submitting = false);
        }
      }
    }
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TapRegion(
      groupId: widget.tapRegionGroupId,
      onTapOutside: (_) => widget.onCancel(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onCancel();
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
                          maxLength: maxProblemTextLength,
                          decoration: InputDecoration(
                            hintText: l10n.editProblemHint,
                          ),
                          onSubmitted:
                              hasEnoughWords(_editController.text) &&
                                  !_submitting
                              ? (_) => _submitEdit()
                              : null,
                        ),
                        TextField(
                          controller: _editGoalController,
                          readOnly: _submitting,
                          maxLength: maxProblemTextLength,
                          decoration: InputDecoration(
                            hintText: l10n.editGoalHint,
                          ),
                          onSubmitted:
                              hasEnoughWords(_editController.text) &&
                                  !_submitting
                              ? (_) => _submitEdit()
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
                  final hasWords = hasEnoughWords(_editController.text);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...buildGeoscopeDropdown(
                        context,
                        geoscope: context
                            .read<GeoscopeCubit>()
                            .state
                            .selectedGeoscope,
                        currentValue:
                            _editProblemGeoscope ?? widget.problem.geoscope,
                        onChanged: (value) => setState(() {
                          _editProblemGeoscope = value;
                        }),
                        enabled: hasWords,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: hasWords && !_submitting
                            ? _submitEdit
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
}
