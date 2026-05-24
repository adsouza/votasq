// One-shot backfill: populate `users/{uid}.votesCastCount` from each
// user's `problems/.../voters/{uid}` history. Run BEFORE deploying the
// new Cloud Function that maintains votesCastCount going forward.
//
// Usage (against production Firestore via Application Default Credentials):
//
//   gcloud auth application-default login
//   cd functions && npm run backfill
//
// Idempotent — safe to re-run.

import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

export type UserRow = {uid: string};
export type VoterRow = {uid: string; votes: number};

/**
 * Pure count-aggregation: takes the full user and voter lists, returns
 * a map of `uid -> total lifetime votes cast`. Side-effect-free so we
 * can unit-test it without a Firestore mock.
 */
export function computeVotesCastCounts(
  users: ReadonlyArray<UserRow>,
  voters: ReadonlyArray<VoterRow>,
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const u of users) {
    counts[u.uid] = 0;
  }
  for (const v of voters) {
    if (counts[v.uid] === undefined) continue;
    counts[v.uid] += v.votes;
  }
  return counts;
}

/** Production entry point: reads from Firestore, computes, writes back. */
export async function main(): Promise<void> {
  if (getApps().length === 0) initializeApp();
  const firestore = getFirestore();

  console.log("Reading users/ ...");
  const usersSnap = await firestore.collection("users").get();
  const users: UserRow[] = usersSnap.docs.map((d) => ({uid: d.id}));

  console.log(`Reading voters/ (collection group) ... ${users.length} users`);
  const votersSnap = await firestore.collectionGroup("voters").get();
  const voters: VoterRow[] = votersSnap.docs.map((d) => ({
    uid: (d.get("uid") as string) ?? "",
    votes: (d.get("votes") as number | undefined) ?? 0,
  }));

  const counts = computeVotesCastCounts(users, voters);

  let touched = 0;
  for (const [uid, sum] of Object.entries(counts)) {
    await firestore.collection("users").doc(uid).update({
      votesCastCount: sum,
    });
    touched++;
  }
  console.log(`Done. ${touched} user(s) updated.`);
}

// Invoke when run as a CLI script (not when imported by tests).
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
