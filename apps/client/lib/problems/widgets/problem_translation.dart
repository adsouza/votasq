import 'dart:async';
import 'dart:developer';

import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared/shared.dart';

/// Wraps a [child] and manages the translation lifecycle for a single problem.
///
/// Compares the problem's [lang] against the user's locale to determine if
/// translation is needed. Descendants access the translation state via
/// [ProblemTranslation.of].
class ProblemTranslation extends StatefulWidget {
  const ProblemTranslation({
    required this.problemId,
    required this.originalDescription,
    required this.child,
    this.originalGoal = '',
    this.lang,
    super.key,
  });

  /// The problem's document ID.
  final String problemId;

  /// The original description text, used for on-device translation.
  final String originalDescription;

  /// The original goal text, used for on-device translation.
  final String originalGoal;

  /// BCP-47 language code the problem was written in, or `null` if unknown.
  final String? lang;

  /// The widget subtree that may contain [TranslatedField] widgets.
  final Widget child;

  /// Returns the translation scope from the nearest ancestor, or `null`.
  static ProblemTranslationState? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ProblemTranslationScope>()
        ?.state;
  }

  @override
  State<ProblemTranslation> createState() => _ProblemTranslationState();
}

/// The translation state exposed to descendants via [ProblemTranslation.of].
class ProblemTranslationState {
  const ProblemTranslationState({
    required this.translation,
    required this.needsTranslation,
    required this.isTranslating,
    required this.isCheckingCache,
    required this.translate,
    this.autoTranslate = false,
  });

  final TranslatedProblem? translation;
  final bool needsTranslation;
  final bool isTranslating;
  final bool isCheckingCache;
  final VoidCallback translate;
  final bool autoTranslate;
}

class _ProblemTranslationState extends State<ProblemTranslation> {
  TranslatedProblem? _translation;
  bool _translating = false;
  bool _cacheChecked = false;

  @override
  void didUpdateWidget(ProblemTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.problemId != widget.problemId ||
        oldWidget.lang != widget.lang ||
        oldWidget.originalDescription != widget.originalDescription ||
        oldWidget.originalGoal != widget.originalGoal) {
      _translation = null;
      _translating = false;
      _cacheChecked = false;
      _scheduleAutoTranslate();
    }
  }

  void _scheduleAutoTranslate() {
    if (!_needsTranslation || _translating || _translation != null) return;
    try {
      if (!context.read<AutoTranslateCubit>().state) return;
    } on Exception {
      return; // Cubit not provided (e.g. in tests without it).
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _translation == null && !_translating) {
        unawaited(_translate());
      }
    });
  }

  /// Probes the Firestore cache for an existing translation. Does not trigger
  /// on-device or server-side translation.
  Future<void> _checkCache() async {
    if (_cacheChecked || _translating || _translation != null) return;
    _cacheChecked = true;
    try {
      final userLanguage = Localizations.localeOf(context).languageCode;
      final firestoreRepo = context.read<FirestoreRepository>();
      final cached = await firestoreRepo.getTranslation(
        widget.problemId,
        userLanguage,
      );
      if (mounted) {
        setState(() {
          if (cached != null) _translation = cached;
        });
      }
    } on Exception catch (e) {
      log('Cache check failed: $e');
      if (mounted) setState(() {});
    }
  }

  bool get _needsTranslation {
    final lang = widget.lang;
    if (lang == null) return false;
    final userLanguage = Localizations.localeOf(context).languageCode;
    return lang != userLanguage;
  }

  Future<void> _translate() async {
    if (_translating) return;
    setState(() => _translating = true);
    try {
      final userLanguage = Localizations.localeOf(context).languageCode;
      final firestoreRepo = context.read<FirestoreRepository>();
      final translationRepo = context.read<TranslationRepository>();

      // 1. Check Firestore cache.
      final cached = await firestoreRepo.getTranslation(
        widget.problemId,
        userLanguage,
      );
      if (cached != null) {
        if (mounted) setState(() => _translation = cached);
        return;
      }

      // 2. Try on-device translation.
      final onDevice = await translationRepo.translate(
        text: widget.originalDescription,
        targetLanguage: userLanguage,
        sourceLanguage: widget.lang,
      );
      if (onDevice != null) {
        String? onDeviceGoal;
        if (widget.originalGoal.isNotEmpty) {
          onDeviceGoal = await translationRepo.translate(
            text: widget.originalGoal,
            targetLanguage: userLanguage,
            sourceLanguage: widget.lang,
          );
        }
        final translated = TranslatedProblem(
          description: onDevice,
          goal: onDeviceGoal ?? '',
        );
        if (mounted) setState(() => _translation = translated);
        // Cache in background so other clients benefit.
        unawaited(
          firestoreRepo.saveTranslation(
            widget.problemId,
            userLanguage,
            translated,
          ),
        );
        return;
      }

      // 3. Server fallback (translates & caches server-side).
      final result = await translationRepo.translateProblem(
        problemId: widget.problemId,
        targetLanguage: userLanguage,
      );
      if (mounted) setState(() => _translation = result);
    } on Exception catch (e) {
      log('Translation failed: $e');
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool autoTranslate;
    try {
      autoTranslate = context.watch<AutoTranslateCubit>().state;
    } on Exception {
      autoTranslate = false;
    }

    if (_needsTranslation && _translation == null && !_translating) {
      if (!_cacheChecked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_checkCache());
        });
      } else if (autoTranslate) {
        _scheduleAutoTranslate();
      }
    }

    return _ProblemTranslationScope(
      state: ProblemTranslationState(
        translation: _translation,
        needsTranslation: _needsTranslation,
        isTranslating: _translating,
        isCheckingCache: _needsTranslation && !_cacheChecked,
        translate: _translate,
        autoTranslate: autoTranslate,
      ),
      child: widget.child,
    );
  }
}

