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
  votes: (json['votes'] as num?)?.toInt() ?? 1,
  solved: json['solved'] as bool? ?? false,
);

Map<String, dynamic> _$ProblemToJson(_Problem instance) => <String, dynamic>{
  'id': instance.id,
  'description': instance.description,
  'createdAt': instance.createdAt.toIso8601String(),
  'lastUpdatedAt': instance.lastUpdatedAt.toIso8601String(),
  'votes': instance.votes,
  'solved': instance.solved,
};
