import 'package:bloc_test/bloc_test.dart';
import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
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
import 'package:toastification/toastification.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _MockGeoscopeCubit extends MockCubit<GeoscopeState>
    implements GeoscopeCubit {}

class _MockProblemsCubit extends MockCubit<ProblemsState>
    implements ProblemsCubit {}

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
  int votes = 7,
  String? lang,
  bool hidden = false,
}) {
  final now = DateTime.utc(2024);
  return Problem(
    id: id,
    description: description,
    goal: goal,
    ownerId: ownerId,
    geoscope: geoscope,
    votes: votes,
    lang: lang,
    hidden: hidden,
    createdAt: now,
    lastUpdatedAt: now,
  );
}

void main() {
  late FirestoreRepository repo;
  late AuthCubit authCubit;
  late GeoscopeCubit geoscopeCubit;
  late ProblemsCubit problemsCubit;
  late LanguageDetectionService languageDetectionService;
  late TranslationRepository translationRepo;

  setUpAll(() {
    registerFallbackValue(_problem());
    registerFallbackValue(ProblemLinkKind.specialization);
  });

  setUp(() {
    repo = _MockFirestoreRepository();
    authCubit = _MockAuthCubit();
    geoscopeCubit = _MockGeoscopeCubit();
    problemsCubit = _MockProblemsCubit();
    languageDetectionService = _MockLanguageDetectionService();
    translationRepo = _MockTranslationRepository();

    when(() => authCubit.state).thenReturn(const AuthState());
    when(() => geoscopeCubit.state).thenReturn(const GeoscopeState());
    when(() => problemsCubit.state).thenReturn(const ProblemsState());
    when(() => problemsCubit.applyLocalUpdate(any())).thenReturn(null);
    when(
      () => repo.getVotersForProblem(
        any(),
        excludeUid: any(named: 'excludeUid'),
        anonymous: any(named: 'anonymous'),
      ),
    ).thenAnswer((_) async => []);
    when(() => repo.getForksOfProblem(any())).thenAnswer((_) async => []);
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
        BlocProvider<ProblemsCubit>.value(value: problemsCubit),
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
        child: ToastificationWrapper(
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
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
      expect(find.text('7'), findsOneWidget);
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

    group('hidden flag', () {
      testWidgets('owner sees Hide button when problem is not hidden', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(),
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(status: AuthStatus.authenticated, userId: 'owner1'),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('hideProblemButton')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('hiddenBanner')), findsNothing);
      });

      testWidgets('owner sees owner banner and Show-in-listing when hidden', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(hidden: true),
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(status: AuthStatus.authenticated, userId: 'owner1'),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hiddenBanner')), findsOneWidget);
        expect(
          find.byKey(const Key('unhideProblemButton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('hideProblemButton')),
          findsNothing,
        );
      });

      testWidgets('non-owner sees viewer banner only, no buttons', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(hidden: true),
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'other-user',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hiddenBanner')), findsOneWidget);
        expect(
          find.byKey(const Key('hideProblemButton')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('unhideProblemButton')),
          findsNothing,
        );
      });

      testWidgets('non-owner sees no banner when problem is not hidden', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(),
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'other-user',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hiddenBanner')), findsNothing);
      });

      testWidgets('tapping Hide calls cubit.setHidden(problem, true)', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(),
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(status: AuthStatus.authenticated, userId: 'owner1'),
        );
        when(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: any(named: 'hidden'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('hideProblemButton')));
        await tester.pumpAndSettle();
        verify(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: true,
          ),
        ).called(1);
      });

      testWidgets('tapping Show-in-listing calls cubit.setHidden(false)', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(hidden: true),
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(status: AuthStatus.authenticated, userId: 'owner1'),
        );
        when(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: any(named: 'hidden'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('unhideProblemButton')));
        await tester.pumpAndSettle();
        verify(
          () => problemsCubit.setHidden(
            problem: any(named: 'problem'),
            hidden: false,
          ),
        ).called(1);
      });
    });

    testWidgets('back button navigates to home', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => null);
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(find.text("See everybody's problems"));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets(
      'save calls updateProblem, stays on the page, and shows a toast',
      (tester) async {
        final problem = _problem();
        when(() => repo.getProblem(any())).thenAnswer((_) async => problem);
        when(
          () => repo.updateProblem(
            any(),
            userLanguage: any(named: 'userLanguage'),
            copiedFromProblemId: any(named: 'copiedFromProblemId'),
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
            copiedFromProblemId: any(named: 'copiedFromProblemId'),
          ),
        ).called(1);
        // Notifies the list cubit so the list won't show stale data on return.
        verify(() => problemsCubit.applyLocalUpdate(any())).called(1);
        // Still on the detail page, not navigated home.
        expect(find.text('home'), findsNothing);
        // Confirmation toast is visible.
        expect(find.text('Your changes have been saved'), findsOneWidget);
        // Dismiss so the toast's auto-close timer doesn't outlive the test.
        toastification.dismissAll(delayForAnimation: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('save shows an error toast when updateProblem throws', (
      tester,
    ) async {
      final problem = _problem();
      when(() => repo.getProblem(any())).thenAnswer((_) async => problem);
      when(
        () => repo.updateProblem(
          any(),
          userLanguage: any(named: 'userLanguage'),
          copiedFromProblemId: any(named: 'copiedFromProblemId'),
        ),
      ).thenThrow(Exception('boom'));
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        ),
      );

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'updated problem description',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsNothing);
      expect(
        find.text('Could not save your changes. Please try again.'),
        findsOneWidget,
      );
      // Success toast must NOT appear on failure.
      expect(find.text('Your changes have been saved'), findsNothing);
      // List cubit must NOT be notified on failure.
      verifyNever(() => problemsCubit.applyLocalUpdate(any()));
      // Dismiss so the toast's auto-close timer doesn't outlive the test.
      toastification.dismissAll(delayForAnimation: false);
      await tester.pumpAndSettle();
    });

    testWidgets('vote chip is tappable for authenticated non-owner', (
      tester,
    ) async {
      when(() => repo.getProblem(any())).thenAnswer(
        (_) async => _problem(),
      );
      when(
        () => repo.vote(
          problemId: any(named: 'problemId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
          remainingVotes: initialVoteBudget,
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Should show ActionChip with vote icon.
      expect(find.byType(ActionChip), findsOneWidget);
      expect(
        find.byIcon(Icons.arrow_circle_up_rounded),
        findsOneWidget,
      );

      // Tap the vote chip.
      await tester.tap(find.byType(ActionChip));
      await tester.pump();
      verify(
        () => repo.vote(problemId: 'test-id', userId: 'other-user'),
      ).called(1);
    });

    testWidgets('vote chip is plain Chip when not authenticated', (
      tester,
    ) async {
      when(() => repo.getProblem(any())).thenAnswer(
        (_) async => _problem(),
      );
      when(() => authCubit.state).thenReturn(const AuthState());
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('7'), findsOneWidget);
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

    testWidgets('excludes owner from voter list', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Verify excludeUid is the owner's ID.
      verify(
        () => repo.getVotersForProblem(
          any(),
          excludeUid: 'owner1',
          anonymous: any(named: 'anonymous'),
        ),
      ).called(1);
    });

    testWidgets('shows voter list sorted by votes then name', (
      tester,
    ) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(
        () => repo.getVotersForProblem(
          any(),
          excludeUid: any(named: 'excludeUid'),
          anonymous: any(named: 'anonymous'),
        ),
      ).thenAnswer(
        (_) async => [
          (name: 'Alice', votes: 5),
          (name: 'Bob', votes: 3),
          (name: 'Charlie', votes: 1),
        ],
      );
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Voters'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('hides voter list when empty', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Voters'), findsNothing);
    });

    testWidgets('refreshes voter list after voting', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(
        () => repo.vote(
          problemId: any(named: 'problemId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
          remainingVotes: initialVoteBudget,
        ),
      );

      var callCount = 0;
      when(
        () => repo.getVotersForProblem(
          any(),
          excludeUid: any(named: 'excludeUid'),
          anonymous: any(named: 'anonymous'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) return [];
        return [(name: 'Voter', votes: 1)];
      });

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Initially no voters.
      expect(find.text('Voters'), findsNothing);

      // Tap the vote chip.
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();

      // Voter list should now appear after refresh.
      expect(find.text('Voters'), findsOneWidget);
      expect(find.text('Voter'), findsOneWidget);
      verify(
        () => repo.getVotersForProblem(
          any(),
          excludeUid: any(named: 'excludeUid'),
          anonymous: any(named: 'anonymous'),
        ),
      ).called(2);
    });

    testWidgets('hides forks section when there are no forks', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('shows forks section with count when forks exist', (
      tester,
    ) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => repo.getForksOfProblem(any())).thenAnswer(
        (_) async => [
          _problem(id: 'fork-a', description: 'Forked problem A'),
          _problem(id: 'fork-b', description: 'Forked problem B'),
        ],
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Heading shows the count.
      expect(find.text('Forks (2)'), findsOneWidget);
      // Initially expanded — both fork titles visible.
      expect(find.text('Forked problem A'), findsOneWidget);
      expect(find.text('Forked problem B'), findsOneWidget);
    });

    testWidgets('collapsing the forks section hides the items', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => repo.getForksOfProblem(any())).thenAnswer(
        (_) async => [_problem(id: 'fork-a', description: 'Forked problem A')],
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Forked problem A'), findsOneWidget);
      await tester.tap(find.text('Forks (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Forked problem A'), findsNothing);
      // Heading (with count) remains visible.
      expect(find.text('Forks (1)'), findsOneWidget);
    });

    testWidgets(
      'compare icon hidden when fork matches current problem in all fields',
      (tester) async {
        // Owner viewing their own problem. The fork is identical in
        // description/goal/geoscope, so there is nothing to compare and the
        // compare icon must not render.
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => repo.getForksOfProblem(any())).thenAnswer(
          (_) async => [_problem(id: 'fork-a')],
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.compare_arrows), findsNothing);
      },
    );

    testWidgets('compare icon hidden for non-owners even when forks differ', (
      tester,
    ) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => repo.getForksOfProblem(any())).thenAnswer(
        (_) async => [_problem(id: 'fork-a', description: 'A different desc')],
      );
      // Authenticated but not the owner.
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.compare_arrows), findsNothing);
    });

    testWidgets(
      'owner can replace one field with a fork value via "Use this here"',
      (tester) async {
        final current = _problem(description: 'original desc', goal: 'g1');
        final fork = _problem(
          id: 'fork-a',
          description: 'forked desc',
          goal: 'g1', // same goal — should NOT appear in the panel
        );
        when(() => repo.getProblem(any())).thenAnswer((_) async => current);
        when(() => repo.getForksOfProblem(any())).thenAnswer(
          (_) async => [fork],
        );
        when(
          () => repo.updateProblem(
            any(),
            userLanguage: any(named: 'userLanguage'),
            copiedFromProblemId: any(named: 'copiedFromProblemId'),
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

        // The compare icon is present (description differs).
        await tester.tap(find.byIcon(Icons.compare_arrows));
        await tester.pumpAndSettle();

        // Only the differing field is listed in the panel; the matching
        // goal is omitted entirely. The field-label string ("Description")
        // is what uniquely identifies the panel — the fork's description
        // also renders in the row title, so we check the label rather than
        // the value.
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Goal'), findsNothing);
        expect(find.text('Use this here'), findsOneWidget);

        await tester.tap(find.text('Use this here'));
        await tester.pumpAndSettle();

        // updateProblem was called once with the fork's description merged
        // into the current problem; other fields are unchanged.
        final captured =
            verify(
                  () => repo.updateProblem(
                    captureAny(),
                    userLanguage: any(named: 'userLanguage'),
                    copiedFromProblemId: any(named: 'copiedFromProblemId'),
                  ),
                ).captured.single
                as Problem;
        expect(captured.description, 'forked desc');
        expect(captured.goal, 'g1');
        expect(captured.id, current.id);

        // Notifies the list cubit, shows the standard "saved" toast.
        verify(() => problemsCubit.applyLocalUpdate(any())).called(1);
        expect(find.text('Your changes have been saved'), findsOneWidget);
        toastification.dismissAll(delayForAnimation: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'different-language fork bundles description and goal into one button',
      (tester) async {
        // Bundling is required because updateProblem's language validator
        // would reject a mixed-language result if we copied just one of
        // the two text fields. A single bundled button replaces both.
        final current = _problem(
          description: 'english desc',
          goal: 'english goal',
          lang: 'en',
        );
        final fork = _problem(
          id: 'fork-a',
          description: 'french desc',
          goal: 'french goal',
          lang: 'fr',
        );
        when(() => repo.getProblem(any())).thenAnswer((_) async => current);
        when(() => repo.getForksOfProblem(any())).thenAnswer(
          (_) async => [fork],
        );
        when(
          () => repo.updateProblem(
            any(),
            userLanguage: any(named: 'userLanguage'),
            copiedFromProblemId: any(named: 'copiedFromProblemId'),
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

        await tester.tap(find.byIcon(Icons.compare_arrows));
        await tester.pumpAndSettle();

        // Both field labels render inside the same diff row.
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Goal'), findsOneWidget);
        // Exactly one "Use this here" button — not one per field.
        expect(find.text('Use this here'), findsOneWidget);

        await tester.tap(find.text('Use this here'));
        await tester.pumpAndSettle();

        // updateProblem received both text fields swapped at once.
        final captured =
            verify(
                  () => repo.updateProblem(
                    captureAny(),
                    userLanguage: any(named: 'userLanguage'),
                    copiedFromProblemId: any(named: 'copiedFromProblemId'),
                  ),
                ).captured.single
                as Problem;
        expect(captured.description, 'french desc');
        expect(captured.goal, 'french goal');

        toastification.dismissAll(delayForAnimation: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'different-language fork still offers geoscope independently',
      (tester) async {
        // Geoscope is language-independent, so it stays its own row even
        // when the text fields are bundled.
        final current = _problem(
          description: 'english desc',
          goal: 'english goal',
          lang: 'en',
        );
        final fork = _problem(
          id: 'fork-a',
          description: 'french desc',
          goal: 'french goal',
          geoscope: 'eu/fr',
          lang: 'fr',
        );
        when(() => repo.getProblem(any())).thenAnswer((_) async => current);
        when(() => repo.getForksOfProblem(any())).thenAnswer(
          (_) async => [fork],
        );
        when(
          () => repo.updateProblem(
            any(),
            userLanguage: any(named: 'userLanguage'),
            copiedFromProblemId: any(named: 'copiedFromProblemId'),
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

        await tester.tap(find.byIcon(Icons.compare_arrows));
        await tester.pumpAndSettle();

        // One bundled text entry + one geoscope entry = two buttons.
        expect(find.text('Use this here'), findsNWidgets(2));
        expect(find.text('Location'), findsOneWidget);

        // Tap the geoscope button (the second "Use this here").
        await tester.tap(find.text('Use this here').last);
        await tester.pumpAndSettle();

        final captured =
            verify(
                  () => repo.updateProblem(
                    captureAny(),
                    userLanguage: any(named: 'userLanguage'),
                    copiedFromProblemId: any(named: 'copiedFromProblemId'),
                  ),
                ).captured.single
                as Problem;
        // Geoscope swapped, text fields untouched.
        expect(captured.geoscope, 'eu/fr');
        expect(captured.description, 'english desc');
        expect(captured.goal, 'english goal');

        toastification.dismissAll(delayForAnimation: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'shows linked problems section with count when linked problems exist',
      (tester) async {
        final mainProblem = _problem(
          id: 'p1',
        ).copyWith(linkedProblemIds: ['p2']);
        final linkedProblem = _problem(
          id: 'p2',
          description: 'Linked problem description',
        );

        when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
        when(
          () => repo.getProblem('p2'),
        ).thenAnswer((_) async => linkedProblem);

        await tester.pumpWidget(buildSubject(problemId: 'p1'));
        await tester.pumpAndSettle();

        // Heading shows the count.
        expect(find.text('Linked Problems (1)'), findsOneWidget);
        // Linked problem description is visible.
        expect(find.text('Linked problem description'), findsOneWidget);
      },
    );

    testWidgets('allows unlinking when authenticated', (tester) async {
      final mainProblem = _problem(id: 'p1').copyWith(linkedProblemIds: ['p2']);
      final linkedProblem = _problem(
        id: 'p2',
        description: 'Linked problem description',
      );

      when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
      when(() => repo.getProblem('p2')).thenAnswer((_) async => linkedProblem);
      when(() => repo.unlinkProblem('p2')).thenAnswer((_) async {});
      when(() => authCubit.state).thenReturn(
        const AuthState(
          status: AuthStatus.authenticated,
          userId: 'owner1',
        ),
      );

      await tester.pumpWidget(buildSubject(problemId: 'p1'));
      await tester.pumpAndSettle();

      // Unlink button should be present
      final unlinkBtn = find.byIcon(Icons.link_off);
      expect(unlinkBtn, findsOneWidget);

      await tester.tap(unlinkBtn);
      await tester.pumpAndSettle();

      verify(() => repo.unlinkProblem('p2')).called(1);
    });

    testWidgets('hides unlink button when unauthenticated', (tester) async {
      final mainProblem = _problem(id: 'p1').copyWith(linkedProblemIds: ['p2']);
      final linkedProblem = _problem(
        id: 'p2',
        description: 'Linked problem description',
      );

      when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
      when(() => repo.getProblem('p2')).thenAnswer((_) async => linkedProblem);
      when(() => authCubit.state).thenReturn(const AuthState());

      await tester.pumpWidget(buildSubject(problemId: 'p1'));
      await tester.pumpAndSettle();

      // Unlink button should not be present
      expect(find.byIcon(Icons.link_off), findsNothing);
    });

    testWidgets(
      'clicking link button opens dialog and allows linking via search',
      (tester) async {
        final mainProblem = _problem(id: 'p1');
        final searchResult = _problem(
          id: 'p2',
          description: 'Matching problem description',
        );

        when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
        when(
          () => repo.getGlobalProblemsForSearch(),
        ).thenAnswer((_) async => [searchResult]);
        when(() => repo.linkProblems('p1', 'p2')).thenAnswer((_) async {});
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject(problemId: 'p1'));
        await tester.pumpAndSettle();

        // Dialog trigger button (link icon) should be in app bar actions
        final linkBtn = find.byIcon(Icons.link);
        expect(linkBtn, findsOneWidget);

        await tester.tap(linkBtn);
        await tester.pumpAndSettle();

        // Dialog is open
        expect(find.text('Link a Problem'), findsOneWidget);
        expect(find.text('Matching problem description'), findsOneWidget);

        // Tap on link icon of the search result
        final confirmLinkBtn = find.descendant(
          of: find.byType(ListTile),
          matching: find.byIcon(Icons.link),
        );
        await tester.tap(confirmLinkBtn);
        await tester.pumpAndSettle();

        verify(() => repo.linkProblems('p1', 'p2')).called(1);
        expect(find.text('Link a Problem'), findsNothing);
      },
    );

    testWidgets(
      'typing in search query debounces and filters list correctly',
      (tester) async {
        final mainProblem = _problem(id: 'p1');
        final result1 = _problem(id: 'p2', description: 'Apple problem');
        final result2 = _problem(id: 'p3', description: 'Banana problem');

        when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
        when(() => repo.getGlobalProblemsForSearch()).thenAnswer(
          (_) async => [result1, result2],
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject(problemId: 'p1'));
        await tester.pumpAndSettle();

        // Open dialog
        await tester.tap(find.byIcon(Icons.link));
        await tester.pumpAndSettle();

        expect(find.text('Apple problem'), findsOneWidget);
        expect(find.text('Banana problem'), findsOneWidget);

        // Type "Apple"
        await tester.enterText(find.byType(TextField).last, 'Apple');

        // Before 300ms debounce, nothing should change
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Apple problem'), findsOneWidget);
        expect(find.text('Banana problem'), findsOneWidget);

        // Pump 300ms to trigger debounce and perform search
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Now only "Apple problem" should be visible, and "Banana problem"
        // should be gone
        expect(find.text('Apple problem'), findsOneWidget);
        expect(find.text('Banana problem'), findsNothing);
      },
    );

    testWidgets(
      'split-button menu opens dialog in specialization mode',
      (tester) async {
        final mainProblem = _problem(id: 'p1');
        final searchResult = _problem(id: 'p2', description: 'Candidate');

        when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
        when(
          () => repo.getGlobalProblemsForSearch(),
        ).thenAnswer((_) async => [searchResult]);
        when(
          () => repo.tagProblemLink(
            sourceId: any(named: 'sourceId'),
            targetId: any(named: 'targetId'),
            kind: any(named: 'kind'),
          ),
        ).thenAnswer((_) async {});
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject(problemId: 'p1'));
        await tester.pumpAndSettle();

        // App bar shows the link icon AND the chevron dropdown
        expect(find.byIcon(Icons.link), findsOneWidget);
        final chevron = find.byIcon(Icons.arrow_drop_down);
        expect(chevron, findsOneWidget);

        await tester.tap(chevron);
        await tester.pumpAndSettle();

        // Menu items
        expect(find.text('Link as specialization'), findsOneWidget);
        expect(find.text('Link as generalization'), findsOneWidget);

        await tester.tap(find.text('Link as specialization'));
        await tester.pumpAndSettle();

        // Dialog opens with the specialization title
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Link as specialization'),
          ),
          findsOneWidget,
        );

        // Tap the per-row link icon to confirm
        await tester.tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.byIcon(Icons.link),
          ),
        );
        await tester.pumpAndSettle();

        verify(
          () => repo.tagProblemLink(
            sourceId: 'p1',
            targetId: 'p2',
            kind: ProblemLinkKind.specialization,
          ),
        ).called(1);
      },
    );

    testWidgets(
      'renders typed-link subsections and untag fires repository call',
      (tester) async {
        final mainProblem = _problem(id: 'p1').copyWith(
          typedLinks: const [
            ProblemLink(
              targetId: 'gen',
              kind: ProblemLinkKind.generalization,
            ),
            ProblemLink(
              targetId: 'spec',
              kind: ProblemLinkKind.specialization,
            ),
          ],
        );
        final generalProblem = _problem(
          id: 'gen',
          description: 'Broader problem',
        );
        final specProblem = _problem(
          id: 'spec',
          description: 'Narrower problem',
        );

        when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
        when(
          () => repo.getProblem('gen'),
        ).thenAnswer((_) async => generalProblem);
        when(
          () => repo.getProblem('spec'),
        ).thenAnswer((_) async => specProblem);
        when(
          () => repo.untagProblemLink(
            sourceId: any(named: 'sourceId'),
            targetId: any(named: 'targetId'),
          ),
        ).thenAnswer((_) async {});
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject(problemId: 'p1'));
        await tester.pumpAndSettle();

        expect(find.text('Generalizations (1)'), findsOneWidget);
        expect(find.text('Specializations (1)'), findsOneWidget);
        expect(find.text('Broader problem'), findsOneWidget);
        expect(find.text('Narrower problem'), findsOneWidget);

        // Untag the generalization (find the link-off near "Broader problem")
        final broaderTile = find.widgetWithText(ListTile, 'Broader problem');
        await tester.tap(
          find.descendant(
            of: broaderTile,
            matching: find.byIcon(Icons.link_off),
          ),
        );
        await tester.pumpAndSettle();

        verify(
          () => repo.untagProblemLink(sourceId: 'p1', targetId: 'gen'),
        ).called(1);
      },
    );

    testWidgets(
      'dialog already-linked guard excludes typed-link targets',
      (tester) async {
        final mainProblem = _problem(id: 'p1').copyWith(
          typedLinks: const [
            ProblemLink(
              targetId: 'p2',
              kind: ProblemLinkKind.specialization,
            ),
          ],
        );
        final alreadyTaggedProblem = _problem(
          id: 'p2',
          description: 'Already tagged',
        );
        final freshProblem = _problem(id: 'p3', description: 'Fresh candidate');

        when(() => repo.getProblem('p1')).thenAnswer((_) async => mainProblem);
        when(
          () => repo.getProblem('p2'),
        ).thenAnswer((_) async => alreadyTaggedProblem);
        when(() => repo.getGlobalProblemsForSearch()).thenAnswer(
          (_) async => [alreadyTaggedProblem, freshProblem],
        );
        when(() => authCubit.state).thenReturn(
          const AuthState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject(problemId: 'p1'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.link).first);
        await tester.pumpAndSettle();

        // Fresh candidate should appear inside the dialog; the already-tagged
        // one should be filtered out.
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Fresh candidate'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Already tagged'),
          ),
          findsNothing,
        );
      },
    );
  });
}
