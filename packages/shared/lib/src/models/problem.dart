import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared/src/models/problem_link.dart';

part 'problem.freezed.dart';
part 'problem.g.dart';

@freezed
/// Represents a core aggregate.
abstract class Problem with _$Problem {
  /// Creates problems.
  const factory Problem({
    required String id,
    required String description,
    required DateTime createdAt,
    required DateTime lastUpdatedAt,
    required String ownerId,
    @Default('') String goal,
    @Default('/') String geoscope,
    String? lang,
    @Default(1) int votes,
    @Default([]) List<String> complaints,
    @Default(false) bool solved,
    @Default(false) bool hidden,
    @Default(1) int version,
    // Source ProblemRevision that inspired this problem (set when forked).
    // The two `inspo*` fields together identify a revision and must be set
    // or null as a pair. Kept as two flat fields rather than a composite
    // string so `inspoProblemId` can be queried directly to enumerate all
    // forks of a problem. Write-once: only populated at creation time and
    // never modified afterwards.
    String? inspoProblemId,
    int? inspoVersion,
    @Default([]) List<String> linkedProblemIds,
    // Outgoing typed links from this problem's perspective. An entry
    // `{targetId: B, kind: specialization}` means "B is a specialization of
    // this problem"; the inverse `{targetId: this.id, kind: generalization}`
    // is mirrored onto B by paired writes. A pair appears in at most one of
    // `linkedProblemIds` or `typedLinks`, never both.
    @Default(<ProblemLink>[]) List<ProblemLink> typedLinks,
  }) = _Problem;

  /// This factory is what the Server uses to encode and Client uses to decode
  factory Problem.fromJson(Map<String, dynamic> json) =>
      _$ProblemFromJson(json);
}
