# ITEM_EXECUTION_LIST — `variant` field (`fields` | `pivot`)

**Buat:** Flutter dev. Nambahin field `variant` ke widget `ITEM_EXECUTION_LIST` (Widget tab row 219) biar 1 widget bisa dipake banyak case (bukan cuma driver delivery). Nama variant **struktural / global** — gak boleh feature-bound (`closing`/`driver` dilarang) karena widget reusable di case apapun.

**Precedent:** `ROUTE_PROGRESS_HEADER` udah punya `variant:"full"`. `VEHICLE_CARGO_SUMMARY` (D1081 ReturnVehicle) udah pivot `asset_cache` by `cd` (`condField`/`fullValue`/`emptyValue`) — vocab pivot di bawah ngikut itu.

---

## 0. Kenapa

- Sekarang widget cuma 1 bentuk: stepper per item dari **field-pair di SATU record** (`task.it[]` line: `pd→ad` Drop, `pp→ap` Pickup, dst). Belum ada `variant`.
- C1 ClosingCheck butuh **card visual yang SAMA** (nama item sekali, stepper di dalem) tapi datanya beda: `asset_cache`, **2 doc per item** (`cd:full` + `cd:empty`) → 2 stepper Penuh/Kosong.
- Sekarang C1 pake `CUSTODY_COUNT_LIST` → render **2 card nama kembar** (`condField:cd` ke-render per-doc) → bikin bingung user.
- Solusi: reuse `ITEM_EXECUTION_LIST` + variant baru `pivot`. Gak bikin widget baru.

---

## 1. Field baru: `variant`

| value | bentuk data | stepper sumbernya | case |
|---|---|---|---|
| `fields` (DEFAULT) | **1 record / item** (`itemsField` array line) | tiap stepper = 1 field-pair (`planX`/`actualX`) yg di-config | driver delivery (existing) |
| `pivot` | **N record / item** (group by `groupKey`) | 1 `valueField`, di-split jadi stepper per nilai distinct `pivotField` | closing Penuh/Kosong, + case kategori apapun |

**Back-compat WAJIB:** `variant` absent → treat as `fields`. Semua page live existing (DeliveryWorkspace dll) GAK di-edit; tetep jalan tanpa nulis `variant`. Retrofit `"variant":"fields"` ke template = opsional, cuma biar eksplisit.

---

## 2. Variant `fields` (EXISTING — retrofit, ZERO perubahan behavior)

Behavior persis sekarang. Stepper = field-pair di config: Drop (`planDropField`/`actualDropField`), Pickup (`planPickupField`/`actualPickupField`), Sale (`saleField`/`actualSaleField`), Buy (`buyField`/`actualBuyField`), Refill (`refillField`/`actualRefillField`). Data 1 record per item dari `itemsField`.

**Resolved JSON LIVE (DeliveryWorkspace D1072) — cuma nambah `"variant":"fields"`:**

```json
{"type":"ITEM_EXECUTION_LIST","variant":"fields","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","itemsField":"it","labelField":"in","planDropField":"pd","actualDropField":"ad","planPickupField":"pp","actualPickupField":"ap","txField":"tx","saleField":"ps","actualSaleField":"as","buyField":"pb","actualBuyField":"ab","refillField":"pr","actualRefillField":"ar","condOutField":"cdo","condInField":"cdi","waterField":"wt","dropCapTable":"84214220504259//asset_cache","dropCapSearch":"lv◼{vehicleId}⭘cd◼full","dropCapKey":"ii","dropCapField":"qt","capLabel":"Maks <max> — stok mobil","text":"…(text ◆-segments existing, gak berubah)…"}
```

---

## 3. Variant `pivot` (BARU — closing & sembarang kategori)

Group record by `groupKey` → 1 card per item. `valueField` di-pivot jadi N stepper, satu per nilai distinct `pivotField` yang didaftar di `slots`. Nama item ditampilin SEKALI (dari `labelField` via `joinTable`); stepper di-label dari `slots`. Bunuh masalah "card nama kembar".

