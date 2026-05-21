import 'package:bloc_test/bloc_test.dart';
import 'package:client/notifications/cubit/notifications_cubit.dart';
import 'package:client/notifications/cubit/notifications_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

// DocumentSnapshot is @sealed but we need a testable stand-in for state.
// ignore: subtype_of_sealed_class
class _FakeDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {}

AppNotification _notification({
  String id = 'voteReceived__p1__u1',
  String recipientUid = 'ownerA',
  DateTime? readAt,
}) {
  final now = DateTime.utc(2026, 5, 21);
  return AppNotification(
    id: id,
    recipientUid: recipientUid,
    payload: const NotificationPayload.voteReceived(
      problemId: 'p1',
      actorUid: 'u1',
    ),
    createdAt: now,
    updatedAt: now,
    readAt: readAt,
  );
}

void main() {
  late FirestoreRepository repo;

  setUp(() {
    repo = _MockFirestoreRepository();
  });

  group('NotificationsCubit', () {
    test('initial state is correct', () {
      final cubit = NotificationsCubit(repo: repo);
      expect(cubit.state.status, NotificationsStatus.initial);
      expect(cubit.state.notifications, isEmpty);
      expect(cubit.state.hasMore, isTrue);
      addTearDown(cubit.close);
    });

    blocTest<NotificationsCubit, NotificationsState>(
      'subscribe emits loading then success',
      build: () {
        when(
          () => repo.watchNotifications(
            any(),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) => Stream.value(
            (
              notifications: [_notification()],
              lastDoc: _FakeDocumentSnapshot(),
            ),
          ),
        );
        return NotificationsCubit(repo: repo);
      },
      act: (cubit) => cubit.subscribe('ownerA'),
      expect: () => [
        isA<NotificationsState>().having(
          (s) => s.status,
          'status',
          NotificationsStatus.loading,
        ),
        isA<NotificationsState>()
            .having((s) => s.status, 'status', NotificationsStatus.success)
            .having((s) => s.notifications.length, 'count', 1),
      ],
    );

    blocTest<NotificationsCubit, NotificationsState>(
      'markAsRead delegates to the repo',
      build: () {
        when(
          () => repo.watchNotifications(
            any(),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) => const Stream.empty());
        when(
          () => repo.markNotificationRead(any(), any()),
        ).thenAnswer((_) async {});
        return NotificationsCubit(repo: repo);
      },
      act: (cubit) async {
        cubit.subscribe('ownerA');
        await cubit.markAsRead('voteReceived__p1__u1');
      },
      verify: (_) {
        verify(
          () => repo.markNotificationRead('ownerA', 'voteReceived__p1__u1'),
        ).called(1);
      },
    );

    blocTest<NotificationsCubit, NotificationsState>(
      'clear resets state to initial',
      build: () {
        when(
          () => repo.watchNotifications(
            any(),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) => Stream.value(
            (
              notifications: [_notification()],
              lastDoc: _FakeDocumentSnapshot(),
            ),
          ),
        );
        return NotificationsCubit(repo: repo);
      },
      act: (cubit) async {
        cubit.subscribe('ownerA');
        // Let the stream-listener microtask deliver the success state before
        // we clear, so we actually exercise the reset transition.
        await Future<void>.delayed(Duration.zero);
        await cubit.clear();
      },
      verify: (cubit) {
        expect(cubit.state.status, NotificationsStatus.initial);
        expect(cubit.state.notifications, isEmpty);
      },
    );
  });
}
