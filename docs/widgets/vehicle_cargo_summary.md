# VehicleCargoSummary

Intro paragraph with bold plate + per-item "Sisa di Kendaraan" cargo card for
P12 ReturnVehicle.

- **File:** [lib/widget/vehicle_cargo_summary.dart](../../lib/widget/vehicle_cargo_summary.dart)
- **Class:** `VehicleCargoSummary` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Display widget for the P12 ReturnVehicle page. Shows an intro paragraph
(with the vehicle plate bolded inline) and a white rounded card listing
per-item cargo quantities (grouped by item, with isi/kosong sub-row per item).

Also serves as the **vehicleId publisher** for P12 -- P12 has no other
publisher header, so this widget derives the vehicle doc from
stock_location and publishes `lv` into DriverHomeState.vehicleId.

## Signature / Constructor

```dart
VehicleCargoSummary({
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
| `type` | `String` | `"VEHICLE_CARGO_SUMMARY"` |
| `vidtable` | `String` | Firestore container VID (`20342033315492`) |
| `vehicleTable` | `String` | stock_location table path (`84214220504259//stock_location`) |
| `plateField` | `String` | Field for plate in vehicle doc (default `ln`) |
| `cacheTable` | `String` | asset_cache table path (`84214220504259//asset_cache`) |
| `cacheSearch` | `String` | Search condition for asset_cache (e.g. `lv◼{vehicleId}`) |
| `itemTable` | `String` | item master table path (`84214220504259//item`) -- for name FK resolution |
| `text` | `String` | Diamond-separated: 6 segments (introA, introB, cardTitle, fullLabel, emptyLabel, emptyState) |

### Text slots

| Index | Meaning | Default |
|-------|---------|---------|
| 0 | introA | `'Serahkan kendaraan'` |
| 1 | introB | `''` |
| 2 | cardTitle | `'Sisa di Kendaraan'` |
| 3 | fullLabel | `'isi'` |
| 4 | emptyLabel | `'kosong'` |
| 5 | emptyState | `'Tidak ada sisa muatan'` |

## State / Bloc / Dependencies

- **GetX (RxMap):** reads `mapTableContent` for stock_location, asset_cache, and item docs.
- **DriverHomeState:** publishes `vehicleId` via post-frame callback.
- **Redux:** reads `#has_user_login` for driverVid (read-only, no dispatch).
- **Shared helpers (`driver_home_support.dart`):**
  - `buildItemNameMap` -- resolves `ii` -> `in` from the item master collection.
  - `computePerItemCargoRows` -- the pure aggregation core. Groups asset_cache
    docs by `ii`, sums `qt` per `cd`, resolves names, 0-fills missing
    conditions, and returns a sorted `List<CargoItemRow>`. The widget calls
    this helper; the aggregation is NOT re-implemented inside the widget
    (so it is directly unit-testable).
- No txfController, no saveSend, no history writes.

## Important Behavior

- vehicleId is published via post-frame callback with mounted + equality
  guard (mirrors vehicle_custody_header._publishVehicleId).
- asset_cache docs are grouped by `ii` (item id), quantity summed per `cd`
  (condition: `full`/`empty`). Each distinct item renders as a name header
  line + a sub-row showing isi qty and kosong qty. Missing conditions are 0-filled.
- Item names are resolved from the item master collection (`itemTable` subscription).
  When `itemTable` is absent or `ii` is not found (or its name is empty), the
  raw `ii` string is shown (degrade-safe).
- Items are sorted by resolved name ascending, tiebreak by raw `ii`.
- Empty state (no items for this vehicle): muted italic text from slot 5.
- Plate is bolded in the intro text via `parseInlineEmphasis` (`**plate**` markers).
- The spec's `vehicleSearch` re-lookup is collapsed: plate is read directly
  from the derived vehicle doc (one subscription for stock_location, not two).

## See Also

- [vehicle_custody_header.md](vehicle_custody_header.md) -- P5 header that also publishes vehicleId
- [route_feed_header.md](route_feed_header.md) -- P10 header with vehicleId publisher
- [inventory_bucket_card.md](inventory_bucket_card.md) -- P4 card using same asset_cache + item pattern
- [notice_bar.md](notice_bar.md) -- source of `parseInlineEmphasis`
