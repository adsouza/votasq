import 'package:client/services/firestore_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirestoreRepository', () {
    group('geoscopeAncestors', () {
      test('returns ["/"] for global scope', () {
        expect(FirestoreRepository.geoscopeAncestors('/'), ['/']);
      });

      test('returns root + country for single-level scope', () {
        expect(
          FirestoreRepository.geoscopeAncestors('us'),
          ['/', 'us'],
        );
      });

      test('returns root + all ancestors for two-level scope', () {
        expect(
          FirestoreRepository.geoscopeAncestors('us/nyc'),
          ['/', 'us', 'us/nyc'],
        );
      });

      test('returns root + all ancestors for four-level scope', () {
        expect(
          FirestoreRepository.geoscopeAncestors('na/us/ny/nyc'),
          ['/', 'na', 'na/us', 'na/us/ny', 'na/us/ny/nyc'],
        );
      });

      test('returns root + all ancestors for five-level scope', () {
        expect(
          FirestoreRepository.geoscopeAncestors('na/us/ny/nyc/brooklyn'),
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
  });
}
