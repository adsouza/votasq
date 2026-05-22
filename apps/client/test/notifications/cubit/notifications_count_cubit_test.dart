import 'package:bloc_test/bloc_test.dart';
import 'package:client/notifications/cubit/notifications_count_cubit.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestoreRepository extends Mock implements FirestoreRepository {}

void main() {
  late FirestoreRepository repo;

  setUp(() {
    repo = _MockFirestoreRepository();
  });

  group('NotificationsCountCubit', () {
    test('initial count is 0', () {
      expect(NotificationsCountCubit(repo: repo).state, 0);
    });

    blocTest<NotificationsCountCubit, int>(
      'watch emits the latest count for the user',
      build: () {
        when(
          () => repo.unreadNotificationCount(any()),
        ).thenAnswer((_) async => 3);
        return NotificationsCountCubit(repo: repo);
      },
      act: (cubit) => cubit.watch('ownerA'),
      expect: () => [3],
      verify: (_) {
        verify(() => repo.unreadNotificationCount('ownerA')).called(1);
      },
    );

    blocTest<NotificationsCountCubit, int>(
      'refresh re-queries the count for the current user',
      build: () {
        var calls = 0;
        when(() => repo.unreadNotificationCount(any())).thenAnswer(
          (_) async => ++calls, // 1, then 2
        );
        return NotificationsCountCubit(repo: repo);
      },
      act: (cubit) async {
        await cubit.watch('ownerA');
        await cubit.refresh();
      },
      expect: () => [1, 2],
    );

    blocTest<NotificationsCountCubit, int>(
      'reset clears the count and stops responding to refresh',
      build: () {
        when(
          () => repo.unreadNotificationCount(any()),
        ).thenAnswer((_) async => 5);
        return NotificationsCountCubit(repo: repo);
      },
      act: (cubit) async {
        await cubit.watch('ownerA');
        cubit.reset();
        await cubit.refresh();
      },
      expect: () => [5, 0],
    );
  });
}
