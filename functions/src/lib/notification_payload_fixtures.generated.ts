// GENERATED — DO NOT EDIT BY HAND.
//
// Source: packages/shared/test/src/models/notification_ts_fixture_test.dart
//
// Regenerate after intentional Dart schema changes via:
//   SYNC_TS_FIXTURES=1 dart test packages/shared/test/src/models/notification_ts_fixture_test.dart
//
// Drift invariant: `tsc --noEmit` type-checks the
// `satisfies NotificationPayload` clause below. If Dart adds,
// removes, or renames a field, the literal stops satisfying the
// union and tsc fails. CI surfaces drift before it ships.

import type {NotificationPayload} from './types';

export const notificationPayloadFixtures = {
  voteReceived: {
    problemId: 'p1',
    actorUid: 'u1',
    type: 'voteReceived',
  },
  problemForked: {
    originalProblemId: 'orig',
    forkProblemId: 'fork',
    actorUid: 'u1',
    type: 'problemForked',
  },
  problemLinkedUntyped: {
    linkedProblemId: 'linked',
    linkerProblemId: 'linker',
    actorUid: 'u1',
    kind: null,
    type: 'problemLinked',
  },
  problemLinkedSpecialization: {
    linkedProblemId: 'linked',
    linkerProblemId: 'linker',
    actorUid: 'u1',
    kind: 'specialization',
    type: 'problemLinked',
  },
  problemLinkedGeneralization: {
    linkedProblemId: 'linked',
    linkerProblemId: 'linker',
    actorUid: 'u1',
    kind: 'generalization',
    type: 'problemLinked',
  },
  problemRevised: {
    problemId: 'p1',
    newVersion: 3,
    type: 'problemRevised',
  },
  forkAdopted: {
    forkProblemId: 'fork',
    originalProblemId: 'orig',
    newVersion: 2,
    type: 'forkAdopted',
  },
} as const satisfies Record<string, NotificationPayload>;
