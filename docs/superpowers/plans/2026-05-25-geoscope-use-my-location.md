# "Use my location" in geoscope picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users tap "Use my location" in the geoscope picker to snap to the nearest known metro using the device's coarse location. Persist denial so the button stops being offered once refused.

**Architecture:** Client-side nearest-neighbor (Haversine) against ~50 metro centroids stored in the existing Firestore `geoscopes` collection. New `LocationService` abstraction wraps `geolocator`; `GeoscopeCubit` orchestrates state transitions. UI changes confined to `geoscope_picker.dart`. No server, callable functions, or shared-model changes.

**Tech Stack:** Flutter + Dart, BLoC, `geolocator` package (new), `cloud_firestore`, `shared_preferences`, `toastification` (already present), `googleapis/firestore/v1` for the backfill tool.

**Spec:** [`docs/superpowers/specs/2026-05-25-geoscope-use-my-location-design.md`](../specs/2026-05-25-geoscope-use-my-location-design.md)

---

## File Structure

**Created:**
- `apps/client/lib/geoscope/location_service.dart` — `LocationService` abstraction + `geolocator`-backed default impl.
- `apps/server/tool/seed_geoscope_coords.dart` — one-shot backfill writer (emulator + prod).

**Modified:**
- `apps/client/lib/services/firestore_repository.dart` — `getGeoscopes()` reads new lat/lng fields.
- `apps/client/lib/geoscope/cubit/geoscope_state.dart` — new state fields.
- `apps/client/lib/geoscope/cubit/geoscope_cubit.dart` — `findNearestMetro` helper + `selectNearestMetroFromLocation` orchestration + `acceptLocationSuggestion` / `dismissLocationSuggestion` / `clearPendingToast`. Constructor takes a `LocationService`.
- `apps/client/lib/app/view/app.dart` — pass `LocationService` to `GeoscopeCubit`.
- `apps/client/lib/problems/widgets/geoscope_picker.dart` — new "Use my location" row + suggestion mode + denial-hide + toast listener.
- `apps/client/lib/l10n/arb/app_*.arb` × 24 — four new keys.
- `apps/client/pubspec.yaml` — add `geolocator`.
- `apps/client/ios/Runner/Info.plist` — `NSLocationWhenInUseUsageDescription`.
- `apps/client/macos/Runner/Info.plist` — same usage description (file may need creating if it doesn't define one yet).
- `apps/client/macos/Runner/DebugProfile.entitlements`, `Release.entitlements` — location entitlement.
- `apps/client/android/app/src/main/AndroidManifest.xml` — `ACCESS_COARSE_LOCATION`.

**Test files modified/created:**
- `apps/client/test/services/firestore_repository_test.dart` — extend `getGeoscopes` group.
- `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart` — extend with new groups for `findNearestMetro`, `selectNearestMetroFromLocation`, initialize-with-denied-flag.
- `apps/client/test/problems/widgets/geoscope_picker_test.dart` — extend with location-row tests.

---

## Execution Order

**This supersedes the in-document task numbering below.** Tasks remain documented in their original order to keep cross-references stable, but the executor must follow this sequence:

| # | Task ref in doc | What |
|---|---|---|
| 1 | Task 10 | Build the backfill tool (`seed_geoscope_coords.dart`), curated coords, `--dry-run` sanity. |
| 2 | Task 12 (steps 1–4 only) | Start emulator, seed geoscopes from prod, run backfill against emulator, verify a sample doc has `lat`/`lng`. |
| 3 | Task 13 | **User-gated.** Run backfill against production. Spot-check 2–3 docs via the Firebase MCP. |
| 4 | Task 1 | Extend `getGeoscopes` to read lat/lng (read-side trap test). |
| 5 | Task 2 | Extend `GeoscopeState` with new fields. |
| 6 | Task 3 | Add `geolocator` dependency. |
| 7 | Task 4 | Create `LocationService` abstraction. |
| 8 | Task 5 | Implement `findNearestMetro` (pure static helper). |
| 9 | Task 6 | Wire `LocationService` into `GeoscopeCubit` + extend `initialize`. |
| 10 | Task 7 | Cubit orchestration methods. |
| 11 | Task 8 | Add ARB strings in all 24 locales. |
| 12 | Task 9 | Platform manifest updates (iOS / Android / macOS). |
| 13 | Task 11 | Picker UI changes. |
| 14 | Task 12 (steps 5–7 only) | UI smoke-test: launch the app against the emulator, verify the new row, the suggestion flow, and the denial-hide flow. |
| 15 | Task 14 | Final verification (`melos format`, `flutter analyze`, full test suite). |

**Rationale for this order:**

- Backfill data lands first. Once metro docs in prod have `lat`/`lng`, old clients ignore the new fields (no breakage), and the client work can be developed and tested against real data without further redeployments.
- If the curated coords need fixing after the client UI is built and exercised, that's a one-line tool change and a re-run of Task 13 — cheaper than rolling client code.
- The two halves of Task 12 (data verify before client code, UI smoke-test after) are explicit gates: each runs at the right point in the sequence.

## Conventions

- **TDD:** write a failing test, see it fail, write the smallest impl that makes it pass, see it pass, commit. Never combine those into one commit.
- **Commit prefix:** `feat(client):` for client work, `feat(server):` for the backfill tool, `chore:` for ARBs and platform manifests. End every commit message body with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Format check after every code change:** `melos format` (NOT `dart format apps packages` — see CLAUDE.md gotcha about vendored SwiftPM dirs).
- **Analyze after every step that compiles:** `flutter analyze apps packages`.

---

## Task 1: Extend `getGeoscopes` to read lat/lng (read-side trap test)

This task lands the read-side change first, with a failing test that guards against the silent-drop trap from CLAUDE.md (`_docToProblem`-style bug). The record type change ripples through compile errors that subsequent tasks fix.

**Files:**
- Modify: `apps/client/lib/services/firestore_repository.dart:613-632` (the `getGeoscopes` method)
- Modify test: `apps/client/test/services/firestore_repository_test.dart:832-859`

- [ ] **Step 1: Write the failing test**

Open `apps/client/test/services/firestore_repository_test.dart` and replace the contents of the `group('getGeoscopes', ...)` block (lines 832-859) with:

```dart
    group('getGeoscopes', () {
      test(
        'returns geoscopes sorted by population descending',
        () async {
          await firestore.collection('geoscopes').doc('us').set({
            'id': 'us',
            'label': 'United States',
            'population': 330000000,
          });
          await firestore.collection('geoscopes').doc('in').set({
            'id': 'in',
            'label': 'India',
            'population': 1400000000,
          });
          await firestore.collection('geoscopes').doc('uk').set({
            'id': 'uk',
            'label': 'United Kingdom',
            'population': 67000000,
          });

          final geoscopes = await repo.getGeoscopes();
          expect(geoscopes, hasLength(3));
          expect(geoscopes[0].label, 'India');
          expect(geoscopes[1].label, 'United States');
          expect(geoscopes[2].label, 'United Kingdom');
        },
      );

      test(
        'reads lat and lng from metro docs',
        () async {
          await firestore.collection('geoscopes').doc('sfbay').set({
            'id': 'us/ca/sfbay',
            'label': 'SF Bay Area',
            'population': 7700000,
            'lat': 37.7793,
            'lng': -122.4193,
          });

          final geoscopes = await repo.getGeoscopes();
          expect(geoscopes, hasLength(1));
          expect(geoscopes[0].lat, closeTo(37.7793, 1e-6));
          expect(geoscopes[0].lng, closeTo(-122.4193, 1e-6));
        },
      );

      test(
        'returns null lat and lng for docs without coords',
        () async {
          await firestore.collection('geoscopes').doc('eu').set({
            'id': 'eu',
            'label': 'European Union',
            'population': 430000000,
          });

          final geoscopes = await repo.getGeoscopes();
          expect(geoscopes, hasLength(1));
          expect(geoscopes[0].lat, isNull);
          expect(geoscopes[0].lng, isNull);
        },
      );
    });
```

- [ ] **Step 2: Run tests to verify the two new tests fail to compile**

Run: `cd apps/client && very_good test test/services/firestore_repository_test.dart --no-optimization`
Expected: compile error like `The getter 'lat' isn't defined for the type ...` and `The getter 'lng' isn't defined for the type ...`. The existing sort test should still pass once the impl compiles.

- [ ] **Step 3: Update the record type and the read path in `firestore_repository.dart`**

Modify `apps/client/lib/services/firestore_repository.dart` lines 613-632 to:

```dart
  /// Fetch available geoscopes from the `geoscopes` collection,
  /// sorted by population descending.
  Future<
    List<
      ({
        String id,
        String label,
        int population,
        double? lat,
        double? lng,
      })
    >
  >
  getGeoscopes() async {
    final snapshot = await _firestore.collection('geoscopes').get();
    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final popA = (a.data()['population'] as num?) ?? 0;
        final popB = (b.data()['population'] as num?) ?? 0;
        return popB.compareTo(popA);
      });
    return docs.map((doc) {
      final data = doc.data();
      return (
        id: data['id'] as String? ?? doc.id,
        label: data['label'] as String? ?? doc.id,
        population: ((data['population'] as num?) ?? 0).toInt(),
        lat: (data['lat'] as num?)?.toDouble(),
        lng: (data['lng'] as num?)?.toDouble(),
      );
    }).toList();
  }
```

Note: the return type changes — this will cause compile errors elsewhere in the code that constructs the record type. The following tasks fix those.

- [ ] **Step 4: Run the repo test to verify the new tests pass**

Run: `cd apps/client && very_good test test/services/firestore_repository_test.dart --no-optimization`
Expected: all three tests in `group('getGeoscopes', ...)` pass. Other tests in the file should also still pass.

- [ ] **Step 5: Run the full project analyzer to see expected compile errors elsewhere**

Run: `flutter analyze apps packages` from the project root.
Expected: errors in `geoscope_state.dart`, `geoscope_cubit.dart`, `geoscope_picker.dart`, and possibly test files that reference the old record shape. These are fixed in Tasks 2, 3, and 6.

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib/services/firestore_repository.dart \
        apps/client/test/services/firestore_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(client): read lat/lng from geoscope docs

Adds nullable lat/lng to the in-memory geoscope record type. Metro
docs that carry coords now round-trip; other docs read null. Lays
groundwork for the "Use my location" feature.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Extend `GeoscopeState` with new fields

Adds the four new state fields (`locationStatus`, `locationSuggestion`, `pendingToast`, `locationDenied`) plus the supporting enums. This unblocks the cubit compile errors from Task 1.

**Files:**
- Modify: `apps/client/lib/geoscope/cubit/geoscope_state.dart`
- Modify test: `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart` (initial-state test)

- [ ] **Step 1: Write the failing test**

In `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart`, extend the existing `'initial state is correct'` test (around line 20):

```dart
    test('initial state is correct', () {
      final cubit = GeoscopeCubit(repo, _FakeLocationService());
      expect(cubit.state.status, GeoscopeStatus.initial);
      expect(cubit.state.selectedGeoscope, '/');
      expect(cubit.state.availableGeoscopes, isEmpty);
      expect(cubit.state.locationStatus, GeoscopeLocationStatus.idle);
      expect(cubit.state.locationSuggestion, isNull);
      expect(cubit.state.pendingToast, isNull);
      expect(cubit.state.locationDenied, isFalse);
      addTearDown(cubit.close);
    });
```

Also add this fake at the top of the file just under `_MockFirestoreRepository` (Task 5 will replace it with a real fake, but a no-op stub is enough to compile this test):

```dart
class _FakeLocationService implements LocationService {
  @override
  Future<LocationOutcome> getApproximateLocation() async => LocationUnavailable();
}
```

And add the import at the top:

```dart
import 'package:client/geoscope/location_service.dart';
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization`
Expected: compile errors about `GeoscopeLocationStatus`, `locationStatus`, `locationSuggestion`, `pendingToast`, `locationDenied`, `LocationService`, and `LocationOutcome` not defined. (These are fixed in this task for state + Task 4 for LocationService.)

- [ ] **Step 3: Rewrite `geoscope_state.dart` with the new fields**

Replace the entire contents of `apps/client/lib/geoscope/cubit/geoscope_state.dart` with:

```dart
enum GeoscopeStatus { initial, loading, success, failure }

/// Transient status of an in-flight location lookup. `denied` and
/// `unavailable` outcomes signal via [GeoscopeState.locationDenied]
/// (persisted) and [GeoscopeState.pendingToast] (one-shot) respectively;
/// they don't need a sticky enum value here.
enum GeoscopeLocationStatus { idle, fetching }

/// One-shot toast signal consumed by the picker's BlocListener.
enum GeoscopeToast { denied, unavailable }

class GeoscopeState {
  const GeoscopeState({
    this.status = GeoscopeStatus.initial,
    this.selectedGeoscope = '/',
    this.availableGeoscopes = const [],
    this.needsSelection = false,
    this.locationStatus = GeoscopeLocationStatus.idle,
    this.locationSuggestion,
    this.pendingToast,
    this.locationDenied = false,
  });

  final GeoscopeStatus status;
  final String selectedGeoscope;
  final List<
    ({
      String id,
      String label,
      int population,
      double? lat,
      double? lng,
    })
  >
  availableGeoscopes;

  /// True when no geoscope has ever been explicitly chosen by the user — the
  /// current [selectedGeoscope] is either the global fallback or a locale
  /// inference. UI uses this to prompt for a first-time selection.
  final bool needsSelection;

  /// Transient state of an in-flight location lookup.
  final GeoscopeLocationStatus locationStatus;

  /// Set when the nearest metro is outside the auto-select threshold.
  /// The UI shows a confirmation row; tapping "Use" calls
  /// [GeoscopeCubit.acceptLocationSuggestion].
  final ({String id, double distanceKm})? locationSuggestion;

  /// One-shot toast signal, cleared by [GeoscopeCubit.clearPendingToast]
  /// after the listener fires.
  final GeoscopeToast? pendingToast;

  /// True if the user has ever denied OS location permission for this app.
  /// When true, the "Use my location" row is hidden in the picker.
  /// Persisted to SharedPreferences under `geoscope_location_denied`.
  final bool locationDenied;

  GeoscopeState copyWith({
    GeoscopeStatus? status,
    String? selectedGeoscope,
    List<
      ({
        String id,
        String label,
        int population,
        double? lat,
        double? lng,
      })
    >?
    availableGeoscopes,
    bool? needsSelection,
    GeoscopeLocationStatus? locationStatus,
    ({String id, double distanceKm})? locationSuggestion,
    bool clearLocationSuggestion = false,
    GeoscopeToast? pendingToast,
    bool clearPendingToast = false,
    bool? locationDenied,
  }) {
    return GeoscopeState(
      status: status ?? this.status,
      selectedGeoscope: selectedGeoscope ?? this.selectedGeoscope,
      availableGeoscopes: availableGeoscopes ?? this.availableGeoscopes,
      needsSelection: needsSelection ?? this.needsSelection,
      locationStatus: locationStatus ?? this.locationStatus,
      locationSuggestion: clearLocationSuggestion
          ? null
          : (locationSuggestion ?? this.locationSuggestion),
      pendingToast: clearPendingToast
          ? null
          : (pendingToast ?? this.pendingToast),
      locationDenied: locationDenied ?? this.locationDenied,
    );
  }
}
```

The `clearLocationSuggestion` and `clearPendingToast` boolean flags are needed because `copyWith` can't otherwise distinguish "leave as-is" from "set to null" for nullable fields. (Standard Dart `copyWith` workaround.)

- [ ] **Step 4: Run the initial-state test**

Still expect compile failures for `LocationService` and `LocationOutcome` (filled in by Task 4). The state fields themselves should now resolve.

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization 2>&1 | head -40`
Expected: still failing — `LocationService` undefined. That's fine; we proceed to Task 3 / 4.

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/geoscope/cubit/geoscope_state.dart \
        apps/client/test/geoscope/cubit/geoscope_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(client): add geoscope location state fields

Adds locationStatus, locationSuggestion, pendingToast, and
locationDenied to GeoscopeState, plus supporting enums. The cubit
wiring follows in subsequent commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `geolocator` dependency

Adds the package so `LocationService` can compile in Task 4.

**Files:**
- Modify: `apps/client/pubspec.yaml`

- [ ] **Step 1: Confirm latest stable version**

Run: `cd apps/client && flutter pub deps --no-dev 2>&1 | head -5` to confirm we have a working pub setup.
Run: `cd apps/client && flutter pub outdated --no-dev 2>&1 | head -5` (not strictly required; this is informational).

Use `geolocator: ^14.0.0` if it resolves cleanly. If pub complains about Flutter SDK constraints, lower the major version one notch (the implementer can run `flutter pub add geolocator` and let pub pick a version).

- [ ] **Step 2: Add the dependency**

Modify `apps/client/pubspec.yaml`. In the `dependencies:` block (alphabetical order), insert `geolocator: ^14.0.0` between `feedback:` and `firebase_app_check:`. The relevant block:

```yaml
  feedback: ^3.1.0
  firebase_app_check: ^0.4.4+1
```

becomes:

```yaml
  feedback: ^3.1.0
  geolocator: ^14.0.0
  firebase_app_check: ^0.4.4+1
```

(Alphabetical placement: `f` then `g` then `f` again — `firebase_*` keeps its existing block; `geolocator` is a top-level `g` entry between them.)

Actually, strictly alphabetical: after `feedback`, before `firebase_*`. The above placement is correct.

- [ ] **Step 3: Run `melos setup` to resolve**

Run: `melos setup` from the project root.
Expected: clean exit, lockfiles updated.

If you see a Flutter SDK constraint failure: `cd apps/client && flutter pub add geolocator` and re-run `melos setup`.

- [ ] **Step 4: Verify analyze still works (pre-platform-config)**

Run: `flutter analyze apps packages` from the project root.
Expected: same errors as before (no LocationService yet), no new errors from the geolocator import itself.

- [ ] **Step 5: Commit**

```bash
git add apps/client/pubspec.yaml apps/client/pubspec.lock pubspec.lock
git commit -m "$(cat <<'EOF'
chore(client): add geolocator dependency

Used by the upcoming "Use my location" feature in the geoscope picker
to obtain coarse device coordinates on iOS/Android/macOS/Windows/Web.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `LocationService` abstraction

Wraps `geolocator` behind a testable interface. The default impl handles permission flow, coarse-accuracy fetch, and outcome classification.

**Files:**
- Create: `apps/client/lib/geoscope/location_service.dart`
- (No test yet — `Geolocator` is platform-channel and unit tests inject the fake. We could add a smoke-test for the outcome branch logic, but it's better validated via the cubit's bloc_test which uses the fake.)

- [ ] **Step 1: Write the file**

Create `apps/client/lib/geoscope/location_service.dart` with:

```dart
import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Outcome of an attempt to read the user's approximate location.
sealed class LocationOutcome {
  const LocationOutcome();
}

class LocationCoords extends LocationOutcome {
  const LocationCoords(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// User explicitly denied OS permission (either now or previously
/// with "don't ask again"). Persisted as a sticky hide signal.
class LocationDenied extends LocationOutcome {
  const LocationDenied();
}

/// Transient failure: location services off, timeout, etc. NOT
/// persisted — the user may want to try again next picker open.
class LocationUnavailable extends LocationOutcome {
  const LocationUnavailable();
}

/// One-shot coarse-location lookup. Implementations must be
/// inexpensive to call once per picker open.
abstract class LocationService {
  Future<LocationOutcome> getApproximateLocation();
}

/// Default impl, backed by the `geolocator` package. Requests coarse
/// accuracy (~5 km on iOS/Android) — metro-centroid matching doesn't
/// benefit from sub-km precision.
///
/// Note: on Web, requires a secure context (HTTPS or localhost).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationOutcome> getApproximateLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationUnavailable();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationDenied();
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LocationCoords(position.latitude, position.longitude);
    } on TimeoutException {
      return const LocationUnavailable();
    } on LocationServiceDisabledException {
      return const LocationUnavailable();
    } on PermissionDeniedException {
      return const LocationDenied();
    } on Exception {
      return const LocationUnavailable();
    }
  }
}
```

- [ ] **Step 2: Verify it compiles in isolation**

Run: `cd apps/client && flutter analyze lib/geoscope/location_service.dart`
Expected: no errors. (Warnings about not being used yet are fine.)

- [ ] **Step 3: Commit**

```bash
git add apps/client/lib/geoscope/location_service.dart
git commit -m "$(cat <<'EOF'
feat(client): add LocationService abstraction

Wraps geolocator behind a sealed-outcome interface so the cubit's
location flow stays platform-independent and unit-testable. Coarse
accuracy (~5 km) is sufficient for metro-centroid matching.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Implement `findNearestMetro` (pure static helper)

Pure Haversine over the in-memory metro list. Unit-tested with known-pair distances.

**Files:**
- Modify: `apps/client/lib/geoscope/cubit/geoscope_cubit.dart` (add static method + import `dart:math`).
- Modify test: `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart` (new group).

- [ ] **Step 1: Write the failing tests**

In `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart`, add this `group` block inside `main()` after the existing `group('GeoscopeCubit', ...)`:

```dart
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization 2>&1 | head -50`
Expected: compile error `The method 'findNearestMetro' isn't defined`.

- [ ] **Step 3: Implement the helper**

Modify `apps/client/lib/geoscope/cubit/geoscope_cubit.dart`. Add `import 'dart:math' as math;` (it isn't currently imported). Then, inside the `GeoscopeCubit` class, after the existing `resolveGeoscope` method (around line 107), add:

```dart
  /// Earth radius in km, used by [findNearestMetro].
  static const _earthRadiusKm = 6371.0;

  /// Returns the metro in [available] closest to ([lat], [lng]), or null
  /// if no row carries both `lat` and `lng`. Threshold logic is the
  /// caller's responsibility — this function always returns the absolute
  /// nearest if any candidate exists.
  @visibleForTesting
  static ({String id, double distanceKm})? findNearestMetro({
    required double lat,
    required double lng,
    required List<
      ({
        String id,
        String label,
        int population,
        double? lat,
        double? lng,
      })
    >
    available,
  }) {
    ({String id, double distanceKm})? best;
    for (final g in available) {
      final gLat = g.lat;
      final gLng = g.lng;
      if (gLat == null || gLng == null) continue;
      final d = _haversineKm(lat, lng, gLat, gLng);
      if (best == null || d < best.distanceKm) {
        best = (id: g.id, distanceKm: d);
      }
    }
    return best;
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;
```

- [ ] **Step 4: Run the tests**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --plain-name 'findNearestMetro' --no-optimization`
Expected: all 5 tests in the new group pass. (Other tests in the file may still fail to compile due to missing LocationService constructor argument — fixed in Task 6.)

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/geoscope/cubit/geoscope_cubit.dart \
        apps/client/test/geoscope/cubit/geoscope_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(client): add findNearestMetro Haversine helper

Pure static method on GeoscopeCubit. Returns the nearest metro by
great-circle distance from a given lat/lng, skipping rows without
coords. Threshold logic is the caller's responsibility.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire `LocationService` into `GeoscopeCubit` constructor + extend `initialize`

Threading the dependency through the cubit, loading the persisted denial flag.

**Files:**
- Modify: `apps/client/lib/geoscope/cubit/geoscope_cubit.dart` (constructor, fields, initialize).
- Modify: `apps/client/lib/app/view/app.dart:118-126` (pass the new service).
- Modify test: `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart` (extend setUp + add initialize-with-denied-flag test).

- [ ] **Step 1: Write the failing test**

In `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart`, at the top of the file, ensure the imports include `package:client/geoscope/location_service.dart` (Task 2 already added this).

Update the `_FakeLocationService` to be more flexible (replace the Task-2 stub with):

```dart
class _FakeLocationService implements LocationService {
  _FakeLocationService([this._outcome = const LocationUnavailable()]);
  LocationOutcome _outcome;
  void setOutcome(LocationOutcome outcome) => _outcome = outcome;

  @override
  Future<LocationOutcome> getApproximateLocation() async => _outcome;
}
```

Update the file's `setUp` and all existing `GeoscopeCubit(repo)` constructor calls to take a `_FakeLocationService` as the second argument. (The simplest mechanical change is to introduce a top-level `late _FakeLocationService locationService;` and use `GeoscopeCubit(repo, locationService)` everywhere.)

Concretely, change the setUp block from:

```dart
  setUp(() {
    repo = _MockFirestoreRepository();
    SharedPreferences.setMockInitialValues({});
  });
```

to:

```dart
  late _FakeLocationService locationService;

  setUp(() {
    repo = _MockFirestoreRepository();
    locationService = _FakeLocationService();
    SharedPreferences.setMockInitialValues({});
  });
```

Then update every `GeoscopeCubit(repo)` and `() => GeoscopeCubit(repo)` in the file to `GeoscopeCubit(repo, locationService)` and `() => GeoscopeCubit(repo, locationService)` respectively.

Then add a new `blocTest` after the existing initialize tests inside `group('GeoscopeCubit', ...)`:

```dart
    blocTest<GeoscopeCubit, GeoscopeState>(
      'initialize loads persisted geoscope_location_denied=true',
      setUp: () {
        SharedPreferences.setMockInitialValues({
          'geoscope_location_denied': true,
        });
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
            .having((s) => s.locationDenied, 'locationDenied', true),
      ],
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization 2>&1 | head -30`
Expected: compile errors about `GeoscopeCubit` constructor taking only 1 positional arg.

- [ ] **Step 3: Update `GeoscopeCubit` constructor and `initialize`**

Modify `apps/client/lib/geoscope/cubit/geoscope_cubit.dart`. Replace lines 16-21 (the class header) with:

```dart
class GeoscopeCubit extends Cubit<GeoscopeState> {
  GeoscopeCubit(this._repo, this._location) : super(const GeoscopeState());

  final FirestoreRepository _repo;
  final LocationService _location;
  static const _prefsKey = 'selected_geoscope';
  static const _locationDeniedPrefsKey = 'geoscope_location_denied';
```

Add the import at the top of the file:

```dart
import 'package:client/geoscope/location_service.dart';
```

Modify the `initialize` method (currently lines 25-55). Replace the `final available = await _repo.getGeoscopes();` line and the subsequent `emit(state.copyWith(...))` to also load and pass through `locationDenied`. Specifically:

```dart
  Future<void> initialize() async {
    emit(state.copyWith(status: GeoscopeStatus.loading));
    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString(_prefsKey);
      final locationDenied = prefs.getBool(_locationDeniedPrefsKey) ?? false;
      final available = await _repo.getGeoscopes();
      final availableIds = {'/'}..addAll(available.map((g) => g.id));
      final geoscope = resolveGeoscope(
        persisted: persisted,
        inferred: _inferFromLocale(),
        availableIds: availableIds,
      );
      if (persisted != null && geoscope != persisted) {
        await prefs.setString(_prefsKey, geoscope);
      }
      emit(
        state.copyWith(
          status: GeoscopeStatus.success,
          selectedGeoscope: geoscope,
          availableGeoscopes: available,
          needsSelection: persisted == null,
          locationDenied: locationDenied,
        ),
      );
    } on Exception catch (e, st) {
      log('GeoscopeCubit.initialize failed: $e', stackTrace: st);
      emit(state.copyWith(status: GeoscopeStatus.failure));
    }
  }
```

- [ ] **Step 4: Update `app.dart` to inject the service**

Modify `apps/client/lib/app/view/app.dart` lines 118-126. Replace:

```dart
          BlocProvider(
            create: (context) {
              final cubit = GeoscopeCubit(
                context.read<FirestoreRepository>(),
              );
              unawaited(cubit.initialize());
              return cubit;
            },
          ),
```

with:

```dart
          BlocProvider(
            create: (context) {
              final cubit = GeoscopeCubit(
                context.read<FirestoreRepository>(),
                const GeolocatorLocationService(),
              );
              unawaited(cubit.initialize());
              return cubit;
            },
          ),
```

Add the import at the top of `app.dart`:

```dart
import 'package:client/geoscope/location_service.dart';
```

- [ ] **Step 5: Run all geoscope cubit tests**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization`
Expected: all tests pass, including the two new initialize variants.

- [ ] **Step 6: Run the analyzer**

Run: `flutter analyze apps packages`
Expected: errors confined to picker widget tests / picker widget. Cubit-related errors should be gone.

- [ ] **Step 7: Commit**

```bash
git add apps/client/lib/geoscope/cubit/geoscope_cubit.dart \
        apps/client/lib/app/view/app.dart \
        apps/client/test/geoscope/cubit/geoscope_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(client): inject LocationService into GeoscopeCubit

Adds LocationService as a constructor dependency, loads the persisted
geoscope_location_denied flag in initialize, and wires GeolocatorLocationService
into the app's BlocProvider tree.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Cubit orchestration — `selectNearestMetroFromLocation`, `acceptLocationSuggestion`, `dismissLocationSuggestion`, `clearPendingToast`

Adds the orchestration that the picker UI calls.

**Files:**
- Modify: `apps/client/lib/geoscope/cubit/geoscope_cubit.dart`
- Modify test: `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart` (new groups)

- [ ] **Step 1: Write the failing tests**

In `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart`, inside `group('GeoscopeCubit', ...)`, add:

```dart
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
        locationService.setOutcome(const LocationCoords(37.83, -122.42));
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
        locationService.setOutcome(const LocationCoords(39.53, -119.81));
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
        locationService.setOutcome(const LocationDenied());
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
        locationService.setOutcome(const LocationUnavailable());
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
        locationService.setOutcome(const LocationCoords(39.53, -119.81));
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
        locationService.setOutcome(const LocationCoords(39.53, -119.81));
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
        locationService.setOutcome(const LocationUnavailable());
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization 2>&1 | head -40`
Expected: compile errors about `selectNearestMetroFromLocation`, `acceptLocationSuggestion`, `dismissLocationSuggestion`, `clearPendingToast` not defined.

- [ ] **Step 3: Implement the methods**

Modify `apps/client/lib/geoscope/cubit/geoscope_cubit.dart`. Add a class-level constant near the other consts:

```dart
  /// Within this distance, auto-select the nearest metro silently.
  /// Beyond this, surface a confirmation row so the user can decide.
  static const _autoSelectThresholdKm = 100.0;
```

Add the orchestration method, placed after `selectGeoscope` (around the existing line 62):

```dart
  /// Ask the OS for a coarse location, find the nearest metro, and either
  /// auto-select (within threshold) or emit a [GeoscopeState.locationSuggestion]
  /// for user confirmation.
  ///
  /// On [LocationDenied], persists the denial flag so the picker stops
  /// offering the button. On [LocationUnavailable] (timeout, services off),
  /// emits a one-shot toast but does not persist.
  Future<void> selectNearestMetroFromLocation() async {
    if (state.locationStatus == GeoscopeLocationStatus.fetching) return;
    emit(state.copyWith(locationStatus: GeoscopeLocationStatus.fetching));
    final outcome = await _location.getApproximateLocation();
    switch (outcome) {
      case LocationCoords(:final lat, :final lng):
        final nearest = findNearestMetro(
          lat: lat,
          lng: lng,
          available: state.availableGeoscopes,
        );
        if (nearest == null) {
          emit(
            state.copyWith(
              locationStatus: GeoscopeLocationStatus.idle,
              pendingToast: GeoscopeToast.unavailable,
            ),
          );
          return;
        }
        if (nearest.distanceKm <= _autoSelectThresholdKm) {
          await _persistGeoscope(nearest.id);
          emit(
            state.copyWith(
              selectedGeoscope: nearest.id,
              needsSelection: false,
              locationStatus: GeoscopeLocationStatus.idle,
              clearLocationSuggestion: true,
            ),
          );
        } else {
          emit(
            state.copyWith(
              locationStatus: GeoscopeLocationStatus.idle,
              locationSuggestion: nearest,
            ),
          );
        }
      case LocationDenied():
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_locationDeniedPrefsKey, true);
        emit(
          state.copyWith(
            locationStatus: GeoscopeLocationStatus.idle,
            locationDenied: true,
            pendingToast: GeoscopeToast.denied,
          ),
        );
      case LocationUnavailable():
        emit(
          state.copyWith(
            locationStatus: GeoscopeLocationStatus.idle,
            pendingToast: GeoscopeToast.unavailable,
          ),
        );
    }
  }

  /// Accepts a previously-emitted [GeoscopeState.locationSuggestion],
  /// selecting the suggested geoscope and clearing the suggestion.
  Future<void> acceptLocationSuggestion() async {
    final s = state.locationSuggestion;
    if (s == null) return;
    await _persistGeoscope(s.id);
    emit(
      state.copyWith(
        selectedGeoscope: s.id,
        needsSelection: false,
        clearLocationSuggestion: true,
      ),
    );
  }

  /// Dismisses a previously-emitted location suggestion without selecting.
  void dismissLocationSuggestion() {
    emit(state.copyWith(clearLocationSuggestion: true));
  }

  /// Called by the picker's BlocListener after firing a toast, so the
  /// listener doesn't re-fire on subsequent state emissions.
  void clearPendingToast() {
    if (state.pendingToast != null) {
      emit(state.copyWith(clearPendingToast: true));
    }
  }

  Future<void> _persistGeoscope(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }
```

- [ ] **Step 4: Run the tests**

Run: `cd apps/client && very_good test test/geoscope/cubit/geoscope_cubit_test.dart --no-optimization`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/client/lib/geoscope/cubit/geoscope_cubit.dart \
        apps/client/test/geoscope/cubit/geoscope_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(client): add geoscope location-flow cubit methods

selectNearestMetroFromLocation orchestrates a one-shot location lookup,
nearest-metro match (Haversine), and either auto-selection (within 100
km) or a confirmable suggestion. Denial persists; unavailability fires
a transient toast.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Add ARB strings in `app_en.arb`, then mirror to all 24 locales

Per memory `[ARB translation policy]` — all locales in the same PR.

**Files:**
- Modify: `apps/client/lib/l10n/arb/app_en.arb`
- Modify: every other `apps/client/lib/l10n/arb/app_*.arb` (23 files)

- [ ] **Step 1: Add English strings**

Open `apps/client/lib/l10n/arb/app_en.arb`. After the existing `geoscopePickerHeading` block (around line 232), insert:

```json
    "geoscopeUseMyLocation": "Use my location",
    "@geoscopeUseMyLocation": {
        "description": "Label on the button in the geoscope picker that triggers a coarse-location lookup to suggest the nearest metro"
    },
    "geoscopeSuggestionDistance": "About {distanceKm} km away — use anyway?",
    "@geoscopeSuggestionDistance": {
        "description": "Subtitle shown under the suggested metro when the nearest match is outside the auto-select threshold",
        "placeholders": {
            "distanceKm": {
                "type": "int"
            }
        }
    },
    "geoscopeLocationDenied": "Location access was denied — please pick manually.",
    "@geoscopeLocationDenied": {
        "description": "Toast shown when the OS reports the user denied location permission"
    },
    "geoscopeLocationUnavailable": "Location is unavailable — please pick manually.",
    "@geoscopeLocationUnavailable": {
        "description": "Toast shown when location services are off or the lookup timed out"
    },
```

Mind the JSON trailing comma — leave the existing comma after the closing `}` of `@geoscopePickerHeading` and add your new block before the next existing key.

- [ ] **Step 2: Generate localizations and verify**

Run: `melos gen` from the project root (which runs the l10n generator across packages).
Expected: clean run. The generated `app_localizations.dart` should now have the four new getters.

Run: `grep -l "geoscopeUseMyLocation" apps/client/lib/l10n/gen/app_localizations_en.dart`
Expected: file path matches (i.e. the getter was generated).

- [ ] **Step 3: Mirror to all 23 other locales with English placeholders**

For each of the 23 non-English `app_*.arb` files in `apps/client/lib/l10n/arb/`, add the same four keys (without the `@description` and `@placeholders` blocks — those only live in `app_en.arb`). Use the English text as the placeholder value. Insert them at the equivalent position (after the `geoscopePickerHeading` key).

A scripted approach (run from project root, copy the structure manually if you prefer):

```bash
for arb in apps/client/lib/l10n/arb/app_*.arb; do
  if [ "$(basename "$arb")" = "app_en.arb" ]; then
    continue
  fi
  # Manual edit each one; the in-PR diff is small enough that a search-and-replace
  # is safer than auto-generation. Add the four bare key entries below the
  # geoscopePickerHeading entry, with English values.
done
```

Each non-English file gets exactly these four lines added (with the JSON commas placed correctly relative to neighboring entries):

```json
    "geoscopeUseMyLocation": "Use my location",
    "geoscopeSuggestionDistance": "About {distanceKm} km away — use anyway?",
    "geoscopeLocationDenied": "Location access was denied — please pick manually.",
    "geoscopeLocationUnavailable": "Location is unavailable — please pick manually.",
```

The implementer should manually open each ARB and add these keys, verifying JSON validity per file. **DO NOT use sed/awk** — JSON nesting and trailing commas are too easy to break.

- [ ] **Step 4: Regenerate localizations**

Run: `melos gen` from the project root.
Expected: clean run. No locale should be missing the new keys (the generator warns about missing translations, but English fallback is the documented project policy per the ARB translation memory).

- [ ] **Step 5: Run the analyzer**

Run: `flutter analyze apps packages`
Expected: no new errors related to localization. (Picker errors from referencing not-yet-imported keys still exist; the picker update is Task 11.)

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib/l10n/arb/ apps/client/lib/l10n/gen/
git commit -m "$(cat <<'EOF'
chore(client): add ARB strings for "Use my location" in all locales

Per project policy, new l10n strings land in every locale at the same
time as English (with English placeholders for non-English). Four
keys: geoscopeUseMyLocation, geoscopeSuggestionDistance,
geoscopeLocationDenied, geoscopeLocationUnavailable.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Platform manifest updates (iOS, Android, macOS)

**Files:**
- Modify: `apps/client/ios/Runner/Info.plist`
- Modify: `apps/client/android/app/src/main/AndroidManifest.xml`
- Modify: `apps/client/macos/Runner/DebugProfile.entitlements`
- Modify: `apps/client/macos/Runner/Release.entitlements`
- Modify: `apps/client/macos/Runner/Info.plist`

- [ ] **Step 1: iOS — add `NSLocationWhenInUseUsageDescription`**

Open `apps/client/ios/Runner/Info.plist`. Inside the top-level `<dict>`, add:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Used to suggest the metro area nearest you when picking a geoscope.</string>
```

Place it alphabetically with the other `N*` keys (e.g. after `CFBundleVersion` and any other existing `N*` keys; the exact position isn't load-bearing, just consistent).

- [ ] **Step 2: Android — add coarse-location permission**

Open `apps/client/android/app/src/main/AndroidManifest.xml`. Just before the existing `<application>` tag (i.e. after the `<manifest>` opening tag), add:

```xml
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Final structure:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <application
        android:label="${appName}"
        ...
```

- [ ] **Step 3: macOS — add location entitlement to both entitlements files**

Open `apps/client/macos/Runner/DebugProfile.entitlements`. Inside the `<dict>`, after the existing `com.apple.security.network.server` entry, add:

```xml
	<key>com.apple.security.personal-information.location</key>
	<true/>
```

Repeat for `apps/client/macos/Runner/Release.entitlements` (same insertion).

- [ ] **Step 4: macOS — add usage description to Info.plist**

Open `apps/client/macos/Runner/Info.plist`. Inside the top-level `<dict>`, add:

```xml
	<key>NSLocationUsageDescription</key>
	<string>Used to suggest the metro area nearest you when picking a geoscope.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Used to suggest the metro area nearest you when picking a geoscope.</string>
```

(macOS uses `NSLocationUsageDescription` historically; `NSLocationWhenInUseUsageDescription` is required for sandboxed apps on recent macOS. Including both is safe.)

- [ ] **Step 5: Verify nothing is syntactically broken**

Run: `flutter analyze apps packages`
Expected: no analyzer changes (manifests aren't analyzed by `flutter analyze`).

Run: `cd apps/client && flutter build apk --debug --flavor development --target lib/main_development.dart 2>&1 | tail -20`
Expected: clean exit. (If you're on a machine without Android tooling, skip and verify on iOS via `flutter build ios --no-codesign --flavor development --target lib/main_development.dart`. If on neither: skip — the runtime build is the verification.)

- [ ] **Step 6: Commit**

```bash
git add apps/client/ios/Runner/Info.plist \
        apps/client/android/app/src/main/AndroidManifest.xml \
        apps/client/macos/Runner/DebugProfile.entitlements \
        apps/client/macos/Runner/Release.entitlements \
        apps/client/macos/Runner/Info.plist
git commit -m "$(cat <<'EOF'
chore(client): add location permission entries for iOS/Android/macOS

iOS NSLocationWhenInUseUsageDescription, Android ACCESS_COARSE_LOCATION,
macOS location entitlement + usage description. Windows and Web need
no manifest entries (browser API / system-level toggle respectively).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Backfill tool — `seed_geoscope_coords.dart`

Pre-curated coords for ~50 metro docs (no countries, states, or supranationals — see comment in the file), writes via `googleapis/firestore`.

**Files:**
- Create: `apps/server/tool/seed_geoscope_coords.dart`

- [ ] **Step 1: Write the tool**

Create `apps/server/tool/seed_geoscope_coords.dart` with:

```dart
// One-shot backfill: writes canonical lat/lng to metro docs in the
// `geoscopes` collection. Idempotent — re-running overwrites with the
// same values. Uses an update_mask so existing fields (id, label,
// population) are preserved.
//
// Usage (run from `apps/server/`):
//   # Emulator:
//   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8081
//   dart run tool/seed_geoscope_coords.dart --emulator [--dry-run]
//
//   # Production (explicit opt-in, no default):
//   gcloud auth application-default login
//   gcloud auth application-default set-quota-project votasq
//   dart run tool/seed_geoscope_coords.dart --prod [--dry-run]

import 'dart:io';

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:http/http.dart' as http;

const _scopes = <String>[FirestoreApi.datastoreScope];
const _projectId = 'votasq';

/// Document id (the doc name in the `geoscopes` collection) → lat/lng.
/// Per spec, only METRO docs get coords — supranationals (eu/sea/cn/...),
/// countries, and states do NOT, because a single point can't meaningfully
/// represent them and `findNearestMetro` is intentionally metros-only.
/// Coords are city-centre / metro centroid in WGS84 decimal degrees.
/// References noted in comments so a reviewer can sanity-check.
const _coords = <String, ({double lat, double lng})>{
  // North America metros
  'sfbay': (lat: 37.7793, lng: -122.4193), // SF City Hall
  'socal': (lat: 34.0522, lng: -118.2437), // Downtown LA
  'nyc': (lat: 40.7128, lng: -74.0060), // Manhattan
  'chicago': (lat: 41.8781, lng: -87.6298), // The Loop
  'atlanta': (lat: 33.7490, lng: -84.3880), // Downtown Atlanta
  'miami': (lat: 25.7617, lng: -80.1918), // Downtown Miami
  'philly': (lat: 39.9526, lng: -75.1652), // Center City
  'dc': (lat: 38.9072, lng: -77.0369), // Washington DC, Capitol
  'gta': (lat: 43.6532, lng: -79.3832), // Greater Toronto, downtown
  'cdmx': (lat: 19.4326, lng: -99.1332), // Mexico City, Zócalo

  // South America metros
  'ba': (lat: -34.6037, lng: -58.3816), // Buenos Aires centre
  'sãopaulo': (lat: -23.5505, lng: -46.6333), // São Paulo centre
  'rio': (lat: -22.9068, lng: -43.1729), // Rio centre
  'bogota': (lat: 4.7110, lng: -74.0721), // Bogotá centre
  'lima': (lat: -12.0464, lng: -77.0428), // Lima centre

  // Europe metros
  'paris': (lat: 48.8566, lng: 2.3522), // Île-de-la-Cité
  'berlin': (lat: 52.5200, lng: 13.4050), // Brandenburg Gate
  'rome': (lat: 41.9028, lng: 12.4964), // Colosseum
  'madrid': (lat: 40.4168, lng: -3.7038), // Puerta del Sol
  'london': (lat: 51.5074, lng: -0.1278), // Charing Cross
  'athens': (lat: 37.9838, lng: 23.7275), // Acropolis

  // India metros
  'mumbai': (lat: 19.0760, lng: 72.8777),
  'delhi': (lat: 28.7041, lng: 77.1025),
  'bengaluru': (lat: 12.9716, lng: 77.5946),
  'hyderabad': (lat: 17.3850, lng: 78.4867),
  'chennai': (lat: 13.0827, lng: 80.2707),
  'kolkata': (lat: 22.5726, lng: 88.3639),
  'ahmedabad': (lat: 23.0225, lng: 72.5714),
  'pune': (lat: 18.5204, lng: 73.8567),
  'surat': (lat: 21.1702, lng: 72.8311),
  'jaipur': (lat: 26.9124, lng: 75.7873),
  'kanpur': (lat: 26.4499, lng: 80.3319),
  'lucknow': (lat: 26.8467, lng: 80.9462),

  // China metros (Guangdong omitted — it's a province, ~127M people,
  // a single point can't represent it)
  'beijing': (lat: 39.9042, lng: 116.4074),
  'shanghai': (lat: 31.2304, lng: 121.4737),
  'hongkong': (lat: 22.3193, lng: 114.1694),

  // Japan metro
  'tokyo': (lat: 35.6762, lng: 139.6503),

  // SE Asia metros
  'singapore': (lat: 1.3521, lng: 103.8198), // city-state, doubles as metro
  'jakarta': (lat: -6.2088, lng: 106.8456),
  'krungthep': (lat: 13.7563, lng: 100.5018), // Bangkok
  'manila': (lat: 14.5995, lng: 120.9842),
  'hanoi': (lat: 21.0285, lng: 105.8542),
  'hochiminh': (lat: 10.8231, lng: 106.6297),

  // West / South Asia metros
  'karachi': (lat: 24.8607, lng: 67.0011),
  'dhaka': (lat: 23.8103, lng: 90.4125),
  'istanbul': (lat: 41.0082, lng: 28.9784),
  'jeddah': (lat: 21.4858, lng: 39.1925),
  'riyadh': (lat: 24.7136, lng: 46.6753),

  // Africa metros
  'cairo': (lat: 30.0444, lng: 31.2357),
  'alexandria': (lat: 31.2001, lng: 29.9187),
  'lagos': (lat: 6.5244, lng: 3.3792),
};

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final emulator = args.contains('--emulator');
  final prod = args.contains('--prod');

  if (!emulator && !prod) {
    stderr.writeln(
      'Specify --emulator or --prod. See file header for usage.',
    );
    exit(2);
  }
  if (emulator && prod) {
    stderr.writeln('Cannot specify both --emulator and --prod.');
    exit(2);
  }

  http.Client client;
  String? rootUrl;
  if (emulator) {
    final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
    if (host == null || host.isEmpty) {
      stderr.writeln(
        'FIRESTORE_EMULATOR_HOST must be set when using --emulator '
        '(e.g. 127.0.0.1:8081).',
      );
      exit(2);
    }
    client = _EmulatorOwnerClient(http.Client());
    rootUrl = 'http://$host/';
  } else {
    client = await auth_io.clientViaApplicationDefaultCredentials(
      scopes: _scopes,
    );
  }

  final api = rootUrl == null
      ? FirestoreApi(client)
      : FirestoreApi(client, rootUrl: rootUrl);

  const databasePath = 'projects/$_projectId/databases/(default)';
  const base = '$databasePath/documents';

  var updated = 0;
  try {
    for (final entry in _coords.entries) {
      final docId = entry.key;
      final lat = entry.value.lat;
      final lng = entry.value.lng;
      final docName = '$base/geoscopes/$docId';
      stdout.writeln(
        'doc=$docId lat=$lat lng=$lng dryRun=$dryRun',
      );
      if (dryRun) continue;
      await api.projects.databases.documents.patch(
        Document(
          name: docName,
          fields: {
            'lat': Value(doubleValue: lat),
            'lng': Value(doubleValue: lng),
          },
        ),
        docName,
        updateMask_fieldPaths: ['lat', 'lng'],
      );
      updated++;
    }
  } finally {
    client.close();
  }

  stdout.writeln(
    'updated=$updated dryRun=$dryRun '
    'target=${emulator ? "emulator" : "prod"}',
  );
}

/// Wraps an [http.Client] so every request carries
/// `Authorization: Bearer owner`, the documented Firebase emulator
/// admin-bypass token.
class _EmulatorOwnerClient extends http.BaseClient {
  _EmulatorOwnerClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd apps/server && dart analyze tool/seed_geoscope_coords.dart`
Expected: no errors.

- [ ] **Step 3: Run dry-run against emulator (no emulator required for `--dry-run`)**

Run: `cd apps/server && FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 dart run tool/seed_geoscope_coords.dart --emulator --dry-run`
Expected: prints one `doc=X lat=Y lng=Z dryRun=true` line per entry in the `_coords` map (~50 lines) and a final `updated=0 dryRun=true target=emulator` summary. No network calls.

- [ ] **Step 4: Commit**

```bash
git add apps/server/tool/seed_geoscope_coords.dart
git commit -m "$(cat <<'EOF'
feat(server): add seed_geoscope_coords backfill tool

One-shot writer that stamps lat/lng on the ~50 metro docs in the
`geoscopes` collection (countries/states/supranationals deliberately
excluded — a single point can't represent them). --emulator and
--prod flags select the target; update_mask keeps existing
id/label/population fields untouched. Coords curated by hand;
reviewer notes in source comments.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Picker UI — add location row, suggestion mode, denial-hide, toast listener

The big UI change. Wraps the relevant parts in `BlocConsumer` so the picker reacts to cubit state.

**Files:**
- Modify: `apps/client/lib/problems/widgets/geoscope_picker.dart`
- Modify test: `apps/client/test/problems/widgets/geoscope_picker_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Open `apps/client/test/problems/widgets/geoscope_picker_test.dart`. The existing `buildSubject` helper passes a real `GeoscopeCubit` state into a mock. We need to extend it to take the new fields.

Replace the existing `buildSubject` function (lines 21-46) with:

```dart
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
    geoscopes = const [],
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
```

Also: every existing `geoscopes: [...]` literal in existing tests needs `lat: null, lng: null` added to each row (because the record type changed). Run a find-and-replace in the file: `(id: '` → keep as-is, but for each row, append `, lat: null, lng: null` before the closing `)`. There are roughly 10-15 such rows; do them all.

Then add a new group at the end of `main()`:

```dart
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
        await tester.pumpAndSettle();
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/client && very_good test test/problems/widgets/geoscope_picker_test.dart --no-optimization 2>&1 | head -30`
Expected: failures because the picker doesn't yet render the new row.

- [ ] **Step 3: Update `geoscope_picker.dart`**

Open `apps/client/lib/problems/widgets/geoscope_picker.dart`. Two changes:

**3a. Wrap the body in a `BlocConsumer` for reactive rebuild + listener.**

Modify the `build` method (around lines 139-194). Replace the `return Padding(...)` block (lines 146-193) with:

```dart
    return BlocConsumer<GeoscopeCubit, GeoscopeState>(
      listenWhen: (prev, curr) => prev.pendingToast != curr.pendingToast,
      listener: (context, state) {
        final toast = state.pendingToast;
        if (toast == null) return;
        final message = switch (toast) {
          GeoscopeToast.denied => l10n.geoscopeLocationDenied,
          GeoscopeToast.unavailable => l10n.geoscopeLocationUnavailable,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
          ),
        );
        context.read<GeoscopeCubit>().clearPendingToast();
      },
      buildWhen: (prev, curr) =>
          prev.locationStatus != curr.locationStatus ||
          prev.locationSuggestion != curr.locationSuggestion ||
          prev.locationDenied != curr.locationDenied ||
          prev.selectedGeoscope != curr.selectedGeoscope,
      builder: (context, state) {
        // After a location-driven auto-select, pop the sheet to mirror
        // the manual-tap UX. Trigger heuristic: status was fetching last
        // frame and is idle now, and there's no outstanding suggestion.
        // (We close after the build via addPostFrameCallback.)
        final filterEnabled =
            _selectedSuperstate == null && _selectedCountry == null;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    l10n.geoscopePickerHeading,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _filterController,
                    enabled: filterEnabled,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.geoscopeFilterHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _filterController.clear,
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (!state.locationDenied) _buildLocationRow(context, state),
                Flexible(
                  child: _query.isEmpty
                      ? _buildHierarchical(context)
                      : _buildFiltered(context, _query.toLowerCase()),
                ),
              ],
            ),
          ),
        );
      },
    );
```

(The closing `}` for `Widget build` stays as-is. The `final l10n = context.l10n;` line at the very top of the original `build` method must remain, since `BlocConsumer`'s listener references it.)

**3b. Add a `_buildLocationRow` helper inside the same `State` class:**

```dart
  Widget _buildLocationRow(BuildContext context, GeoscopeState state) {
    final l10n = context.l10n;
    final cubit = context.read<GeoscopeCubit>();

    if (state.locationSuggestion != null) {
      final suggestion = state.locationSuggestion!;
      final allGeo = state.availableGeoscopes;
      final match = allGeo.where((g) => g.id == suggestion.id).firstOrNull;
      final label = match?.label ?? suggestion.id;
      return ListTile(
        leading: const Icon(Icons.my_location),
        title: Text(label),
        subtitle: Text(
          l10n.geoscopeSuggestionDistance(suggestion.distanceKm.round()),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () async {
                await cubit.acceptLocationSuggestion();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Use'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: cubit.dismissLocationSuggestion,
            ),
          ],
        ),
      );
    }

    final isFetching =
        state.locationStatus == GeoscopeLocationStatus.fetching;
    return ListTile(
      leading: isFetching
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location),
      title: Text(l10n.geoscopeUseMyLocation),
      onTap: isFetching
          ? null
          : () async {
              final before = cubit.state.selectedGeoscope;
              await cubit.selectNearestMetroFromLocation();
              final after = cubit.state.selectedGeoscope;
              if (before != after && context.mounted) {
                Navigator.of(context).pop();
              }
            },
    );
  }
```

Also ensure the file imports what it needs. Add to the existing imports if not present:

```dart
import 'package:client/geoscope/cubit/geoscope_state.dart';
```

(The other imports — `Material`, `flutter_bloc`, etc. — are already there.)

- [ ] **Step 4: Run the widget tests**

Run: `cd apps/client && very_good test test/problems/widgets/geoscope_picker_test.dart --no-optimization`
Expected: all tests in `Use my location row` group pass, and the existing tests continue to pass (modulo the record-type updates from Step 1).

- [ ] **Step 5: Run the full client test suite**

Run: `cd apps/client && very_good test --recursive --no-optimization`
Expected: all pass.

- [ ] **Step 6: Run analyzer**

Run: `flutter analyze apps packages`
Expected: clean.

- [ ] **Step 7: Format**

Run: `melos format` from the project root.

- [ ] **Step 8: Commit**

```bash
git add apps/client/lib/problems/widgets/geoscope_picker.dart \
        apps/client/test/problems/widgets/geoscope_picker_test.dart
git commit -m "$(cat <<'EOF'
feat(client): add "Use my location" row to geoscope picker

New row under the search field offers a one-tap coarse-location
lookup. Within 100 km it auto-selects and dismisses the sheet; beyond
that it shows a confirmation row with the nearest metro and its
distance. Hidden permanently once the user denies OS permission.
Errors show a brief orange toast.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Run the backfill against the emulator and smoke-test the picker

This is the verification step — not just a code change. The user reviews the picker behavior before approving prod backfill.

**Files:** No code changes.

- [ ] **Step 1: Start the Firestore emulator**

Run in a separate terminal: `firebase emulators:start --only auth,firestore`
Expected: Firestore on `:8081`, Auth on `:9099` (per CLAUDE.md).

- [ ] **Step 2: Seed the emulator with the prod geoscopes collection**

This needs to happen first so the seed-coords tool has docs to patch. Run from project root:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project votasq
cd apps/server
FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 dart run tool/copy_geoscopes_to_emulator.dart
```

Expected: `copied=N dryRun=false project=votasq emulator=127.0.0.1:8081` where N matches the prod count.

- [ ] **Step 3: Run the new backfill in dry-run, then for real**

Run from `apps/server/`:

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 dart run tool/seed_geoscope_coords.dart --emulator --dry-run
FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 dart run tool/seed_geoscope_coords.dart --emulator
```

Expected: `updated=N dryRun=false target=emulator` where N is the count of entries in the `_coords` map (~70).

- [ ] **Step 4: Verify a sample doc has the new fields**

Use the Firebase MCP or the emulator UI (`http://127.0.0.1:4000`) to inspect e.g. `geoscopes/sfbay`. Expect to see `lat: 37.7793, lng: -122.4193` alongside the existing `id, label, population`.

- [ ] **Step 5: Run the Flutter app against the emulator**

Following CLAUDE.md's macOS gotcha (use literal `127.0.0.1`, debug-token registered):

```bash
cd apps/client
flutter run --flavor development --target lib/main_development.dart -d macos
```

(Or `-d chrome` for web; or your preferred device.)

In the app:
1. Open the geoscope picker (gear icon / location button).
2. Verify the "Use my location" row is present.
3. Tap it.
4. Grant location permission when prompted.
5. **Expected:** if you're in/near a listed metro, the picker dismisses and the selected scope shows your metro. If not, you see a suggestion row with a metro and distance.

- [ ] **Step 6: Smoke-test denial flow**

1. Tap "Use my location" again — but this time, deny the OS permission.
2. **Expected:** an orange toast appears, picker stays open, the "Use my location" row disappears (because `locationDenied` was set + persisted).
3. Cold-start the app (kill + relaunch). Re-open the picker.
4. **Expected:** "Use my location" row is still absent.

- [ ] **Step 7: Reset for further testing if needed**

To re-enable for additional testing, clear the app's `SharedPreferences` (the relevant key is `geoscope_location_denied`). On macOS: delete `~/Library/Preferences/com.example.client.plist` (path depends on flavor). On web: `localStorage.clear()` in DevTools.

- [ ] **Step 8: No commit (verification only)**

If everything passes, proceed to Task 13. If something is wrong, fix in a new commit on top.

---

## Task 13: Run the backfill against production

User-gated. Do not run without explicit approval after Task 12 passes.

**Files:** No code changes.

- [ ] **Step 1: Confirm with the user that Task 12 verification looks good**

Stop and ask: "Emulator verification passed. Ready to run the seed against production?" — wait for explicit yes.

- [ ] **Step 2: Run prod backfill in dry-run first**

Run from `apps/server/`:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project votasq
dart run tool/seed_geoscope_coords.dart --prod --dry-run
```

Expected: ~70 lines of `doc=X lat=Y lng=Z dryRun=true` followed by `updated=0 dryRun=true target=prod`. No network writes.

- [ ] **Step 3: Run prod backfill for real**

Run from `apps/server/`:

```bash
dart run tool/seed_geoscope_coords.dart --prod
```

Expected: `updated=N dryRun=false target=prod` where N matches the entry count.

- [ ] **Step 4: Spot-check a doc via the Firebase MCP**

Use `firestore_get_document` on `geoscopes/sfbay` and verify `lat` and `lng` are present. Pick 2-3 other docs at random.

- [ ] **Step 5: Optional — re-deploy the client**

If you want users to be able to use the new feature, ensure the client release goes out via the normal `melos run release -- vX.Y.Z` flow. Until then, prod has the data but old clients ignore it.

---

## Task 14: Final verification — full test suite + CI parity

**Files:** No code changes.

- [ ] **Step 1: Run the formatter**

Run: `melos format` from project root.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze apps packages`
Expected: clean.

- [ ] **Step 3: Run the full test suite (mirrors CI)**

Run from project root:

```bash
very_good test --recursive --no-optimization --coverage --test-randomize-ordering-seed random
```

Expected: clean exit. Some long-running but every test passes.

- [ ] **Step 4: Optional: run e2e tests**

If Firebase emulators are still running (Task 12), run from project root:

```bash
dart test apps/server/e2e/ --tags e2e
```

Expected: clean. (No e2e changes were needed since `firestore.rules` didn't change — geoscopes collection is already publicly readable.)

- [ ] **Step 5: Commit any final tweaks if needed**

If anything failed and required a tweak, that's a separate commit. Otherwise this task is just a verification gate.

---

## Self-review notes (for plan author)

**Spec coverage:**
- Data model: Task 1 (read-side), Task 10 (backfill). ✓
- Backfill: Task 10. ✓
- Matching algorithm: Task 5. ✓
- Cubit state: Task 2. ✓
- Cubit methods: Task 7. ✓ + initialize in Task 6.
- Picker UI: Task 11. ✓
- Localization: Task 8 (all 24 locales). ✓
- Permissions: Task 9. ✓
- Tests: Tasks 1, 5, 6, 7, 11 cover all required automated test classes. ✓ Manual smoke-test: Task 12. ✓
- Denial-hide: Task 6 (initialize), Task 7 (persist), Task 11 (UI). ✓
- Sequencing: matches spec's "Sequencing" section. ✓

**Placeholder scan:** None remain. Every code block is concrete; every command is runnable.

**Type consistency check:**
- Record type `({String id, String label, int population, double? lat, double? lng})` appears identically in Tasks 1, 2, 5, 7, 11 — ✓.
- `GeoscopeLocationStatus { idle, fetching }` — referenced in Tasks 2, 5, 7, 11 — ✓.
- `GeoscopeToast { denied, unavailable }` — referenced in Tasks 2, 7, 11 — ✓.
- `LocationOutcome` sealed hierarchy: `LocationCoords(double, double)`, `LocationDenied()`, `LocationUnavailable()` — same in Tasks 4, 7 — ✓.
- Method names: `selectNearestMetroFromLocation`, `acceptLocationSuggestion`, `dismissLocationSuggestion`, `clearPendingToast`, `findNearestMetro` — consistent in Tasks 5, 7, 11 — ✓.
- `_autoSelectThresholdKm = 100.0` — single definition in Task 7, referenced via `findNearestMetro` callers only — ✓.
- SharedPreferences keys: `selected_geoscope` (existing), `geoscope_location_denied` (new) — used consistently in Tasks 2, 6, 7 — ✓.
