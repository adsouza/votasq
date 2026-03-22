import 'dart:developer';
import 'dart:io';

import 'package:client/services/trigram_language_detector.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

/// Whether the current platform supports Google ML Kit (iOS & Android only).
final bool _mlKitSupported = Platform.isIOS || Platform.isAndroid;

/// On-device language detection using Google ML Kit (iOS & Android), falling
/// back to trigram-based detection on desktop platforms.
class LanguageDetectionService {
  LanguageDetectionService()
    : _identifier = _mlKitSupported
          ? LanguageIdentifier(confidenceThreshold: 0.5)
          : null;

  final LanguageIdentifier? _identifier;
  final _trigramDetector = TrigramLanguageDetector();

  /// Returns `true` when [text] appears to be in a different language than
  /// [userLanguage] (a BCP-47 primary subtag such as `"en"` or `"es"`).
  Future<bool> needsTranslation({
    required String text,
    required String userLanguage,
  }) async {
    // Use ML Kit on iOS/Android.
    if (_identifier != null) {
      try {
        final detected = await _identifier.identifyLanguage(text);
        if (detected == 'und') return false;
        return detected != userLanguage;
      } on Exception catch (e) {
        log('ML Kit language detection failed: $e');
      }
    }

    // Fall back to trigram detection on desktop.
    // Check whether the text matches the user's language — if not, it needs
    // translation regardless of what language it actually is.
    return !_trigramDetector.isLanguage(text, userLanguage);
  }

  /// Returns the detected BCP-47 language code for [text], or `null` if
  /// detection is inconclusive.
  Future<String?> detectLanguage(String text) async {
    if (_identifier != null) {
      try {
        final detected = await _identifier.identifyLanguage(text);
        if (detected != 'und') return detected;
      } on Exception catch (e) {
        log('ML Kit detectLanguage failed: $e');
      }
    }
    final detected = _trigramDetector.detect(text);
    return detected == 'und' ? null : detected;
  }

  /// Releases native resources held by the identifier.
  Future<void> dispose() async {
    await _identifier?.close();
  }
}
