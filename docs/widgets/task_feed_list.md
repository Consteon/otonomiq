# TaskFeedList

Grouped task card list for the P10 TaskFeed screen with per-state sections and allDone footer.

- **File:** [lib/widget/task_feed_list.dart](../../lib/widget/task_feed_list.dart)
- **Class:** `TaskFeedList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** TBD

## Purpose

Replaces the abandoned `driverStopCardFull` type. Groups task docs by state (assigned+on_delivery / failed / completed), renders per-card layout with avatar, customer, state chip, drop/pickup badges, and state-specific footer. Shows allDone banner when all tasks are completed or failed.

## Signature / Constructor

TaskFeedList({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad, tPad, rPad, bPad,
})

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | Firestore container VID (`20342033315492`) |
| `table` | `String` | Task table path (e.g. `84214220504259//task`) |
| `search` | `String` | Task filter (e.g. `vv◼{vehicleId}⭘tdt◼{today}`) |
| `groupField` | `String` | State field for grouping (default `tst`) |
| `idField` | `String` | Task ID field (default `tnm`) |
| `titleField` | `String` | Customer name field (default `kn`) |
| `addressField` | `String` | Address field (default `al`) |
| `typeField` | `String` | Task type field (default `tty`) |
| `itemsField` | `String` | Items array field (default `it`) |
| `dropField` | `String` | Planned drop field (default `pd`) |
| `pickupField` | `String` | Planned pickup field (default `pp`) |
| `actualDropField` | `String` | Actual drop field (default `ad`) |
| `actualPickupField` | `String` | Actual pickup field (default `ap`) |
| `route` | `String` | Card-tap navigation route (DeliveryWorkspace) |
| `returnRoute` | `String` | allDone button route (ReturnVehicle) |
| `text` | `String` | Diamond-separated labels (15 segments) |

## State / Dependencies

- **GetX Obx** for reactive mapTableContent reads.
- **DriverHomeState** (driver_home_support.dart) for vehicleId dependency.
- **stopStatusOf** (driver_home_support.dart) for state normalization.

## Important Behavior

- `on_delivery` tasks group with `assigned` (still-open).
- `allDone` = pending group empty AND tasks non-empty.
- Card tap on assigned/on_delivery: `routeStack.push(route)` then `gotoRoute(route)`.
- allDone button: `routeStack.push(returnRoute)` then `gotoRoute(returnRoute)`.
- Dead routes degrade gracefully (silent push+goto, no snackbar).
- Distance line: HIDDEN (no GPS).
- completedAt time: HIDDEN (no tce field).
- customerConfirmed: HIDDEN (P11 deferred).
- stopNumber: 1-based global doc-order index on assigned/on_delivery only.

## See Also

- [route_feed_header.md](route_feed_header.md) -- companion header widget
- [driver_stop_card.md](driver_stop_card.md) -- P4 sibling card
