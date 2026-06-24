# P10 / P11 — Task Feed + Delivery Workspace Dev Spec

**Buat:** Flutter dev. Route-execution layer setelah custody (P4–P9). Grounded ke mockup `src/component/Driverruntimefull.jsx`: `TaskFeedScreen`(753) / `DeliveryExecutionWorkspace`(874) + sub-sheets (`SubmitConfirmSheet` 1192, `FailedDeliverySheet` 1469, `SignaturePad` 191).

**Flow:** P4 DriverHome → (Buka Tasklist) → **P10 TaskFeed** → tap stop → **P11 DeliveryWorkspace** → submit → balik P10 (state updated).

Route: P10 `vertikaTeknoLokaciptaTaskFeed` · P11 `vertikaTeknoLokaciptaDeliveryWorkspace`.

---

## STATUS — SHELL DULU (writes DEFERRED)

Diputus user 2026-06-18. P11 dibangun sebagai **viewable shell** karena WRITE-nya gantung di data-model/CF yang belum ada:

| write | kenapa deferred |
|---|---|
| item actuals → **movement** (DROP/PICKUP) | belum ada **CF** yang derive `task.it[].ad/ap` + `asset_cache`. User: "movement belakangan, belum ada CF." → `submitConfirmSheet.confirmEvent` = **kosong** sekarang. |
| `failedDeliverySheet.failEvent` | task SSOT belum punya field fail-reason (`fr`/sejenis) atau coll `delivery_event`. → `failEvent` = **kosong** sekarang. |
| active-task identity | P11 = 1 stop spesifik; nyebrang dari P10 tanpa passParams. Pakai token **`{activeTaskVid}`** (dev convert, sama konvensi `{}` lain). Search `tnm◼{activeTaskVid}`. |
| item write binding | per-item drop/pickup actual mau ditulis kemana → ikut keputusan movement/CF. |

Semua DSL write di P11 = **placeholder kosong**, diisi pas CF + schema-delta landing. Display/baca = grounded ke field existing → bisa dirender + demo sekarang.

---

## DESIGN DECISIONS (user 2026-06-18)

1. **signaturePad = widget BARU** (`SIGNATURE_PAD`).
2. ~~Header reuse `custodyStepHeader`~~ **SUPERSEDED 2026-06-18** (user: "samain mockup, widget baru"). → **dedicated `WORKSPACE_HEADER`** (§6) match mockup top-bar (id/stop/customer/Berjalan chip + address band).
3. **distance computed** (GPS site la/lo vs current), BUKAN field. Tidak ada `distance` di task SSOT.
4. **movement + CF = belakangan.**

---

## P10 — TaskFeed (LIVE 2026-06-18)

op1Screen page `vertikaTeknoLokaciptaTaskFeed` @1066. Reuse 2 varian-full dari widget P4:

| row | widget | type | catatan |
|---|---|---|---|
| 1067 | `routeProgressHeaderFull` (Widget 216) | `ROUTE_PROGRESS_HEADER` variant `full` | + `taskTable`/`taskSearch` → computed `{completed}/{failed}/{total}/{progress}/{totalDrop}/{actualDrop}/{totalPickup}/{actualPickup}`. `logoutRoute`→DriverHome (back). Spec v2 `driver-route-progress-header-dev-spec.md`. |
| 1068 | `driverStopCardFull` (Widget 217) | `DRIVER_STOP_CARD` variant `full` | grouped assigned/gagal/selesai dari `task` (`vv◼{vehicleId}⭘tdt◼{today}`). tap stop assigned → route `vertikaTeknoLokaciptaDeliveryWorkspace`. NO gate (post-custody = unlocked). Spec `driver-stop-card-dev-spec.md`. |

> P4 DriverHome "Buka Tasklist" route masih `""` → kalau mau nyambung P4→P10, wiring P4 terpisah.

---

## P11 — DeliveryWorkspace (SHELL LIVE 2026-06-18)

op1Screen page `vertikaTeknoLokaciptaDeliveryWorkspace` @1071. Widget rows:

**REVISI 2026-06-18 — dedicated widgets (match mockup), 6 children:**

