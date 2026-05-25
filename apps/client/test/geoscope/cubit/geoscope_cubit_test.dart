import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:client/geoscope/cubit/geoscope_cubit.dart';
import 'package:client/geoscope/cubit/geoscope_state.dart';
import 'package:client/geoscope/location_service.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _FakeLocationService implements LocationService {
  LocationOutcome _outcome = const LocationUnavailable();

  /// If non-null, future returned by [getApproximateLocation] never completes.
  Completer<LocationOutcome>? _hang;

  /// If non-zero, delay before completing with [_outcome].
  Duration _delay = Duration.zero;

  /// What [hasPermission] returns. Independent of [_outcome] because the
  /// reconciliation logic in initialize() checks this without triggering
  /// a full lookup.
  bool _hasPermission = false;

  // Test-only setter; no getter needed since the field is read internally.
  // ignore: avoid_setters_without_getters
  set outcome(LocationOutcome value) => _outcome = value;

  // Test-only setter; the field is read internally by `hasPermission`.
  // ignore: avoid_setters_without_getters
  set hasPermissionResult(bool value) => _hasPermission = value;

  /// Make the next call to [getApproximateLocation] hang forever.
  void hangNext() => _hang = Completer<LocationOutcome>();

  /// Delay the next outcome by [d] before completing.
  // ignore: use_setters_to_change_properties
  void delayBy(Duration d) => _delay = d;

  @override
  Future<LocationOutcome> getApproximateLocation() async {
    if (_hang != null) return _hang!.future;
    if (_delay > Duration.zero) await Future<void>.delayed(_delay);
    return _outcome;
  }

  @override
  Future<bool> hasPermission() async => _hasPermission;
}

