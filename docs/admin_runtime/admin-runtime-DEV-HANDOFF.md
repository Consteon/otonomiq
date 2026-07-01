# Admin Runtime — DEV HANDOFF (cover · baca ini DULU)

Entry tunggal buat dev yang ngerjain **Admin Runtime (Koordinasi)** — sisi kantor dari sistem galon Consteon. Admin **bikin/assign task**, **onboard customer**, **seed saldo awal**, **monitoring**. Mobile, op1Screen, pola sama Driver/Gudang — beda page.

Admin **reuse ~90%** library widget yang udah ada (driver/op1Screen). Kerjaan baru dev = sedikit. Doc ini bilang persis: apa yang dikirim, apa yang dibangun, apa yang bukan urusan dev.

---

## 1. KIRIM INI (paket lengkap)

### A. Mockup / prototype — visual SSOT (4 file, repo ini)
```
src/component/ConsteonAdminHomeEvolved.jsx     # H1 Home (triage)
src/component/AdminCreateTaskIntegrated2.jsx   # FINAL — P1–S3 + Customer Baru + Walk-in POS (v1 AdminCreateTaskIntegrated.jsx superseded)
src/component/AdminRuntimeGallery2.jsx         # semua frame berdampingan (overview, v2 walk-in POS)
src/component/AdminRuntimeFlow.jsx             # prototype clickable — walk routing
```
Lihat: `npm run dev` (main.jsx → AdminRuntimeGallery buat overview / AdminRuntimeFlow buat klik flow).

### B. Spec Admin (docs/ — ini punya Admin sendiri)
```
docs/admin-runtime-DEV-HANDOFF.md     # ← ini (cover)
docs/admin-home-dev-spec.md           # H1 ✅ (REBUILD 2026-06-25 — JSON embedded per §widget)
docs/admin-create-task-dev-spec.md    # P1–S3 wizard (1 doc, section per-page) ✅
docs/customer-namelist-and-creator-token-dev-spec.md  # ⚠️ live-test gap: P1 customer-list blank (extend TASK_FEED_LIST groupField-optional) + creator token {adminVid}→{userVid} wire
docs/admin-feature-handoff.md         # entry point fitur
json/admin-runtime/*.json             # JSON resolved per widget H1 (7 file: header, signal-list, noticeBar, selectableGrid, running/upcoming/outstanding) — sama isi dgn blok JSON di spec
```

### C. Konteks wajib (schema + arsitektur — SHARED, bukan driver-only)
```
docs/consteon-runtime-knowledge-base.md    # arsitektur + konvensi op1Screen + data model
docs/driver-runtime-field-dictionary.md    # SEMUA field code (task/evidence/stock_location/movement/asset_cache/vehicle_check) — schema bersama, dinamain "driver" tapi dipakai semua runtime
```

### D. Dependency (Admin reuse renderer-nya — reference, jangan bangun ulang)
```
docs/driver-runtime-DEV-HANDOFF.md          # cover renderer driver yg Admin reuse (workspaceHeader, taskManifestList, submitConfirmSheet, displayStatisticCard keyed, noticeBar, stepper, selectableGrid, datePicker…)
docs/rbt-route-params-dev-spec.md           # routeParams (nav bawa data, cross-Gudang)
docs/driver-runtime-movement-cf-handoff.md  # asset_cache CF (sumber outstanding/Model B)
```

> **"Tentang Admin aja":** yang murni Admin = **A + B**. **C + D** = referensi bersama (schema + renderer reuse) — ikut dikirim tapi bukan barang baru. Kalau dev udah pegang konteks driver, C+D tinggal pointer.

---

## 2. Yang dev BANGUN (scope)

### ⭐ PRIORITAS — H1 REBUILD (2026-06-25): config udah APPLIED live (op1Screen row 1145), tinggal RENDERER
H1 di-rebuild: home gak bisa pake widget generic existing (3× displayStatisticCard keyed = render BLANK + bentuk gak match mockup). Ganti jadi **3 widget feed dedicated baru + 2 extend generic**. **Semua config + JSON udah di-set live + di spec** (admin-home-dev-spec.md §3-5 + json/admin-runtime/). Yang ketahan = renderer Flutter. Sampai dibikin, 3 section feed + launcher + notice-action **render blank/parsial** di app.

