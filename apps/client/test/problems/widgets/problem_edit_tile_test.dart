import 'package:bloc_test/bloc_test.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/problem_edit_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockGeoscopeCubit extends MockCubit<GeoscopeState>
    implements GeoscopeCubit {}

Problem _problem({
  String id = 'p1',
  String description = 'A test problem description that is long enough',
  String goal = 'A test goal',
  String ownerId = 'owner1',
  String geoscope = '/',
}) {
  final now = DateTime.utc(2024);
  return Problem(
    id: id,
    description: description,
    goal: goal,
    ownerId: ownerId,
    geoscope: geoscope,
    createdAt: now,
    lastUpdatedAt: now,
  );
}

void main() {
  late GeoscopeCubit geoscopeCubit;
  late bool cancelCalled;
  late List<Problem> submittedProblems;

  setUp(() {
    geoscopeCubit = _MockGeoscopeCubit();
    cancelCalled = false;
    submittedProblems = [];

    when(() => geoscopeCubit.state).thenReturn(
      const GeoscopeState(),
    );
  });

  Widget buildSubject({Problem? problem}) {
    return BlocProvider<GeoscopeCubit>.value(
      value: geoscopeCubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProblemEditTile(
            problem: problem ?? _problem(),
            tapRegionGroupId: 'test',
            onCancel: () => cancelCalled = true,
            onSubmit: (p, {required userLanguage}) async {
              submittedProblems.add(p);
            },
          ),
        ),
      ),
    );
  }

  group('ProblemEditTile', () {
    testWidgets('renders with problem text', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A test problem description that is long enough',
        ),
        findsOneWidget,
      );
      expect(find.text('A test goal'), findsOneWidget);
    });

    testWidgets(
      'submit button is disabled when description is too short',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            problem: _problem(description: 'hi'),
          ),
        );
        await tester.pumpAndSettle();

        // Clear and type short text.
        final descField = find.byType(TextField).first;
        await tester.tap(descField);
        await tester.enterText(descField, 'hi');
        await tester.pump();

        // Check button is disabled.
        final button = tester.widget<TextButton>(
          find.byType(TextButton),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'submit button is enabled when description has enough words',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // The default problem has enough words.
        final button = tester.widget<TextButton>(
          find.byType(TextButton),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('calls onCancel when cancel triggered', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Tap outside the TapRegion to trigger cancel.
      await tester.tapAt(Offset.zero);
      await tester.pump();

      expect(cancelCalled, isTrue);
    });

    testWidgets(
      'calls onSubmit with updated problem on save',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // Modify the description.
        final descField = find.byType(TextField).first;
        await tester.enterText(
          descField,
          'Updated description that has enough words to pass',
        );
        await tester.pump();

        // Tap the submit button.
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        expect(submittedProblems, hasLength(1));
        expect(
          submittedProblems.first.description,
          'Updated description that has enough words to pass',
        );
      },
    );

    testWidgets(
      'does not call onSubmit when nothing changed',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        // Tap submit without changing anything.
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        // onCancel is called instead since nothing changed.
        expect(submittedProblems, isEmpty);
        expect(cancelCalled, isTrue);
      },
    );
  });
}
