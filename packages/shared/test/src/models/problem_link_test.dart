import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('ProblemLink', () {
    test('roundtrips specialization through JSON', () {
      const original = ProblemLink(
        targetId: 'abc',
        kind: ProblemLinkKind.specialization,
      );

      final json = original.toJson();
      expect(json['targetId'], equals('abc'));
      expect(json['kind'], equals('specialization'));

      final decoded = ProblemLink.fromJson(json);
      expect(decoded, equals(original));
    });

    test('roundtrips generalization through JSON', () {
      const original = ProblemLink(
        targetId: 'def',
        kind: ProblemLinkKind.generalization,
      );

      final json = original.toJson();
      expect(json['kind'], equals('generalization'));

      final decoded = ProblemLink.fromJson(json);
      expect(decoded, equals(original));
    });

    test('inverse flips specialization and generalization', () {
      expect(
        ProblemLinkKind.specialization.inverse,
        equals(ProblemLinkKind.generalization),
      );
      expect(
        ProblemLinkKind.generalization.inverse,
        equals(ProblemLinkKind.specialization),
      );
    });
  });

  group('Problem.typedLinks', () {
    test('roundtrips with mixed kinds and generic linked ids', () {
      final original = Problem(
        id: 'p1',
        description: 'd',
        createdAt: DateTime.utc(2026, 5, 22),
        lastUpdatedAt: DateTime.utc(2026, 5, 22),
        ownerId: 'u1',
        linkedProblemIds: const ['plain1', 'plain2'],
        typedLinks: const [
          ProblemLink(
            targetId: 'special',
            kind: ProblemLinkKind.specialization,
          ),
          ProblemLink(
            targetId: 'general',
            kind: ProblemLinkKind.generalization,
          ),
        ],
      );

      final decoded = Problem.fromJson(original.toJson());
      expect(decoded, equals(original));
      expect(decoded.typedLinks, hasLength(2));
    });

    test('defaults to empty when absent from JSON', () {
      final json = {
        'id': 'p1',
        'description': 'd',
        'createdAt': DateTime.utc(2026, 5, 22).toIso8601String(),
        'lastUpdatedAt': DateTime.utc(2026, 5, 22).toIso8601String(),
        'ownerId': 'u1',
      };

      final decoded = Problem.fromJson(json);
      expect(decoded.typedLinks, isEmpty);
      expect(decoded.linkedProblemIds, isEmpty);
    });
  });
}
