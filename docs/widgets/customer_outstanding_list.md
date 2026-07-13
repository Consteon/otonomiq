# CustomerOutstandingList

**File:** `lib/widget/customer_outstanding_list.dart`
**Component type:** `CUSTOMER_OUTSTANDING_LIST`
**Status:** draft

## Purpose

Full-page customer outstanding lookup surface. Shows all customers with
outstanding custody balance (assets on loan), grouped by customer with
category-colored per-item chips, aging tiers, and a detail bottom sheet.

## Component JSON

```json
{
  "type": "CUSTOMER_OUTSTANDING_LIST",
  "vidtable": "20342033315492",
  "table": "84214220504259//asset_cache",
  "search": "lt◼client",
  "hideZero": "TRUE",
  "groupField": "lv",
  "itemField": "ii",
  "qtyField": "qt",
  "condField": "cd",
  "ageField": "t",
  "customerTable": "84214220504259//stock_location",
  "customerKey": "lv",
  "nameField": "ln",
  "typeField": "ty",
  "itemTable": "84214220504259//item",
  "itemKey": "ii",
  "itemNameField": "in",
  "itemCatField": "ic",
  "dangerAge": 30,
  "warnAge": 14,
  "itemIconMap": "galon◼💧◼blue★returnable12◼🛢️◼red★returnable55◼🛢️◼amber",
  "title": "Outstanding Customer",
  "subtitle": "Saldo pinjaman per customer",
  "text": "total di luar◆pcs pinjam◆customer punya outstanding◆tertua◆hari",
  "detailText": "Rincian per jenis◆nyangkut◆total pinjam◆pcs",
  "emptyText": "Belum ada customer dengan outstanding",
  "doctrineText": "Outstanding = aset dipinjam & belum kembali ...",
  "closeText": "Tutup"
}
```

## Data Source

- `asset_cache` rows filtered by `search` (default `lt◼client`)
- Joined with `stock_location` (customer name + type) and `item` (name + category)
- All via `subscribeToMapCollection` (VID-scoped codes)

## Aggregation

Pure function `groupCustomerOutstanding()` (top-level, testable):
1. Group by `groupField` (customer)
2. Within each, group by `itemField` (item), SUM `qtyField` across all conditions
3. Aging = max(now - ageField) per item
4. Sort customers by total desc
5. hideZero drops 0-balance items/customers

## Chip Accent Colors

Per-item chips are colored by category. Config: `itemIconMap` with optional
3rd segment = accent slot name (`key◼emoji◼slot`). No slot = deterministic
category-based assignment via `ChipAccent.forCategory()`. Slot palette:
blue, red, amber, green, violet, teal, slate (fallback).

## Color Sourcing

Zero inline hex. All colors from `AdminTierColors.*` constants (matching
sibling `admin_outstanding_list.dart`) plus `Colors.white` for card
backgrounds.

## State Hygiene

Per-screen search text in `static Map<String, String> _searchText`, cleared
via `clearState(scrName)` called from `buildPage` in `ui_component.dart`.
NOT cleared in `dispose()` (linkElement caching prevents reliable dispose).

## Notes

- `condField` is INERT in v1: parsed for config completeness but not read
  by the aggregation function (sum aggregates ALL conditions)

## Interactions

- Search: client-side name filter (case-insensitive contains)
- Tap card: `showModalBottomSheet` with per-item breakdown, doctrine note, Tutup

## See Also

- `admin_outstanding_list.dart` — compact Admin H1 priority-action (same data source, different UX)
- `inventory_bucket_card.dart` — vehicle inventory card (similar asset_cache aggregation)
- `vehicle_cargo_summary.dart` — vehicle cargo card (similar pattern)
