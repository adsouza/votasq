import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions/v2";

/**
 * Maximum number of writes per Firestore batch. The hard SDK limit is 500;
 * we use that exactly.
 */
export const MAX_BATCH_WRITES = 500;

/**
 * Chunks [refs] into groups of [chunkSize] (default [MAX_BATCH_WRITES]).
 * Exported so the chunking math can be tested without spinning up Firestore.
 */
export function chunkRefs<T>(refs: T[], chunkSize = MAX_BATCH_WRITES): T[][] {
  if (chunkSize <= 0) throw new Error("chunkSize must be > 0");
  const chunks: T[][] = [];
  for (let i = 0; i < refs.length; i += chunkSize) {
    chunks.push(refs.slice(i, i + chunkSize));
  }
  return chunks;
}

/**
 * Marks every unread notification under `users/{caller}/notifications` as
 * read in one logical request. Writes are batched to respect Firestore's
 * 500-write-per-batch limit. Returns the number of notifications that
 * were flipped (so the client can refresh the badge count with confidence).
 *
 * Auth is required — anonymous calls are rejected.
 */
export const markAllNotificationsRead = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "markAllNotificationsRead requires an authenticated caller.",
    );
  }

  const db = getFirestore();
  const snapshot = await db
    .collection(`users/${uid}/notifications`)
    .where("readAt", "==", null)
    .select() // we only need the doc refs, not the field values
    .get();

  if (snapshot.empty) return {marked: 0};

  const chunks = chunkRefs(snapshot.docs.map((d) => d.ref));
  const now = FieldValue.serverTimestamp();
  for (const chunk of chunks) {
    const batch = db.batch();
    for (const ref of chunk) {
      batch.update(ref, {readAt: now});
    }
    await batch.commit();
  }

  logger.info(
    `markAllNotificationsRead: flipped ${snapshot.size} notification(s) ` +
      `for ${uid}`,
  );
  return {marked: snapshot.size};
});
