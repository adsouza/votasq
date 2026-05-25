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
    List<
          ({
            String id,
            String label,
            int population,
            double? lat,
            double? lng,
          })
        >
        geoscopes =
        const [],
    String selectedGeoscope = '/',
    GeoscopeLocationStatus locationStatus = GeoscopeLocationStatus.idle,
    ({String id, double distanceKm})? locationSuggestion,
    bool locationDenied = false,
  }) {
    when(() => geoscopeCubit.state).thenReturn(
      GeoscopeState(
        availableGeoscopes: geoscopes,
        selectedGeoscope: selectedGeoscope,
        locationStatus: locationStatus,
        locationSuggestion: locationSuggestion,
        locationDenied: locationDenied,
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
      expect(find.textContaining('🌐'), findsOneWidget);
    });

    testWidgets(
      'shows superstates when available',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'in',
                label: 'India',
                population: 1400000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'eu',
                label: 'European Union',
                population: 450000000,
                lat: null,
                lng: null,
              ),
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

        await tester.tap(find.textContaining('🌐'));
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
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
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
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
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
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ny',
                label: 'New York',
                population: 19000000,
                lat: null,
                lng: null,
              ),
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
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              // Megacity — should appear at top level.
              (
                id: 'us/ny/nyc',
                label: 'New York City',
                population: 19000000,
                lat: null,
                lng: null,
              ),
              // Below threshold — should be hidden at top level.
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
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
      'opens drilled into a 1-part non-superstate country '
      '(locale-inferred default like Canada / "ca")',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'ca',
                label: 'Canada',
                population: 38000000,
                lat: null,
                lng: null,
              ),
              // Sub-megacity that would be hidden without a drill-in.
              (
                id: 'ca/toronto',
                label: 'Toronto',
                population: 6700000,
                lat: null,
                lng: null,
              ),
            ],
            // Mimics the cubit's locale resolution for en-CA: an exact-match
            // 1-part id that isn't a superstate.
            selectedGeoscope: 'ca',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        // Sub-region surfaces because the picker drilled in to "ca".
        expect(find.text('Toronto'), findsOneWidget);
        // The filter field is disabled while drilled in.
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.enabled, isFalse);
      },
    );

    testWidgets(
      'population threshold is lifted once a superstate is selected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              // Below 10M — hidden at top level, but visible under "us".
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
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
      'filter field hint text is configured on the sheet',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(
          field.decoration?.hintText,
          'Type partial name of current location here to '
          'narrow down the list.',
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
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              // Sub-megacity metro that would normally be hidden at top level.
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
              // A metro that doesn't match the query.
              (
                id: 'us/ny/nyc',
                label: 'New York City',
                population: 19000000,
                lat: null,
                lng: null,
              ),
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
        expect(find.text('Global regions'), findsNothing);
        expect(find.text('Metro areas'), findsNothing);
      },
    );

    testWidgets(
      'clearing the filter restores the full hierarchical list',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'in',
                label: 'India',
                population: 1400000000,
                lat: null,
                lng: null,
              ),
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
      'filter field is disabled when a superstate is selected and '
      're-enabled when deselected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
            ],
            // Opens the picker already drilled into the "us" superstate.
            selectedGeoscope: 'us',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        TextField findField() =>
            tester.widget<TextField>(find.byType(TextField));
        expect(findField().enabled, isFalse);

        // Tapping the active superstate clears the drill-in and brings the
        // selection back to global, which should re-enable the filter.
        await tester.tap(find.text('United States'));
        await tester.pumpAndSettle();
        expect(findField().enabled, isTrue);
      },
    );

    testWidgets(
      'filter field is disabled when a state is selected and '
      're-enabled when deselected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              // Non-superstate country so the country row appears in the
              // States section even with no superstate selected.
              (
                id: 'mx/mexico-city',
                label: 'Mexico City',
                population: 22000000,
                lat: null,
                lng: null,
              ),
            ],
            selectedGeoscope: 'mx/mexico-city',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        TextField findField() =>
            tester.widget<TextField>(find.byType(TextField));
        expect(findField().enabled, isFalse);

        // Tapping the active state collapses the drill-in.
        await tester.tap(find.text('mx'));
        await tester.pumpAndSettle();
        expect(findField().enabled, isTrue);
      },
    );

    testWidgets(
      'tapping a filtered leaf result selects that geoscope and closes '
      'the sheet',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
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
        // SF Bay Area has no children in this fixture, so the sheet closes.
        expect(find.byType(TextField), findsNothing);
      },
    );

    testWidgets(
      'tapping a filtered superstate drills in instead of dismissing',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'united');
        await tester.pumpAndSettle();
        await tester.tap(find.text('United States'));
        await tester.pumpAndSettle();

        verify(() => geoscopeCubit.selectGeoscope('us')).called(1);
        // Sheet still open: TextField still present.
        expect(find.byType(TextField), findsOneWidget);
        // The drill-in surfaces "California" (the state under "us") which
        // was not visible at the top level before.
        expect(find.text('California'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a filtered state with metros drills in to its metros',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
              // Sub-megacity metro that wouldn't show without drill-in.
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
            ],
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'cali');
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        verify(() => geoscopeCubit.selectGeoscope('us/ca')).called(1);
        // Sheet still open.
        expect(find.byType(TextField), findsOneWidget);
        // California's metros are now reachable.
        expect(find.text('SF Bay Area'), findsOneWidget);
      },
    );

    testWidgets(
      'superstates section heading is visible but collapsed when a state is '
      'selected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
            ],
            selectedGeoscope: 'us/ca',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        // The state (California) and its metro areas are visible.
        expect(find.text('California'), findsOneWidget);
        expect(find.text('SF Bay Area'), findsOneWidget);

        // Superstates heading is visible, but list items are hidden/collapsed.
        expect(find.text('Global regions'), findsOneWidget);
        expect(find.text('United States'), findsNothing);
      },
    );

    testWidgets(
      'superstates section is expanded when no state is selected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
            ],
            selectedGeoscope: 'us',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        // No state is selected (only superstate is selected).
        // Superstates heading and items are visible.
        expect(find.text('Global regions'), findsOneWidget);
        expect(find.text('United States'), findsOneWidget);
      },
    );

    testWidgets(
      'superstates section expands automatically when a selected state is '
      'deselected',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
            ],
            selectedGeoscope: 'us/ca',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        // Superstates heading is visible but list items are collapsed.
        expect(find.text('Global regions'), findsOneWidget);
        expect(find.text('United States'), findsNothing);

        // Deselect the state by tapping on California again.
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Superstates list items are now automatically expanded.
        expect(find.text('United States'), findsOneWidget);
      },
    );

    testWidgets(
      'user can manually toggle the superstates section by tapping the heading',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us',
                label: 'United States',
                population: 330000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca',
                label: 'California',
                population: 39000000,
                lat: null,
                lng: null,
              ),
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: null,
                lng: null,
              ),
            ],
            selectedGeoscope: 'us/ca',
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        // Initially collapsed due to active state.
        expect(find.text('United States'), findsNothing);

        // Tap the heading to manually expand it.
        await tester.tap(find.text('Global regions'));
        await tester.pumpAndSettle();

        // Now expanded.
        expect(find.text('United States'), findsOneWidget);

        // Tap the heading again to manually collapse it.
        await tester.tap(find.text('Global regions'));
        await tester.pumpAndSettle();

        // Collapsed again.
        expect(find.text('United States'), findsNothing);
      },
    );
  });

  group('Use my location row', () {
    testWidgets('shows "Use my location" row by default', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();
      expect(find.text('Use my location'), findsOneWidget);
    });

    testWidgets('hides the row when locationDenied is true', (tester) async {
      await tester.pumpWidget(buildSubject(locationDenied: true));
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();
      expect(find.text('Use my location'), findsNothing);
    });

    testWidgets(
      'shows spinner when locationStatus is fetching',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(locationStatus: GeoscopeLocationStatus.fetching),
        );
        await tester.tap(find.text('Open Picker'));
        // The spinner animates indefinitely, so pumpAndSettle would time
        // out — pump a single frame past the sheet's open transition.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'shows suggestion row with metro label and distance',
      (tester) async {
        when(() => geoscopeCubit.acceptLocationSuggestion()).thenAnswer(
          (_) async {},
        );
        when(() => geoscopeCubit.dismissLocationSuggestion()).thenReturn(null);
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: 37.7793,
                lng: -122.4193,
              ),
            ],
            locationSuggestion: (id: 'us/ca/sfbay', distanceKm: 183.4),
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();
        expect(find.text('SF Bay Area'), findsAtLeastNWidgets(1));
        expect(find.textContaining('183 km'), findsOneWidget);
        expect(find.text('Use'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Use my location" calls selectNearestMetroFromLocation',
      (tester) async {
        when(() => geoscopeCubit.selectNearestMetroFromLocation()).thenAnswer(
          (_) async {},
        );
        await tester.pumpWidget(buildSubject());
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use my location'));
        await tester.pumpAndSettle();
        verify(() => geoscopeCubit.selectNearestMetroFromLocation()).called(1);
      },
    );

    testWidgets(
      'tapping Use on the suggestion calls acceptLocationSuggestion',
      (tester) async {
        when(() => geoscopeCubit.acceptLocationSuggestion()).thenAnswer(
          (_) async {},
        );
        await tester.pumpWidget(
          buildSubject(
            geoscopes: [
              (
                id: 'us/ca/sfbay',
                label: 'SF Bay Area',
                population: 7700000,
                lat: 37.7793,
                lng: -122.4193,
              ),
            ],
            locationSuggestion: (id: 'us/ca/sfbay', distanceKm: 183.4),
          ),
        );
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use'));
        await tester.pumpAndSettle();
        verify(() => geoscopeCubit.acceptLocationSuggestion()).called(1);
      },
    );
  });
}
