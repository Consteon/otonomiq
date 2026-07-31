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
that submit one or more write operations (updateEventRow, addToEvent, addToTable, updateTableRow)
inline via a single saveSend call. One action can optionally require a note via a
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
| `updateEventRow1` | `String` | Button 1: merge keyed doc (updateEventRow DSL). Empty = this op off. |
| `addToEvent1` | `String` | Button 1: append keyed event (addToEvent DSL). Empty = this op off. |
| `addToTable1` | `String` | Button 1: positional table add. Empty = this op off. Must author explicit `tableVid◼` (see Behavior). |
| `updateTableRow1` | `String` | Button 1: positional table update. Empty = this op off. Must author explicit `tableVid◼` (see Behavior). |
| `updateEventRow2` | `String` | Button 2: merge keyed doc. Empty = this op off. |
| `addToEvent2` | `String` | Button 2: append keyed event. Empty = this op off. |
| `addToTable2` | `String` | Button 2: positional table add. Empty = this op off. Must author explicit `tableVid◼`. |
| `updateTableRow2` | `String` | Button 2: positional table update. Empty = this op off. Must author explicit `tableVid◼`. |
| `note` | `String` | Optional display line template with `<field>` tokens resolved from the row doc. Empty or absent = not rendered. If the template contains tokens and ANY resolves to missing/blank, the entire line is hidden (no half-resolved stubs). If the note does not appear, check the token spelling first — a misspelled `<field>` is hidden exactly like an unstamped one. **This is a display-only line — unrelated to the `notePosition` rejection-reason bottom sheet.** |
| `actionMeta` | `String` | Per-action: `tone◼flag[◼posisiNote]` ◆-split |
| `text` | `String` | 13 ◆-segments for all UI labels |
| `gateTable` | `String` | Slot gate: keyed collection for grant docs. Bare name = subcollection under same `table` docId. Full path also accepted. **This key alone decides whether gating is requested** — empty = gating OFF, non-empty = gating ON and every later failure is fail-closed. |
| `gateSearch` | `String` | Search DSL for current user's grant docs (raw to `filterDriverHomeDocs`). Example: `ty◼approver⭘vid◼{userVid}`. **Required whenever `gateTable` is set** — leaving it empty does NOT disable gating, it yields an empty list. **Must identify the user by the `{userVid}` token, never a literal vid** — see "Identity" in `docs/widgets/approval_detail.md`. |
| `gateSlot` | `String` | `slotField◆pointerField◆levelField`. Example: `sc◆ak◆cl`. **Required whenever `gateTable` is set** — empty/unparseable yields an empty list, not "gating off". |

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

- **actionMeta pairs positionally with button N's write DSLs.** `actionMeta` segment 1 (before the
  first `◆`) configures button 1; segment 2 configures button 2. The segment index is ABSOLUTE --
  segment 1 always means button 1 regardless of which buttons are visible. Button N is visible when
  at least one of its 4 write DSL keys (`updateEventRow{N}`, `addToEvent{N}`, `addToTable{N}`,
  `updateTableRow{N}`) is non-empty AND `actionMeta` has a segment at position N-1. If you want a
  single reject-only button, put its `tone◼flag[◼posisiNote]` in segment 1 and author its DSLs
  under the `...1` keys, NOT the `...2` keys.
- **Position token offset:** The note position in `actionMeta` is a literal txfController position
  (e.g. `5` means `txfController[scrName][5]`). When the RBT's DSL references this position via
  `◁N▷`, it resolves to `ref[1][N-1]` = form position `N-1`. Therefore the builder MUST author
  `◁posisiNote+1▷` in the action DSL to reference the note at position `posisiNote`. Example:
  note at position 5 → DSL token is `◁6▷`, NOT `◁5▷`.
- **saveSend appVid is always `defaultVid()`.** The 5th `saveSend` argument is the *history-row*
  appVid forwarded to `appendToSheet`; every live caller passes `defaultVid()`. The target
  *table* vid reaches Firestore through the DSL's own `⭘tablevid◼…` segment, not through this
  argument. `vidtable` only feeds the read subscription path.
