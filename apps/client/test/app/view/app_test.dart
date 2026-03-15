// Ignore for testing purposes
// ignore_for_file: prefer_const_constructors

import 'package:client/app/app.dart';
import 'package:client/problems/problems.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App', () {
    testWidgets('renders problemsPage', (tester) async {
      await tester.pumpWidget(App());
      expect(find.byType(ProblemsPage), findsOneWidget);
    });
  });
}