| row | widget | type | status |
|---|---|---|---|
| 1072 | `workspaceHeader` (Widget 225, BARU) | `WORKSPACE_HEADER` | top-bar id/stop/customer/Berjalan + address band (§6) |
| 1073 | `itemExecutionList` (Widget 219) | `ITEM_EXECUTION_LIST` | per-item rows + hint label; rollup banner (partial/opportunistic/zero) = renderer-internal; write deferred |
| 1074 | `signaturePad` (Widget 220) | `SIGNATURE_PAD` | capture |
| 1075 | `evidenceRow` (Widget 226, BARU) | `EVIDENCE_ROW` | note/photo buttons (§6); write deferred |
| 1076 | `rbtCta` (Widget 210) | `RBT` | failed-report link "Tidak bisa dieksekusi · Lapor sebagai gagal" → trigger `failedDeliverySheet` (DO_DIALOG, deferred) |
| 1077 | `rbtCta` (Widget 210) | `RBT` | submit footer "Konfirmasi Pengiriman" → trigger `submitConfirmSheet` (DO_DIALOG, deferred) |

> Header reuse (`custodyStepHeader`) superseded. Submit/failed footer = `rbtCta` placeholder skrng (trigger sheet + write = deferred dgn movement/CF). Rollup banner folded ke `ITEM_EXECUTION_LIST` renderer.

### §6 widget BARU
**`workspaceHeader`** (`WORKSPACE_HEADER`, mockup `DeliveryExecutionWorkspace` 936-982): top-bar back `←`→`backRoute`(TaskFeed) + mono `{id} · Stop {stopNumber}` + customer (`kn` bold) + chip "Berjalan" (kanan); address band (driverAccentBg) `📍 {al}`. Reads active task (`tnm◼{activeTaskVid}`). stopNumber = route-order (derived). text 2 seg `Stop◆Berjalan`.
```json
{"type":"WORKSPACE_HEADER","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","idField":"tnm","titleField":"kn","addressField":"al","backRoute":"vertikaTeknoLokaciptaTaskFeed","text":"Stop◆Berjalan"}
```
**`evidenceRow`** (`EVIDENCE_ROW`, mockup 1011-1048): 2 tombol toggle — 📝 "Tambah Catatan" (aktif→"Catatan ditambah", buka EvidenceNoteSheet) / 📷 "Ambil Foto" (aktif→"Foto · 1"). text 6 seg. write deferred (`notePosition`/`photoPosition` finalize pas submit).
```json
{"type":"EVIDENCE_ROW","notePosition":7,"photoPosition":8,"text":"📝◆Tambah Catatan◆Catatan ditambah◆📷◆Ambil Foto◆Foto · 1"}
```

**Belum di page (published, modal-instantiated via DO_DIALOG nanti):** `submitConfirmSheet` (Widget 221), `failedDeliverySheet` (Widget 222).

---

## Widget templates BARU (Widget tab, 2026-06-18)

Type UPPERCASE_SNAKE; registry col-A camelCase (lihat konvensi). Published I+J only (col A/G/H = formula user-drag).

### `itemExecutionList` (Widget 219) — `ITEM_EXECUTION_LIST`
Array-list pattern (mirror `custodyCountList`): baca `table`+`search` → doc → iterate `itemsField` (`it`) → per item render nama (`in`) + type chip (returnable kalau `pp>0` else consumable) + drop stepper (`planned`=`pd`) + pickup stepper (`planned`=`pp`, hanya returnable). Per-cell status state-machine ikut `executionStepper` (partial/sesuai/opportunistic/extra — `execution-stepper-dev-spec.md` §6). **Fold:** spec asli pisah `executionStepper`(atom)+`itemExecutionRow`(composite); LIVE digabung jadi 1 list-widget krn item dinamis (presedent `custodyCountList` baca array). 

```json
{"type":"ITEM_EXECUTION_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","itemsField":"it","labelField":"in","planDropField":"pd","planPickupField":"pp","text":"Catat aktual · default = rencana, sesuaikan kalau beda◆Drop◆Pickup◆Partial · <kurang> kurang◆✓ Sesuai◆Opportunistic · <value>◆+<extra> extra◆plan◆Returnable◆Consumable◆💡 Customer juga punya tabung lama buat dibalikin? Tap [+] di pickup."}
```
text 11 seg: hint◆Drop◆Pickup◆partial◆complete◆opportunistic◆extra◆planlabel◆Returnable◆Consumable◆pickupHint.
**DEFERRED:** per-item actual write (drop/pickup) → movement; tambah `dropWriteField`/`pickupWriteField` atau emit form-position pas movement/CF diputus.

