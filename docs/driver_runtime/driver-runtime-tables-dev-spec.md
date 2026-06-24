# Driver Runtime — Firestore Tables Dev Spec

**Audience:** developer yang implement Driver Runtime (galon/gas delivery).
**Status:** schema sudah disepakati; field code sudah masuk dictionary `1_XHmo5…` (tab: `item`, `stock_location`, `task`, `movement`, `vehicle_check`, `evidence`, `investigation`, `asset_cache`).
**Acuan lain:** flow naratif → `driver-runtime-phase1-driver-babylang.md` · field code → `driver-runtime-field-dictionary.md` · perubahan dari schema tech lead → `driver-runtime-techlead-schema-deltas.md`.

---

## 1. Konsep inti (wajib paham dulu)

1. **Movement Ledger = source of truth.** Stok TIDAK disimpan sebagai angka yang diedit. Stok = hasil hitung dari riwayat `movement`. Tiap barang pindah = 1 baris `movement` (append-only).
2. **`asset_cache` = derived state.** Ditulis HANYA oleh Cloud Function (CF). **Tidak ada app yang menulis `asset_cache` langsung** — app hanya BACA. CF trigger tiap `movement` masuk → update saldo di `from` (kurang) & `to` (tambah).
3. **Lokasi disatukan.** Gudang, mobil, customer = satu collection `stock_location`, dibedakan `lt` (location_type). Pengiriman = stok pindah `vehicle → client`. Outstanding customer = saldo `asset_cache` di lokasi client itu.
4. **Kondisi first-class.** Item returnable (galon/tabung) dilacak per `cd` = `full` | `empty`. Saldo dipisah per kondisi (2 baris cache per item per lokasi).
5. **`occurred_at` (`t`) ≠ `synchronized_at` (`et`).** `t` diset di device saat kejadian (valid walau offline). `et` diset server saat doc masuk. Jangan disamakan.

---

## 2. Di mana data tinggal (path)

Semua collection nested di bawah container tenant (mengikuti struktur live):

```
MobileTable / {db} / tables / {tableVID}/          ← tenant boundary
   ├─ workforce        (EXISTING) ← orang; driver = 1 doc, dikunci `VID`
   ├─ site             (EXISTING)
   ├─ event            (EXISTING) ← ledger audit universal
   ├─ item
   ├─ stock_location
   ├─ task
   ├─ movement
   ├─ vehicle_check
   ├─ evidence
   ├─ investigation
   └─ asset_cache
```

- **Tenant = path**, jadi **tidak ada field `tenant_id`** di dokumen. Security Rules enforce tenant dari path.
- `event` = ledger audit yang sudah ada (dipakai bersama fitur lain). `movement` = ledger stok khusus driver (terpisah dari `event`).

---

## 3. Tiga cara menulis (model write)

| Mode | Operasi | Collection | DSL |
|---|---|---|---|
| **APPEND** | tambah doc baru, tidak pernah diedit/dihapus | `movement`, `evidence`, `vehicle_check`, `event` | `addToEvent` |
| **UPDATE (sparse)** | edit hanya field yang dikirim; field lain tidak tersentuh; cari doc via `search` | `task`, `investigation`, `workforce` | `updateEventRow` |
| **ROBOT** | app tidak menulis; Cloud Function only; app hanya BACA | `asset_cache` | — |

- **`updateEventRow` itu sparse + tidak support map.** Yang dikirim hanya field yang berubah. Cari doc target pakai `search` (compound `★`/`☆`). Karena tidak support nested-map update, struktur sengaja FLAT — tiap item line jadi baris collection sendiri (lihat `movement`), bukan map.
- **Envelope** tiap doc yang ditulis via DSL: `r` (retention, wajib), `tablevid`, `p`, `et`, `ev`, plus `t`/`ts`. Detail envelope ada di tab `addToEvent` dictionary.

---

## 4. Relasi antar-collection

