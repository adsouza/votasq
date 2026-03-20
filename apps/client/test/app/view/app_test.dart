import 'dart:async';

import 'package:client/app/app.dart';
import 'package:client/auth/auth.dart';
import 'package:client/problems/problems.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockFeedbackRepository extends Mock implements FeedbackRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  group('App', () {
    late FirestoreRepository repo;
    late FeedbackRepository feedbackRepo;
    late AuthRepository authRepo;

    setUp(() {
      repo = _MockFirestoreRepository();
      feedbackRepo = _MockFeedbackRepository();
      authRepo = _MockAuthRepository();
      when(() => repo.watchProblems(limit: any(named: 'limit'))).thenAnswer(
        (_) => const Stream.empty(),
      );
      when(() => authRepo.authStateChanges).thenAnswer(
        (_) => const Stream<User?>.empty(),
      );
      when(() => authRepo.currentUser).thenReturn(null);
      when(() => authRepo.isAuthenticated).thenReturn(false);
    });

    testWidgets('renders problemsPage', (tester) async {
      await tester.pumpWidget(
        App(
          firestoreRepository: repo,
          feedbackRepository: feedbackRepo,
          authRepository: authRepo,
        ),
      );
      expect(find.byType(ProblemsPage), findsOneWidget);
    });
  });
}
