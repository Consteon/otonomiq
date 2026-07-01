# Warehouse Runtime (Vehicle Runtime) — DEV HANDOFF (kirim ini ke dev)

**Apa ini:** sisi **gudang/checker** dari Driver Runtime — bukan fitur terpisah. Dia **memproduksi** `vehicle_check` opening (`ie[]`/`gv`/`gn`/`ldt`) + designate driver (`stock_location.dv`) yang selama ini di-hand-seed buat driver custody (P5/P6), dan **memvalidasi** hasil rute (closing reconcile). 0 collection baru; **+1 field denorm `dn`**.

**Konteks config:** H1/O1/C1/R1/R2 **config sheet SEMUA udah live** (op1Screen 1101/1106/1120/1132/1138). Renderer 4 page warehouse udah dev build (review-clean). Yang dev kerjain = on-device QA + fix di bawah + CF (§C).

---

## ⚠️ UPDATE 2026-06-25 — AS-BUILT delta + keputusan executor designate

Bagian A/B/C/D di bawah ditulis **SEBELUM** dev build → sebagian STALE. AS-BUILT (SSOT = `warehouse-runtime-feedback.md`):
- Submit = **`createNativeDoc`** one-shot (scalar+array sekaligus), **BUKAN** `addToEvent`+native split (A4 salah — addToEvent void/async → array di-query sebelum doc ada → race → array ilang).
- Designate = **`executor_designate_card`** (kartu amber + sheet picker), **BUKAN** `searchFromTableConsteon` (A3/D-O2 stale).
- Masih bener: schema `dn` (B), tier logic (A5), handshake.

### Keputusan designate (FINAL): KEEP `executor_designate_card`
Sempet ditimbang ganti ke `searchFromTableConsteon` (capture `◁N▷` position) / picker baru → **DITOLAK**. Alasan: kartu token-based (`{chosenVid}`+`{chosenName}`) pas ke keyed write `…⭘search◼lv★{vehicleId}⭘dv◼{chosenVid}⭘dn◼{chosenName}` — nangkep **vid + nama sekaligus**, udah dibangun. searchFromTableConsteon cuma capture vid (nama jadi lookup PR). **JANGAN switch. Capture tetap token.** Live submit D1117 udah bener.

### 2 fix di `executor_designate_card` (kecil, bukan redesign)
1. **Click nama di sheet (O2) gak ke-select** — tap baris driver gak ada efek. Fix select handler renderer sheet. (test 2026-06-25 11:24)
2. **Sheet munculin tenant/system row** ("Autsorz / ? / Agenia Demo-7"), bukan driver — query `workforce` TANPA filter → ketarik semua. Fix:
   - **Tambah param filter** ke `executor_designate_card` (cth `workforceSearch:"<key>◼<staff>"`) + renderer apply ke query. Begitu field-nya ada, isi config-nya tinggal 1 cell.
   - **DATA prereq:** driver demo (Budi/Dirgahayu/Anton di `Master_Driver`) harus ADA di collection `workforce` yang di-query picker. Sekarang seeder **TIDAK** seed workforce (cuma item/stock_location/task/vehicle_check/movement) → driver demo kemungkinan gak ada di workforce. Verify; kalau kosong → seed `Master_Driver`→`workforce` atau pakai employee existing. **Verify field role/jabatan workforce** (Master_Driver pakai `role`; live tampil `Position <5>`) buat nentuin filter value.

---

**Start here (urut):**
1. `docs/consteon-runtime-knowledge-base.md` — arsitektur op1Screen + DSL token + data model.
2. `docs/driver-runtime-field-dictionary.md` — semua field (Warehouse pakai collection driver yang SAMA).
3. Per-page: `docs/vehicle-feed-h1-dev-spec.md`, `docs/warehouse-opening-check-o1-dev-spec.md`, `docs/warehouse-closing-check-c1-dev-spec.md`.

Handshake lengkap (siapa nulis apa):
```
GUDANG opening (O1) → muat, count ie[], designate driver (dv/dn), gv/gn/ldt, cst=awaiting_custody   [vehicle_check opening]
DRIVER custody P5/6 → count ip[], reveal vs ie[], confirm → cst=custody_confirmed
DRIVER rute P10/11  → movement DROP/PICKUP
DRIVER return P12   → serah ke gudang; driver SELESAI
GUDANG closing (C1) → count fisik turun = ip[] vs expected ie[] → R1 match=approve / R2 selisih=eskalasi   [vehicle_check closing]
```

---

## A. RENDERER (Flutter)

### A1. Type BARU — bangun dari nol (2)
| type | page | spec | catatan |
|---|---|---|---|
| `VEHICLE_FEED_HEADER` | H1 | h1 §1 | identitas checker (`workforce.n` via `VID◼{checkerVid}`) + 3 snapshot count (Perlu Tindakan / Opening Check / Hari Ini). Config live @ Widget 229. |
| `VEHICLE_FEED_LIST` | H1 | h1 §2–3 | feed kendaraan tier-grouped + kartu (plat `ln`, executor `dn`, state-action). **Tier = composite gate** (A5). Config live @ Widget 230. |

