import 'dart:async';
import 'dart:developer';

import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Displays [text] with an optional translate icon when the detected language
/// differs from the app's current locale. Tapping the icon fetches and shows
/// the translation inline.
class TranslatableText extends StatefulWidget {
  const TranslatableText(
    this.text, {
    this.style,
    super.key,
  });

  final String text;
  final TextStyle? style;

  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  bool _needsTranslation = false;
  String? _lastDetectedText;
  String? _translatedText;
  bool _translating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detectIfNeeded();
  }

  @override
  void didUpdateWidget(TranslatableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _detectIfNeeded();
  }

  void _detectIfNeeded() {
    if (_lastDetectedText != widget.text) {
      _lastDetectedText = widget.text;
      _translatedText = null;
      _translating = false;
      unawaited(_detect());
    }
  }

  Future<void> _detect() async {
    final service = context.read<LanguageDetectionService>();
    final userLanguage = Localizations.localeOf(context).languageCode;
    final result = await service.needsTranslation(
      text: widget.text,
      userLanguage: userLanguage,
    );
    if (mounted && result != _needsTranslation) {
      setState(() => _needsTranslation = result);
    }
  }

  Future<void> _translate() async {
    if (_translating) return;
    setState(() => _translating = true);
    try {
      final repo = context.read<TranslationRepository>();
      final userLanguage = Localizations.localeOf(context).languageCode;
      final result = await repo.translate(
        text: widget.text,
        targetLanguage: userLanguage,
      );
      if (mounted) setState(() => _translatedText = result);
    } on Exception catch (e) {
      log('Translation failed: $e');
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_needsTranslation) {
      return Text(widget.text, style: widget.style);
    }

    // Show translation below original when available.
    if (_translatedText != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            style: (widget.style ?? const TextStyle()).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(_translatedText!, style: widget.style),
        ],
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: widget.text, style: widget.style),
          const TextSpan(text: ' '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _translating
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : GestureDetector(
                    onTap: _translate,
                    child: Icon(
                      Icons.translate,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
