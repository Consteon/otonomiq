# P7 / P8 / P9 — Custody Outcome Dev Spec

**Buat:** Flutter dev. Outcome custody abis `custodyReveal` branch. Grounded ke mockup `Driverruntimefull.jsx`: ConfirmationSuccessScreen(2779) / MismatchReportScreen(2915) / MismatchSubmittedScreen(3155).
**Flow:** custodyReveal → **match → P7** / **selisih → P8 → P9** → balik DriverHome (cst=custody_confirmed).

Route: P7 `vertikaTeknoLokaciptaCustodySuccess` · P8 `vertikaTeknoLokaciptaMismatchReport` · P9 `vertikaTeknoLokaciptaMismatchSubmitted`.

---

## ATURAN WRITE (penting)
- DSL update = **`updateEventRow`** (varian event, keyed), DSL append = **`addToEvent`**. **BUKAN** `updateTableRow`/`addToTable`.
- **Scalar / append → RBT + DSL.** Write yang scalar (`cst`, `d`) atau append (`evidence`) = bisa DSL → pakai **RBT** (action savesend/DSL), **bukan** widget custom.
- **Array → custom/native.** Write/baca array (`ip[]`, `dp[]`) = DSL gak support → widget **custom native** (Flutter).

| data | tipe | mekanisme |
|---|---|---|
| `cst`=`custody_confirmed` | scalar | **`updateEventRow`** (opening doc) via RBT |
| `d` = note selisih | scalar | **`updateEventRow`** (opening doc) via RBT |
| foto bukti | append | **`addToEvent` → `evidence`** (`ety:photo`,`ept:check`,`erf:cnm`,`i:path`) via RBT |
| `ip[]` / `dp[]` | array | NATIVE (udah ditulis @P6 / @reveal) — P7/P8 cuma BACA |

---

## P7 — CustodySuccess (match)
Mockup ConfirmationSuccessScreen(2779).
- **Display:** header "Custody Confirmed"+plat · banner ✓ "Konfirmasi Tercatat"+`cnm` · **list "Yang Dikonfirmasi"** (baca `ip[]`+join item) · hint "Selanjutnya: N task, stop 1".
- **Submit = RBT**: "Lapor Selesai · Kembali ke Home" → `updateEventRow` set **`cst=custody_confirmed`** (opening) → route `vertikaTeknoLokaciptaDriverHome`.
- Widget: `noticeBar`(ok) + **`CUSTODY_CONFIRMED_LIST`** (custom, baca `ip[]`) + `text` + **RBT**(DSL).

## P8 — MismatchReport (selisih)
Mockup MismatchReportScreen(2915).
- **Display:** warning · **dp list** (per item: nama · chip Kurang/Lebih · grid **Warehouse(`ie`) | Lo Hitung(`ip`) | Selisih(`dl`)**) · note **wajib min 10** · **foto WAJIB** · doctrine.
- **Submit = RBT** (aktif kalau note≥10 **&&** foto): `updateEventRow` set **`cst=custody_confirmed`** + **`d`=note** (opening) **+** `addToEvent` → **`evidence`** (foto) → route P9.
- Widget: `noticeBar`(warn) + **`CUSTODY_DISCREPANCY_LIST`** (custom, baca `dp[]`) + note-input + foto(`getImages`) + **RBT**(DSL ref input).

## P9 — MismatchSubmitted
Mockup MismatchSubmittedScreen(3155).
- **Display:** banner ✓ "Siap Berangkat — dengan Catatan Selisih" · "Apa yang terjadi" (3 step) · doctrine.
- **Button = RBT** → route `vertikaTeknoLokaciptaDriverHome`. (Gak nulis — cst udah @P8.)
- Widget: `noticeBar`(ok) + `text` + **RBT**.

---

## Widget — custom BARU vs reuse
| jenis | widget | baru? |
|---|---|---|
| P7 submit / P8 submit / P9 nav | **RBT** + DSL (`updateEventRow`/`addToEvent`) | reuse (RBT udah ada) |
| P7 list baca `ip[]` | `CUSTODY_CONFIRMED_LIST` | **BARU** (array read) — ATAU reuse `CUSTODY_REVEAL` read-only |
| P8 list baca `dp[]` | `CUSTODY_DISCREPANCY_LIST` | **BARU** (array read, grid ie/ip/dl) |
| note input | textarea/`txf` | reuse |
| foto | `getImages` | reuse |
| banner / text | `noticeBar` / `text` | reuse |

→ Custom BARU minimal: **2** (confirmed-list, discrepancy-list) — keduanya **array-read display**. Submit semua RBT+DSL.

## DSL FINAL (2026-06-18)
Prefix = `84214220504259//{coll}` (table-path, sama kaya driver widget) + `tablevid◼20342033315492`. Token runtime = `{}` (dev convert). `◁N▷` = form input posisi-N (= seq widget di page). `◀2▶` = stream epoch submit. `★`=key/val, `☆`=AND (search updateEventRow).

**P7 submit (match) — RBT, field `updateEventRow`:**
```
84214220504259//vehicle_check⭘tablevid◼20342033315492⭘search◼cty★opening☆vv★{vehicleId}☆cdt★{today}⭘cst◼custody_confirmed
```

**P8 submit (selisih) — RBT, field `updateEventRow` + `addToEvent`:**
```
updateEventRow: 84214220504259//vehicle_check⭘tablevid◼20342033315492⭘search◼cty★opening☆vv★{vehicleId}☆cdt★{today}⭘cst◼custody_confirmed⭘d◼◁5▷
addToEvent:     84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ty◼photo⭘ept◼check⭘erf◼{cnm}⭘i◼◁6▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶
```
*(posisi ◁5▷ note / ◁6▷ foto = sesuai seq final P8; fix pas wiring)*

**Form pattern (mirror `vertikaTeknoLokaciptaRequestLeave`):** input widget bawa `position:N` (N = seq-nya di page); submit RBT ref form via `◁N▷`. P8 form: `3LineBorderForm` (note, position=seq) + `getImages1` (foto, position=seq) + submit RBT.

## OPEN
1. **Submit = RBT field `updateEventRow`/`addToEvent`** (sibling event dari `updateTableRow`/`addToTable`). Template RBT existing pakai field table-variant; **butuh template submit BARU** dengan field `updateEventRow`+`addToEvent`, ATAU dev extend RBT renderer baca `component['updateEventRow']`/`['addToEvent']` (per `docs/2026-06-04-updateEventRow-design.md`). 1 RBT 2 aksi.
2. P7 list: `CUSTODY_CONFIRMED_LIST` baru, atau reuse `CUSTODY_REVEAL` read-only?
3. **Prereq build: col A** Widget tab harus keisi (drag) — sekarang base widget (3LineBorderForm/getImages1/submit) col A kosong → RequestLeave & semua VLOOKUP page `#N/A`.

Source mockup: `src/component/Driverruntimefull.jsx` 2779 / 2915 / 3155.
