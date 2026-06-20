import 'dart:async';

import 'package:client/l10n/l10n.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/widgets/relative_timestamp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

/// One card per notification. The whole card surface marks the notification
/// read when tapped; the explicit "Open" button (in the trailing position)
/// navigates to the relevant problem detail.
///
/// Stateful because the actor's `displayName` is resolved asynchronously
/// from `users/{actorUid}` — the card initially renders with a `Someone`
/// placeholder and re-renders with the real name once the lookup returns.
/// Caching is in [FirestoreRepository], so duplicate actor uids across the
/// page share one read.
class NotificationCard extends StatefulWidget {
  const NotificationCard({
    required this.notification,
    required this.onMarkRead,
    super.key,
  });

  final AppNotification notification;
  final ValueChanged<String> onMarkRead;

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  static const _actorPlaceholder = 'Someone';

  String? _resolvedActorName;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveActor());
  }

  Future<void> _resolveActor() async {
    final uid = _actorUidFor(widget.notification.payload);
    if (uid == null) return;
    final name = await context.read<FirestoreRepository>().getDisplayName(uid);
    if (!mounted) return;
    if (name != null && name.isNotEmpty) {
      setState(() => _resolvedActorName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actorName = _resolvedActorName ?? _actorPlaceholder;
    final (title, body, targetProblemId) = _content(
      widget.notification.payload,
      actorName,
      l10n,
    );
    final isUnread = widget.notification.readAt == null;

    return Card(
      color: isUnread ? null : Theme.of(context).colorScheme.surfaceContainer,
      child: InkWell(
        onTap: isUnread
            ? () => widget.onMarkRead(widget.notification.id)
            : null,
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
                      const SizedBox(height: 4),
                      RelativeTimestamp(
                        timestamp: widget.notification.updatedAt,
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
  (String, String, String) _content(
    NotificationPayload payload,
    String actorName,
    AppLocalizations l10n,
  ) {
    return switch (payload) {
      VoteReceivedPayload(:final problemId) => (
        l10n.notificationVoteReceivedTitle,
        l10n.notificationVoteReceivedBody(actorName),
        problemId,
      ),
      ProblemForkedPayload(:final originalProblemId) => (
        l10n.notificationProblemAdaptedTitle,
        l10n.notificationProblemAdaptedBody(actorName),
        originalProblemId,
      ),
      ProblemLinkedPayload(
        :final linkedProblemId,
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
            null => l10n.notificationProblemLinkedBody(actorName),
            ProblemLinkKind.specialization =>
              l10n.notificationProblemLinkedAsSpecializationBody(actorName),
            ProblemLinkKind.generalization =>
              l10n.notificationProblemLinkedAsGeneralizationBody(actorName),
          },
          linkedProblemId,
        ),
      ProblemRevisedPayload(:final problemId) => (
        l10n.notificationProblemRevisedTitle,
        l10n.notificationProblemRevisedBody,
        problemId,
      ),
      ForkAdoptedPayload(:final forkProblemId) => (
        l10n.notificationAdaptationIncorporatedTitle,
        l10n.notificationAdaptationIncorporatedBody,
        forkProblemId,
      ),
    };
  }

  /// Extracts the actor uid from payloads that carry one. Returns null for
  /// types where no actor is relevant (problemRevised / forkAdopted —
  /// their bodies don't reference an actor).
  static String? _actorUidFor(NotificationPayload payload) {
    return switch (payload) {
      VoteReceivedPayload(:final actorUid) => actorUid,
      ProblemForkedPayload(:final actorUid) => actorUid,
      ProblemLinkedPayload(:final actorUid) => actorUid,
      ProblemRevisedPayload() => null,
      ForkAdoptedPayload() => null,
    };
  }
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
