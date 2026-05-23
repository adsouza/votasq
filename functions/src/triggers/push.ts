import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";

import {format, loadStrings} from "../lib/l10n";
import {resolveOptIn} from "../lib/preferences";
import type {
  NotificationDoc,
  NotificationPayload,
} from "../lib/types";

const DEFAULT_LOCALE = "en";
const ACTOR_PLACEHOLDER = "Someone";

/**
 * Pushes a notification to the recipient's registered FCM tokens when a
 * new doc lands under `users/{uid}/notifications/{nid}`.
 *
 * Skips when push is disabled for the type in the recipient's prefs.
 * Renders title + body server-side from the synced ARB files using the
 * recipient's `locale` field (default 'en'). Sends via FCM multicast and
 * deletes per-token registrations that come back as
 * `registration-token-not-registered`.
 */
export const onNotificationCreated = onDocumentCreated(
  "users/{recipientUid}/notifications/{notificationId}",
  async (event) => {
    const recipientUid = event.params.recipientUid as string;
    const notificationId = event.params.notificationId as string;
    const data = event.data?.data() as NotificationDoc | undefined;
    if (!data?.payload?.type) {
      logger.warn(
        `push: notification ${notificationId} for ${recipientUid} has no ` +
          "payload type — skipping",
      );
      return;
    }
    const payload = data.payload;

    const db = getFirestore();
    const recipientSnapshot = await db.doc(`users/${recipientUid}`).get();
    const recipient = recipientSnapshot.data();
    const prefs = (recipient?.notificationPreferences as
      | Parameters<typeof resolveOptIn>[0]
      | undefined) ?? undefined;
    if (!resolveOptIn(prefs, payload.type, "push")) return;

    const locale = (recipient?.locale as string | undefined) ?? DEFAULT_LOCALE;

    const tokenSnapshot = await db
      .collection(`users/${recipientUid}/fcmTokens`)
      .get();
    if (tokenSnapshot.empty) return;
    const tokens = tokenSnapshot.docs
      .map((d) => d.get("token") as string | undefined)
      .filter((t): t is string => typeof t === "string" && t.length > 0);
    if (tokens.length === 0) return;

    const {title, body} = await _renderText(payload, locale);

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {title, body},
      data: _flattenDataPayload(payload),
    });

    // Clean up tokens the FCM service no longer recognizes.
    const stale: Array<Promise<unknown>> = [];
    response.responses.forEach((resp, i) => {
      if (resp.success) return;
      const code = resp.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        stale.push(tokenSnapshot.docs[i].ref.delete());
      } else if (resp.error) {
        logger.warn(
          `push: FCM send failed for token (${tokenSnapshot.docs[i].id}): ` +
            `${code}`,
        );
      }
    });
    if (stale.length > 0) await Promise.all(stale);

    logger.info(
      `push: ${payload.type} for ${recipientUid}: ` +
        `${response.successCount}/${tokens.length} delivered, ` +
        `${stale.length} stale token(s) cleaned`,
    );
  },
);

async function _renderText(
  payload: NotificationPayload,
  locale: string,
): Promise<{title: string; body: string}> {
  const strings = loadStrings(locale);
  const actorName = await _resolveActorName(payload);

  switch (payload.type) {
    case "voteReceived":
      return {
        title: strings.notificationVoteReceivedTitle,
        body: format(strings.notificationVoteReceivedBody, {actorName}),
      };
    case "problemForked":
      return {
        title: strings.notificationProblemForkedTitle,
        body: format(strings.notificationProblemForkedBody, {actorName}),
      };
    case "problemLinked":
      return {
        title: strings.notificationProblemLinkedTitle,
        body: format(strings.notificationProblemLinkedBody, {actorName}),
      };
    case "problemRevised":
      return {
        title: strings.notificationProblemRevisedTitle,
        body: strings.notificationProblemRevisedBody,
      };
    case "forkAdopted":
      return {
        title: strings.notificationForkAdoptedTitle,
        body: strings.notificationForkAdoptedBody,
      };
  }
}

/**
 * Resolves the actor's displayName from `users/{actorUid}` for payloads
 * that carry an actor. Falls back to [ACTOR_PLACEHOLDER] when the field
 * is missing, the doc doesn't exist, or the read fails — the body
 * template gets a readable string either way.
 *
 * problemRevised and forkAdopted have no actor in their body templates,
 * so we short-circuit to the placeholder without a read.
 */
async function _resolveActorName(
  payload: NotificationPayload,
): Promise<string> {
  let actorUid: string | undefined;
  switch (payload.type) {
    case "voteReceived":
    case "problemForked":
    case "problemLinked":
      actorUid = payload.actorUid;
      break;
    case "problemRevised":
    case "forkAdopted":
      return ACTOR_PLACEHOLDER;
  }
  if (!actorUid) return ACTOR_PLACEHOLDER;
  try {
    const snapshot = await getFirestore().doc(`users/${actorUid}`).get();
    const name = snapshot.get("displayName");
    if (typeof name === "string" && name.length > 0) return name;
    return ACTOR_PLACEHOLDER;
  } catch (e) {
    logger.warn(
      `push: getDisplayName failed for actor ${actorUid}: ${String(e)}`,
    );
    return ACTOR_PLACEHOLDER;
  }
}

/**
 * FCM's `data` payload must be `Record<string, string>`. Flatten the
 * payload into string-keyed string values so tapping the push can route
 * deep-link the recipient to the right problem.
 */
function _flattenDataPayload(
  payload: NotificationPayload,
): Record<string, string> {
  const out: Record<string, string> = {type: payload.type};
  for (const [key, value] of Object.entries(payload)) {
    if (key === "type") continue;
    out[key] = String(value);
  }
  return out;
}
