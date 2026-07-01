# Admin Home (H1) — Dev Spec

**Page:** `AdminHome` · Admin Runtime (Koordinasi) · mobile op1Screen
**Route key:** `vertikaTeknoLokaciptaAdminHome` (op1Screen row 1145)
**Entry point:** first screen Admin runtime. Bukan create-flow — ini **triage / command center**: lihat yang mandek → lempar ke aksi (Create Task / Gudang).
**Mockup:** `src/component/ConsteonAdminHomeEvolved.jsx` → `AdminHomeView` (mounted via `AdminRuntimeGallery2.jsx`, Frame H1)
**JSON per widget (copy-paste):** `json/admin-runtime/*.json` (1 file/widget, sama isi dgn blok JSON di bawah + `_doc`).
**Doctrine:** Admin = koordinasi. Assign order ke **kendaraan** (recon container), bukan orang. Siapa nyetir ditentukan di Gudang. Sinyal lintas-runtime (no_executor / blocked_departure) **nyebrang ke Gudang**, bukan diselesaikan Admin.

> Status legend: ✅ reuse (renderer BUILT) · ✳️ EXTEND (renderer ada, tambah param) · 🆕 NEW (bikin renderer + Widget template)
> Tiap §widget punya **2 blok**: penjelasan param + **JSON resolved (jadi)**. JSON = bentuk akhir yg di-render, bukan pseudo.

---

## 0. PRINSIP WAJIB — semua widget GENERIC (config-driven, reusable case manapun)

User directive: **tiap widget harus bisa dipakai di case/page/tenant manapun, bukan baked ke Admin Home.** Konsekuensi non-negosiable buat SEMUA widget di spec ini:

1. **Label = config, bukan Flutter.** Semua teks tampil (judul, prefix progress, label tombol, badge) datang dari `text` ◆-segment (renderer baca by index). NOL string Indonesia di-hardcode di renderer. Owner reword via sheet → tanpa deploy. (lihat `feedback_config_driven_labels`)
2. **Table/search/field = param.** Collection name, search clause, dan tiap field tampil = param config (`table`, `search`, `[X]Field`). Renderer table-agnostic → `OUTSTANDING_PANEL` bisa list-aged koleksi apapun, `UPCOMING_TASK_LIST` buat list-with-assign apapun, `RUNNING_TASK_LIST` buat progress-list apapun. NOL "task"/"asset_cache" baked di renderer.
3. **Status = 3-tier baku (theme) + relabel.** Tier `danger`/`warn`/`ok`, warna dari **theme** bukan config. Threshold = param. Label via `statusLabels`/`text` kalau perlu reword. NOL hex/warna di config. (lihat `feedback_status_3tier_relabel`)
4. **Route = param.** Tiap nav (launcher cell, CTA button, cross-runtime) = route string di config. NOL route hardcoded di renderer.

Pola implementasi = **generic-SUBSTITUTE** (Widget tab J = template `[PLACEHOLDER]` per field, op1Screen D = nested SUBSTITUTE isi nilai). lihat `feedback_generic_substitute_pattern`.

---

## 1. Widget manifest (render order, 9 child)

| # | widget | type | status | write |
|---|--------|------|--------|-------|
| 1 | `adminCoordinationHeader` | header identitas koordinator + chip beban | 🆕 | — (read) + nav switch |
| 2 | `coordinationSignalList` | Perlu Tindakan (sinyal mandek, cluster) | 🆕 | updateEventRow (assign) + nav cross |
| 3 | `noticeBar` | genesis nudge + tombol Catat→Seed | ✳️ | — + nav |
| 4 | `selectableGrid` | Quick actions (launcher 3-cell) | ✳️ | — + nav |
| 5 | `text` "Berjalan" | section label | ✅ | — |
| 6 | `RUNNING_TASK_LIST` | trip aktif (progress read-only) | 🆕 | — (read) |
| 7 | `text` "Akan Datang" | section label | ✅ | — |
| 8 | `UPCOMING_TASK_LIST` | task terjadwal + assign kondisional | 🆕 | updateEventRow (assign vv) |
| 9 | `OUTSTANDING_PANEL` | Prioritas Pengambilan (collapsible, aged) | 🆕 | — + nav schedule |

