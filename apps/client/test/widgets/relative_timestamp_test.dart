import 'package:client/l10n/l10n.dart';
import 'package:client/l10n/timeago_locales.dart';
import 'package:client/widgets/relative_timestamp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // RelativeTimestamp reads timeago's global locale table; register it the
  // way bootstrap() does so non-bundled locales (e.g. 'sw') resolve.
  setUpAll(registerTimeagoLocales);

  Widget buildSubject(DateTime timestamp, {Locale? locale, String? label}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RelativeTimestamp(timestamp: timestamp, label: label),
      ),
    );
  }

  testWidgets('renders an English relative time', (tester) async {
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

    await tester.pumpWidget(buildSubject(threeDaysAgo));

    expect(find.text('3 days ago'), findsOneWidget);
  });

  testWidgets('localizes for a hand-written locale (Swahili)', (tester) async {
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

    await tester.pumpWidget(
      buildSubject(threeDaysAgo, locale: const Locale('sw')),
    );

    expect(find.text('siku 3 zilizopita'), findsOneWidget);
  });

  testWidgets('prefixes an optional label', (tester) async {
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

    await tester.pumpWidget(buildSubject(threeDaysAgo, label: 'Edited'));

    expect(find.text('Edited 3 days ago'), findsOneWidget);
  });
}
