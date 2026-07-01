# AdminActiveTripList

"BERJALAN" stat-list for Admin Home (H1): read-only cards for vehicles currently on confirmed trips today (plate, driver, stop progress, BERJALAN badge).

- **File:** [lib/widget/admin_active_trip_list.dart](../../lib/widget/admin_active_trip_list.dart)
- **Class:** `AdminActiveTripList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** Admin Home R2 (slice 2)
- **Dispatch type:** `ADMIN_ACTIVE_TRIP_LIST` (matched lowercase as `adminactivetriplist`)

## Purpose

Surfaces the "what's on the road right now" panel of the Admin coordination screen. It cross-collection-derives (does NOT use `list_statistic_card`, which is single-collection) from `vehicle_check` + `task` + `stock_location` + `workforce` to show, per active vehicle: the plate, the driver name, the completed/total stop count, and the last completed stop name. Mirrors the `task_feed_list` / `route_feed_header` subscribe-in-`initState` → typed-read-in-`Obx` → derive pattern.

Read-only — no write, no navigation. Collapses to `SizedBox.shrink()` when there are no active trips.

## Signature / Constructor

```dart
AdminActiveTripList({
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
| `vidtable` | `String` | appVid (driver container), e.g. `20342033315492`; resolved via `resolveAppVid` |
| `checkTable` | `String` | `vehicle_check` table path `tableDocId//vehicle_check` |
| `taskTable` | `String` | `task` table path `tableDocId//task` |
| `vehicleTable` | `String` | `stock_location` table path (plate lookup, `lt=vehicle`) |
| `workforceTable` | `String` | `workforce` table path (driver-name lookup) |
| `text` | `String` | `◆`-separated label slots (see below) |

### `text` slots (◆-separated, length-guarded via `_t(i, def)`)

| Index | Default | Meaning |
|---|---|---|
| `[0]` | `BERJALAN` | section caps header (rendered UPPERCASE) |
| `[1]` | `BERJALAN` | per-card badge label |
| `[2]` | `Stop` | stop-count prefix |
| `[3]` | `dari` | stop-count separator ("x dari y") |
| `[4]` | `selesai` | last-completed-stop suffix |

### Config params (R3)

All optional; absent = current defaults (backward-compatible).

| Key | Default | Meaning |
|---|---|---|
| `vehicleNameField` | `'ln'` | field on the `stock_location` vehicle doc used as the plate title |
| `execField` | `'dv'` | field on the `stock_location` vehicle doc holding the driver FK |
| `nameField` | `'n'` | field on the `workforce` doc used as the driver name |

### Config params (R4)

All optional; absent = the documented default (backward-compatible). Read in `_parseConfig()` and used by the stop-progress aggregation. R4 switches stop progress from task-doc status counting (`computeAdminStopProgress`) to per-item `it[]` line counting via `progressFromItems`.

| Key | Default | Meaning |
|---|---|---|
| `itemsField` | `'it'` | field on each task holding the items array iterated for progress |
| `doneMarker` | `'ad,ap'` | comma-separated item field names; a line is "done" if ANY marker field is non-empty (e.g. `ad` actual-drop OR `ap` actual-pickup) |

Stop progress now aggregates `it[]` lines across all of the vehicle's tasks (excluding `tst=='load_rejected'`): `done` = lines with a non-empty marker field, `total` = total lines. **CF dependency:** until the Cloud Function that sets `ad`/`ap` on movement is deployed, this reads 0/0 (spec(2) §7 seed-sementara). `computeAdminStopProgress` remains defined in `admin_home_support.dart` but is no longer called from this widget.

## Data sources / derive

- **Active filter:** `vehicle_check` docs where `cst == 'custody_confirmed'` AND `cdt == todayEpochMidnightWib()`.
- **Plate:** `stock_location` doc (indexed by `lv`, `lt=vehicle`) matching the vehicle_check `vv`; reads `ln` (override: `vehicleNameField`).
- **Driver name:** `workforce` doc whose id (`vid`, fallback `lv`) equals the vehicle's `dv` field (override: `execField`); reads `n` (override: `nameField`). **JOIN-KEY ASSUMPTION** (best-guess, degrade-safe): if the tenant keys workforce differently from `stock_location.dv`, the lookup misses and the driver name is omitted — the subline degrades to stop-progress only. Not a guaranteed join.
- **Stop progress:** `computeAdminStopProgress(tasks, vv)` from `admin_home_support.dart` — completed = tasks with normalized status done/closed/completed; total = all non-`load_rejected` tasks for that vehicle.
- **Last stop:** `lastCompletedStopName(tasks, vv)` — `kn` of the done task with the highest `tce`.

## State / Dependencies

- **Subscriptions:** `subscribeToMapCollection` (idempotent per code) into `mapTableContent` (GetX `RxMap`), read typed via `List<Map<String,dynamic>>.from(mapTableContent[code] ?? const [])`.
- **Pure helpers:** `computeAdminStopProgress`, `lastCompletedStopName` (admin_home_support.dart). Named with the `Admin` prefix because `driver_home_support.dart` already exports a differently-shaped `StopProgress`/`computeStopProgress` via the `all_widget.dart` barrel.
- **Side effects:** none (read-only).

## Important Behavior

- Empty active set → `SizedBox.shrink()` (no blank frame). Per-screen reactivity comes from `Obx`; no per-scrName static store is used.
- Plate falls back to the raw `vv` id when no `stock_location.ln` is found.

## See Also

- [coordination_signal_list.md](coordination_signal_list.md) — the "Perlu Tindakan" sibling on the same screen.
- [admin_upcoming_task_list.md](admin_upcoming_task_list.md) — "AKAN DATANG" stat-list.
- [admin_outstanding_list.md](admin_outstanding_list.md) — "PRIORITAS PENGAMBILAN" stat-list.
