// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_User _$UserFromJson(Map<String, dynamic> json) => _User(
  uid: json['uid'] as String,
  lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
  votes: (json['votes'] as num).toInt(),
  displayName: json['displayName'] as String?,
);

Map<String, dynamic> _$UserToJson(_User instance) => <String, dynamic>{
  'uid': instance.uid,
  'lastActiveAt': instance.lastActiveAt.toIso8601String(),
  'votes': instance.votes,
  'displayName': instance.displayName,
};
