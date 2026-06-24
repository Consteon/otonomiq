# ItemExecutionList

Per-item execution list for P11 DeliveryWorkspace. Supports four transaction types: deliver (editable steppers), sale, purchase, refill (read-only cards).

- **File:** [lib/widget/item_execution_list.dart](../../lib/widget/item_execution_list.dart)
- **Class:** `ItemExecutionList` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Renders per-item execution controls based on the item's transaction type (`tx` field):
- **deliver** (default): name, type chip (returnable/consumable), DROP stepper, PICKUP stepper (returnable only). Status state-machine: partial (amber), sesuai (emerald), opportunistic/extra (violet).
- **sale**: read-only teal card with qty display + condition sub-label.
- **purchase**: read-only teal card with qty display + condition sub-label.
- **refill**: read-only emerald card with qty display + water sub-label.

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

`executionStore` is a plain `Map<String, Map<String, ExecutionEntry>>` keyed by `scrName` then item-index string. Only **deliver** items seed the store. Sale/purchase/refill items are stateless (read-only). NOT an RxMap. Reactivity via separate `RxInt executionRev` signal. Cleared per-NAV in `clearData` and in `buildPage` startup hook.

## Condition / water label mapping

Best-guess mapping (schema/CF not yet defined):
- Condition (`cdo`/`cdi`): `full` -> Penuh (slot 21), `empty` -> Kosong (slot 20), other -> raw value.
- Water (`wt`): `ro` -> RO (slot 22), other non-empty -> Isi Ulang (slot 23).

## DEFERRED

- SUBMIT_CONFIRM_SHEET per-tx recap (widget does not exist yet).
- All writes: movement CF, actual=plan auto-set, saveSend, history queue.
- Failed delivery sheet.

## See Also

- [custody_count_list.md](custody_count_list.md) -- P6 count list (same store pattern)
- [vehicle_cargo_summary.md](vehicle_cargo_summary.md) -- P12 cargo (same best-guess field pattern)
