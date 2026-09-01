# NotaCreateSubmit

Submit button for the nota wizard (Walk-in POS / Supplier / Seed transactions).

- **File:** [lib/widget/nota_create_submit.dart](../../lib/widget/nota_create_submit.dart)
- **Class:** `NotaCreateSubmit` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Reads the draft from `AdminCreateTaskSupport`, assembles a nota doc (scalars +
`li[]` native array), and writes via `createNativeDocAutoId`. Above the button:
renders TOTAL Rp. On success: injects `{nno}` bare screenTx key, clears draft,
navigates (chain-aware or route).

NO movement written -- CF OnNotaCreated handles movement per `li[]` line.

## Component shape

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `wizardKey` | String | `walkin_pos` | Draft holder key |
| `vidtable` | String | | appVid override |
| `table` | String | | Firestore table path for nota collection |
| `gl` | String | | Origin warehouse id. **Non-empty = literal (old behavior). Empty = registry fallback (queries `stock_location` for active warehouses).** |
| `warehouseTable` | String | | Optional: explicit stock_location table path override. Default: derived from `table` docId + `stock_location` subcollection. |
| `src` | String | `walkin` | Source identifier (`walkin`, `supplier`, or `seed`) |
| `action` | String | | Must be `savesend` for nota mode |
| `numberPos` | String/int | `0` | txfController position for generated nno |
| `run` | String | | Run commands (e.g. `17:generate_number`) |
| `buyerPosition` | String/int | `12` | txfController position for buyer name. **Empty = use session #NAME.** |
| `paymentPosition` | String/int | `1` | txfController position for payment method. **Empty = skip.** |
| `route` | String | | Navigation target on success (if no chain) |
| `chain` | dynamic | | DO_DIALOG chain config on success |
| `text` | String | | Diamond-separated 6 slots (see below) |
| `sv` | String | | Supplier id token. Supplier only. |
| `sn` | String | | Supplier name token. Supplier only. |
| `kl` | String | | Customer id token. Seed only. |
| `kn` | String | | Customer name token. Seed only. |
| `notePosition` | String/int | | txfController position for note text -> doc field `d`. |
| `daysPosition` | String/int | | txfController position for days -> doc field `days`. Seed only. |

## Text slots

| Index | Default | Used for |
|-------|---------|----------|
| 0 | Buat Nota | Enabled button label |
| 1 | TOTAL | Total label above button |
| 2 | Lengkapi item dulu | Disabled / error label |
| 3 | Gagal membuat nota | Error snackbar |
| 4 | Pilih gudang | Warehouse dropdown hint/label (gl fallback) |
| 5 | Tidak ada gudang aktif | No-warehouse error (gl fallback) |

Slots [4] and [5] are only rendered when config `gl` is empty and the
stock_location subscription is active. Existing configs with fewer than 6 slots
get defaults via the length-guarded `_t()` accessor.

## gl registry fallback (EXTEND #3)

When config `gl` is **empty**, the widget subscribes to the `stock_location`
collection and queries for docs where `lt=='warehouse' && lst=='active'`:

- **Exactly 1** -- auto-uses its `lv` as `gl` (no UI). Common single-warehouse case.
- **>1** -- renders a mandatory `DropdownButton` above the submit button. Submit is disabled until a warehouse is picked.
- **0** -- submit permanently disabled; error text from slot [5] shown.
- **Config gl non-empty** -- ALL fallback logic is skipped. Byte-identical to pre-feature behavior.

Table path for the subscription is derived from `table` config's tableDocId +
`stock_location` subcollection (same container as nota). The optional
`warehouseTable` config overrides this derivation (escape hatch only).

## Supplier mode

Detected when `src == 'supplier'`. Differences:
- li[] uses supplier shape (`draftToSupplierLiArray`): `{ii, in, tx, qo, qi, hrg}`.
- Total = `computeSupplierTotal` (sum of `hrg * max(qo, qi)`).
- Validation = `allSupplierLinesValid`.
- `sv`/`sn` resolved from component tokens via `resolveDriverCurlyTokens`.
- `d` read from `notePosition` txfController.
- `by` = session `#NAME` when `buyerPosition` empty.
- `bym` = '' when `paymentPosition` empty.

