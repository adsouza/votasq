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
    List<({String id, String label})> geoscopes = const [],
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
              (id: 'us', label: 'United States'),
              (id: 'in', label: 'India'),
              (id: 'eu', label: 'European Union'),
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
              (id: 'us', label: 'United States'),
              (id: 'us/ca', label: 'California'),
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
              (id: 'us', label: 'United States'),
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
              (id: 'us', label: 'United States'),
              (id: 'us/ca', label: 'California'),
              (id: 'us/ny', label: 'New York'),
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
  });
}
