import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/services/firestore_repository.dart';

/// Holds the unread notification count for the current user, refreshed via
/// Firestore's `count()` aggregation. The live notifications subscription
/// doesn't drive this directly — the badge calls [refresh] on app focus
/// and after a mark-read action.
class NotificationsCountCubit extends Cubit<int> {
  NotificationsCountCubit({required FirestoreRepository repo})
    : _repo = repo,
      super(0);

  final FirestoreRepository _repo;
  String? _uid;

  /// Set the user the badge counts for. Triggers an immediate refresh.
  Future<void> watch(String uid) async {
    _uid = uid;
    await refresh();
  }

  /// Clear the count (e.g. on sign-out).
  void reset() {
    _uid = null;
    emit(0);
  }

  /// Re-query Firestore for the current unread count.
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final count = await _repo.unreadNotificationCount(uid);
      emit(count);
    } on Exception catch (e, st) {
      log('unreadNotificationCount failed: $e', stackTrace: st);
    }
  }
}
