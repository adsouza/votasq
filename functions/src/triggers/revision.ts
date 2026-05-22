import {getFirestore} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";

import {writeNotification} from "../lib/notify";

/**
 * Fan-out producer for `problemRevised` and `forkAdopted`.
 *
 * Fires on creation of a new revision under `problems/{pid}/versions/{v}`.
 *
 *   - `problemRevised`: one notification per voter under
 *     `problems/{pid}/voters`, EXCLUDING the owner (who authored the
 *     revision).
 *
 *   - `forkAdopted`: if the new revision was created by copying field
 *     values from a fork (revision doc has `copiedFromProblemId`), notify
 *     that fork's owner. The fork owner is also typically not in the
 *     voter set, so this emits a notification they wouldn't have
 *     received via the `problemRevised` fan-out alone.
 */
export const onRevisionCreated = onDocumentCreated(
  "problems/{pid}/versions/{versionId}",
  async (event) => {
    const data = event.data?.data();
    if (data == null) return;

    const pid = event.params.pid as string;
    const newVersion = _readInt(data.version);
    if (newVersion == null) {
      logger.warn(`revision: ${pid}/versions/${event.params.versionId} has no int version`);
      return;
    }

    const db = getFirestore();
    const problemSnapshot = await db.doc(`problems/${pid}`).get();
    const ownerId = problemSnapshot.get("ownerId");
    if (typeof ownerId !== "string") {
      logger.warn(`revision: problems/${pid} has no string ownerId`);
      return;
    }

    // problemRevised fan-out to voters (excluding the owner).
    const votersSnapshot = await db
      .collection(`problems/${pid}/voters`)
      .get();
    await Promise.all(
      votersSnapshot.docs.map(async (voterDoc) => {
        const voterUid = (voterDoc.get("uid") as string | undefined) ??
          voterDoc.id;
        if (voterUid === ownerId) return;
        await writeNotification(voterUid, {
          type: "problemRevised",
          problemId: pid,
          newVersion,
        });
      }),
    );

    // forkAdopted — when the revision was sourced from a fork.
    const forkId = data.copiedFromProblemId;
    if (typeof forkId === "string" && forkId.length > 0) {
      const forkSnapshot = await db.doc(`problems/${forkId}`).get();
      const forkOwnerId = forkSnapshot.get("ownerId");
      if (typeof forkOwnerId === "string" && forkOwnerId !== ownerId) {
        await writeNotification(forkOwnerId, {
          type: "forkAdopted",
          forkProblemId: forkId,
          originalProblemId: pid,
          newVersion,
        });
      }
    }
  },
);

function _readInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  return null;
}
