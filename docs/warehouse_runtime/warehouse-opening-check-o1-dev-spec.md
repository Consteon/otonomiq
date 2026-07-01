# O1 WarehouseOpeningCheck — Dev Spec (Vehicle Runtime / Gudang)

**Buat:** Flutter dev. O1 = layar gudang muat + cek pembukaan (`vertikaTeknoLokaciptaWarehouseOpeningCheck`). Checker berdiri di samping kendaraan: hitung fisik yang dimuat vs rencana, **tentukan pengemudi**, submit → bikin custody opening.

**Source mockup (SSOT layout):** `src/component/Vehicleruntimemobile.jsx` — `OpeningCheckWorkspace` (794), `ExecutorCard` (453), `ExecutorPickerSheet` (507, = O2), `LoadOriginCard` (347), `QuantityStepper` (216), `OpeningSubmitConfirmSheet` (1058).

**Masuk dari:** H1 feed, kartu tier `loading` (`dv` kosong) → bawa `{vehicleId}` (= `lv` mobil).

---

## 0. INTI — O1 = "gudang-flow" yang driver custody tunggu

Spec driver P5/P6 berulang bilang `ie[]` / `gv` / `gn` / `ldt` = *"pre-seed gudang, hand-seed dulu, gudang-app belum ada"*. **O1 = gudang-app itu.** O1 yang **memproduksi** `vehicle_check` opening doc yang dibaca P5 (`vehicleCustodyHeader`) + P6 (`CUSTODY_COUNT_LIST` baca `ie[]`). Bukti: mock checker "Anton Pratama" = persis contoh dict `gn`.

**O1 submit nulis (handshake ke driver):**
1. **Create `vehicle_check` opening doc** — `cnm`, `cty◼opening`, `vv`, `gl`, `cdt◼{today}`, `cst◼awaiting_custody`, `gv`/`gn` (loader = checker sesi), `ldt` (jam muat).
2. **`ie[]`** = hasil hitung fisik checker `[{ii,cd:full,qt}]` — manifest gudang (SSOT "apa yang fisik dimuat"). Array → **native write**.
3. **Designate driver** → update `stock_location` `dv` (vid) + `dn` (nama denorm). Ini yang ngeluarin mobil dari backlog `loading` di H1.
4. (opsional) evidence note/foto kalau ada selisih opening.

Setelah O1: mobil → tier `custody_pending` (driver giliran konfirmasi P5/P6).

> `ie[]` opening = **full only** (muat = semua full; empty balik pas rute). `cd:full` baked tiap entry.

---

## 1. Widget O1 — reuse-first (1 baru + O2)

Urutan (match mockup): header → context rail → executor card → load origin → planned-loading banner → count (returnable/consumable) → notes → mismatch hint → submit bar.

| # | UI | widget | verdict |
|---|---|---|---|
| 1 | back + "Pengecekan Pembukaan" + plat | `WORKSPACE_HEADER` | REUSE (row 225) |
| 2 | rail "station · verify physical vs plan" | `TXT` | REUSE |
| 3 | designate driver (search pegawai → vid) | **`searchFromTableConsteon`** (Widget 156) + `NOTICE_BAR` warn | REUSE (§2) |
| 4 | LoadOrigin (task list, no qty, collapsible) | `TASK_MANIFEST_LIST` + `hideQty`+`collapsible` | REUSE-variant (§5) |
| 5 | "Planned Loading" info banner | `NOTICE_BAR` variant=info | REUSE |
| 6 | count returnable/consumable (vs plan visible) | `CUSTODY_COUNT_LIST` + `blind:false`+`writeField:ie`+`groupBy` | REUSE-variant (§4) |
| 7 | catatan checker | `TXF` | REUSE |
| 8 | mismatch hint | `NOTICE_BAR` variant=warn | REUSE |
| 9 | submit (write ie + create doc + designate) | `CUSTODY_COUNT_SUBMIT` variant (send-button) | REUSE-variant (§6) |
| — | konfirmasi sheet (recap ie vs plan) | `SUBMIT_CONFIRM_SHEET` variant | REUSE (§5) |
| O2 | picker pengemudi | = `searchFromTableConsteon` itu sendiri | folded ke §2 |

