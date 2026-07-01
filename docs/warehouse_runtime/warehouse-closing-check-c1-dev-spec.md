# C1 WarehouseClosingCheck + R1/R2 — Dev Spec (Vehicle Runtime / Gudang)

**Buat:** Flutter dev. C1 = gudang hitung fisik muatan yang **turun dari mobil** setelah driver balik (P12 handover). Banding vs expected (sisa yang seharusnya) → **R1 match=approve** / **R2 selisih=eskalasi supervisor**.

**Source mockup:** `src/component/Vehicleruntimemobile.jsx` — `ClosingCheckWorkspace` (1251), `SubmitConfirmSheet` (1494), `PostSubmitScreen` (1665, = R1/R2).

**Masuk dari:** H1 feed, kartu tier `returning` (`cst◼custody_confirmed` + semua task selesai + closing doc belum ada) → bawa `{vehicleId}`.

---

## 0. INTI — siapa nulis apa di closing

Flow (per keputusan 2026-06-23): **driver P12 = serah doang (handover), driver SELESAI.** **Gudang C1 = hitung fisik + reconcile.**

```
DRIVER P12  → serah mobil ke gudang (handover). Driver done.
GUDANG C1   → hitung fisik turun per item (full+empty) = ip[]
            → banding vs expected (sisa = asset_cache mobil) → dp[]
            → R1 match  : approve, opening cst◼closed
            → R2 selisih: investigation (supervisor), opening cst◼closed
```

**C1 submit nulis:**
1. **Create `vehicle_check` closing doc** — `cnm`, `cty◼closing`, `vv`, `gl`, `cdt`, `cv`/`cn` (checker), `t`.
2. **`ip[]`** = hitung fisik checker `[{ii,cd,qt}]` (full + empty) — array → **native**.
3. **`dp[]`** = expected − `ip` per item+cond (kalau selisih) → array native; **`rs`** = `matched`|`discrepancy_detected` (scalar DSL).
4. **Opening doc `cst◼closed`** (updateEventRow, trip selesai).
5. **R2 only:** create `investigation` (`vst◼pending_review`, `vrf◼{closingCnm}`, `vpt◼check`).

> Beda dari `tables-dev-spec §6` (yang nulis P12 driver bikin closing). **Delta:** closing pindah ke gudang C1; P12 driver = handover (movement INTERNAL mobil→gudang = CF/movement track, flag §6).

---

## 1. Widget C1 — reuse (0 baru)

Mirror O1 minus executor (driver udah fix), plus result R1/R2. Urutan: header → context rail → load origin → count returnable/consumable → notes → discrepancy hint → submit.

| # | UI | widget | verdict |
|---|---|---|---|
| 1 | back + "Pengecekan Penutupan" + plat | `WORKSPACE_HEADER` | REUSE |
| 2 | rail "executor · tiba · N ret·M cons" | `TXT` | REUSE |
| 3 | LoadOrigin (collapsible, no qty) | `TASK_MANIFEST_LIST` variant | REUSE (= O1 §5) |
| 4 | count returnable/consumable (vs expected) | `CUSTODY_COUNT_LIST` + `blind:false`+`writeField:ip` | REUSE-variant (§2) |
| 5 | catatan | `TXF` | REUSE |
| 6 | discrepancy hint | `NOTICE_BAR` warn | REUSE |
| 7 | submit (write ip + closing doc + reconcile) | `CUSTODY_COUNT_SUBMIT` variant | REUSE-variant (§4) |
| — | konfirmasi sheet (recap ip vs expected) | `SUBMIT_CONFIRM_SHEET` variant | REUSE |
| R1/R2 | hasil clean / discrepancy | `CUSTODY_CONFIRMED_LIST` / `CUSTODY_DISCREPANCY_LIST` | REUSE (§3, co-spec driver P7/P8/P9) |

**Net widget baru C1+R: 0.** Semua reuse O1/driver custody.

---

## 2. `CUSTODY_COUNT_LIST` variant — closing count vs expected

Beda dari O1: expected = **asset_cache mobil** (sisa yang seharusnya), count **full + empty** (returnable balik kosong), tulis **`ip`**.

| field | O1 (opening) | **C1 (closing)** |
|---|---|---|
| sumber expected | task plan (`Σ pd+ps+pr`) | **`asset_cache` `lv◼{vehicleId}`** (sisa CF-derived) |
| kondisi | full only | **full + empty** |
| `writeField` | `ie` | **`ip`** |
| `blind` | FALSE | FALSE (mock visible; lihat OPEN §7) |
| group | ic returnable/consumable | sama |

Config:
```json
{"type":"CUSTODY_COUNT_LIST","vidtable":"20342033315492","table":"84214220504259//asset_cache","search":"lv◼{vehicleId}","itemsField":"","joinTable":"84214220504259//item","joinKey":"ii","labelField":"in","catField":"ic","condField":"cd","qtyField":"qt","filter":"ic◼returnable","blind":"FALSE","writeField":"ip","text":""}
```
(2 instance returnable/consumable.) Stepper per item+cond, expected = `asset_cache.qt`, count fisik → `ip[]`. `ip`/`dp` native (§4).

