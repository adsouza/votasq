import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_preferences.freezed.dart';
part 'notification_preferences.g.dart';

@freezed
/// User-level notification opt-ins, stored as a field on the user doc.
///
/// `perType` is keyed by notification type name (e.g., `voteReceived`,
/// `problemForked`). Missing entries — and missing per-channel booleans —
/// mean "use the channel's default for that type", applied in code rather
/// than the database.
abstract class NotificationPreferences with _$NotificationPreferences {
  /// Creates a [NotificationPreferences].
  const factory NotificationPreferences({
    @Default(<String, ChannelPreferences>{})
    Map<String, ChannelPreferences> perType,
  }) = _NotificationPreferences;

  /// Deserializes from JSON.
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      _$NotificationPreferencesFromJson(json);
}

@freezed
/// Per-channel opt-ins for a single notification type.
///
/// `null` for any channel means "use the default"; resolve via
/// [resolveNotificationOptIn].
abstract class ChannelPreferences with _$ChannelPreferences {
  /// Creates a [ChannelPreferences].
  const factory ChannelPreferences({
    bool? inApp,
    bool? email,
    bool? push,
  }) = _ChannelPreferences;

  /// Deserializes from JSON.
  factory ChannelPreferences.fromJson(Map<String, dynamic> json) =>
      _$ChannelPreferencesFromJson(json);
}

/// Delivery channels for notifications.
enum NotificationChannel {
  /// The in-app notifications list (the per-user Firestore subcollection).
  inApp,

  /// Push notifications via FCM.
  push,

  /// Email notifications (planned; no worker yet).
  email,
}

/// Resolves whether a given (type, channel) combination should deliver to the
/// user, taking stored prefs and channel defaults into account.
///
/// Defaults: `inApp` and `push` are on for every type; `email` is off (no
/// email worker exists yet). Mirror these defaults in any other language
/// consuming this schema (e.g. the Cloud Functions TS code).
bool resolveNotificationOptIn({
  required NotificationPreferences prefs,
  required String type,
  required NotificationChannel channel,
}) {
  final stored = prefs.perType[type];
  return switch (channel) {
    NotificationChannel.inApp => stored?.inApp ?? true,
    NotificationChannel.push => stored?.push ?? true,
    NotificationChannel.email => stored?.email ?? false,
  };
}
