# H1 VehicleFeed — Dev Spec (Vehicle Runtime / Gudang)

**Buat:** Flutter dev. H1 = layar beranda checker gudang (`vertikaTeknoLokaciptaWarehouseFeed`). Daftar kendaraan di loading bay — termasuk **backlog** mobil yang belum di-assign driver (muncul terus walau kemarin/seminggu lalu) — dikelompokkan per tier, dengan aksi sesuai state (opening check / closing check) atau read-only (giliran driver).

**Source mockup (SSOT layout):** `src/component/Vehicleruntimemobile.jsx` — `VehicleFeedScreen` (660), `VehicleCard` (581), `StateChip` (203).

**Pola:** persis langkah driver P10 (`ROUTE_FEED_HEADER` + `TASK_FEED_LIST`) — reuse generic header/card "full" GAGAL mirip → 2 widget BARU dedicated. Verdict sama di sini.

| widget | type | render |
|---|---|---|
| `vehicleFeedHeader` | `VEHICLE_FEED_HEADER` | header sticky atas (identitas checker + snapshot 3 angka) |
| `vehicleFeedList` | `VEHICLE_FEED_LIST` | list tier-grouped + kartu kendaraan + aksi per state |

> **Status:** **SHEET CONFIG BUILT LIVE (2026-06-23)** @ op1Screen `vertikaTeknoLokaciptaWarehouseFeed` rows 1101–1105 + Widget rows 229 (`vehicleFeedHeader`) / 230 (`vehicleFeedList`), assembled + resolving. Type BARU → **renderer (2 type) pending** di app build, sama kaya custody/feed types driver. Datanya = **collection driver yang SAMA** (`stock_location`, `vehicle_check`, `task`) — 0 collection baru, +1 denorm field `dn`.

---

## 0. Konteks — Vehicle Runtime = sisi GUDANG dari data driver

Vehicle Runtime bukan fitur terpisah dari driver — dia yang **memproduksi** data yang driver custody konsumsi, dan yang **memvalidasi** hasil rute driver. Field `ie[]` / `gv` / `gn` / `ldt` / `stock_location.dv` di dictionary driver ditandai *"gudang-flow (next feature), struktur disiapin dari sekarang"* — itu fitur ini.

Handshake:
```
GUDANG opening (O1)   → muat mobil, hitung ie[] manifest, designate driver (dv),
                        set gv/gn/ldt, cst=awaiting_custody          [vehicle_check cty=opening]
DRIVER custody (P5/6) → hitung ip[], reveal vs ie[], confirm → cst=custody_confirmed
DRIVER rute (P10/11)  → movement DROP/PICKUP per stop
DRIVER return (P12)   → serah mobil ke gudang; driver SELESAI       [movement INTERNAL mobil→gudang]
GUDANG closing (C1)   → hitung fisik turun per item → ip[] closing vs expected ie[]
                        → R1 match=approve / R2 selisih=eskalasi supervisor  [vehicle_check cty=closing]
```

Aktor: checker/gudang = `cv`/`cn` (di vehicle_check) + loader `gv`/`gn`. Driver = `dv`/`dn`. Beda orang, field beda — udah dipisah di dict.

---

## 1. `VEHICLE_FEED_HEADER` (mockup `VehicleFeedScreen` 667-742)

Layout (surface bg, border-bottom):

**Baris 1 — identitas:**
- avatar bulat inisial checker (gradient teal) + nama checker (15px bold) + baris kedua `{station} · Vehicle Runtime` (11px textMid).
  - nama checker = `workforce.n` (search `VID◼{checkerVid}`), `{checkerVid}` = sesi login.
  - `station` = **statis** (cth "Loading Bay 1") — bukan field dict (kosmetik). Boleh di-config atau drop.
- kanan: tombol menu ☰ (36×36) → `menuRoute` (opsional).

**Baris 2 — snapshot 3 box (flex):**
- **Perlu Tindakan** (amber kalau >0): count kendaraan tier returning (+custody_pending). Highlight amber kalau ada.
- **Opening Check**: count kendaraan tier loading.
- **Hari Ini**: total kendaraan di feed.
- Ketiga angka = count dari feed yang sama (lihat §3 derivation). Renderer hitung sekali, share.

**text (4 seg):** `Vehicle Runtime◆Perlu Tindakan◆Opening Check◆Hari Ini`

