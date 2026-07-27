# PayoutList

Multi-select keyed-table list with per-item nominal (count x rate), select-all, summary totals, emitting selected values/labels/total to form positions.

- **File:** [lib/widget/payout_list.dart](../../lib/widget/payout_list.dart)
- **Class:** `PayoutList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Admin selects workers for bulk payout marking. Each item shows a computed nominal (count field x rate), and the widget tracks a running total of selected items. Emits selected ids, labels, and total nominal to form positions for downstream RBT submission.

Replaces the interim GROUP_PICKER src:table on RewardPayout@1026 which showed names only (no nominal / no total).

## Signature / Constructor

```dart
PayoutList({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

| Key | Type | Required | Description |
|---|---|---|---|
| `type` | `String` | yes | `"PAYOUT_LIST"` |
| `vidtable` | `String` | yes | App VID for table subscription |
| `table` | `String` | yes | `"docId//subColl"` keyed table path |
| `search` | `String` | no | eq-only filter (e.g. `"rd◼1"`) |
| `labelField` | `String` | no | Row label field (default `"n"`) |
| `subField` | `String` | no | Row sub-label field (empty = 1 line) |
| `countField` | `String` | no | Numeric count field for nominal calc |
| `valueField` | `String` | no | Emitted value field (empty = `__docId`) |
| `rate` | `String` | no | Rupiah per unit (empty/0 = non-money mode). Parsed via `num.tryParse` then `.round()`, so `"1000.5"` becomes `1001` (whole rupiah). |
| `sortField` | `String` | no | Sort key |
| `sortDir` | `String` | no | `"asc"` (default) or `"desc"` |
| `position` | `int` | yes | Form position for selected values |
| `labelPosition` | `int` | no | Form position for selected labels |
| `totalPosition` | `int` | no | Form position for total nominal (plain int) |
| `selectAll` | `bool` | no | Show select-all row (default false) |
| `joinSep` | `String` | no | Output join separator (default `"|"`) |
| `maxListHeight` | `num` | no | Max px height for scrollable list |
| `text` | `String` | no | diamond-separated text segments (see below) |

### `text` segments (by index)

| Idx | Token(s) | Description |
|---|---|---|
| 0 | -- | Title |
| 1 | -- | Empty state label |
| 2 | `{n}` | Select-all label |
| 3 | `{n}`, `{total}` | Selected counter |
| 4 | `{c}`, `{nom}` | Per-item nominal line |
| 5 | `{total}`, `{n}` | Grand summary |

## State / Dependencies

- **State:** `static Map<String, Map<int, Set<String>>> _selectionStore` keyed by `scrName` then `position`. `_selectionStore` may hold stale ids from departed rows; emission always intersects with the live row set so stale ids are excluded by construction. Cleared on route change via `clearState(scrName)` registered in both `clearData` (api.dart) and `buildPage` (ui_component.dart).
- **GetX:** `Obx` wrapping `mapTableContent[_code]` for reactive table updates.
- **Helpers:** `PickerList.filterRows`, `TaskItemBuilder.sortPickerItems`, `TablePicker.resolveValueFromDoc`, `AdminCreateTaskSupport.formatRupiah`, `resolveAppVid`, `resolveDriverCurlyTokens`, `parseTablePath`, `coerceNum`.

## Important Behavior

- **Emit ordering:** all three outputs (values, labels, total) are derived from a single ordered pass over the sorted row set. This guarantees `position` and `labelPosition` are index-aligned parallel arrays regardless of tap order.
- **Stale id tolerance:** if a row departs the Firestore subscription (e.g. CF resets `rd` after payout), its id may linger in `_selectionStore` but is excluded from all outputs by the intersection pass.
- **Non-money mode:** rate empty/0 hides nominal lines (text[4]) and collapses `{total}` tokens with surrounding separators (generalised, any punctuation separator; removes the token plus one adjacent separator run, preferring trailing then leading).
- **Emit:** writes to `txfController[scrName][pos].finalData` on every toggle. Never uses diamond as join separator (forbidden char, destroyed by `stringCleanUp`).
- **Obx:** unconditional `mapTableContent[_code]` read at top of builder prevents GetX zero-observable crash.
- **Position token offset:** RBT references these positions via position-token which resolves to slot `N-1`. So RBT must author `pos+1` tokens.
- **Selected counter placement (I1):** rendered as a separate line below the select-all row, not inline right-aligned as shown in the spec mockup. Acceptable divergence; revisit if designer requests inline.

## See Also

- [group_picker.md](group_picker.md) -- multi-group picker (interim on the same page)
- [table_picker.md](table_picker.md) -- single/multi picker with modal sheet
- [list_card.md](list_card.md) -- read-only keyed list
