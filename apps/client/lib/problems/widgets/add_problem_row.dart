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
  final _keyboardListenerFocusNode = FocusNode();
  bool _addGoalVisible = false;
  String? _addProblemGeoscope;
  bool _submitting = false;

  @override
  void dispose() {
    _addController.dispose();
    _addGoalController.dispose();
    _addFocusNode.dispose();
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

  /// Show the goal field and geoscope picker once the description has enough
  /// words. We deliberately do not gate this on focus — the geoscope dropdown
  /// opens a `PopupRoute` whose own `FocusScope` would otherwise pull focus
  /// out of our row and collapse it mid-interaction. Explicit dismissal still
  /// happens via escape or successful submit.
  void _updateAddGoalVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shouldShow = hasEnoughWords(_addController.text);
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  _addController,
                  _addGoalController,
                ]),
                builder: (context, child) {
                  final selectedGeoscope = context
                      .read<GeoscopeCubit>()
                      .state
                      .selectedGeoscope;
                  final geoscopeDropdown = buildGeoscopeDropdown(
                    context,
                    geoscope: selectedGeoscope,
                    currentValue: _addProblemGeoscope ?? selectedGeoscope,
                    compact: false,
                    onChanged: (value) => setState(() {
                      _addProblemGeoscope = value;
                    }),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                            hasEnoughWords(_addController.text) && !_submitting
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
                      if (_addGoalVisible && geoscopeDropdown.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(l10n.geoscopeLabel),
                              ...geoscopeDropdown,
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([
                _addController,
                _addGoalController,
              ]),
              builder: (context, child) {
                final hasWords =
                    hasEnoughWords(_addController.text) &&
                    (_addGoalController.text.isEmpty ||
                        hasEnoughWords(_addGoalController.text));
                return Tooltip(
                  message: l10n.addProblemTooltip,
                  child: ElevatedButton(
                    onPressed: hasWords && !_submitting ? _submitProblem : null,
                    child: Text(l10n.addProblemButton),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
