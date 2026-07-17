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

## See Also

- [task_item_builder.md](task_item_builder.md) -- item-line builder (P2)
