# TaskItemBuilder

Item-line builder for the Admin create-task wizard (P2).

- **File:** [lib/widget/task_item_builder.dart](../../lib/widget/task_item_builder.dart)
- **Class:** `TaskItemBuilder` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** admin-create-task slice

## Purpose

Builds the `it[]` array for a new task. Each line has a transaction type
(deliver/sale/purchase/refill) with qty steppers and condition/water toggles.
Product picker bottom-sheets read from the item collection. Model B pickup
suggestion auto-computes pp from pd + outstanding (degrade-safe when
asset_cache is absent). Four separate CTAs map to the four tx types.

Sale rows include an inline price input (`hg`, integer rupiah). Default price
seeded from the item catalog; **in order mode** that is `priceSourceField`
(default `hrg`) first, falling back to `itemPriceField` (default `harga`) when
that yields 0. The fallback is order-mode only — a `walkin` sale row reads
`priceSourceField` with no fallback (0 when only `harga` is set), `supplier`
likewise for every tx type, and any other mode's sale row reads
`itemPriceField`. Per-line subtotal = `hg * ps`. Footer shows
Total Rp = sum of all sale line subtotals.

## Signature / Constructor

(Standard SDUI widget: key, scrName, component, lPad, tPad, rPad, bPad.)

### `component` shape

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `itemTable` | String | | Firestore table path for item catalog (e.g. `84214220504259//item`) |
| `clientTable` | String | | stock_location table path (resolve kl -> kn/al) |
| `outstandingTable` | String | | asset_cache table path (Model B source) |
| `wizardKey` | String | `admin_create_task` | Draft holder key |
| `vidtable` | String | | appVid override |
| `itemIdField` | String | `ii` | Item id field on item catalog doc |
| `itemNameField` | String | `in` | Item name field on item catalog doc |
| `itemCatField` | String | `ic` | Item category field on item catalog doc |
| `itemPriceField` | String | `harga` | **Fallback** price field on the item catalog doc. In `order` mode read only when `priceSourceField` yields 0; never read in `walkin`/`supplier`. |
| `priceSourceField` | String | `hrg` | **Primary** price field on the item catalog doc — the field walkin, supplier AND order all price from, and the field the Cloud Function builds the real invoice from. Since spec (4) §6b-2.2 no.3a, `order` mode reads this first. |
| `priceField` | String | — | **INERT — the renderer ignores this key entirely.** `grep -rn "priceField" lib/` returns zero hits; the `it[]` price key is hardcoded as `hg` in `DraftItem.toItMap`. Safe to delete from the sheet. Deliberately NOT implemented (owner decision 2026-08-28): config-renamable `it[]` keys would silently break every by-key reader — `item_execution_submit.rebuildItWithActuals`, `receiptDoc`'s `linePriceField`/`lineSubField`, the driver feed's it[] readers, and the out-of-repo Go CF. |
| `searchField` | String | value of `itemNameField` | Which item field the picker search query filters against (spec section 1.5b) |
| `searchHint` | String | `Cari...` | Placeholder text in the picker search box |
| `emptyText` | String | `Semua item sudah ditambahkan` | Text shown when the filtered picker list is empty (catalog exhausted or query no-match) |
| `sortField` | String | `''` (empty = name-asc only) | Numeric field on item docs to sort the picker by (e.g. `freq` for popularity). Uses `coerceNum`; absent field on a doc = 0. When empty, picker sorts by name asc (backward-compat). |
| `sortDir` | String | `desc` (when `sortField` present) | Sort direction for `sortField`: `desc` (popular first) or `asc`. Ignored when `sortField` is empty. |
| `txTypes` | String | `deliver,sale,purchase,refill` | Comma-separated list of active transaction button types. Order = button order. Absent/empty = all 4 (backward-compat). Unknown types silently skipped. |
| `text` | String | | Diamond-separated label slots (16 slots; see below) |

### Text slots

