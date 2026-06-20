import 'package:client/l10n/l10n.dart';
import 'package:client/l10n/timeago_locales.dart';
import 'package:client/notifications/view/notification_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  // The widget reads timeago's global locale table; register it like the app
  // does in bootstrap(). 'en' is bundled by timeago, but the custom locales
  // (e.g. 'sw') only exist once this runs.
  setUpAll(registerTimeagoLocales);

  // problemRevised carries no actor, so the card never touches
  // FirestoreRepository — no provider needed to render it.
  AppNotification notificationUpdatedAt(DateTime updatedAt) => AppNotification(
    id: 'n1',
    recipientUid: 'me',
    payload: const NotificationPayload.problemRevised(
      problemId: 'p1',
      newVersion: 2,
    ),
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );

  Widget buildSubject(AppNotification notification, {Locale? locale}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: NotificationCard(notification: notification, onMarkRead: (_) {}),
      ),
    );
  }

  group('NotificationCard relative timestamp', () {
    testWidgets('renders an English relative time from updatedAt', (
      tester,
    ) async {
      final updatedAt = DateTime.now().subtract(const Duration(hours: 9));

      await tester.pumpWidget(buildSubject(notificationUpdatedAt(updatedAt)));
      await tester.pump();

      expect(find.text('9 hours ago'), findsOneWidget);
    });

    testWidgets('localizes the relative time for a hand-written locale', (
      tester,
    ) async {
      final updatedAt = DateTime.now().subtract(const Duration(hours: 9));

      await tester.pumpWidget(
        buildSubject(
          notificationUpdatedAt(updatedAt),
          locale: const Locale('sw'),
        ),
      );
      await tester.pump();

      expect(find.text('saa 9 zilizopita'), findsOneWidget);
    });
  });
}