**NEW renderer (3):** `RUNNING_TASK_LIST`, `UPCOMING_TASK_LIST`, `OUTSTANDING_PANEL`.
**EXTEND renderer (2):** `selectableGrid` (+launcher mode), `noticeBar` (+action button).
**KEEP (2, dedicated, LIVE):** `adminCoordinationHeader` (Widget row 231), `coordinationSignalList` (row 232).
**Sheet (overlay, reuse):** `vehiclePicker` (row 233) — dipicu signal-list / upcoming / outstanding.

Mapping mockup → widget:

| Mockup (`AdminHomeView`) | Widget |
|---|---|
| `IdentityZone` (header biru) | `adminCoordinationHeader` |
| `PerluTindakan` (sinyal cluster) | `coordinationSignalList` |
| genesis nudge (violet + Catat) | `noticeBar` ✳️ |
| `QuickActions` (3 tombol ikon) | `selectableGrid` ✳️ launcher |
| `ActiveCard` list (Berjalan) | `RUNNING_TASK_LIST` 🆕 |
| `UpcomingCard` list (Akan Datang) | `UPCOMING_TASK_LIST` 🆕 |
| `OutstandingPanel` (Prioritas) | `OUTSTANDING_PANEL` 🆕 |

---

## 2. Komposisi page

```
AdminHome (children, urutan):
  ├─ adminCoordinationHeader        (pinned top, bukan scroll)
  └─ scroll body:
       ├─ coordinationSignalList    (judul "Perlu Tindakan" di header widget)
       ├─ noticeBar (genesis nudge) + tombol Catat
       ├─ selectableGrid (3× launcher cell)
       ├─ text "Berjalan"
       ├─ RUNNING_TASK_LIST
       ├─ text "Akan Datang"
       ├─ UPCOMING_TASK_LIST
       └─ OUTSTANDING_PANEL (collapsible, judul "Prioritas Pengambilan" di header panel)
  + vehiclePicker → bottom-sheet overlay, di-trigger signal-list / upcoming / outstanding
```

Header pinned; sisanya scroll. Sheet = overlay (bukan route baru). Panel outstanding judulnya nyatu di header panel → **drop TXT "Prioritas Pengambilan" terpisah**.

---

## 3. KEEP — dedicated widgets (LIVE, contract tetap)

### 3.1 `adminCoordinationHeader` 🆕 (LIVE Widget row 231)

Bar biru atas. Identitas koordinator + ringkasan beban + switch runtime.

**Display (mockup `IdentityZone`):** icon 🗺️ + "Koordinasi" · baris-2 `{nama}` · `{plat}` · 2 chip `{N} berjalan`/`{N} sinyal` · tombol "⇄ Ganti"→launcher.

**Param:** nama dibaca dari token **`#NAME`** (bukan workforce lookup). `{N} berjalan`/`{N} sinyal` = {dev}-count dari taskTable/checkTable, konsisten dgn widget #2/#6. `switchRoute:""` → tombol Ganti hidden (set launcher route kalau ada). `text` ◆ = `[role]◆[switchBtn]◆[activeChipSuffix]◆[signalChipSuffix]`.

**JSON resolved (H1):**
```json
{"type":"ADMIN_COORDINATION_HEADER","vidtable":"20342033315492","taskTable":"84214220504259//task","vehicleTable":"84214220504259//stock_location","checkTable":"84214220504259//vehicle_check","evidenceTable":"84214220504259//evidence","switchRoute":"","text":"Koordinasi◆⇄ Ganti◆berjalan◆sinyal"}
```

### 3.2 `coordinationSignalList` 🆕 (LIVE Widget row 232) ← inti H1

