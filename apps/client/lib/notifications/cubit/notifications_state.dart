import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';

enum NotificationsStatus { initial, loading, success, failure }

class NotificationsState {
  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.notifications = const [],
    this.lastDocument,
    this.hasMore = true,
  });

  final NotificationsStatus status;
  final List<AppNotification> notifications;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? notifications,
    DocumentSnapshot? Function()? lastDocument,
    bool? hasMore,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      notifications: notifications ?? this.notifications,
      lastDocument: lastDocument != null ? lastDocument() : this.lastDocument,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}
