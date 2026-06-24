# Reject Task Sheet — Dev Spec

**Buat:** Flutter dev. Layar/sheet driver buat **menolak (reject) task** yang tidak searah rute, **sebelum Konfirmasi Penerimaan** (opening-only). Task dikembalikan ke Admin buat di-assign ke mobil lain. Route `vertikaTeknoLokaciptaRejectTask`.

Grounded mockup: `src/component/Driverruntimefull2.jsx` — `RejectTaskSheet` (3863), `handleRejectTask` (3939). Schema: `docs/driver-runtime-field-dictionary.md` + `docs/driver-runtime-transaction-delta.md`.

**Status:** DRAFT, belum final (nunggu review tech lead, bareng tx-delta).

---

## 1. Konteks & alur

- Masuk dari **P4 DriverHome (locked)** → `DRIVER_STOP_CARD variant:"preview"`, tombol **"Tolak"** per stop (lihat `driver-stop-card-dev-spec.md` §15). Tap Tolak → route ke sini, bawa token **`{rejectTaskVid}`** (= `tnm` task yang ditolak).
- Cuma muncul saat **custody belum confirmed** (rute masih 🔒). Setelah berangkat tidak bisa.
- Submit → task `tst=load_rejected`, balik ke DriverHome.

**Doktrin (penting):**
- **`vv` (mobil) TIDAK dikosongkan.** Admin perlu tahu driver/mobil terakhir buat audit + re-assign. (Revisi 2026-06-19: dulu sempat `vv→null`, diganti.)
- **Barang tetap di gudang**, tidak naik ke kendaraan → stok gudang tidak berubah, **tidak ada movement**.
- **Re-assign = domain Admin app** (di luar driver): Admin ganti `vv` + set `tst→assigned`. Driver penolak tetap kerekam di evidence.

---

## 2. Layout (mockup `RejectTaskSheet` 3863-3914)

Bottom sheet (atau page) di atas backdrop gelap:
1. **Header** — judul "Tolak Task — Tidak Searah" + subtitle `{customer} · Stop {n}` (dari task `{rejectTaskVid}`).
2. **Notice (amber)** — "Task ini dikembalikan ke Admin buat di-assign ke mobil lain. Barang tetap di gudang, nggak naik ke kendaraan lo. Cuma bisa sebelum berangkat."
3. **Alasan (wajib)** — textarea, min 10 karakter. Helper: "✓ alasan cukup" / "min 10 karakter · {n}/10".
4. **Aksi** — "Batal" (tutup) + "Kembalikan ke Admin" (disabled sampai alasan ≥10).

---

## 3. Komposisi widget (REUSE dulu, minim renderer baru)

| # | widget | peran | catatan |
|---|---|---|---|
| 1 | `WORKSPACE_HEADER` (reuse) | header customer + stop | search `tnm◼{rejectTaskVid}` (sama mekanik P11, beda token) |
| 2 | `NOTICE_BAR` variant `warn` | box peringatan amber | literal text |
| 3 | `TXF` (reuse) | input alasan | `position` N, `line:3`, `border:true` |
| 4 | `RBT` savesend (`sendButtonGpsWithEvent`) | submit | `updateEventRow` + `addToEvent` + gate min10 + chain dialog |

> Header pakai `WORKSPACE_HEADER` karena dia udah baca `task` by `tnm` → `titleField:kn`, `addressField:al`. Cukup ganti `search` ke `{rejectTaskVid}`. Tidak butuh type baru.

---

## 4. Submit DSL (RBT savesend)

Posisi form: alasan = `◁5▷` (TXF `position:5`). GPS opsional `gpsPosition:2`.

**updateEventRow** (flip status, vv TIDAK disentuh):
```
84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{rejectTaskVid}⭘tst◼load_rejected
```

**addToEvent** (alasan + siapa nolak → evidence):
```
84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{rejectTaskVid}⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶
```

**Gate:** `gateNotePosition:5`, `minNoteLength:10` (tombol mati sampai alasan ≥10 char).
**Route:** `vertikaTeknoLokaciptaDriverHome` + chain `DO_DIALOG` ("Dikembalikan ke Admin · ga searah" → Ok → DriverHome).

RBT (literal, contoh):
```json
{"type":"RBT","alignment":"spaceevenly","children":[{"text":"Kembalikan ke Admin","action":"savesend","route":"vertikaTeknoLokaciptaDriverHome","delay":3,"gpsPosition":2,"flag":"task-load-rejected","gateNotePosition":5,"minNoteLength":10,"updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{rejectTaskVid}⭘tst◼load_rejected","addToEvent":"84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{rejectTaskVid}⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","chain":{"type":"DO_DIALOG","title":"Tolak Task","children":[{"type":"TXT","data":"Dikembalikan ke Admin · ga searah"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaDriverHome"}]}]}}]}
```

---

## 5. op1Screen page (`vertikaTeknoLokaciptaRejectTask`)

Children (urut):
| # | widget | isi |
|---|---|---|
| 1 | `WORKSPACE_HEADER` | search `tnm◼{rejectTaskVid}`, backRoute DriverHome, text "Tolak Task◆Tidak Searah" |
| 2 | `NOTICE_BAR` warn | box amber (§2.2) |
| 3 | `TXF` position 5 | alasan, line 3, border, hint "Kenapa nggak searah? mis. arah berlawanan, kejauhan…" |
| 4 | `RBT` savesend | submit DSL §4 |

Pakai literal D-cell (gak butuh drag Widget col), sama pola page driver lain.

---

## 6. Token & field
- `{rejectTaskVid}` — task `tnm` yang ditolak (injected dari tombol Tolak P4). Token runtime baru.
- `{driverVid}` / `{driverName}` — aktor (driver penolak).
- Tulis: `task.tst=load_rejected` (updateEventRow) · `evidence` baru (addToEvent). **`vv` tidak ditulis.**

---

## 7. Open / flag dev
1. **Manifest custody exclude `tst=load_rejected`** — P5/P6 (TASK_MANIFEST_LIST, CUSTODY_COUNT_LIST) jangan ikut hitung task yang ditolak (biar ie-vs-ip gak mismatch palsu). Cross-ref custody specs.
2. **Sheet vs page** — mockup = bottom sheet. Di proxy bisa page penuh (route) atau dialog. Default spec ini = page route `vertikaTeknoLokaciptaRejectTask`. Kalau dev mau sheet overlay, sesuaikan.
3. **`savesend` baca `updateEventRow`** — dikonfirmasi user ADA di `sendButtonGpsWithEvent`. Verify saat build.
4. **Re-assign** = Admin app (ganti `vv` + `tst→assigned`). Bukan scope driver.

---

## 8. Checklist
- [ ] page `vertikaTeknoLokaciptaRejectTask` @op1Screen (4 children literal)
- [ ] WORKSPACE_HEADER search `tnm◼{rejectTaskVid}` resolve customer+stop
- [ ] TXF position 5 + gate min 10
- [ ] RBT updateEventRow `tst=load_rejected` (vv utuh) + addToEvent evidence
- [ ] chain dialog → DriverHome
- [ ] tombol Tolak di DRIVER_STOP_CARD pass `{rejectTaskVid}` (lihat stop-card §15)
- [ ] manifest P5/P6 exclude load_rejected
