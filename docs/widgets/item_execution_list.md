# ItemExecutionList

Per-item execution list for P11 DeliveryWorkspace. Supports four transaction types: deliver (editable steppers with optional stock cap), sale (editable stepper with optional stock cap via `saleCapSearch`), purchase (editable stepper, uncapped), refill (static card, stepper deferred).

- **File:** [lib/widget/item_execution_list.dart](../../lib/widget/item_execution_list.dart)
- **Class:** `ItemExecutionList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Renders per-item execution controls based on the item's transaction type (`tx` field):
- **deliver** (default): name, type chip (returnable/consumable), DROP stepper, PICKUP stepper (returnable only). Status state-machine: partial (amber), sesuai (emerald), opportunistic/extra (violet).
- **sale**: teal card with qty stepper (when `editConsumable` is true/absent) or static qty display (when false) + condition sub-label.
- **purchase**: teal card with qty stepper or static qty display + condition sub-label. Same `editConsumable` rule as sale.
- **refill**: read-only emerald card with static qty display + water sub-label. No stepper (deliberate deferral).

Items without a `tx` field (or `tx` empty) render as deliver for backward compatibility.

## Component JSON

```json
{"type":"ITEM_EXECUTION_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","itemsField":"it","labelField":"in","planDropField":"pd","planPickupField":"pp","txField":"tx","saleField":"ps","buyField":"pb","refillField":"pr","condOutField":"cdo","condInField":"cdi","waterField":"wt","text":"hint◆Drop◆Pickup◆partial◆complete◆opportunistic◆extra◆plan◆Returnable◆Consumable◆pickupHint◆Jual◆Jual ke customer◆Kepemilikan pindah · tanpa pickup◆Beli◆Beli dari customer◆Kepemilikan ke operator · naik ke kendaraan◆Refill◆Tukar galon customer◆Kosong masuk · isi keluar · galon milik customer◆Kosong◆Penuh◆RO◆Isi Ulang"}
```

### Config fields

| Field | Default | Description |
|-------|---------|-------------|
| vidtable | -- | App VID for table subscription |
| table | -- | Table path (parsed via parseTablePath) |
| search | -- | Filter expression for active task doc |
| itemsField | `it` | Item array key in task doc |
| labelField | `in` | Item name key |
| planDropField | `pd` | Planned drop qty key |
| planPickupField | `pp` | Planned pickup qty key |
| txField | `tx` | Transaction type key (deliver/sale/purchase/refill) |
| saleField | `ps` | Sale qty key |
| buyField | `pb` | Purchase qty key |
| refillField | `pr` | Refill qty key |
| condOutField | `cdo` | Outbound condition key |
| condInField | `cdi` | Inbound condition key |
| waterField | `wt` | Water type key |
| editDrop | `"true"` | Edit lock for **returnable** deliver rows. `"false"` (case-insensitive) removes +/- buttons and locks drop at seeded value (plan, or min(plan, cap) when `dropCapTable` is configured). Any other value or absent = editable (backward-compatible default). Pickup is gated separately by `editPickup`. Applies to the default (`fields`) variant only — `variant:pivot` renders custody-count slots and is unaffected. |
| editPickup | `"true"` | Edit lock for **returnable** pickup cells. `"false"` (case-insensitive) removes +/- buttons and locks pickup at seeded value (`ap` = `pp`). Pickup is never capped, so the lock always produces `ap` = `pp` exactly. Any other value or absent = editable (backward-compatible default). Consumable rows have no pickup cell — the flag is a silent no-op. Applies to the default (`fields`) variant only — `variant:pivot` renders custody-count slots and is unaffected. Locking pickup makes the **Opportunistic** and **Partial** pickup states unreachable (`_cellStatus` always returns `complete`); the cell permanently renders `✓ Sesuai`. This is why spec §2 defaults pickup to `TRUE` — the opportunistic empty-return count is only known at the customer site. |
| editConsumable | `"true"` | Edit lock for **consumable** rows. Governs: (a) non-returnable deliver rows (stepper hidden, actual = plan) and (b) sale/purchase cards (stepper shown when true, static qty frame when false). Same parse rule as `editDrop`. Refill is always static (no stepper regardless of this flag). Applies to the default (`fields`) variant only -- `variant:pivot` renders custody-count slots and is unaffected. **Edge case:** `putIfAbsent` seeds sale/buy once per session. A mid-session flip to `"false"` (requires page-JSON reload) leaves an already-adjusted entry at its driver-set value. Same property as `editDrop`. |
| saleCapSearch | `''` (no cap) | Search filter for **sale** stock cap. When non-empty, sale rows (`as`) are capped at the item's stock in the vehicle's `asset_cache`, mirroring `dropCap` for returnable drop. Example: `lv◼{vehicleId}⭘cd◼full`. `{vehicleId}` resolves from the task doc's `vehicleField` (default `vv`). Note: `cd` is fill-state (`empty`/`full`), NOT item category -- category lives in the `item` table's `ic` field, so sale and drop searches legitimately use the same `cd◼full` filter and are separated per-row by item id. Requires a cap-table subscription (`dropCapTable` or `saleCapTable`). Uses `saleCapKey` for item id, `saleCapField` for qty, `saleCapLabel` for status label (each with fallback chain -- see those rows). Absent/blank = no sale cap (backward-compatible default). |
| saleCapTable | `''` | Firestore table path for sale cap subscription. Activates the `_capCode` subscription when `dropCapTable` is blank, enabling sale cap for tenants that sell consumables but do no returnable drop. When BOTH `dropCapTable` and `saleCapTable` are non-blank, `dropCapTable` wins (the subscription is shared; precedence is deliberately opposite from `saleCapKey`/`saleCapField`/`saleCapLabel` where sale overrides drop). Resolved by `resolveCapTable`. |
| saleCapKey | `''` | Item id field for sale cap map lookup. Fallback: `dropCapKey` -> hard default `'ii'`. Resolved by `resolveCapFields`. |
| saleCapField | `''` | Quantity field for sale cap map lookup. Fallback: `dropCapField` -> hard default `'qt'`. Resolved by `resolveCapFields`. |
| saleCapLabel | `''` | Status label for capped sale rows. Fallback: `capLabel` -> hard default `'Maks <max>'`. `<max>` is replaced with the cap value at render time. Resolved by `resolveCapFields`. |
| `variant` | `"fields"` (default) or `"pivot"` | Structural variant. `fields` = existing behavior (1 record/item, field-pair steppers). `pivot` = N records/item grouped by `groupKey`, stepper per `pivotField` value. |

### Pivot-specific config (variant:"pivot")

| Field | Example | Description |
|-------|---------|-------------|
| `groupKey` | `ii` | Docs with same value in this field become one card |
| `pivotField` | `cd` | Discriminator field for pivoting docs into slots |
| `slots` | `full^Penuh~empty^Kosong` | `value^Label` pairs, `~`-separated. Order = stepper order. Labels are config-driven. |
| `valueField` | `qt` | Expected quantity field per slot |
| `writeField` | `ip` | Nominal write key (closing submit reads countStore directly) |
| `joinTable` | `84214220504259//item` | Table for item name + category JOIN |
| `joinKey` | `ii` | JOIN key field |

