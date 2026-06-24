# Failed Delivery Sheet — Dev Spec (v2.0)

**Buat:** Flutter dev. Layar/page driver buat **melaporkan delivery gagal** di sebuah stop saat eksekusi rute (di dalam P11 DeliveryWorkspace). Stop ditandai gagal, dikembalikan ke Admin buat reschedule. Route `vertikaTeknoLokaciptaFailedDelivery`.

**Supersedes v1.0** (lihat §15). v1.0 mendesain 1 widget dedicated `FAILED_DELIVERY_SHEET` @ Widget row 203 — tapi row 203 keburu dipakai `driverStopCard`, widget itu **tidak pernah dibuild**. v2.0 ganti ke **page komposisi widget reuse** (mirror RejectTask), zero widget baru.

Grounded mockup: `src/component/Driverruntimefull2.jsx` — `FailedDeliverySheet` (1679), tombol pemicu "Tidak bisa dieksekusi · Lapor sebagai gagal" (1265), `handleFailedSubmit` (1075), state map `failed` → "Gagal" (192). Mengikuti pola `driver-reject-task-sheet-dev-spec.md`.

**Status:** DRAFT, belum final.

---

## 1. Konteks & alur

- Masuk dari **P11 DeliveryWorkspace** → tombol **"Tidak bisa dieksekusi · Lapor sebagai gagal"** (mockup 1265). Tap → route ke sini, bawa token **`{failedTaskVid}`** (= `tnm` task stop yang gagal).
- Terjadi **saat eksekusi** (rute sudah jalan), beda dari RejectTask yang opening-only. Stop ini tidak bisa di-drop (customer tutup / tolak / dst).
- Submit → task `tst=failed`, balik ke TaskFeed/DriverHome.

**Doktrin:**
- **Barang tidak jadi turun** → tetap di kendaraan (dibawa balik / nunggu reschedule). **Tidak ada movement** (delivery tidak terjadi).
- **`vv` (mobil) tidak dikosongkan** (audit + re-assign Admin), sama doktrin reject.
- **Reschedule = domain Admin app** (di luar driver). Driver pelapor + alasan kerekam di evidence.

---

## 2. Layout (mockup `FailedDeliverySheet` 1679-1790)

Bottom sheet (di proxy = page route):
1. **Header** — "Lapor Delivery Gagal" + subtitle `{customer} · Stop {n}` (dari task `{failedTaskVid}`).
2. **Pilih Alasan (wajib)** — 4 pilihan, single-select grid:
   - Customer Tutup
   - Akses Ditolak
   - Customer Tolak
   - Kapasitas Penuh
   (mockup punya desc per item — di widget grid `text` tidak ada slot desc, jadi **label saja**; desc bisa dipindah ke hint catatan kalau perlu. Lihat §7.3.)
3. **Catatan Tambahan (opsional)** — textarea, muncul setelah alasan dipilih.
4. **Aksi** — "Batal" (tutup) + "Lapor Gagal" (disabled sampai alasan dipilih).

---

## 3. Komposisi widget (REUSE, zero renderer baru)

| # | widget | peran | catatan |
|---|---|---|---|
| 1 | `WORKSPACE_HEADER` (reuse) | header customer + stop | search `tnm◼{failedTaskVid}`, `titleField:kn`, `addressField:al` (mekanik sama reject/P11) |
| 2 | `NOTICE_BAR` variant `warn` | box peringatan | literal text |
| 3 | `SELECTABLE_BTN` variant `grid` (reuse) | pilih alasan | opsi dari `text` (`◆`-sep), `maxGrid:2`, single-select, `position` N |
| 4 | `3LineBorderForm` / `TXF` (reuse) | catatan opsional | `position` M, `line:3`, `border:true` |
| 5 | `RBT` savesend | submit | `updateEventRow` + `addToEvent` + gate alasan + chain dialog |

> Reason picker pakai `SELECTABLE_BTN variant:"grid"` (contoh kanonik dari user: `{"type":"SELECTABLE_BTN","variant":"grid","icon":"pin_drop","title":"JENIS KELUHAN","height":50,"maxGrid":2,"position":7,"bgSelected":"gray","text":"Kebersihan◆AC & pendingin◆Listrik & lampu◆Maintenance"}`). Tidak butuh widget baru. Trade-off vs v1.0: `text` cuma simpan label (bukan kode mesin `customer_closed` + desc). Lihat §7.3.

---

## 4. Submit DSL (RBT savesend)

Posisi form: alasan = `◁7▷` (SELECTABLE_BTN `position:7`), catatan = `◁5▷` (form `position:5`). GPS opsional `gpsPosition:2`.

**updateEventRow** (flip status, vv tidak disentuh):
```
84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{failedTaskVid}⭘tst◼failed
```

**addToEvent** (alasan + catatan + pelapor → evidence):
```
84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{failedTaskVid}⭘ec◼◁7▷⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶
```
`ec` = alasan (`◁7▷`, label terpilih dari SELECTABLE_BTN); `d` = catatan (`◁5▷`). Field terpisah → queryable per-alasan, gak perlu jejelin 2 token di 1 field.

**Gate:** alasan wajib dipilih sebelum tombol aktif (mockup: submit disabled sampai `reason` ada). Catatan opsional. Lihat §7.2 (mekanik gate untuk required-selection).

**Route:** balik `vertikaTeknoLokaciptaTaskFeed` (atau DriverHome) + chain `DO_DIALOG` ("Dilaporkan gagal · nunggu admin reschedule" → Ok).

