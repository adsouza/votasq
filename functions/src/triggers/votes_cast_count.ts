import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

/**
 * `votesCastCount` materializer.
 *
 * Watches every write to `problems/{pid}/voters/{actorUid}` and propagates
 * the delta into `users/{actorUid}.votesCastCount`. Deliberately monotonic:
 * a voter doc deletion or a `votes` decrement does NOT decrement the user's
 * counter — tip graduation reflects *demonstrated knowledge*, which doesn't
 * un-happen.
 *
 * Runs with admin credentials, bypassing Firestore rules — no rule branch
 * needs to permit writing votesCastCount to an arbitrary value.
 *
 * Sibling to onVoterWritten (which handles the voteReceived notification
 * producer); kept in a separate file because the two have unrelated
 * downstream effects and we want failures in one not to mask the other.
 */
export const onVoterWrittenForVotesCastCount = onDocumentWritten(
  "problems/{pid}/voters/{actorUid}",
  async (event) => {
    const actorUid = event.params.actorUid as string;
    const before = event.data?.before;
    const after = event.data?.after;

    const beforeVotes = (before?.get("votes") as number | undefined) ?? 0;
    const afterVotes = (after?.get("votes") as number | undefined) ?? 0;

    const delta = afterVotes - beforeVotes;
    if (delta <= 0) return;

    await getFirestore()
      .doc(`users/${actorUid}`)
      .update({votesCastCount: FieldValue.increment(delta)});
  },
);
