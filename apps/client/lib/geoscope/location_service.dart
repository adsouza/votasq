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