| Index | Default | Used for |
|-------|---------|----------|
| 0 | Tambah Item | Deliver CTA label |
| 1 | (reserved) | -- |
| 2 | Refill | Refill CTA / label |
| 3 | Jual | Sale CTA / label / chip |
| 4 | Beli | Purchase CTA / label |
| 5 | Kosong | Condition empty |
| 6 | Penuh | Condition full |
| 7 | Air RO | Water type RO |
| 8 | Isi Ulang | Water type refill |
| 9 | Pilih Produk | Picker sheet title |
| 10 | Drop | Drop stepper label |
| 11 | Pickup | Pickup stepper label |
| 12 | Hapus | Delete button tooltip |
| 13 | saran | Model B suggestion hint |
| 14 | Harga | Price input label |
| 15 | Total | Total Rp footer label |

### Price field (`hg`)

- **Price INPUT is sale rows only.** Deliver, purchase, and refill rows show no
  price field in the builder.
- **Price VALUE is carried on deliver rows too** (order mode, since
  2026-08-27, spec (3) §6b-2.2 no.3). A deliver line is seeded per
  `seedPriceFor` — see the next bullet for which field that actually reads —
  and keeps the value silently: the admin never sees it in the builder, but the
  WA order-confirm message prints it per line and is editable before sending.
  Same "silently carried `hg`" pattern already used for consumables. Purchase
  and refill stay at `hg: 0`.
- **Default source (order mode, since spec (4) §6b-2.2 no.3a):**
  `item[priceSourceField]` (default `hrg`) **first**, falling back to
  `item[itemPriceField]` (default `harga`) **only when the first yields 0**.
  Seeded when the product is picked; user can override inline on sale rows.
  - Why: the catalog's real price field is `hrg` — walkin and supplier both read
    it, and the CF prices the real invoice from `item.hrg`. Order mode read
    `harga` only, found nothing, and shipped every line at `hg: 0` → `sub: 0` →
    `tot: 0` → `PERKIRAAN TOTAL Rp 0` on `OrderConfirm` (order
    TASK-2026-000561).
  - Why a fallback and not a swap: `itemPriceField`'s default is documented as a
    live schema. A hard swap would silently zero out any tenant for whom that is
    true — no crash, no log, no analyzer finding.
  - **Accepted ceiling:** an item with `hrg: 0` (deliberately free) AND a
    non-zero `harga` falls back to `harga`. `coerceNum` maps a missing key and a
    literal `0` to the same `0`, so "free" and "absent" are indistinguishable
    here. Both fields zero still yields 0.
  - Applies to `order` + `deliver` **and** `order` + `sale` (a consumable
    deliver becomes an effective `sale`). `purchase` / `refill` / `seed` stay
    unpriced. `walkin` and `supplier` are byte-identical to before.
- **Decision helpers:** `TaskItemBuilder.seedPriceFor()` (which field to seed
  from, per mode + effective tx) and `TaskItemBuilder.keepsPrice()` (whether the
  new line keeps it). Both pure statics; walkin/supplier/seed behaviour is
  unchanged.
- **Format:** integer rupiah (e.g. 45000). Input accepts digits only.
  Display uses `AdminCreateTaskSupport.formatRupiah()` (e.g. "Rp 45.000").
- **Subtotal:** shown per line when `ps > 0` and `hg > 0` as
  `"{ps} x Rp {hg} = Rp {subtotal}"`.
- **Footer Total Rp:** sum of `hg * ps` across all sale lines, shown as an
  amber pill below the existing qty pills.
