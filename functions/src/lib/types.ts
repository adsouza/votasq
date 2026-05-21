// TypeScript mirrors of the Dart Freezed models in
// `packages/shared/lib/src/models/notification*.dart`. Kept in sync by
// convention — when you change a shape on either side, update the other.

import type {Timestamp} from "firebase-admin/firestore";

/**
 * The five notification payload shapes. The `type` discriminator selects the
 * variant on the wire; field names match the Dart sealed-class constructors.
 */
export type NotificationPayload =
  | VoteReceivedPayload
  | ProblemForkedPayload
  | ProblemLinkedPayload
  | ProblemRevisedPayload
  | ForkAdoptedPayload;

export interface VoteReceivedPayload {
  type: "voteReceived";
  problemId: string;
  actorUid: string;
}

export interface ProblemForkedPayload {
  type: "problemForked";
  originalProblemId: string;
  forkProblemId: string;
  actorUid: string;
}

export interface ProblemLinkedPayload {
  type: "problemLinked";
  linkedProblemId: string;
  linkerProblemId: string;
  actorUid: string;
}

export interface ProblemRevisedPayload {
  type: "problemRevised";
  problemId: string;
  newVersion: number;
}

export interface ForkAdoptedPayload {
  type: "forkAdopted";
  forkProblemId: string;
  originalProblemId: string;
  newVersion: number;
}

/** Stored shape of `users/{uid}/notifications/{nid}`. */
export interface NotificationDoc {
  id: string;
  recipientUid: string;
  payload: NotificationPayload;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  readAt: Timestamp | null;
}

/** Per-channel opt-ins for a single notification type. */
export interface ChannelPreferences {
  inApp?: boolean;
  push?: boolean;
  email?: boolean;
}

/** User-level notification preferences stored on the user doc. */
export interface NotificationPreferences {
  perType?: Record<string, ChannelPreferences>;
}

/** Delivery channels for notifications. */
export type NotificationChannel = "inApp" | "push" | "email";
