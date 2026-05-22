import 'dart:async';

import 'package:client/app/app.dart';
import 'package:client/auth/auth.dart';
import 'package:client/problems/problems.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/notification_registration_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

class _MockFeedbackRepository extends Mock implements FeedbackRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockNotificationRegistrationService extends Mock
    implements NotificationRegistrationService {}

void main() {
  group('App', () {
    late FirestoreRepository repo;
    late FeedbackRepository feedbackRepo;
    late AuthRepository authRepo;
    late NotificationRegistrationService notificationRegistration;

    setUp(() {
      repo = _MockFirestoreRepository();
      feedbackRepo = _MockFeedbackRepository();
      authRepo = _MockAuthRepository();
      notificationRegistration = _MockNotificationRegistrationService();
      when(
        () => repo.watchProblems(
          geoscope: any(named: 'geoscope'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) => const Stream.empty());
      when(() => repo.getGeoscopes()).thenAnswer((_) async => []);
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
          notificationRegistration: notificationRegistration,
        ),
      );
      expect(find.byType(ProblemsPage), findsOneWidget);
    });
  });
}
