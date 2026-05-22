import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('AppNotification', () {
    test('roundtrips a voteReceived payload through JSON', () {
      final original = AppNotification(
        id: 'voteReceived__p1__u1',
        recipientUid: 'ownerA',
        payload: const NotificationPayload.voteReceived(
          problemId: 'p1',
          actorUid: 'u1',
        ),
        createdAt: DateTime.utc(2026, 5, 21, 10),
        updatedAt: DateTime.utc(2026, 5, 21, 10),
      );

      final json = original.toJson();
      expect(json['payload'], containsPair('type', 'voteReceived'));
      expect(json['payload'], containsPair('problemId', 'p1'));

      final decoded = AppNotification.fromJson(json);
      expect(decoded, equals(original));
    });

    test('roundtrips a forkAdopted payload through JSON', () {
      final original = AppNotification(
        id: 'forkAdopted__fork1__orig1__v2',
        recipientUid: 'forkOwner',
        payload: const NotificationPayload.forkAdopted(
          forkProblemId: 'fork1',
          originalProblemId: 'orig1',
          newVersion: 2,
        ),
        createdAt: DateTime.utc(2026, 5, 21, 10),
        updatedAt: DateTime.utc(2026, 5, 21, 11),
        readAt: DateTime.utc(2026, 5, 21, 12),
      );

      final json = original.toJson();
      expect(json['payload'], containsPair('type', 'forkAdopted'));
      expect(json['payload'], containsPair('newVersion', 2));

      final decoded = AppNotification.fromJson(json);
      expect(decoded, equals(original));
      expect(decoded.readAt, equals(DateTime.utc(2026, 5, 21, 12)));
    });

    test('roundtrips a problemLinked payload with a kind', () {
      final original = AppNotification(
        id: 'problemLinked__linked__linker__special',
        recipientUid: 'ownerA',
        payload: const NotificationPayload.problemLinked(
          linkedProblemId: 'linked',
          linkerProblemId: 'linker',
          actorUid: 'u1',
          kind: ProblemLinkKind.specialization,
        ),
        createdAt: DateTime.utc(2026, 5, 22, 10),
        updatedAt: DateTime.utc(2026, 5, 22, 10),
      );

      final json = original.toJson();
      expect(json['payload'], containsPair('type', 'problemLinked'));
      expect(json['payload'], containsPair('kind', 'specialization'));

      final decoded = AppNotification.fromJson(json);
      expect(decoded, equals(original));
    });

    test('discriminates all five payload variants by their type key', () {
      final variants = <NotificationPayload, String>{
        const NotificationPayload.voteReceived(
          problemId: 'p1',
          actorUid: 'u1',
        ): 'voteReceived',
        const NotificationPayload.problemForked(
          originalProblemId: 'orig',
          forkProblemId: 'fork',
          actorUid: 'u1',
        ): 'problemForked',
        const NotificationPayload.problemLinked(
          linkedProblemId: 'linked',
          linkerProblemId: 'linker',
          actorUid: 'u1',
        ): 'problemLinked',
        const NotificationPayload.problemRevised(
          problemId: 'p1',
          newVersion: 3,
        ): 'problemRevised',
        const NotificationPayload.forkAdopted(
          forkProblemId: 'fork',
          originalProblemId: 'orig',
          newVersion: 2,
        ): 'forkAdopted',
      };

      for (final entry in variants.entries) {
        final json = entry.key.toJson();
        expect(
          json['type'],
          equals(entry.value),
          reason: 'expected type=${entry.value} for ${entry.key.runtimeType}',
        );
        final decoded = NotificationPayload.fromJson(json);
        expect(decoded, equals(entry.key));
      }
    });
  });

  group('NotificationPreferences', () {
    test('roundtrips through JSON', () {
      const original = NotificationPreferences(
        perType: {
          'voteReceived': ChannelPreferences(push: false),
          'problemForked': ChannelPreferences(inApp: true, email: true),
        },
      );

      final decoded = NotificationPreferences.fromJson(original.toJson());
      expect(decoded, equals(original));
    });

    test('resolveNotificationOptIn applies defaults when no entry exists', () {
      const empty = NotificationPreferences();
      expect(
        resolveNotificationOptIn(
          prefs: empty,
          type: 'voteReceived',
          channel: NotificationChannel.inApp,
        ),
        isTrue,
      );
      expect(
        resolveNotificationOptIn(
          prefs: empty,
          type: 'voteReceived',
          channel: NotificationChannel.push,
        ),
        isTrue,
      );
      expect(
        resolveNotificationOptIn(
          prefs: empty,
          type: 'voteReceived',
          channel: NotificationChannel.email,
        ),
        isFalse,
      );
    });

    test('resolveNotificationOptIn honors stored opt-outs', () {
      const prefs = NotificationPreferences(
        perType: {
          'voteReceived': ChannelPreferences(push: false, email: true),
        },
      );
      expect(
        resolveNotificationOptIn(
          prefs: prefs,
          type: 'voteReceived',
          channel: NotificationChannel.push,
        ),
        isFalse,
      );
      expect(
        resolveNotificationOptIn(
          prefs: prefs,
          type: 'voteReceived',
          channel: NotificationChannel.email,
        ),
        isTrue,
      );
      // Channel not specified in stored prefs falls back to the default.
      expect(
        resolveNotificationOptIn(
          prefs: prefs,
          type: 'voteReceived',
          channel: NotificationChannel.inApp,
        ),
        isTrue,
      );
    });
  });
}
