import 'dart:convert';
import 'dart:developer';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

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
class TranslationRepository {
  TranslationRepository({required String serverBaseUrl, http.Client? client})
    : _baseUrl = serverBaseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  bool _chromeApiUnavailable = false;

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

  /// Fetches the translation for a problem, creating it via Cloud Translate
  /// on the server if not yet cached.
  Future<TranslatedProblem> translateProblem({
    required String problemId,
    required String targetLanguage,
  }) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/problems/$problemId/translations/$targetLanguage'),
    );
    if (response.statusCode != 200) {
      throw Exception('Problem translation failed: ${response.statusCode}');
    }
    return TranslatedProblem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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

  /// Detects the language of [text] via the server's Cloud Translation API.
  Future<String> detectLanguageViaServer(String text) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/detect'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode != 200) {
      throw Exception('Language detection failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['detectedLanguage'] as String;
  }
}
