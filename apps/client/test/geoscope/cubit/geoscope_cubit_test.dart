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
      'falls back to "/"',
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
            .having((s) => s.selectedGeoscope, 'selectedGeoscope', '/'),
      ],
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize with persisted value matching available uses persisted',
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
            ),
      ],
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize with stale persisted value resolves via suffix match',
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
            ),
      ],
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
        isA<GeoscopeState>().having(
          (s) => s.selectedGeoscope,
          'selectedGeoscope',
          'us/nyc',
        ),
      ],
      verify: (_) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), 'us/nyc');
      },
    );
  });
}
