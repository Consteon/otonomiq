# TablePicker

Generic single/multi-select picker bound to **form positions**: pick one or more records from **any** keyed Firestore table collection and write the value(s) + label(s) into `txfController` slots so they ride the standard submit / `addToTable` path. Zero entity baked in — workforce / customer / item / model are all just config.

- **File:** [lib/widget/table_picker.dart](../../lib/widget/table_picker.dart)
- **Class:** `TablePicker` (StatefulWidget)
- **SDUI type:** `table_picker`
- **Status:** draft
- **Widget version:** v1
- **Introduced in:** unreleased (dev, 2026-07-14)
- **Spec:** `fate-runtime-dev-spec.md` §4

## Purpose

One renderer for every form-bound picker over a table collection. Unlike [PickerList](picker_list.md) — which captures a single id into a **screenTx token** — `TablePicker` writes into **form positions** (`txfController[scrName][position]` / `[labelPosition]`), so the picked value flows into the submitted record via `resolveValueTokens` position markers (e.g. `◁16▷` for `position:16`). This lets the standard `addToTable` DSL (`mv◼◁16▷⭘mn◼◁26▷`) pick up both the value and the label. Supports single **and** multi selection, config-driven labels, and search-DSL filtering.

## `component` shape

```json
{
  "type": "TABLE_PICKER",
  "mode": "single",
  "vidtable": "20342033315492",
  "table": "84214220504259//workforce",
  "search": "ps◼model",
  "labelField": "n",
  "subField": "ps",
  "valueField": "",
  "max": 0,
  "position": 16,
  "labelPosition": 26,
  "title": "Assign model",
  "hint": "Pilih satu atau lebih",
  "text": "Pilih Model◆Cari nama◆Data tidak ditemukan◆Pilih◆Batal◆{n} dipilih"
}
```

| Field | Default | Description |
|---|---|---|
| `mode` | `single` | `single` = one bare value; `multi` = JSON-array of values. Case-insensitive |
| `table` / `vidtable` | — | source keyed collection + appVid. `vidtable` is `resolveAppVid`'s first priority. Empty `table` → no subscription, no rows |
| `search` | — (all rows) | gate-DSL row filter `key◼val⭘…`; `autheniumDecode`'d then AND-matched via `PickerList.filterRows` (shared, no coupling). Empty → all docs |
| `labelField` | `n` | doc field shown as row title AND captured as the label written to `labelPosition` |
| `subField` | — | doc field shown as row subtitle (omit → no subtitle). Also matched by the client-side search box |
| `valueField` | — | doc field captured as the value written to `position`. **Empty → the Firestore doc id** (`__docId`, stamped by `subscribeToMapCollection`) |
| `max` | `0` | multi-mode cap; `0` = unlimited. Ignored in single mode (forced to 1) |
| `position` | — | **required** form slot the value(s) are written to. Missing → dispatch degrades to `--table_picker-- missing position` (does not build) |
| `labelPosition` | — | **required** form slot the label(s) are written to. Missing → same degrade as `position` |
| `title` | — | field label rendered above the tap-target; also the sheet-title fallback (`text[0]`) |
| `hint` | — | placeholder shown in the tap-target when nothing is selected |
| `text` | — | `◆`-separated sheet strings (see below); all length-guarded |

### `text` slots (`◆`-separated, all length-guarded)

| # | Meaning | Default |
|---|---|---|
| 0 | Sheet title | falls back to `title` field |
| 1 | Search-box hint | `''` |
| 2 | Empty-state text | `Tidak ada data` |
| 3 | Confirm button label (multi) | `Pilih` |
| 4 | Cancel button label (multi) | `Batal` |
| 5 | Count-label template (`{n}` = count) | `{n} dipilih` |

Access is via `TablePicker.textSegment(arr, i, def)` → `arr.length > i ? arr[i] : def`, so a lean tenant sheet that ships fewer than 6 segments never throws.

## Behavior & data flow

