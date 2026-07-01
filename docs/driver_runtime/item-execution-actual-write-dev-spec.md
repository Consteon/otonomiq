# ITEM_EXECUTION_LIST — Actual Write (Phase 2) Dev Spec

**Buat:** Flutter dev. **Status:** SPEC 2026-06-25. Config field UDAH ditambah live (Widget!J219 + auto-resolve op1Screen D1073). Renderer = **belum** (ini tugasnya).

---

## 1. Masalah (test live 2026-06-25)

Di DeliveryWorkspace, driver set stepper **drop 2 / pickup 2** (aktual, beda dari plan 3). Pas submit, movement keluar **qt=3** (plan), bukan 2. Penyebab:

- Submit RBT (`sendButtonGpsWithEvent`) cuma `updateEventRow`: **`tst◼completed⭘tce◼◀2▶`**. Gak nulis aktual.
- `ITEM_EXECUTION_LIST` capture angka stepper di **UI doang** — gak ke-persist ke `task.it[]`.
- CF `OnTaskCompleted` rumus `qt = actual ?? plan` → aktual (`ad`/`ap`) **absent** → fallback ke plan (`pd`/`pp`) → qt=3.

**Ini Phase 1.** CF bener; yang kurang = app belum nulis aktual. Lihat `driver-runtime-movement-emit-dev-spec.md` §0 + `driver-runtime-test-scenarios.md` §7.

## 2. Kenapa Flutter, BUKAN CF

Angka aktual cuma **driver** yang tau (input di lapangan). CF gak bisa nebak/invent. CF cuma BACA data yang udah ada + bikin movement. Yang MASUKIN data (input driver) = app. Jadi nulis aktual = **inherently app-side**. CF udah siap (`actual ?? plan`) — zero rework.

(Beda sama CF `OnCustodyConfirmed`: di situ data `ie`+`ip` UDAH ada di doc, CF tinggal banding. Di sini aktual belum ada di mana-mana → app harus nulis dulu.)

## 3. Config (LIVE — Widget!J219, auto-resolve D1073)

Field baru di `ITEM_EXECUTION_LIST` (renderer baca nama field dari config, JANGAN hardcode):
```json
"actualDropField":"ad","actualPickupField":"ap",
"actualSaleField":"as","actualBuyField":"ab","actualRefillField":"ar"
```
Pasangan plan-nya (udah ada): `planDropField:"pd"`, `planPickupField:"pp"`, `saleField:"ps"`, `buyField:"pb"`, `refillField:"pr"`.

## 4. Yang HARUS renderer kerjain

Pas submit ("Kirim"), `ITEM_EXECUTION_LIST` **tulis angka aktual yang dicapture ke `task.it[]`**:

1. Ambil array `it[]` yang udah ke-load (yang lagi ditampilin).
2. Per line, set field aktual = angka stepper, **by `tx`**:

| `tx` | field aktual yang ditulis | dari stepper |
|---|---|---|
| `deliver` | `ad` (=actualDropField), `ap` (=actualPickupField) | drop, pickup |
| `sale` | `as` (=actualSaleField) | jual |
| `purchase` | `ab` (=actualBuyField) | beli |
| `refill` | `ar` (=actualRefillField) | tukar |

3. **Tulis balik SELURUH `it[]` (native array write)** ke task doc: `doc.update({ it: <array baru> , ... })`. **BUKAN** `updateEventRow` (DSL cuma bisa field scalar, gak bisa nulis ke elemen array).

## 5. Default & nilai

- Stepper **default = plan** (UI udah gitu: "default = rencana, sesuaikan kalau beda").
- Tulis aktual = **angka stepper SELALU** (walau gak disentuh = sama dengan plan). Jadi `it[].ad` selalu keisi = angka yang driver konfirm. Eksplisit > implicit.
- (Alternatif: kalau stepper gak disentuh → biarin aktual `null` → CF fallback plan. Dua-duanya jalan karena CF `actual ?? plan`. Tapi nulis selalu lebih bersih buat audit "driver konfirm berapa".)

## 6. Atomicity / urutan (PENTING — hindari race sama CF)

CF `OnTaskCompleted` trigger pas `tst→completed`, langsung baca `it[]`. Jadi **aktual HARUS udah ke-tulis SEBELUM / BARENG** `tst=completed`. Kalau `tst` flip duluan terus `it[]` nyusul → CF udah jalan pake plan → telat.

**Cara paling aman = 1 native write atomik:**
```dart
doc.update({
  'it': updatedItArray,   // aktual ad/ap/as/ab/ar terisi
  'tst': 'completed',
  'tce': nowEpochMs,
});
```
Gabung `it[]` + `tst` + `tce` dalam SATU update. CF (trigger di `tst` flip) baca doc yang udah lengkap. Evidence (foto/note via addToEvent) + GPS + dialog navigasi tetep di pipeline RBT existing (collection beda, gak ganggu).

> Kalau gak bisa atomik (it[] write & tst flip kepisah): pastiin `it[]` write **selesai dulu**, baru `tst=completed`.

## 7. Verifikasi (abis build)

DeliveryWorkspace, set drop **2** / pickup **2**, submit:
- `task.it[]` line → `ad:2`, `ap:2` (ke-tulis). ✅
- CF emit movement `drop-{tnm}-{ii}` **qt=2**, `pickup-…` **qt=2**. ✅
- asset_cache mobil: full 3→**1**, empty 0→**2** (sisa 1 full + 2 empty di truk).

Phase 1 (sekarang, sebelum build): `ad`/`ap` null → qt=plan=3.

## 8. CF side = DONE

`OnTaskCompleted` (`cloud-function/task_complete_trigger.go`) `qtFor(m, actualKey, planKey)` = `actual ?? plan` (presence-based: aktual ada sebagai angka → pakai, walau 0). Begitu app nulis `ad`/`ap` → CF auto-pakai. **Nol perubahan CF.**
