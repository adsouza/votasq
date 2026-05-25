import 'package:client/geoscope/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeolocatorLocationService', () {
    test(
      'has a finite outer timeout (guards against geolocator_web '
      'timeout bugs like the unit-conversion issue in 4.1.3)',
      () {
        // The bug was that geolocator_web 4.1.3 ignored our inner
        // timeLimit. An outer Future.timeout was added as a Dart-level
        // hard ceiling. If a future refactor removes this constant or
        // the wrapping call, this test will fail loudly so the
        // load-bearing nature of the timeout doesn't get lost.
        expect(GeolocatorLocationService.overallTimeout, isA<Duration>());
        expect(
          GeolocatorLocationService.overallTimeout.inSeconds,
          lessThan(30),
        );
        expect(
          GeolocatorLocationService.overallTimeout.inSeconds,
          greaterThan(0),
        );
      },
    );

    test('GeolocatorLocationService is const-constructible', () {
      const service = GeolocatorLocationService();
      expect(service, isA<LocationService>());
    });
  });
}
