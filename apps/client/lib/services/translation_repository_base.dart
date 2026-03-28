import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Shared HTTP methods used by both native and web `TranslationRepository`
/// implementations. Platform-specific code (on-device translation) stays in
/// the respective files.
mixin TranslationRepositoryBase {
  String get baseUrl;
  http.Client get client;

  /// Fetches the translation for a problem, creating it via Cloud Translate
  /// on the server if not yet cached.
  Future<TranslatedProblem> translateProblem({
    required String problemId,
    required String targetLanguage,
  }) async {
    final response = await client.get(
      Uri.parse(
        '$baseUrl/api/problems/$problemId/translations/$targetLanguage',
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Problem translation failed: ${response.statusCode}');
    }
    return TranslatedProblem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Translates [text] to English via the server, returning both the detected
  /// source language and the English translation. This is used as a fallback
  /// when on-device detection fails — translating costs the same as pure
  /// detection but gives us a cacheable English translation for free.
  Future<({String detectedLanguage, String translation})> translateToEnglish(
    String text,
  ) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/translate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode != 200) {
      throw Exception('Language detection failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      detectedLanguage: body['detectedLanguage'] as String,
      translation: body['translation'] as String,
    );
  }
}