**Config:**
```json
{"type":"VEHICLE_FEED_HEADER","vidtable":"20342033315492","workforceTable":"84214220504259//workforce","checkerSearch":"VID◼{checkerVid}","nameField":"n","station":"Loading Bay 1","menuRoute":"","text":"Vehicle Runtime◆Perlu Tindakan◆Opening Check◆Hari Ini"}
```
> Angka snapshot diturunkan renderer dari list (§3), bukan field — header gak perlu source sendiri kalau renderer share state dengan list. Kalau perlu standalone, header pakai source/gate yang sama dengan list.

---

## 2. `VEHICLE_FEED_LIST` (mockup `VehicleFeedScreen` body + `VehicleCard` 581)

Baca kendaraan hari ini, group by **tier** (komposit — §3), render section + kartu.

### 2.1 Section (urutan)
- **Perlu Tindakan** (`returning`, +`custody_pending`): label uppercase amber700 + dot amber. Returning = aksi checker (closing). custody_pending = read-only (giliran driver).
- **Pengecekan Pembukaan** (`loading`): label teal (vehicleAccent).
- **Dalam Perjalanan** (`in_route`): label textDim. Read-only.
- **Selesai Hari Ini** (`completed`): label textDim. Read-only.
- Section kosong → header hidden.

### 2.2 VehicleCard (per kendaraan) — layout
Card (radius10, border, borderLeft 3px):
- borderLeft + bg: tier1 (returning/custody_pending) = amber400 + amber50 bg; loading = vehicleAccent + surface; lainnya = transparent + surface. completed = opacity .65.

**Identity row:** plat mono 16px bold (`stock_location.ln`) + `StateChip` (kanan).

**Summary:** `{executor || "Pengemudi belum ditentukan"}` + ` · tiba {arrivedAt}` / ` · selesai {completedAt}` / ` · stop {routeStop}` sesuai state.
- executor = nama driver dari `stock_location.dv` (vid) → resolve `workforce.n`. Kalau `dv` null → "Pengemudi belum ditentukan".

**expectedSummary:** baris textDim — ringkasan muatan (cth "3 returnable · 1 consumable"), derive dari `task.it[]` group `item.ic`.

**Action button (per state):**
| state | tombol | warna | route |
|---|---|---|---|
| `loading` | "Pengecekan Pembukaan" | teal | → O1 opening check |
| `returning` | "Pengecekan Penutupan" | amber | → C1 closing check |
| `custody_pending` | — (read-only*) | — | — |
| `in_route` | — | — | — |
| `completed` | — | — | — |

\* mock nampilin "Konfirmasi Penerimaan" tapi itu aksi DRIVER (P5/6). Di app checker = read-only. **OPEN — konfirmasi (§5).**

**text (7 seg):** `Perlu Tindakan◆Pengecekan Pembukaan◆Dalam Perjalanan◆Selesai Hari Ini◆Pengecekan Penutupan◆Pengecekan Pembukaan◆Pengemudi belum ditentukan`

**Config:**
```json
{"type":"VEHICLE_FEED_LIST","vidtable":"20342033315492","table":"84214220504259//stock_location","search":"lt◼vehicle⭘lst◼active","plateField":"ln","executorField":"dv","executorNameField":"dn","openingGate":"84214220504259//vehicle_check⭘cty◼opening⭘vv◼{lv}","cstField":"cst","closingGate":"84214220504259//vehicle_check⭘cty◼closing⭘vv◼{lv}","taskTable":"84214220504259//task","taskSearch":"vv◼{lv}⭘tdt◼{today}","taskStateField":"tst","itemsField":"it","openingRoute":"vertikaTeknoLokaciptaWarehouseOpeningCheck","closingRoute":"vertikaTeknoLokaciptaWarehouseClosingCheck","text":"Perlu Tindakan◆Pengecekan Pembukaan◆Dalam Perjalanan◆Selesai Hari Ini◆Pengecekan Penutupan◆Pengecekan Pembukaan◆Pengemudi belum ditentukan"}
```

---

## 3. State → tier derivation — INTI

Sinyal utama "belum di-assign driver" = **`stock_location.dv` kosong** → backlog, **TANPA filter tanggal** (mobil belum di-assign tetap muncul walau kemarin / seminggu lalu, sampai di-assign). Sisanya (trip aktif) baru pakai `vehicle_check.cst` + `task.tst`.

`cst` cuma 3 nilai (model B): `awaiting_custody → custody_confirmed → closed`. Fase rute (`on_delivery`/`returning`) = `task.tst`, BUKAN cst. Per kendaraan (`lv`), evaluasi urut:

