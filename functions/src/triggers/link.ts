import {getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";

import {writeNotification} from "../lib/notify";
import type {ProblemLinkKind} from "../lib/types";

interface TypedLinkEntry {
  targetId: string;
  kind: ProblemLinkKind;
}

/**
 * `problemLinked` producer.
 *
 * Diffs both `linkedProblemIds` (generic clique links) and `typedLinks`
 * (directional specialization / generalization tags) between before/after
 * of the linker problem. For each *newly added* entry, notifies the linked
 * problem's owner. Generic-link notifications carry `kind: null`; typed
 * notifications carry the kind from the source-side entry, which matches
 * the recipient-perspective ARB string ("their problem is a [kind] of
 * yours") because the trigger fires on the side whose owner == actor.
 *
 * Removals are not retracted (intentional asymmetry — only votes
 * self-retract).
 *
 * Actor attribution
 * -----------------
 * Linking is a *paired write* — `linkProblems` and `tagProblemLink` in
 * `apps/client/lib/services/firestore_repository.dart` update both
 * problem docs in a single batch. This trigger fires once per modified
 * doc. Historically we used `after.get("ownerId")` as the actor, but
 * `ownerId` is only correct on the side whose owner is the actor; on the
 * mirrored side it points to the counterparty, which produces a
 * notification falsely attributing the action to them.
 *
 * The client now stamps `lastLinkActor: <auth.uid>` on every modified
 * doc in the batch (enforced in `firestore.rules`). We prefer that field;
 * fall back to `ownerId` only for pre-existing docs that haven't been
 * touched since this change shipped, so the fix is non-breaking on
 * historical data.
 *
 * The same per-recipient filter (`linkedOwnerId === actorUid`) that
 * skips self-notifications now also de-duplicates the mirrored second
 * firing: because both firings see the same `lastLinkActor`, the firing
 * whose `linkedOwnerId` happens to *be* the actor is silently skipped.
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

    const beforeGenericIds = _readIdList(before?.get("linkedProblemIds"));
    const afterGenericIds = _readIdList(after.get("linkedProblemIds"));
    const beforeGenericSet = new Set(beforeGenericIds);
    const newGenericIds = afterGenericIds.filter(
      (id) => !beforeGenericSet.has(id),
    );

    const beforeTyped = _readTypedLinks(before?.get("typedLinks"));
    const afterTyped = _readTypedLinks(after.get("typedLinks"));
    const beforeTypedKeys = new Set(
      beforeTyped.map((l) => `${l.targetId}__${l.kind}`),
    );
    const newTypedEntries = afterTyped.filter(
      (l) => !beforeTypedKeys.has(`${l.targetId}__${l.kind}`),
    );

    if (newGenericIds.length === 0 && newTypedEntries.length === 0) return;

    const actorUid =
      _readString(after.get("lastLinkActor")) ??
      _readString(after.get("ownerId"));
    if (actorUid == null) {
      logger.warn(
        `problemLinked: linker ${linkerId} has neither lastLinkActor nor ` +
          "ownerId — skipping",
      );
      return;
    }

    const db = getFirestore();

    for (const linkedProblemId of newGenericIds) {
      if (linkedProblemId === linkerId) continue;
      const linkedOwnerId = await _readOwner(db, linkedProblemId);
      if (linkedOwnerId == null) continue;
      if (linkedOwnerId === actorUid) continue;

      await writeNotification(linkedOwnerId, {
        type: "problemLinked",
        linkedProblemId,
        linkerProblemId: linkerId,
        actorUid,
        kind: null,
      });
    }

    for (const entry of newTypedEntries) {
      if (entry.targetId === linkerId) continue;
      const linkedOwnerId = await _readOwner(db, entry.targetId);
      if (linkedOwnerId == null) continue;
      // Mirrored-side firing: `lastLinkActor` is identical on both writes
      // in the paired batch, so when this firing is on the target side
      // (where ownerOf(targetId) is the actor), the recipient equals the
      // actor and we skip — preventing duplicate notifications.
      if (linkedOwnerId === actorUid) continue;

      await writeNotification(linkedOwnerId, {
        type: "problemLinked",
        linkedProblemId: entry.targetId,
        linkerProblemId: linkerId,
        actorUid,
        kind: entry.kind,
      });
    }
  },
);

function _readIdList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === "string");
}

function _readTypedLinks(value: unknown): TypedLinkEntry[] {
  if (!Array.isArray(value)) return [];
  const out: TypedLinkEntry[] = [];
  for (const v of value) {
    if (v == null || typeof v !== "object") continue;
    const rec = v as Record<string, unknown>;
    const targetId = rec.targetId;
    const kind = rec.kind;
    if (typeof targetId !== "string") continue;
    if (kind !== "specialization" && kind !== "generalization") continue;
    out.push({targetId, kind});
  }
  return out;
}

function _readString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

async function _readOwner(
  db: ReturnType<typeof getFirestore>,
  problemId: string,
): Promise<string | null> {
  const snapshot = await db.doc(`problems/${problemId}`).get();
  return _readString(snapshot.get("ownerId"));
}
