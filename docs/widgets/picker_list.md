# PickerList

Generic single-select picker: pick one record from **any** collection and capture its id into a token. Optional per-row count badge and an "ad-hoc / lainnya" row. Zero entity baked into the renderer — vehicle / warehouse / slot / category / approver / customer are all just config.

- **File:** [lib/widget/picker_list.dart](../../lib/widget/picker_list.dart)
- **Class:** `PickerList` (StatefulWidget)
- **SDUI type:** `picker_list` (aliases `pickerlist`, legacy `vehicle_picker` / `vehiclepicker`)
- **Status:** draft
- **Widget version:** v1
- **Spec:** `picker-list-widget-dev-spec.md` (genericized from `VEHICLE_PICKER`, 2026-06-29)

## Purpose

One renderer for every single-select picker. The picker **never writes Firestore** — it binds the selected id into a screenTx token; the write is the caller's responsibility (H1 `updateEventRow`) or the page submit (create-task P3 → P4 draft). Before this widget, the page JSON referenced an unbuilt type and fell through to `--TYPE-- Wrong widget name.` (`build_display_component.dart`).

## `component` shape

```json
{
  "type": "PICKER_LIST",
  "mode": "capture",
  "vidtable": "20342033315492",
  "table": "84214220504259//stock_location",
  "search": "lt◼vehicle⭘lst◼active",
  "titleField": "ln",
  "subField": "ty",
  "metaField": "dv",
  "countTable": "84214220504259//task",
  "countSearch": "vv◼{lv}⭘tst◼assigned",
  "captureToken": "vv",
  "route": "",
  "adhocLabel": "Ad-hoc / Nanti",
  "emptyText": "Belum ada kendaraan aktif",
  "text": "Pilih Kendaraan◆Pilih◆task aktif"
}
```

| Field | Default | Description |
|---|---|---|
| `table` / `vidtable` | — | source collection + appVid |
| `search` | — (all rows) | gate-DSL row filter `key◼val⭘…`; `autheniumDecode`'d, AND-matched via `evaluateGate`. Empty → **all docs** (no entity fallback) |
| `titleField` | `ln` | row title (the one required display field) |
| `subField` | — | row sub/tag (omit → no sub line) |
| `metaField` | — | row 3rd line. Configured but doc value empty → placeholder `—`; not configured → no line |
| `idField` | `lv` | doc field whose value is **captured** and substituted for `{idField}` in `countSearch` |
| `countTable` + `countSearch` | — | per-row badge "{N} {countSuffix}". Counts `countTable` docs where `countSearch` matches, with `{idField}` (e.g. `{lv}`) → this row's id |
| `statusSearch` | — | per-row status pill (reuses `countForRow` over `countTable`; gated on `countTable` set). `{idField}` substituted (e.g. `vv◼{lv}⭘tst◼on_delivery`). >0 matches → `statusOnLabel` (amber); else `statusOffLabel` (emerald). Empty → no pill |
| `statusOnLabel` / `statusOffLabel` | — | pill text for the on/off state (e.g. `On Route` / `Available`) |
| `busySelfField` | *(empty)* | Optional. Row field; non-empty value = row is busy (disabled, un-tappable). Self-field case: the picker's own table carries the busy signal (e.g. `dv` on a `stock_location` vehicle row). Empty/absent = no busy guard. |
| `busySelfLabelField` | *(empty)* | Optional. Row field for the busy subtitle label (e.g. `dn` = driver name). Rendered as `text[3]` + field value. |
| `rowIcon` | — | **entity-card mode gate.** Non-empty icon name (resolved via `panelIcon`, e.g. `truck`/`vehicle`) → renders the ENTITY card: 40×40 icon-avatar + title + sub + inline `[status pill + count]` + selected-only check. Empty → legacy radio card (byte-identical). NOTE: entity mode **drops `metaField`** (no 3rd line) and moves the count badge inline. |
| `titleMono` | `false` | entity-mode only — monospace title (vehicle plates). Accepts bool or `"true"`/`"1"`. iOS falls back to Menlo/Courier. |
| `accentColor` | (theme primary) | hex (`0xFF2563EB`/`#2563EB`/bare) for selected border/avatar/check; entity selected-bg is fixed admin-blue tint `#EFF6FF`. |
| `captureToken` | `vv` | screenTx bare key bound to the selection. Override per context (`vehicleId`, `kl`, …) |
| `mode` | `capture` | `capture` = bind token only; `navigate` = bind token **+** push `route` |
| `route` | — | navigate-mode target (`[ROUTE:…]` wrapper stripped; `routeStack.push` before `gotoRoute`) |
| `adhocLabel` | — | non-empty → render an extra "＋" ad-hoc row |
| `adhocValue` | `''` | value captured by the ad-hoc row (empty = no fixed record; see Open Q1) |
| `emptyText` | `Tidak ada data` | shown when `search` yields 0 rows (never hide the widget silently) |

