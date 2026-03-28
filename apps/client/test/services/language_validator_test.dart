import 'package:client/services/language_detection_service.dart';
import 'package:client/services/language_validator.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Fake [LanguageDetectionService] that returns pre-configured values.
class _FakeLangService implements LanguageDetectionService {
  _FakeLangService({
    this.needsTranslationResults = const {},
    this.detectLanguageResults = const {},
  });

  /// Map from text → whether it needs translation.
  final Map<String, bool> needsTranslationResults;

  /// Map from text → detected language code (null = inconclusive).
  final Map<String, String?> detectLanguageResults;

  @override
  Future<bool> needsTranslation({
    required String text,
    required String userLanguage,
  }) async => needsTranslationResults[text] ?? false;

  @override
  Future<String?> detectLanguage(String text) async =>
      detectLanguageResults[text];

  @override
  Future<void> dispose() async {}
}

/// Fake [TranslationRepository] that returns pre-configured translations.
class _FakeTranslationRepo implements TranslationRepository {
  _FakeTranslationRepo({this.translations = const {}});

  /// Map from text → (detectedLanguage, englishTranslation).
  final Map<String, ({String detectedLanguage, String translation})>
  translations;

  @override
  String get baseUrl => '';
  @override
  http.Client get client => http.Client();

  @override
  Future<({String detectedLanguage, String translation})> translateToEnglish(
    String text,
  ) async {
    final result = translations[text];
    if (result == null) throw Exception('No translation for "$text"');
    return result;
  }

  @override
  bool get canTranslateOnDevice => false;

  @override
  Future<String?> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async => null;

  @override
  Future<TranslatedProblem> translateProblem({
    required String problemId,
    required String targetLanguage,
  }) async => throw UnimplementedError();
}

void main() {
  group('LanguageValidator', () {
    group('both fields match user language', () {
      test('returns userLanguage with no translation', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(),
        );
        final result = await validator.detectAndValidateLang(
          'hello world',
          'some goal',
          'en',
        );
        expect(result.lang, 'en');
        expect(result.englishTranslation, isNull);
      });
    });

    group('goal empty delegates to single-field', () {
      test('returns userLanguage when not foreign', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(),
        );
        final result = await validator.detectAndValidateLang(
          'hello world',
          '',
          'en',
        );
        expect(result.lang, 'en');
        expect(result.englishTranslation, isNull);
      });

      test('detects on-device when foreign', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {'hola mundo': true},
            detectLanguageResults: {'hola mundo': 'es'},
          ),
        );
        final result = await validator.detectAndValidateLang(
          'hola mundo',
          '',
          'en',
        );
        expect(result.lang, 'es');
        expect(result.englishTranslation, isNull);
      });

      test('falls back to server when on-device fails', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {'hola mundo': true},
            detectLanguageResults: {'hola mundo': null},
          ),
          translationRepo: _FakeTranslationRepo(
            translations: {
              'hola mundo': (
                detectedLanguage: 'es',
                translation: 'hello world',
              ),
            },
          ),
        );
        final result = await validator.detectAndValidateLang(
          'hola mundo',
          '',
          'en',
        );
        expect(result.lang, 'es');
        expect(result.englishTranslation, isNotNull);
        expect(result.englishTranslation!.description, 'hello world');
      });

      test('returns und when all tiers fail', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {'hola mundo': true},
            detectLanguageResults: {'hola mundo': null},
          ),
        );
        final result = await validator.detectAndValidateLang(
          'hola mundo',
          '',
          'en',
        );
        expect(result.lang, 'und');
      });
    });

    group('one foreign one not throws mismatch', () {
      test('throws LanguageMismatchException', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {
              'hola mundo': true,
              'my goal': false,
            },
            detectLanguageResults: {'hola mundo': 'es'},
          ),
        );
        expect(
          () => validator.detectAndValidateLang('hola mundo', 'my goal', 'en'),
          throwsA(isA<LanguageMismatchException>()),
        );
      });
    });

    group('both foreign on-device', () {
      test('returns detected lang when both agree', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {
              'hola mundo': true,
              'mi meta': true,
            },
            detectLanguageResults: {
              'hola mundo': 'es',
              'mi meta': 'es',
            },
          ),
        );
        final result = await validator.detectAndValidateLang(
          'hola mundo',
          'mi meta',
          'en',
        );
        expect(result.lang, 'es');
        expect(result.englishTranslation, isNull);
      });

      test('throws when on-device detects different languages', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {
              'hola mundo': true,
              'bonjour le monde': true,
            },
            detectLanguageResults: {
              'hola mundo': 'es',
              'bonjour le monde': 'fr',
            },
          ),
        );
        expect(
          () => validator.detectAndValidateLang(
            'hola mundo',
            'bonjour le monde',
            'en',
          ),
          throwsA(isA<LanguageMismatchException>()),
        );
      });

      test('uses whichever field was detected when other is null', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {
              'hola mundo': true,
              'mi meta': true,
            },
            detectLanguageResults: {
              'hola mundo': 'es',
              'mi meta': null,
            },
          ),
        );
        final result = await validator.detectAndValidateLang(
          'hola mundo',
          'mi meta',
          'en',
        );
        expect(result.lang, 'es');
      });
    });

    group('server fallback for both fields', () {
      test('returns server lang + caches English when both agree', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {
              'hola mundo': true,
              'mi meta': true,
            },
            detectLanguageResults: {
              'hola mundo': null,
              'mi meta': null,
            },
          ),
          translationRepo: _FakeTranslationRepo(
            translations: {
              'hola mundo': (
                detectedLanguage: 'es',
                translation: 'hello world',
              ),
              'mi meta': (
                detectedLanguage: 'es',
                translation: 'my goal',
              ),
            },
          ),
        );
        final result = await validator.detectAndValidateLang(
          'hola mundo',
          'mi meta',
          'en',
        );
        expect(result.lang, 'es');
        expect(result.englishTranslation, isNotNull);
        expect(result.englishTranslation!.description, 'hello world');
        expect(result.englishTranslation!.goal, 'my goal');
      });

      test('throws when server detects different languages', () async {
        final validator = LanguageValidator(
          langService: _FakeLangService(
            needsTranslationResults: {
              'hola mundo': true,
              'bonjour le monde': true,
            },
            detectLanguageResults: {
              'hola mundo': null,
              'bonjour le monde': null,
            },
          ),
          translationRepo: _FakeTranslationRepo(
            translations: {
              'hola mundo': (
                detectedLanguage: 'es',
                translation: 'hello world',
              ),
              'bonjour le monde': (
                detectedLanguage: 'fr',
                translation: 'hello world',
              ),
            },
          ),
        );
        expect(
          () => validator.detectAndValidateLang(
            'hola mundo',
            'bonjour le monde',
            'en',
          ),
          throwsA(isA<LanguageMismatchException>()),
        );
      });

      test(
        'returns und when no translation repo and on-device fails',
        () async {
          final validator = LanguageValidator(
            langService: _FakeLangService(
              needsTranslationResults: {
                'hola mundo': true,
                'mi meta': true,
              },
              detectLanguageResults: {
                'hola mundo': null,
                'mi meta': null,
              },
            ),
          );
          final result = await validator.detectAndValidateLang(
            'hola mundo',
            'mi meta',
            'en',
          );
          expect(result.lang, 'und');
          expect(result.englishTranslation, isNull);
        },
      );
    });
  });
}
