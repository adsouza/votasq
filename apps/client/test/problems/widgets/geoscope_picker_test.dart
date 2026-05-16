import 'package:bloc_test/bloc_test.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/geoscope_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGeoscopeCubit extends MockCubit<GeoscopeState>
    implements GeoscopeCubit {}

void main() {
  late GeoscopeCubit geoscopeCubit;

  setUp(() {
    geoscopeCubit = _MockGeoscopeCubit();
    when(() => geoscopeCubit.selectGeoscope(any())).thenAnswer((_) async {});
  });

  Widget buildSubject({
    List<({String id, String label, int population})> geoscopes = const [],
    String selectedGeoscope = '/',
  }) {
    when(() => geoscopeCubit.state).thenReturn(
      GeoscopeState(
        availableGeoscopes: geoscopes,
        selectedGeoscope: selectedGeoscope,
      ),
    );
    return BlocProvider<GeoscopeCubit>.value(
      value: geoscopeCubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showGeoscopePicker(context),
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );
  }

  group('showGeoscopePicker', () {
    testWidgets('shows global option', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Global option should be visible.
      expect(find.textContaining('Global'), findsOneWidget);
    });

    testWidgets(
      'shows superstates when available',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              (id: 'in', label: 'India', population: 1400000000),
              (id: 'eu', label: 'European Union', population: 450000000),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        expect(find.text('United States'), findsOneWidget);
        expect(find.text('India'), findsOneWidget);
        expect(find.text('European Union'), findsOneWidget);
      },
    );

    testWidgets(
      'selecting global calls selectGeoscope with /',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Global'));
        await tester.pumpAndSettle();

        verify(() => geoscopeCubit.selectGeoscope('/')).called(1);
      },
    );

    testWidgets(
      'selecting superstate calls selectGeoscope',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              (id: 'us/ca', label: 'California', population: 39000000),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('United States'));
        await tester.pumpAndSettle();

        verify(
          () => geoscopeCubit.selectGeoscope('us'),
        ).called(1);
      },
    );

    testWidgets(
      'shows check mark for active geoscope',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
            ],
            selectedGeoscope: 'us',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        // Check mark for the active geoscope.
        expect(find.byIcon(Icons.check), findsOneWidget);
      },
    );

    testWidgets(
      'shows states when superstate is expanded',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              (id: 'us/ca', label: 'California', population: 39000000),
              (id: 'us/ny', label: 'New York', population: 19000000),
            ],
            selectedGeoscope: 'us',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        expect(find.text('California'), findsOneWidget);
        expect(find.text('New York'), findsOneWidget);
      },
    );

    testWidgets(
      'top-level metro list hides metros under 10M population',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              // Megacity — should appear at top level.
              (id: 'us/ny/nyc', label: 'New York City', population: 19000000),
              // Below threshold — should be hidden at top level.
              (id: 'us/ca/sfbay', label: 'SF Bay Area', population: 7700000),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        expect(find.text('New York City'), findsOneWidget);
        expect(find.text('SF Bay Area'), findsNothing);
      },
    );

    testWidgets(
      'population threshold is lifted once a superstate is selected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              // Below 10M — hidden at top level, but visible under "us".
              (id: 'us/ca/sfbay', label: 'SF Bay Area', population: 7700000),
            ],
            selectedGeoscope: 'us',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        expect(find.text('SF Bay Area'), findsOneWidget);
      },
    );

    testWidgets(
      'filter field hint text is shown at the top of the sheet',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Type partial name of current location here to '
            'narrow down the list',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'typing a substring filters the list across sections and bypasses '
      'the population threshold',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              // Superstate.
              (id: 'us', label: 'United States', population: 330000000),
              // Sub-megacity metro that would normally be hidden at top level.
              (id: 'us/ca/sfbay', label: 'SF Bay Area', population: 7700000),
              // A metro that doesn't match the query.
              (id: 'us/ny/nyc', label: 'New York City', population: 19000000),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'sf');
        await tester.pumpAndSettle();

        // Matches across the (formerly) hidden metro tier — case-insensitive.
        expect(find.text('SF Bay Area'), findsOneWidget);
        // Non-matching entries are filtered out.
        expect(find.text('United States'), findsNothing);
        expect(find.text('New York City'), findsNothing);
        // Section headers don't render while filtering.
        expect(find.text('Superstates'), findsNothing);
        expect(find.text('Metro areas'), findsNothing);
      },
    );

    testWidgets(
      'clearing the filter restores the full hierarchical list',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              (id: 'in', label: 'India', population: 1400000000),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'india');
        await tester.pumpAndSettle();
        expect(find.text('United States'), findsNothing);

        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.text('United States'), findsOneWidget);
        expect(find.text('India'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a filtered result selects that geoscope and closes the sheet',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (id: 'us', label: 'United States', population: 330000000),
              (id: 'us/ca/sfbay', label: 'SF Bay Area', population: 7700000),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'bay');
        await tester.pumpAndSettle();
        await tester.tap(find.text('SF Bay Area'));
        await tester.pumpAndSettle();

        verify(() => geoscopeCubit.selectGeoscope('us/ca/sfbay')).called(1);
      },
    );
  });
}
