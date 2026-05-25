# "Use my location" in the geoscope picker

**Status:** Design approved 2026-05-25. Awaiting implementation plan.

## Problem

The geoscope picker overlay (`apps/client/lib/problems/widgets/geoscope_picker.dart`) currently requires the user to find their metro area by either drilling through the hierarchy (superstate → state → metro) or substring-filtering the flat list. For users whose metro is in the list, this is friction; for users who don't know their region's id (e.g. "Krung Thep" vs. "Bangkok"), it can be a dead end.

We want to offer an optional "Use my location" affordance that snaps the user to the nearest known metro using the device's coarse location.

## Goals

- One-tap selection of the nearest metro for users who consent to share approximate location.
- Honest UX when the nearest metro is far away (no silent mis-selection).
- Zero new infra: no callable function, no reverse-geocoding service, no shared model changes.
- Works on iOS, Android, Web, macOS, and Windows (Linux is intentionally not in our release matrix — see memory `[No Linux client]`).
- Respect a user who has denied location: don't keep offering the button.

## Non-goals

- Precise location (city-block / GPS-grade). Coarse (~5 km) is plenty for metro centroids.
- Continuous tracking / "always on" location.
- Reverse-geocoding to country fallback.
- An in-app settings toggle to re-enable location after denial. (Possible follow-up; out of scope here.)
- Analytics on button usage.

## Approach (summary)

Add optional `lat`/`lng` fields to each metro doc in the `geoscopes` collection. On tap, the client requests one-shot coarse location via the `geolocator` package, runs Haversine in memory against the ~50 metro centroids, and either auto-selects (within 100 km) or shows a confirmable suggestion. Permission denial flips a persistent `SharedPreferences` flag that hides the button thereafter.

## Data model

### Firestore `geoscopes` collection

Each metro doc gets two new optional fields:

- `lat: number` — WGS84 decimal degrees, range [-90, 90].
- `lng: number` — WGS84 decimal degrees, range [-180, 180].

State, country, and supranational docs are unchanged: they simply have no `lat`/`lng`. The client treats absence as null.

The collection is read-only to clients (`firestore.rules` line 127–129). No rules change is required: the existing `allow read: if true` rule has no field allowlist that would block the new fields.

### Client record type

`GeoscopeState.availableGeoscopes` currently uses an inline record:

```dart
List<({String id, String label, int population})>
```

Extend to:

```dart
List<({String id, String label, int population, double? lat, double? lng})>
```

### Read-side parsing

`FirestoreRepository.getGeoscopes()` reads the new fields as nullable doubles:

```dart
lat: (data['lat'] as num?)?.toDouble(),
lng: (data['lng'] as num?)?.toDouble(),
```

This matters because of CLAUDE.md's read-side trap (`_docToProblem` silently dropping the `hidden` flag in May 2026). A unit test must seed a metro doc with `lat`/`lng` present and assert it round-trips.

## Backfill

### New tool

`apps/server/tool/seed_geoscope_coords.dart`, modeled on `copy_geoscopes_to_emulator.dart`. A one-shot Dart script that:

- Defines a `Map<String, ({double lat, double lng})>` keyed by geoscope id (e.g. `'us/ca/sfbay'` → `(lat: 37.7793, lng: -122.4193)`) as a top-of-file constants block. Pre-populated by the assistant with best-effort centroids for all ~50 known metros (see "Curation" below).
- Flags:
  - `--emulator` — writes to the local Firestore emulator (requires `FIRESTORE_EMULATOR_HOST` env var, same as the copy tool).
  - `--prod` — writes to the production `votasq` project. Explicit opt-in, no default.
  - `--dry-run` — prints what would be written without committing.
- Uses `update_mask` to set only `lat` and `lng`, preserving existing `id`/`label`/`population`.
- Idempotent: re-running overwrites with the same values.

### Curation

The constants map is pre-populated by the assistant with best-effort lat/lng for each known metro id. Reference points: city hall / central business district for most; for sprawling metros (Bay Area, GTA, Southern California, Greater Manila) the geographic centroid of the metro region. A one-line `//` comment per row names the reference point so a reviewer can sanity-check.

The user reviews the pre-populated values, runs the tool against the emulator, smoke-tests the picker, then runs the same tool with `--prod`.

