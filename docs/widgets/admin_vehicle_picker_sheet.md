# VehiclePickerSheet

Reusable bottom-sheet for assigning / reassigning a vehicle to a task. Extracted from `CoordinationSignalList` so it can be shared.

- **File:** [lib/widget/admin_vehicle_picker_sheet.dart](../../lib/widget/admin_vehicle_picker_sheet.dart)
- **Class:** `VehiclePickerSheet` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** Admin Home R2 (slice 2) — extracted from the private `_VehiclePickerSheet` of slice 1
- **Dispatch type:** NONE — this is launched imperatively via `showModalBottomSheet`, not a `build_display_component` branch.

## Purpose

A `DraggableScrollableSheet` listing the tenant's vehicles (`stock_location` where `lt == 'vehicle'`), each with its plate and a "N task aktif" count. The user taps one and confirms; the sheet writes the selection onto the target task via `writeNativeFields` (online-only, bypasses the offline history queue — custody precedent). It shows a spinner while writing and a result/offline snackbar.

Shared by:
- [CoordinationSignalList](coordination_signal_list.md) — `assign` (unassigned_vehicle) and `reassign` (task_returned) signal actions.
- [AdminUpcomingTaskList](admin_upcoming_task_list.md) — the inline "+ Tugaskan Kendaraan" button (`assign`).

## Signature / Constructor

```dart
VehiclePickerSheet({
  Key? key,
  required String mode,                 // 'assign' or 'reassign'
  required String taskVid,              // target task document id (tnm)
  required List<Map<String, dynamic>> stockLocations,
  required List<Map<String, dynamic>> tasks,
  required dynamic component,           // carries `table` (task path) + vidtable
  required String scrName,
  String titleAssign     = 'Pilih Kendaraan',
  String titleReassign   = 'Assign Ulang Kendaraan',
  String confirmLabel    = 'Konfirmasi',
  String activeTaskSuffix = 'task aktif',
  String offlineError    = 'Perlu koneksi internet',
  String writeFailError  = 'Gagal menyimpan',
})
```

### Parameters

| Param | Type | Description |
|---|---|---|
| `mode` | `String` | `'assign'` (patch `{vv}` only) or `'reassign'` (also resets `tst` → `'assigned'`) |
| `taskVid` | `String` | task `tnm`; the write searches `tnm◼{taskVid}` |
| `stockLocations` | `List<Map>` | snapshot of `stock_location` docs (caller passes the current `mapTableContent` value) |
| `tasks` | `List<Map>` | snapshot of `task` docs (for the per-vehicle "N task aktif" count) |
| `component` | `dynamic` | reads `table` (task path) and resolves appVid via `resolveAppVid` for the write path |
| `scrName` | `String` | screen name (passed through to `writeNativeFields` for token resolution) |
| `title*/confirmLabel/activeTaskSuffix/*Error` | `String` | label overrides (callers wire these from their own `text` slots) |

### Config params (R4)

R4 reverses the write from `writeNativeFields` to the spec(2) `updateEventRow` DSL via the new `executeUpdateEventRow` helper (`admin_home_support.dart`). The sheet now receives the DSL **template** from its caller and resolves `{taskVid}`/`{vehicleId}` tokens at confirm time; it no longer references `scrName` or `writeNativeFields`.

| Param | Type | Description |
|---|---|---|
| `updateEventRowDsl` | `String` (required) | the raw `component['updateEventRow']` DSL template, threaded from the caller (signal-list or upcoming). At confirm time the sheet calls `executeUpdateEventRow(rawDsl: updateEventRowDsl, tokens: {'{taskVid}': taskVid, '{vehicleId}': <selected lv>}, component: component)`. Spec(2): `84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{taskVid}⭘vv◼{vehicleId}⭘tst◼assigned`. |

`executeUpdateEventRow` mirrors `writeNativeFields`'s semantics (direct Firestore set-merge on the single search match, **online-only**, bypasses the offline history queue, returns `Future<bool>`) but parses the `updateEventRow` DSL: `autheniumDecode` → token replacement → `parseUpdateEventRow` → build path `MobileTable/<tablevid>/tables/<docId>/<sub>` → AND-query from `search` conditions → 0/1/>1 match guard → set-merge the body (`vv`, `tst`, …). An unresolved `{token}` short-circuits to `false`.

**Removed in R4:**
- `final String scrName;` field + `required this.scrName` constructor param + the `scrName:` argument to the old write (the constructor block / Parameters row / Usage example above still showing `scrName` are pre-R4 and superseded by this section).
- The direct `writeNativeFields` dependency (the function itself is NOT deleted — still used by other modules).

## Usage

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (_) => VehiclePickerSheet(
    mode: 'assign',
    taskVid: tnm,
    stockLocations: List<Map<String, dynamic>>.from(mapTableContent[slCode] ?? const []),
    tasks: List<Map<String, dynamic>>.from(mapTableContent[taskCode] ?? const []),
    component: component,
    scrName: scrName,
  ),
);
```

## State / Dependencies

- **Repository / write:** `writeNativeFields` (driver_home_support.dart) — builds the Firestore query from the task path + `tnm◼{taskVid}` search, merges the patch. Returns `bool`.
- **Connectivity:** `internetConnectionFlag` (global.dart) — on write failure, chooses `offlineError` vs `writeFailError`.
- **Local state:** `_selectedLv` (selected vehicle), `_writing` (in-flight guard; disables confirm + shows a spinner).
- **Active-task count:** counts `tasks` where `vv == lv` and `tst` ∈ {`assigned`, `on_delivery`}.

## Important Behavior

- The patch is `{vv: <selectedLv>}`; in `reassign` mode it also sets `tst: 'assigned'`.
- Write is **online-only** — there is no offline-queue path; an offline attempt surfaces `offlineError`.
- On success: pops the sheet and shows a "Berhasil" snackbar; guards `mounted` before `setState`/navigation.
- The confirm button is full-width with a fixed `height: 44` (≥44pt touch target).

## See Also

- [coordination_signal_list.md](coordination_signal_list.md) — original host (now imports this shared sheet).
- [admin_upcoming_task_list.md](admin_upcoming_task_list.md) — inline assign launcher.
