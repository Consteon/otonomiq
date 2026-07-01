# ExecutorDesignateCard

O1 driver-picker card: lets the warehouse checker designate which driver will execute the load, via a bottom-sheet workforce picker.

- **File:** [lib/widget/executor_designate_card.dart](../../lib/widget/executor_designate_card.dart)
- **Class:** `ExecutorDesignateCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** warehouse-opening-check-o1 (2026-06-24)

## Purpose

On O1 (`vertikaTeknoLokaciptaWarehouseOpeningCheck`) the checker must pick the
driver who will take custody of the load before submitting the opening
`vehicle_check` doc. This card renders that choice as a two-state card:

- **UNSET** — amber card, "?" avatar, "Belum ditentukan" + a "Tentukan" button.
- **SET** — teal card, initial avatar, the chosen driver's name + a "Ganti" button.

Tapping the button opens a `showModalBottomSheet` workforce picker. Picking a
driver writes `#CHOSEN_DRIVER_VID` + `#CHOSEN_DRIVER_NAME` to the screenTx
datastore and bumps the shared `chosenRev` signal so the
[CustodyCountSubmit](custody_count_submit.md) O1 variant can react (its enable
gate is `#CHOSEN_DRIVER_VID` non-empty).

It is read-only for Firestore: it subscribes to the workforce collection for
the picker list but never writes (no `txfController`, no `saveSend`, no
history). The actual `dv`/`dn` designation happens at submit time in
`CustodyCountSubmit`.

## Signature / Constructor

```dart
ExecutorDesignateCard({
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
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Left/top/right/bottom padding |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `type` | `String` | Must be `executor_designate_card` (dispatch literal) |
| `workforceTable` | `String` | Workforce subcollection path, e.g. `<docId>//workforce` |
| `com` | `String` | Tenant code for container resolution (`getTableVid`); used when `vidtable` absent |
| `vidtable` | `String` | Explicit container VID override (takes priority over `com`) |
| `nameField` | `String` | Workforce doc field for the driver name (default `n`) |
| `vidField` | `String` | Workforce doc field for the driver VID (default `VID`) |
| `siteField` | `String` | Optional workforce doc field for a site/subtitle line (default empty = hidden) |
| `workforceSearch` | `String` | Optional. Server-encoded AND filter (`key_25FC_val` pairs separated by `_2B58_`). Applied to subscribed workforce docs via `filterDriverHomeDocs` before the VID guard. Empty/absent = no server filter. Example: `role_25FC_staff` filters to docs where `role == 'staff'`. |
| `text` | `String` | Diamond-separated label slots (see below) |

### `text` slots (diamond-separated `◆`)

| Index | Default | Meaning |
|---|---|---|
| 0 | `PENGEMUDI` | Section label |
| 1 | `Belum ditentukan — pilih sebelum berangkat` | UNSET message |
| 2 | `Tentukan` | UNSET button |
| 3 | `Ganti` | SET button |
| 4 | `TENTUKAN PENGEMUDI` | Picker title |
| 5 | `Siapa yang ngantar?` | Picker subtitle |
| 6 | `Pilih dari daftar pegawai` | Picker helper |
| 7 | `Tidak ada pegawai tersedia` | Picker empty state |

All slots are length-guarded via `_t(i, def)` (`diamondTextToList` indexes are
read with `length > i`, never `[i]` directly).

## State / Bloc / Dependencies

- **State used:** Redux `transactionStore` (`#CHOSEN_DRIVER_VID`,
  `#CHOSEN_DRIVER_NAME`, `#ACTIVE_WAREHOUSE`); GetX `RxInt chosenRev` (static,
  cross-widget reactivity).
- **Repository:** `subscribeToMapCollection` (workforce list), `mapTableContent`.
- **Side effects:** dispatches `#CHOSEN_DRIVER_VID`/`#CHOSEN_DRIVER_NAME` on
  pick; bumps `chosenRev`.

### Cross-widget reactivity

`static final RxInt chosenRev` is bumped on pick and on clear. Both this card
and the O1 `CustodyCountSubmit` Obx-touch it, so the submit's enable gate
updates the instant a driver is picked. The chosen vid/name themselves live in
screenTx (a plain datastore), NOT in an RxMap — `chosenRev` is the only
reactive signal (no mutate-in-build hazard).

### State reset on route change

`static void clearO1State(String scrName)` clears all three screenTx keys
(`#CHOSEN_DRIVER_VID`, `#CHOSEN_DRIVER_NAME`, `#ACTIVE_WAREHOUSE`), bumps
`chosenRev`, and resets `CustodyCountList.resetWarehousePublished(scrName)`.
It is called from `clearData` (api.dart) on every route change, BEFORE the
`txfController[scrName] == null` early-return (the SDUI per-scrName state-reset
rule). On reopen the card is UNSET again and the warehouse `gl` re-publishes.

## Workforce filtering

The picker list is filtered through two layers (in order):

1. **Server search (`workforceSearch`):** Applied via `filterDriverHomeDocs`
   (from `driver_home_support.dart`). Handles `autheniumDecode` internally —
   the caller passes the raw component field value. Empty/absent value = no
   server filter (all docs pass through unchanged).

2. **VID guard:** Drops any doc whose resolved `vidField` is empty. This ensures
   meta/tenant docs (which have no VID) never appear in the picker, regardless
   of whether a server search is configured.

Both layers are implemented in `static filterWorkforceDocs(...)` — a pure
function on the widget class, directly testable. `_getWorkforceDocs` delegates
to it.

> **QA prereq (data):** Functional on-device QA needs real driver docs in the
> `workforce` collection (Firestore). The demo seeder does NOT seed workforce
> docs. When the collection is empty the picker correctly shows the empty-state
> message ("Tidak ada pegawai tersedia") — expected behavior, not a bug.

## Important Behavior

- The picker list shows whatever is currently in `mapTableContent` for the
  workforce subscription — empty until the first snapshot lands (empty-state
  message shown).
- A workforce row with an empty `vidField` is not tappable (defense-in-depth
  `onTap` guard in `_buildRow`, in addition to the `filterWorkforceDocs` VID
  guard which already prevents such rows from reaching the list).
- Container consistency: `workforceTable` + `vidtable`/`com` must resolve to the
  container the workforce subcollection actually lives in (mirrors scanner /
  otq_txf_2 searchtable routing).

## See Also

- [custody_count_submit.md](custody_count_submit.md) — O1 submit reads
  `#CHOSEN_DRIVER_VID` for its enable gate + designates `dv`/`dn` at submit.
- [custody_count_list.md](custody_count_list.md) — O1 count-list publishes
  `#ACTIVE_WAREHOUSE`, which `clearO1State` resets.