**Net widget baru O1: 0.** Executor designate+pick = reuse `searchFromTableConsteon`. Sisanya reuse driver custody/generic dengan flag.

---

## 2. Executor designate + pick = `searchFromTableConsteon` (REUSE, Widget 156)

Checker tentuin pengemudi pakai widget search **existing** — **0 widget baru** (executor card + O2 picker dua-duanya collapse ke sini). `searchFromTableConsteon` = `TXF variant:tableSearch`: ketik → cari `workforce` → tampil record (`Nama <2>` / `Position <5>` / `Site <6>`) → capture **vid** di `[POSITION]`.

| field | nilai |
|---|---|
| `[TABLE]` | `84214220504259//workforce` |
| `[POSITION]` | posisi form penangkap **vid** driver terpilih → ditulis ke `dv` pas submit (§6) |
| `[FILTER]` | opsional batasi kandidat; kosong = semua workforce (driver/gudang/admin bebas → ad-hoc OK) |
| `[QRTYPE]`/`[TEXT]`/`[ICON]`/`[TABLEREF]` | label "Pengemudi" dll (tarik usage existing pas build) |

- Hasil capture = **vid** → `dv`; nama (`dn`) dari record (denorm pas submit).
- Free-search → **gap role/ad-hoc moot** (gak butuh field `role` yang udah di-drop Delta 9).
- "Wajib tentukan sebelum berangkat" = `NOTICE_BAR` warn di atas search kalau `dv` kosong (reuse, bukan styled card).
- Penentuan **di-surface ke Admin** (Admin baca `stock_location.dv`/`dn` yang sama).

> Verify pas build: `com:"auz"` route ke tenant workforce yang bener (driver tablevid `84214220504259`); kolom `<2>` = nama.

---

## 4. `CUSTODY_COUNT_LIST` variant — count vs plan (VISIBLE)

Beda dari P6 (blind, baca `ie`, tulis `ip`): O1 **visible** (banding vs plan), baca **task plan**, tulis **`ie`**.

| field | P6 (driver) | **O1 (gudang)** |
|---|---|---|
| sumber item-set | `vehicle_check.ie[]` | **`task` aggregate `it[]`** (§7) |
| `blind` | `TRUE` (qt disembunyiin) | **`FALSE`** (tampil "Ekspektasi: N") |
| `writeField` | `ip` | **`ie`** |
| join | item `ii`→`in`/`ic` | sama |
| filter/group | `ic◼returnable`/`ic◼consumable` (2 instance) | sama (+ `groupBy` display) |
| stepper | start 0, min 0 | sama; tampil delta (fisik − plan) |

Config O1:
```json
{"type":"CUSTODY_COUNT_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"vv◼{vehicleId}⭘tdt◼{today}","aggregate":"it","planField":"pd","saleField":"ps","refillField":"pr","excludeStatus":"load_rejected","joinTable":"84214220504259//item","joinKey":"ii","labelField":"in","catField":"ic","filter":"ic◼returnable","blind":"FALSE","writeField":"ie","writeCond":"full","text":""}
```
(2 instance: `filter:ic◼returnable` + `ic◼consumable`.) `blind`/exclude pakai string `"FALSE"`/`"TRUE"` (konvensi user). Write `ie[]` = native array (§6).

---

## 5. Widget reuse lain (variant ringkas)

- **`TASK_MANIFEST_LIST` (LoadOrigin)** — reuse P5, +`hideQty:"TRUE"` (drop badge ↓↑) +`collapsible:"TRUE"` (default collapsed) +`excludeStatus:"load_rejected"`. Footnote "per-customer qty di Driver Runtime" = 1 text seg. Header = "{N} task · {today}".
- **`NOTICE_BAR`** ×2 — info ("Planned Loading. Jumlah dari aggregate task; verify physical, lapor kalau selisih") + warn ("Load tidak match plan → opening discrepancy, Admin diberi tahu"). 3-tier label/title/text. Existing.
- **`TXF`** — catatan checker (wajib bila mismatch).
- **`SUBMIT_CONFIRM_SHEET` variant** — recap `ie` (load) vs plan per item + delta chip + **baris Executor** (driver terpilih) + banner clean/discrepancy. Beda dari driver (drop/pickup) → vehicle pakai single count vs plan; +1 baris executor. Reuse renderer, config text segmen vehicle.

