import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:client/services/firestore_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Owns the FCM permission + token lifecycle for the signed-in user.
///
/// Call [register] on sign-in: it requests notification permission,
/// fetches the current token, writes it under
/// `users/{uid}/fcmTokens/{sha256(token)}`, and subscribes to
/// [FirebaseMessaging.onTokenRefresh] so rotations are persisted too.
///
/// Call [unregister] on sign-out: it deletes this device's token doc so
/// the next user of the same physical device doesn't inherit pushes meant
/// for the previous account.
///
/// Idempotent — safe to call [register] across multiple sign-in cycles;
/// the previous refresh subscription is cancelled before a new one is
/// installed.
class NotificationRegistrationService {
  NotificationRegistrationService({
    required FirestoreRepository repo,
    FirebaseMessaging? messaging,
    String? webVapidKey,
  }) : _repo = repo,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _webVapidKey = webVapidKey;

  final FirestoreRepository _repo;
  final FirebaseMessaging _messaging;
  final String? _webVapidKey;

  String? _currentUid;
  StreamSubscription<String>? _refreshSubscription;

  /// Register the current device's FCM token for [uid]. Permission is
  /// requested (a no-op grant on Android; an explicit prompt on iOS/macOS
  /// /web on first call). A denied prompt is logged and otherwise ignored —
  /// the function returns normally rather than throwing so the rest of
  /// sign-in continues.
  Future<void> register(String uid) async {
    await _refreshSubscription?.cancel();
    _currentUid = uid;

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      log('FCM: notification permission denied; skipping token registration');
      return;
    }

    final token = await _fetchToken();
    if (token != null) {
      try {
        await _repo.registerFcmToken(
          uid: uid,
          token: token,
          platform: _platformName(),
        );
      } on Exception catch (e, st) {
        log('FCM: registerFcmToken failed: $e', stackTrace: st);
      }
    }

    _refreshSubscription = _messaging.onTokenRefresh.listen((newToken) async {
      final activeUid = _currentUid;
      if (activeUid == null) return;
      try {
        await _repo.registerFcmToken(
          uid: activeUid,
          token: newToken,
          platform: _platformName(),
        );
      } on Exception catch (e, st) {
        log('FCM: token-refresh persist failed: $e', stackTrace: st);
      }
    });
  }

  /// Drop this device's token registration for [uid] (called on sign-out).
  Future<void> unregister(String uid) async {
    final token = await _fetchToken();
    if (token != null) {
      try {
        await _repo.unregisterFcmToken(uid: uid, token: token);
      } on Exception catch (e, st) {
        log('FCM: unregisterFcmToken failed: $e', stackTrace: st);
      }
    }
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _currentUid = null;
  }

  /// Surfaces FCM messages received while the app is foregrounded. The
  /// notification doc is also written server-side, so the in-app reader's
  /// live Firestore subscription will pick it up — this listener is only
  /// here in case you want to add a banner/toast later. For v1 it just
  /// logs so the dev loop confirms delivery without rendering anything.
  StreamSubscription<RemoteMessage> listenForegroundMessages(
    void Function(RemoteMessage) onMessage,
  ) {
    return FirebaseMessaging.onMessage.listen(onMessage);
  }

  Future<String?> _fetchToken() async {
    try {
      return await _messaging.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
    } on Exception catch (e, st) {
      // Typical on macOS/iOS without an APNs key configured for the
      // Firebase project, or on web without a VAPID key.
      log('FCM: getToken failed: $e', stackTrace: st);
      return null;
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
}
