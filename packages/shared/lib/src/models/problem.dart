import 'package:freezed_annotation/freezed_annotation.dart';

part 'problem.freezed.dart';
part 'problem.g.dart';

@freezed
/// Represents a core aggregate.
abstract class Problem with _$Problem {
  /// Creates problems.
  const factory Problem({
    required String id,
    required String description,
    @Default(1) int votes,
    @Default(false) bool solved,
  }) = _Problem;

  /// This factory is what the Server uses to encode and Client uses to decode
  factory Problem.fromJson(Map<String, dynamic> json) =>
      _$ProblemFromJson(json);
}
