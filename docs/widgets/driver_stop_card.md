# DriverStopCard

Stop list + progress card for DriverHome (P4). Dual-mode: locked preview (pending) or active list with progress bar (confirmed).

- **File:** [lib/widget/driver_stop_card.dart](../../lib/widget/driver_stop_card.dart)
- **Class:** `DriverStopCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Renders the driver's today-route as a stop list. In pending mode, shows a
locked preview with numbered stops (not tappable). In confirmed mode, shows
a progress bar, per-stop status badges (SELESAI/GAGAL/LANJUT/KIRIM/AMBIL),
active-row highlight, and a CTA to the taskFeed screen.

Uses `computeStopProgress` from `driver_home_support.dart` for the
tst-to-status mapping and closed/total/allClosed computation.

When `rejectRoute` is set, the locked preview gains per-row "Tolak" buttons
(amber outline) for non-completed stops, a "Selesai" chip for completed ones,
and a footnote at card bottom. Tapping Tolak dispatches `#REJECT_TASK` and
navigates to the reject sheet.

When `excludeStatus` is set, tasks whose raw `tst` field matches are dropped
from both the rendered list and the "N tujuan" count. It defaults to
`load_rejected` (via `kDefaultExcludeStatus`): an absent or empty
`excludeStatus` triggers that default, so `load_rejected` tasks are excluded
unless a tenant explicitly overrides the field. This keeps the stop-card
progress in sync with NAV_ACTION_CARD's `allClosed`.

## Signature / Constructor

```dart
DriverStopCard({
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
| `type` | String | yes | `"DRIVER_STOP_CARD"` |
| `variant` | String | no | `"preview"` |
| `table` | String | yes | `"<docId>//task"` |
| `search` | String | yes | `"vv◼(VEHICLEID)⭘tdt◼(TODAY)"` |
| `vidtable` | String | yes | App VID for Firestore path |
| `navState` | String | no | Forward-compat metadata (e.g. `"assigned"`) |
| `route` | String | no | Route for CTA button (e.g. `taskFeed`) |
| `rejectRoute` | String | no | Route for reject-task sheet (e.g. `rejectTask`). When absent, Tolak buttons are hidden (backward compat). |
| `taskIdField` | String | no | Field on task row for reject VID (default `tnm`) |
| `excludeStatus` | String | no | Raw `tst` value to exclude from list + count (e.g. `"load_rejected"`). Default: `load_rejected` (via `kDefaultExcludeStatus`). Empty string from server JSON triggers the default, not "no exclusion". Compares raw tst, NOT stopStatusOf. Mirrors PRECONDITION_GATE_CARD excludeStatus. |
| `text` | String | yes | diamond-delimited 20 slots (18 original + 2 reject) |

## Stop status mapping (SINGLE source: `driver_home_support.dart`)

| `tst` value | Display | Badge color | Closed? |
|---|---|---|---|
| `done` | SELESAI | green | yes |
| `failed` | GAGAL | amber | yes |
| `active` | LANJUT | indigo | no |
| other/absent | KIRIM/AMBIL | gray | no |

## Lifecycle

1. `initState` -> parse text, subscribe to task mapCollection
2. `build` (Obx) -> gate check, filter stops, compute progress, render mode
3. Cleared by `clearDriverHomeState(scrName)` in `buildPage`

## See Also

- `NavActionCard` -- reads the same `allClosed` from `computeStopProgress`
- `PreconditionGateCard` -- publishes `confirmed` state
- `DriverHomeState` (`driver_home_support.dart`) -- shared state holder
