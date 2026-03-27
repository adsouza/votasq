import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('geoscopeAncestors', () {
    test('returns ["/"] for global scope', () {
      expect(geoscopeAncestors('/'), ['/']);
    });

    test('returns root + country for single-level scope', () {
      expect(
        geoscopeAncestors('us'),
        ['/', 'us'],
      );
    });

    test('returns root + all ancestors for two-level scope', () {
      expect(
        geoscopeAncestors('us/nyc'),
        ['/', 'us', 'us/nyc'],
      );
    });

    test('returns root + all ancestors for four-level scope', () {
      expect(
        geoscopeAncestors('na/us/ny/nyc'),
        ['/', 'na', 'na/us', 'na/us/ny', 'na/us/ny/nyc'],
      );
    });

    test('returns root + all ancestors for five-level scope', () {
      expect(
        geoscopeAncestors('na/us/ny/nyc/brooklyn'),
        [
          '/',
          'na',
          'na/us',
          'na/us/ny',
          'na/us/ny/nyc',
          'na/us/ny/nyc/brooklyn',
        ],
      );
    });
  });
}
