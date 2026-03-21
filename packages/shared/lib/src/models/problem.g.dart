// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'problem.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Problem _$ProblemFromJson(Map<String, dynamic> json) => _Problem(
  id: json['id'] as String,
  description: json['description'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  lastUpdatedAt: DateTime.parse(json['lastUpdatedAt'] as String),
  ownerId: json['ownerId'] as String,
  geoscope: json['geoscope'] as String? ?? '/',
  votes: (json['votes'] as num?)?.toInt() ?? 1,
  complaints:
      (json['complaints'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  solved: json['solved'] as bool? ?? false,
  version: (json['version'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _$ProblemToJson(_Problem instance) => <String, dynamic>{
  'id': instance.id,
  'description': instance.description,
  'createdAt': instance.createdAt.toIso8601String(),
  'lastUpdatedAt': instance.lastUpdatedAt.toIso8601String(),
  'ownerId': instance.ownerId,
  'geoscope': instance.geoscope,
  'votes': instance.votes,
  'complaints': instance.complaints,
  'solved': instance.solved,
  'version': instance.version,
};
