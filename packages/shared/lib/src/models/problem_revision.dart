import 'package:freezed_annotation/freezed_annotation.dart';

part 'problem_revision.freezed.dart';
part 'problem_revision.g.dart';

@freezed
/// An immutable snapshot of a problem at a specific version.
abstract class ProblemRevision with _$ProblemRevision {
  /// Creates a problem revision.
  const factory ProblemRevision({
    required String description,
    required int version,
    required DateTime archivedAt,
    @Default('') String goal,
    int? restoredFrom,
  }) = _ProblemRevision;

  /// Deserializes a [ProblemRevision] from JSON.
  factory ProblemRevision.fromJson(Map<String, dynamic> json) =>
      _$ProblemRevisionFromJson(json);
}