class _ProblemTranslationScope extends InheritedWidget {
  const _ProblemTranslationScope({
    required this.state,
    required super.child,
  });

  final ProblemTranslationState state;

  @override
  bool updateShouldNotify(_ProblemTranslationScope oldWidget) =>
      state.translation != oldWidget.state.translation ||
      state.needsTranslation != oldWidget.state.needsTranslation ||
      state.isTranslating != oldWidget.state.isTranslating ||
      state.isCheckingCache != oldWidget.state.isCheckingCache ||
      state.autoTranslate != oldWidget.state.autoTranslate;
}

/// Displays a single translatable text field within a [ProblemTranslation].
///
/// Reads the translation state from the nearest [ProblemTranslation] ancestor.
/// When a translation is available, shows the original with strikethrough and
/// the translated text below. Otherwise shows the original text as-is.
///
/// Use [ProblemTranslateButton] to show a single translate trigger for the
/// entire problem rather than per-field icons.
class TranslatedField extends StatelessWidget {
  const TranslatedField(
    this.originalText, {
    required this.fieldSelector,
    this.style,
    super.key,
  });

  /// The original (untranslated) text.
  final String originalText;

  /// Extracts this field's translation from a [TranslatedProblem].
  final String? Function(TranslatedProblem) fieldSelector;

  /// Text style for the original (and translated) text.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scope = ProblemTranslation.of(context);
    final theme = Theme.of(context);

    // No translation scope or no translation needed — show plain text.
    if (scope == null || !scope.needsTranslation) {
      return Text(originalText, style: style);
    }

    // Translation available — show original (struck through) + translated.
    final translated = scope.translation != null
        ? fieldSelector(scope.translation!)
        : null;
    if (translated != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            originalText,
            style: (style ?? const TextStyle()).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(translated, style: style),
        ],
      );
    }

    // Translation not yet available — show original text only.
    return Text(originalText, style: style);
  }
}

/// A single translate button for an entire problem.
///
/// Reads the [ProblemTranslation] scope and shows a translate icon (tap to
/// trigger), a spinner (while translating / checking cache), or nothing
/// (when translation is complete or not needed).
class ProblemTranslateButton extends StatelessWidget {
  const ProblemTranslateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ProblemTranslation.of(context);
    final theme = Theme.of(context);

    if (scope == null || !scope.needsTranslation || scope.translation != null) {
      return const SizedBox.shrink();
    }

    if (scope.isTranslating || scope.isCheckingCache || scope.autoTranslate) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return GestureDetector(
      onTap: scope.translate,
      child: Icon(
        Icons.translate,
        size: 16,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
