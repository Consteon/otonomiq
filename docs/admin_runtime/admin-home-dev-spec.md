# Admin Home (H1) — Dev Spec

**Page:** `AdminHome` · Admin Runtime (Koordinasi) · mobile op1Screen
**Route key:** `vertikaTeknoLokaciptaAdminHome` (op1Screen row 1145)
**Entry point:** first screen Admin runtime. Bukan create-flow — ini **triage / command center**: lihat yang mandek → lempar ke aksi (Create Task / Gudang).
**Mockup:** `src/component/ConsteonAdminHomeEvolved.jsx` → `AdminHomeView` (mounted via `AdminRuntimeGallery2.jsx`, Frame H1)
**Doctrine:** Admin = koordinasi. Assign order ke **kendaraan** (recon container), bukan orang. Siapa nyetir ditentukan di Gudang. Sinyal lintas-runtime (no_executor / blocked_departure) **nyebrang ke Gudang**, bukan diselesaikan Admin.

> Status legend: ✅ reuse (renderer BUILT) · ✳️ EXTEND (renderer ada, tambah param) · 🆕 NEW (bikin renderer + Widget template)

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
**KEEP (2, dedicated, udah dispek terpisah di §3):** `adminCoordinationHeader`, `coordinationSignalList`.
**Sheet (overlay, reuse):** `vehiclePicker` — dipicu signal-list / upcoming / outstanding.

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
       ├─ [label] Perlu Tindakan    (di dalam coordinationSignalList header)
       ├─ coordinationSignalList
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

## 3. KEEP — dedicated widgets (udah ada, contract tetap)

### 3.1 `adminCoordinationHeader` 🆕 (dispek, live row 231)

Bar biru atas. Identitas koordinator + ringkasan beban + switch runtime.

**Display (mockup `IdentityZone`):** icon 🗺️ + "Koordinasi" · baris-2 `{nama}` · `{plat}` · 2 chip `{N} berjalan`/`{N} sinyal` · tombol "⇄ Ganti"→launcher.