## Matching algorithm

### Helper (pure, static)

Lives on `GeoscopeCubit` next to the existing `resolveGeoscope`:

```dart
@visibleForTesting
static ({String id, double distanceKm})? findNearestMetro({
  required double lat,
  required double lng,
  required List<({String id, String label, int population, double? lat, double? lng})> available,
}) {
  // Iterate, skipping rows with null lat/lng; Haversine; return the min.
  // Returns null only when no row has coords at all (degenerate, pre-seed state).
}
```

### Haversine

Standard formula, R = 6371 km, `dart:math.sin`/`cos`/`atan2`. ~10 lines. Pure and unit-tested with known pairs (SF↔NYC ≈ 4130 km, London↔Paris ≈ 344 km).

### Threshold

`_autoSelectThresholdKm = 100`.

- Within 100 km → auto-select, picker dismisses.
- Outside 100 km → no selection; the cubit emits a `locationSuggestion` and the picker UI swaps the "Use my location" row for a confirmation row.

The threshold is a soft signal for "auto vs. confirm-first", not a match cutoff. The nearest metro is *always* the nearest; the threshold only decides whether to trust it silently.

## Cubit + state

### Location service abstraction

New file `apps/client/lib/geoscope/location_service.dart`:

```dart
abstract class LocationService {
  /// Returns null on denial, timeout, or platform unavailability.
  /// Implementations must distinguish denied (permanent, callee
  /// signal) from unavailable (transient) via [LocationOutcome].
  Future<LocationOutcome> getApproximateLocation();
}

sealed class LocationOutcome {}
class LocationCoords extends LocationOutcome {
  LocationCoords(this.lat, this.lng);
  final double lat;
  final double lng;
}
class LocationDenied extends LocationOutcome {}
class LocationUnavailable extends LocationOutcome {}
```

Default implementation wraps `geolocator`:

1. `checkPermission()` — if `denied`, call `requestPermission()`.
2. If `denied` or `deniedForever` post-request → return `LocationDenied`.
3. If `serviceEnabled()` is false → return `LocationUnavailable`.
4. `getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)))`.
5. On `TimeoutException` or platform exception → return `LocationUnavailable`.
6. Otherwise → return `LocationCoords(lat, lng)`.

Injected into `GeoscopeCubit` via constructor so tests can substitute a fake (same pattern as `_repo`).

### New state fields

```dart
enum GeoscopeLocationStatus { idle, fetching }
enum GeoscopeToast { denied, unavailable }

class GeoscopeState {
  // ... existing fields
  final GeoscopeLocationStatus locationStatus;          // transient
  final ({String id, double distanceKm})? locationSuggestion; // transient
  final GeoscopeToast? pendingToast;                    // transient, one-shot
  final bool locationDenied;                            // persistent
}
```

`locationStatus` only needs `idle` and `fetching`. `denied` / `unavailable` are signaled through `locationDenied` (persisted) and toast emissions respectively — they don't need a sticky enum value.

### New cubit methods

- `Future<void> selectNearestMetroFromLocation()` — orchestrates: emit `fetching` → call `LocationService` → branch:
  - `LocationCoords` + nearest within threshold → call `selectGeoscope(id)`, emit `idle`.
  - `LocationCoords` + nearest outside threshold → emit `idle` + `locationSuggestion = (id, distanceKm)`.
  - `LocationDenied` → persist `geoscope_location_denied=true`, emit `idle` + `locationDenied: true` + `pendingToast: GeoscopeToast.denied`.
  - `LocationUnavailable` → emit `idle` + `pendingToast: GeoscopeToast.unavailable`. No persistence.

`pendingToast` is a nullable `GeoscopeToast?` state field consumed by the picker's `BlocListener`. After firing the toast, the listener calls a `cubit.clearPendingToast()` method that emits a state with `pendingToast: null`. This avoids a `Stream` surface on the cubit and matches the project's existing one-shot-event idioms.
- `void acceptLocationSuggestion()` — calls `selectGeoscope(suggestionId)` and clears `locationSuggestion`.
- `void dismissLocationSuggestion()` — clears `locationSuggestion` without selecting.

### Updated `initialize`

