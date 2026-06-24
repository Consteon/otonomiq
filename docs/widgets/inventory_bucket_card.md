# InventoryBucketCard

Vehicle stock display card for DriverHome (P4). Shows real-time asset counts per condition bucket (isi/kosong).

- **File:** [lib/widget/inventory_bucket_card.dart](../../lib/widget/inventory_bucket_card.dart)
- **Class:** `InventoryBucketCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Displays the current vehicle inventory grouped by asset type with per-bucket
(condition) qty sums. HIDDEN when the DriverHome gate has not confirmed
(`DriverHomeState.confirmed == false`). Reads `asset_cache` docs via the
mapCollection subscribe pattern.

## Signature / Constructor

```dart
InventoryBucketCard({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

## `component` shape

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | String | yes | `"INVENTORY_BUCKET_CARD"` |
| `table` | String | yes | `"<docId>//asset_cache"` |
| `search` | String | yes | `"lv◼(VEHICLEID)"` |
| `vidtable` | String | yes | App VID for Firestore path |
| `categoryField` | String | no | Field for bucket category (default `cd`) |
| `categoryMap` | String | no | Maps `cd` values to bucket labels: `"cdValue◼bucketLabel⭘cdValue◼bucketLabel"` (autheniumDecode applied). Overrides the built-in identity/positional fallback |
| `typeField` | String | no | Field for asset type name (default `ty`) |
| `qtyField` | String | no | Field for quantity (default `qt`) |
| `buckets` | String | yes | Bucket defs: `"label◼status⭘label◼status"` |
| `text` | String | yes | diamond-delimited 2 slots |

## cd → bucket mapping (W2)

The `categoryField` (default `cd`) value on each asset_cache doc is mapped to a
bucket label via, in priority order:

1. **`categoryMap`** override (server JSON), if supplied.
2. **Identity** — a `cd` value equal to a bucket label maps to itself.
3. **Positional fallback** — `full` → bucket[0], `empty` → bucket[1] (English
   convention; last resort only).

`BucketDef.status` (`ok`/`warn`/`danger`) drives the primary qty accent color
(neutral / amber / red).

> OPEN ITEM: verify real asset_cache `cd` values, `ty` (type) and `qt` (qty)
> field codes on-device. If `cd` values are neither `full`/`empty` nor equal a
> bucket label, supply `categoryMap`.

## Lifecycle

1. `initState` -> parse text, parse buckets, subscribe to asset_cache
2. `build` (Obx) -> gate check (confirmed?), filter + group docs, render
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## See Also

- `PreconditionGateCard` -- publishes the `confirmed` state this widget reads
- `DriverStopCard`, `NavActionCard` -- sibling Phase 2 consumers
- `DriverHomeState` (`driver_home_support.dart`) -- shared state holder
