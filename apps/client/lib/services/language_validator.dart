import 'dart:developer';

import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:shared/shared.dart';

/// Thrown when the description and goal are detected as different languages.
class LanguageMismatchException implements Exception {
  const LanguageMismatchException({
    required this.descriptionLang,
    required this.goalLang,
  });

  final String descriptionLang;
  final String goalLang;
}

/// Result of language detection. When the server fallback is used, English
/// translations come back for free and can be cached.
typedef DetectionResult = ({
  String lang,
  TranslatedProblem? englishTranslation,
});

/// 3-tier language detection with cross-field validation.
///
/// Detection tiers (tried in order for each field):
/// 1. On-device: `needsTranslation` + `detectLanguage` via ML Kit / trigrams
/// 2. Server: `translateToEnglish` (gives detection + English translation)
/// 3. Fallback: `'und'` (undetermined)
class LanguageValidator {
  LanguageValidator({
    required LanguageDetectionService langService,
    TranslationRepository? translationRepo,
  }) : _langService = langService,
       _translationRepo = translationRepo;

  final LanguageDetectionService _langService;
  final TranslationRepository? _translationRepo;

  /// Detect + validate language for description and optional goal.
  /// Throws [LanguageMismatchException] if the two fields differ.
  Future<DetectionResult> detectAndValidateLang(
    String description,
    String goal,
    String userLanguage,
  ) async {
    final descForeign = await _langService.needsTranslation(
      text: description,
      userLanguage: userLanguage,
    );

    // No goal — single-field detection only.
    if (goal.isEmpty) {
      return _detectSingleField(description, descForeign, userLanguage);
    }

    final goalForeign = await _langService.needsTranslation(
      text: goal,
      userLanguage: userLanguage,
    );

    // Both match the user's language.
    if (!descForeign && !goalForeign) {
      return (lang: userLanguage, englishTranslation: null);
    }

    // One matches, one doesn't — mismatch.
    if (descForeign != goalForeign) {
      final descLang = descForeign
          ? await _langService.detectLanguage(description) ?? '?'
          : userLanguage;
      final goalLang = goalForeign
          ? await _langService.detectLanguage(goal) ?? '?'
          : userLanguage;
      throw LanguageMismatchException(
        descriptionLang: descLang,
        goalLang: goalLang,
      );
    }

    // Both foreign — detect each on-device and check they agree.
    final descLang = await _langService.detectLanguage(description);
    final goalLang = await _langService.detectLanguage(goal);

    if (descLang != null && goalLang != null && descLang != goalLang) {
      throw LanguageMismatchException(
        descriptionLang: descLang,
        goalLang: goalLang,
      );
    }

    // Use whichever was detected on-device.
    final detected = descLang ?? goalLang;
    if (detected != null) {
      return (lang: detected, englishTranslation: null);
    }

    // Fall back to server: translate both fields to English.
    return _serverFallbackBothFields(description, goal);
  }

  /// Single-field language detection (no cross-field validation needed).
  Future<DetectionResult> _detectSingleField(
    String text,
    bool isForeign,
    String userLanguage,
  ) async {
    if (!isForeign) return (lang: userLanguage, englishTranslation: null);

    final detected = await _langService.detectLanguage(text);
    if (detected != null) return (lang: detected, englishTranslation: null);

    final repo = _translationRepo;
    if (repo != null) {
      try {
        final result = await repo.translateToEnglish(text);
        return (
          lang: result.detectedLanguage,
          englishTranslation: TranslatedProblem(
            description: result.translation,
          ),
        );
      } on Exception catch (e) {
        log('Server language detection failed: $e');
      }
    }

    return (lang: 'und', englishTranslation: null);
  }

  /// Server fallback for two foreign fields.
  Future<DetectionResult> _serverFallbackBothFields(
    String description,
    String goal,
  ) async {
    final repo = _translationRepo;
    if (repo != null) {
      try {
        final descResult = await repo.translateToEnglish(description);
        final goalResult = await repo.translateToEnglish(goal);
        if (descResult.detectedLanguage != goalResult.detectedLanguage) {
          throw LanguageMismatchException(
            descriptionLang: descResult.detectedLanguage,
            goalLang: goalResult.detectedLanguage,
          );
        }
        return (
          lang: descResult.detectedLanguage,
          englishTranslation: TranslatedProblem(
            description: descResult.translation,
            goal: goalResult.translation,
          ),
        );
      } on LanguageMismatchException {
        rethrow;
      } on Exception catch (e) {
        log('Server language detection failed: $e');
      }
    }

    return (lang: 'und', englishTranslation: null);
  }
}
