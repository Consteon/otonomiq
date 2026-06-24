# NavActionCard

Return-vehicle CTA card for DriverHome (P4). HIDDEN when pending; confirmed shows muted or active based on all-stops-closed.

- **File:** [lib/widget/nav_action_card.dart](../../lib/widget/nav_action_card.dart)
- **Class:** `NavActionCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

The final CTA on the DriverHome screen. HIDDEN when pending (`!confirmed`).
When confirmed, the card shows with a "Return Kendaraan" button that is
enabled only when all stops are closed (done or failed). Uses
`computeStopProgress` from `driver_home_support.dart` to derive `allClosed`.

## Signature / Constructor

```dart
NavActionCard({
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
| `type` | String | yes | `"NAV_ACTION_CARD"` |
| `table` | String | yes | `"<docId>//task"` |
| `search` | String | yes | `"vv◼(VEHICLEID)⭘tdt◼(TODAY)"` |
| `vidtable` | String | yes | App VID for Firestore path |
| `route` | String | yes | Route for CTA (e.g. `returnVehicle`) |
| `ready` | String | no | `"{allClosed}"` -- forward-compat metadata |
| `text` | String | yes | diamond-delimited 3 slots |

## Lifecycle

1. `initState` -> parse text, subscribe to task mapCollection
2. `build` (Obx) -> gate check (confirmed?), compute allClosed, render
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## See Also

- `DriverStopCard` -- uses the same `computeStopProgress`
- `PreconditionGateCard` -- publishes `confirmed` state
- `DriverHomeState` (`driver_home_support.dart`) -- shared state holder
