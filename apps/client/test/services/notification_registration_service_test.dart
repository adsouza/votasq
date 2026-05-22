import 'dart:async';

import 'package:client/services/firestore_repository.dart';
import 'package:client/services/notification_registration_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class _MockNotificationSettings extends Mock implements NotificationSettings {}

void main() {
  late FirestoreRepository repo;
  late FirebaseMessaging messaging;
  late NotificationSettings authorizedSettings;
  late NotificationSettings deniedSettings;
  late StreamController<String> refreshController;

  setUp(() {
    repo = _MockFirestoreRepository();
    messaging = _MockFirebaseMessaging();
    authorizedSettings = _MockNotificationSettings();
    deniedSettings = _MockNotificationSettings();
    refreshController = StreamController<String>.broadcast();

    when(
      () => authorizedSettings.authorizationStatus,
    ).thenReturn(AuthorizationStatus.authorized);
    when(
      () => deniedSettings.authorizationStatus,
    ).thenReturn(AuthorizationStatus.denied);

    when(() => messaging.onTokenRefresh).thenAnswer(
      (_) => refreshController.stream,
    );

    when(
      () => repo.registerFcmToken(
        uid: any(named: 'uid'),
        token: any(named: 'token'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => repo.unregisterFcmToken(
        uid: any(named: 'uid'),
        token: any(named: 'token'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    await refreshController.close();
  });

  group('NotificationRegistrationService.register', () {
    test('writes the token when permission is authorized', () async {
      when(
        () => messaging.requestPermission(
          alert: any(named: 'alert'),
          announcement: any(named: 'announcement'),
          badge: any(named: 'badge'),
          carPlay: any(named: 'carPlay'),
          criticalAlert: any(named: 'criticalAlert'),
          provisional: any(named: 'provisional'),
          sound: any(named: 'sound'),
        ),
      ).thenAnswer((_) async => authorizedSettings);
      when(
        () => messaging.getToken(vapidKey: any(named: 'vapidKey')),
      ).thenAnswer((_) async => 'fcm-token-abc');

      final service = NotificationRegistrationService(
        repo: repo,
        messaging: messaging,
      );
      await service.register('user-a');

      verify(
        () => repo.registerFcmToken(
          uid: 'user-a',
          token: 'fcm-token-abc',
          platform: any(named: 'platform'),
        ),
      ).called(1);
    });

    test('skips the token write when permission is denied', () async {
      when(
        () => messaging.requestPermission(
          alert: any(named: 'alert'),
          announcement: any(named: 'announcement'),
          badge: any(named: 'badge'),
          carPlay: any(named: 'carPlay'),
          criticalAlert: any(named: 'criticalAlert'),
          provisional: any(named: 'provisional'),
          sound: any(named: 'sound'),
        ),
      ).thenAnswer((_) async => deniedSettings);

      final service = NotificationRegistrationService(
        repo: repo,
        messaging: messaging,
      );
      await service.register('user-a');

      verifyNever(
        () => repo.registerFcmToken(
          uid: any(named: 'uid'),
          token: any(named: 'token'),
          platform: any(named: 'platform'),
        ),
      );
    });

    test('persists refreshed tokens when the refresh stream fires', () async {
      when(
        () => messaging.requestPermission(
          alert: any(named: 'alert'),
          announcement: any(named: 'announcement'),
          badge: any(named: 'badge'),
          carPlay: any(named: 'carPlay'),
          criticalAlert: any(named: 'criticalAlert'),
          provisional: any(named: 'provisional'),
          sound: any(named: 'sound'),
        ),
      ).thenAnswer((_) async => authorizedSettings);
      when(
        () => messaging.getToken(vapidKey: any(named: 'vapidKey')),
      ).thenAnswer((_) async => 'initial-token');

      final service = NotificationRegistrationService(
        repo: repo,
        messaging: messaging,
      );
      await service.register('user-a');

      refreshController.add('rotated-token');
      // Let the listener microtask drain.
      await Future<void>.delayed(Duration.zero);

      verify(
        () => repo.registerFcmToken(
          uid: 'user-a',
          token: 'rotated-token',
          platform: any(named: 'platform'),
        ),
      ).called(1);
    });
  });

  group('NotificationRegistrationService.unregister', () {
    test('deletes the current token for the given uid', () async {
      when(
        () => messaging.getToken(vapidKey: any(named: 'vapidKey')),
      ).thenAnswer((_) async => 'fcm-token-abc');

      final service = NotificationRegistrationService(
        repo: repo,
        messaging: messaging,
      );
      await service.unregister('user-a');

      verify(
        () => repo.unregisterFcmToken(
          uid: 'user-a',
          token: 'fcm-token-abc',
        ),
      ).called(1);
    });
  });
}
