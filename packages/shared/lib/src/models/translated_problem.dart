import 'package:freezed_annotation/freezed_annotation.dart';

part 'translated_problem.freezed.dart';
part 'translated_problem.g.dart';

@freezed
/// A cached translation of a problem's textual fields.
abstract class TranslatedProblem with _$TranslatedProblem {
  /// Creates a translated problem.
  const factory TranslatedProblem({
    required String description,
    @Default('') String goal,
  }) = _TranslatedProblem;

  /// Deserializes a [TranslatedProblem] from JSON.
  factory TranslatedProblem.fromJson(Map<String, dynamic> json) =>
      _$TranslatedProblemFromJson(json);
}
