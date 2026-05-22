import {getFirestore} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";

import {writeNotification} from "../lib/notify";

/**
 * `problemForked` producer.
 *
 * Fires when any new problem is created. If the new problem has an
 * `inspoProblemId` set, the original problem's owner is notified that their
 * problem was forked.
 *
 * Skips when the fork's owner is the original problem's owner (an owner
 * forking their own problem).
 */
export const onProblemForked = onDocumentCreated(
  "problems/{forkId}",
  async (event) => {
    const data = event.data?.data();
    if (data == null) return;

    const inspoProblemId = data.inspoProblemId;
    if (typeof inspoProblemId !== "string" || inspoProblemId.length === 0) {
      return;
    }

    const forkId = event.params.forkId as string;
    const actorUid = data.ownerId;
    if (typeof actorUid !== "string") {
      logger.warn(`problemForked: fork ${forkId} has no string ownerId`);
      return;
    }

    const originalSnapshot = await getFirestore()
      .doc(`problems/${inspoProblemId}`)
      .get();
    const originalOwnerId = originalSnapshot.get("ownerId");
    if (typeof originalOwnerId !== "string") {
      logger.warn(
        `problemForked: original problems/${inspoProblemId} has no ownerId`,
      );
      return;
    }
    if (originalOwnerId === actorUid) return;

    await writeNotification(originalOwnerId, {
      type: "problemForked",
      originalProblemId: inspoProblemId,
      forkProblemId: forkId,
      actorUid,
    });
  },
);