- **Positional ops and tableVid injection:** `saveSend` injects `tableVid◼$currentTableVid` into
  positional DSLs containing `◼A⭘`/`◼D⭘`/`◼S⭘` (api.dart:4506-4508) where `currentTableVid` is
  the 5th argument (`defaultVid()`), NOT this widget's `vidtable`. An `addToTable{N}` /
  `updateTableRow{N}` DSL using those markers would land in the wrong tenant table. Positional ops
  on this widget must author an explicit `tableVid◼` segment in the DSL, exactly as the keyed ops
  already ride their own `⭘tablevid◼`.
- **`route` / `delay` are stripped before saveSend.** The card-tap `route` is always present;
  if it reached saveSend, `routeExist(component['route'])` (api.dart) would fire
  `clearData(scrName)` and wipe the whole screen's `txfController` plus every per-screen store.
  Both keys are removed from the component copy for the inline write.
- **ABORT rule:** If any `{field}` token in the action DSL cannot be resolved from the tapped row
  doc (field absent or empty), the write is silently aborted (no saveSend, no network request)
  **before** the note sheet is shown. Buttons re-enable. A WARN is logged via devPrint.
- **Token scope — row doc + session tokens:** every `{token}` in an action DSL is first resolved
  against the tapped Firestore row doc. If the token is absent or empty in the row doc, the
  resolver probes `resolveDriverCurlyTokens` -- if it recognises the token (e.g. `{userVid}`,
  `{userName}`), the token is left literal and `saveSend`'s own `resolveDriverCurlyTokens` call
  resolves it downstream. If neither source knows the token, the write ABORTs (no saveSend, buttons
  re-enable, WARN logged). Note: `saveSend` only calls `resolveDriverCurlyTokens` on the
  `addToEvent` and `updateEventRow` paths -- session tokens in `addToTable`/`updateTableRow` DSLs
  will NOT be resolved and will reach Firestore as literal `{name}`.
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
- **Slot gating — `gateTable` is the intent switch, everything else fails CLOSED.** With
  `gateTable` absent, gating was never requested and docs pass through untouched (back-compat for
  `RewardReview@1014` and every pre-gating consumer). With `gateTable` present, gating WAS
  requested and **every** subsequent failure yields an EMPTY list, never the unfiltered set —
  unparseable `gateSlot`, empty `gateSearch`, unresolved subscription, no matching grant doc,
  slot field with no terms, or any thrown exception. The asymmetry is the point: failing open
  here shows every pending request to every approver **with working approve/reject buttons**.
  Each fail-closed branch emits a `devPrint` naming the cause; a working gate logs
  `grants=N concrete={…} wildcardLevels={…} X→Y`. Gating is applied BEFORE stats counts and
  sorting. See `list_card.md` for the full section (identical semantics in both widgets).
- **Level indicator via meta slot:** the `fields` position 3 (`metaTpl`) already resolves `<field>`
  tokens from the row doc. Set it to `"Level <cl> dari <nl>"` for the approval level line. No
  separate `note` config key is needed — the existing meta slot covers this use case. Empty meta
  template = no line rendered.
- **Cross-reference — detail-page gate.** The ApproverStickyBar (detail page) uses the same gate
  infrastructure with a sibling key `gateRowSlot` (numeric row indexes instead of field names). See
  `docs/widgets/approval_detail.md` "Slot gate on ApproverStickyBar" for details. The RBT's
  `gateTable` MUST use the fully-qualified `{docId}//subColl` format (bare-name resolution is not
  available on the RBT). The RBT and list components SHOULD carry the same `vidtable`/`com` so they
  share a subscription key.

## See Also

- [list_card.md](list_card.md) -- read-only keyed list (display machinery reused)
- [payout_list.md](payout_list.md) -- inline per-row write + per-screen state pattern
- [stat_card_row.md](stat_card_row.md) -- keyed cache → number cards (same subscription engine)
