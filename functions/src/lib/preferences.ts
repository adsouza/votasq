import {getFirestore} from "firebase-admin/firestore";

import type {
  NotificationChannel,
  NotificationPreferences,
} from "./types";

// Mirrors the Dart helper `resolveNotificationOptIn` in
// `packages/shared/lib/src/models/notification_preferences.dart`. Defaults:
// in-app and push are on for every type; email is off (no email worker yet).
const _defaults: Record<NotificationChannel, boolean> = {
  inApp: true,
  push: true,
  email: false,
};

/**
 * Whether a given (type, channel) combination should be delivered for the
 * recipient, taking stored prefs and defaults into account.
 */
export function resolveOptIn(
  prefs: NotificationPreferences | undefined,
  type: string,
  channel: NotificationChannel,
): boolean {
  const stored = prefs?.perType?.[type]?.[channel];
  if (stored !== undefined) return stored;
  return _defaults[channel];
}

/**
 * Fetches `users/{uid}.notificationPreferences`. Returns an empty object when
 * the user doc or the field is missing — callers should then rely on the
 * defaults in [resolveOptIn].
 */
export async function readPreferences(
  uid: string,
): Promise<NotificationPreferences> {
  const snapshot = await getFirestore().doc(`users/${uid}`).get();
  const data = snapshot.data();
  if (!data) return {};
  return (data.notificationPreferences as NotificationPreferences) ?? {};
}