### Pivot text slots (diamondTextToList, 0-based)

| Index | Content | Default |
|-------|---------|---------|
| 0 | Hint caption | `''` |
| 1 | Plan label | `'Ekspektasi'` |
| 2 | Match label | `'✓ Sesuai'` |
| 3 | Mismatch template (`<delta>` replaced) | `'Selisih · <delta>'` |
| 4 | Returnable chip label | `'Returnable'` |
| 5 | Consumable chip label | `'Consumable'` |

### Submit integration (pivot)

The pivot path writes counted values to `CustodyCountList.countStore[scrName]`
keyed `'${ii}__${slotValue}'` as `CountEntry{ii, cd:slotValue, qty, planQty}`.
The existing `CUSTODY_COUNT_SUBMIT mode:closing` reads this store unchanged.

### Text slots (24, 0-based)

| Index | Label | Default |
|-------|-------|---------|
| 0 | hint caption | (empty) |
| 1 | Drop label | Drop |
| 2 | Pickup label | Pickup |
| 3 | partial template | Partial · N kurang |
| 4 | complete label | Sesuai |
| 5 | opportunistic template | Opportunistic · N |
| 6 | extra template | +N extra |
| 7 | plan label | plan |
| 8 | Returnable | Returnable |
| 9 | Consumable | Consumable |
| 10 | pickupHint | (empty) |
| 11 | sale chip | Jual |
| 12 | sale line | Jual ke customer |
| 13 | sale desc | Kepemilikan pindah · tanpa pickup |
| 14 | purchase chip | Beli |
| 15 | purchase line | Beli dari customer |
| 16 | purchase desc | Kepemilikan ke operator · naik ke kendaraan |
| 17 | refill chip | Refill |
| 18 | refill line | Tukar galon customer |
| 19 | refill desc | Kosong masuk · isi keluar · galon milik customer |
| 20 | condition kosong | Kosong |
| 21 | condition penuh | Penuh |
| 22 | water RO | RO |
| 23 | water isi ulang | Isi Ulang |