### `text` slots (`◆`-separated)

| # | Meaning |
|---|---|
| 0 | list title (reserved; the page usually has its own header) |
| 1 | per-row select label ("Pilih") |
| 2 | count badge suffix ("task aktif") |
| 3 | Busy prefix (e.g. `Sedang jalan \u{00B7} `). Prepended to `busySelfLabelField` value. |

`adhocLabel` / `emptyText` are dedicated fields, **not** `text` segments.

## Modes & data flow

```
capture:  tap row → screenTx[captureToken] = row[idField]      (no nav, no write)
navigate: tap row → screenTx[captureToken] = row[idField] → routeStack.push(route)
```

- **Create-task P3 (capture):** `captureToken:"vv"` → P4 `TASK_CREATE_SUBMIT` reads `screenTx[vvKey]` (default `vv`). **captureToken MUST equal the submit's `vvKey`** or P4 stays disabled.
- **H1 assign sheet (capture):** `captureToken:"vehicleId"`; caller's `updateEventRow:"…vv◼{vehicleId}…"` consumes it.
- Selection is re-derived from `screenTx[captureToken]` on **every** build (back-nav re-highlights; external token clear un-highlights). Ad-hoc row with empty `adhocValue` (the default `''`) is **not** visually highlighted after tap -- the empty token maps to `null` selection. Configure a non-empty `adhocValue` if ad-hoc highlight is needed.

## Busy guard (optional, self-field)

When `busySelfField` is configured, each row's own field is checked: non-empty
(trimmed) = the row is busy. The row renders DISABLED (grayed, un-tappable) with
a distinct subtitle = `text[3]` + `row[busySelfLabelField]` (e.g. "Sedang jalan
· Agenia Demo-3"). This is separate from the `statusSearch` pill (label-only,
never blocks selection) -- both can coexist on the same row config. When a row
is busy its trailing affordance (count badge + "Pilih" label / check icon) is
hidden in BOTH the radio and entity layouts, so an inert row never shows a
selectable cue.

Fail-open: empty `busySelfField` config -> `isBusy` is always false -> byte-
identical current behavior. Missing field key on a row -> empty string -> not
busy (no crash).

## Static methods (tested directly)

- `resolveCaptureToken(component)` / `resolveIdField(component)` — degrade-safe config resolution.
- `filterRows(docs, rawSearch)` — generic gate filter; empty search → all docs.
- `countForRow(countDocs, rawCountSearch, idField, rowId)` — per-row count; `{idField}` substitution; bails to 0 on empty rowId or leftover unresolved `{token}` (guards against accidental count-all).

## Tests

[test/picker_list_test.dart](../../test/picker_list_test.dart) — `filterRows` (single/AND gate, `_25FC_`/`_u2B58_` decode, client reuse), `countForRow` (per-row token sub, encoded, leftover-token guard, custom idField), config resolvers.

## Open questions (from spec §9)

1. May capture be empty (ad-hoc)? Tasks without `vv`? — affects `adhocValue` default and P4 gating.
2. H1 `schedule` mode: sheet+capture vs route to pre-filled Create Task.
3. `captureToken` varies per context (`vv` vs `vehicleId`) — leave free (recommended) or unify.
4. Fold P1 customer-picker into PICKER_LIST (replace `TASK_FEED_LIST` flat)? — owner decision.

## See Also

- [admin_vehicle_picker_sheet.md](admin_vehicle_picker_sheet.md) — the modal vehicle sheet (writes immediately; this picker only stages)
- [task_create_submit.md](task_create_submit.md) — P4 reader/writer of `vv`
- [task_item_builder.md](task_item_builder.md) — subscribe + screenTx-publish pattern this mirrors
