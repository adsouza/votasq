import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Whether the current platform supports Google ML Kit (iOS & Android only).
final bool _mlKitSupported = Platform.isIOS || Platform.isAndroid;

/// Translation repository for native platforms.
///
/// [translate] uses Google ML Kit for on-device translation on iOS/Android.
/// Returns `null` on desktop or when on-device translation fails.
/// [translateProblem] fetches a cached (or freshly Cloud-Translated) result
/// from the server.
class TranslationRepository {
  TranslationRepository({required String serverBaseUrl, http.Client? client})
    : _baseUrl = serverBaseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// Whether this platform supports on-device translation.
  bool get canTranslateOnDevice => _mlKitSupported;

  /// Attempts on-device translation of [text] into [targetLanguage].
  /// Returns `null` when on-device translation is unavailable or fails.
  Future<String?> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    if (_mlKitSupported) {
      final target = BCP47Code.fromRawValue(targetLanguage);
      if (target != null) {
        try {
          final source = sourceLanguage != null
              ? BCP47Code.fromRawValue(sourceLanguage)
              : await _detectSource(text);
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
          log('ML Kit translation failed: $e');
        }
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
      Uri.parse(
        '$_baseUrl/api/problems/$problemId/translations/$targetLanguage',
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Problem translation failed: ${response.statusCode}');
    }
    return TranslatedProblem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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

  /// Detects the language of [text] via the server's Cloud Translation API.
  Future<String> detectLanguageViaServer(String text) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/detect'),
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
