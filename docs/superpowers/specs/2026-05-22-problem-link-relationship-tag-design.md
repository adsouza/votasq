# Problem-link relationship tag — design

**Date:** 2026-05-22
**Status:** Approved, awaiting implementation

## Problem statement

Today every link between two `Problem` documents is generic and untyped. Users want to express richer semantics — specifically, whether a linked problem is a **specialization** (more specific) or **generalization** (more general) of the current one.

The existing link model is symmetric and clique-based: linking A↔B and B↔C automatically merges everyone into a single clique, and each document stores every other clique member's ID in a flat `List<String> linkedProblemIds`. A specialization/generalization tag is inherently asymmetric, which the current model cannot express.

## Goals

- Allow a user to optionally tag a link as **specialization** or **generalization** of the current problem.
- Preserve the existing generic clique-link behavior for untagged links.
- Surface the relationship type both in the link UI and in notifications.

## Non-goals

- Transitive reasoning over the typed graph (e.g., enumerating "grand-specializations").
- Replacing the generic-link model entirely.
- Inferring tags from existing generic links.

## High-level decisions (locked in via brainstorming)

1. **Generic links keep clique-merge; typed links are pairwise asymmetric edges.** The two link kinds coexist.
2. **Per-side storage:** each problem stores its outgoing typed edges in a new field `typedLinks: List<ProblemLink>`. The inverse is mirrored on the other side via paired writes.
3. **UI entry point:** a single split button. Primary tap → generic link (today's behavior). Chevron/dropdown → "Link as specialization" / "Link as generalization" menu items.
4. **Mutually exclusive:** any pair (A, B) appears in at most one of `linkedProblemIds` or `typedLinks`. Promoting a generic link to typed severs only that pair from the clique.
5. **Display:** the existing linked-problems section is split into three subsections in this order: **Generalizations**, **Linked** (generic), **Specializations**.

---

## Data model

### `shared` package — new file `lib/src/models/problem_link.dart`

```dart
enum ProblemLinkKind {
  @JsonValue('specialization') specialization, // target is more specific than me
  @JsonValue('generalization') generalization, // target is more general than me
}

@freezed
abstract class ProblemLink with _$ProblemLink {
  const factory ProblemLink({
    required String targetId,
    required ProblemLinkKind kind,
  }) = _ProblemLink;
  factory ProblemLink.fromJson(Map<String, dynamic> json) =>
      _$ProblemLinkFromJson(json);
}
```

### `shared` — extend `Problem`

```dart
@Default(<ProblemLink>[]) List<ProblemLink> typedLinks,
```

Outgoing-from-self perspective: an entry `{targetId: B, kind: specialization}` on A means "B is a specialization of A." The inverse `{targetId: A, kind: generalization}` lives on B.

### Firestore representation

`typedLinks` is stored as an array of maps:

```
typedLinks: [
  { targetId: "abc", kind: "specialization" },
  { targetId: "def", kind: "generalization" },
]
```

No new indices required — we always read by parent doc and never query across.

### Invariants

- For each (selfId, targetId) pair, exactly one of the following holds: the pair is in both sides' `linkedProblemIds`, or the pair is in both sides' `typedLinks` with inverse kinds, or there is no link.
- Reads are best-effort tolerant of inconsistency. Writes always perform paired updates in a single Firestore batch.
- Promoting A↔B from generic to typed may degrade the previous clique invariant for the pair (other clique members remain mutually linked among themselves; A and B drop their direct generic edge).

---

## Server (`apps/server`)

### `lib/src/db.dart`

Extend `_problemToDocument` and `_documentToProblem` to round-trip the new `typedLinks` field. Use the existing `arrayValue` + `mapValue` helpers (same pattern as `complaints` / `linkedProblemIds`, plus nested maps for each link entry).

Unknown `kind` strings from the wire are treated as a parse error — surfaces as a 500 from the route, which is acceptable: indicates schema drift to investigate, not user-recoverable.

### `routes/api/problems/[id]/index.dart` PUT route

Extend the partial-update preservation guard. Currently:

```dart
if (!body.containsKey('linkedProblemIds'))
  'linkedProblemIds': existing.linkedProblemIds,
```

Add an analogous guard for `typedLinks`. Without it, a PUT that touches only `description` would erase typed links.

### No new endpoints

Link operations write Firestore directly from the client (see [firestore_repository.dart:744](apps/client/lib/services/firestore_repository.dart:744)). The server reads/writes `Problem` documents for adjacent flows (GET, notification fanout, translation invalidation), so updating the parse/serialize layer is sufficient.

### Firestore security rules

The existing "Problem linking / clustering update" clause in [firestore.rules](firestore.rules) is gated by `affectedKeys().hasOnly(['linkedProblemIds'])`, which rejects any write that also touches `typedLinks`. Broaden the clause to `hasOnly(['linkedProblemIds', 'typedLinks'])` and add a parallel `typedLinks.size() <= 100` cap for DoS protection.

**Test coverage:** Closed by [apps/server/e2e/firestore_rules_e2e_test.dart](apps/server/e2e/firestore_rules_e2e_test.dart), which exercises `firestore.rules` directly via the Firestore emulator's REST API with a real ID token. Six scenarios cover the regression (the exact tag-link pattern that previously failed), the orthogonal clique-link path, unauthed rejection, the 100-entry size cap, and rejection of writes that piggyback unrelated fields. The test uploads the current rules file to the emulator at setup time via the `:securityRules` PUT endpoint, so it is self-contained regardless of when the emulator was started.

---

## Client (`apps/client`)

### `FirestoreRepository` — new methods

```dart
Future<void> tagProblemLink({
  required String sourceId,
  required String targetId,
  required ProblemLinkKind kind,
});

Future<void> untagProblemLink({
  required String sourceId,
  required String targetId,
});
```

`tagProblemLink` semantics:
1. Read both `Problem` docs.
2. Compute the updated arrays for each side:
   - **source:** `linkedProblemIds` minus `targetId`; `typedLinks` filtered to drop any entry for `targetId`, then append `{targetId, kind}`.
   - **target:** `linkedProblemIds` minus `sourceId`; `typedLinks` filtered to drop any entry for `sourceId`, then append `{sourceId, inverse(kind)}`.
3. Single batched `update` on both docs.

`untagProblemLink` removes the matching `{targetId, kind}` from each side's `typedLinks`. **Does not restore** the generic clique link — explicit user re-link is required if they want it back.

### Deserialization

Extend `_docToProblem` in [firestore_repository.dart:588](apps/client/lib/services/firestore_repository.dart:588) to parse `typedLinks` from the Firestore document into `List<ProblemLink>`.

### UI — split button (`problem_detail_page.dart`)

Replace the single `IconButton(Icons.link)` at [problem_detail_page.dart:672](apps/client/lib/problems/view/problem_detail_page.dart:672) with a `Row` containing:

- The existing `IconButton(Icons.link, tooltip: linkProblemButton)` — opens the dialog in **generic** mode (today's behavior).
- A small `MenuAnchor` triggered by `Icons.arrow_drop_down` with two `MenuItemButton`s:
  - "Link as specialization" → opens dialog in `mode: specialization`.
  - "Link as generalization" → opens dialog in `mode: generalization`.

Visible only when the viewer is signed in (existing guard).

### UI — link dialog

Extend `_LinkProblemDialog` with a `ProblemLinkKind? mode` parameter (null = generic). The dialog title changes per mode (generic / "Link as specialization" / "Link as generalization"). Search and filtering are unchanged.

The "already linked" guard at [problem_detail_page.dart:1039](apps/client/lib/problems/view/problem_detail_page.dart:1039) is extended to also exclude problems whose ID appears in the current problem's `typedLinks.map((l) => l.targetId)` — i.e., a pair can have at most one relationship type.

Confirm action routes to `linkProblems` (generic) or `tagProblemLink(sourceId, targetId, mode)` (typed) based on mode.

### UI — three-section linked-problems display

The existing expansion tile at [problem_detail_page.dart:300](apps/client/lib/problems/view/problem_detail_page.dart:300) is restructured to render up to three subsections in this order, each hidden if empty:

1. **Generalizations (k)** — entries from `typedLinks` where `kind == generalization`. Trailing button: `Icons.link_off` with tooltip `untagProblemLinkTooltip` → `untagProblemLink`.
2. **Linked (existing generic section, unchanged)** — entries from `linkedProblemIds`. Trailing button: today's unlink that ejects from the whole clique.
3. **Specializations (m)** — entries from `typedLinks` where `kind == specialization`. Trailing button as above.

The combined count in the parent heading sums all three.

`_load` is extended to fetch typed-link targets in parallel with generic ones (`Future.wait` over both lists), then partition results into the three buckets by re-reading the parent problem's `linkedProblemIds` and `typedLinks`.

### Notifications

Extend `ProblemLinkedPayload` (in `shared`) with an optional `ProblemLinkKind? kind`. Generic links emit `kind: null`. Typed links emit the kind from the **target's perspective** — so if user A tags their problem as a specialization of user B's problem, B receives a notification with `kind: specialization` (meaning "your problem has a new specialization").

Client notification rendering branches:

- `kind == null` → existing string.
- `kind == specialization` → `notificationProblemLinkedAsSpecialization` (new l10n key).
- `kind == generalization` → `notificationProblemLinkedAsGeneralization` (new l10n key).

---

## i18n

New ARB keys (English ARB gets them immediately; other locales fall back until translated):

| Key | English value |
|---|---|
| `linkAsSpecializationButton` | "Link as specialization" |
| `linkAsGeneralizationButton` | "Link as generalization" |
| `linkProblemDialogTitleSpecialization` | "Link as specialization" |
| `linkProblemDialogTitleGeneralization` | "Link as generalization" |
| `generalizationsHeading` | "Generalizations ({count})" |
| `specializationsHeading` | "Specializations ({count})" |
| `untagProblemLinkTooltip` | "Remove relationship" |
| `untagProblemLinkError` | "Couldn't remove the relationship." |
| `notificationProblemLinkedAsSpecialization` | "Someone linked their problem as a specialization of yours" |
| `notificationProblemLinkedAsGeneralization` | "Someone linked their problem as a generalization of yours" |

---

## Testing

### `packages/shared`

- JSON round-trip for `ProblemLink` and `ProblemLinkKind`.
- `Problem` round-trip with `typedLinks` populated and empty.

### `apps/server`

- `_problemToDocument` / `_documentToProblem` round-trip with mixed `linkedProblemIds` and `typedLinks`.

### `apps/client` repository (`firestore_repository_test.dart`)

- `tagProblemLink` writes both sides with inverted kinds.
- `tagProblemLink` removes the pair from both sides' `linkedProblemIds` when previously generic-linked.
- `tagProblemLink` replacing an existing typed-link kind deduplicates rather than appends.
- `untagProblemLink` symmetric removal; does not restore the generic link.
- Invariant test: after any tag/untag sequence, no pair appears in both lists on either doc.

### `apps/client` widget (`problem_detail_page_test.dart`)

- Split button: icon tap opens dialog in generic mode; chevron tap shows the two menu items; selecting each opens the dialog in the right mode.
- Linked-problems display partitions into three subsections in the expected order; empty subsections hidden.
- Typed-link row's untag button calls `untagProblemLink` with the right args.
- "Already linked" dialog guard excludes problems with a typed link in either direction.

---

## Migration & backwards compatibility

- Existing Firestore documents have no `typedLinks` field. Parsing returns the `@Default([])` empty list — no data migration required.
- Server PUT preserves `typedLinks` on partial updates.
- Old clients reading new docs ignore the unknown field (Freezed defaults tolerate extra keys).
- Old clients writing docs omit `typedLinks`; server preservation prevents data loss.
- Old clients never touch `typedLinks` directly, so the cross-list invariant holds.

---

## Follow-up notes (out of scope)

- Toolbar density on narrow screens — if the split button still crowds, future work could collapse the entire link affordance into a single bottom-sheet chooser.
- Transitive reasoning across the typed graph.
- Property-style/randomized testing for the cross-list invariant.