## Seed mode

Detected when `src == 'seed'`. Differences:
- li[] uses seed shape (`draftToSeedLiArray`): `{ii, in, qt, cd}`.
- Total = `computeSeedTotalQty` (plain count).
- Validation = `allSeedLinesValid`.
- `kl`/`kn` resolved from component tokens via `resolveDriverCurlyTokens`.
- `days` read from `daysPosition` txfController (integer, nullable).
- `tot` = 0 (no money).

## Event audit row

After a successful native write and **before** navigation, the widget calls
`emitSubmitEventRow` (`lib/widget/driver_home_support.dart`), which routes through
`saveSend` -> `saveSendRows` -> `appendToSheet` -> the history queue -> the Event
tab. **Unconditional** -- no config key gates it, and one insertion covers all
three pages this widget serves (WalkIn / SupplierTransaksi / SeedSaldoAwal).

- `ev` (Event col C) = geo block (`⬤`-left) + every `txfController[scrName]` slot
  with `1 <= position <= 100`, joined by `★`. On these pages that is the generated
  `nno` at `numberPos`, the buyer at `buyerPosition`, the payment method at
  `paymentPosition`, and the note/days slots when configured.
- `p` (col B) = `scrName`. All three pages this widget serves have distinct
  screen names, so `p` alone separates walk-in / supplier / seed.
- `component['flag']` travels as a **prefix inside `ev` itself** -- `saveSendRows`
  builds `'0' + flag + locString + ⬤ + ...` (api.dart:5035-5038) -- not as a
  separate field. Blank when the config omits it; the row still lands.
- **`w` (widget type) and `desc` never leave the device.** `historySync` writes
  only `{"t","p","c","s"}` to Firestore (table_repository.dart:3099-3104); the
  `toDocument2()` path that would carry `w`/`f` is commented out
  (submit_repository.dart:54, :61). They exist in the LOCAL history row
  (`historyAdd([t, p, c, w, f, tb])`, table_repository.dart:2500-2502) and
  nowhere else. So with `flag` unset the report can key only on `p`.
- **GPS is UNCONDITIONAL.** `gpsPosition` is NOT read (renderer-submit-event-gap
  round 2): `emitSubmitEventRow` always awaits `OtqState().setAllDataAsync()`.
  When the fix is invalid, `eventLocString` (driver_home_support.dart) BLANKS the
  latitude / longitude / `isoCountryCode` slots rather than shipping `OtqState`'s
  field initialisers (`888.8888888`, `88`) as if they were a measurement. The
  `locationStatus` slot keeps its `No Gps` value -- so the report can still tell
  "GPS failed" from "geo never captured" -- and the geo block stays at exactly
  16 ◆-separated fields, leaving the report's column mapping unchanged.
- The component copy handed to `saveSend` has `addToTable`, `updateTableRow`,
  `deleteFromTable`, `addToEvent`, `updateEventRow` and `route` removed, so it can
  never double-write or fire `clearData` mid-submit.
- Best-effort: a GPS/compose failure logs and is swallowed, and it never rolls back the
  nota doc. It DOES delay navigation, but **boundedly**: `emitSubmitEventRow` wraps the
  capture in an 8-second `.timeout`, because `getAppGps` puts no `timeLimit` on its
  `Geolocator.getCurrentPosition` fallback (api.dart:301-305) and this await sits on the
  pre-navigation path. Worst case the user waits ~8s before the success route appears;
  the row is still emitted, degraded to the blanked no-GPS geo block described above
  (lat/lng and `isoCountryCode` empty, `locationStatus` = `No Gps`, still 16 ◆ fields).

The nota doc itself no longer carries `search` or `tablevid` (owner decision
2026-08-27) -- they were config parameters, not business data, and nothing read
them.

## See Also

- [task_item_builder.md](task_item_builder.md) -- item-line builder (P2)
