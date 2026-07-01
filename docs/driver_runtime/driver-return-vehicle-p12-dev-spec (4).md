# P12 ReturnVehicle — Dev Spec

**Buat:** Flutter dev. P12 = akhir hari, driver serahkan kendaraan + sisa muatan ke gudang. Route `vertikaTeknoLokaciptaReturnVehicle`. Grounded mockup `src/component/Driverruntimefull.jsx` — `ReturnScreen`(3597), `deriveCargo`(3279).

**Flow:** P10 TaskFeed allDone → "Kembali ke Gudang" → **P12 ReturnVehicle** → "Serahkan ke Gudang" → handover gudang → sesi auto-close (logout terminal).

**Doctrine (penting):** driver CUMA serahkan. **Reconciliation/validasi = domain gudang (Vehicle Runtime), BUKAN driver.** Gudang yang hitung & confirm return → baru sesi ketutup + `cst=closed`.

---

## STATUS — display shell (data + write DEFERRED)
- **Cargo "Sisa di Kendaraan"** = `asset_cache` (CF-derived vehicle stock). CF belum ada (movement/CF deferred) → card render struktur, value nunggu CF. `deriveCargo` mockup recompute dari task `it[]` (loaded−drop, pickup) krn prototype; runtime REAL baca `asset_cache`.
- **Submit "Serahkan ke Gudang"** = savesend set **`rt◼returned`** (handover marker) di opening `vehicle_check` + dialog feedback → route DriverHome. **`cst` TETEP `custody_confirmed`** (cst locked 3 nilai; gudang yang set `closed`). **BUILT 2026-06-24** (config live D1084). Logout pas `cst=closed` = renderer behavior (deferred).

---

## Widget (dedicated, match mockup) — Widget tab

| widget | type | row | render |
|---|---|---|---|
| `returnHeader` | `RETURN_HEADER` | 227 | header |
| `vehicleCargoSummary` | `VEHICLE_CARGO_SUMMARY` | 228 | intro + cargo card (per-item, §2 revisi) |
| `circulationSummary` | `CIRCULATION_SUMMARY` | 208 (REUSE) | total Jual/Tukar/Beli + Drop/Pickup hari ini |

> op1Screen pakai **literal D-cell** (bukan VLOOKUP) → resolve tanpa nunggu drag col A/G/H. Registry Widget I+J tetep diisi (reference dev).

### 1. `RETURN_HEADER` (mockup 3601-3610)
Header: back `←`→`backRoute` (DriverHome) + label uppercase "Akhir Hari" + title "Return Kendaraan". text 2 seg.
```json
{"type":"RETURN_HEADER","backRoute":"vertikaTeknoLokaciptaDriverHome","text":"Akhir Hari◆Return Kendaraan"}
```

### 2. `VEHICLE_CARGO_SUMMARY` (mockup 3612-3623 — REVISI per-item 2026-06-24)
- intro: "Serahkan kendaraan **{plate}** + sisa muatan ke gudang. Gudang yang hitung & validasi (reconciliation = domain Vehicle Runtime)." — plate = `stock_location.ln` (`lv◼{vehicleId}`).
- card "Sisa di Kendaraan" — **list PER-ITEM** (revisi; mockup lama 4-bucket Tabung/Galon di-DROP). Source = `asset_cache` (vehicle) **di-join ke `item`** (`ii`→nama+satuan).
  - **group by `ii`** → 1 baris per item. Header = nama item **`item.in`** (BUKAN `ii` mentah).
  - breakdown per kondisi `cd`: **"{un} isi {qty}"** (cd=`full`) + **"{un} kosong {qty}"** (cd=`empty`). `un` = **`item.un`** (satuan) per item → "Tabung"/"Galon"/"Karton" otomatis. **JANGAN hardcode "Tabung"** — salah buat galon/karton.
  - qty = `asset_cache.qt` per (ii, cd). Boleh sembunyiin kondisi yang qty 0 / kondisi yg gak ada di `item.tc` (hideZero opsional).

⚠️ **Renderer live SALAH** (gambar 2026-06-24): nampil per-item TAPI (a) `ii` mentah (`2000000000031`) bukan nama, (b) label **"Tabung isi/kosong" hardcoded** (galon pun ketulis "Tabung"). Fix = join `item` + pakai `un`. Sama pola join kayak `INVENTORY_BUCKET_CARD` (yg udah bener nampil nama via `itemTable`).

