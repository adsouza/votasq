# macOS client setup notes

## Firebase App Check debug token

The first time you run the macOS app in debug mode (any flavor — `dev`,
`staging`, or `prod`), the Firebase App Check Apple debug provider
generates a UUID token and prints it to the Flutter run console:

```
Firebase App Check Debug Token: D51DDE81-F12C-4051-9D01-3730E3F54B51
```

This token must be registered in Firebase Console before the macOS app
can complete App Check exchanges. Without registration:

- **Against the local emulator:** Firestore SDK gives up on its
  `WatchStream` after the exchange returns HTTP 403, the listing stays
  empty, and the console shows `[cloud_firestore/unavailable] The
  service is currently unavailable`.
- **Against production:** Requests eventually go through (App Check
  enforcement on the Firestore prod backend is currently off, so the
  server accepts requests with a failed exchange), but the console
  floods with `AppCheck failed: ... HTTP 403 ... exchangeDebugToken`
  for every request. Functional but noisy and slow.

### One-time registration (per machine)

1. Run the macOS app once and copy the debug token UUID from the
   terminal output.
2. Open the Firebase Console for the **votasq** project.
3. Left nav → **App Check**.
4. In the Apps list, locate the **macOS app row**. macOS is classified
   as iOS in Firebase, so there are two `iOS` rows — the macOS one is
   the row whose App ID ends in **`3b37d6293e192f2b124b9f`** (see
   `apps/client/lib/firebase_options.dart`'s `macos` block to confirm).
   The iPhone iOS row ends in `facee32ee03ee929124b9f`.
5. Click the three-dot menu on that row → **Manage debug tokens** →
   **Add debug token**.
6. Paste the UUID, give it a name (e.g. `tony's mac dev build`), save.

The token persists in macOS Keychain across rebuilds, so this is a
one-time setup per machine. Re-register if you reset Keychain, set up
a new machine, or the token UUID changes for any reason (you'll see
the new UUID in the run console on next launch — the existing
registration will become inert and the new one needs to be added).

The same registered token is used by the SDK for prod-mac calls and
emulator-mac calls — the Apple App Check provider doesn't care which
Firestore endpoint you point at.

## Sandbox entitlements

Outgoing network connections — including to `127.0.0.1` for the local
emulator — require `com.apple.security.network.client` in the
.entitlements file. Both `Runner/DebugProfile.entitlements` and
`Runner/Release.entitlements` already have this set; don't drop it.

## Connecting to the local emulator

See the `.claude/CLAUDE.md` "Running the mac (or iOS) app against the
local emulator" gotcha for why `apps/client/lib/bootstrap.dart`
hardcodes `127.0.0.1` (not `localhost`) as the emulator host for
native platforms.