### A2. Variant/extension dari type driver EXISTING
| type | dari | extension | spec |
|---|---|---|---|
| `CUSTODY_COUNT_LIST` | driver P6 (Widget 209) | **O1 variant**: `blind:false` (tampil plan), source = `task` aggregate (`Σ pd+ps+pr`, exclude `load_rejected`/purchase), `writeField:ie`, full-only, `groupBy` ic. **C1 variant**: source = `asset_cache` (`lv◼{vehicleId}`), `writeField:ip`, full+empty. | o1 §4, c1 §2 |
| `TASK_MANIFEST_LIST` | driver P5 (Widget 207) | +`hideQty` +`collapsible` (LoadOrigin: task list tanpa qty) | o1 §5 |

### A3. Reuse APA ADANYA (udah ada / udah di-spec driver)
- **`searchFromTableConsteon`** (Widget 156, EXISTING) — designate+pick pengemudi: search `workforce` → capture **vid** di `[POSITION]` → `dv`. Ganti executor card + picker sheet sekaligus. (o1 §2)
- `WORKSPACE_HEADER` (225), `NOTICE_BAR` (199), `3LineBorderForm`/`TXF` (88), `SUBMIT_CONFIRM_SHEET` (202), `CUSTODY_CONFIRMED_LIST` (214), `CUSTODY_DISCREPANCY_LIST` (215), `sendButtonGpsWithEvent` (192).

### A4. Submit = send-button multi-write (per page)
Array (`ie`/`ip`/`dp`) = **native Flutter write** (DSL gak support array — sama aturan driver P6). Scalar + create = DSL (`addToEvent`/`updateEventRow`).
- **O1 submit:** (1) `addToEvent` create opening `vehicle_check` (`cnm`/`cty◼opening`/`vv`/`gl`/`cdt`/`cst◼awaiting_custody`/`gv`/`gn`/`ldt`); (2) native `ie[]`; (3) `updateEventRow` `stock_location` designate `dv`/`dn`. (o1 §6)
- **C1 submit:** (1) `addToEvent` create closing doc; (2) native `ip[]`; (3) reconcile → native `dp[]` + `rs`; (4) `updateEventRow` opening `cst◼closed`; (5) R2: `addToEvent` `investigation` (`vst◼pending_review`). (c1 §4)

### A5. H1 tier derivation (logic penting — composite, bukan 1 field)
Sinyal "belum di-assign" = `stock_location.dv` kosong → tier **loading**, **TANPA filter tanggal** (backlog persist). Sisanya: `vehicle_check.cst` (3-nilai) + opening/closing doc existence + `task.tst` rollup. Detail tabel: h1 §3.

**Token runtime:** `{checkerVid}` `{vehicleId}`/`{lv}` `{today}` `{warehouseId}` `{chosenVid}`/`{chosenName}` `{openingCnm}` + generated `cnm`. (mekanik inject = ikut driver session.)

---

## B. Schema delta (cuma 1)
- **`dn`** (driver name) di **`stock_location`** — denorm, di-set bareng `dv` pas O1 designate. **Reuse code `dn`** (= driver name di `movement`; fungsi sama → no collision, sesuai aturan dict). Hindari N+1 lookup workforce di feed list. Tambah ke dict tab `stock_location`.

Sisanya pakai field driver existing: `vehicle_check` (`cnm cty cst vv gl cdt ie ip rs dp gv gn ldt`), `stock_location` (`lv lt ln dv` +`dn`), `task` (`tst it[] pd ps pr`), `asset_cache` (`lv ii cd qt`), `workforce` (`VID n`), `investigation` (`vnm vst vrf vpt`).

---

## C. CF / movement (POINTER — track Go terpisah, JANGAN di-detail di sini)
- **Expected closing** = `asset_cache` saldo mobil (`lv◼{vehicleId}`, full+empty) = loaded − dropped + picked, CF-derived. Sampe CF live → hand-seed (udah ada baris asset_cache mobil di seed).
- **P12↔C1 INTERNAL movement** (mobil→gudang) = diturunkan dari `ip` counted gudang (truth). Siapa emit (C1 / CF) = **OPEN, track movement/CF**. Mekanik CF = `docs/driver-runtime-movement-cf-handoff.md`.

---

## D. Status + reuse map
| page | route | config sheet | renderer |
|---|---|---|---|
| H1 Feed | `…WarehouseFeed` (1101) | ✅ LIVE | ⬜ 2 type baru (A1) |
| O1 Opening | `…WarehouseOpeningCheck` | ⬜ pending | ⬜ CUSTODY_COUNT_LIST O1-variant + multi-write + reuse |
| O2 Picker | (in O1) | — | ✅ searchFromTableConsteon ada (wire) |
| C1 Closing | `…WarehouseClosingCheck` | ⬜ pending | ⬜ CUSTODY_COUNT_LIST C1-variant + reconcile multi-write |
| R1/R2 Result | `…WarehouseClosingResult` | ⬜ pending | ⬜ reuse CUSTODY_CONFIRMED/DISCREPANCY_LIST |

**Net widget baru seluruh fitur: 2** (`VEHICLE_FEED_HEADER`, `VEHICLE_FEED_LIST`). Sisanya variant-flag atau reuse.

**Open (konfirmasi sebelum/saat build):** `{warehouseId}` source (sesi vs task `gl`); closing blind atau visible (mock visible); `searchFromTableConsteon` `com:"auz"` tenant routing; P12↔C1 INTERNAL emitter (§C).
