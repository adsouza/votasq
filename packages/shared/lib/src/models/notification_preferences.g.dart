// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_preferences.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NotificationPreferences _$NotificationPreferencesFromJson(
  Map<String, dynamic> json,
) => _NotificationPreferences(
  perType:
      (json['perType'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, ChannelPreferences.fromJson(e as Map<String, dynamic>)),
      ) ??
      const <String, ChannelPreferences>{},
);

Map<String, dynamic> _$NotificationPreferencesToJson(
  _NotificationPreferences instance,
) => <String, dynamic>{
  'perType': instance.perType.map((k, e) => MapEntry(k, e.toJson())),
};

_ChannelPreferences _$ChannelPreferencesFromJson(Map<String, dynamic> json) =>
    _ChannelPreferences(
      inApp: json['inApp'] as bool?,
      email: json['email'] as bool?,
      push: json['push'] as bool?,
    );

Map<String, dynamic> _$ChannelPreferencesToJson(_ChannelPreferences instance) =>
    <String, dynamic>{
      'inApp': instance.inApp,
      'email': instance.email,
      'push': instance.push,
    };