### `signaturePad` (Widget 220) — `SIGNATURE_PAD`
Canvas capture (mockup `SignaturePad` 191). State kosong (dashed border, placeholder) vs terisi (solid emerald, "Hapus", hint confirmed). Output = signature image → `writeField` (`sig`) / form `position` `◁N▷` saat submit.
```json
{"type":"SIGNATURE_PAD","optional":true,"position":3,"writeField":"sig","text":"✍️ Tap & tarik untuk tanda tangan customer◆Hapus◆Opsional · jika customer berkenan tanda tangan◆✓ Tanda tangan tersimpan · customer confirmed"}
```
text 4 seg: placeholder◆clearLabel◆hintEmpty◆hintFilled. `position` finalize pas layout submit final.

### `submitConfirmSheet` (Widget 221) — `SUBMIT_CONFIRM_SHEET`
Bottom-sheet review (spec `driver-submit-confirm-sheet-dev-spec.md`). Recap per-item aktual-vs-plan + totals + outcome banner (clean/partial/opportunistic, MASTER §3) + evidence checklist. Confirm = commit movement.
```json
{"type":"SUBMIT_CONFIRM_SHEET","source":"{FORM}","confirmEvent":"","text":"Konfirmasi Pengiriman◆Konfirmasi & Catat Movement◆Cek Lagi◆Total Drop◆Total Pickup◆Clean execution. Semua item sesuai rencana. Movement DROP/PICKUP akan dicatat.◆Partial execution akan dicatat. Sisa item yang kurang akan trigger follow-up coordination dengan admin.◆Clean + opportunistic pickup. Drop sesuai plan. Customer balikin lebih banyak — outstanding berkurang lebih banyak.◆Tanda tangan◆Catatan◆Foto◆Partial◆0◆Opportunistic◆extra"}
```
text 15 seg (spec §4). **DEFERRED:** `confirmEvent` = kosong (movement/CF belum ada). Pas landing → isi `addToEvent` DROP+PICKUP per item via `sendButtonGpsWithEvent` (`◁N▷` actuals).

### `failedDeliverySheet` (Widget 222) — `FAILED_DELIVERY_SHEET`
Bottom-sheet lapor gagal (spec `driver-failed-delivery-sheet-dev-spec.md`). Reason picker single-select (4 reason `code^label^desc~…`) + note opsional + info banner.
```json
{"type":"FAILED_DELIVERY_SHEET","failEvent":"","reasons":"customer_closed^Customer Tutup^Lokasi tutup / tidak ada orang~access_denied^Akses Ditolak^Tidak diizinkan masuk lokasi~customer_refused^Customer Tolak^Customer menolak menerima~capacity_full^Kapasitas Penuh^Customer tidak punya tempat","notePosition":9,"text":"Lapor Delivery Gagal◆Pilih Alasan◆Catatan Tambahan◆Detail tambahan untuk admin...◆Setelah submit, admin akan dapat signal untuk reschedule atau create task lanjutan.◆Batal◆Lapor Gagal"}
```
text 7 seg (spec §5). **DEFERRED:** `failEvent` = kosong. Pas schema-delta → isi: `updateEventRow` task `tst◼failed` + fail-reason field (`{failCode}`) + note `◁9▷` (+ opsional `addToEvent` delivery_event). NO movement.

---

## TX-DELTA (2026-06-19) — transaksi jual/beli/tukar

Grounded mockup `src/component/Driverruntimefull2.jsx`: `ItemExecutionRow` (444-583), `SubmitConfirmSheet` (1383-1465). Tiap item di `it[]` sekarang punya `tx` (deliver/sale/purchase/refill). Detail schema: `docs/driver-runtime-transaction-delta.md`.

### `ITEM_EXECUTION_LIST` — render per `tx`

Renderer baca `txField` (`tx`) tiap item lalu pilih cabang. `tx` kosong = `deliver` (default; doc lama gak rusak).