Existing `initialize` is extended to also load the persisted denial flag:

```dart
final locationDenied = prefs.getBool('geoscope_location_denied') ?? false;
emit(state.copyWith(..., locationDenied: locationDenied));
```

## Picker UI changes

File: `apps/client/lib/problems/widgets/geoscope_picker.dart`.

### Layout

Insert a new `ListTile`-style row between the filter `TextField` and the divider preceding the list. The row is the FIRST thing under the search, in three transient renderings:

1. **Idle** — `ListTile` with `leading: Icon(Icons.my_location)`, `title: Text(l10n.geoscopeUseMyLocation)`, tappable.
2. **Fetching** — same row, leading replaced with a 16 dp `CircularProgressIndicator`; tap disabled.
3. **Suggestion (outside threshold)** — two-line `ListTile`:
   - `title: Text(metroLabel)`
   - `subtitle: Text(l10n.geoscopeSuggestionDistance(distanceKm.round()))` → "About 180 km away — use anyway?" The cubit stores the raw double; the UI rounds to the nearest int for display.
   - `trailing: Row` with `TextButton('Use')` (calls `acceptLocationSuggestion`) and `IconButton(Icons.close)` (calls `dismissLocationSuggestion`).

### Hide-when-denied

At the top of `_GeoscopePickerSheet.build`, after reading the cubit, gate the row on `!state.locationDenied`. When true, render nothing in the row's slot; the filter sits flush against the divider.

### Reactive wiring

The picker is currently a `StatefulWidget` reading via `context.read`. Wrap the new row and the listening logic in a `BlocConsumer<GeoscopeCubit, GeoscopeState>`:

- `buildWhen` — rebuild on `locationStatus`, `locationSuggestion`, or `locationDenied` change.
- `listenWhen` — fire on transitions to a toast-emitting state.
- `listener` — call `toastification` with the appropriate localized message and color (orange for both denial and unavailability, per the project's existing color-coding pattern from commit `b614401`).

### Auto-dismiss on success

When `selectGeoscope` is called by `selectNearestMetroFromLocation` (in-threshold path) or `acceptLocationSuggestion`, the existing flow runs (`selectGeoscope` emits `selectedGeoscope` change → no automatic pop). To match the existing manual-tap UX, the picker's listener also calls `Navigator.of(context).pop()` when `locationStatus` transitions from `fetching` to `idle` AND the selected geoscope changed during that transition. (Equivalent to how `_select` calls `Navigator.pop` today.)

## Localization

Three new keys in `apps/client/lib/l10n/arb/app_en.arb`:

- `geoscopeUseMyLocation`: "Use my location"
- `geoscopeSuggestionDistance`: "About {distanceKm} km away — use anyway?" with `{distanceKm}` as an integer placeholder.
- `geoscopeLocationDenied`: "Location access was denied — please pick manually."
- `geoscopeLocationUnavailable`: "Location is unavailable — please pick manually."

Per memory `[ARB translation policy]`, all four keys must land in every one of the 24 locales (`app_*.arb`) in the same PR. English values may stand in as placeholders for languages the implementer doesn't translate; the keys themselves must exist or the generator crashes and CI fails.

## Permissions & platform plumbing

### Package

Add to `apps/client/pubspec.yaml`:

```yaml
geolocator: ^14.0.0  # or latest stable at implementation time
```

### Per-platform

| Platform | Plumbing | File |
|---|---|---|
| iOS | `NSLocationWhenInUseUsageDescription` = "Used to suggest the metro area nearest you when picking a geoscope." | `apps/client/ios/Runner/Info.plist` |
| Android | `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />` | `apps/client/android/app/src/main/AndroidManifest.xml` |
| macOS | `com.apple.security.personal-information.location` entitlement + Info.plist usage description string | `apps/client/macos/Runner/DebugProfile.entitlements`, `Release.entitlements`, and `Info.plist` |
| Windows | None — relies on system-level Location toggle | — |
| Web | None — uses browser-native Geolocation API. Requires HTTPS or localhost (a one-line comment at the call site notes this). | — |

### Accuracy choice

`LocationAccuracy.low` — ~5 km on iOS/Android. Specifically chosen because:
- Metro centroid matching doesn't benefit from sub-km accuracy.
- On iOS 14+, low accuracy can be served by reduced-accuracy mode, sidestepping the precise-location toggle UI in the permission dialog.
- On Android, uses the network/Wi-Fi/cell locator (fast first fix, low battery).

### App Check interaction

None. Location is OS-level; nothing crosses Firebase.

## Error handling matrix

| Failure | Persistent flag set? | UI |
|---|---|---|
| OS permission denied (denied or deniedForever) | YES (`geoscope_location_denied = true`) | One-time orange toast; row vanishes immediately and stays gone. |
| OS location services disabled | No | Orange toast; row stays for next attempt. |
| Timeout (8 s no fix) | No | Orange toast; row stays. |
| Got coords, no metro doc has lat/lng (pre-seed) | No | Orange "unavailable" toast (defensive — should never happen post-seed). |
| Got coords, nearest within 100 km | No | Picker pops; selection updated. |
| Got coords, nearest outside 100 km | No | Row swaps to suggestion. User confirms or dismisses. |

## Testing

### Unit

1. **`findNearestMetro` (pure, static)** — `apps/client/test/geoscope/cubit/geoscope_cubit_test.dart`:
   - Known-pair distance assertions (SF↔NYC ≈ 4130 km; London↔Paris ≈ 344 km).
   - Skips rows with null `lat`/`lng`.
   - Empty input → returns null.
   - Returns absolute nearest regardless of distance.

2. **`selectNearestMetroFromLocation` (bloc_test)** — same file, with a fake `LocationService`:
   - `LocationCoords` within threshold → emits `fetching` then `idle` with new `selectedGeoscope`; `selectGeoscope` persisted to `SharedPreferences`.
   - `LocationCoords` outside threshold → emits `idle` + `locationSuggestion`, no selection change.
   - `LocationDenied` → emits `idle` + `locationDenied: true`; persisted to `SharedPreferences`.
   - `LocationUnavailable` → emits `idle`; `locationDenied` unchanged; no persistence.

3. **`initialize`** — reads `geoscope_location_denied` from prefs and reflects in state.

4. **`FirestoreRepository.getGeoscopes` (read-shape)** — `apps/client/test/services/firestore_repository_test.dart`:
   - Seed a metro doc *with* `lat`/`lng` set → assert they round-trip through the record type.
   - Seed a state-tier doc *without* `lat`/`lng` → assert record's lat/lng are null.

### Widget

5. **Picker widget tests** — `apps/client/test/problems/widgets/geoscope_picker_test.dart`:
   - Default state → "Use my location" row present.
   - `locationStatus = fetching` → spinner visible, tap disabled.
   - `locationSuggestion` non-null → two-line row with Use/Cancel actions; tapping Use calls `acceptLocationSuggestion`.
   - `locationDenied = true` → row entirely absent.

### Manual

6. Smoke-test on:
   - Web (Chrome, https or localhost)
   - macOS (with debug-token registered per memory `[Firebase App Check rollout state]`)
   - At least one mobile (iOS or Android)
   
   Verify: permission dialog text reads sensibly; row hides after denial; suggestion appears when outside 100 km (test from a non-metro location or by spoofing coords).

### Out of scope for automated tests

- Actual `geolocator` calls. The injected `LocationService` keeps the matching cubit free of platform dependencies.
- Cross-platform permission dialog UI variations.

## Sequencing

This spec maps to a single PR (one focused feature). Suggested implementation order:

1. Data model + repo read-side change + tests.
2. `LocationService` abstraction + default `geolocator`-backed implementation.
3. Cubit changes (state fields, new methods, `initialize` update) + bloc tests.
4. Backfill tool + assistant-curated coords map.
5. Run backfill against emulator; manually verify the picker renders the new row.
6. Picker UI changes + widget tests.
7. ARB strings in all 24 locales.
8. Platform manifest entries (Info.plist, AndroidManifest, entitlements).
9. Add `geolocator` to `pubspec.yaml`; `melos setup` to refresh lockfiles.
10. `melos format`, `flutter analyze apps packages`, full test suite.
11. After user-approved emulator testing: run backfill tool with `--prod`.

## Open questions

None remaining at design approval. Implementation can begin from the plan once written.