| widget | page | berat | jenis | spec | JSON |
|---|---|---|---|---|---|
| `coordinationSignalList` | H1 | **HIGH** | NEW | home §3.2 | coordination-signal-list.json |
| `adminCoordinationHeader` | H1 | LOW | NEW | home §3.1 | admin-coordination-header.json |
| `RUNNING_TASK_LIST` | H1 | MED | **NEW** (Berjalan, progress read-only) | home §5.1 | running-task-list.json |
| `UPCOMING_TASK_LIST` | H1 | MED | **NEW** (Akan Datang, assign kondisional) | home §5.2 | upcoming-task-list.json |
| `OUTSTANDING_PANEL` | H1 | MED | **NEW** (collapsible aged) | home §5.3 | outstanding-panel.json |
| `selectableGrid` | H1 | LOW | **EXTEND** (+`mode:launch`+`routes`/`icons`, tap=navigate, backward-compat) | home §4.1 | selectable-grid-launcher.json |
| `noticeBar` | H1 | LOW | **EXTEND** (+`actionText`/`actionRoute` = tombol CTA) | home §4.2 | notice-bar-genesis.json |
| `taskItemBuilder` | P2 · W1 | **HIGH** | NEW (+**gate tx-button dari `txTypes`** — live-test 2026-06-29: tombol Tambah/Jual/Beli/Refill HARDCODED, abai txTypes; +search `searchField`/`searchHint`) | create-task §1 + §1.5b | — |
| `PICKER_LIST` (generic; ex-VEHICLE_PICKER) | H1 · P3 | MED | **NEW** (app: "wrong widget name") | **picker-list-widget-dev-spec.md** | — |
| `TASK_FEED_LIST` flat | P1 (+H1) | MED | **EXTEND** (`groupField` optional→flat + **visual refactor = card mockup P1**: avatar/title/sub/badge/chevron, search built-in + "{N}" header + emptyText, self-contained) | customer-namelist §1 + §1b | — |
| `sendButtonGpsWithEvent` submit + `it[]` native-append | P4 | **HIGH** | savesend (reuse, LIVE row 1190) nulis header via addToEvent; **renderer WAJIB append draft `it[]` native** (= keystone) | create-task §5 | — |
| draft-carry token | P2→P4 | **HIGH** | bawa `{kl}/{kn}/{al}/{vv}`+`it[]` draft lintas page → P4 review+submit | create-task §3/§5 | — |
| `{userVid}`/`{userName}` | N1·P4·semua write | LOW | **WIRE** session token current-user (role-agnostic; N1 `{adminVid}` invalid) | customer-namelist §2 | — |

**Prinsip §0 (WAJIB):** semua widget generic/config-driven — label di `text` ◆-segment, table/search/field=param, status 3-tier theme, route=param. JANGAN hardcode label/collection/route di renderer. (admin-home-dev-spec.md §0)

### Reuse renderer (shared driver — sebagian masih PENDING di handoff driver)
`workspaceHeader` · `taskManifestList` · `submitConfirmSheet` · `displayStatisticCard` keyed · `noticeBar` · `stepper` · `selectableGrid` · `switch` · `datePicker` · `textField` · `buttonRoute` · `displayList`.
→ kalau renderer driver-nya udah jalan, Admin tinggal config. Status renderer: `driver-runtime-DEV-HANDOFF.md`.

### ⛔ Blocker bareng — native array write (KEYSTONE)
`task.it[]` (P4 submit) butuh **native Firestore array write** — DSL/`addToEvent` gak bisa nest array. P4 submit = `sendButtonGpsWithEvent` (addToEvent nulis HEADER scalar) → renderer `savesend` **WAJIB ALSO append draft `it[]` sbg native array** ke doc yg sama. **Capability SAMA dengan custody `ip[]`/`dp[]`** — solve sekali, kebuka Admin P4 + custody. Sampai itu, item task gak ke-tulis (header doang).

---

## 3. Yang BUKAN dev (= config sheet, kerjaan design/SSOT)
- op1Screen page-row block + write DSL string = kerjaan sheet (bukan dev). Status: **H1 (1145) + P1–P5 (1159–1200) APPLIED live**. **N1 NewCustomer (1201), S1 Seed (1212), W1 WalkIn (1224) BUILT REAL** (formula-driven, verified resolve) — multi-step flow di-collapse jadi 1-page self-contained (capture+submit same-page + chain dialog); sub-page (N2/S2/S3/W3) folded.
- **N1 = FULL functional** (addToEvent create `stock_location` scalar). **S1 = page real, GENESIS write SKELETON** (FLAG: `ii` butuh taskItemBuilder seed-skin, `{kl}` client ctx, `cd`, backdate occurred_at). **W1 = intake real, POS submit PENDING** (taskItemBuilder walkin + collection `nota` belum diratifikasi). Flags ada di NOTICE_BAR in-page tiap halaman.
- Dev fokus: **renderer Flutter** (NEW + extend + reuse) + **native array write** + **taskItemBuilder** (unblock S1/W1/P2 write). Config (`type`, field-map, route, token) udah ke-set di sheet + JSON-nya di spec.

