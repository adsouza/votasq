import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

/// Whether the current platform supports Google ML Kit (iOS & Android only).
final bool _mlKitSupported = Platform.isIOS || Platform.isAndroid;

/// Translation repository for native platforms.
///
/// Uses Google ML Kit for on-device translation on iOS/Android, falling back to
/// the server's Cloud Translation endpoint on desktop or when on-device
/// translation fails (e.g. model not downloaded).
class TranslationRepository {
  TranslationRepository({required String serverBaseUrl, http.Client? client})
    : _baseUrl = serverBaseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// Translates [text] into [targetLanguage] (a BCP-47 code like `"es"`).
  Future<String> translate({
    required String text,
    required String targetLanguage,
  }) async {
    if (_mlKitSupported) {
      // Try ML Kit on-device translation first.
      final target = BCP47Code.fromRawValue(targetLanguage);
      if (target != null) {
        try {
          final source = await _detectSource(text);
          if (source != null && source != target) {
            final translator = OnDeviceTranslator(
              sourceLanguage: source,
              targetLanguage: target,
            );
            try {
              return await translator.translateText(text);
            } finally {
              await translator.close();
            }
          }
        } on Exception catch (e) {
          log('ML Kit translation failed, falling back to server: $e');
        }
      }
    }

    // Fall back to the server endpoint.
    return _translateViaServer(text: text, targetLanguage: targetLanguage);
  }

  /// Detects the source [TranslateLanguage] of [text] using ML Kit, or returns
  /// `null` if detection is unavailable.
  Future<TranslateLanguage?> _detectSource(String text) async {
    final identifier = LanguageIdentifier(confidenceThreshold: 0.5);
    try {
      final code = await identifier.identifyLanguage(text);
      if (code == 'und') return null;
      return BCP47Code.fromRawValue(code);
    } finally {
      await identifier.close();
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
