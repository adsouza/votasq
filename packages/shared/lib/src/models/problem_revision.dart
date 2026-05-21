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
    // Set when this revision was created by copying field values from a fork
    // of the parent problem (the "Use this here" action on the detail page).
    // Used by the notifications producer to emit `forkAdopted` notifications
    // to the fork's owner. Null for normal user-authored revisions.
    String? copiedFromProblemId,
  }) = _ProblemRevision;

  /// Deserializes a [ProblemRevision] from JSON.
  factory ProblemRevision.fromJson(Map<String, dynamic> json) =>
      _$ProblemRevisionFromJson(json);
}