```json
{"type":"VEHICLE_CARGO_SUMMARY","vidtable":"20342033315492","vehicleTable":"84214220504259//stock_location","vehicleSearch":"lv◼{vehicleId}","plateField":"ln","cacheTable":"84214220504259//asset_cache","cacheSearch":"lv◼{vehicleId}","itemTable":"84214220504259//item","itemKey":"ii","nameField":"in","unitField":"un","condField":"cd","fullValue":"full","emptyValue":"empty","text":"Serahkan kendaraan◆ + sisa muatan ke gudang. Gudang yang hitung & validasi (reconciliation = domain Vehicle Runtime).◆Sisa di Kendaraan◆isi◆kosong"}
```
text 5 seg: introA◆introB◆cardTitle◆isiLabel◆kosongLabel. Renderer susun `"{un} {isiLabel} {qty}"`.
Join: `itemTable`/`itemKey`(ii)/`nameField`(in)/`unitField`(un); `condField`=cd, `fullValue`/`emptyValue` map cd→isi/kosong. `item` schema: `{ii,in,ic,tc,un,ist}` (`ic`=kategori, `un`=satuan, `tc`=kondisi array).

---

### 3. `CIRCULATION_SUMMARY` (flow Drop/Pickup/Jual/Tukar/Beli) — ADDED 2026-06-24
Aktivitas/flow hari ini (BUKAN stok). Beda dari "Sisa di Kendaraan" (stok fisik). Baca `task.it[]` per tx, `excludeStatus:load_rejected`. Header baris = nama item = `task.it[].in` (denorm, udah ADA di it[]).

✅ **DONE (2026-06-24): renderer Opsi A per-item tx-driven LIVE** + config diisi di return (1082) & custody (1016). Item sale→Jual, purchase→Beli muncul. Label dari `text` ◆-seg (config-driven). Mockup `Driverruntimefull.jsx` 2279 (3 kolom Muat/Drop/Pickup) = prototype lama, SUPERSEDED.
- Data **CONFIRMED ada jual+beli** (Firebase otq-01, task `i89dddJsDN3q94bw4lnZ`, 2026-06-24): it[0] Amidis tx=`deliver` pd=3/pp=3; it[1] Aqua 600ml tx=`sale` **ps=8** (jual); it[2] LPG 12kg tx=`purchase` **pb=5** (beli). Data SIAP — begitu kolom Jual/Beli dirender langsung muncul. Renderer current ignore ps/pb → **item sale/purchase nampil 0/0/0** (kebukti di app: Aqua600 & LPG12kg semua 0).
- Idealnya angka = ACTUAL (`ad`/`ap`, CF-derived) bukan plan; CF off → pakai plan (`pd/ps/pr/pb`), oke krn task done. Doctrine: display recap, validasi domain gudang.

**Opsi A — WAJIB BUILD (per-item tx-driven, owner pilih 2026-06-24):** tiap baris item nampil metric **sesuai `tx`-nya** (bukan paksa semua ke Drop/Pickup → item sale/purchase gak lagi 0/0/0):

| `tx` | label (dari text seg) | field |
|---|---|---|
| `deliver` | Drop + Pickup | `pd` + `pp` |
| `sale` | Jual | `ps` |
| `refill` | Tukar | `pr` |
| `purchase` | Beli | `pb` |

Header baris = nama item = **`task.it[].in`** (denorm — udah ADA di it[], lihat Firebase: `in:"Amidis Galon 19 Liter"` → TANPA join `item`).

⚠️ **Label WAJIB dari `text` ◆-segment, JANGAN hardcode di renderer** (owner atur kata sendiri). Mockup (`Driverruntimefull.jsx` 2285) hardcode "↓ Drop"/"↑ Pickup" — itu prototype; renderer PRODUKSI baca label dari segment by index. Layout text Opsi A (7 seg):
```json
{"type":"CIRCULATION_SUMMARY","vidtable":"20342033315492","table":"84214220504259//task","search":"vv◼{vehicleId}⭘tdt◼{today}","itemsField":"it","nameField":"in","txField":"tx","dropField":"pd","pickupField":"pp","saleField":"ps","refillField":"pr","buyField":"pb","excludeStatus":"load_rejected","text":"Total Circulation◆Drop◆Pickup◆Jual◆Tukar◆Beli◆Sirkulasi barang hari ini per tujuan."}
```
seg: `title◆Drop◆Pickup◆Jual◆Tukar◆Beli◆caption`. Owner reword seg 1-6 sesuai bahasa. Footer total opsional (tambah seg kalau perlu).
⚠️ Config sama dipakai **CustodyNotification (1016)** — owner update layout di KEDUA page bareng **pas renderer Opsi A udah live** (parse-by-index konsisten). Config live SEKARANG masih layout lama (Muat/Drop/Pickup) — **JANGAN diubah sebelum renderer Opsi A jadi** (kalau diubah duluan → label garbled di renderer lama).

**Status build (2026-06-24):** §2 VEHICLE_CARGO_SUMMARY = DONE (config live). §3 CIRCULATION_SUMMARY Opsi A = DONE (renderer live + config diisi return 1082 + custody 1016). Dua-duanya jalan.

