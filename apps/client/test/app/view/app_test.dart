import 'package:client/app/app.dart';
import 'package:client/problems/problems.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

void main() {
  group('App', () {
    late FirestoreRepository repo;

    setUp(() {
      repo = _MockFirestoreRepository();
      when(() => repo.watchProblems(limit: any(named: 'limit'))).thenAnswer(
        (_) => const Stream.empty(),
      );
    });

    testWidgets('renders problemsPage', (tester) async {
      await tester.pumpWidget(App(firestoreRepository: repo));
      expect(find.byType(ProblemsPage), findsOneWidget);
    });
  });
}