List "Perlu Tindakan": sinyal **mandek** lintas-koleksi (task/stock_location/vehicle_check/evidence), **diklaster per tipe**, **diurut umur**, tiap item 1 tombol aksi. Sebagian aksi **nyebrang ke Gudang**.

**Taksonomi (4 tipe, gate via param):**

| tipe | gate (derive) | holder | aksi | domain |
|---|---|---|---|---|
| unassigned_vehicle | `tst◼assigned⭘vv◼` (vv kosong) | `kn` | **Tugaskan** → vehiclePicker (set vv) | Admin |
| task_returned | `tst◼load_rejected` | `kn` | **Assign Ulang** → vehiclePicker | Admin |
| no_executor | `lt◼vehicle⭘dv◼` (dv kosong) | `ln` | **Tunjuk di Gudang ⇄** | CROSS→Gudang |
| blocked_departure | `cty◼opening⭘cst◼awaiting_custody` | `ln` | **Lihat di Gudang ⇄** (soft) | CROSS→Gudang |

**Param:** status 3-tier theme via `dangerAge`/`warnAge` (menit). Cluster diurut maxAge desc. `text` 9-segment: `[section]◆[act1..4]◆[clusterTpl5..8]`; segmen 5-8 prefix `{n} ` (cluster count, resolved in-widget `.replaceAll`). Assign → `updateEventRow` scalar task.vv+tst (BUKAN array). Cross → `crossRoute`+`crossRouteParams:"vehicleId◼{vehicleId}"` (destKey `vehicleId` CONFIRMED). `reasonSearch` evidence `ept◼task⭘erf◼{tnm}` + `ec`/`d` (alasan task_returned).

**JSON resolved (H1):**
```json
{"type":"COORDINATION_SIGNAL_LIST","vidtable":"20342033315492","table":"84214220504259//task","vehicleTable":"84214220504259//stock_location","checkTable":"84214220504259//vehicle_check","evidenceTable":"84214220504259//evidence","statusField":"tst","vehicleField":"vv","customerNameField":"kn","addressField":"al","scheduleField":"tdt","itemsField":"it","plateField":"ln","driverField":"dv","checkTypeField":"cty","checkStatusField":"cst","reasonSearch":"ept◼task⭘erf◼{tnm}","reasonCatField":"ec","reasonNoteField":"d","unassignedGate":"tst◼assigned⭘vv◼","returnedGate":"tst◼load_rejected","noExecutorGate":"lt◼vehicle⭘dv◼","blockedGate":"cty◼opening⭘cst◼awaiting_custody","assignSheet":"vehiclePicker","updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{taskVid}⭘vv◼{vehicleId}⭘tst◼assigned","crossRoute":"vertikaTeknoLokaciptaWarehouseFeed","crossRouteParams":"vehicleId◼{vehicleId}","dangerAge":90,"warnAge":30,"text":"Perlu Tindakan◆Tugaskan◆Assign Ulang◆Tunjuk di Gudang◆Lihat di Gudang◆{n} order menunggu kendaraan◆{n} order dikembalikan◆{n} belum ada pengantar◆{n} opening belum kelar"}
```

---

## 4. EXTEND — generic widgets (tambah param, jaga backward-compat)

### 4.1 `selectableGrid` ✳️ — tambah launcher mode

Sekarang: single-select button-grid, label-only, capture via `position` (◁N▷). **Tambah:** `mode:"launch"` + array `routes` + `icons` (◆-sep, index-align dgn `text`). Saat `mode:"launch"` → tap cell = **navigate `routes[i]`**, TIDAK capture. Tanpa `mode`/`routes` = selector lama (backward-compat).

**GENERIC:** launcher grid apapun (menu, kategori, shortcut).