---

## op1Screen — P12 page @1079 (`vertikaTeknoLokaciptaReturnVehicle`)
5 children (literal D) — **circulationSummary disisipin antara cargo & notice 2026-06-24**:
| row | widget | catatan |
|---|---|---|
| 1080 | `returnHeader` (`RETURN_HEADER`) | back + Akhir Hari / Return Kendaraan |
| 1081 | `vehicleCargoSummary` (`VEHICLE_CARGO_SUMMARY`) | intro + Sisa di Kendaraan (asset_cache per-item, §2 revisi) |
| 1082 | `circulationSummary` (`CIRCULATION_SUMMARY`) | **REUSE** widget 208 — Jual/Tukar/Beli + Drop/Pickup (flow, exclude load_rejected) |
| 1083 | `NOTICE_BAR` info | "Setelah gudang konfirmasi return, sesi lo otomatis ketutup (logout terminal)." |
| 1084 | `RBT` savesend | "Serahkan ke Gudang →" → set `rt◼returned` (handover) + dialog → route DriverHome. cst gak disentuh. Logout pas cst=closed (gudang) = renderer (deferred) |

> ⚠️ Col E = header-arrayformula (auto `,{D}` gated F=TRUE). Nambah/geser widget row: tulis **B+D+F=TRUE** doang, **JANGAN tulis col E** (literal-D page pun col E tetep arrayformula). Sisa 1 buffer (1085).

---

## OPEN (jangan invent)
1. **`asset_cache` schema** = `{lv, lt, ii, cd, qt}` — **NO nama/satuan** → WAJIB join `item` (ii→`in`/`un`/`ic`). Per-item (group by ii), kondisi dari `cd`. Bucket 4-baris lama DI-DROP (lihat §2 revisi). `un` satuan = label pengganti "Tabung" hardcoded. **Verifikasi `un` di `Master_Item` keisi tampil** (Tabung/Galon/Karton); kalau kosong → isi dulu, jangan tebak dari nama.
2. **CF dependency** — asset_cache value nunggu movement-CF (deferred). Spec CF `driver-runtime-movement-cf-handoff.md`.
3. **Handover write** — ✅ RESOLVED 2026-06-24. Sinyal = field **`rt`** (return status) di `vehicle_check`: **`pending`** (default, di-seed) → **`returned`** (driver "Serahkan"). BUKAN `cst` (cst locked 3 nilai; nambah value bakal break gate `cst◼custody_confirmed`). Driver savesend set `rt◼returned`. Gudang H1 baca `rt=returned` (cst masih confirmed, closing belum ada) → C1 closing → `cst=closed`. Config: D1084 savesend `updateEventRow vehicle_check (cty★opening☆vv☆cdt) rt◼returned` + chain DO_DIALOG.
   - **Hide entry-point ReturnVehicle abis handover** (biar driver gak re-serahin):
     - `navActionCard` (DriverHome, D1014) = ✅ DONE config — gateSearch `…⭘rt◼pending` (gate KOSONG pas rt=returned → HIDDEN, sesuai mekanisme gate). Butuh `rt:pending` di-seed (sudah di `buildVehicleCheckOpen`).
     - `taskFeedList` "Kembali ke Gudang" (TaskFeed) = **DEV WAJIB** (owner: button HARUS hilang abis return — jangan bisa re-return). CTA internal renderer (state all-stop-done), **NO gateField** → 2 cara:
       - **(a) rekomendasi** — dev tambah **gate ke return-CTA** TASK_FEED_LIST (mirror navActionCard `gateTable`+`gateSearch`, field baru mis. `returnGateTable`/`returnGateSearch`) → owner config `returnGateSearch:"cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}⭘rt◼pending"` (no-match → CTA HIDDEN). Owner-controlled, konsisten navActionCard.
       - **(b)** dev hardcode suppress CTA kalau `rt=returned`. Cepet, kurang fleksibel.
       (handover idempotent → bukan data-bug, tapi owner mau UX bersih gak bisa re-return.)
     - ReturnVehicle RBT sendiri = feedback via dialog (cukup); persistent button-hide opsional (RBT belum support gate).
   - **Logout** pas `cst=closed` (gudang konfirmasi) = renderer behavior.
   - **Dict:** field `rt` di tab `vehicle_check` (FREE), values `pending|returned`.
4. **Type baru** (`RETURN_HEADER`/`VEHICLE_CARGO_SUMMARY`) butuh renderer build dev-side. ⚠️ `VEHICLE_CARGO_SUMMARY` versi live SALAH (`ii` mentah + "Tabung" hardcoded) → **rebuild per §2 revisi**: join `item`, nama (`in`) + satuan (`un`) per-item, drop 4-bucket.

Source mockup: `src/component/Driverruntimefull.jsx` 3597 / 3279.
