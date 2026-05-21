import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/notifications/cubit/notifications_state.dart';
import 'package:client/services/firestore_repository.dart';

class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({required FirestoreRepository repo})
    : _repo = repo,
      super(const NotificationsState());

  final FirestoreRepository _repo;
  StreamSubscription<dynamic>? _subscription;
  static const _pageSize = 20;
  bool _isLoadingMore = false;
  String? _uid;

  /// Subscribe to real-time notifications for [uid]. Cancels any prior
  /// subscription so it's safe to call across auth changes.
  void subscribe(String uid) {
    _uid = uid;
    emit(state.copyWith(status: NotificationsStatus.loading));
    unawaited(_subscription?.cancel());
    _subscription = _repo
        .watchNotifications(uid)
        .listen(
          (result) {
            emit(
              state.copyWith(
                status: NotificationsStatus.success,
                notifications: result.notifications,
                lastDocument: () => result.lastDoc,
                hasMore: result.notifications.length >= _pageSize,
              ),
            );
          },
          onError: (Object e, StackTrace st) {
            log('watchNotifications failed: $e', stackTrace: st);
            emit(state.copyWith(status: NotificationsStatus.failure));
          },
        );
  }

  /// Append the next page of notifications.
  Future<void> loadMore() async {
    final uid = _uid;
    if (uid == null ||
        _isLoadingMore ||
        !state.hasMore ||
        state.lastDocument == null) {
      return;
    }
    _isLoadingMore = true;
    try {
      final result = await _repo.getNotifications(
        uid,
        startAfter: state.lastDocument,
      );
      emit(
        state.copyWith(
          notifications: [...state.notifications, ...result.notifications],
          lastDocument: () => result.lastDoc,
          hasMore: result.notifications.length >= _pageSize,
        ),
      );
    } on Exception catch (e, st) {
      log('loadMore notifications failed: $e', stackTrace: st);
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Cancel the live subscription and clear local state (e.g. on sign-out).
  Future<void> clear() async {
    _uid = null;
    await _subscription?.cancel();
    _subscription = null;
    emit(const NotificationsState());
  }

  /// Mark a single notification as read. The live subscription will pick up
  /// the resulting state change.
  Future<void> markAsRead(String notificationId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _repo.markNotificationRead(uid, notificationId);
    } on Exception catch (e, st) {
      log('markNotificationRead failed: $e', stackTrace: st);
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
