import 'package:client/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

/// One card per notification. The whole card surface marks the notification
/// read when tapped; the explicit "Open" button (in the trailing position)
/// navigates to the relevant problem detail.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    required this.notification,
    required this.onMarkRead,
    super.key,
  });

  final AppNotification notification;
  final ValueChanged<String> onMarkRead;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (title, body, targetProblemId) = _content(notification.payload, l10n);
    final isUnread = notification.readAt == null;

    return Card(
      color: isUnread ? null : Theme.of(context).colorScheme.surfaceContainer,
      child: InkWell(
        onTap: isUnread ? () => onMarkRead(notification.id) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Opacity(
            // Read notifications fade so unread ones visually dominate.
            opacity: isUnread ? 1.0 : 0.5,
            child: Row(
              children: [
                _ReadStateIndicator(isUnread: isUnread),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => context.go('/problems/$targetProblemId'),
                  child: Text(l10n.notificationOpenButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the localized (title, body, targetProblemId) tuple for a payload.
  ///
  /// `targetProblemId` is the id of the problem the "Open" button should
  /// navigate to — always the problem the recipient cares about (their own
  /// problem for the user-action types; the problem they voted on for
  /// problemRevised; their fork for forkAdopted).
  ///
  /// Actor display names aren't fetched here — for v1 we render the actor's
  /// uid suffix. The cubit could be extended later to enrich actor names
  /// via a separate user lookup if needed.
  (String, String, String) _content(
    NotificationPayload payload,
    AppLocalizations l10n,
  ) {
    return switch (payload) {
      VoteReceivedPayload(:final problemId, :final actorUid) => (
        l10n.notificationVoteReceivedTitle,
        l10n.notificationVoteReceivedBody(_actorDisplay(actorUid)),
        problemId,
      ),
      ProblemForkedPayload(
        :final originalProblemId,
        :final actorUid,
      ) =>
        (
          l10n.notificationProblemForkedTitle,
          l10n.notificationProblemForkedBody(_actorDisplay(actorUid)),
          originalProblemId,
        ),
      ProblemLinkedPayload(
        :final linkedProblemId,
        :final actorUid,
        :final kind,
      ) =>
        (
          switch (kind) {
            null => l10n.notificationProblemLinkedTitle,
            ProblemLinkKind.specialization =>
              l10n.notificationProblemLinkedAsSpecializationTitle,
            ProblemLinkKind.generalization =>
              l10n.notificationProblemLinkedAsGeneralizationTitle,
          },
          switch (kind) {
            null => l10n.notificationProblemLinkedBody(_actorDisplay(actorUid)),
            ProblemLinkKind.specialization =>
              l10n.notificationProblemLinkedAsSpecializationBody(
                _actorDisplay(actorUid),
              ),
            ProblemLinkKind.generalization =>
              l10n.notificationProblemLinkedAsGeneralizationBody(
                _actorDisplay(actorUid),
              ),
          },
          linkedProblemId,
        ),
      ProblemRevisedPayload(:final problemId) => (
        l10n.notificationProblemRevisedTitle,
        l10n.notificationProblemRevisedBody,
        problemId,
      ),
      ForkAdoptedPayload(:final forkProblemId) => (
        l10n.notificationForkAdoptedTitle,
        l10n.notificationForkAdoptedBody,
        forkProblemId,
      ),
    };
  }

  /// v1 actor-name placeholder. We only have the actor's uid on the
  /// notification doc; resolving to a display name requires fetching
  /// `users/{uid}`, which we'll add when the UI gains a place to surface
  /// it. For now we show a short, anonymized form so the body is readable.
  String _actorDisplay(String uid) => 'Someone';
}

/// Checkbox-style indicator to the left of each notification.
///
/// An empty outlined square when the notification is unread (waiting to be
/// acknowledged); a checked square in the primary color when read. Same
/// glyph footprint between states so the layout doesn't shift.
class _ReadStateIndicator extends StatelessWidget {
  const _ReadStateIndicator({required this.isUnread});

  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    return Icon(
      isUnread ? Icons.check_box_outline_blank : Icons.check_box,
      size: 20,
      color: isUnread
          ? Theme.of(context).colorScheme.onSurface
          : Theme.of(context).colorScheme.primary,
    );
  }
}
