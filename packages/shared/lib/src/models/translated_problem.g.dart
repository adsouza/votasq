// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translated_problem.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TranslatedProblem _$TranslatedProblemFromJson(Map<String, dynamic> json) =>
    _TranslatedProblem(
      description: json['description'] as String,
      goal: json['goal'] as String? ?? '',
    );

Map<String, dynamic> _$TranslatedProblemToJson(_TranslatedProblem instance) =>
    <String, dynamic>{
      'description': instance.description,
      'goal': instance.goal,
    };
