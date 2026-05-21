// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppNotification _$AppNotificationFromJson(Map<String, dynamic> json) =>
    _AppNotification(
      id: json['id'] as String,
      recipientUid: json['recipientUid'] as String,
      payload: NotificationPayload.fromJson(
        json['payload'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      readAt: json['readAt'] == null
          ? null
          : DateTime.parse(json['readAt'] as String),
    );

Map<String, dynamic> _$AppNotificationToJson(_AppNotification instance) =>
    <String, dynamic>{
      'id': instance.id,
      'recipientUid': instance.recipientUid,
      'payload': instance.payload.toJson(),
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'readAt': instance.readAt?.toIso8601String(),
    };

VoteReceivedPayload _$VoteReceivedPayloadFromJson(Map<String, dynamic> json) =>
    VoteReceivedPayload(
      problemId: json['problemId'] as String,
      actorUid: json['actorUid'] as String,
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$VoteReceivedPayloadToJson(
  VoteReceivedPayload instance,
) => <String, dynamic>{
  'problemId': instance.problemId,
  'actorUid': instance.actorUid,
  'type': instance.$type,
};

ProblemForkedPayload _$ProblemForkedPayloadFromJson(
  Map<String, dynamic> json,
) => ProblemForkedPayload(
  originalProblemId: json['originalProblemId'] as String,
  forkProblemId: json['forkProblemId'] as String,
  actorUid: json['actorUid'] as String,
  $type: json['type'] as String?,
);

Map<String, dynamic> _$ProblemForkedPayloadToJson(
  ProblemForkedPayload instance,
) => <String, dynamic>{
  'originalProblemId': instance.originalProblemId,
  'forkProblemId': instance.forkProblemId,
  'actorUid': instance.actorUid,
  'type': instance.$type,
};

ProblemLinkedPayload _$ProblemLinkedPayloadFromJson(
  Map<String, dynamic> json,
) => ProblemLinkedPayload(
  linkedProblemId: json['linkedProblemId'] as String,
  linkerProblemId: json['linkerProblemId'] as String,
  actorUid: json['actorUid'] as String,
  $type: json['type'] as String?,
);

Map<String, dynamic> _$ProblemLinkedPayloadToJson(
  ProblemLinkedPayload instance,
) => <String, dynamic>{
  'linkedProblemId': instance.linkedProblemId,
  'linkerProblemId': instance.linkerProblemId,
  'actorUid': instance.actorUid,
  'type': instance.$type,
};

ProblemRevisedPayload _$ProblemRevisedPayloadFromJson(
  Map<String, dynamic> json,
) => ProblemRevisedPayload(
  problemId: json['problemId'] as String,
  newVersion: (json['newVersion'] as num).toInt(),
  $type: json['type'] as String?,
);

Map<String, dynamic> _$ProblemRevisedPayloadToJson(
  ProblemRevisedPayload instance,
) => <String, dynamic>{
  'problemId': instance.problemId,
  'newVersion': instance.newVersion,
  'type': instance.$type,
};

ForkAdoptedPayload _$ForkAdoptedPayloadFromJson(Map<String, dynamic> json) =>
    ForkAdoptedPayload(
      forkProblemId: json['forkProblemId'] as String,
      originalProblemId: json['originalProblemId'] as String,
      newVersion: (json['newVersion'] as num).toInt(),
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$ForkAdoptedPayloadToJson(ForkAdoptedPayload instance) =>
    <String, dynamic>{
      'forkProblemId': instance.forkProblemId,
      'originalProblemId': instance.originalProblemId,
      'newVersion': instance.newVersion,
      'type': instance.$type,
    };