**Data binding:** nama dibaca dari token **`#NAME`** (bukan workforce lookup). `{N} berjalan`/`{N} sinyal` = {dev} count (konsisten dgn widget #2 / #6). `switchRoute:""` → tombol Ganti hidden (set launcher route kalau ada).

**Config (live):**
```
type: ADMIN_COORDINATION_HEADER
vidtable, taskTable, vehicleTable, checkTable, evidenceTable   # buat compute chip
switchRoute: ""
text: "Koordinasi◆⇄ Ganti◆berjalan◆sinyal"
```

### 3.2 `coordinationSignalList` 🆕 (dispek, live row 232) ← inti H1

List "Perlu Tindakan": sinyal **mandek** lintas-koleksi, **diklaster per tipe**, **diurut umur**, tiap item 1 tombol aksi. Sebagian aksi **nyebrang ke Gudang**.

**Taksonomi (4 tipe, gate via param):**

| tipe | gate (derive) | holder | aksi | domain |
|---|---|---|---|---|
| unassigned_vehicle | `tst◼assigned⭘vv◼` (vv kosong) | `kn` | **Tugaskan** → vehiclePicker (set vv) | Admin |
| task_returned | `tst◼load_rejected` | `kn` | **Assign Ulang** → vehiclePicker | Admin |
| no_executor | `lt◼vehicle⭘dv◼` (dv kosong) | `ln` | **Tunjuk di Gudang ⇄** | CROSS→Gudang |
| blocked_departure | `cty◼opening⭘cst◼awaiting_custody` | `ln` | **Lihat di Gudang ⇄** (soft) | CROSS→Gudang |

**Status 3-tier:** umur → `danger`(>`dangerAge`)/`warn`(>`warnAge`)/`ok`, warna theme. Cluster diurut maxAge desc. `{n}`-prefix di text[5..8] = cluster count (resolved in-widget via `.replaceAll`).

**Write:** assign → `updateEventRow` scalar `task.vv`+`tst◼assigned` (token `{vehicleId}`/`{taskVid}`). Cross → nav `crossRoute`+`crossRouteParams:"vehicleId◼{vehicleId}"` (destKey `vehicleId` CONFIRMED vs WarehouseOpeningCheck).

**Config (live):** lihat op1Screen row 1145 child #2 / Widget row 232 (lengkap: gate, reasonSearch evidence `ept◼task⭘erf◼{tnm}`+`ec`/`d`, assignSheet, dangerAge:90/warnAge:30, text 9-segment).

---

## 4. EXTEND — generic widgets (tambah param, jaga backward-compat)

### 4.1 `selectableGrid` ✳️ — tambah launcher mode

Sekarang: single-select button-grid, label-only, capture via `position` (◁N▷). **Tambah:** `mode:"launch"` + array `routes` + `icons` (◆-sep, index-align dgn `text`). Saat `mode:"launch"` → tap cell = **navigate `routes[i]`**, TIDAK capture.

**Config baru:**
```
type: SELECTABLE_BTN
mode: "launch"            # default "select" (existing) → backward-compat
maxGrid: 3
text:   "Customer Baru◆Order Masuk◆Walk-in"      # label per cell
icons:  "👤◆➕◆🚶"                                  # ikon per cell (opsional)
routes: "[ROUTE_NEWCUSTOMER]◆[ROUTE_ORDER]◆[ROUTE_WALKIN]"   # route per cell
```

**Generic:** launcher grid apapun (menu, kategori, shortcut). Renderer: kalau `routes` ada + `mode=launch` → launcher; else → selector lama.

**Routing H1 (FIX bug):** sekarang Customer Baru & Order Masuk dua-duanya → CreateTaskCustomer. Benerin:
| cell | route |
|---|---|
| 👤 Customer Baru | `vertikaTeknoLokaciptaNewCustomer` (N1) |
| ➕ Order Masuk | `vertikaTeknoLokaciptaCreateTaskCustomer` (P1) |
| 🚶 Walk-in | `vertikaTeknoLokaciptaWalkIn` (W1) |

N1/W1 = forward-ref (belum dibangun) → cell inert sampe page jadi. Wajar.

### 4.2 `noticeBar` ✳️ — tambah action button

Sekarang: variant→theme, 1–3 tier label/title/text, iconAlign. **Tambah:** `actionText` + `actionRoute` → render tombol CTA trailing, tap = navigate.

**Config (genesis nudge):**
```
type: NOTICE_BAR
variant: "info"            # violet/info tier dari theme
text: "Sebagian customer migrasi belum tercatat saldo awal. Catat biar outstanding akurat."
actionText: "Catat"
actionRoute: "[ROUTE_SEED]"   # vertikaTeknoLokaciptaSeed (S1, forward-ref)
```

**Count DROP (decision (i)):** count "{n} customer" = derived cross-collection (client tanpa GENESIS) → mahal + renderer baru. Banner transient (ilang abis seed). Count tampil di halaman Seed-nya sendiri pas admin tap Catat. noticeBar = pure-display, teks statik. **Generic:** banner + CTA apapun.

---

## 5. NEW — 3 feed widgets (generic, config-driven)

> Ketiganya = list-of-cards tapi interaksi beda. Semua field/label/table = param (PRINSIP §0). Card shape acuan = mockup jsx.

### 5.1 `RUNNING_TASK_LIST` 🆕 — list progress read-only (Berjalan)

Mockup `ActiveCard`: plat (mono) + chip status + "executor · Stop x/y" + note. **Read-only** (gak ada aksi).

**Config:**
```
type: RUNNING_TASK_LIST
vidtable, table: "[TABLE]"            # 84214220504259//task
search: "[SEARCH]"                     # tst◼on_delivery
titleField: "[F]"                      # vv → plat via vehicle lookup
vehicleTable / vehicleNameField        # vv → stock_location.ln (plat)
execField: "[F]"                       # dv → executor via workforce lookup
workforceTable / nameField             # dv → workforce.n
itemsField: "it"                       # progress source
doneMarker: "ad,ap"                    # it[] line dianggap done kalau ada ad ATAU ap (CF-set)
noteField: "[F]"                       # note (stop terakhir) — opsional
status: "ok"                           # tier fixed (badge ijo)
text: "Berjalan◆Stop◆dari"             # [badge]◆[progressPrefix]◆[progressSep]
```

**Derived {dev}:** progress = `count(it[] where ad|ap present) / it[].length` → render "Stop {done} dari {total}". plat/executor via lookup.

**Generic:** list card "X/Y progress + 2-line content + note, read-only" — reusable progress list apapun (route patrol, batch produksi, dst).

### 5.2 `UPCOMING_TASK_LIST` 🆕 — list + assign kondisional (Akan Datang)

Mockup `UpcomingCard`: customer + chip jadwal + summary item + (plat ATAU tombol +Tugaskan). Kalau `assignField` kosong → tampil tombol assign → buka sheet → tulis balik.

**Config:**
```
type: UPCOMING_TASK_LIST
vidtable, table: "[TABLE]"             # task
search: "[SEARCH]"                      # tst◼assigned⭘tdt◼{today}
titleField: "kn"                        # customer
schedField: "tdt"                       # chip jadwal
summaryField: "it"                      # roll-up drop/pickup {dev}
assignField: "vv"                       # kosong → tombol assign; isi → tampil plat
plateField / vehicleTable / vehicleNameField   # vv → ln
assignSheet: "vehiclePicker"
assignText: "+ Tugaskan Kendaraan"
updateEventRow: "[TABLE]⭘tablevid◼[VID]⭘search◼tnm★{taskVid}⭘vv◼{vehicleId}"
text: "Akan Datang◆kirim◆ambil"         # [section]◆[dropLabel]◆[pickupLabel]
```

**Derived {dev}:** summary roll-up dari `it[]` (mis "Drop 6 · Pickup 5"). `{today}` = `todayEpochMidnightWib()` + 2-clause AND (tst◼assigned AND tdt◼today).

**Generic:** list dimana baris bisa "belum lengkap" (field kosong) → tombol inline isi via sheet. Reusable: assign driver, pilih slot, lengkapi data.

### 5.3 `OUTSTANDING_PANEL` 🆕 — collapsible aged-list (Prioritas Pengambilan)

Mockup `OutstandingPanel`: header collapsible "Prioritas Pengambilan ▾" + per baris chip aging + customer + "item · qty · {days} hari" + tombol Jadwalkan.

**Config:**
```
type: OUTSTANDING_PANEL
vidtable, table: "[TABLE]"             # 84214220504259//asset_cache
search: "[SEARCH]"                      # lt◼client
hideZero: "TRUE"                        # sembunyi qt net 0
collapsible: "TRUE"                     # default open
titleField: "lv"                        # client → name via lookup (lv → stock_location.ln)
locationTable / locationNameField       # lv → ln
itemField: "ii"
qtyField: "qt"
ageAnchorField: "t"                     # timestamp last movement → days = now − t
dangerAge: 14                           # hari → tier danger
warnAge: 7                              # hari → tier warn (else ok)
actionText: "Jadwalkan"
actionSheet: "vehiclePicker"            # mode schedule → bikin pickup task
text: "Prioritas Pengambilan◆pcs◆hari◆Kritis◆Perhatian◆Normal"
        # [panelTitle]◆[qtyUnit]◆[ageUnit]◆[dangerLabel]◆[warnLabel]◆[okLabel]
```

**Derived {dev}:** days = `now − ageAnchorField` (hari). Tier by dangerAge/warnAge. Urut tertua dulu (umur = horizon, gak ada cutoff jam). statusLabels relabel via text[3..5].

**Generic:** collapsible list ber-tier-umur + aksi per baris. Reusable: aging piutang, SLA breach, item kedaluwarsa.

---

## 6. Sheet — `vehiclePicker` (reuse, live row 233)

Bottom-sheet pilih kendaraan, 3 mode (judul beda, list sama): `assign` (set vv), `reassign` (load_rejected→assigned+vv baru), `schedule` (outstanding→pickup task+vv). `captureToken:"vehicleId"` → caller (signal-list / upcoming / outstanding) yang nulis. Write = `updateEventRow` scalar (BUKAN array). Detail di spec lama / Widget row 233.

---

## 7. Data dependencies

| koleksi | field | dipakai | peran |
|---|---|---|---|
| `task` | `tst`,`vv`,`kn`,`al`,`tdt`,`it`,`dv`,`tnm`,`t` | signal, upcoming, running | read + updateEventRow(vv) |
| `stock_location` (vehicle) | `ln`,`dv`,type | header, signal, vehiclePicker, running | read |
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
4. **`asset_cache` aging anchor** — apakah `asset_cache` simpan `t` (last-movement ts)? Kalau keyed `lv__ii__cd` tanpa ts → aging butuh join ke movement terakhir. CONFIRM field.
5. **Header plat koordinasi** — admin koordinasi punya kendaraan sendiri, atau hilangin baris plat? (mockup nampilin plat statis "B 1234 XY").
6. **selectableGrid launcher** — `mode:"launch"`+`routes`/`icons` array baru: confirm renderer mau additive param ini, atau lebih milih widget launcher terpisah.

---

## 10. Build order (saran)
1. EXTEND `selectableGrid` (+launcher) + `noticeBar` (+action) — kecil, additive, unblock quick-action + nudge.
2. `RUNNING_TASK_LIST` (read-only, no write) — warm-up renderer baru.
3. `OUTSTANDING_PANEL` (collapsible + tier umur).
4. `UPCOMING_TASK_LIST` (+ assign sheet write).
5. `coordinationSignalList` (paling berat — derive lintas-koleksi) — udah dispek, finalize renderer.

> Semua widget §0-compliant: label di `text` ◆, table/search/field param, status theme-tier, route param. Reusable case manapun.
