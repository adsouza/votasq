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

/// Row at the top of the problems list that lets authenticated users submit a
/// new problem with an optional goal.
class AddProblemRow extends StatefulWidget {
  const AddProblemRow({
    required this.onSubmit,
    required this.defaultGeoscope,
    super.key,
  });

  /// Called when the user submits a valid problem. The parent is responsible
  /// for forwarding to `ProblemsCubit.addProblem`.
  final Future<void> Function({
    required String description,
    required String goal,
    required String? geoscope,
  })
  onSubmit;

  /// The geoscope pre-selected from `GeoscopeCubit`.
  final String defaultGeoscope;

  @override
  State<AddProblemRow> createState() => _AddProblemRowState();
}

class _AddProblemRowState extends State<AddProblemRow> {
  final _addController = TextEditingController();
  final _addGoalController = TextEditingController();
  final _addFocusNode = FocusNode();
  final _addRowFocusNode = FocusNode();
  final _keyboardListenerFocusNode = FocusNode();
  bool _addGoalVisible = false;
  String? _addProblemGeoscope;
  bool _submitting = false;

  @override
  void dispose() {
    _addController.dispose();
    _addGoalController.dispose();
    _addFocusNode.dispose();
    _addRowFocusNode.dispose();
    _keyboardListenerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitProblem() async {
    if (_submitting || !hasEnoughWords(_addController.text)) return;
    final text = _addController.text.trim();
    final goalText = _addGoalController.text.trim();

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        description: text,
        goal: goalText,
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
      final hasWords = hasEnoughWords(_addController.text);
      final rowHasFocus = _addRowFocusNode.hasFocus;
      final shouldShow = hasWords && rowHasFocus;
      if (shouldShow != _addGoalVisible) {
        setState(() => _addGoalVisible = shouldShow);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: KeyboardListener(
        focusNode: _keyboardListenerFocusNode,
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
                          maxLength: maxProblemTextLength,
                          decoration: InputDecoration(
                            hintText: l10n.addProblemHint,
                          ),
                          onChanged: (_) => _onAddDescriptionChanged(),
                          onSubmitted:
                              hasEnoughWords(_addController.text) &&
                                  !_submitting
                              ? (_) => _submitProblem()
                              : null,
                        ),
                        if (_addGoalVisible)
                          TextField(
                            controller: _addGoalController,
                            readOnly: _submitting,
                            maxLength: maxProblemTextLength,
                            decoration: InputDecoration(
                              hintText: l10n.addGoalHint,
                            ),
                            onSubmitted:
                                hasEnoughWords(_addController.text) &&
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
                  final hasWords = hasEnoughWords(_addController.text);
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
}
