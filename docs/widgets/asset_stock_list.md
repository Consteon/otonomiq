# AssetStockList

Generic pivot-cube stock distribution widget. Renders entity x pivotValue x condValue aggregation with summary strip, filter tabs, proportion bar, and per-pivot breakdown cards. Display-only.

- **File:** [lib/widget/asset_stock_list.dart](../../lib/widget/asset_stock_list.dart)
- **Class:** `AssetStockList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Displays stock distribution as a pivot cube (entity x dimension x condition). First consumer: Admin/Owner "Stok & Sebaran Aset" page. Fully generic: swap table+field config for any (entity x dimension -> sum value) distribution.

## Signature / Constructor

```dart
AssetStockList({
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

| Key | Type | Description |
|---|---|---|
| `table` | `String` | asset_cache collection path |
| `search` | `String` | Optional filter |
| `hideZero` | `String` | `TRUE` to skip zero-qty |
| `groupField` | `String` | Entity key (default `ii`) |
| `valueField` | `String` | Sum field (default `qt`) |
| `pivotField` | `String` | Dimension key (default `lt`) |
| `pivotValues` | `String` | `value◼label◼icon★...` |
| `condField` | `String` | Condition key (default `cd`) |
| `condValues` | `String` | `value◼label★...` |
| `showCondition` | `String` | `TRUE`/`FALSE` |
| `joinTable` | `String` | Item join collection |
| `joinKey` | `String` | Join key (default `ii`) |
| `nameField` | `String` | Item name field (default `in`) |
| `catField` | `String` | Item category field (default `ic`) |
| `itemIconMap` | `String` | `key◼emoji◼slot★...` |
| `filterTabs` | `String` | `TRUE`/`FALSE` |
| `summary` | `String` | `scope◼label★...` |
| `title` | `String` | Header title |
| `subtitle` | `String` | Header subtitle |
| `text` | `String` | Diamond-separated label segments |
| `condNote` | `String` | Caveat text (shown when showCondition) |
| `emptyText` | `String` | Empty state text |
| `detailField` | `String` | Detail group field for per-location breakdown in pivot tabs (default empty = no breakdown) |
| `detailNameField` | `String` | Display name field for detail rows (default empty = id used) |
| `detailSubField` | `String` | Inline subtitle field for detail rows, rendered after name with ` · ` separator (default empty = name only, zero regression) |

## State / Dependencies

- **State:** GetX `mapTableContent` (reactive Obx rebuild).
- **Subscriptions:** 2 Firestore collections (asset_cache + item).
- **Screen state:** `static Map<String, int> _activeTab` keyed by scrName, cleared via `clearState(scrName)` from `ui_component.dart` buildPage.
- **Side effects:** None (read-only).

## Important Behavior

- `showCondition:FALSE` (default) hides Isi/Kosong per-item split and condNote. Summary strip always computes full cube.
- Last pivotValue with non-empty text seg-3 renders "outstanding-style" (violet, no condition split).
- `text` seg-2 (unit, e.g. "pcs") renders next to the big entity/pivot totals when present; absent config = no unit.
- No detail sheet, no navigation. Display-only.
- `autheniumDecode` applied to pivotValues/condValues/summary/itemIconMap before splitting.
- Semua-tab pivot boxes and summary strip chips are tappable -- tap switches to the corresponding filter tab.
- Pivot boxes with total 0 render at 50% opacity (dimmed, still tappable).
- When `detailField` is set, specific-pivot tabs (not Semua) show per-detail rows instead of the aggregate ISI/KOSONG box. Each row shows condition split when `showCondition:TRUE` and the pivot is non-outstanding; otherwise shows single total.
- When `detailSubField` is set, detail rows in pivot tabs show `name · sub` inline (e.g. `B 1234 XY · Pickup`). Absent config or absent/empty field on doc = name only, no layout shift.

## See Also

- [customer_outstanding_list.md](customer_outstanding_list.md) -- sibling widget (same data source, different aggregation)
