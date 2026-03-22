import 'dart:developer';

import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Displays [text] with an optional translate icon when [lang] differs from
/// the app's current locale. Tapping the icon fetches and shows the
/// translation inline.
class TranslatableText extends StatefulWidget {
  const TranslatableText(
    this.text, {
    this.lang,
    this.style,
    super.key,
  });

  final String text;

  /// BCP-47 language code the text was written in, or `null` if unknown.
  final String? lang;
  final TextStyle? style;

  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  String? _translatedText;
  bool _translating = false;

  @override
  void didUpdateWidget(TranslatableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.lang != widget.lang) {
      _translatedText = null;
      _translating = false;
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
      final repo = context.read<TranslationRepository>();
      final userLanguage = Localizations.localeOf(context).languageCode;
      final result = await repo.translate(
        text: widget.text,
        targetLanguage: userLanguage,
        sourceLanguage: widget.lang,
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