```
stock_location ◄── task          (kl client, gl warehouse, vv vehicle)
               ◄── movement       (fl from, tl to)
               ◄── vehicle_check   (vv vehicle, gl warehouse)
               ◄── asset_cache     (lv location)
item           ◄── task.it[] · movement.ii · vehicle_check.ip/ie/dp · asset_cache.ii
task           ◄── movement.mrf · evidence.erf(ept=task)
movement       ──► asset_cache     (via Cloud Function, on write)
movement/check ──► investigation   (discrepancy → investigation.vrf)
evidence       ──► movement|task|check|investigation  (erf + ept)
workforce(VID) ◄── cv/cn aktor (task admin · check checker · evidence uploader · investigation supervisor); movement actor = dv/dn
```

---

## 5. Spesifikasi per collection

> Notasi: **id/key** = field yang di-Index (query). Tipe & allowed values lengkap ada di dictionary sheet.

### 5.1 `item` — master barang
Definisi barang. Seed oleh admin.

| code | field | tipe | catatan |
|---|---|---|---|
| `ii` 🔑 | item id | String | `galon`, `tabung_12kg` |
| `in` | nama | String | "Galon Air 19L" |
| `ic` | kategori | `returnable`\|`consumable` | returnable = ada siklus isi/kosong |
| `tc` | kondisi dilacak | Array `[full,empty]` (returnable) / `[full]` (consumable) | kondisi yg dilacak |
| `un` | unit | `pcs`\|`kg` | |
| `ist` 🔑 | status | `active`\|`inactive` | |

```json
{ "ii":"galon", "in":"Galon Air 19L", "ic":"returnable", "tc":["full","empty"], "un":"pcs", "ist":"active" }
```

### 5.2 `stock_location` — gudang / mobil / customer (1 collection)
| code | field | tipe | catatan |
|---|---|---|---|
| `lv` 🔑 | location id | String | `WH-bintaro`, `VEH-B1234XY`, `CLT-honda` |
| `lt` 🔑 | tipe | `warehouse`\|`vehicle`\|`client` | pembeda jenis lokasi |
| `ln` | nama | String | "B-1234-XY", "Honda Bintaro" |
| `al` | alamat | String? | null untuk vehicle |
| `la`/`lo` | geo lat/long | Number? | |
| `dv` | driver aktif | String? | **vehicle only** — driver hari ini |
| `lst` 🔑 | status | `active`\|`inactive` | |

```json
{ "lv":"VEH-B1234XY", "lt":"vehicle", "ln":"B-1234-XY", "dv":"87544551624342", "lst":"active" }
{ "lv":"CLT-honda", "lt":"client", "ln":"Honda Bintaro", "al":"Jl. ...", "la":-6.31, "lo":106.64, "lst":"active" }
```

### 5.3 `task` — 1 stop pengiriman/pickup
Dibuat admin (`assigned`), di-UPDATE driver (→ `completed`). UPDATE sparse via `search`.

| code | field | tipe | catatan |
|---|---|---|---|
| `tnm` 🔑 | task no (id) | String | `TASK-20260612-001` |
| `tty` 🔑 | task_type | `delivery`\|`pickup_return` | |
| `tst` 🔑 | execution_state | draft\|assigned\|ready\|on_delivery\|completed\|validated\|closed | lifecycle |
| `kl` | lokasi customer (FK) | →`stock_location` | |
| `kn` | nama customer (denorm) | String | buat tampil |
| `al` | alamat (denorm) | String | buat tampil |
| `gl` | gudang asal | →`stock_location` | |
| `vv` | mobil | →`stock_location` | |
| `cv`/`cn` | dibuat oleh (admin) | String | |
| `tdt` 🔑 | scheduled_date | String `YYYY-MM-DD` | simpan mentah, format di widget |
| `it` | items | Array `[{ii,in,cdo,cdi,pd,pp,ad,ap}]` | plan vs aktual (drop+pickup) |
| `t` | created_at | Number epoch | |
| `tce` | completed_at | Number epoch | diset saat submit |
| `search` 🔑 | kunci cari | String | `tnm★TASK-…` |

`it[]`: `ii` item · `in` nama · `cdo` cond_out · `cdi` cond_in · `pd` planned_drop · `pp` planned_pickup · `ad` actual_drop · `ap` actual_pickup

