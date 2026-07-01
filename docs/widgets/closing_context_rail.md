# closing_context_rail

Green-tinted single-line context strip for C1 WarehouseClosingCheck.

- **File:** [lib/widget/closing_context_rail.dart](../../lib/widget/closing_context_rail.dart)
- **Class:** `ClosingContextRail` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in:** `warehouse-closing-check-c1`

## Purpose

Renders a compact, green-tinted strip at the top of the C1 closing-check
screen. Displays the driver name (from the opening `vehicle_check` doc) and a
category summary (N returnable, M consumable) computed from `asset_cache` docs
joined with `item` docs.

Pure display: no `txfController`, no `saveSend`, no history queue, no mutable
per-`scrName` state. Renders its chrome unconditionally (driver shows `-` when
the opening doc / driver name is not found).

## Signature / Constructor

```dart
ClosingContextRail({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

## Config fields

| Field | Type | Default | Description |
|---|---|---|---|
| `table` | string | -- | asset_cache collection path (e.g. `84214220504259//asset_cache`) |
| `search` | string | -- | Filter clause for asset_cache (e.g. `lv◼{vehicleId}`) |
| `checkTable` | string | -- | vehicle_check collection path (for opening-doc driver name) |
| `checkSearch` | string | -- | Search clause for the opening doc |
| `joinTable` | string | -- | item collection path (for `ic` category) |
| `joinKey` | string | `ii` | Item id field |
| `catField` | string | `ic` | Item category field |
| `driverField` | string | `cn` | Opening-doc field holding the driver name |
| `text` | diamond | -- | Text slots (currently unused) |

## Text slots

None currently used (all labels are hardcoded for v1).

## State

- No `txfController`, no `saveSend`, no history.
- Pure display; no mutable per-`scrName` state.
- `Obx` on `DriverHomeState.vehicleId` + the `mapTableContent` reactive maps
  (asset_cache / vehicle_check / item subscriptions).

## Data flow

1. `initState` subscribes (via `subscribeToMapCollection`) to asset_cache,
   vehicle_check, and item collections derived from the config paths.
2. Driver name: filter the vehicle_check docs by `checkSearch`
   (`filterDriverHomeDocs`), read `driverField` from the first match; `-` when
   none.
3. Category summary: filter asset_cache docs by `search`, JOIN each `ii` to the
   item collection via `buildItemDetailMap`, count DISTINCT `ii` per `ic`
   (`returnable` / `consumable`).

## See Also

- [custody_count_list.md](custody_count_list.md) (C1 count-list source)
- [custody_count_submit.md](custody_count_submit.md) (C1 submit variant)