---

## 3. R1 / R2 — hasil (mockup `PostSubmitScreen` 1665)

Satu page outcome (`vertikaTeknoLokaciptaWarehouseClosingResult`?) atau sheet — 2 cabang dari reconcile:

- **R1 clean** (`rs◼matched`): banner hijau ✓ "Validation Clean" + `CUSTODY_CONFIRMED_LIST` (item match) + tombol "Selesai → feed".
- **R2 discrepancy** (`rs◼discrepancy_detected`): banner amber ! "Discrepancy Tercatat" + `CUSTODY_DISCREPANCY_LIST` (per item: expected/actual/delta + chip Shortage/Surplus) + info "Lo cuma deteksi, supervisor investigasi" (NOTICE_BAR info) + tombol "Eskalasi ke Supervisor" + "Kembali ke Daftar".

| field (discrepancy list) | nilai |
|---|---|
| `table`/`search` | `84214220504259//vehicle_check` / `cnm◼{closingCnm}` |
| `itemsField` | `dp` — `[{ii,cd,ex,ac,dl}]` |
| join item | `ii`→`in`/`ic` |
| `expField`/`actField`/`deltaField` | `ex`/`ac`/`dl` |
| `escalateEvent` | create investigation (§4) |

Branch (match/mismatch) ditentukan `rs` hasil reconcile C1 — pola sama driver custodyReveal (`matchRoute`/`mismatchRoute`). Reuse types P7/P8/P9 (belum di-spec driver, co-spec di sini).

---

## 4. Submit = send-button multi-write

1. **Create closing doc** (`addToEvent` `vehicle_check`):
   `r◼…⭘tablevid◼20342033315492⭘cnm◼{genClosingCnm}⭘cty◼closing⭘vv◼{vehicleId}⭘gl◼{warehouseId}⭘cdt◼{today}⭘cv◼{checkerVid}⭘cn◼{checkerName}⭘t◼◀…▶`
2. **`ip[]`** native ke doc itu: `[{ii,cd,qt}, …]` (full+empty).
3. **Reconcile** (native compute): `dp[]` = expected(asset_cache) − `ip` per item+cond; non-zero → `dp` native + `rs◼discrepancy_detected`, else `rs◼matched` (scalar DSL/native).
4. **Opening doc `cst◼closed`** (`updateEventRow` `vehicle_check` `search◼cnm★{openingCnm}⭘cst◼closed`).
5. **R2 only:** `addToEvent` `investigation` (`vnm◼{genVnm}⭘vst◼pending_review⭘vrf◼{genClosingCnm}⭘vpt◼check⭘t◼◀…▶`).
6. Nav → R1/R2 (sesuai `rs`).

Token: `{vehicleId}` `{warehouseId}` `{checkerVid}` `{checkerName}` `{today}` `{genClosingCnm}` `{openingCnm}` `{genVnm}`. Array (`ip`/`dp`) = native (sama aturan P6 §4).

---

## 5. Expected source = asset_cache mobil

Sisa yang seharusnya di mobil = `asset_cache` `lv◼{vehicleId}` (per item+cd, full+empty), CF-derived dari movement (loaded − dropped + picked). Match vs hitung fisik gudang. Kalau CF belum live → hand-seed (seed udah ada baris asset_cache mobil empty). Driver P12 INTERNAL movement belum nge-update? → §6.

---

## 6. OPEN / confirm

1. **P12 ↔ C1 movement** — siapa bikin movement INTERNAL (mobil→gudang)? Driver P12 (klaim) atau gudang C1 (counted ip = truth) atau CF dari closing? **Rec:** INTERNAL diturunkan dari `ip` counted gudang (truth) via CF. = movement/CF track, di luar widget. **Flag.**
2. **Closing blind?** — mock visible (tampil expected). Anti-bias mau blind kaya driver custody? Same widget, flip `blind`. Konfirmasi.
3. **`{openingCnm}`** — buat update cst closed, butuh cnm opening. Lookup `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` → ambil `cnm`. OK.
4. **R1/R2 = page atau sheet?** — mock full-screen. Rec page (`...WarehouseClosingResult`), branch by `rs`. Konfirmasi.
5. **investigation actor** `cv`/`cn` — supervisor belum login di gudang-app; isi checker dulu? Konfirmasi.
6. **R2 cst** — set `closed` walau discrepancy (trip selesai, investigation jalan paralel)? Rec ya. Konfirmasi.

---

## 7. Op1Screen integration

C1 `vertikaTeknoLokaciptaWarehouseClosingCheck`: name-row + widget rows (workspaceHeader, txt-rail, taskManifestList(variant), custodyCountList×2, txf, noticeBar-warn, custodyCountSubmit) + buffer. R1/R2 `vertikaTeknoLokaciptaWarehouseClosingResult`: banner + custodyConfirmedList/custodyDiscrepancyList + noticeBar + RBT (selesai/eskalasi). 0 widget baru — reuse O1 + driver custody types (custodyConfirmedList/custodyDiscrepancyList co-spec driver P7/P8/P9). Row >237, alokasi pas build.
