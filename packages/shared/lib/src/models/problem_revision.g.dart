// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'problem_revision.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProblemRevision _$ProblemRevisionFromJson(Map<String, dynamic> json) =>
    _ProblemRevision(
      description: json['description'] as String,
      version: (json['version'] as num).toInt(),
      archivedAt: DateTime.parse(json['archivedAt'] as String),
      restoredFrom: (json['restoredFrom'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ProblemRevisionToJson(_ProblemRevision instance) =>
    <String, dynamic>{
      'description': instance.description,
      'version': instance.version,
      'archivedAt': instance.archivedAt.toIso8601String(),
      'restoredFrom': instance.restoredFrom,
    };
