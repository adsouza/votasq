import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:meta/meta.dart';

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

  /// Read-only check of the OS's current authorization status. Does NOT
  /// prompt the user — safe to call on startup. Returns true iff the
  /// app currently holds permission (whileInUse or always). Used to
  /// reconcile a previously-persisted `locationDenied` flag against the
  /// live OS state on initialize.
  Future<bool> hasPermission();
}

/// Default impl, backed by the `geolocator` package. Requests coarse
/// accuracy (~5 km on iOS/Android) — metro-centroid matching doesn't
/// benefit from sub-km precision.
///
/// Note: on Web, requires a secure context (HTTPS or localhost).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  /// Hard ceiling on the entire location lookup. Defensive against
  /// platform-impl timeout bugs (e.g. geolocator_web 4.1.3 ignored
  /// our inner timeLimit due to a microseconds/milliseconds unit
  /// confusion, causing the picker's spinner to hang indefinitely).
  /// Loud-named so a future cleanup is more likely to notice it's
  /// load-bearing.
  @visibleForTesting
  static const overallTimeout = Duration(seconds: 10);

  @override
  Future<LocationOutcome> getApproximateLocation() async {
    try {
      return await _resolveOutcome().timeout(
        overallTimeout,
        onTimeout: () => const LocationUnavailable(),
      );
    } on TimeoutException {
      return const LocationUnavailable();
    } on LocationServiceDisabledException {
      return const LocationUnavailable();
    } on PermissionDeniedException {
      // Only treat as a sticky denial if the OS still reports denial
      // after the exception. macOS has a race window where the dialog's
      // response hasn't propagated yet — we don't want to persist a
      // false denial.
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.deniedForever
          ? const LocationDenied()
          : const LocationUnavailable();
    } on Exception {
      return const LocationUnavailable();
    }
  }

  @override
  Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  Future<LocationOutcome> _resolveOutcome() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationUnavailable();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // Only sticky-persist on `deniedForever`. A bare `denied` here may
    // be a transient race (macOS in particular returns the pre-dialog
    // status before the delegate callback fires) — treat as unavailable
    // so the next attempt re-asks rather than silently hiding the row
    // forever.
    if (permission == LocationPermission.deniedForever) {
      return const LocationDenied();
    }
    if (permission == LocationPermission.denied) {
      return const LocationUnavailable();
    }
    // Web's `low` path uses the browser's Network Location Service (Wi-Fi
    // triangulation + IP geo), which is unreliable on networks where the
    // underlying Google endpoint is blocked or slow (privacy extensions,
    // VPNs, corporate proxies). On the browser, the "low/high" knob is
    // not gated by a precise-location toggle UI like it is on iOS, so
    // there's no UX cost to using `high` on web — and it routes through
    // CoreLocation / OS APIs instead, which actually returns.
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: kIsWeb ? LocationAccuracy.high : LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return LocationCoords(position.latitude, position.longitude);
  }
}
