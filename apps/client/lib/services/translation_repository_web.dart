import 'dart:convert';
import 'dart:developer';
import 'dart:js_interop';

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
/// Uses the Chrome Translator API when available, falling back to the server's
/// Cloud Translation endpoint on other browsers.
class TranslationRepository {
  TranslationRepository({required String serverBaseUrl, http.Client? client})
    : _baseUrl = serverBaseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  bool _chromeApiUnavailable = false;

  /// Translates [text] into [targetLanguage] (a BCP-47 code like `"es"`).
  Future<String> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    // Try the Chrome Translator API first.
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

    // Fall back to the server endpoint.
    return _translateViaServer(text: text, targetLanguage: targetLanguage);
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

    final options = _TranslatorOptions(
      sourceLanguage: sourceLanguage ?? 'en',
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

  Future<String> _translateViaServer({
    required String text,
    required String targetLanguage,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/translate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'target': targetLanguage}),
    );
    if (response.statusCode != 200) {
      throw Exception('Translation failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['translatedText'] as String;
  }
}
