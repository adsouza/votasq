import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
/// Represents a user with a vote budget.
abstract class User with _$User {
  /// Creates a user.
  const factory User({
    required String uid,
    required DateTime lastActiveAt,
    required int votes,
    String? displayName,
  }) = _User;

  /// Deserializes a [User] from JSON.
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
