# ListActionCard

Config-driven keyed list with inline per-row action buttons that write via saveSend updateEventRow.

- **File:** [lib/widget/list_action_card.dart](../../lib/widget/list_action_card.dart)
- **Class:** `ListActionCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** unreleased

## Purpose

Replaces the list-navigate-act-back roundtrip for high-volume review queues. Each row shows
a summary card (thumbnail/title/subtitle/meta/badge) and exposes up to 2 action buttons
that submit an updateEventRow write inline. One action can optionally require a note via a
bottom sheet before submission.

## Signature / Constructor

```dart
ListActionCard({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | Table VID used to resolve the subscription path (`resolveAppVid`). NOT the saveSend appVid. |
| `table` | `String` | Keyed collection `tableDocId//subColl` |
| `search` | `String` | Server filter DSL (passed raw to `filterDriverHomeDocs`, which decodes it) |
| `sort` | `String` | `field◼dir` (asc/desc), split at first `◼` |
| `fields` | `String` | 6 ◆-segments: titleTpl, subtitleTpl, imageField, metaTpl, badgeField, badgeMap |
| `stats` | `String` | Header stat boxes (`Label◼filter★…`) |
| `searchFields` | `String` | Client search bar fields |
| `route` | `String` | Card-tap route (empty = tap disabled) |
| `routeParams` | `String` | Route params DSL |
| `action1` | `String` | updateEventRow DSL for button 1 |
| `action2` | `String` | updateEventRow DSL for button 2 |
| `actionMeta` | `String` | Per-action: `tone◼flag[◼posisiNote]` ◆-split |
| `text` | `String` | 13 ◆-segments for all UI labels |

### `text` positions (0-indexed)

| # | Purpose |
|---|---|
| 0 | Header title |
| 1 | Header subtitle |
| 2 | Header count unit label |
| 3 | Search bar hint |
| 4 | Empty state text |
| 5 | Action 1 button label |
| 6 | Action 2 button label |
| 7 | Note popup title |
| 8 | Note popup body |
| 9 | Note input label |
| 10 | Note input hint |
| 11 | Note send button label |
| 12 | Fallback subtitle (when row subtitle empty) |

## Important Behavior

- **actionMeta pairs positionally with actionN.** `actionMeta` segment 1 (before the first `◆`)
  configures `action1`; segment 2 configures `action2`. This is by *position*, not by name —
  authoring only `action2` still consumes `actionMeta` **segment 1** (there is no way to skip a
  segment). If you want a single reject-only button, put its `tone◼flag[◼posisiNote]` in
  segment 1 and author its DSL in `action1`.
- **Position token offset:** The note position in `actionMeta` is a literal txfController position
  (e.g. `5` means `txfController[scrName][5]`). When the RBT's DSL references this position via
  `◁N▷`, it resolves to `ref[1][N-1]` = form position `N-1`. Therefore the builder MUST author
  `◁posisiNote+1▷` in the action DSL to reference the note at position `posisiNote`. Example:
  note at position 5 → DSL token is `◁6▷`, NOT `◁5▷`.
- **saveSend appVid is always `defaultVid()`.** The 5th `saveSend` argument is the *history-row*
  appVid forwarded to `appendToSheet`; every live caller passes `defaultVid()`. The target
  *table* vid reaches Firestore through the DSL's own `⭘tablevid◼…` segment, not through this
  argument. `vidtable` only feeds the read subscription path.
- **`route` / `delay` are stripped before saveSend.** The card-tap `route` is always present;
  if it reached saveSend, `routeExist(component['route'])` (api.dart) would fire
  `clearData(scrName)` and wipe the whole screen's `txfController` plus every per-screen store.
  Both keys are removed from the component copy for the inline write.
- **ABORT rule:** If any `{field}` token in the action DSL cannot be resolved from the tapped row
  doc (field absent or empty), the write is silently aborted (no saveSend, no network request)
  **before** the note sheet is shown. Buttons re-enable. A WARN is logged via devPrint.
- **Token scope — row doc ONLY:** every `{token}` in an action DSL is resolved against the tapped
  Firestore row doc and nothing else. Session/screen tokens (`{today}`, `{driverVid}`,
  `{vehicleId}`, …) are NOT passed through to `saveSend`'s own `resolveDriverCurlyTokens` — they
  have no matching row field, so they trip the ABORT rule and the write silently no-ops. Author
  action DSLs with row-field tokens only; if a future consumer needs a session token, the resolver
  must be widened first (it is not today).
- **Note slot hygiene:** the note slot (`txfController[scrName][posisiNote]`) is cleared
  (`finalData = "--"`, `controller.text = ""`) on every exit that does not submit (sheet
  dismissed) and right after a submit reads it, so a stale reason never rides the next write.
- **Stats strip suppression (no duplicate count):** the header already shows the total. The stats
  strip renders **only** when at least one parsed `StatsDef` has a non-empty filter. If every
  `stats` box has an empty filter (e.g. `stats:"Antrian◼"`), the strip would just duplicate the
  header count, so it is suppressed.
- **Obx:** unconditional `mapTableContent[_code]` read at top of builder prevents GetX
  zero-observable crash.
- **In-flight per-row:** Both buttons on a row disable + show spinner while that row's write is
  in progress. Other rows are unaffected. State keyed by scrName + row doc ID (`__docId`).
- **Thumbnail guard:** Image.network is used only for a parseable absolute URL
  (`Uri.tryParse(url)?.hasScheme`); any other value shows a grey placeholder box (the same one the
  errorBuilder shows). A malformed URL would otherwise throw in `_Uri.resolve` at paint time.
- **Offline:** saveSend queues the write, a snackbar confirms offline storage, and the row's
  buttons re-enable immediately (nothing will remove the row until the queue syncs).
- **Row disappearance:** Reactive — when the write changes the doc's `st` field it fails the
  `search` filter and drops out of the displayed list on the next Obx rebuild.

## See Also

- [list_card.md](list_card.md) -- read-only keyed list (display machinery reused)
- [payout_list.md](payout_list.md) -- inline per-row write + per-screen state pattern
- [stat_card_row.md](stat_card_row.md) -- keyed cache → number cards (same subscription engine)
