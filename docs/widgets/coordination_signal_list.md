# CoordinationSignalList

Admin "Perlu Tindakan" signal list (H1): derives actionable signals client-side from 5 Firestore collections and renders clustered cards with admin actions (vehiclePicker assign/reassign) and cross-runtime nav (Gudang).

- **File:** [lib/widget/coordination_signal_list.dart](../../lib/widget/coordination_signal_list.dart)
- **Class:** `CoordinationSignalList` (StatefulWidget) + private `_VehiclePickerSheet`
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** admin-home slice 1

## Purpose

The triage command-center body of the Admin Koordinasi screen. It computes five signal types across `task`, `stock_location`, `vehicle_check`, and `evidence` (via `deriveAdminSignals` — the SINGLE source of truth shared with `AdminCoordinationHeader`'s sinyal-count chip), clusters them by type (most urgent cluster first), and gives each a one-tap remediation:

| Signal type | Trigger | Action |
|---|---|---|
| `unassigned_vehicle` | task `tst==assigned` AND `vv` empty | vehiclePicker (assign) |
| `task_returned` | task `tst==load_rejected` | vehiclePicker (reassign) |
| `no_executor` | vehicle (`lt==vehicle`) with `dv` empty AND ≥1 assigned task | cross-nav to Gudang |
| `blocked_departure` | vehicle_check `cty==opening` AND `cst==awaiting_custody` AND vehicle has a task today | cross-nav to Gudang (soft/outline) |
| `invoice_pending` | task `tst==completed` AND `iv` empty | navigate to invoiceRoute (DeliveryInvoice) |

When zero signals are derived, the widget collapses to `SizedBox.shrink()`.

## Signature / Constructor

```dart
CoordinationSignalList({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance (the dispatch chain passes `txfKey`) |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Left/top/right/bottom padding |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | appVid (Firestore container). Falls back to `getTableVid(component['com'])` via `resolveAppVid`. |
| `table` | `String` | `"<tableDocId>//task"` — task subcollection (also the vehiclePicker write target). |
| `vehicleTable` | `String` | `"<tableDocId>//stock_location"` — stock_location subcollection. |
| `checkTable` | `String` | `"<tableDocId>//vehicle_check"` — vehicle_check subcollection. |
| `evidenceTable` | `String` | `"<tableDocId>//evidence"` — evidence subcollection (reject reasons). |
| `assetTable` | `String` | `"<tableDocId>//asset_cache"` — subscribed but NOT consumed by signal derive in slice 1 (future genesis-nudge). |
| `crossRoute` | `String` | Gudang route for `no_executor`/`blocked_departure`. Dead-route silent-skip via `routeExist`. |
| `crossRouteParams` | `String` | routeParams DSL, e.g. `"gudangVehicle◼{vehicleId}"`; `{vehicleId}` is replaced with the signal's vehicle id, then dispatched via `writeRouteParams`. |
| `text` | `String` | `◆`-separated label slots (see Text slots). |

### Config params (R3)

All optional; absent = current defaults (backward-compatible). Threaded through to `deriveAdminSignals` as `dangerMs`/`warnMs` (minutes × 60 000).

| Key | Default | Meaning |
|---|---|---|
| `dangerAge` | `90` | minutes threshold for the `danger` tier |
| `warnAge` | `30` | minutes threshold for the `warn` tier |

### Config params (R4)

All optional; absent = the documented default (backward-compatible). Field-name keys are read in `_parseFieldConfig()` and passed to `deriveAdminSignals`; gate DSLs are `autheniumDecode`d (server sends `◼`/`⭘` as `_25FC_`/`_2B58_`) before storing. `updateEventRow` is the DSL template threaded to `VehiclePickerSheet` (resolved with `{taskVid}`/`{vehicleId}` at confirm time, executed via `executeUpdateEventRow`).

**Field-name config** (all default to the current hardcoded value):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `statusField` | `String` | `tst` | task status field |
| `vehicleField` | `String` | `vv` | task vehicle FK field |
| `customerNameField` | `String` | `kn` | task customer name field (signal head) |
| `addressField` | `String` | `al` | task address field |
| `scheduleField` | `String` | `tdt` | task schedule date field |
| `plateField` | `String` | `ln` | stock_location plate/name field |
| `driverField` | `String` | `dv` | stock_location driver FK field |
| `locationTypeField` | `String` | `lt` | stock_location type field |
| `locationIdField` | `String` | `lv` | stock_location id field |
| `checkTypeField` | `String` | `cty` | vehicle_check type field |
| `checkStatusField` | `String` | `cst` | vehicle_check status field |
| `checkVehicleField` | `String` | `vv` | vehicle_check vehicle FK field |
| `evidenceTypeField` | `String` | `ept` | evidence parent type field |
| `evidenceRefField` | `String` | `erf` | evidence reference field |
| `reasonNoteField` | `String` | `d` | evidence reason note field (task_returned summary suffix) |

**Gate DSL config** (`field◼value⭘field◼value…`, AND'd; empty value = "field must be empty"; `autheniumDecode`d before use). When a gate is empty/absent, that signal type produces ZERO signals — the signal-list is INERT until the gate JSON is deployed. A `devPrint` warning fires when ALL 5 gates are empty.

| Key | Default | Spec(2) value | Meaning |
|---|---|---|---|
| `unassignedGate` | `''` | `tst◼assigned⭘vv◼` | gate for `unassigned_vehicle` (task docs) |
| `returnedGate` | `''` | `tst◼load_rejected` | gate for `task_returned` (task docs) |
| `noExecutorGate` | `''` | `lt◼vehicle⭘dv◼` | gate for `no_executor` (stock_location docs) |
| `blockedGate` | `''` | `cty◼opening⭘cst◼awaiting_custody` | gate for `blocked_departure` (vehicle_check docs) |
| `invoiceGate` | `''` | `tst◼completed⭘iv◼` | gate for `invoice_pending` (task docs); always tier `ok` (no age coloring) |

**Write target:**

| Key | Default | Meaning |
|---|---|---|
| `updateEventRow` | `''` | updateEventRow DSL template passed to the vehiclePicker (`executeUpdateEventRow`, online-only). Spec(2): `84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{taskVid}⭘vv◼{vehicleId}⭘tst◼assigned`. |
| `assignSheet` | `''` | sheet identity (e.g. `vehiclePicker`); read but not yet branched in H1. |

**Invoice tier navigation:**

| Key | Default | Meaning |
|---|---|---|
| `invoiceRoute` | `''` | Route name for invoice page |
| `invoiceRouteParams` | `''` | routeParams DSL with `{tnm}` token (e.g. `taskVid◼{tnm}`); resolved and dispatched before nav |

**Invoice tier styling** (hardcoded, no config key). The card layout is the shared
`_buildSignalCard` used by every tier — only the accent differs, because the invoice
signal means "delivery done, just bill" rather than "action blocked":

| Element | Other tiers | `invoice_pending` |
|---|---|---|
| Action button | blue `#2563EB` (admin) / amber `#F59E0B` (danger, cross) | green `#15803D` (`okActionGreen`) |
| Button icon | `open_in_new` (cross) / none | `receipt_long_outlined` |
| Age pill | slate `#F1F5F9` / `#64748B` | green `#DCFCE7` / `#16A34A` |
| Icon tile | blue `#EAF1FF` + blue glyph | green `#DCFCE7` + `okActionGreen` glyph |

`okActionGreen` is deliberately darker than the `okBadgeText` green used on the pill:
as a solid button background behind a white 14px-bold label it needs AA contrast
(5.0:1); `okBadgeText` is 3.3:1 and is badge-only.

**RESERVED** (accepted in JSON, NOT consumed by `deriveAdminSignals`):

| Key | Default | Why reserved |
|---|---|---|
| `reasonSearch` | `''` | Spec(2) evidence-query filter. The evidence match uses a hardcoded `ept=='task'` + `erf==tnm` join (correct for H1); the per-task `{tnm}` token DSL is not wired. Future slice. |
| `reasonCatField` | `ec` | Spec(2) evidence category. The signal summary shows only `reasonNoteField` (free-text), not the category code. Future slice. |
| `itemsField` | `it` | Listed in spec(2) but signals do not display items. |

### Text slots (`◆`-separated, length-guarded)

| Index | Meaning | Default |
|---|---|---|
| 0 | Section title | `Perlu Tindakan` |
| 1 | assign button label | `Tugaskan` |
| 2 | reassign button label | `Assign Ulang` |
| 3 | no_executor button label | `Tunjuk di Gudang` |
| 4 | blocked_departure button label | `Lihat di Gudang` |
| 5 | cluster: unassigned_vehicle template | `{n} order menunggu kendaraan` |
| 6 | cluster: task_returned template | `{n} order dikembalikan driver` |
| 7 | cluster: no_executor template | `{n} kendaraan tanpa pengantar` |
| 8 | cluster: blocked_departure template | `{n} kendaraan menunggu opening` |
| 9 | vehiclePicker assign title | `Pilih Kendaraan` |
| 10 | vehiclePicker reassign title | `Assign Ulang Kendaraan` |
| 11 | vehiclePicker confirm label | `Konfirmasi` |
| 12 | "task aktif" suffix | `task aktif` |
| 13 | offline error | `Perlu koneksi internet` |
| 14 | write fail error | `Gagal menyimpan` |
| 15 | cluster: invoice_pending template | `{n} selesai - perlu invoice` |
| 16 | invoice action button label | `Cetak Invoice` |

Each slot uses `_t(i, def)` = `arr.length > i ? arr[i] : def` (out-of-range safe). Cluster templates substitute `{n}` with the cluster count.

## Usage Examples

Server op1Screen child (see [admin-home-op1screen.md](../admin_runtime/admin-home-op1screen.md)):

```json
{"type":"COORDINATION_SIGNAL_LIST","vidtable":"20342033315492","table":"84214220504259//task","vehicleTable":"84214220504259//stock_location","checkTable":"84214220504259//vehicle_check","evidenceTable":"84214220504259//evidence","assetTable":"84214220504259//asset_cache","crossRoute":"vertikaTeknoLokaciptaGudangVehicle","crossRouteParams":"gudangVehicle◼{vehicleId}","text":"Perlu Tindakan◆Tugaskan◆Assign Ulang◆Tunjuk di Gudang◆Lihat di Gudang◆{n} order menunggu kendaraan◆{n} order dikembalikan driver◆{n} kendaraan tanpa pengantar◆{n} kendaraan menunggu opening◆Pilih Kendaraan◆Assign Ulang Kendaraan◆Konfirmasi◆task aktif◆Perlu koneksi internet◆Gagal menyimpan◆{n} selesai - perlu invoice◆Cetak Invoice","invoiceGate":"tst◼completed⭘iv◼","invoiceRoute":"vertikaTeknoLokaciptaDeliveryInvoice","invoiceRouteParams":"taskVid◼{tnm}"}
```

## State / Bloc / Dependencies

- **State used:** none persisted. Reactive from GetX `mapTableContent` (5 collections) inside one `Obx`. The vehiclePicker is a transient `showModalBottomSheet`.
- **Repository:** `subscribeToMapCollection` (table_repository) for live subcollection reads.
- **Helpers:** `admin_home_support.dart` (`deriveAdminSignals`, `Signal`, `formatAge`, `AdminTierColors`), `driver_home_support.dart` (`resolveAppVid`, `todayEpochMidnightWib`, `writeRouteParams`, `writeNativeFields`), `panel_card_support.dart` (`parseTablePath`). Tier colors come from `AdminTierColors` (R3 centralized palette), NOT `statusColor`/`statusBgColor`.
- **Side effects:** cross-nav does `writeRouteParams(...)` then `routeStack.push(route)` BEFORE `gotoRoute(route)`. vehiclePicker confirm calls `writeNativeFields`.
- **Writes:** vehiclePicker → `writeNativeFields` (set-merge into the unique task doc). assign patch `{'vv': <lv>}`; reassign patch `{'vv': <lv>, 'tst': 'assigned'}`; search `tnm◼{taskVid}`. **Online-only — bypasses the offline history queue** (custody precedent). 0-match or >1-match → returns false → snackbar.

## Important Behavior

- 0 signals → `SizedBox.shrink()` (full collapse).
- Cluster ordering is preserved from `deriveAdminSignals` (clusters by maxAge desc, items by age desc); `_buildClusters` re-groups while honoring that order.
- Cards use the centralized `AdminTierColors` 3-tier palette keyed by each signal's `tier` (danger/warn/ok). Age thresholds default to danger > 90 min, warn > 30 min, overridable per-component via `dangerAge`/`warnAge`. The signal head text renders in `monospace` (P2/optional dispatch-ticket styling). The age pill shows `formatAge` (e.g. `2j 15m`, `45m`, `< 1m`).
- `blocked_departure` renders as a soft `OutlinedButton`; the other three use a filled `ElevatedButton`. Cross-nav cards show an `open_in_new` icon.
- Cross-nav (`no_executor`/`blocked_departure`) is dead-route safe: empty `crossRoute` or `!routeExist` → no push/nav (silent-skip). routeParams are still dispatched first so the destination can read them when the Gudang runtime later ships.
- vehiclePicker lists ALL `lt==vehicle` stock_location rows (both modes) with their active-task count (`tst` in `{assigned, on_delivery}`); no overload cap in v1. Confirm shows a spinner while writing; offline → "Perlu koneksi internet", other failure → "Gagal menyimpan".
- Dispatch literal is lowercase `coordinationsignallist` (the chain lowercases `component['type']`).

## See Also

- [admin_coordination_header.md](admin_coordination_header.md) — the header that shares `deriveAdminSignals` for its sinyal count.
- [admin-home-op1screen.md](../admin_runtime/admin-home-op1screen.md) — paste-ready server page JSON.
- [driver_home_support.md](../../lib/widget/driver_home_support.dart) — `writeNativeFields` / `writeRouteParams` source.
