// The single-method `LocationService` abstract is intentional: it exists so
// `GeoscopeCubit` can accept a fake in unit tests. A top-level function
// (what `one_member_abstracts` suggests) wouldn't be substitutable.
// ignore_for_file: one_member_abstracts

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
      return const LocationDenied();
    } on Exception {
      return const LocationUnavailable();
    }
  }

  Future<LocationOutcome> _resolveOutcome() async {
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
