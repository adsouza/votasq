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

class _MockUserCubit extends MockCubit<UserState> implements UserCubit {}

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
  late UserCubit userCubit;
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
    userCubit = _MockUserCubit();
    geoscopeCubit = _MockGeoscopeCubit();
    problemsCubit = _MockProblemsCubit();
    languageDetectionService = _MockLanguageDetectionService();
    translationRepo = _MockTranslationRepository();

    when(() => userCubit.state).thenReturn(const UserState());
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
    when(() => repo.getDisplayName(any())).thenAnswer((_) async => null);
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
        BlocProvider<UserCubit>.value(value: userCubit),
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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

    testWidgets(
      'owner editing a global problem from global user scope omits the '
      'geoscope row entirely (no orphan label hanging beside an empty '
      'dropdown)',
      (tester) async {
        // Default _problem().geoscope and default GeoscopeState are both
        // '/', which is the exact condition where buildGeoscopeDropdown
        // returns []. The whole label + dropdown row should disappear.
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        expect(find.text('Geographic scope:'), findsNothing);
      },
    );

    testWidgets(
      'owner editing a non-global problem still shows the geoscope row',
      (tester) async {
        // Regression guard for the omit-when-empty fix: it must not hide
        // the row in the normal editing case.
        when(() => repo.getProblem(any())).thenAnswer(
          (_) async => _problem(geoscope: 'na/us'),
        );
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        expect(find.text('Geographic scope:'), findsOneWidget);
      },
    );

    testWidgets('shows editable view for owner', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => userCubit.state).thenReturn(
        const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(status: AuthStatus.authenticated, userId: 'owner1'),
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
        when(() => userCubit.state).thenReturn(
          const UserState(status: AuthStatus.authenticated, userId: 'owner1'),
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(status: AuthStatus.authenticated, userId: 'owner1'),
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
        when(() => userCubit.state).thenReturn(
          const UserState(status: AuthStatus.authenticated, userId: 'owner1'),
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

      testWidgets(
        'tapping Hide works when ProblemsCubit is NOT in scope '
        '(direct-URL navigation regression test)',
        (tester) async {
          // Reproduces the prod bug from 2026-05-23: the detail page is
          // reachable by direct URL (e.g. from a notification or a shared
          // link) without going through the listing route, so the
          // ProblemsCubit provided by ProblemsPage is not in the
          // ancestor chain. context.read<ProblemsCubit>() throws
          // ProviderNotFoundException there; the fix falls back to the
          // FirestoreRepository directly.
          when(() => repo.getProblem(any())).thenAnswer(
            (_) async => _problem(),
          );
          when(() => userCubit.state).thenReturn(
            const UserState(
              status: AuthStatus.authenticated,
              userId: 'owner1',
            ),
          );
          when(
            () => repo.setHidden(
              problemId: any(named: 'problemId'),
              hidden: any(named: 'hidden'),
            ),
          ).thenAnswer((_) async {});

          // Build a subject WITHOUT BlocProvider<ProblemsCubit>.
          final router = GoRouter(
            initialLocation: '/problems/test-id',
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
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<UserCubit>.value(value: userCubit),
                BlocProvider<GeoscopeCubit>.value(value: geoscopeCubit),
                // Intentionally no BlocProvider<ProblemsCubit>.
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
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    routerConfig: router,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('hideProblemButton')), findsOneWidget);
          await tester.tap(find.byKey(const Key('hideProblemButton')));
          await tester.pumpAndSettle();

          // Repo was called directly (cubit fallback path).
          verify(
            () => repo.setHidden(problemId: 'test-id', hidden: true),
          ).called(1);

          // UI flipped to hidden state despite the missing cubit.
          expect(find.byKey(const Key('hiddenBanner')), findsOneWidget);
          expect(find.byKey(const Key('hideProblemButton')), findsNothing);
          expect(
            find.byKey(const Key('unhideProblemButton')),
            findsOneWidget,
          );
        },
      );
    });

    group('flag complaint', () {
      testWidgets('non-owner sees the flag icon', (tester) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'other-user',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('flagProblemButton')), findsOneWidget);
      });

      testWidgets('owner does not see the flag icon', (tester) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => userCubit.state).thenReturn(
          const UserState(status: AuthStatus.authenticated, userId: 'owner1'),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('flagProblemButton')), findsNothing);
      });

      testWidgets('unauthenticated viewer does not see the flag icon', (
        tester,
      ) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => userCubit.state).thenReturn(const UserState());
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('flagProblemButton')), findsNothing);
      });

      testWidgets(
        'tapping flag → Report calls cubit.flagProblem, shows toast, '
        'and returns to listing',
        (tester) async {
          final problem = _problem();
          when(() => repo.getProblem(any())).thenAnswer((_) async => problem);
          when(() => userCubit.state).thenReturn(
            const UserState(
              status: AuthStatus.authenticated,
              userId: 'other-user',
            ),
          );
          when(
            () => problemsCubit.flagProblem(
              problem: any(named: 'problem'),
              userId: any(named: 'userId'),
            ),
          ).thenAnswer((_) async {});

          await tester.pumpWidget(buildSubject());
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('flagProblemButton')));
          await tester.pumpAndSettle();

          expect(find.text('Flag as abusive?'), findsOneWidget);
          expect(find.text('Report'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);

          await tester.tap(find.text('Report'));
          await tester.pumpAndSettle();

          verify(
            () => problemsCubit.flagProblem(
              problem: problem,
              userId: 'other-user',
            ),
          ).called(1);
          // After flagging the user is sent back to listing so the
          // now-filtered problem disappears from view — same outcome as
          // tapping the flag icon on the listing itself.
          expect(find.text('home'), findsOneWidget);
          toastification.dismissAll(delayForAnimation: false);
          await tester.pump(const Duration(seconds: 1));
        },
      );

      testWidgets('tapping flag → Cancel does not submit', (tester) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'other-user',
          ),
        );

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('flagProblemButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        verifyNever(
          () => problemsCubit.flagProblem(
            problem: any(named: 'problem'),
            userId: any(named: 'userId'),
          ),
        );
      });

      testWidgets(
        'falls back to repo.addComplaint when ProblemsCubit is NOT in scope '
        '(direct-URL navigation regression test)',
        (tester) async {
          // Mirrors the _setHidden direct-URL fallback test above: a user
          // landing on the detail page from a notification or shared link
          // sits outside the listing's BlocProvider subtree, so
          // context.read<ProblemsCubit>() throws. The fix is to write the
          // complaint via the repo instead.
          final problem = _problem();
          when(() => repo.getProblem(any())).thenAnswer((_) async => problem);
          when(() => userCubit.state).thenReturn(
            const UserState(
              status: AuthStatus.authenticated,
              userId: 'other-user',
            ),
          );
          when(
            () => repo.addComplaint(
              problemId: any(named: 'problemId'),
              userId: any(named: 'userId'),
            ),
          ).thenAnswer((_) async {});

          final router = GoRouter(
            initialLocation: '/problems/test-id',
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
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<UserCubit>.value(value: userCubit),
                BlocProvider<GeoscopeCubit>.value(value: geoscopeCubit),
                // Intentionally no BlocProvider<ProblemsCubit>.
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
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    routerConfig: router,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('flagProblemButton')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Report'));
          await tester.pumpAndSettle();

          verify(
            () => repo.addComplaint(
              problemId: 'test-id',
              userId: 'other-user',
            ),
          ).called(1);
          expect(find.text('home'), findsOneWidget);
          toastification.dismissAll(delayForAnimation: false);
          await tester.pump(const Duration(seconds: 1));
        },
      );
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        // Flush the AnimatedBuilder rebuild that listens to the text
        // controllers so the Save button picks up its newly-enabled state
        // before we tap it; without this the button would still hold its
        // initial (disabled, no-changes) onPressed=null.
        await tester.pump();
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

    testWidgets(
      'Save button is disabled until the user edits something and '
      'becomes disabled again after a successful save',
      (tester) async {
        final problem = _problem(goal: 'original goal');
        when(() => repo.getProblem(any())).thenAnswer((_) async => problem);
        when(
          () => repo.updateProblem(
            any(),
            userLanguage: any(named: 'userLanguage'),
            copiedFromProblemId: any(named: 'copiedFromProblemId'),
          ),
        ).thenAnswer((_) async {});
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'owner1',
          ),
        );

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        FilledButton saveButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save'),
        );

        // Before any edit, the loaded values equal the persisted ones, so
        // there is nothing to save — button is disabled.
        expect(saveButton().onPressed, isNull);

        // Editing the description enables it.
        await tester.enterText(
          find.byType(TextField).first,
          'updated problem description',
        );
        await tester.pump();
        expect(saveButton().onPressed, isNotNull);

        // Reverting the edit (back to the original text) disables it again.
        await tester.enterText(
          find.byType(TextField).first,
          'test problem description',
        );
        await tester.pump();
        expect(saveButton().onPressed, isNull);

        // Editing the *goal* alone (description still pristine) also enables
        // it — the previous implementation only listened to the description
        // controller and would have missed this.
        await tester.enterText(
          find.byType(TextField).at(1),
          'new goal',
        );
        await tester.pump();
        expect(saveButton().onPressed, isNotNull);

        // Tapping Save persists the change; afterward _problem reflects the
        // saved values so the button should disable again without needing
        // any further input.
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saveButton().onPressed, isNull);

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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      // See the success-path test for why this pump() is required between
      // enterText and the Save tap.
      await tester.pump();
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      when(() => userCubit.state).thenReturn(const UserState());
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      when(() => userCubit.state).thenReturn(
        const UserState(
          status: AuthStatus.authenticated,
          userId: 'other-user',
        ),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('test problem description'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
      "shows 'Posted by {name}' when the owner has a displayName",
      (tester) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(
          () => repo.getDisplayName('owner1'),
        ).thenAnswer((_) async => 'Alice');
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'other-user',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        expect(find.text('Posted by Alice'), findsOneWidget);
      },
    );

    testWidgets(
      "omits the 'Posted by' line when the owner has no displayName",
      (tester) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        // Default stub returns null; assert no attribution line renders.
        when(() => userCubit.state).thenReturn(
          const UserState(
            status: AuthStatus.authenticated,
            userId: 'other-user',
          ),
        );
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        expect(find.textContaining('Posted by'), findsNothing);
      },
    );

    testWidgets('excludes owner from voter list', (tester) async {
      when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      expect(find.text('Adaptations (2)'), findsOneWidget);
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
      await tester.tap(find.text('Adaptations (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Forked problem A'), findsNothing);
      // Heading (with count) remains visible.
      expect(find.text('Adaptations (1)'), findsOneWidget);
    });

    testWidgets(
      'hides forks section entirely when every fork is identical to parent',
      (tester) async {
        // Two forks, both with identical description/goal/geoscope to the
        // parent. They contribute nothing the viewer can compare or adopt,
        // so the whole section is suppressed.
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => repo.getForksOfProblem(any())).thenAnswer(
          (_) async => [_problem(id: 'fork-a'), _problem(id: 'fork-b')],
        );

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        expect(find.byType(ExpansionTile), findsNothing);
      },
    );

    testWidgets(
      'omits identical forks but keeps the section for differing ones',
      (tester) async {
        when(() => repo.getProblem(any())).thenAnswer((_) async => _problem());
        when(() => repo.getForksOfProblem(any())).thenAnswer(
          (_) async => [
            // Identical to parent — should not render.
            _problem(id: 'fork-identical'),
            // Differs by description — should render and be counted.
            _problem(id: 'fork-diff', description: 'A different description'),
          ],
        );

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // Count reflects only the visible fork; if the identical fork
        // weren't filtered out the heading would read "Adaptations (2)".
        expect(find.text('Adaptations (1)'), findsOneWidget);
        expect(find.text('A different description'), findsOneWidget);
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
      when(() => userCubit.state).thenReturn(
        const UserState(
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
      when(() => userCubit.state).thenReturn(const UserState());

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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
        when(() => userCubit.state).thenReturn(
          const UserState(
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