- **Serialization:** `DraftItem.toItMap()` emits `'qt'` on **every** row (the
  canonical billed qty — `pd` for deliver, `ps` for sale, `pb` for purchase,
  `pr` for refill, `0` for anything else; same key and meaning as the walk-in
  nota's `li[].qt`). It additionally emits `'hg'` **and** `'sub'` for
  `deliver` and `sale` rows (`sub = hg * qt`); purchase / refill / buy / seed
  rows carry neither. `assembleTaskDoc` then writes
  `'tot': AdminCreateTaskSupport.computeItTotal(itArray)` — always present,
  `0` for a pickup-only task. Propagates through `draftToItArray` ->
  `assembleTaskDoc` -> native Firestore `set()` at P4 submit. The order-time
  price is a PLANNING estimate; the CF prices the real invoice from `item.hrg`
  at completion (spec (3) §2).
- **`qt` is PLANNED, never actual.** `rebuildItWithActuals`
  (item_execution_submit) shallow-copies every element and writes only the
  actual-qty fields, so after the driver executes a task, `qt` — like `sub`
  and `tot` — still holds the qty planned at creation. It feeds the
  pre-execution order confirmation (`OrderConfirm` receiptDoc + WA message),
  not the invoice. `qt` exists because `receiptDoc`'s `lineQtyField` and the
  WA template's `{{item.*}}` can each name only ONE key, while the real qty
  lives in a different field per tx kind (spec (5) §6b-2.2 no.6).
  A pickup-only `deliver` line (`pd: 0`, `pp: 3` — a customer returning
  empties) therefore carries `qt: 0` and will render "0x" once the sheet
  reads `qt`. That is CORRECT: `pp` is a return quantity, never billed. It is
  not the defect `qt` fixes — that was a row whose BILLED qty was non-zero
  (`ps: 3`) rendering "0x".

### Empty state

When the product picker sheet has zero items to display (either all catalog
items are already in the draft, or the search query matches nothing), a centered
muted text shows `emptyText` instead of a blank list. Config-driven; default
`"Semua item sudah ditambahkan"`.

### CTA button gating (`txTypes`)

The CTA row ("Tambah Item", "+ Jual", "+ Beli", "+ Refill") is config-driven
via `txTypes`. Only types listed in the comma-separated value are rendered as
buttons, in the order they appear. This lets the owner start with a subset of
transaction types (e.g. `"txTypes": "deliver"` for delivery-only) and add more
later by editing the JSON -- zero Dart deploy.

**Default (absent/empty):** all 4 buttons in order `deliver, sale, purchase,
refill` -- backward-compatible with deployments that lack the key.

**Unknown types:** silently skipped. Only the 4 known types (`deliver`, `sale`,
`purchase`, `refill`) have product-picker category filters and card body
rendering support. An unrecognized entry in `txTypes` produces no button.

**Parse method:** `TaskItemBuilder.parseTxTypes(component)` -- public static,
unit-testable without widget pump.

## See Also

- [task_draft_summary.md](task_draft_summary.md) -- P4 read-only preview
- [task_create_submit.md](task_create_submit.md) -- P4 submit button
- [custody_count_list.md](custody_count_list.md) -- structural mirror

## Supplier mode (`mode:"supplier"`)

When `component['mode']` is `'supplier'`, the widget renders a supplier
transaction builder instead of the order/walkin item builder.

### Supplier component shape

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | String | | Must be `'supplier'` |
| `wizardKey` | String | `admin_create_task` | Draft holder key |
| `vidtable` | String | | appVid override |
| `itemTable` | String | | Firestore table path for item catalog |
| `itemIdField` | String | `ii` | Item id field on item catalog doc |
| `itemNameField` | String | `in` | Item name field on item catalog doc |
| `priceSourceField` | String | `hrg` | Field for default price seed |
| `txOptions` | String | | ★-separated pairs of `value◼Label` (e.g. `buy◼Beli★refill◼Tukar★sale◼Jual`). autheniumDecode before parsing. |
| `searchHint` | String | `Cari...` | Picker search placeholder |
| `text` | String | | Diamond-separated 7 slots (see below) |

### Supplier text slots

| Index | Default | Used for |
|-------|---------|----------|
| 0 | Barang | Empty state title |
| 1 | + Barang | Add CTA label |
| 2 | Keluar | qo stepper label |
| 3 | Masuk | qi stepper label |
| 4 | Harga | Price input label |
| 5 | Subtotal | Per-line subtotal label / footer |
| 6 | Hapus | Delete tooltip |

### Behavior differences from order/walkin

- **Single CTA**: one "+ Barang" button opens the picker for all items. No per-tx CTAs.
- **No category filter**: all items shown in picker regardless of tx type.
- **Per-line tx selector**: segmented chips parsed from `txOptions` config.
  User selects buy/refill/sale per line.
- **Qty fields**: uses `DraftItem.qo` / `DraftItem.qi` (not pd/pp/ps/pb/pr).
- **Price**: seeded from `priceSourceField` for ALL tx types (not just sale).
- **Subtotal**: `hrg * max(qo, qi)` per line.
- **Refill seeding**: selecting "Tukar" seeds `qo = qi` once; both independent after.
- **Validation**: buy requires qi>=1+hrg>0; sale requires qo>=1+hrg>0;
  refill requires qo>=1+qi>=1 (hrg may be 0).
