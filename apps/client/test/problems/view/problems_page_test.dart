import 'package:bloc_test/bloc_test.dart';
import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/problems/view/problems_page.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockProblemsCubit extends MockCubit<ProblemsState>
    implements ProblemsCubit {}

class _MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _MockGeoscopeCubit extends MockCubit<GeoscopeState>
    implements GeoscopeCubit {}

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockFeedbackRepository extends Mock implements FeedbackRepository {}

class _MockLanguageDetectionService extends Mock
    implements LanguageDetectionService {}

class _MockTranslationRepository extends Mock
    implements TranslationRepository {}

Problem _problem({
  String id = '1',
  String description = 'first test problem',
  String goal = '',
  String ownerId = 'owner1',
  String geoscope = '/',
  int votes = 3,
  List<String> complaints = const [],
}) {
  final now = DateTime.utc(2024);
  return Problem(
    id: id,
    description: description,
    goal: goal,
    ownerId: ownerId,
    geoscope: geoscope,
    votes: votes,
    complaints: complaints,
    createdAt: now,
    lastUpdatedAt: now,
  );
}

void main() {
  late ProblemsCubit problemsCubit;
  late AuthCubit authCubit;
  late GeoscopeCubit geoscopeCubit;
  late FirestoreRepository firestoreRepo;
  late FeedbackRepository feedbackRepo;
  late LanguageDetectionService languageDetectionService;
  late TranslationRepository translationRepo;

  setUp(() {
    problemsCubit = _MockProblemsCubit();
    authCubit = _MockAuthCubit();
    geoscopeCubit = _MockGeoscopeCubit();
    firestoreRepo = _MockFirestoreRepository();
    feedbackRepo = _MockFeedbackRepository();
    languageDetectionService = _MockLanguageDetectionService();
    translationRepo = _MockTranslationRepository();

    // Default states.
    when(() => problemsCubit.state).thenReturn(const ProblemsState());
    when(() => authCubit.state).thenReturn(const AuthState());
    when(() => geoscopeCubit.state).thenReturn(const GeoscopeState());
    when(
      () => languageDetectionService.needsTranslation(
        text: any(named: 'text'),
        userLanguage: any(named: 'userLanguage'),
      ),
    ).thenAnswer((_) async => false);
    when(() => translationRepo.canTranslateOnDevice).thenReturn(false);
  });

  Widget buildSubject() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProblemsCubit>.value(value: problemsCubit),
        BlocProvider<AuthCubit>.value(value: authCubit),
        BlocProvider<GeoscopeCubit>.value(value: geoscopeCubit),
        BlocProvider<AutoTranslateCubit>(
          create: (_) => AutoTranslateCubit(),
        ),
      ],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<FirestoreRepository>.value(value: firestoreRepo),
          RepositoryProvider<FeedbackRepository>.value(value: feedbackRepo),
          RepositoryProvider<LanguageDetectionService>.value(
            value: languageDetectionService,
          ),
          RepositoryProvider<TranslationRepository>.value(
            value: translationRepo,
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Test ProblemsView directly — ProblemsPage creates its own cubit.
          home: Scaffold(body: ProblemsView()),
        ),
      ),
    );
  }

  group('ProblemsView', () {
    testWidgets('shows add-problem row when authenticated', (tester) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('hides add-problem row when not authenticated', (tester) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.unauthenticated),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('renders problem descriptions in list', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(description: 'fix the potholes'),
            _problem(id: '2', description: 'plant more trees'),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.text('fix the potholes'), findsOneWidget);
      expect(find.text('plant more trees'), findsOneWidget);
    });

    testWidgets('shows edit button for owned problems', (tester) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'owner1'),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem()],
        ),
      );
      await tester.pumpWidget(buildSubject());
      // Edit button renders as 🖊️.
      expect(find.text('🖊️'), findsOneWidget);
    });

    testWidgets('shows flag button for non-owned problems', (tester) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'other'),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem()],
        ),
      );
      await tester.pumpWidget(buildSubject());
      // Flag button renders as 🙈.
      expect(find.text('🙈'), findsOneWidget);
    });

    testWidgets('hides flagged problems', (tester) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(
              description: 'visible problem here',
            ),
            _problem(
              id: '2',
              description: 'flagged problem here',
              complaints: ['user1'],
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.text('visible problem here'), findsOneWidget);
      expect(find.text('flagged problem here'), findsNothing);
    });

    testWidgets('geoscope chip shown for non-global problems', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(geoscope: 'us/nyc')],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.text('nyc'), findsOneWidget);
    });

    testWidgets('geoscope chip hidden for global problems', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem()],
        ),
      );
      await tester.pumpWidget(buildSubject());
      // Only the votes chip should exist, no geoscope chip.
      final chips = tester.widgetList<Chip>(find.byType(Chip));
      expect(chips, hasLength(1));
    });

    testWidgets('votes chip shows vote count', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(votes: 42)],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('vote chip is ActionChip when authenticated', (
      tester,
    ) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(ownerId: 'other', votes: 7)],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.byType(ActionChip), findsOneWidget);
      expect(find.byIcon(Icons.arrow_circle_up_rounded), findsOneWidget);
    });

    testWidgets('vote chip is plain Chip when not authenticated', (
      tester,
    ) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.unauthenticated),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem()],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.byType(ActionChip), findsNothing);
      expect(find.byType(Chip), findsOneWidget);
    });

    testWidgets('tapping vote chip calls cubit.vote', (tester) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(id: 'p1', ownerId: 'other', votes: 5)],
        ),
      );
      when(
        () => problemsCubit.vote(
          problemId: any(named: 'problemId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.byType(ActionChip));
      await tester.pump();
      verify(
        () => problemsCubit.vote(problemId: 'p1', userId: 'user1'),
      ).called(1);
    });

    testWidgets('loading indicator shown during initial load', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.loading),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hamburger menu hides owned filter when not authenticated', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      // Only "with goals" checkbox visible, not "my problems".
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('hamburger menu shows owned filter when authenticated', (
      tester,
    ) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      // Both checkboxes visible.
      expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(2));
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('goal field hidden until description has 3 words', (
      tester,
    ) async {
      when(() => authCubit.state).thenReturn(
        const AuthState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());

      // Only the description field is visible initially.
      expect(find.byType(TextField), findsOneWidget);

      // Type fewer than 3 words and focus — goal stays hidden.
      await tester.enterText(find.byType(TextField), 'two words');
      await tester.pump(); // onChanged
      await tester.pump(); // postFrameCallback
      expect(find.byType(TextField), findsOneWidget);

      // Type 3+ words — goal field appears.
      await tester.enterText(find.byType(TextField), 'now three words here');
      await tester.pump(); // onChanged
      await tester.pump(); // postFrameCallback
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('shows goal text for problems with non-empty goal', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(
              description: 'traffic is terrible',
              goal: 'reduce commute times',
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.text('traffic is terrible'), findsOneWidget);
      expect(find.text('reduce commute times'), findsOneWidget);
    });

    testWidgets('hides goal text for problems with empty goal', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(description: 'traffic is terrible')],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.text('traffic is terrible'), findsOneWidget);
      // No extra text widget for the empty goal.
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(
        textWidgets.where((t) => t.data == '').length,
        isZero,
      );
    });
  });
}