**Routing H1 (FIX bug):** sekarang Customer Baru & Order Masuk dua-duanya → CreateTaskCustomer. Benerin: 👤 Customer Baru → `vertikaTeknoLokaciptaNewCustomer` (N1) · ➕ Order Masuk → `vertikaTeknoLokaciptaCreateTaskCustomer` (P1) · 🚶 Walk-in → `vertikaTeknoLokaciptaWalkIn` (W1). N1/W1 = forward-ref → cell inert sampe page jadi.

**JSON resolved (H1):**
```json
{"type":"SELECTABLE_BTN","mode":"launch","maxGrid":3,"text":"Customer Baru◆Order Masuk◆Walk-in","icons":"👤◆➕◆🚶","routes":"vertikaTeknoLokaciptaNewCustomer◆vertikaTeknoLokaciptaCreateTaskCustomer◆vertikaTeknoLokaciptaWalkIn"}
```

### 4.2 `noticeBar` ✳️ — tambah action button

Sekarang: variant→theme, 1–3 tier label/title/text, iconAlign. **Tambah:** `actionText` + `actionRoute` → render tombol CTA trailing, tap = navigate.

**Count DROP (decision-i):** count "{n} customer" = derived cross-collection (client tanpa GENESIS) → mahal + renderer baru. Banner transient (ilang abis seed). Count tampil di halaman Seed-nya sendiri pas admin tap Catat. noticeBar = pure-display, teks statik. **GENERIC:** banner + CTA apapun. `actionRoute`=`vertikaTeknoLokaciptaSeed` (S1, forward-ref).

**JSON resolved (H1):**
```json
{"type":"NOTICE_BAR","variant":"info","icon":"","text":"Sebagian customer migrasi belum tercatat saldo awal. Catat biar outstanding akurat.","actionText":"Catat","actionRoute":"vertikaTeknoLokaciptaSeed"}
```

---

## 5. NEW — 3 feed widgets (generic, config-driven)

> Ketiganya = list-of-cards tapi interaksi beda. Semua field/label/table = param (PRINSIP §0). Card shape acuan = mockup jsx.

### 5.1 `RUNNING_TASK_LIST` 🆕 — list progress read-only (Berjalan)

Mockup `ActiveCard`: plat (mono) + chip status + "executor · Stop x/y" + note. **Read-only** (gak ada aksi).

**Param:** `titleField` vv→plat via `vehicleTable`.`vehicleNameField` (ln). `execField` dv→nama via `workforceTable`.`nameField` (n). progress {dev} = `count(it[] where ad|ap present)/it[].length` → "Stop {done} dari {total}". `doneMarker` "ad,ap" = line done kalau ada `ad`(actual drop) ATAU `ap`(actual pickup), di-set CF. `noteField` opsional (stop terakhir, {dev}-derive). `status:ok` = tier fixed (badge ijo). `text` = `[badge]◆[progressPrefix]◆[progressSep]`.

**GENERIC:** list card "X/Y progress + 2-line content + note, read-only" — reusable progress list apapun (route patrol, batch produksi).

**JSON resolved (H1):**
```json
{"type":"RUNNING_TASK_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"tst◼on_delivery","titleField":"vv","vehicleTable":"84214220504259//stock_location","vehicleNameField":"ln","execField":"dv","workforceTable":"84214220504259//workforce","nameField":"n","itemsField":"it","doneMarker":"ad,ap","noteField":"","status":"ok","text":"Berjalan◆Stop◆dari"}
```

### 5.2 `UPCOMING_TASK_LIST` 🆕 — list + assign kondisional (Akan Datang)

Mockup `UpcomingCard`: customer + chip jadwal + summary item + (plat ATAU tombol +Tugaskan). Kalau `assignField` kosong → tombol assign → buka sheet → tulis balik.