| `tx` | render | qty | stepper? | chip |
|---|---|---|---|---|
| **deliver** | existing (drop + pickup stepper) | `pd`/`pp` → `ad`/`ap` | YA (editable) | Returnable/Consumable |
| **sale** "Jual" | kartu read-only teal, `→ Jual ke customer · Kepemilikan pindah · tanpa pickup` | `ps` | TIDAK | "Jual" + kondisi (`cdo`: Penuh/Kosong) |
| **purchase** "Beli" | read-only teal, `← Beli dari customer · Kepemilikan ke operator · naik ke kendaraan` | `pb` | TIDAK | "Beli" + kondisi (`cdi`) |
| **refill** "Tukar" | read-only emerald, `⇄ Tukar galon customer · Kosong masuk · isi keluar · galon milik customer` | `pr` | TIDAK | "Refill" + air (`wt`: RO/Isi Ulang) |

- **sale/purchase/refill = read-only** (ditetapkan Admin, driver tinggal eksekusi). Aktual otomatis = plan saat submit (`as=ps`, `ab=pb`, `ar=pr`). Tidak ada stepper, tidak ada pickup.
- **`wt`** sebaiknya **denorm ke `it[]`** biar renderer baca langsung (pola `in`); SSOT tetap `item`.

Config +field:
```json
{"type":"ITEM_EXECUTION_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","itemsField":"it","labelField":"in","planDropField":"pd","planPickupField":"pp","txField":"tx","saleField":"ps","buyField":"pb","refillField":"pr","condOutField":"cdo","condInField":"cdi","waterField":"wt","text":"…(11 seg lama)…◆Jual◆Jual ke customer◆Kepemilikan pindah · tanpa pickup◆Beli◆Beli dari customer◆Kepemilikan ke operator · naik ke kendaraan◆Refill◆Tukar galon customer◆Kosong masuk · isi keluar · galon milik customer◆Kosong◆Penuh◆RO◆Isi Ulang"}
```
+13 seg tx (seg 12-24): Jual◆saleLine◆saleDesc◆Beli◆buyLine◆buyDesc◆Refill◆refillLine◆refillDesc◆Kosong◆Penuh◆RO◆Isi Ulang.

### `SUBMIT_CONFIRM_SHEET` — recap per tx

Baris recap per item ikut `tx`:
- sale: `→ {ps} jual · tanpa pickup` (no baris drop/pickup) + chip "Jual".
- purchase: `← {pb} beli · masuk kendaraan` + chip "Beli".
- refill: `⇄ {pr} tukar · kosong in / isi out` + chip "Refill".
- deliver: baris drop/pickup aktual-vs-plan (existing).

Total: jual/beli/tukar **dihitung terpisah** dari Total Drop/Pickup. Tambah seg ringkasan (mis. "Total Jual / Beli / Tukar") kalau perlu.

### Write saat CF landing (per item, by `tx`)
| tx | movement |
|---|---|
| deliver | `DROP` (qt=`ad`) + `PICKUP` (qt=`ap`) |
| sale | `SALE` (`fl`=mobil, `tl`=null, qt=`as`) |
| purchase | `PURCHASE` (`fl`=client, `tl`=mobil, qt=`ab`) |
| refill | `REFILL` (qt=`ar`, `cd` diabaikan; CF full−/empty+) |

Semua masih **deferred** (nunggu CF + movement, sama kaya deliver). Renderer + chip = build sekarang; write nyusul.

---

## OPEN (sebelum P11 fully functional)
1. **CF + movement** — submit success (confirmEvent) commit DROP/PICKUP → CF derive `it[].ad/ap` + `asset_cache`. Spec CF `driver-runtime-movement-cf-handoff.md` (chat terpisah).
2. **fail-reason field** — task SSOT belum punya. Tambah `fr` (atau coll `delivery_event`) sebelum wire `failEvent`.
3. **active-task token** — gimana P11 tau stop mana (dev inject `{activeTaskVid}` saat tap stop di P10, mirip scanner nulis `driver.session`). Konfirmasi mekanisme.
4. **item write binding** — per-item actual ke movement (bukan langsung `it[].ad/ap` — itu CF-derived).
5. **header task-context** — kalau butuh customer/alamat/stop-number di header P11 (mockup ada), `custodyStepHeader` reuse gak nampung → header data-bound baru.

Source mockup: `src/component/Driverruntimefull.jsx` 753 / 874 / 1192 / 1469 / 191. Parent: `driver-runtime-widgets-MASTER-handoff.md`.
