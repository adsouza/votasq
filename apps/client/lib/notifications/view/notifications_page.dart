import 'dart:async';

import 'package:client/auth/auth.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/notifications/cubit/notifications_count_cubit.dart';
import 'package:client/notifications/cubit/notifications_cubit.dart';
import 'package:client/notifications/cubit/notifications_state.dart';
import 'package:client/notifications/view/notification_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final uid = context.read<UserCubit>().state.userId;
    if (uid != null) {
      context.read<NotificationsCubit>().subscribe(uid);
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      unawaited(context.read<NotificationsCubit>().loadMore());
    }
  }

  Future<void> _markRead(String notificationId) async {
    await context.read<NotificationsCubit>().markAsRead(notificationId);
    if (!mounted) return;
    await context.read<NotificationsCountCubit>().refresh();
  }

  Future<void> _markAllRead() async {
    await context.read<NotificationsCubit>().markAllAsRead();
    if (!mounted) return;
    await context.read<NotificationsCountCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsPageTitle),
        actions: [
          BlocBuilder<NotificationsCountCubit, int>(
            builder: (context, count) => IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: l10n.notificationsMarkAllReadTooltip,
              onPressed: count == 0 ? null : () => unawaited(_markAllRead()),
            ),
          ),
        ],
      ),
      body: BlocBuilder<NotificationsCubit, NotificationsState>(
        builder: (context, state) {
          return switch (state.status) {
            NotificationsStatus.initial || NotificationsStatus.loading
                when state.notifications.isEmpty =>
              const Center(child: CircularProgressIndicator()),
            NotificationsStatus.failure when state.notifications.isEmpty =>
              Center(child: Text(l10n.notificationsEmpty)),
            _ when state.notifications.isEmpty => Center(
              child: Text(l10n.notificationsEmpty),
            ),
            _ => ListView.builder(
              controller: _scrollController,
              itemCount: state.notifications.length,
              itemBuilder: (context, index) => NotificationCard(
                notification: state.notifications[index],
                onMarkRead: _markRead,
              ),
            ),
          };
        },
      ),
    );
  }
}
