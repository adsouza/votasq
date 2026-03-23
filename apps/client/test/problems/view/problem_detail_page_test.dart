import 'package:bloc_test/bloc_test.dart';
import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/view/problem_detail_page.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _MockGeoscopeCubit extends MockCubit<GeoscopeState>
    implements GeoscopeCubit {}

class _MockLanguageDetectionService extends Mock
    implements LanguageDetectionService {}

class _MockTranslationRepository extends Mock
    implements TranslationRepository {}

Problem _problem({
  String id = 'test-id',
  String description = 'test problem description',
  String goal = '',
  String ownerId = 'owner1',
  String geoscope = '/',
  int votes = 5,
}) {
  final now = DateTime.utc(2024);
  return Problem(
    id: id,
    description: description,
    goal: goal,
    ownerId: ownerId,
    geoscope: geoscope,
    votes: votes,
    createdAt: now,
    lastUpdatedAt: now,
  );
}

void main() {
  late FirestoreRepository repo;
  late AuthCubit authCubit;
  late GeoscopeCubit geoscopeCubit;
  late LanguageDetectionService languageDetectionService;
  late TranslationRepository translationRepo;

  setUpAll(() {
    registerFallbackValue(_problem());
  });

  setUp(() {
    repo = _MockFirestoreRepository();
    authCubit = _MockAuthCubit();
    geoscopeCubit = _MockGeoscopeCubit();
    languageDetectionService = _MockLanguageDetectionService();
    translationRepo = _MockTranslationRepository();

    when(() => authCubit.state).thenReturn(const AuthState());
    when(() => geoscopeCubit.state).thenReturn(const GeoscopeState());
    when(
      () => languageDetectionService.needsTranslation(
        text: any(named: 'text'),
        userLanguage: any(named: 'userLanguage'),
      ),
    ).thenAnswer((_) async => false);
  });

  Widget buildSubject({
    String problemId = 'test-id',
  }) {
    final router = GoRouter(
      initialLocation: '/problems/$problemId',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
          routes: [
            GoRoute(
              path: 'problems/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return ProblemDetailPage(problemId: id);
              },
            ),
          ],
        ),
      ],
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: authCubit),
        BlocProvider<GeoscopeCubit>.value(value: geoscopeCubit),
      ],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<FirestoreRepository>.value(value: repo),
          RepositoryProvider<LanguageDetectionService>.value(
            value: languageDetectionService,
          ),
          RepositoryProvider<TranslationRepository>.value(
            value: translationRepo,
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
  }

  group('ProblemDetailPage', () {
    testWidgets('shows loading indicator while fetching', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      await tester.pumpWidget(buildSubject());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error when problem not found', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => null);
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Problem not found'), findsOneWidget);
    });

    testWidgets('shows read-only view for non-owner', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('test problem description'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // No text field in read-only view.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('shows editable view for owner', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('back button navigates to home', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => null);
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('save calls updateProblem and navigates home', (tester) async {
      final problem = _problem();
      when(() => repo.getProblem(any())).thenAnswer((_) async => problem);
      when(
        () => repo.updateProblem(
          any(),
          userLanguage: any(named: 'userLanguage'),
        ),
      ).thenAnswer((_) async {});
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        ),
      );

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Modify the description.
      await tester.enterText(
        find.byType(TextField).first,
        'updated problem description',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(
        () => repo.updateProblem(
          any(),
          userLanguage: any(named: 'userLanguage'),
        ),
      ).called(1);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('shows goal in read-only view when non-empty', (
      tester,
    ) async {
      when(
        () => repo.getProblem(any()),
      ).thenAnswer(
        (_) async => _problem(goal: 'reduce commute times'),
      );
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('reduce commute times'), findsOneWidget);
    });

    testWidgets('hides goal in read-only view when empty', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('test problem description'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