RBT (literal, contoh — selaras reject):
```json
{"type":"RBT","alignment":"spaceevenly","children":[{"text":"Lapor Gagal","action":"savesend","route":"vertikaTeknoLokaciptaTaskFeed","delay":3,"gpsPosition":2,"flag":"task-failed","updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{failedTaskVid}⭘tst◼failed","addToEvent":"84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{failedTaskVid}⭘ec◼◁7▷⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","chain":{"type":"DO_DIALOG","title":"Delivery Gagal","children":[{"type":"TXT","data":"Dilaporkan gagal · nunggu admin reschedule"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaTaskFeed"}]}]}}]}
```

---

## 5. op1Screen page (`vertikaTeknoLokaciptaFailedDelivery`)

Children (urut):
| # | widget | isi |
|---|---|---|
| 1 | `WORKSPACE_HEADER` | search `tnm◼{failedTaskVid}`, backRoute (P11/TaskFeed), text "Lapor Delivery Gagal◆{customer}" |
| 2 | `NOTICE_BAR` warn | "Stop ini dilaporkan gagal → dikembalikan ke Admin buat reschedule. Barang tetap di kendaraan." |
| 3 | `SELECTABLE_BTN` grid position 7 | title "PILIH ALASAN", `maxGrid:2`, text `Customer Tutup◆Akses Ditolak◆Customer Tolak◆Kapasitas Penuh` |
| 4 | `3LineBorderForm` position 5 | catatan opsional, hint "Detail tambahan (opsional)…" |
| 5 | `RBT` savesend | submit DSL §4 |

Pakai literal D-cell, sama pola page driver lain.

---

## 6. Token & field
- `{failedTaskVid}` — task `tnm` yang gagal (injected dari tombol "Lapor gagal" P11). Token runtime baru.
- `{driverVid}` / `{driverName}` — pelapor.
- Tulis: `task.tst=failed` (updateEventRow) · `evidence` baru (addToEvent, alasan+catatan). **`vv` tidak ditulis. Tidak ada movement.**
- Alasan disimpan di field evidence baru **`ec`** (Evidence Category) = **label** dari `SELECTABLE_BTN` (mis. "Customer Tutup"). Catatan di `d`. `ec` queryable buat filter per-alasan. Label, bukan kode `customer_closed` (§7.3).

---

## 7. Open / flag dev
1. **RESOLVED (opsi B)** — alasan → field evidence baru **`ec`** (Evidence Category), catatan → `d`. Field sendiri-sendiri, gak perlu 2 token di 1 field. `ec` udah ditambah ke dict `evidence` row 11 (2026-06-23).
2. **Gate required-selection** — reject pakai `gateNotePosition`+`minNoteLength` (gate teks). Di sini yang wajib = **alasan dipilih** (bukan panjang teks). Perlu konfirmasi mekanik RBT buat gate "SELECTABLE_BTN harus terpilih" (mungkin widget sudah handle sendiri, atau butuh prop gate baru).
3. **`ec` simpan label, bukan kode** — `ec` = label dari `SELECTABLE_BTN` (mis. "Customer Tutup"), bukan kode mesin `customer_closed` (v1.0 punya kode). Buat filter Admin per-label cukup. Kalau perlu kode stabil: `SELECTABLE_BTN` value≠label (kalau didukung) atau mapping label→kode. Default = label.
4. **Tombol pemicu P11** — `DeliveryWorkspace` (P11) harus punya tombol "Lapor sebagai gagal" yang route ke `vertikaTeknoLokaciptaFailedDelivery` + pass `{failedTaskVid}`. Pass-nya pakai **`routeParams:"failedTaskVid◼{tnm}"`** (deklaratif, lihat `docs/rbt-route-params-dev-spec.md`) — begitu dev nambah `routeParams` ke RBT. Interim bisa bespoke (`failedRoute`+`taskIdField`) kayak reject kalau mau test sebelum dev.
5. **Sheet vs page** — mockup = bottom sheet; default spec = page route. Kalau dev mau sheet overlay, sesuaikan.
6. **failed vs load_rejected** — `failed` = gagal saat eksekusi (sudah berangkat, barang di kendaraan); `load_rejected` = tolak opening (barang di gudang). Dua status beda, jangan dicampur.

---

## 8. Checklist
- [ ] page `vertikaTeknoLokaciptaFailedDelivery` @op1Screen (5 children literal)
- [ ] WORKSPACE_HEADER search `tnm◼{failedTaskVid}` resolve customer+stop
- [ ] SELECTABLE_BTN grid position 7 (4 alasan, maxGrid 2) + gate wajib pilih
- [ ] 3LineBorderForm position 5 (catatan opsional)
- [ ] RBT updateEventRow `tst=failed` (vv utuh) + addToEvent evidence (alasan+catatan)
- [ ] chain dialog → TaskFeed/DriverHome
- [ ] tombol "Lapor gagal" di P11 pass `{failedTaskVid}`
- [ ] verifikasi packing evidence `d` (§7.1) + gate selection (§7.2) saat build

---

## 15. Versi & history
- **v2.0 (2026-06-23)** — Redesign: popup → **page** `vertikaTeknoLokaciptaFailedDelivery` (mirror RejectTask), komposisi widget **reuse** (WORKSPACE_HEADER + NOTICE_BAR + SELECTABLE_BTN grid + 3LineBorderForm + RBT savesend). Write `tst=failed` + evidence (`ec`=alasan + `d`=catatan). Field evidence baru **`ec`** (Evidence Category) ditambah ke dict. Zero widget baru. Supersedes v1.0.
- v1.0 (2026-06-10) — Widget dedicated `FAILED_DELIVERY_SHEET` @ row 203 (reason `^`/`~` encoded code+label+desc, single failed event). **Tidak pernah dibuild** (row 203 dipakai driverStopCard). Diarsipkan oleh v2.0.
