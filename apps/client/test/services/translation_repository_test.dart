import 'dart:convert';

import 'package:client/services/translation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  late http.Client httpClient;
  late TranslationRepository repo;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    httpClient = _MockHttpClient();
    repo = TranslationRepository(
      serverBaseUrl: 'https://example.com',
      client: httpClient,
    );
  });

  group('TranslationRepository', () {
    group('translate', () {
      test('returns null on non-mobile platforms', () async {
        // In test (desktop), ML Kit is unsupported → returns null.
        final result = await repo.translate(
          text: 'hola mundo',
          targetLanguage: 'en',
          sourceLanguage: 'es',
        );
        expect(result, isNull);
      });
    });

    group('translateProblem', () {
      test('returns TranslatedProblem on success', () async {
        when(() => httpClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer(
          (_) async => http.Response(
            jsonEncode({'description': 'hello world'}),
            200,
          ),
        );

        final result = await repo.translateProblem(
          problemId: 'p1',
          targetLanguage: 'es',
        );

        expect(result, isA<TranslatedProblem>());
        expect(result.description, 'hello world');
        verify(
          () => httpClient.get(
            Uri.parse(
              'https://example.com/problems/p1/translations/es',
            ),
            headers: any(named: 'headers'),
          ),
        ).called(1);
      });

      test('throws on non-200 response', () async {
        when(() => httpClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('', 500));

        expect(
          () => repo.translateProblem(
            problemId: 'p1',
            targetLanguage: 'es',
          ),
          throwsException,
        );
      });
    });

    group('detectLanguageViaServer', () {
      test('returns detected language code', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'detectedLanguage': 'es'}),
            200,
          ),
        );

        final result = await repo.detectLanguageViaServer(
          'hola mundo',
        );

        expect(result, 'es');
        verify(
          () => httpClient.post(
            Uri.parse('https://example.com/detect'),
            headers: any(named: 'headers'),
            body: jsonEncode({'text': 'hola mundo'}),
          ),
        ).called(1);
      });

      test('throws on non-200 response', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', 400));

        expect(
          () => repo.detectLanguageViaServer('test'),
          throwsException,
        );
      });
    });
  });
}
