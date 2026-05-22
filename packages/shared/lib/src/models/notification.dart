import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification.freezed.dart';
part 'notification.g.dart';

@freezed
/// A single notification record stored under `users/{uid}/notifications/{id}`.
///
/// Named `AppNotification` rather than `Notification` to avoid colliding with
/// Flutter's framework class of that name.
abstract class AppNotification with _$AppNotification {
  /// Creates a notification.
  const factory AppNotification({
    required String id,
    required String recipientUid,
    required NotificationPayload payload,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? readAt,
  }) = _AppNotification;

  /// Deserializes an [AppNotification] from JSON.
  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      _$AppNotificationFromJson(json);
}

@Freezed(unionKey: 'type')
/// The typed body of a notification. The `type` discriminator selects the
/// variant on the wire.
sealed class NotificationPayload with _$NotificationPayload {
  /// Someone voted on a problem you own.
  const factory NotificationPayload.voteReceived({
    required String problemId,
    required String actorUid,
  }) = VoteReceivedPayload;

  /// Someone forked a problem you own (created a new problem with your
  /// problem as its `inspoProblemId`).
  const factory NotificationPayload.problemForked({
    required String originalProblemId,
    required String forkProblemId,
    required String actorUid,
  }) = ProblemForkedPayload;

  /// Someone linked your problem from another problem's `linkedProblemIds`.
  const factory NotificationPayload.problemLinked({
    required String linkedProblemId,
    required String linkerProblemId,
    required String actorUid,
  }) = ProblemLinkedPayload;

  /// A problem you've voted on has a new revision (sent to voters, not the
  /// owner who created the revision).
  const factory NotificationPayload.problemRevised({
    required String problemId,
    required int newVersion,
  }) = ProblemRevisedPayload;

  /// The owner of an original problem incorporated field values from your
  /// fork into their new revision.
  const factory NotificationPayload.forkAdopted({
    required String forkProblemId,
    required String originalProblemId,
    required int newVersion,
  }) = ForkAdoptedPayload;

  /// Deserializes a [NotificationPayload] from JSON, using the `type` field
  /// to select the variant.
  factory NotificationPayload.fromJson(Map<String, dynamic> json) =>
      _$NotificationPayloadFromJson(json);
}
