import {getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";

import {
  resurfaceUnread,
  retractIfUnread,
  writeNotification,
} from "../lib/notify";

/**
 * `voteReceived` producer.
 *
 * The voter doc `problems/{pid}/voters/{actorUid}` carries a vote *count*.
 * This handler reacts to its full lifecycle:
 *
 *   - create (0 → N)            → write the notification
 *   - update where count grew   → resurface as unread
 *   - update where count == 0   → retract if still unread
 *   - update where count fell   → no-op
 *   - delete                    → retract if still unread
 *
 * The recipient is the problem owner; we skip when the actor IS the owner
 * (which is the case at problem-creation time, since the creator's voter
 * doc is written in the same batch).
 */
export const onVoterWritten = onDocumentWritten(
  "problems/{pid}/voters/{actorUid}",
  async (event) => {
    const pid = event.params.pid as string;
    const actorUid = event.params.actorUid as string;

    const before = event.data?.before;
    const after = event.data?.after;
    const beforeExists = before?.exists ?? false;
    const afterExists = after?.exists ?? false;

    if (!beforeExists && !afterExists) return;

    const ownerId = await _problemOwner(pid);
    if (ownerId == null || ownerId === actorUid) return;

    const payload = {
      type: "voteReceived" as const,
      problemId: pid,
      actorUid,
    };

    const beforeVotes = (before?.get("votes") as number | undefined) ?? 0;
    const afterVotes = (after?.get("votes") as number | undefined) ?? 0;

    // Deletion (or update-to-zero) — retract if unread.
    if (!afterExists || afterVotes <= 0) {
      await retractIfUnread(ownerId, payload);
      return;
    }

    // Initial create — write the notification.
    if (!beforeExists) {
      await writeNotification(ownerId, payload);
      return;
    }

    // Count went up — resurface as unread. (Doc may not exist if the
    // recipient had inApp disabled at first vote; resurfaceUnread is a no-op
    // in that case.)
    if (afterVotes > beforeVotes) {
      await resurfaceUnread(ownerId, payload);
      return;
    }

    // Count decreased but still positive — do nothing.
  },
);

async function _problemOwner(pid: string): Promise<string | null> {
  const snapshot = await getFirestore().doc(`problems/${pid}`).get();
  const ownerId = snapshot.get("ownerId");
  if (typeof ownerId !== "string") {
    logger.warn(`voteReceived: problems/${pid} has no string ownerId`);
    return null;
  }
  return ownerId;
}
