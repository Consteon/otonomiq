# custody_event_submit

| field | value |
|---|---|
| file | `lib/widget/custody_event_submit.dart` |
| dispatch | `custody_event_submit` |
| status | draft |

## Purpose

Pre-resolving submit button for custody outcome pages. `saveSend` now
resolves shared `{curly}` tokens generically via `resolveDriverCurlyTokens`;
this widget pre-resolves the widget-local `{cnm}` token (which requires
checkDoc access unavailable in `saveSend`) and the shared tokens
(`{vehicleId}`, `{today}`, `{driverVid}`, `{driverName}`) by delegating to
the same shared resolver before calling `saveSend`.

Operates in two modes:
- **Ungated (P7):** always enabled, updateEventRow only.
- **Gated (P8):** disabled until note >= 10 chars AND photo attached.

## Reactivity

- **Note:** `TextEditingController.addListener` -> `setState` (attached via
  `addPostFrameCallback` in `initState`, disposed in `dispose`).
- **Photo:** `GetBuilder<GeneralGetXController>(id: photoWidgetId)` where
  `photoWidgetId = "$scrName.$photoPos"`. Rebuilds when `OtqGetImages2` calls
  `GeneralGetXController.to.redraw()` or `deleteWidgetAt()`.
- NO Obx, NO timer, NO Rx mutation in build.

## Component JSON

| key | type | required | notes |
|---|---|---|---|
| `table` | string | yes | vehicle_check path (for cnm read) |
| `search` | string | yes | opening doc search |
| `updateEventRow` | string | yes | DSL with curly tokens |
| `addToEvent` | string | no | DSL with curly tokens (P8) |
| `route` | string | yes | nav target after submit |
| `text` | string | no | [0] enabled label, [1] disabled label, [2] hint |
| `gateNotePosition` | int | no | txf position for note gate |
| `gatePhotoPosition` | int | no | get_images position for photo gate |
| `minNoteLength` | int | no | default 10 |
| `cnmField` | string | no | default `cnm` |
| `vidtable` | string | no | explicit appVid |
| `com` | string | no | tenant container |
| `chain` | object | no | DO_DIALOG (or DO_BOTTOM_SHEET) shown after submit instead of direct route nav |

## Subscriptions

- `vehicle_check` via `table` (to read cnm from opening doc at submit time)

## Token Resolution (pre-resolve before saveSend)

| Token | Source |
|---|---|
| `{vehicleId}` | `DriverHomeState.vehicleId` |
| `{today}` | `todayEpochMidnightWib()` |
| `{driverVid}` | `screenTx['#has_user_login']` |
| `{driverName}` | `DriverHomeState.driverName` |
| `{cnm}` | `checkDoc['cnm']` (from own subscription) |
| `{activeTaskVid}` | `screenTx['#ACTIVE_TASK']` (via delegation to `resolveDriverCurlyTokens`) |
| `{tnm}` | `screenTx['#ACTIVE_TASK']` (alias of `{activeTaskVid}`; task doc id per spec section 4) |
| `{rejectTaskVid}` | `screenTx['#REJECT_TASK']` (via delegation to `resolveDriverCurlyTokens`) |

## See Also

- `custody_count_submit.md` (P6 submit, similar pattern)
- `custody_step_header.md` (vehicleId + driverName publisher)