```json
{ "tnm":"TASK-20260612-001", "tty":"delivery", "tst":"assigned",
  "kl":"CLT-honda", "kn":"Honda Bintaro", "al":"Jl. Bintaro Utama 3A",
  "gl":"WH-bintaro", "vv":"VEH-B1234XY",
  "cv":"87544551624342", "cn":"Admin Gudang", "tdt":"2026-06-12",
  "it":[{"ii":"galon","in":"Galon Air 19L","cdo":"full","cdi":"empty","pd":5,"pp":5,"ad":null,"ap":null}],
  "search":"tnm★TASK-20260612-001" }
```

### 5.4 `movement` — ledger pindah (APPEND-ONLY)
Tiap barang pindah = 1 doc. **Tidak boleh diedit/dihapus.** Koreksi hanya via doc baru `mt:ADJUSTMENT` (Supervisor). CF baca tiap movement → update `asset_cache`.

| code | field | tipe | catatan |
|---|---|---|---|
| `mt` 🔑 | movement_type | GENESIS\|DROP\|PICKUP\|INTERNAL\|SALE\|DAMAGE\|LOST\|ADJUSTMENT | qty selalu positif; arah dari type |
| `fl` | from_location | →`stock_location`? | null = GENESIS |
| `tl` | to_location | →`stock_location`? | null = LOST/DAMAGE |
| `ii` | item | →`item` | |
| `cd` | kondisi | `full`\|`empty` | |
| `qt` | qty | Number >0 | selalu positif |
| `dv`/`dn` | driver yg scan | String | aktor; **≠ id login** (login dipegang di sesi) |
| `mrf` | ref task | →`task.tnm`? | null = GENESIS/ADJUSTMENT |
| `t`/`ts` 🔑 | occurred_at | Number/String | waktu device |
| `et` | synchronized_at | Number | waktu server |
| `er` | emitter_runtime | DRIVER\|VEHICLE\|SUPERVISOR | app asal |
| `d` | notes | String? | |

```json
{ "mt":"DROP", "fl":"VEH-B1234XY", "tl":"CLT-honda",
  "ii":"galon", "cd":"full", "qt":5,
  "dv":"87544551624342", "dn":"Budi Santoso", "mrf":"TASK-20260612-001",
  "t":1781163662868, "et":1781163700000, "er":"DRIVER" }
```

### 5.5 `vehicle_check` — custody opening + rekonsiliasi closing (APPEND)
Diisi **driver** (yg hitung) — loader gudang (`gv`/`gn`) aktor beda. 2 doc/hari: `opening` (custody muatan awal) & `closing` (rekonsiliasi sisa). `ie` = manifest gudang: keisi saat **OPENING** (dibanding vs `ip` driver di P6 reveal) + closing (server-computed dari movement); driver submit fisik (`ip`). **Opening doc = anchor 1 TRIP** (1 driver=1 vehicle=1 trip SEKARANG; future driver bisa N trip & pilih duluan); `cst` = status trip; link task↔trip via `(vv, tanggal)`.

| code | field | tipe | catatan |
|---|---|---|---|
| `cnm` 🔑 | check no | String | `CHK-VEH-B1234XY-20260612` |
| `cty` 🔑 | check_type | `opening`\|`closing` | |
| `cst` | trip/custody status (NEW) | enum | loading→awaiting_custody→custody_confirmed/discrepancy→on_delivery→returning→closed |
| `vv` | mobil | →`stock_location` | |
| `gl` | gudang | →`stock_location` | |
| `cv`/`cn` | checker = driver | String | |
| `cdt` 🔑 | check_date | `YYYY-MM-DD` | |
| `ip` | items_physical | Array `[{ii,cd,qt}]` | hitung tangan |
| `ie` | items_expected (manifest gudang) | Array `[{ii,cd,qt}]` | keisi OPENING (banding vs `ip`, P6) + closing (server) |
| `rs` | reconciliation_state | `matched`\|`discrepancy_detected` | closing |
| `dp` | discrepancies | Array `[{ii,cd,ex,ac,dl}]` | ex expected, ac actual, dl delta |
| `t` 🔑 | occurred_at | Number | |
| `gv`/`gn` | loader gudang vid/nama ("dimuat oleh") | String | **gudang-flow, FUTURE** |
| `ldt` | load datetime (jam muat) | Number epoch | **gudang-flow, FUTURE** |

