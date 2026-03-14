// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Success<T> _$SuccessFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) => Success<T>(fromJsonT(json['data']), $type: json['runtimeType'] as String?);

Map<String, dynamic> _$SuccessToJson<T>(
  Success<T> instance,
  Object? Function(T value) toJsonT,
) => <String, dynamic>{
  'data': toJsonT(instance.data),
  'runtimeType': instance.$type,
};

Error<T> _$ErrorFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) => Error<T>(json['message'] as String, $type: json['runtimeType'] as String?);

Map<String, dynamic> _$ErrorToJson<T>(
  Error<T> instance,
  Object? Function(T value) toJsonT,
) => <String, dynamic>{
  'message': instance.message,
  'runtimeType': instance.$type,
};

Loading<T> _$LoadingFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) => Loading<T>($type: json['runtimeType'] as String?);

Map<String, dynamic> _$LoadingToJson<T>(
  Loading<T> instance,
  Object? Function(T value) toJsonT,
) => <String, dynamic>{'runtimeType': instance.$type};