---

## 4. 2 grounding penting (jangan salah)
1. **Customer = `stock_location` `lt=client`.** GAK ADA collection `customer`. Outstanding customer = `asset_cache` row di client (Model B net). Task refer customer via `kl` (FK→stock_location) + `kn` (denorm).
2. **`genesisStatus`/`provisional`/`seed_confidence`/"belum di-seed" = MOCKUP-ONLY.** BUKAN field. Real: derive (client tanpa GENESIS movement / tanpa asset_cache row). Seed nulis **GENESIS movement** (`mt=GENESIS`, `er=ADMIN`, backdated `occurred_at`). Jangan bikin field genesisStatus.

Tambahan: Admin set `vv`+`cv/cn`(creator), **TIDAK** set driver (`dv` di-set Gudang loading).

3. **Walk-in counter = POS** (mockup v2 §7) — harga per-baris **`hg`** (FIELD BARU di `it[]`/line; `pr` udah kepake plan_refill), default dari pricelist produk global (read-only), bayar LUNAS (tunai/transfer), **nota cetak** (Document Engine + `printBluetooth`). Harga/payment/nota = **data komersial BARU, belum di schema**. Rekomendasi: `hg` di line + collection **`nota`** terpisah (bukan nempel movement). Tech-lead ratify. Detail: create-task §7 + §11.8–11.11.

---

## 5. Status spec (per page)
| page | spec | status |
|---|---|---|
| H1 Home | admin-home-dev-spec.md | ✅ |
| P1 CustomerPicker | create-task §2 | ✅ |
| P2 ItemBuilder | create-task §1+§3 | ✅ |
| P3 Vehicle | create-task §4 (+home §2.3) | ✅ |
| P4 Summary/Submit | create-task §5 | ✅ |
| P5 Success | create-task §6 | ✅ |
| W1–W3 Walk-in (POS) | create-task §7 | ✅ (mockup `AdminCreateTaskIntegrated2.jsx`) |
| N1–N2 Customer Baru | create-task §8 | ✅ |
| S1–S3 Seed | create-task §9 | ✅ |

---

## 6. Build order — FOKUS CORE FLOW dulu (admin→warehouse→driver "sampai task"; walk-in di-KEEP)
Target user: **1 flow task kebuat dari admin → muncul di Gudang → Driver eksekusi.** Urut biar cepet nyambung:

**A. Core task-create (P1→P5) — prioritas:**
1. `PICKER_LIST` (P3 pilih kendaraan) — sekarang "wrong widget name".
2. `taskItemBuilder` (P2) + gate tombol `txTypes` + search.
3. `TASK_FEED_LIST` flat + visual mockup (P1 list customer).
4. **draft-carry** token (`{kl}/{kn}/{al}/{vv}`+`it[]` lintas P1→P4).
5. **KEYSTONE**: `savesend` renderer append draft `it[]` native (P4 submit) + wire `{userVid}/{userName}`.
   → abis 1-5: admin emit task lengkap → **Gudang+Driver langsung consume** (path itu udah tested via seed).

**B. H1 home (paralel/nyusul):**
6. EXTEND `selectableGrid`(+launcher) + `noticeBar`(+action) — kecil.
7. `adminCoordinationHeader` (LOW) → feed read-only `RUNNING`/`UPCOMING`/`OUTSTANDING_PANEL`.
8. `coordinationSignalList` (paling berat, derive lintas-koleksi).

**C. Walk-in (W) — DITUNDA** (owner keep dulu sampe core kelar).

> Config semua udah live di op1Screen — dev bikin renderer per type, test langsung resolve. "wrong widget name" = type belum ada renderer-nya.

---

## 7. Open decisions (butuh keputusan user/tech-lead)
Lihat per-spec: `admin-home-dev-spec.md` §6 (6 item) + `admin-create-task-dev-spec.md` §11 (7 item). Yang paling ngeblok: **native array write** (P4) + **W1 jsx final**.
