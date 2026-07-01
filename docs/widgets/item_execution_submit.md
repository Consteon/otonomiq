# ItemExecutionSubmit

Atomic submit button for P11 DeliveryWorkspace that persists driver stepper actuals into the task `it[]` array.

- **File:** [lib/widget/item_execution_submit.dart](../../lib/widget/item_execution_submit.dart)
- **Class:** `ItemExecutionSubmit` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** TBD

## Purpose

Replaces the generic RBT for P11 submit. The existing RBT wrote `tst=completed` + `tce` via `updateEventRow`, but never persisted the stepper actuals (`ad`/`ap`/`as`/`ab`/`ar`) to the task doc's `it[]` array. The CF `OnTaskCompleted` uses `qt = actual ?? plan`, so absent actuals caused incorrect movement quantities.

This widget performs ONE atomic native Firestore write with the rebuilt `it[]` + `tst` + `tce`, then runs `saveSend` for evidence/GPS/history with `tst`/`tce` stripped from the `updateEventRow` DSL.

## Signature / Constructor

```dart
ItemExecutionSubmit({
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

```json
{
  "type": "item_execution_submit",
  "table": "84214220504259//task",
  "search": "tnm◼{activeTaskVid}",
  "itemsField": "it",
  "txField": "tx",
  "planDropField": "pd",
  "planPickupField": "pp",
  "saleField": "ps",
  "buyField": "pb",
  "refillField": "pr",
  "actualDropField": "ad",
  "actualPickupField": "ap",
  "actualSaleField": "as",
  "actualBuyField": "ab",
  "actualRefillField": "ar",
  "updateEventRow": "<DSL with tst/tce auto-stripped>",
  "addToEvent": "<evidence DSL>",
  "chain": "<DO_DIALOG>",
  "route": "<fallback route>",
  "text": "KONFIRMASI PENGIRIMAN◆MEMPROSES...",
  "vidtable": "20342033315492",
  "com": "con"
}
```

## State

- **executionStore**: reads `ItemExecutionList.executionStore[scrName]` (shared, per-screen, cleared on route change). Read-only here — only `ItemExecutionList` writes it.
- **_writing**: `static Map<String, bool>` per-scrName debounce flag, cleared via `clearState(scrName)` (wired into `buildPage` clear block and `clearData`).

## Data flow

1. Subscribe to task collection via `subscribeToMapCollection`.
2. On tap: find task doc → `extractItemsFromDoc` (identical extractor to `ItemExecutionList._extractItems`, so `'$i'` index keys align) → `rebuildItWithActuals` → atomic `writeNativeFields` (`{it, tst, tce}`, set-merge) → `saveSend` (evidence + GPS + history) → navigate.
3. On native-write failure: snackbar, no `saveSend`, no navigation.

## DSL handling (`updateEventRow` / `addToEvent`)

Mirrors `CustodyEventSubmit` exactly (custody_event_submit.dart:275-301):

- The widget resolves `{curly}` tokens only (`resolveDriverCurlyTokens`) and hands the still-**literal** `⭘`/`◼` DSL to `saveSend`. It does **NOT** `autheniumDecode` the DSL — `saveSend` runs its own decode (api.dart:4269/4282; a no-op on already-literal text) and the diamond decode happens later at history-sync (table_repository.dart:1502/1514). Pre-decoding here would be a redundant double-decode.
- `tst`/`tce` strip (`stripTstFromUpdateEventRow`) runs on that literal form. Confirmed against the live `op1screen` artifacts for the sibling `CUSTODY_EVENT_SUBMIT` template (`docs/driver_runtime/*-op1screen.md`) and `json/admin-runtime/*.json` — the stored `updateEventRow` always uses literal `⭘`/`◼`.
- **Empty-body guard** (`updateEventRowHasBody`): the live P11 `updateEventRow` is only `tst◼completed⭘tce◼{now}` plus the `path`/`tablevid`/`search` header clauses. After stripping `tst`+`tce` no body clause remains, so the widget drops `updateEventRow` from the `saveSend` payload entirely (historySync would otherwise issue a harmless `set({}, merge:true)` no-op query/write).

## Timestamp (`tce`)

`tce` and the `saveSend` history timestamp share a single `await getRealTime()` value (NTP/server-truth, matching `saveSend`'s own clock) rather than the synchronous local `getNowMillisecondFromEpoch()`.

## See Also

- [item_execution_list.md](item_execution_list.md) — the stepper list widget (writes executionStore).
- [custody_count_submit.md](custody_count_submit.md) — pattern model (subscribe + native write + nav).
- [custody_event_submit.md](custody_event_submit.md) — pattern model (curly token pre-resolve + doChain + DSL handling).
