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
            (id: 'us', label: 'United States', population: 330000000),
            (id: 'us/nyc', label: 'New York City', population: 8500000),
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
          (_) async => [
            (id: 'na/us', label: 'United States', population: 330000000),
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

    group('resolveGeoscope (locale-based defaulting)', () {
      test('locale country code resolves via 1-part exact match', () {
        // e.g. en-US with the `us` superstate present, or en-CA with a
        // top-level `ca` (Canada) row.
        expect(
          GeoscopeCubit.resolveGeoscope(
            persisted: null,
            inferred: 'us',
            availableIds: const {'/', 'us', 'us/ca'},
          ),
          'us',
        );
        expect(
          GeoscopeCubit.resolveGeoscope(
            persisted: null,
            inferred: 'ca',
            availableIds: const {'/', 'ca', 'us', 'us/ca'},
          ),
          'ca',
        );
      });

      test(
        'inferred country code with no 1-part match falls back to a '
        'country-containing superstate (e.g. fr → eu/fr)',
        () {
          expect(
            GeoscopeCubit.resolveGeoscope(
              persisted: null,
              inferred: 'fr',
              availableIds: const {'/', 'eu', 'eu/fr', 'us', 'us/ca'},
            ),
            'eu/fr',
          );
        },
      );

      test(
        'inferred country code does NOT fall back to a subdivision id '
        '(en-CA must not resolve to us/ca / California)',
        () {
          expect(
            GeoscopeCubit.resolveGeoscope(
              persisted: null,
              inferred: 'ca',
              // No top-level `ca`, but `us/ca` (California) is present and
              // would have matched a blind suffix search.
              availableIds: const {'/', 'us', 'us/ca'},
            ),
            '/',
          );
        },
      );

      test('persisted value takes precedence over locale inference', () {
        expect(
          GeoscopeCubit.resolveGeoscope(
            persisted: 'eu/de',
            inferred: 'us',
            availableIds: const {'/', 'us', 'eu', 'eu/de'},
          ),
          'eu/de',
        );
      });

      test(
        'persisted-value suffix match still uses the broad rule '
        '(e.g. us → na/us) — independent of locale',
        () {
          expect(
            GeoscopeCubit.resolveGeoscope(
              persisted: 'us',
              inferred: 'fr',
              availableIds: const {'/', 'na/us', 'eu/fr'},
            ),
            'na/us',
          );
        },
      );
    });

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
