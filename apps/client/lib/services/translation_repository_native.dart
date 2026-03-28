import 'dart:developer';
import 'dart:io';

import 'package:client/services/translation_repository_base.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

/// Whether the current platform supports Google ML Kit (iOS & Android only).
final bool _mlKitSupported = Platform.isIOS || Platform.isAndroid;

/// Translation repository for native platforms.
///
/// [translate] uses Google ML Kit for on-device translation on iOS/Android.
/// Returns `null` on desktop or when on-device translation fails.
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
}
