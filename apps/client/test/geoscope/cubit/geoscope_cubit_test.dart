import 'package:bloc_test/bloc_test.dart';
import 'package:client/geoscope/cubit/geoscope_cubit.dart';
import 'package:client/geoscope/cubit/geoscope_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

void main() {
  late FirestoreRepository repo;

  setUp(() {
    repo = _MockFirestoreRepository();
    SharedPreferences.setMockInitialValues({});
  });

  group('GeoscopeCubit', () {
    test('initial state is correct', () {
      final cubit = GeoscopeCubit(repo);
      expect(cubit.state.status, GeoscopeStatus.initial);
      expect(cubit.state.selectedGeoscope, '/');
      expect(cubit.state.availableGeoscopes, isEmpty);
      addTearDown(cubit.close);
    });

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize with no persisted value and no available geoscopes '
      'falls back to "/" and flags needsSelection',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<GeoscopeState>().having(
          (s) => s.status,
          'status',
          GeoscopeStatus.loading,
        ),
        isA<GeoscopeState>()
            .having((s) => s.status, 'status', GeoscopeStatus.success)
            .having((s) => s.selectedGeoscope, 'selectedGeoscope', '/')
            .having((s) => s.needsSelection, 'needsSelection', true),
      ],
      verify: (_) async {
        // The auto-inferred default must NOT be persisted; otherwise the next
        // cold start would think the user had already picked.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), isNull);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize with persisted value matching available uses persisted '
      'and does not flag needsSelection',
      setUp: () {
        SharedPreferences.setMockInitialValues(
          {'selected_geoscope': 'us/nyc'},
        );
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [
            (id: 'us', label: 'United States'),
            (id: 'us/nyc', label: 'New York City'),
          ],
        );
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<GeoscopeState>().having(
          (s) => s.status,
          'status',
          GeoscopeStatus.loading,
        ),
        isA<GeoscopeState>()
            .having((s) => s.status, 'status', GeoscopeStatus.success)
            .having(
              (s) => s.selectedGeoscope,
              'selectedGeoscope',
              'us/nyc',
            )
            .having(
              (s) => s.availableGeoscopes,
              'availableGeoscopes',
              hasLength(2),
            )
            .having((s) => s.needsSelection, 'needsSelection', false),
      ],
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize with stale persisted value resolves via suffix match '
      'and persists the migrated id',
      setUp: () {
        // User had "us" persisted, but hierarchy changed to "na/us".
        SharedPreferences.setMockInitialValues(
          {'selected_geoscope': 'us'},
        );
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [(id: 'na/us', label: 'United States')],
        );
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<GeoscopeState>().having(
          (s) => s.status,
          'status',
          GeoscopeStatus.loading,
        ),
        isA<GeoscopeState>()
            .having((s) => s.status, 'status', GeoscopeStatus.success)
            .having(
              (s) => s.selectedGeoscope,
              'selectedGeoscope',
              'na/us',
            )
            .having((s) => s.needsSelection, 'needsSelection', false),
      ],
      verify: (_) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), 'na/us');
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'acknowledgeSelectionPrompt clears needsSelection without persisting',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) async {
        await cubit.initialize();
        cubit.acknowledgeSelectionPrompt();
      },
      skip: 2,
      expect: () => [
        isA<GeoscopeState>()
            .having((s) => s.needsSelection, 'needsSelection', false)
            .having((s) => s.selectedGeoscope, 'selectedGeoscope', '/'),
      ],
      verify: (_) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), isNull);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'acknowledgeSelectionPrompt is a no-op when needsSelection is false',
      build: () => GeoscopeCubit(repo),
      act: (cubit) => cubit.acknowledgeSelectionPrompt(),
      expect: () => <GeoscopeState>[],
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize emits failure on exception',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenThrow(Exception('network error'));
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<GeoscopeState>().having(
          (s) => s.status,
          'status',
          GeoscopeStatus.loading,
        ),
        isA<GeoscopeState>().having(
          (s) => s.status,
          'status',
          GeoscopeStatus.failure,
        ),
      ],
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectGeoscope emits new state and persists',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) => cubit.selectGeoscope('us/nyc'),
      expect: () => [
        isA<GeoscopeState>()
            .having(
              (s) => s.selectedGeoscope,
              'selectedGeoscope',
              'us/nyc',
            )
            .having((s) => s.needsSelection, 'needsSelection', false),
      ],
      verify: (_) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), 'us/nyc');
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectGeoscope clears needsSelection set by initialize',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
      },
      build: () => GeoscopeCubit(repo),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectGeoscope('us/nyc');
      },
      skip: 2,
      expect: () => [
        isA<GeoscopeState>()
            .having((s) => s.selectedGeoscope, 'selectedGeoscope', 'us/nyc')
            .having((s) => s.needsSelection, 'needsSelection', false),
      ],
    );
  });
}
