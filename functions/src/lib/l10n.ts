import {readFileSync} from "node:fs";
import {join} from "node:path";

/**
 * Server-side localization for FCM push notifications.
 *
 * Loads ARB JSON files synced from `apps/client/lib/l10n/arb/` into
 * `functions/l10n/` by `tool/sync-arbs.mjs` (hooked to npm run build's
 * prebuild). Same source of truth as the client; same translations.
 *
 * The substituter handles `{placeholder}` interpolation only. The
 * client ARBs include one ICU plural string (`menuVotesRemaining`),
 * but the notification-text strings we use here don't need plural or
 * select — keep this simple until they do.
 */

const FALLBACK_LOCALE = "en";
const L10N_DIR = join(__dirname, "..", "..", "l10n");

const _cache = new Map<string, Record<string, string>>();

/**
 * Returns the string table for [locale]. Falls back to English when the
 * locale's ARB is missing or unreadable. Throws if even the fallback
 * fails to load (indicates a deployment misconfiguration).
 */
export function loadStrings(locale: string): Record<string, string> {
  const cached = _cache.get(locale);
  if (cached) return cached;

  let raw: string;
  try {
    raw = readFileSync(join(L10N_DIR, `app_${locale}.arb`), "utf-8");
  } catch (e) {
    if (locale === FALLBACK_LOCALE) {
      throw new Error(
        `l10n: fallback locale '${FALLBACK_LOCALE}' is missing — ` +
          `did 'npm run sync:arbs' run? Original error: ${e}`,
      );
    }
    return loadStrings(FALLBACK_LOCALE);
  }

  const json = JSON.parse(raw) as Record<string, unknown>;
  const strings: Record<string, string> = {};
  for (const [key, value] of Object.entries(json)) {
    // Skip @-prefixed metadata entries; only collect string values.
    if (!key.startsWith("@") && typeof value === "string") {
      strings[key] = value;
    }
  }
  _cache.set(locale, strings);
  return strings;
}

/**
 * Substitute `{name}`-style placeholders in [template] with values from
 * [params]. Unknown placeholders are left in place so a missing param
 * doesn't silently produce text like "voted on your problem"; an
 * obviously-broken `{actorName} voted on your problem` is louder.
 */
export function format(
  template: string,
  params: Record<string, string> = {},
): string {
  return template.replace(/\{(\w+)\}/g, (match, key) =>
    key in params ? params[key] : match,
  );
}

/** Test-only: clear the in-memory string cache. */
export function _clearCacheForTesting(): void {
  _cache.clear();
}
