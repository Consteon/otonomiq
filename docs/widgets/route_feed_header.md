# RouteFeedHeader

Sticky 3-row header for the P10 TaskFeed screen: driver identity, route progress bar, and drop/pickup grand totals.

- **File:** [lib/widget/route_feed_header.dart](../../lib/widget/route_feed_header.dart)
- **Class:** `RouteFeedHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** TBD

## Purpose

Replaces the abandoned `routeProgressHeaderFull` type. Renders driver name, plate, stop progress (completed/total + failed), and drop/pickup aggregate stats. Acts as the **vehicleId publisher** for P10 -- downstream widgets' `{vehicleId}` searches fail without it.

## Signature / Constructor

RouteFeedHeader({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad, tPad, rPad, bPad,
})

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | Firestore container VID (`20342033315492`) |
| `workforceTable` | `String` | Workforce table path (e.g. `84214220504259//workforce`) |
| `workforceSearch` | `String` | Workforce search (e.g. `VID◼{driverVid}`) |
| `nameField` | `String` | Driver name field (default `n`) |
| `vehicleTable` | `String` | Stock_location table path |
| `vehicleSearch` | `String` | Vehicle search (not used; vehicleId derived by code scan) |
| `plateField` | `String` | Plate field (default `ln`) |
| `taskTable` | `String` | Task table path |
| `taskSearch` | `String` | Task filter (e.g. `vv◼{vehicleId}⭘tdt◼{today}`) |
| `stateField` | `String` | Task state field (default `tst`) |
| `itemsField` | `String` | Nested items array field (default `it`) |
| `dropField` | `String` | Planned drop qty field (default `pd`) |
| `pickupField` | `String` | Planned pickup qty field (default `pp`) |
| `actualDropField` | `String` | Actual drop qty field (default `ad`) |
| `actualPickupField` | `String` | Actual pickup qty field (default `ap`) |
| `backRoute` | `String` | Back navigation route |
| `text` | `String` | Diamond-separated labels (5 segments) |

## State / Dependencies

- **GetX Obx** for reactive mapTableContent reads.
- **DriverHomeState** (driver_home_support.dart) for vehicleId publish.
- **Redux transactionStore** for `#has_user_login` (driverVid).

## Important Behavior

- Publishes vehicleId via post-frame callback (never during build).
- `load_rejected` tasks are unconditionally excluded from stop count, progress bar, and Drop/Pickup grand totals. The exclusion is applied in `_getFilteredTasks()` via `excludeByStatus(filtered, kDefaultExcludeStatus, statusField: stateField)`, comparing the raw state field (not `stopStatusOf`). No component config key controls this. This is deliberately unconditional, unlike the sibling `driver_stop_card` / `nav_action_card` widgets which use a config-fallback shape.
- Renders title unconditionally; a blank top bar = header missing from server JSON.
- Back button: `routeStack.push(backRoute)` then `gotoRoute(backRoute)`.

## See Also

- [route_progress_header.md](route_progress_header.md) -- P4 sibling header
- [task_feed_list.md](task_feed_list.md) -- companion list widget