---

## 6. Submit = send-button multi-write (PENTING)

Tombol submit (`CUSTODY_COUNT_SUBMIT` variant) BUKAN nav-polos. Urutan (renderer/native):
1. **Create opening doc** (`addToEvent`, append `vehicle_check`):
   `r◼…⭘tablevid◼20342033315492⭘cnm◼{genCnm}⭘cty◼opening⭘vv◼{vehicleId}⭘gl◼{warehouseId}⭘cdt◼{today}⭘cst◼awaiting_custody⭘gv◼{checkerVid}⭘gn◼{checkerName}⭘ldt◼{now}⭘t◼◀…▶`
2. **Write `ie[]`** (NATIVE array, ke doc `cnm` barusan): `[{ii,cd:"full",qt}, …]` gabung 2 count-list.
3. **Designate driver** (`updateEventRow` `stock_location`): `search◼lv★{vehicleId}⭘dv◼{chosenVid}⭘dn◼{chosenName}`.
4. (opsional, kalau mismatch + ada note/foto) `addToEvent` `evidence` (`ept◼check⭘erf◼{genCnm}⭘ety◼notes⭘d◼…` / `ety◼photo⭘i◼…`).
5. Nav balik H1 feed.

Token: `{vehicleId}` `{warehouseId}` `{checkerVid}` `{checkerName}` `{chosenVid}` `{chosenName}` `{today}` `{now}` `{genCnm}`. `ie`/`ip`/`dp` = array → **native** (DSL gak support array, sama aturan P6 §4).

> `cnm` di-generate client-side (cth `CHK-{vv}-{YYYYMMDD}`) biar bisa target native `ie[]` write + evidence `erf`.

---

## 7. Expected/plan aggregation (= manifest awal, samain P5/P6)

Plan visible di count = **manifest awal full** per item: `Σ(pd + ps + pr)` lintas task (`vv`,`today`), **exclude `tst◼load_rejected`**, **exclude purchase `pb`** (beli naik mid-rute, bukan muat gudang). Sama rumus P5 §B / P6 §B — biar `ie` yang O1 hasilin konsisten sama yang driver harapin. cd = `full`.

---

## 8. OPEN / confirm

1. ✅ **O2 picker RESOLVED** — reuse `searchFromTableConsteon` (collapse executor card, 0 widget baru). Verify pas build: `com:"auz"` tenant workforce + kolom `<2>`=nama.
2. **`gl` (warehouse id)** — dari mana? sesi checker (stasiun → warehouse) atau task `gl`. Confirm sumber `{warehouseId}`.
3. **Designate timing** — tulis `dv`/`dn` pas submit (asumsi, §6) atau langsung pas pilih di O2? Submit = atomik sama opening; rec submit. Konfirmasi.
4. **Opening discrepancy handling** — mock "Admin diberi tahu". Cukup `ie≠plan` implicit (Admin banding), atau perlu flag eksplisit? (kandidat: gak ada field; Admin compute). Konfirmasi.
5. **`ldt`/`now`** — epoch device pas submit. OK.
6. **cnm gen format** — `CHK-{vv}-{YYYYMMDD}` usulan. Konfirmasi (hindari tabrakan kalau >1 trip/hari/mobil — sekarang 1 trip/hari aman).

---

## 9. Op1Screen integration

O1 `vertikaTeknoLokaciptaWarehouseOpeningCheck`: name-row + widget rows (workspaceHeader, txt-rail, executorDesignateCard, taskManifestList(variant), noticeBar-info, custodyCountList×2, txf, noticeBar-warn, custodyCountSubmit) + 2 buffer. Confirm sheet = instantiated by submit (DO_DIALOG), bukan standing row. Widget baru (`executorDesignateCard` [+ picker]) ditulis I/J/G/H dulu; variant reuse = config beda di col D/param. Row >237 (lanjut driver). Belum di-assign nomor — alokasi pas build.
