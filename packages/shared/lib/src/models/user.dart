import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
/// Represents a user with a vote budget and onboarding-tip counters.
abstract class User with _$User {
  /// Creates a user.
  const factory User({
    required String uid,
    required DateTime lastActiveAt,
    required int votes,
    String? displayName,
    @Default(0) int problemDetailsViewCount,
    @Default(0) int votesCastCount,
  }) = _User;

  /// Deserializes a [User] from JSON.
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