| urut | kondisi | tier | date scope |
|---|---|---|---|
| 1 | `dv` kosong (belum di-assign) | **loading** (opening check) | TANPA tanggal — backlog persist |
| 2 | `dv` keisi + opening `cst◼awaiting_custody` | **custody_pending** (giliran driver) | trip aktif |
| 3 | `dv` keisi + `cst◼custody_confirmed` + masih ada `task.tst` belum selesai | **in_route** | trip aktif |
| 4 | `dv` keisi + `cst◼custody_confirmed` + semua `task.tst`∈{completed,validated,closed} + closing doc GAK ADA | **returning** (siap closing check) | trip aktif |
| 5 | closing doc ADA / opening `cst◼closed` | **completed** | **hari ini** (`cdt◼{today}`; trip lama drop) |

Catatan: opening doc = anchor 1 trip (1 mobil = 1 trip aktif). `dv` di-set saat O1 (designate driver) → mobil keluar dari backlog loading. Trip `closed` + bukan hari ini → mobil hilang dari feed (sampai dapat assign/task baru → balik ke loading).

Snapshot header:
- Perlu Tindakan = count(returning)
- Opening Check = count(loading) — backlog unassigned
- Hari Ini = total row feed (backlog + trip aktif + completed hari ini)

> Renderer cache `openingGate`/`closingGate`/`taskSearch` per `lv` biar gak query berulang. `{lv}` = id stock_location row; `{today}` = epoch-midnight-ms device. loading **tanpa** `{today}`.

---

## 4. Field mapping — dari dict driver (0 collection baru; +1 denorm field `dn`)

| UI | field real | sumber |
|---|---|---|
| plat | `ln` | stock_location (row feed) |
| state/tier | `dv` (assign) + `cst` + existence opening/closing doc + `task.tst` rollup | stock_location + vehicle_check + task |
| executor (nama) | `dn` (denorm, di-set bareng `dv` saat O1) | stock_location (row feed) |
| nama checker | `workforce.n` (`VID◼{checkerVid}`) | sesi |
| expectedSummary | Σ `task.it[]` group `item.ic` | task |
| loaded/arrival time | `vehicle_check.ldt` (opening) / closing `t` | vehicle_check |
| station | — (statis) | kosmetik, bukan field |

**1 field ditambah:** `dn` (driver name) di `stock_location`, denorm bareng `dv`. Reuse code `dn` existing (= driver name di `movement`; fungsi sama → no collision, sesuai aturan dict). Denorm biar list gak N+1 query workforce per row ([[feedback_nosql_denorm_pattern]]). `station` = satu-satunya yang gak di dict (kosmetik/statis). Sisanya field driver existing.

---

## 5. RESOLVED / OPEN

- ✅ **Sumber feed (RESOLVED 2026-06-23)** — `stock_location lt◼vehicle⭘lst◼active`, **TANPA filter tanggal**. Mobil `dv` kosong = backlog belum-di-assign, muncul terus sampai di-assign (§3). Cuma tier completed di-scope hari ini.
- ✅ **Executor name (RESOLVED)** — denorm `dn` ke stock_location, di-set bareng `dv` saat O1. Reuse code `dn` (= driver name di movement; fungsi sama, no collision). +1 field ke dict stock_location.
- ✅ **Route prefix (RESOLVED)** — `vertikaTeknoLokaciptaWarehouse*` (Feed / OpeningCheck / ClosingCheck).
- **custody_pending actionable?** — mock kasih tombol "Konfirmasi Penerimaan" tapi itu aksi driver. Asumsi: read-only di app checker. Konfirmasi.
- **arrival/loaded time format** — `ldt` epoch (opening). Closing arrival = movement INTERNAL `t` / closing doc `t`. Confirm sumber.
- **routeStop "3 / 6"** (in_route) — derive dari `task.tst` rollup (Σ selesai / total). Bukan field. OK.

---

## 6. Op1Screen integration

H1 `vertikaTeknoLokaciptaWarehouseFeed`: name-row + 2 widget row (`vehicleFeedHeader`, `vehicleFeedList`) + 2 buffer. Tap kartu `loading` → `vertikaTeknoLokaciptaWarehouseOpeningCheck` (O1); `returning` → `vertikaTeknoLokaciptaWarehouseClosingCheck` (C1); lainnya no-op. Widget rows ditulis (I/J/G/H) sebelum page-row block (ikutin KB §1). Belum di-assign row number — alokasi pas build (lanjutan driver, row >237).