- Tapping the field opens a **modal bottom sheet** (`showModalBottomSheet`) — NOT a route, so no `routeStack` push.
- **Single mode:** tapping a row auto-confirms (writes + closes); selection is capped at 1.
- **Multi mode:** rows toggle; a bottom bar shows the count + Cancel/Confirm. `max > 0` blocks further taps once reached; Cancel discards the sheet's working set (the field's committed selection is untouched), Confirm commits.
- The picked value/label are written to `txfController` on confirm (and on chip-remove). On re-open, the field re-seeds its working set from the stored `txfController` value via `decodeSelection`.

### Output encoding (`position` / `labelPosition`)

| mode | `position.finalData` | `labelPosition.finalData` |
|---|---|---|
| single | bare value (e.g. `V1`) | bare label (e.g. `Alice`) |
| multi | JSON-array string `["V1","V2"]` | JSON-array string `["Alice","Bob"]` |

### ⚠ Multi-mode CF un-escape contract

The submit path runs every field value through `stringCleanUp` → `quoteCleanUp` (`global.dart`), which escapes quotes:

```
"  ->  `` (two backticks)
'  ->  `  (one backtick)
```

So a multi-mode `["V1","V2"]` **persists in Firestore backtick-escaped** as `` [``V1``,``V2``] `` — which is **not valid JSON**. Any consumer that wants a native array MUST reverse the escaping before `JSON.parse`, two-backticks first:

```js
// Consteon/asset_cache CF onFateProjectCreated
const json = raw.replaceAll('``', '"').replaceAll('`', "'");
const arr  = JSON.parse(json);
```

Single mode writes a bare value with no quotes, so it is unaffected. (This is a backend contract; the widget deliberately keeps writing the JSON string — decided 2026-07-14: keep JSON, CF un-escapes.)

## Static methods (tested directly)

- `resolveValueFromDoc(doc, valueField)` — value capture; empty `valueField` → `__docId`.
- `encodeSelection(values, isSingle:)` — single → bare, multi → JSON-array string (see contract above).
- `decodeSelection(stored, isSingle:)` — reverse for re-open/chips; malformed JSON and the `--` empty sentinel → `[]` (no crash).
- `textSegment(arr, i, def)` — length-guarded `text` accessor.
- `canAddMore(currentCount:, max:)` — `max <= 0` unlimited, else `currentCount < max`.
- `clientSearch(rows, query, labelField, subField)` — case-insensitive `contains` filter for the sheet search box.
- `clearState(scrName)` — clears the per-screen selection/label stores; called from `buildPage` clearData.

## State / dependencies

- **Per-screen state:** `static Map<String, Map<int, Set<String>>>` (+ companion label map), keyed by `scrName` **and** `position` so two pickers on one screen don't collide. Static-on-class (never `global.dart`), cleared in `buildPage`'s clearData path.
- **Data source:** `subscribeToMapCollection` (vid-scoped code `$appVid/$tableDocId/$subColl`) → `mapTableContent[_code]`, read reactively inside `Obx`. Same pattern as PickerList / panel_card / statistic_card.
- **Repository:** `TableRepository` (`subscribeToMapCollection`), `panel_card_support.parseTablePath`.
- **Side effects:** writes `txfController[...].finalData` only; no Firestore write, no screenTx token, no history entry.

## Tests

[test/table_picker_test.dart](../../test/table_picker_test.dart) — 30 tests over the pure statics: `resolveValueFromDoc`, `encodeSelection`, `decodeSelection`, `textSegment`, `canAddMore`, `clientSearch`, plus two `PickerList.filterRows` reuse checks with `_25FC_`/`_u2B58_` server-encoded search strings.

## See Also

- [picker_list.md](picker_list.md) — sibling single-select picker; captures into a **screenTx token** instead of form positions, and the `filterRows` helper this widget reuses.
- [otq_txf_2.md](otq_txf_2.md) — the `txfController` paired-position write pattern this mirrors (tableSearch).
