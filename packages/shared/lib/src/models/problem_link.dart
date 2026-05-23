import 'package:freezed_annotation/freezed_annotation.dart';

part 'problem_link.freezed.dart';
part 'problem_link.g.dart';

/// Kind of a typed relationship between two problems.
///
/// Stored from the perspective of the problem that holds the
/// [ProblemLink]. For example, an entry `{targetId: B, kind: specialization}`
/// on problem A means "B is a specialization of A". The inverse on B is
/// `{targetId: A, kind: generalization}`.
enum ProblemLinkKind {
  /// The target is more specific than the source.
  @JsonValue('specialization')
  specialization,

  /// The target is more general than the source.
  @JsonValue('generalization')
  generalization;

  /// The inverse kind used when mirroring the edge on the other problem.
  ProblemLinkKind get inverse {
    switch (this) {
      case ProblemLinkKind.specialization:
        return ProblemLinkKind.generalization;
      case ProblemLinkKind.generalization:
        return ProblemLinkKind.specialization;
    }
  }
}

@freezed
/// A directional, typed link from one problem to another.
abstract class ProblemLink with _$ProblemLink {
  /// Creates a typed problem link.
  const factory ProblemLink({
    required String targetId,
    required ProblemLinkKind kind,
  }) = _ProblemLink;

  /// Deserializes a [ProblemLink] from JSON.
  factory ProblemLink.fromJson(Map<String, dynamic> json) =>
      _$ProblemLinkFromJson(json);
}