### Config keys (`pivot`)

| key | isi | catatan |
|---|---|---|
| `variant` | `pivot` | |
| `table` | `84214220504259//asset_cache` | sumber saldo mobil |
| `search` | `lv◼{activeVehicle}` | **`{activeVehicle}`**, BUKAN `{vehicleId}` (token resolver) |
| `groupKey` | `ii` | record dengan `ii` sama → 1 card |
| `pivotField` | `cd` | discriminator (full/empty). Generic — bisa field kategori apapun |
| `slots` | `full^Penuh~empty^Kosong` | `value^Label`, `~`-sep. Urutan = urutan stepper. Label config-driven (gak hardcode di Flutter) |
| `valueField` | `qt` | ekspektasi per slot |
| `writeField` | `ip` | form-state key; count aktual ke-collect per (`ii`,`pivotValue`); submit baca utk rakit `ip[]` `[{ii,cd,qt}]` |
| `joinTable` | `84214220504259//item` | |
| `joinKey` | `ii` | |
| `labelField` | `in` | nama item (ditampilin sekali per card) |
| `catField` | `ic` | badge Returnable/Consumable |
| `text` | ◆-segments | semua label UI (header, ✓ Sesuai, kata "Ekspektasi", selisih, dll) |

### Resolved JSON — C1 ClosingCheck (REAL, siap tulis)

```json
{"type":"ITEM_EXECUTION_LIST","variant":"pivot","vidtable":"20342033315492","table":"84214220504259//asset_cache","search":"lv◼{activeVehicle}","groupKey":"ii","pivotField":"cd","slots":"full^Penuh~empty^Kosong","valueField":"qt","writeField":"ip","joinTable":"84214220504259//item","joinKey":"ii","labelField":"in","catField":"ic","text":"Hitung fisik turun dari mobil◆Ekspektasi◆✓ Sesuai◆Selisih · <delta>◆Returnable◆Consumable"}
```

### Mapping driver→closing (visual sama, data beda)

| `fields` (delivery) | `pivot` (closing) |
|---|---|
| DROP / PICKUP | PENUH / KOSONG (dari `slots`) |
| plan `pd`/`pp` | Ekspektasi `qt` @ `cd:full` / `cd:empty` |
| 1 doc, 2 field | 2 doc, group by `ii` |
| tulis `ad`/`ap` inline | tulis `ip[]` `[{ii,cd,qt}]` (via submit) |
| ✓ Sesuai / selisih | sama |

---

## 4. Integrasi submit (C1)

Pas C1 swap `CUSTODY_COUNT_LIST`→`ITEM_EXECUTION_LIST(pivot)`, count aktual mesti ke-collect ke form-state yg SAMA yg dibaca `CUSTODY_COUNT_SUBMIT mode:closing` (rakit `ip[]` + reconcile `dp[]` vs ekspektasi `asset_cache`). `writeField:ip` = kontrak key-nya. Submit widget GAK berubah.

---

## 5. Sequencing — JANGAN pre-stage config

1. Dev build renderer: `variant` dispatch + varian `pivot` (group/pivot/slots/write `ip[]`).
2. **BARU** swap live config C1 D1125 `CUSTODY_COUNT_LIST`→JSON §3. Sebelum renderer support = widget DROP/blank (pelajaran `config-ahead-of-renderer`: field token-bearing `{activeVehicle}`/`◼` ke widget live tanpa renderer = app buang widget).
3. Variant `fields`: back-compat, gak perlu pre-edit page live.
4. Ship config + renderer **1 PR**. Verify di device langsung abis edit live-sheet.

**Status:** C1 live SEKARANG tetep `CUSTODY_COUNT_LIST` (2-row, jalan). Spec ini buat dev build varian dulu; swap nyusul.
