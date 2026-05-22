import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/problem_translation.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

import '../../helpers/helpers.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockTranslationRepository extends Mock
    implements TranslationRepository {}

void main() {
  late FirestoreRepository firestoreRepo;
  late TranslationRepository translationRepo;
  late MockSharedPreferencesWithCache mockPrefs;

  setUpAll(() {
    registerFallbackValue(const TranslatedProblem(description: ''));
  });

  setUp(() {
    mockPrefs = createMockSharedPreferences();
    firestoreRepo = _MockFirestoreRepository();
    translationRepo = _MockTranslationRepository();
  });

  Widget buildSubject({
    String problemId = 'p1',
    String? lang,
    String originalDescription = 'hola mundo amigos',
    String originalGoal = '',
    Locale locale = const Locale('en'),
    bool autoTranslate = false,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AutoTranslateCubit>(
          create: (_) => AutoTranslateCubit(
            initial: autoTranslate,
            prefsForTesting: mockPrefs,
          ),
        ),
      ],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<FirestoreRepository>.value(value: firestoreRepo),
          RepositoryProvider<TranslationRepository>.value(
            value: translationRepo,
          ),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ProblemTranslation(
              problemId: problemId,
              lang: lang,
              originalDescription: originalDescription,
              originalGoal: originalGoal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TranslatedField(
                    originalDescription,
                    fieldSelector: (tp) => tp.description,
                  ),
                  if (originalGoal.isNotEmpty)
                    TranslatedField(
                      originalGoal,
                      fieldSelector: (tp) => tp.goal,
                    ),
                  const ProblemTranslateButton(),
                ],
              ),
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

    testWidgets('shows translate icon when lang differs and cache misses', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async => null);

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle(); // Complete auto cache check.

      expect(find.text('hola mundo amigos'), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });
  });

  group('Cache probe', () {
    testWidgets('automatically shows cached translation without tap', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle();

      // Translation appears without any tap; original is hidden.
      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.text('hola mundo amigos'), findsNothing);
      // Toggle button stays visible (pressed in) so the user can flip back.
      expect(find.byIcon(Icons.translate), findsOneWidget);

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

    testWidgets('shows spinner during cache probe', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return null;
      });

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pump(); // Trigger post-frame callback.

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsNothing);

      await tester.pumpAndSettle();
    });
  });

  group('ProblemTranslation', () {
    testWidgets('falls through to on-device when cache misses', (
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
      ).thenAnswer((_) async => 'hello world friends');

      when(
        () => firestoreRepo.saveTranslation(any(), any(), any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle(); // Complete auto cache check.

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
      await tester.pumpAndSettle(); // Complete auto cache check.

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
      // Auto cache check returns null quickly; _translate() re-check is slow.
      var callCount = 0;
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount <= 1) return null; // Auto cache check.
        await Future<void>.delayed(const Duration(seconds: 1));
        return const TranslatedProblem(description: 'translated');
      });

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle(); // Complete auto cache check.

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('resets when problemId changes', (tester) async {
      when(
        () => firestoreRepo.getTranslation('p1', any()),
      ).thenAnswer(
        (_) async => const TranslatedProblem(description: 'cached translation'),
      );
      when(
        () => firestoreRepo.getTranslation('p2', any()),
      ).thenAnswer((_) async => null);

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle();

      expect(find.text('cached translation'), findsOneWidget);

      // Re-pump with a different problemId.
      await tester.pumpWidget(buildSubject(lang: 'es', problemId: 'p2'));
      await tester.pumpAndSettle();

      // Translation should be reset — translate icon reappears.
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });
  });

  group('Auto-translate', () {
    testWidgets('auto-translates without tap when enabled', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(
        buildSubject(lang: 'es', autoTranslate: true),
      );
      await tester.pumpAndSettle();

      // Translation should appear without any tap; original is hidden.
      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.text('hola mundo amigos'), findsNothing);
      // Toggle stays visible so the user can switch back to the original.
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });

    testWidgets('shows spinner (not icon) when auto-translate is enabled', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return const TranslatedProblem(description: 'translated');
      });

      await tester.pumpWidget(
        buildSubject(lang: 'es', autoTranslate: true),
      );
      await tester.pump();

      // Spinner should appear, not the translate icon.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('translate icon appears when auto-translate is disabled', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async => null);

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle(); // Complete auto cache check.

      expect(find.byIcon(Icons.translate), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Goal translation', () {
    testWidgets('on-device translates both description and goal', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer((_) async => null);

      var translateCallCount = 0;
      when(
        () => translationRepo.translate(
          text: any(named: 'text'),
          targetLanguage: any(named: 'targetLanguage'),
          sourceLanguage: any(named: 'sourceLanguage'),
        ),
      ).thenAnswer((invocation) async {
        translateCallCount++;
        final text = invocation.namedArguments[#text] as String;
        return text == 'hola mundo amigos'
            ? 'hello world friends'
            : 'less traffic';
      });

      when(
        () => firestoreRepo.saveTranslation(any(), any(), any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        buildSubject(
          lang: 'es',
          originalGoal: 'menos tráfico',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      // Both translations should appear.
      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.text('less traffic'), findsOneWidget);
      // Originals should be hidden.
      expect(find.text('hola mundo amigos'), findsNothing);
      expect(find.text('menos tráfico'), findsNothing);

      // translate() should have been called twice: once for description,
      // once for goal.
      expect(translateCallCount, 2);
    });

    testWidgets('skips goal translation when goal is empty', (tester) async {
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
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      // translate() should have been called only once (for description).
      verify(
        () => translationRepo.translate(
          text: any(named: 'text'),
          targetLanguage: any(named: 'targetLanguage'),
          sourceLanguage: any(named: 'sourceLanguage'),
        ),
      ).called(1);
    });
  });

  group('Show-original toggle', () {
    testWidgets('clicking toggle swaps translation for original', (
      tester,
    ) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle();

      // Starts on the translation side.
      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.text('hola mundo amigos'), findsNothing);

      // Tap the toggle — should flip to showing the original.
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('hola mundo amigos'), findsOneWidget);
      expect(find.text('hello world friends'), findsNothing);
      // Toggle stays visible so user can flip back.
      expect(find.byIcon(Icons.translate), findsOneWidget);

      // Tap again — back to the translation.
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('hello world friends'), findsOneWidget);
      expect(find.text('hola mundo amigos'), findsNothing);
    });

    testWidgets('tooltip text flips with the toggle state', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Pressed-in: the translation is shown, so tooltip offers original.
      expect(
        find.byTooltip(l10n.showOriginalLanguageTooltip),
        findsOneWidget,
      );
      expect(
        find.byTooltip(l10n.showTranslationTooltip),
        findsNothing,
      );

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      // Pressed-out: now offers to switch back to the translation.
      expect(
        find.byTooltip(l10n.showTranslationTooltip),
        findsOneWidget,
      );
      expect(
        find.byTooltip(l10n.showOriginalLanguageTooltip),
        findsNothing,
      );
    });

    testWidgets('translated text is rendered in italics', (tester) async {
      when(
        () => firestoreRepo.getTranslation(any(), any()),
      ).thenAnswer(
        (_) async =>
            const TranslatedProblem(description: 'hello world friends'),
      );

      await tester.pumpWidget(buildSubject(lang: 'es'));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('hello world friends'));
      expect(textWidget.style?.fontStyle, FontStyle.italic);
    });
  });
}
