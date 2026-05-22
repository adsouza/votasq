import {FieldValue, getFirestore} from "firebase-admin/firestore";

import {readPreferences, resolveOptIn} from "./preferences";
import type {NotificationPayload} from "./types";

/**
 * Deterministic notification id for [payload]. Identical payloads always map
 * to the same id so retries and duplicate triggers collapse into one
 * notification.
 */
export function deterministicId(payload: NotificationPayload): string {
  switch (payload.type) {
    case "voteReceived":
      return `voteReceived__${payload.problemId}__${payload.actorUid}`;
    case "problemForked":
      return `problemForked__${payload.forkProblemId}`;
    case "problemLinked":
      return `problemLinked__${payload.linkedProblemId}__${payload.linkerProblemId}`;
    case "problemRevised":
      return `problemRevised__${payload.problemId}__v${payload.newVersion}`;
    case "forkAdopted":
      return `forkAdopted__${payload.forkProblemId}__${payload.originalProblemId}__v${payload.newVersion}`;
  }
}

/**
 * Write a notification doc for [recipientUid] if (a) the recipient has in-app
 * notifications enabled for the payload's type, and (b) the deterministic
 * doc doesn't already exist. The second-write idempotency is enforced via
 * `.create()`, which throws ALREADY_EXISTS when the doc is already there —
 * we swallow that specific error.
 *
 * Returns `true` if a new doc was written, `false` if the write was skipped
 * (due to preferences or because the doc already existed).
 */
export async function writeNotification(
  recipientUid: string,
  payload: NotificationPayload,
): Promise<boolean> {
  const prefs = await readPreferences(recipientUid);
  if (!resolveOptIn(prefs, payload.type, "inApp")) return false;

  const id = deterministicId(payload);
  const ref = getFirestore().doc(
    `users/${recipientUid}/notifications/${id}`,
  );
  try {
    await ref.create({
      id,
      recipientUid,
      payload,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
    return true;
  } catch (e) {
    if (isAlreadyExists(e)) return false;
    throw e;
  }
}

/**
 * Bumps `updatedAt` and clears `readAt` on the existing notification so it
 * resurfaces as unread (e.g. when an actor votes additional times). No-op if
 * the doc doesn't exist.
 */
export async function resurfaceUnread(
  recipientUid: string,
  payload: NotificationPayload,
): Promise<void> {
  const id = deterministicId(payload);
  const ref = getFirestore().doc(
    `users/${recipientUid}/notifications/${id}`,
  );
  try {
    await ref.update({
      readAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (isNotFound(e)) return;
    throw e;
  }
}

/**
 * Deletes the existing notification ONLY IF it is still unread. If the
 * recipient already read it, the doc is left in place (rewriting history is
 * jarring; the recipient saw the event).
 */
export async function retractIfUnread(
  recipientUid: string,
  payload: NotificationPayload,
): Promise<void> {
  const id = deterministicId(payload);
  const ref = getFirestore().doc(
    `users/${recipientUid}/notifications/${id}`,
  );
  const snapshot = await ref.get();
  if (!snapshot.exists) return;
  const readAt = snapshot.get("readAt");
  if (readAt != null) return;
  await ref.delete();
}

function isAlreadyExists(e: unknown): boolean {
  return _hasCode(e, 6) || _hasStringCode(e, "already-exists");
}

function isNotFound(e: unknown): boolean {
  return _hasCode(e, 5) || _hasStringCode(e, "not-found");
}

function _hasCode(e: unknown, code: number): boolean {
  return typeof e === "object" && e !== null && (e as {code?: unknown}).code === code;
}

function _hasStringCode(e: unknown, code: string): boolean {
  return typeof e === "object" && e !== null && (e as {code?: unknown}).code === code;
}
