# AdminUpcomingTaskList

"AKAN DATANG" stat-list for Admin Home (H1): today's scheduled task cards with item roll-up and an inline "+ Tugaskan Kendaraan" launcher for unassigned tasks.

- **File:** [lib/widget/admin_upcoming_task_list.dart](../../lib/widget/admin_upcoming_task_list.dart)
- **Class:** `AdminUpcomingTaskList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** Admin Home R2 (slice 2)
- **Dispatch type:** `ADMIN_UPCOMING_TASK_LIST` (matched lowercase as `adminupcomingtasklist`)

## Purpose

Shows the day's planned-but-not-yet-running tasks. Per task: customer name, a time pill, a "Drop N · Pickup N" roll-up from the task's `it[]` array, and either the assigned vehicle's plate or an inline blue "+ Tugaskan Kendaraan" button. The button reuses the shared [VehiclePickerSheet](admin_vehicle_picker_sheet.md) in `assign` mode (online-only write via `writeNativeFields`).

Read-only except the inline assign action. Collapses to `SizedBox.shrink()` when there are no upcoming tasks.

## Signature / Constructor

```dart
AdminUpcomingTaskList({
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
| `vidtable` | `String` | appVid, resolved via `resolveAppVid` |
| `table` | `String` | `task` table path `tableDocId//task` (this is the primary collection) |
| `vehicleTable` | `String` | `stock_location` table path (plate lookup, `lt=vehicle`) |
| `text` | `String` | `◆`-separated label slots (see below) |

### `text` slots (◆-separated, length-guarded via `_t(i, def)`)

| Index | Default | Meaning |
|---|---|---|
| `[0]` | `AKAN DATANG` | section caps header (UPPERCASE) |
| `[1]` | `Drop` | drop label in the item roll-up |
| `[2]` | `Pickup` | pickup label in the item roll-up |
| `[3]` | `+ Tugaskan Kendaraan` | inline assign-button label |
| `[4]` | `Pilih Kendaraan` | VehiclePickerSheet title (assign mode) |
| `[5]` | `Konfirmasi` | VehiclePickerSheet confirm label |
| `[6]` | `task aktif` | per-vehicle "N task aktif" suffix in the sheet |
| `[7]` | `Perlu koneksi internet` | offline error (write attempted offline) |
| `[8]` | `Gagal menyimpan` | write-failure error |

### Config params (R4)

All optional; absent = the documented default (backward-compatible). Field-name keys are read in `_parseConfig()` and used in `_buildCard`/`build`. `updateEventRow` is the DSL template threaded to `VehiclePickerSheet` (resolved with `{taskVid}`/`{vehicleId}` at confirm time, executed via `executeUpdateEventRow`).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `titleField` | `String` | `kn` | customer-name field (card title) |
| `schedField` | `String` | `tdt` | schedule date field (time pill + today filter) |
| `summaryField` | `String` | `it` | items-array field for the Drop/Pickup roll-up (`summarizeItems`) |
| `assignField` | `String` | `vv` | assigned-vehicle FK field on the task |
| `plateField` | `String` | `vv` | task FK used to look up the plate in `stock_location` (same as `assignField` in H1; kept separate for cases where the lookup FK differs) |
| `vehicleNameField` | `String` | `ln` | `stock_location` plate/name field |
| `updateEventRow` | `String` | `''` | updateEventRow DSL template passed to the vehiclePicker (`executeUpdateEventRow`, online-only). Spec(2): `84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{taskVid}⭘vv◼{vehicleId}`. |
| `emptyText` | `String` | `'Tidak ada order terjadwal hari ini'` | Text rendered when the upcoming list is empty (spec section 5.2). Config-driven; the section header always renders. |

Note: the `tst=='assigned'` status filter stays hardcoded — it is part of the UPCOMING widget's identity (vs the configurable display fields), confirmed by spec(2)'s `search` key (`tst◼assigned⭘tdt◼{today}`).

## Data sources / derive

- **Filter:** `task` docs where `tst == 'assigned'` AND `tdt == todayEpochMidnightWib()` (the `assigned`-only test also excludes `load_rejected`).
- **Time pill:** `formatTimePill(task['tdt'])` — HH:mm in WIB (UTC+7); empty if `tdt` is null/0/non-numeric.
- **Item roll-up:** `summarizeItems(task['it'], dropLabel, pickupLabel)` — sums `pd` (drop) and `pp` (pickup) across the `it[]` array → "Drop N · Pickup N"; empty when both sums are 0 or `it` is not a List.
- **Plate:** `stock_location` doc (indexed by `lv`, `lt=vehicle`) matching the task `vv`; reads `ln`. When `vv` is empty/unmatched, the inline assign button is shown instead.
- **Assign write:** `_onAssignTap(tnm)` → `VehiclePickerSheet(mode: 'assign', taskVid: tnm, ...)` → `writeNativeFields` patches `{vv: <selected lv>}` on the task doc (search `tnm◼{taskVid}`). Online-only (custody precedent); offline → snackbar.

## State / Dependencies

- **Subscriptions:** `subscribeToMapCollection` into `mapTableContent`; typed reads via `List<Map<String,dynamic>>.from(...)`.
- **Pure helpers:** `formatTimePill`, `summarizeItems` (admin_home_support.dart).
- **Shared widget:** [VehiclePickerSheet](admin_vehicle_picker_sheet.md).
- **Side effects:** the assign action writes one task field via `writeNativeFields` (bypasses the offline history queue; online-only).

## Important Behavior

- Empty upcoming set → section header ("AKAN DATANG") + muted `emptyText` (config-driven, default "Tidak ada order terjadwal hari ini"). The section is never hidden (spec section 5.2).
- The inline assign button has a `minHeight: 44` constraint (≥44pt touch target per the design spec).
- `formatTimePill` assumes `tdt` is epoch-ms; an epoch-midnight value renders "07:00" (WIB midnight) — degrade-safe.

## See Also

- [admin_vehicle_picker_sheet.md](admin_vehicle_picker_sheet.md) — the shared assign/reassign sheet this widget launches.
- [admin_active_trip_list.md](admin_active_trip_list.md) — "BERJALAN" sibling.
- [coordination_signal_list.md](coordination_signal_list.md) — the other launcher of VehiclePickerSheet.
