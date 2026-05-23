// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'problem_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProblemLink _$ProblemLinkFromJson(Map<String, dynamic> json) => _ProblemLink(
  targetId: json['targetId'] as String,
  kind: $enumDecode(_$ProblemLinkKindEnumMap, json['kind']),
);

Map<String, dynamic> _$ProblemLinkToJson(_ProblemLink instance) =>
    <String, dynamic>{
      'targetId': instance.targetId,
      'kind': _$ProblemLinkKindEnumMap[instance.kind]!,
    };

const _$ProblemLinkKindEnumMap = {
  ProblemLinkKind.specialization: 'specialization',
  ProblemLinkKind.generalization: 'generalization',
};
