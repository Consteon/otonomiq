# RouteProgressHeader

Driver identity header for the DriverHome screen (P4). Displays avatar, driver name, vehicle plate, and a logout button.

- **File:** [lib/widget/route_progress_header.dart](../../lib/widget/route_progress_header.dart)
- **Class:** `RouteProgressHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Shows driver identity (from workforce Firestore subcollection) and publishes `(VEHICLEID)` into DriverHomeState for downstream gate widgets. Always visible (no gate).

## Signature / Constructor

```dart
RouteProgressHeader({
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
| `type` | String | yes | `"ROUTE_PROGRESS_HEADER"` |
| `variant` | String | no | `"identityOnly"` (no progress bar) |
| `table` | String | yes | `"<docId>//workforce"` — workforce subcollection |
| `vidtable` | String | yes | App VID for Firestore path |
| `search` | String | yes | `"VID◼(DRIVERVID)"` — filter workforce by driver VID |
| `logoutRoute` | String | no | Route for logout button (e.g. `pauseConfirm`) |
| `text` | String | yes | `◆`-delimited 11 slots |

## Lifecycle

1. `initState` → parse text, subscribe to workforce mapCollection
2. `build` (Obx) → find driver doc, publish vehicleId (deferred to a
   `WidgetsBinding.addPostFrameCallback` so a mounted dependent Obx never reads
   the Rx mid-build), render header
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## Token resolution

`(DRIVERVID)` → `transactionStore.state.screenTx['#has_user_login']` (set by the
scanner before route navigation). The header reads this directly to find the
driver's workforce doc; from that doc it publishes `vv` → `(VEHICLEID)`.

## See Also

- `PreconditionGateCard` — consumes the `(VEHICLEID)` token this widget publishes
- `DriverHomeState` (`driver_home_support.dart`) — shared state holder
