import 'package:server/src/db.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Round-trips a fully-populated [Problem] through [Db.problemToDocument]
/// and [Db.documentToProblem] and asserts equality.
///
/// The hand-rolled (de)serializers in `db.dart` build the Firestore field
/// map by hand — they do NOT go through freezed's `fromJson`/`toJson`, so
/// `@Default(...)` on a model field never reaches the wire. A new [Problem]
/// field that the (de)serializers forget to handle would silently default
/// on read and disappear on write. That's exactly how the May 2026 `hidden`
/// gap shipped: server creates produced docs missing `hidden`, the listing
/// query's `hidden == false` filter excluded them, and every newly created
/// problem vanished from `GET /api/problems`.
///
/// To catch that drift mechanically, every field in the fixture below is
/// set to a *non-default* value. If a future field is added to [Problem]
/// with an `@Default(...)` and the (de)serializers drop it, the equality
/// check fails on that field with a precise diff.
void main() {
  test(
    'Problem round-trips through Db.problemToDocument/documentToProblem',
    () {
      final problem = Problem(
        id: 'p-roundtrip-1',
        description: 'Round-trip every Problem field',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        lastUpdatedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
        ownerId: 'user-roundtrip',
        goal: 'A non-default goal',
        geoscope: 'na/us/ny',
        lang: 'es',
        votes: 42,
        complaints: const ['complainer-a', 'complainer-b'],
        solved: true,
        hidden: true,
        version: 7,
        inspoProblemId: 'inspo-source-id',
        inspoVersion: 3,
        linkedProblemIds: const ['linked-a', 'linked-b'],
        typedLinks: const [
          ProblemLink(
            targetId: 'target-spec',
            kind: ProblemLinkKind.specialization,
          ),
          ProblemLink(
            targetId: 'target-gen',
            kind: ProblemLinkKind.generalization,
          ),
        ],
      );

      final doc = Db.problemToDocument(problem);
      final roundTripped = Db.documentToProblem(doc, problem.id);

      expect(roundTripped, equals(problem));
    },
  );
}
