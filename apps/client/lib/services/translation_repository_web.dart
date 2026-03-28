import 'dart:developer';
import 'dart:js_interop';

import 'package:client/services/translation_repository_base.dart';
import 'package:http/http.dart' as http;

/// Feature-detect the Translator global (Chrome 138+).
@JS('Translator')
external JSAny? get _translatorGlobal;

/// JS interop bindings for the Chrome Translator API (Chrome 138+).
@JS('Translator')
extension type _JSTranslator._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability(_TranslatorOptions options);
  external static JSPromise<_JSTranslator> create(_TranslatorOptions options);
  external JSPromise<JSString> translate(String input);
  external void destroy();
}

/// Options object for the Translator API.
extension type _TranslatorOptions._(JSObject _) implements JSObject {
  external factory _TranslatorOptions({
    String sourceLanguage,
    String targetLanguage,
  });
}

/// Translation repository for the web platform.
///
/// [translate] uses the Chrome Translator API when available.
/// Returns `null` on other browsers or when the API fails.
/// [translateProblem] fetches a cached (or freshly Cloud-Translated) result
/// from the server.
class TranslationRepository with TranslationRepositoryBase {
  TranslationRepository({required String serverBaseUrl, http.Client? client})
    : baseUrl = serverBaseUrl,
      client = client ?? http.Client();

  @override
  final String baseUrl;
  @override
  final http.Client client;
  bool _chromeApiUnavailable = false;

  /// Whether this platform supports on-device translation.
  bool get canTranslateOnDevice => !_translatorGlobal.isUndefinedOrNull;

  /// Attempts on-device translation of [text] into [targetLanguage] via the
  /// Chrome Translator API. Returns `null` when unavailable or on failure.
  Future<String?> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    if (!_chromeApiUnavailable) {
      try {
        final result = await _translateViaBrowser(
          text: text,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
        );
        if (result != null) return result;
      } on Object catch (e) {
        log('Chrome Translator API failed: $e');
      }
    }
    return null;
  }

  Future<String?> _translateViaBrowser({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    if (_translatorGlobal.isUndefinedOrNull) {
      _chromeApiUnavailable = true;
      return null;
    }

    // Chrome Translator API requires an explicit source language.
    // If unknown, return null so the caller falls back to the server.
    if (sourceLanguage == null) return null;

    final options = _TranslatorOptions(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    final status = (await _JSTranslator.availability(options).toDart).toDart;
    if (status == 'unavailable') return null;

    final translator = await _JSTranslator.create(options).toDart;
    try {
      return (await translator.translate(text).toDart).toDart;
    } finally {
      translator.destroy();
    }
  }
}