## Data Source

Same task table subscription as WorkspaceHeader. Extracts `it[]` array from the matched task doc.

## State store

`executionStore` is a plain `Map<String, Map<String, ExecutionEntry>>` keyed by `scrName` then item-index string. **Deliver**, **sale**, and **purchase** items seed the store. Sale/purchase entries reuse `dropActual`/`dropPlan` for their single qty (`pickupActual`/`pickupPlan` are 0). Refill items are stateless (no store entry; `ar` = `pr` always). NOT an RxMap. Reactivity via separate `RxInt executionRev` signal. Cleared per-NAV in `clearData` and in `buildPage` startup hook.

## Condition / water label mapping

Best-guess mapping (schema/CF not yet defined):
- Condition (`cdo`/`cdi`): `full` -> Penuh (slot 21), `empty` -> Kosong (slot 20), other -> raw value.
- Water (`wt`): `ro` -> RO (slot 22), other non-empty -> Isi Ulang (slot 23).

## DEFERRED

- SUBMIT_CONFIRM_SHEET per-tx recap (widget does not exist yet).
- All writes: movement CF, actual=plan auto-set, saveSend, history queue.
- Failed delivery sheet.
- Admin edit order UI (`TASK_EDIT_SUBMIT`, `TASK_ITEM_BUILDER` mode edit) -- separate workflow run.
- **Spec divergence (D2), SUPERSEDED:** Prior note said sale/purchase/refill are "already permanently read-only" and `editConsumable` governs only the consumable deliver row. This is now WRONG. As of round `item-execution-consumable-stepper`, sale and purchase rows have editable steppers when `editConsumable` is true (or absent). `editConsumable` governs: consumable deliver rows AND sale/purchase cards. Refill remains static.
- **Spec divergence (D3), restated as deferral:** Refill gets no stepper. The spec says refill "sementara ikut editDrop" but refill has no stepper to lock or unlock. `ar` = `pr` always. A separate refill stepper is a deliberate deferral -- add when the business requires adjustable refill quantities.

## Manual verification