**Param:** `assignField` vv kosong → tampil `assignText` button → buka `assignSheet` (vehiclePicker) → `updateEventRow` tulis vv (scalar, BUKAN array; `{taskVid}`=baris, `{vehicleId}`=pilihan). vv isi → tampil plat (`plateField` vv→`vehicleNameField` ln). `summaryField` it[] → roll-up drop/pickup {dev}. `{today}` = `todayEpochMidnightWib()` + 2-clause AND (tst◼assigned AND tdt◼today). `schedField` tdt → chip jadwal. `text` = `[section]◆[dropLabel]◆[pickupLabel]`.

**GENERIC:** list dimana baris bisa "belum lengkap" (field kosong) → tombol inline isi via sheet. Reusable: assign driver, pilih slot, lengkapi data.

**JSON resolved (H1):**
```json
{"type":"UPCOMING_TASK_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"tst◼assigned⭘tdt◼{today}","titleField":"kn","schedField":"tdt","summaryField":"it","assignField":"vv","plateField":"vv","vehicleTable":"84214220504259//stock_location","vehicleNameField":"ln","assignSheet":"vehiclePicker","assignText":"+ Tugaskan Kendaraan","updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{taskVid}⭘vv◼{vehicleId}","text":"Akan Datang◆kirim◆ambil"}
```

### 5.3 `OUTSTANDING_PANEL` 🆕 — collapsible aged-list (Prioritas Pengambilan)

Mockup `OutstandingPanel`: header collapsible "Prioritas Pengambilan ▾" + per baris chip aging + customer + "item · qty · {days} hari" + tombol Jadwalkan.

**Param:** `table` asset_cache `lt◼client`, `hideZero` TRUE (sembunyi qt net 0), `collapsible` TRUE (default open). `titleField` lv (client id) → name via `locationTable`.`locationNameField` (ln). days {dev} = `now − ageAnchorField`(t) hari; tier `dangerAge`>14 / `warnAge`>7 / else ok (warna theme); urut tertua atas. `actionText` Jadwalkan → `actionSheet` vehiclePicker (mode schedule → bikin pickup task). `text` = `[panelTitle]◆[qtyUnit]◆[ageUnit]◆[dangerLabel]◆[warnLabel]◆[okLabel]` (statusLabels relabel).

**GENERIC:** collapsible list ber-tier-umur + aksi per baris. Reusable: aging piutang, SLA breach, item kedaluwarsa.

**JSON resolved (H1):**
```json
{"type":"OUTSTANDING_PANEL","vidtable":"20342033315492","table":"84214220504259//asset_cache","search":"lt◼client","hideZero":"TRUE","collapsible":"TRUE","titleField":"lv","locationTable":"84214220504259//stock_location","locationNameField":"ln","itemField":"ii","qtyField":"qt","ageAnchorField":"t","dangerAge":14,"warnAge":7,"actionText":"Jadwalkan","actionSheet":"vehiclePicker","text":"Prioritas Pengambilan◆pcs◆hari◆Kritis◆Perhatian◆Normal"}
```

---

## 6. Sheet — `vehiclePicker` (reuse, LIVE Widget row 233)

Bottom-sheet pilih kendaraan, 3 mode (judul beda, list sama): `assign` (set vv), `reassign` (load_rejected→assigned+vv baru), `schedule` (outstanding→pickup task+vv). `captureToken:"vehicleId"` → caller (signal-list / upcoming / outstanding) yang nulis. Write = `updateEventRow` scalar (BUKAN array).

**JSON resolved (sheet):**
```json
{"type":"VEHICLE_PICKER","vidtable":"20342033315492","table":"84214220504259//stock_location","search":"lt◼vehicle","plateField":"ln","typeField":"ty","captureToken":"vehicleId","text":"Pilih Kendaraan◆task aktif◆Ad-hoc / Lainnya◆Kendaraan tidak tetap"}
```
> (field `typeField`/`text`-slot = draft; sinkron sama Widget row 233 live — confirm sebelum apply.)

---

## 7. Data dependencies

