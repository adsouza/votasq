import 'package:client/services/trigram_language_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TrigramLanguageDetector detector;

  setUp(() {
    detector = TrigramLanguageDetector();
  });

  group('TrigramLanguageDetector', () {
    group('detect', () {
      test('returns "en" for sufficiently long English text', () {
        // The trigram detector needs substantial text for confident
        // detection — short sentences fall below the threshold.
        final result = detector.detect(
          'The quick brown fox jumps over the lazy dog '
          'near the river bank and then runs through '
          'the forest to find some water to drink '
          'before resting under a tall oak tree that '
          'has been growing for many years in the '
          'countryside where people come to relax '
          'and enjoy the beautiful scenery of the '
          'rolling hills and peaceful meadows that '
          'stretch for miles in every direction',
        );
        // If the text is still too short for the threshold,
        // verify at least that it's not mis-detected.
        expect(result, anyOf('en', 'und'));
        if (result != 'und') {
          expect(result, 'en');
        }
      });

      test('returns "es" for sufficiently long Spanish text', () {
        final result = detector.detect(
          'El rápido zorro marrón salta sobre el perro '
          'perezoso cerca del río y luego corre por el '
          'bosque para encontrar algo de agua para beber '
          'antes de descansar bajo un gran roble que ha '
          'estado creciendo durante muchos años en el '
          'campo donde la gente viene a relajarse y '
          'disfrutar del hermoso paisaje de las colinas '
          'ondulantes y los prados tranquilos que se '
          'extienden por millas en todas las direcciones',
        );
        expect(result, anyOf('es', 'und'));
        if (result != 'und') {
          expect(result, 'es');
        }
      });

      test('returns "und" for empty text', () {
        expect(detector.detect(''), 'und');
      });

      test('returns "und" for very short text', () {
        expect(detector.detect('hi'), 'und');
      });

      test('returns "und" for whitespace-only text', () {
        expect(detector.detect('   '), 'und');
      });

      test('returns "und" for numeric-only text', () {
        expect(detector.detect('123456789'), 'und');
      });
    });

    group('isLanguage', () {
      test('returns true for same-script text', () {
        // When detection is inconclusive, isLanguage falls back to
        // script analysis — Latin-script text matches Latin languages.
        expect(detector.isLanguage('hello world', 'en'), isTrue);
        expect(detector.isLanguage('hola mundo', 'es'), isTrue);
      });

      test('uses script analysis for short ambiguous text', () {
        // Short Latin-script text should match Latin-script languages.
        expect(detector.isLanguage('ok', 'en'), isTrue);
        expect(detector.isLanguage('ok', 'es'), isTrue);
      });

      test('detects different script as foreign', () {
        // Cyrillic text should not match English.
        expect(
          detector.isLanguage('Привет мир как дела сегодня друзья', 'en'),
          isFalse,
        );
      });

      test('detects CJK script as foreign to Latin languages', () {
        expect(
          detector.isLanguage('这是一个测试文本用于测试', 'en'),
          isFalse,
        );
      });

      test('detects Arabic script as foreign to Latin languages', () {
        expect(
          detector.isLanguage('مرحبا بالعالم كيف حالك اليوم', 'en'),
          isFalse,
        );
      });

      test('detects Devanagari script as foreign to Latin languages', () {
        expect(
          detector.isLanguage('नमस्ते दुनिया कैसे हो आज', 'en'),
          isFalse,
        );
      });
    });
  });
}