| Scenario | Expected |
|----------|----------|
| `editPickup:"false"` | Pickup cell has no +/- buttons and is pinned at plan seed. `_cellStatus` returns `complete` always, so the **Opportunistic** (violet) and **Partial** (amber) pickup states are unreachable — the cell permanently renders `✓ Sesuai`. `ap` == `pp` on submit. Drop and consumable rows are unaffected. |
| All three keys absent | All steppers present and editable: deliver drop/pickup, sale, purchase. Refill stays static. Byte-identical to the new default behavior. |
| `editConsumable:"false"` | Sale and purchase cards show static qty frame (no stepper). Consumable deliver row locked. Returnable rows unaffected. On submit: `ab`=`pb`; `as`=`ps` **unless `saleCapSearch` is active**, in which case `as`=`min(ps, stock)` -- cap wins over lock (D5, same contract as `ad` < `pd` under drop lock + cap). |
| `editConsumable:"true"` (or absent) | Sale and purchase cards show `- [n] +` stepper. Driver can adjust qty. Status line shows `✓ Sesuai` when actual == plan, `Partial` when under, `+N extra` when over. On submit: `as`/`ab` = driver-adjusted value (capped at vehicle stock when `saleCapSearch` is active). |
| Sale stepper + driver changes qty | Tap `+` on a sale card: value increments, status updates. Tap `-`: value decrements (min 0). Submit writes the adjusted value to `as`. |
| Refill row (any flag combo) | Always static. No stepper regardless of `editConsumable`. `ar` = `pr` on submit. |
| `editConsumable:"false"` + `editDrop:"false"` | All consumable rows locked (sale, purchase, consumable deliver). Returnable drop also locked. Pickup editable. |
| Sale stepper sub-label | Condition badge (Penuh/Kosong) appears below the stepper (deliberate: stepper is full-width), not beside it as in the static frame. |
| `saleCapSearch` set + item stock < plan | Sale stepper shows stock as max. `[+]` dead at stock. Orange "Maks N" status line. Submit writes `as` = stock. |
| `saleCapSearch` set + item stock >= plan | Sale stepper at plan. `[+]` enabled beyond plan (up to stock). No cap label unless `actual == stock`. |
| `saleCapSearch` set + item NOT in asset_cache | Sale stepper dead at 0. Cap 0 (D4). |
| `saleCapSearch` blank/absent | No sale cap. Sale stepper freely adjustable. Byte-identical to pre-change behavior. |
| `saleCapSearch` set + both `dropCapTable` and `saleCapTable` absent | No sale cap (`saleCapSearch` requires a cap-table subscription from either param). |
| `saleCapSearch` set + `editConsumable:"false"` | Static qty frame shows plan. Submit writes `min(ps, stock)`. |
| Purchase row with `saleCapSearch` active | Purchase stepper uncapped. `[+]` enabled. D3 holds. |

### Edge cases

- **Mid-session `editConsumable` flip:** `putIfAbsent` seeds sale/buy once per session. If the config changes to `"false"` mid-session (requires page-JSON reload/proxy refresh), an already-adjusted entry retains its driver-set value, so `as` may differ from `ps`. Same behaviour as `editDrop` with deliver rows. Extremely unlikely in practice.
- **Wrong `cd` value in `saleCapSearch`:** if `saleCapSearch` filters to zero matching docs, every sale row gets cap 0 (item missing from map = `saleCapMap[ii] ?? 0`). Every sale stepper is dead at 0 and the driver cannot sell anything. Fix: blank `saleCapSearch` to disable sale cap entirely, or correct the filter value (the `saleCapSearch` config row documents the correct `cd◼full` example). The blast radius is intentional -- a wrong search is worse than no cap.
- **`editConsumable:"false"` + `saleCapSearch` active:** cap wins. The sale row seeds at `min(ps, stock)`, so `as` can be `< ps` on submit. The static frame displays plan (`ps`), but the submitted value is the capped seed. Same contract as `editDrop:"false"` + `dropCap` where `ad` can be `< pd`. Reconciled by admin.

## See Also

- [custody_count_list.md](custody_count_list.md) -- P6 count list (same store pattern)
- [vehicle_cargo_summary.md](vehicle_cargo_summary.md) -- P12 cargo (same best-guess field pattern)
