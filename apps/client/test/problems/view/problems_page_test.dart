import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/notifications/notifications.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/problems/view/problems_page.dart';
import 'package:client/problems/widgets/problem_edit_tile.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:client/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';
import 'package:toastification/toastification.dart';

import '../../helpers/helpers.dart';

class _MockProblemsCubit extends MockCubit<ProblemsState>
    implements ProblemsCubit {}

class _MockUserCubit extends MockCubit<UserState> implements UserCubit {}

class _MockGeoscopeCubit extends MockCubit<GeoscopeState>
    implements GeoscopeCubit {}

class _MockNotificationsCountCubit extends MockCubit<int>
    implements NotificationsCountCubit {}

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
  DateTime? lastUpdatedAt,
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
    lastUpdatedAt: lastUpdatedAt ?? now,
  );
}

Finder _menuItem(String value) => find.byWidgetPredicate(
  (w) => w is PopupMenuItem<String> && w.value == value,
);

void main() {
  late ProblemsCubit problemsCubit;
  late UserCubit userCubit;
  late GeoscopeCubit geoscopeCubit;
  late NotificationsCountCubit notificationsCountCubit;
  late RecencyFilterCubit recencyFilterCubit;
  late FirestoreRepository firestoreRepo;
  late FeedbackRepository feedbackRepo;
  late LanguageDetectionService languageDetectionService;
  late TranslationRepository translationRepo;
  late MockSharedPreferencesWithCache mockPrefs;

  setUpAll(() {
    registerFallbackValue(_problem());
  });

  setUp(() {
    mockPrefs = createMockSharedPreferences();
    problemsCubit = _MockProblemsCubit();
    userCubit = _MockUserCubit();
    geoscopeCubit = _MockGeoscopeCubit();
    notificationsCountCubit = _MockNotificationsCountCubit();
    recencyFilterCubit = RecencyFilterCubit(prefsForTesting: mockPrefs);
    firestoreRepo = _MockFirestoreRepository();
    feedbackRepo = _MockFeedbackRepository();
    languageDetectionService = _MockLanguageDetectionService();
    translationRepo = _MockTranslationRepository();

    // Default states.
    when(() => problemsCubit.state).thenReturn(const ProblemsState());
    when(() => userCubit.state).thenReturn(const UserState());
    when(() => geoscopeCubit.state).thenReturn(const GeoscopeState());
    when(() => notificationsCountCubit.state).thenReturn(0);
    when(
      () => languageDetectionService.needsTranslation(
        text: any(named: 'text'),
        userLanguage: any(named: 'userLanguage'),
      ),
    ).thenAnswer((_) async => false);
    when(() => translationRepo.canTranslateOnDevice).thenReturn(false);
  });

  tearDown(() async {
    await recencyFilterCubit.close();
  });

  Widget buildSubject() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProblemsCubit>.value(value: problemsCubit),
        BlocProvider<UserCubit>.value(value: userCubit),
        BlocProvider<GeoscopeCubit>.value(value: geoscopeCubit),
        BlocProvider<AutoTranslateCubit>(
          create: (_) => AutoTranslateCubit(prefsForTesting: mockPrefs),
        ),
        BlocProvider<NotificationsCountCubit>.value(
          value: notificationsCountCubit,
        ),
        BlocProvider<RecencyFilterCubit>.value(value: recencyFilterCubit),
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
        child: const ToastificationWrapper(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // Test ProblemsView directly — ProblemsPage creates its own cubit.
            home: Scaffold(body: ProblemsView()),
          ),
        ),
      ),
    );
  }

  group('ProblemsView', () {
    testWidgets('shows add-problem row when authenticated', (tester) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.authenticated, userId: 'user1'),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('hides add-problem row when not authenticated', (tester) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.unauthenticated),
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
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.authenticated, userId: 'owner1'),
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

    testWidgets(
      'signing in immediately surfaces the edit and flag buttons '
      'without any other rebuild trigger',
      (tester) async {
        // Regression test for the stale-userId bug: the ListView's outer
        // Builder used context.read<UserCubit>() rather than watch(), so
        // showEditButton / showComplaintButton were computed once from the
        // unauthenticated userId and never updated when auth resolved.
        // The vote chip already worked because ProblemReadTile watches
        // UserCubit internally.
        final authController = StreamController<UserState>.broadcast();
        addTearDown(authController.close);
        const initial = UserState();
        const signedIn = UserState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        );
        whenListen(
          userCubit,
          authController.stream,
          initialState: initial,
        );
        when(() => problemsCubit.state).thenReturn(
          ProblemsState(
            status: ProblemsStatus.success,
            problems: [
              _problem(), // owned by 'owner1'
              _problem(
                id: '2',
                description: 'someone else problem',
                ownerId: 'other',
              ),
            ],
          ),
        );

        await tester.pumpWidget(buildSubject());

        // Unauthenticated: neither button is shown on any tile.
        expect(find.text('🖊️'), findsNothing);
        expect(find.text('🙈'), findsNothing);

        // Drive the sign-in transition; no other interaction.
        authController.add(signedIn);
        await tester.pump();

        // Owner of problem #1 sees the edit button on it AND the flag
        // button on the foreign #2.
        expect(find.text('🖊️'), findsOneWidget);
        expect(find.text('🙈'), findsOneWidget);
      },
    );

    testWidgets('shows flag button for non-owned problems', (tester) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.authenticated, userId: 'other'),
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
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.authenticated, userId: 'user1'),
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

    testWidgets('vote chip is ActionChip when authenticated with votes', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
          remainingVotes: initialVoteBudget,
        ),
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

    testWidgets('vote chip is plain Chip when no remaining votes', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
          remainingVotes: 0,
        ),
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

    testWidgets('vote chip is plain Chip when not authenticated', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.unauthenticated),
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
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
          remainingVotes: initialVoteBudget,
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem(id: 'p1', ownerId: 'other')],
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
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.authenticated, userId: 'user1'),
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

    testWidgets(
      'change-location menu item shows global subtitle when scope is /',
      (tester) async {
        when(() => problemsCubit.state).thenReturn(
          const ProblemsState(status: ProblemsStatus.success),
        );
        // Default GeoscopeState selectedGeoscope is '/'.
        await tester.pumpWidget(buildSubject());
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pump();
        expect(find.textContaining('Global'), findsOneWidget);
      },
    );

    testWidgets(
      'change-location menu item shows the selected geoscope label as subtitle',
      (tester) async {
        when(() => problemsCubit.state).thenReturn(
          const ProblemsState(status: ProblemsStatus.success),
        );
        when(() => geoscopeCubit.state).thenReturn(
          const GeoscopeState(
            selectedGeoscope: 'us/ca/sfbay',
            availableGeoscopes: [
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: 37.7793,
                lng: -122.4193,
              ),
            ],
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pump();
        expect(find.text('SF Bay Area'), findsOneWidget);
      },
    );

    testWidgets('goal field hidden until description has 3 words', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.authenticated, userId: 'user1'),
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

    testWidgets('failure state shows retry button', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.failure),
      );
      when(() => problemsCubit.subscribe()).thenAnswer((_) async {});
      await tester.pumpWidget(buildSubject());
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      verify(() => problemsCubit.subscribe()).called(1);
    });

    testWidgets('toggling owned filter hides non-owned problems', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(description: 'my problem'),
            _problem(
              id: '2',
              description: 'someone elses problem',
              ownerId: 'other',
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());

      // Both visible initially.
      expect(find.text('my problem'), findsOneWidget);
      expect(find.text('someone elses problem'), findsOneWidget);

      // Open menu and toggle owned filter.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_menuItem('toggle_owned'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Only owned problem visible.
      expect(find.text('my problem'), findsOneWidget);
      expect(find.text('someone elses problem'), findsNothing);
    });

    testWidgets('toggling goals filter hides problems without goals', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(
              description: 'has goal',
              goal: 'some goal text',
            ),
            _problem(id: '2', description: 'no goal'),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());

      // Both visible initially.
      expect(find.text('has goal'), findsOneWidget);
      expect(find.text('no goal'), findsOneWidget);

      // Open menu and toggle goals filter.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_menuItem('toggle_with_goals'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('has goal'), findsOneWidget);
      expect(find.text('no goal'), findsNothing);
    });

    testWidgets('recency filter hides problems older than the window', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(
              description: 'fresh problem',
              lastUpdatedAt: DateTime.now(),
            ),
            _problem(
              id: '2',
              description: 'stale problem',
              lastUpdatedAt: DateTime.now().subtract(const Duration(days: 100)),
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());

      // Filter off (any time) — both visible.
      expect(find.text('fresh problem'), findsOneWidget);
      expect(find.text('stale problem'), findsOneWidget);

      // Apply a 7-day window (the dialog slider drives this same call). The
      // list watches RecencyFilterCubit, so it re-filters without a setState.
      await recencyFilterCubit.setMaxAgeDays(7);
      await tester.pump();

      expect(find.text('fresh problem'), findsOneWidget);
      expect(find.text('stale problem'), findsNothing);
    });

    testWidgets('recency menu item opens the slider dialog', (tester) async {
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Filter off → the menu offers to enable it ("Show only…"), with the
      // current window in the subtitle.
      expect(find.text('Show only recently updated problems'), findsOneWidget);
      expect(find.text('Any time'), findsOneWidget);

      await tester.tap(_menuItem('recency_filter'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Dialog with the discrete slider, defaulting to the "any time" label.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Any time'), findsOneWidget);
    });

    testWidgets('recency menu states the active filter when a window is set', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());

      // Turn the filter on before opening the menu.
      await recencyFilterCubit.setMaxAgeDays(7);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Filter on → the menu states the active filter ("Showing only…"), with
      // the selected window in the subtitle.
      expect(
        find.text('Showing only recently updated problems'),
        findsOneWidget,
      );
      expect(find.text('Within 7 days'), findsOneWidget);
    });

    testWidgets('sign in button shown when unauthenticated', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.unauthenticated),
      );
      when(() => userCubit.signIn()).thenAnswer((_) async {});
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());

      final signIn = find.widgetWithIcon(IconButton, Icons.login);
      expect(signIn, findsOneWidget);

      await tester.tap(signIn);
      await tester.pump();
      verify(() => userCubit.signIn()).called(1);
    });

    testWidgets('sign out menu item shown when authenticated', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
        ),
      );
      when(() => userCubit.signOut()).thenAnswer((_) async {});
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());

      // Logout is no longer in the app bar — it's a hamburger menu item.
      expect(find.byIcon(Icons.logout), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_menuItem('sign_out'));
      await tester.pump();
      verify(() => userCubit.signOut()).called(1);
    });

    testWidgets('tapping edit shows ProblemEditTile', (tester) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [_problem()],
        ),
      );
      await tester.pumpWidget(buildSubject());

      // Tap the edit button (🖊️).
      await tester.tap(find.text('🖊️'));
      await tester.pump();

      // ProblemEditTile should now be rendered.
      expect(find.byType(ProblemEditTile), findsOneWidget);
    });

    testWidgets('complaint dialog confirms and submits', (tester) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
        ),
      );
      final problem = _problem(ownerId: 'other', description: 'offensive');
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [problem],
        ),
      );
      when(
        () => problemsCubit.flagProblem(
          problem: any(named: 'problem'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpWidget(buildSubject());

      // Tap the flag button (🙈).
      await tester.tap(find.text('🙈'));
      await tester.pump();

      // Confirm dialog appears.
      expect(find.text('Flag as abusive?'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Report.
      await tester.tap(find.text('Report'));
      await tester.pump();

      verify(
        () => problemsCubit.flagProblem(
          problem: problem,
          userId: 'user1',
        ),
      ).called(1);
      // Dismiss and pump past the dismiss-animation + delayed-dispose so the
      // toast's internal timers don't outlive the disposed widget tree.
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('complaint dialog cancel does not submit', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(ownerId: 'other', description: 'offensive'),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());

      await tester.tap(find.text('🙈'));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      verifyNever(
        () => problemsCubit.flagProblem(
          problem: any(named: 'problem'),
          userId: any(named: 'userId'),
        ),
      );
    });

    testWidgets('menu shows votes remaining for authenticated user', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'user1',
          remainingVotes: 7,
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Should display votes remaining text.
      expect(find.textContaining('7'), findsWidgets);
    });

    testWidgets('app bar title shows filtered problem count', (
      tester,
    ) async {
      when(() => problemsCubit.state).thenReturn(
        ProblemsState(
          status: ProblemsStatus.success,
          problems: [
            _problem(description: 'first'),
            _problem(id: '2', description: 'second'),
            _problem(id: '3', description: 'third'),
          ],
        ),
      );
      await tester.pumpWidget(buildSubject());
      expect(find.textContaining('3'), findsWidgets);
    });

    testWidgets('banner shows sign-in tip when unauthenticated', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        const UserState(status: AuthStatus.unauthenticated),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      expect(find.textContaining('Sign in via the'), findsOneWidget);
      expect(find.textContaining('vote for it'), findsNothing);
      expect(find.textContaining('Tap a problem'), findsNothing);
    });

    testWidgets('banner shows vote tip when needsVoteHint is true', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 0,
          problemDetailsViewCount: 0,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      expect(find.textContaining('vote for it'), findsOneWidget);
      expect(find.textContaining('Tap a problem'), findsNothing);
    });

    testWidgets('banner shows tap-for-details tip when vote hint graduated', (
      tester,
    ) async {
      // votesCastCount=5 > daysSince=0 → vote tip graduates;
      // problemDetailsViewCount=0 <= daysSince=0 → tap-for-details tip wins.
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 5,
          problemDetailsViewCount: 0,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      expect(find.textContaining('Tap a problem'), findsOneWidget);
      expect(find.textContaining('vote for it'), findsNothing);
    });

    testWidgets(
      'banner falls through to tap-for-details when remainingVotes is 0',
      (tester) async {
        // remainingVotes=0 suppresses the vote tip (chip is non-interactive),
        // but problemDetailsViewCount=0 <= daysSince=0 means the
        // tap-for-details tip is still applicable — the chain should fall
        // through to it rather than hide the banner entirely.
        when(() => userCubit.state).thenReturn(
          UserState(
            status: AuthStatus.authenticated,
            userId: 'u1',
            remainingVotes: 0,
            votesCastCount: 0,
            problemDetailsViewCount: 0,
            sessionStartLastActiveAt: DateTime.now().toUtc(),
          ),
        );
        when(() => problemsCubit.state).thenReturn(
          const ProblemsState(status: ProblemsStatus.success),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pump();

        expect(find.textContaining('Tap a problem'), findsOneWidget);
        expect(find.textContaining('vote for it'), findsNothing);
      },
    );

    testWidgets('banner shows nothing once both tips graduate', (
      tester,
    ) async {
      when(() => userCubit.state).thenReturn(
        UserState(
          status: AuthStatus.authenticated,
          userId: 'u1',
          remainingVotes: 3,
          votesCastCount: 99,
          problemDetailsViewCount: 99,
          sessionStartLastActiveAt: DateTime.now().toUtc(),
        ),
      );
      when(() => problemsCubit.state).thenReturn(
        const ProblemsState(status: ProblemsStatus.success),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      expect(find.textContaining('Sign in'), findsNothing);
      expect(find.textContaining('vote for it'), findsNothing);
      expect(find.textContaining('Tap a problem'), findsNothing);
    });

    testWidgets(
      'tap fires incrementProblemDetailsViewCount',
      (tester) async {
        when(() => userCubit.state).thenReturn(
          UserState(
            status: AuthStatus.authenticated,
            userId: 'u1',
            remainingVotes: 3,
            votesCastCount: 99,
            problemDetailsViewCount: 99,
            sessionStartLastActiveAt: DateTime.now().toUtc(),
          ),
        );
        when(() => problemsCubit.state).thenReturn(
          ProblemsState(
            status: ProblemsStatus.success,
            problems: [_problem(description: 'tap me')],
          ),
        );
        when(
          () => firestoreRepo.incrementProblemDetailsViewCount(any()),
        ).thenAnswer((_) async {});
        await tester.pumpWidget(buildSubject());
        await tester.pump();

        await tester.tap(find.text('tap me'));
        await tester.pump();

        // The tap handler calls incrementProblemDetailsViewCount and then
        // context.push(...). Because buildSubject() uses a plain MaterialApp
        // (no GoRouter), context.push throws a "No GoRouter found" error.
        // Swallow it — the side-effect we care about (the repo call) is
        // issued synchronously before the navigation attempt.
        tester.takeException();

        verify(
          () => firestoreRepo.incrementProblemDetailsViewCount('u1'),
        ).called(1);
      },
    );
  });
}