```json
{ "cnm":"CHK-VEH-B1234XY-20260612-C", "cty":"closing",
  "vv":"VEH-B1234XY", "gl":"WH-bintaro", "cv":"87544551624342", "cn":"Budi",
  "cdt":"2026-06-12",
  "ip":[{"ii":"galon","cd":"full","qt":24}],
  "ie":[{"ii":"galon","cd":"full","qt":25}],
  "rs":"discrepancy_detected",
  "dp":[{"ii":"galon","cd":"full","ex":25,"ac":24,"dl":-1}],
  "t":1781190000000 }
```

### 5.6 `evidence` — foto / gps / ttd / note (APPEND)
Tiap bukti = 1 doc, nempel ke induk via `erf` + `ept`.

| code | field | tipe | catatan |
|---|---|---|---|
| `ety` 🔑 | evidence_type | photo\|gps\|signature\|notes | |
| `erf` 🔑 | ref induk | id | |
| `ept` | tipe induk | movement\|task\|check\|investigation | |
| `i` | storage_path | URL? | photo/signature |
| `la`/`lo` | gps | Number? | type=gps |
| `d` | content | String? | type=notes |
| `cv`/`cn` | uploaded_by | String | |
| `t` 🔑 | occurred_at | Number | |

```json
{ "ety":"photo", "erf":"TASK-20260612-001", "ept":"task",
  "i":"gs://bucket/photo.jpg", "cv":"87544551624342", "t":1781163662868 }
```

### 5.7 `investigation` — tindak lanjut selisih (UPDATE sparse)
Dibuka saat `vehicle_check.rs = discrepancy_detected`. Diselesaikan Supervisor. Subcollection `investigation/{id}/events` untuk audit trail.

| code | field | tipe | catatan |
|---|---|---|---|
| `vnm` 🔑 | inv no | String | `INV-2026-001` |
| `vst` 🔑 | investigation_state | pending_review\|under_investigation\|clarification_requested\|resolved\|closed | |
| `rt` | resolution_type | clean\|with_adjustment\|damage_confirmed\|loss_confirmed | |
| `vrf` 🔑 | sumber | id | check/movement |
| `vpt` | tipe sumber | check\|movement | |
| `cv`/`cn` | supervisor | String | |
| `t` 🔑 | opened_at | Number | |
| `vce` | resolved_at | Number | |
| `search` 🔑 | kunci cari | String | `vnm★INV-…` |

> **Selisih ≠ ilang.** Tidak boleh langsung `loss_confirmed` tanpa resolusi Supervisor. Koreksi stok hanya via `movement` `mt:ADJUSTMENT/LOST` oleh Supervisor.

### 5.8 `asset_cache` — saldo (ROBOT tulis, app BACA)
Doc id = `{lv}__{ii}__{cd}` (cth `VEH-B1234XY__galon__full`).

| code | field | tipe | catatan |
|---|---|---|---|
| `lv` 🔑 | location | →`stock_location` | |
| `lt` 🔑 | location_type | warehouse\|vehicle\|client | denorm filter cepat |
| `ii` 🔑 | item | →`item` | |
| `cd` 🔑 | kondisi | full\|empty | |
| `qt` | qty terkini | Number | client = **outstanding** |
| `lm` | last_movement | →`movement` | |
| `t` | last_movement_at | Number | |
| `et` | last_computed_at | Number | waktu CF tulis |

```json
// doc id: VEH-B1234XY__galon__full
{ "lv":"VEH-B1234XY", "lt":"vehicle", "ii":"galon", "cd":"full",
  "qt":25, "lm":"mov-abc123", "t":1781163662868, "et":1781163700000 }
```

> `qt` tidak pernah null setelah hydration awal — tampilkan stale, jangan kosong.

---

## 6. Flow driver (read/write per page)

