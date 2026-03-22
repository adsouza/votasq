import 'package:client/problems/widgets/problem_translation.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockTranslationRepository extends Mock
    implements TranslationRepository {}

void main() {
  late FirestoreRepository firestoreRepo;
  late TranslationRepository translationRepo;

  setUpAll(() {
    registerFallbackValue(const TranslatedProblem(description: ''));
  });

  setUp(() {
    firestoreRepo = _MockFirestoreRepository();
    translationRepo = _MockTranslationRepository();
  });

  Widget buildSubject({
    String problemId = 'p1',
    String? lang,
    String originalDescription = 'hola mundo amigos',
    Locale locale = const Locale('en'),
  }) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<FirestoreRepository>.value(value: firestoreRepo),
        RepositoryProvider<TranslationRepository>.value(
          value: translationRepo,
        ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('es')],
        localizationsDelegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: ProblemTranslation(
            problemId: problemId,
            lang: lang,
            originalDescription: originalDescription,
            child: TranslatedField(
              originalDescription,
              fieldSelector: (tp) => tp.description,
            ),
          ),
        ),
      ),
    );
  }

  group('TranslatedField', () {
    testWidgets('shows plain text when lang is null', (tester) async {
      await tester.pumpWidget(
        buildSubject(originalDescription: 'hello world friends'),
      );
      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsNothing);
    });

    testWidgets('shows plain text when lang matches locale', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          lang: 'en',
          originalDescription: 'hello world friends',
        ),
      );
      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsNothing);
    });

    testWidgets('shows translate icon when lang differs', (tester) async {
      await tester.pumpWidget(
        buildSubject(lang: 'es'),
      );
      // Text is inside a Text.rich with spans; use textContaining.
      expect(
        find.textContaining('hola mundo amigos'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });
  });

  group('ProblemTranslation', () {
    testWidgets('uses Firestore cache on hit', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));

      // Tap translate icon.
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      // Should show translated text.
      expect(find.text('hello world friends'), findsOneWidget);
      // Original should be struck through (still visible).
      expect(find.text('hola mundo amigos'), findsOneWidget);

      // Should NOT have called on-device or server translation.
      verifyNever(
        () => translationRepo.translate(
          text: any(named: 'text'),
          targetLanguage: any(named: 'targetLanguage'),
          sourceLanguage: any(named: 'sourceLanguage'),
        ),
      );
      verifyNever(
        () => translationRepo.translateProblem(
          problemId: any(named: 'problemId'),
          targetLanguage: any(named: 'targetLanguage'),
        ),
      );
    });

    testWidgets('falls through to on-device when cache misses', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async => null);

      when(
        () => translationRepo.translate(
          text: any(named: 'text'),
          targetLanguage: any(named: 'targetLanguage'),
          sourceLanguage: any(named: 'sourceLanguage'),
        ),
      ).thenAnswer((_) async => 'hello world friends');

      when(
        () => firestoreRepo.saveTranslation(any(), any(), any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('hello world friends'), findsOneWidget);

      // Verify on-device was tried.
      verify(
        () => translationRepo.translate(
          text: 'hola mundo amigos',
          targetLanguage: 'en',
          sourceLanguage: 'es',
        ),
      ).called(1);

      // Verify result was cached to Firestore.
      verify(
        () => firestoreRepo.saveTranslation(
          'p1',
          'en',
          any(
            that: isA<TranslatedProblem>().having(
              (tp) => tp.description,
              'description',
              'hello world friends',
            ),
          ),
        ),
      ).called(1);

      // Server should NOT have been called.
      verifyNever(
        () => translationRepo.translateProblem(
          problemId: any(named: 'problemId'),
          targetLanguage: any(named: 'targetLanguage'),
        ),
      );
    });

    testWidgets('falls through to server when on-device returns null', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async => null);

      when(
        () => translationRepo.translate(
          text: any(named: 'text'),
          targetLanguage: any(named: 'targetLanguage'),
          sourceLanguage: any(named: 'sourceLanguage'),
        ),
      ).thenAnswer((_) async => null);

      when(
        () => translationRepo.translateProblem(
          problemId: any(named: 'problemId'),
          targetLanguage: any(named: 'targetLanguage'),
        ),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('hello world friends'), findsOneWidget);

      // Verify server was called with correct args.
      verify(
        () => translationRepo.translateProblem(
          problemId: 'p1',
          targetLanguage: 'en',
        ),
      ).called(1);
    });

    testWidgets('shows spinner while translating', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async {
          // Delay to keep spinner visible.
          await Future<void>.delayed(const Duration(seconds: 1));
          return const TranslatedProblem(description: 'translated');
        },
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('resets when problemId changes', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async => const TranslatedProblem(description: 'cached translation'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('cached translation'), findsOneWidget);

      // Re-pump with a different problemId.
      await tester.pumpWidget(buildSubject(lang: 'es', problemId: 'p2'));
      await tester.pumpAndSettle();

      // Translation should be reset — translate icon reappears.
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });
  });
}
