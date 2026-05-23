import {getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";

import {writeNotification} from "../lib/notify";

/**
 * `problemLinked` producer.
 *
 * Diff the `linkedProblemIds` array between before/after of the linker
 * problem. For each *newly added* id, notify the linked problem's owner.
 *
 * Removals are not retracted (intentional asymmetry — only votes self-
 * retract).
 *
 * Skipped:
 *   - self-links (linker id == linked id)
 *   - the actor IS the linked problem's owner
 */
export const onProblemLinkedWritten = onDocumentWritten(
  "problems/{linkerId}",
  async (event) => {
    const linkerId = event.params.linkerId as string;
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) return;

    const beforeIds = _readIdList(before?.get("linkedProblemIds"));
    const afterIds = _readIdList(after.get("linkedProblemIds"));
    const beforeSet = new Set(beforeIds);
    const newIds = afterIds.filter((id) => !beforeSet.has(id));
    if (newIds.length === 0) return;

    const actorUid = after.get("ownerId");
    if (typeof actorUid !== "string") {
      logger.warn(`problemLinked: linker ${linkerId} has no ownerId`);
      return;
    }

    const db = getFirestore();
    for (const linkedProblemId of newIds) {
      if (linkedProblemId === linkerId) continue;

      const linkedSnapshot = await db
        .doc(`problems/${linkedProblemId}`)
        .get();
      const linkedOwnerId = linkedSnapshot.get("ownerId");
      if (typeof linkedOwnerId !== "string") continue;
      if (linkedOwnerId === actorUid) continue;

      await writeNotification(linkedOwnerId, {
        type: "problemLinked",
        linkedProblemId,
        linkerProblemId: linkerId,
        actorUid,
        // This trigger fires on changes to `linkedProblemIds`, which is the
        // generic-clique link surface — typed links (specialization /
        // generalization) write elsewhere and produce their own payloads
        // with `kind` set. null marks the resulting notification as
        // untyped so the recipient's UI / push body uses the un-kinded ARB.
        kind: null,
      });
    }
  },
);

function _readIdList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === "string");
}