| Page | BACA | TULIS |
|---|---|---|
| **P2 Scan** | `workforce`(VID dari QR), `task`(driver+today) | `event`(audit) |
| **P4 Home** | `asset_cache`(mobil), `task`, `vehicle_check`(opening today?) | — |
| **P5–9 Custody** | `asset_cache`(mobil) | **`vehicle_check` cty=opening** + `evidence` + `event` |
| **P10 Feed** | `task` grouped by `tst` | — |
| **P11 Anter** | `task`(1 stop) | **`movement` DROP/PICKUP** + UPDATE `task`(tst=completed, it.ad/ap, tce) + **`evidence`** → CF update `asset_cache` |
| **P12 Return** | `asset_cache`(mobil) | **`vehicle_check` cty=closing** + `movement` INTERNAL mobil→gudang → CF update cache |
| (selisih) | — | `investigation`(vst=pending_review) ; Supervisor → `movement` ADJUSTMENT |
| **S1 Pause** | `task`(sisa assigned) | UPDATE `workforce`(st) + `event` |

**Pola 1 stop (P11):** 1 submit driver → `movement` DROP (+PICKUP) → UPDATE `task` completed → `evidence` (photo/signature/gps) → CF benerin `asset_cache`. App tidak pernah menulis angka stok.

Contoh konkret (anter 5 isi, ambil 5 kosong ke Honda):
```
movement DROP    fl=VEH-B1234XY tl=CLT-honda ii=galon cd=full  qt=5
movement PICKUP  fl=CLT-honda tl=VEH-B1234XY ii=galon cd=empty qt=5
task     UPDATE  tst=completed  it[0].ad=5 it[0].ap=5  tce=<jam>
evidence x3      photo + signature + gps  (ept=task / movement)
─ CF ─►  asset_cache  VEH…full 30→25 · VEH…empty 0→5 · CLT-honda…full 0→5
```

---

## 7. Aturan implementasi (checklist dev)

1. `movement`, `evidence`, `vehicle_check` = **append-only**. Tidak ada update/delete.
2. `asset_cache` = **CF only**. App tidak pernah write. Kalau perlu angka stok, BACA cache (jangan hitung sendiri lalu tulis).
3. `t` (occurred_at) diset di device. `et` (synchronized_at / last_computed_at) diset server. Offline tetap valid.
4. UPDATE `task`/`investigation` = sparse via `updateEventRow`, cari pakai `search` (`★`/`☆`). Kirim hanya field berubah.
5. Koreksi stok hanya via `movement` `mt:ADJUSTMENT` oleh Supervisor. Tidak ada edit doc lama.
6. `ie` (items_expected) vehicle_check closing = **server-computed**. Client submit `ip` saja.
7. Outstanding customer = `asset_cache.qt` untuk `lt=client`. Tidak ada field outstanding manual.
8. Tenant dari **path** (`tables/{tableVID}/...`). Tidak ada field `tenant_id`.

---

## 8. Perbedaan dari schema tech lead asli (ringkas)
Schema asli `firebase-schema-galon.md`; perubahan disepakati ada di `driver-runtime-techlead-schema-deltas.md`:
- `tenant_id` field → dihapus (tenant ke path).
- `users` → pakai `workforce` existing (tanpa role/active).
- `stock_locations.home_warehouse_id` → dibuang.
- `driver_id` → movement `dv` = vid yang scan (≠ id login).
- `stock_cache` → `asset_cache`.
- `stock_location` & `movement` = collection terpisah (bukan reuse `site`/`event`).
- Field name = short code (lihat dictionary sheet).
- Custody dihitung **driver** (bukan checker).

---

## 9. Referensi
- Dictionary (field code + arti + fungsi): sheet `1_XHmo5NaSUXT0Ri6jtf1qvu-wdKZfUS9hSgYJAg2xAw` → tab `item`, `stock_location`, `task`, `movement`, `vehicle_check`, `evidence`, `investigation`, `asset_cache`; envelope DSL → tab `addToEvent`.
- Flow naratif bahasa-bayi: `driver-runtime-phase1-driver-babylang.md`.
- Delta vs tech lead: `driver-runtime-techlead-schema-deltas.md`.
- DSL: `file/addToEvent guide.txt`, `docs/2026-06-04-updateEventRow-design.md`.
