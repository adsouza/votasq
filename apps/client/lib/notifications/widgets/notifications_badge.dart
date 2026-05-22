import 'package:client/l10n/l10n.dart';
import 'package:client/notifications/cubit/notifications_count_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Bell icon for the app bar with an unread-count badge.
///
/// Tapping pushes the /notifications route. The badge count comes from
/// [NotificationsCountCubit]; the icon is rendered even when count is 0.
class NotificationsBadge extends StatelessWidget {
  const NotificationsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCountCubit, int>(
      builder: (context, count) {
        final icon = IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: context.l10n.notificationsBadgeTooltip,
          onPressed: () => context.go('/notifications'),
        );
        if (count == 0) return icon;
        // Anchored to the top-start (top-left in LTR) so the count doesn't
        // get clipped by the right edge of the window when the bell sits
        // at the end of the AppBar actions list.
        return Badge.count(
          count: count,
          alignment: AlignmentDirectional.topStart,
          child: icon,
        );
      },
    );
  }
}
