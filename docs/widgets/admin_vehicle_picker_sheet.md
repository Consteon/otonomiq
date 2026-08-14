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

### Config params (R5 — busy-vehicle guard)

Three OPTIONAL params, read by the caller widget (not the sheet itself) and
forwarded as constructor args. All absent = guard off, unchanged behavior.

| Caller config key | Sheet param | Type | Description |
|---|---|---|---|
| `assignBusySearch` | `busySearch` | `String` | Gate-DSL busy query with row token `{lv}`, evaluated against `busyDocs`. Canonical: `vv◼{lv}⭘cty◼opening⭘cdt◼{today}⭘rt◼pending`. Empty = guard off. |
| `assignBusyTable` | _(resolved by caller → `busyDocs`)_ | `String` | Table the query runs against. Normally `<docId>//vehicle_check`. The caller subscribes it in `_subscribe()` and passes the docs. Empty = query the caller's own `table` docs. |
| `assignBusyLabel` | `busyLabel` | `String` | Badge text on busy rows (e.g. "Lagi Jalan"). Empty = row still disabled, no badge text. |

**Static helpers (public, for testability):**

- `VehiclePickerSheet.busyPoolCode({assignBusySearch, assignBusyTable, appVid})` — vid-scoped `mapTableContent` key for the busy pool, or `''` when the caller should use its own docs.
- `VehiclePickerSheet.isVehicleBusy(docs, busySearch, lv)` — delegates to `PickerList.countForRow`; returns `bool`.

**Busy row visual:** `Opacity(0.45)` + `onTap: null` + subtitle appends ` · {busyLabel}` in red-500 (`#EF4444`).

#### R5.1 — the busy source is `vehicle_check`, NOT `task.tst`

R5 shipped with `assignBusySearch: "vv◼{lv}⭘tst◼on_delivery"` (straight from the
spec) and a resolver that turned the guard **off** whenever `assignBusyTable`
differed from `component['table']`. Both were wrong, and together they made the
guard a no-op that looked configured:

- **`tst` never becomes `on_delivery`.** Verified against tenant `20342033315492`
  on 2026-08-11: 22 `task` docs, statuses only `unassigned` / `assigned` /
  `completed` / `failed`. Nothing in `lib/` or in `op1Screen` writes
  `on_delivery` — all 16 occurrences are read-side searches.
- **"Lagi jalan" is derived from `vehicle_check`.** `deriveVehicleTier`
  (`vehicle_feed_support.dart:154-178`) returns `VehicleTier.inRoute` when the
  opening doc has `cst == 'custody_confirmed'` and any task is still open. A
  vehicle on the road keeps `tst == 'assigned'` — and `assigned` must stay
  selectable (spec §3: loaded-but-not-departed can take a joined trip).

So the guard has to query a **different table than the caller's own**. R5.1
replaces `effectiveBusySearch` (deleted) with `busyPoolCode` + a `busyDocs`
constructor param: the caller resolves `assignBusyTable` to a vid-scoped
`mapTableContent` code, subscribes it in `_subscribe()`
(`subscribeToMapCollection` dedups, so overlapping with a sibling widget on the
same screen is a no-op), and passes that doc list in.

Live config (`op1Screen!AK759` / `!W766` feed `[ASSIGNBUSYSEARCH]`) must move to:

```
"assignBusyTable":"84214220504259//vehicle_check"
"assignBusySearch":"vv◼{lv}⭘cty◼opening⭘cdt◼{today}⭘rt◼pending"
```

Two segments beyond `cst`, both load-bearing (backend spec rev4, verified
against live docs):

- **`rt◼pending`** — ReturnVehicle flips `rt` to `returned` and **never resets
  `cst`**. Without this segment a vehicle stays "Lagi Jalan" from its first
  trip onward, until the warehouse closing sets `cst=closed`.
- **`cdt◼{today}`** — scopes to today's check, so one stuck doc from a previous
  day cannot pin a vehicle busy forever. Requires `PickerList.resolveTimeTokens`
  (added the same day) — before it, `{today}` tripped `countForRow`'s
  leftover-`{` bail and the whole guard counted 0.

State walk for one trip, and why only the middle row matches:

| stage | `cst` | `rt` | assignable? |
|---|---|---|---|
| loaded, driver has not accepted | `awaiting_custody` | `pending` | ✅ joined-trip flow |
| driver accepted, departed | `custody_confirmed` | `pending` | ❌ **on the road** |
| handed back to the warehouse | `custody_confirmed` | `returned` | ✅ idle again |

Ordering: ship this renderer first, then flip the config — the reverse leaves
the guard querying `task` for a status that does not exist.

Side effect of the same wrong query: `PICKER_LIST`@CreateTaskVehicle(790)
`statusSearch` and `LIST_CARD`@AssignVehicle(1181) `statusSearch` carry the
identical `tst◼on_delivery` string and are equally dead — they need the same
config change (the LIST_CARD renderer support is still unbuilt, spec §2B).

**Snapshot semantics (I1):** both callers freeze `busyDocs` via
`List<Map<String, dynamic>>.from(mapTableContent[_busyCode] ?? const [])` at
sheet-launch time, so the guard runs against a **frozen snapshot**, not a live
`Obx` view — a vehicle that departs while the sheet is open stays selectable
until the sheet is reopened (correct for a short-lived modal).

#### R5.2 — `busySelfField`, the second (wider) guard

Backend spec rev3 asked for the mechanism `PICKER_LIST` already ships: the
vehicle row's **own** field marks it busy, no cross-table query.

| Caller config key | Sheet param | Description |
|---|---|---|
| `busySelfField` | `busySelfField` | Row field that means busy when non-empty. `dv` = a driver holds the vehicle. Empty = self-guard off. |
| `busySelfLabelField` | `busySelfLabelField` | Field supplying the badge name (`dn`). Empty = disabled, no name. |

Same key names as `PICKER_LIST` (`picker_list.dart:384-406`), read from the
**caller** component (`COORDINATION_SIGNAL_LIST` / `UPCOMING_TASK_LIST`) — the
sheet never reads a template. Statics: `isVehicleSelfBusy(veh, busySelfField)`
and `busyBadgeText({busyLabel, selfLabel})`.

**The two guards are independent — a row is busy when EITHER fires.** Badge =
`busyLabel · selfLabel`, either part optional.

★ They are NOT interchangeable. `dv` is set from warehouse designation until
the closing check clears it, so it also blocks a vehicle that is still
**loading**: MBL-01 in production has `dv` filled while its opening check is
`awaiting_custody` — the admin feed shows it as CUSTODY PENDING, not IN ROUTE.
Enabling `busySelfField` therefore reverses spec rev1 §3 ("`assigned` stays
selectable") and contradicts the NOTICE_BAR at AssignVehicle(975) that
advertises joined trips. Ship the knob, but default config should use the
`vehicle_check` search alone until that trade-off is decided.

**Not expressible in config alone:** `evaluateGate`
(`admin_home_support.dart:486-492`) has no negation — an empty expected value
means "field must be empty", so `assignBusySearch` cannot say "`dv` is set".
That is why this needed Dart, not another gate string.

**Fail-open by design:** an unsubscribed/empty pool or a typo'd row token
(`{vv}` instead of `{lv}`, which leaves `{` unresolved and makes
`countForRow` bail to 0) blocks nothing and logs a devPrint. Never make this
fail-closed — it gates *availability*, not permission, and a fail-closed
version would block the entire fleet and stop dispatch.

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