| koleksi | field | dipakai | peran |
|---|---|---|---|
| `task` | `tst`,`vv`,`kn`,`al`,`tdt`,`it`,`dv`,`tnm`,`t` | signal, upcoming, running | read + updateEventRow(vv) |
| `stock_location` (vehicle) | `ln`,`dv`,`ty` | header, signal, vehiclePicker, running | read |
| `stock_location` (client) | `ln` | outstanding | read |
| `vehicle_check` | `cty`,`cst`,`cdt`,`vv` | signal blocked, header | read |
| `asset_cache` (client) | `lv`,`ii`,`qt`,`t` | outstanding | read (CF-derived) |
| `evidence` | `ept`,`erf`,`ec`,`d` | alasan task_returned | read |
| `workforce` | `n` | header nama (#NAME), running executor | read |

**{dev}-computed (bukan field):** semua count (berjalan/sinyal/task aktif), umur mandek, aging hari, progress stop (it[] ad/ap), summary roll-up it[], status tier, "belum di-seed". Divisi kerja: config kasih rule, **dev hitung & render**. (lihat `feedback_widget_division_of_labor`)

**CF-dependency:** `asset_cache` di-derive movement CF (`docs/driver-runtime-movement-cf-handoff.md`); `it[].ad`/`ap` di-set CF on movement. Sampai CF live, running-progress + outstanding pakai seed sementara.

---

## 8. Write/DSL

H1 **read-only** kecuali assign (signal-list + upcoming) via `vehiclePicker`:
- assign/reassign = `updateEventRow` scalar `task.vv` (+`tst`) — DSL OK, **bukan array**.
- cross-Gudang = nav only, bawa `{vehicleId}` via `crossRouteParams`.
- Token runtime: `#NAME`, `{today}`, `{taskVid}`, `{vehicleId}`.

---

## 9. Open / decisions

1. **`unassigned_vehicle` ada di doctrine?** Create Task maksa pilih kendaraan di P3 → semua task lahir dgn `vv`. Kapan vv null? (a) pickup task draft dari Outstanding, (b) upcoming sengaja belum di-assign. **CONFIRM** apakah Admin bisa bikin task tanpa vv (draft). Kalau tidak → drop sinyal `unassigned_vehicle` + assign-button di upcoming.
2. **`schedule` mode** — sheet+assign aja, atau route ke Create Task pre-filled (customer+item dari outstanding)?
3. **`task_returned` alasan** — confirm evidence query (`ept◼task⭘erf◼{tnm}` `ec`+`d`) match cara driver nulis reject (`docs/driver-failed-delivery-sheet-dev-spec.md`).
4. **`asset_cache` aging anchor** — apakah `asset_cache` simpan `t` (last-movement ts)? Kalau keyed `lv__ii__cd` tanpa ts → aging butuh join ke movement terakhir. **CONFIRM field** (`ageAnchorField` di OUTSTANDING_PANEL).
5. **Header plat koordinasi** — admin koordinasi punya kendaraan sendiri, atau hilangin baris plat? (mockup nampilin plat statis "B 1234 XY").
6. **selectableGrid launcher** — `mode:"launch"`+`routes`/`icons` array baru: confirm renderer mau additive param ini, atau lebih milih widget launcher terpisah.
7. **vehiclePicker JSON** (§6) = draft (`typeField`/text-slot); confirm vs Widget row 233 live.

---

## 10. Build order (saran)
1. EXTEND `selectableGrid` (+launcher) + `noticeBar` (+action) — kecil, additive, unblock quick-action + nudge.
2. `RUNNING_TASK_LIST` (read-only, no write) — warm-up renderer baru.
3. `OUTSTANDING_PANEL` (collapsible + tier umur).
4. `UPCOMING_TASK_LIST` (+ assign sheet write).
5. `coordinationSignalList` (paling berat — derive lintas-koleksi) — udah dispek, finalize renderer.

> Semua widget §0-compliant: label di `text` ◆, table/search/field param, status theme-tier, route param. Reusable case manapun. JSON jadi per widget di tiap § + `json/admin-runtime/*.json`.
