import 'package:googleapis/translate/v3.dart' as t;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

/// Translates text using Google Cloud Translation API v3.
class Translator {
  Translator._(this._api, this._parent);

  /// Creates a [Translator] backed by the given [client] (for testing /
  /// emulator use).
  Translator.withClient(http.Client client, String projectId)
    : _api = t.TranslateApi(client),
      _parent = 'projects/$projectId/locations/global';

  final t.TranslateApi _api;
  final String _parent;

  /// Creates a [Translator] authenticated via Application Default Credentials.
  static Future<Translator> initialize(String projectId) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [t.TranslateApi.cloudTranslationScope],
    );
    final api = t.TranslateApi(client);
    final parent = 'projects/$projectId/locations/global';
    return Translator._(api, parent);
  }

  /// Translates [text] into [targetLanguage] (a BCP-47 code like `"es"`).
  Future<String> translate({
    required String text,
    required String targetLanguage,
  }) async {
    final result = await translateWithDetection(
      text: text,
      targetLanguage: targetLanguage,
    );
    return result.translatedText;
  }

  /// Translates [text] into [targetLanguage] and also returns the detected
  /// source language. Useful when you need both translation and detection in
  /// a single API call.
  Future<({String translatedText, String detectedLanguage})>
  translateWithDetection({
    required String text,
    required String targetLanguage,
  }) async {
    final response = await _api.projects.locations.translateText(
      t.TranslateTextRequest(
        contents: [text],
        targetLanguageCode: targetLanguage,
        mimeType: 'text/plain',
      ),
      _parent,
    );
    final translation = response.translations!.first;
    return (
      translatedText: translation.translatedText!,
      detectedLanguage: translation.detectedLanguageCode!,
    );
  }

  /// Detects the language of [text]. Returns a BCP-47 code (e.g. `"hi"`).
  Future<String> detectLanguage(String text) async {
    final response = await _api.projects.locations.detectLanguage(
      t.DetectLanguageRequest(content: text, mimeType: 'text/plain'),
      _parent,
    );
    return response.languages!.first.languageCode!;
  }
}
