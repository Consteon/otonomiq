# CustodyCountList

Blind stepper list for P6 CustodyCount -- one row per item with -/value/+ controls.

- **File:** [lib/widget/custody_count_list.dart](../../lib/widget/custody_count_list.dart)
- **Class:** `CustodyCountList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Renders the driver's blind count interface. Subscribes vehicle_check for the
opening doc's `ie[]` manifest, JOINs each item to the item collection for
name and category, filters by category (returnable/consumable), and renders
the item name (+ optional category chip) above a stepper per entry. The
warehouse qty (`ie[].qt`) is hidden when `blind == TRUE`.

The per-row compact inline stepper has been replaced with the shared
`CustodyStepper` widget (`lib/widget/custody_stepper.dart`) in NEUTRAL mode
(white frame, slate number) -- a full-width framed layout (`- | big centered
number | +`). `CustodyStepper` is an INTERNAL widget shared with
`CustodyReveal`; it is NOT a dispatched SDUI type (no barrel export, no
dispatch branch).

Driver-entered counts are held in a per-scrName static map keyed by `ii__cd`.
Future P7/P8 pages will read this store to build the `ip[]` physical count
array. The store is cleared on route change.

## Recount seeding

When a driver returns to P6 via CustodyReveal's "Hitung Ulang" button, counts
are seeded from the previous physical count (`ip[]`) on the opening check doc
rather than reset to 0 wholesale. `CustodyCountList.computeRecountSeeds` applies
a three-way rule per `ii__cd` key:

- `ip[]` absent or empty -> every row starts at 0 (first-time blind count,
  byte-identical to the original behavior).
- `ip.qt == ie.qt` -> the row keeps its previous count (KEEP; the driver does
  not recount it).
- otherwise (mismatch, or the key is absent from `ip[]`) -> the row seeds 0 and
  shows the amber `⚠ Perlu hitung ulang` status line (CLEAR; the driver
  recounts it).

This applies to the default P6 `ie[]` path only. The `aggregate` (O1) and
`source:asset_cache` (C1) variants never call `_buildRows` and are completely
unaffected -- a tenant running those variants sees no change whatsoever.

## Signature / Constructor

```dart
CustodyCountList({
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
| `table` | `String` | Table path for vehicle_check (e.g. `84214220504259//vehicle_check`) |
| `search` | `String` | Multi-clause AND filter (e.g. `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}`) |
| `itemsField` | `String` | Field on check doc holding item array (default `ie`) |
| `joinTable` | `String` | Table path for item collection (e.g. `84214220504259//item`) |
| `joinKey` | `String` | Field to JOIN ie[].ii -> item doc (default `ii`) |
| `labelField` | `String` | Field on item doc for display name (default `in`) |
| `filter` | `String` | Category filter: `fieldCode◼value` (e.g. `ic◼returnable`) |
| `blind` | `String` | `TRUE` to hide ie[].qt (warehouse expected qty) |
| `writeField` | `String` | Target field for driver counts (default `ip`; write is P7/P8 scope) |
| `actualField` | `String` | Field on the check doc holding the PREVIOUS driver counts, used to seed a recount (default `ip`) |
| `text` | `String` | Currently unused (labels come from data, not text slots) |
| `vidtable` | `String?` | Container VID for the vehicle_check + item subscriptions (applicationTableVid, e.g. `20342033315492`); read first by `resolveAppVid` |

## Static API

| Method | Description |
|---|---|
| `CustodyCountList.getCountMap(scrName)` | Get or create the count map for a screen |
| `CustodyCountList.clearCountStore(scrName)` | Clear count store on route change |
| `CustodyCountList.computeRecountSeeds(ieEntries, ipEntries)` | Compute recount seed values: matched rows keep `ip.qt`, mismatched/absent rows seed 0 (see Recount seeding) |

## Data Dependencies

- **vehicle_check** (subscribed): opening doc with `ie[]` manifest
- **item** (subscribed): name (`in`) + category (`ic`) JOIN
- **DriverHomeState.vehicleId** (reactive): search resolves once header publishes

## See Also

- [stepper_widget](../../docs/stepper-widget-dev-spec%20(1).md) -- visual reference for stepper controls
- [vehicle_custody_header.md](vehicle_custody_header.md) -- P5 header (companion widget)