void main() {
  late FirestoreRepository repo;
  late _FakeLocationService locationService;

  setUp(() {
    repo = _MockFirestoreRepository();
    locationService = _FakeLocationService();
    SharedPreferences.setMockInitialValues({});
  });

  group('GeoscopeCubit', () {
    test('initial state is correct', () {
      final cubit = GeoscopeCubit(repo, locationService);
      expect(cubit.state.status, GeoscopeStatus.initial);
      expect(cubit.state.selectedGeoscope, '/');
      expect(cubit.state.availableGeoscopes, isEmpty);
      expect(cubit.state.locationStatus, GeoscopeLocationStatus.idle);
      expect(cubit.state.locationSuggestion, isNull);
      expect(cubit.state.pendingToast, isNull);
      expect(cubit.state.locationDenied, isFalse);
      addTearDown(cubit.close);
    });

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize with no persisted value and no available geoscopes '
      'falls back to "/" and flags needsSelection',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
      },
      build: () => GeoscopeCubit(repo, locationService),
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
            (
              id: 'us',
              label: 'United States',
              population: 330000000,
              lat: null,
              lng: null,
            ),
            (
              id: 'us/nyc',
              label: 'New York City',
              population: 8500000,
              lat: null,
              lng: null,
            ),
          ],
        );
      },
      build: () => GeoscopeCubit(repo, locationService),
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
            (
              id: 'na/us',
              label: 'United States',
              population: 330000000,
              lat: null,
              lng: null,
            ),
          ],
        );
      },
      build: () => GeoscopeCubit(repo, locationService),
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
      'initialize keeps locationDenied=true when OS also reports no permission',
      setUp: () {
        SharedPreferences.setMockInitialValues({
          'geoscope_location_denied': true,
        });
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
        locationService.hasPermissionResult = false;
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) => cubit.initialize(),
      verify: (cubit) async {
        expect(cubit.state.locationDenied, true);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('geoscope_location_denied'), true);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize clears stale locationDenied=true when OS now grants '
      '(reconcile false-denial / user-granted-via-settings)',
      setUp: () {
        SharedPreferences.setMockInitialValues({
          'geoscope_location_denied': true,
        });
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
        // OS reports permission as granted despite the persisted flag.
        // This is the macOS race-condition scenario AND the case where
        // the user later granted access via system settings.
        locationService.hasPermissionResult = true;
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) => cubit.initialize(),
      verify: (cubit) async {
        expect(cubit.state.locationDenied, false);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('geoscope_location_denied'), false);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize defaults locationDenied to false when key absent',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<GeoscopeState>().having(
          (s) => s.status,
          'status',
          GeoscopeStatus.loading,
        ),
        isA<GeoscopeState>()
            .having((s) => s.status, 'status', GeoscopeStatus.success)
            .having((s) => s.locationDenied, 'locationDenied', false),
      ],
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'acknowledgeSelectionPrompt clears needsSelection without persisting',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
      },
      build: () => GeoscopeCubit(repo, locationService),
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
      build: () => GeoscopeCubit(repo, locationService),
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
      build: () => GeoscopeCubit(repo, locationService),
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
      build: () => GeoscopeCubit(repo, locationService),
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
      build: () => GeoscopeCubit(repo, locationService),
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

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectNearestMetroFromLocation: coords within 100 km auto-selects',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [
            (
              id: 'us/ca/sfbay',
              label: 'SF Bay Area',
              population: 7700000,
              lat: 37.7793,
              lng: -122.4193,
            ),
          ],
        );
        // Query coords ~5 km from the SF Bay centroid: well inside 100.
        locationService.outcome = const LocationCoords(37.83, -122.42);
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
      },
      verify: (cubit) async {
        expect(cubit.state.selectedGeoscope, 'us/ca/sfbay');
        expect(cubit.state.locationStatus, GeoscopeLocationStatus.idle);
        expect(cubit.state.locationSuggestion, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), 'us/ca/sfbay');
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectNearestMetroFromLocation: coords outside 100 km emits suggestion',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [
            (
              id: 'us/ca/sfbay',
              label: 'SF Bay Area',
              population: 7700000,
              lat: 37.7793,
              lng: -122.4193,
            ),
          ],
        );
        // Reno-ish coords (~330 km from SF). Outside threshold.
        locationService.outcome = const LocationCoords(39.53, -119.81);
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
      },
      verify: (cubit) {
        expect(cubit.state.selectedGeoscope, '/'); // unchanged from init
        expect(cubit.state.locationStatus, GeoscopeLocationStatus.idle);
        expect(cubit.state.locationSuggestion, isNotNull);
        expect(cubit.state.locationSuggestion!.id, 'us/ca/sfbay');
        expect(cubit.state.locationSuggestion!.distanceKm, greaterThan(100));
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectNearestMetroFromLocation: denial persists flag and emits toast',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
        locationService.outcome = const LocationDenied();
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
      },
      verify: (cubit) async {
        expect(cubit.state.locationDenied, true);
        expect(cubit.state.pendingToast, GeoscopeToast.denied);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('geoscope_location_denied'), true);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectNearestMetroFromLocation: unavailable emits toast but no persist',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
        locationService.outcome = const LocationUnavailable();
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
      },
      verify: (cubit) async {
        expect(cubit.state.locationDenied, false);
        expect(cubit.state.pendingToast, GeoscopeToast.unavailable);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('geoscope_location_denied'), isNull);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'acceptLocationSuggestion selects the suggested id and clears suggestion',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [
            (
              id: 'us/ca/sfbay',
              label: 'SF Bay Area',
              population: 7700000,
              lat: 37.7793,
              lng: -122.4193,
            ),
          ],
        );
        locationService.outcome = const LocationCoords(39.53, -119.81);
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
        await cubit.acceptLocationSuggestion();
      },
      verify: (cubit) {
        expect(cubit.state.selectedGeoscope, 'us/ca/sfbay');
        expect(cubit.state.locationSuggestion, isNull);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'dismissLocationSuggestion clears suggestion without selecting',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [
            (
              id: 'us/ca/sfbay',
              label: 'SF Bay Area',
              population: 7700000,
              lat: 37.7793,
              lng: -122.4193,
            ),
          ],
        );
        locationService.outcome = const LocationCoords(39.53, -119.81);
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
        cubit.dismissLocationSuggestion();
      },
      verify: (cubit) {
        expect(cubit.state.selectedGeoscope, '/'); // unchanged
        expect(cubit.state.locationSuggestion, isNull);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'clearPendingToast clears the toast field',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
        locationService.outcome = const LocationUnavailable();
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        await cubit.selectNearestMetroFromLocation();
        cubit.clearPendingToast();
      },
      verify: (cubit) {
        expect(cubit.state.pendingToast, isNull);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectNearestMetroFromLocation: re-entry while fetching is a no-op',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
        locationService.hangNext();
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        // Fire twice in rapid succession; the second call should bail
        // immediately at the fetching guard.
        unawaited(cubit.selectNearestMetroFromLocation());
        await cubit.selectNearestMetroFromLocation();
      },
      verify: (cubit) {
        // Still fetching — neither call resolved (the first is hung on
        // the never-outcome, the second bailed at the guard).
        expect(cubit.state.locationStatus, GeoscopeLocationStatus.fetching);
      },
    );

    blocTest<GeoscopeCubit, GeoscopeState>(
      'selectNearestMetroFromLocation: manual selection during await wins',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
        when(() => repo.getGeoscopes()).thenAnswer(
          (_) async => [
            (
              id: 'us/ca/sfbay',
              label: 'SF Bay Area',
              population: 7700000,
              lat: 37.7793,
              lng: -122.4193,
            ),
            (
              id: 'us/ny/nyc',
              label: 'New York City',
              population: 19200000,
              lat: 40.7128,
              lng: -74.0060,
            ),
          ],
        );
        // Coords would normally auto-select sfbay — but the test
        // manually selects something else during the await.
        locationService
          ..outcome = const LocationCoords(37.83, -122.42)
          ..delayBy(const Duration(milliseconds: 50));
      },
      build: () => GeoscopeCubit(repo, locationService),
      act: (cubit) async {
        await cubit.initialize();
        final lookup = cubit.selectNearestMetroFromLocation();
        // While the lookup is pending, user manually picks something
        // distinct from both the initial value ('/') and the
        // auto-select target ('us/ca/sfbay').
        await cubit.selectGeoscope('us/ny/nyc');
        await lookup;
      },
      verify: (cubit) async {
        // Manual choice wins; auto-select didn't clobber it.
        expect(cubit.state.selectedGeoscope, 'us/ny/nyc');
        expect(cubit.state.locationStatus, GeoscopeLocationStatus.idle);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_geoscope'), 'us/ny/nyc');
      },
    );
  });

  group('findNearestMetro', () {
    // Known pairs sourced from public references; tolerances reflect the
    // imprecision of "city centre" coords, not floating-point.
    test('returns the only metro when one is given', () {
      final result = GeoscopeCubit.findNearestMetro(
        lat: 37.7793,
        lng: -122.4193,
        available: const [
          (
            id: 'us/ca/sfbay',
            label: 'SF Bay Area',
            population: 7700000,
            lat: 37.7793,
            lng: -122.4193,
          ),
        ],
      );
      expect(result, isNotNull);
      expect(result!.id, 'us/ca/sfbay');
      expect(result.distanceKm, closeTo(0, 0.01));
    });

    test('returns the closer of two metros', () {
      // Querying from London — Paris (~344 km) should beat NYC (~5570 km).
      final result = GeoscopeCubit.findNearestMetro(
        lat: 51.5074,
        lng: -0.1278,
        available: const [
          (
            id: 'eu/fr/par',
            label: 'Paris',
            population: 14000000,
            lat: 48.8566,
            lng: 2.3522,
          ),
          (
            id: 'us/ny/nyc',
            label: 'NYC',
            population: 19200000,
            lat: 40.7128,
            lng: -74.0060,
          ),
        ],
      );
      expect(result, isNotNull);
      expect(result!.id, 'eu/fr/par');
      expect(result.distanceKm, closeTo(344, 30));
    });

    test('computes SF→NYC distance to about 4130 km', () {
      final result = GeoscopeCubit.findNearestMetro(
        lat: 37.7793,
        lng: -122.4193,
        available: const [
          (
            id: 'us/ny/nyc',
            label: 'NYC',
            population: 19200000,
            lat: 40.7128,
            lng: -74.0060,
          ),
        ],
      );
      expect(result, isNotNull);
      expect(result!.distanceKm, closeTo(4130, 50));
    });

    test('skips rows with null lat or lng', () {
      final result = GeoscopeCubit.findNearestMetro(
        lat: 37.7793,
        lng: -122.4193,
        available: const [
          (
            id: 'eu',
            label: 'European Union',
            population: 430000000,
            lat: null,
            lng: null,
          ),
          (
            id: 'us/ca/sfbay',
            label: 'SF Bay Area',
            population: 7700000,
            lat: 37.7793,
            lng: -122.4193,
          ),
        ],
      );
      expect(result, isNotNull);
      expect(result!.id, 'us/ca/sfbay');
    });

    test('returns null when no rows have coords', () {
      final result = GeoscopeCubit.findNearestMetro(
        lat: 0,
        lng: 0,
        available: const [
          (
            id: 'eu',
            label: 'European Union',
            population: 430000000,
            lat: null,
            lng: null,
          ),
        ],
      );
      expect(result, isNull);
    });
  });
}
