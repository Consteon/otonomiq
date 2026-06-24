# P10 TaskFeed — Dedicated Widgets Dev Spec

**Buat:** Flutter dev. P10 = layar route harian (`vertikaTeknoLokaciptaTaskFeed`). User minta **persis** mockup → 2 widget BARU dedicated (reuse `ROUTE_PROGRESS_HEADER`/`DRIVER_STOP_CARD` "full" GAGAL mirip → diganti).

**Source mockup (SSOT layout):** `src/component/Driverruntimefull.jsx` — `TaskFeedScreen`(753), `RouteProgressHeader`(657), `TaskCard`(506).

2 widget:
| widget | type | Widget row | render |
|---|---|---|---|
| `routeFeedHeader` | `ROUTE_FEED_HEADER` | 223 | header sticky atas |
| `taskFeedList` | `TASK_FEED_LIST` | 224 | list grouped + allDone |

> **Status:** type BARU → butuh renderer baru di app build (uncommitted, dev-side), sama kaya custody types. Sheet published + P10 rewired; render nunggu build.

---

## 1. `ROUTE_FEED_HEADER` (mockup `RouteProgressHeader` 657)

Layout (3 baris, surface bg, border-bottom):

**Baris 1 — identitas:**
- back `←` (34×34, tap→`backRoute` = DriverHome, title "Kembali ke Home").
- kiri: judul **"Rute Hari Ini"** (14px bold) + baris kedua mono `{driverName} · {plate}` (11px, textMid).
  - driverName = `workforce.n` (search `VID◼{driverVid}`); plate = `stock_location.ln` (search `lv◼{vehicleId}`).

**Baris 2 — progress:**
- kiri label uppercase "Rute Hari Ini" (text seg 0); kanan mono `{completed} / {total} stop` + kalau `{failed}>0` → ` · {failed} gagal` (amber).
- progress bar (h6, slate100 track) width = `(completed+failed)/total*100`%, gradient driverAccent→driverAccentDark.
- completed/failed/total = count `task` (search `vv◼{vehicleId}⭘tdt◼{today}`) by `stateField` (`tst`): completed=`completed`, failed=`failed`, total=all.

**Baris 3 — 2 stat box (flex):**
- Drop (indigo/driverAccentBg): `↓ Drop` label + mono `{actualDrop} / {totalDrop}`.
- Pickup (violet50): `↑ Pickup` label + mono `{actualPickup} / {totalPickup}`.
- total = Σ semua task `it[]`: drop=Σ`pd`, actualDrop=Σ`ad`, pickup=Σ`pp`, actualPickup=Σ`ap`.

**text (5 seg):** `Rute Hari Ini◆stop◆gagal◆Drop◆Pickup`

**Config:**
```json
{"type":"ROUTE_FEED_HEADER","vidtable":"20342033315492","workforceTable":"84214220504259//workforce","workforceSearch":"VID◼{driverVid}","nameField":"n","vehicleTable":"84214220504259//stock_location","vehicleSearch":"lv◼{vehicleId}","plateField":"ln","taskTable":"84214220504259//task","taskSearch":"vv◼{vehicleId}⭘tdt◼{today}","stateField":"tst","itemsField":"it","dropField":"pd","pickupField":"pp","actualDropField":"ad","actualPickupField":"ap","backRoute":"vertikaTeknoLokaciptaDriverHome","text":"Rute Hari Ini◆stop◆gagal◆Drop◆Pickup"}
```

---

## 2. `TASK_FEED_LIST` (mockup `TaskFeedScreen` body + `TaskCard` 506)

Baca `task` (search `vv◼{vehicleId}⭘tdt◼{today}`), group by `groupField` (`tst`), render 3 section + allDone.

### 2.1 Section (urutan: assigned → failed → completed)
- **assigned** (`tst=assigned`): label uppercase **"Stop Berikutnya · {N}"** (textMid) + subtitle italic **"Pilih sesuai kondisi lapangan"** (textDim).
- **failed** (`tst=failed`): label **"Dilaporkan Gagal · {N}"** (amber700, marginTop).
- **completed** (`tst=completed`): label **"Sudah Selesai · {N}"** (textDim, marginTop).
- allDone = assigned count 0.

### 2.2 TaskCard (per task) — layout
Card (radius12, border, borderLeft 3px; assigned=surface opacity1, failed=amber50 opacity.75, completed=surface opacity.75):

**Header row:**
- avatar 32×32 radius8: assigned=`{stopNumber}` (slate100), completed=`✓` (emerald), failed=`!` (amber).
- tengah: baris mono `{id}` (=`tnm`) + chip **"Pickup Only"** (violet) kalau `typeField`(`tty`)==`pickup_return`. Bawahnya `{customer}` (=`kn`, 15px bold ellipsis).
- kanan: StateChip (state badge).

**Body (indent 42px):**
- `{address}` (=`al`, 12px ellipsis).
- `📍 {distance}` (11px textDim).
- badge row: `↓ {drop} drop` (indigo/driverAccentBg; completed=emerald + pakai actualDrop) kalau drop>0; `↑ {pickup} pickup` (violet; completed=actualPickup) kalau pickup>0. drop=Σ`pd`/`ad`, pickup=Σ`pp`/`ap`.

**Footer (per state, indent 42px):**
- assigned: banner driverAccent putih **"Mulai Eksekusi"** (uppercase) → tap card = `route` (DeliveryWorkspace).
- completed: `✓ Selesai {completedAt}` (emerald) + kalau customerConfirmed → ` · Customer confirmed`.
- failed: `! Dilaporkan gagal — menunggu admin reschedule` (amber).

### 2.3 allDone (assigned==0)
- banner emerald (di list, bawah): `🎉` / **"Semua Stop Selesai"** / "Lo bisa kembali ke gudang untuk closing check."
- footer sticky bawah: tombol driverAccent **"Kembali ke Gudang"** → `returnRoute`.

**text (15 seg):** `Stop Berikutnya◆Pilih sesuai kondisi lapangan◆Dilaporkan Gagal◆Sudah Selesai◆Pickup Only◆drop◆pickup◆Mulai Eksekusi◆✓ Selesai◆Customer confirmed◆! Dilaporkan gagal — menunggu admin reschedule◆🎉◆Semua Stop Selesai◆Lo bisa kembali ke gudang untuk closing check.◆Kembali ke Gudang`

**Config:**
```json
{"type":"TASK_FEED_LIST","vidtable":"20342033315492","table":"84214220504259//task","search":"vv◼{vehicleId}⭘tdt◼{today}","groupField":"tst","idField":"tnm","titleField":"kn","addressField":"al","typeField":"tty","itemsField":"it","dropField":"pd","pickupField":"pp","actualDropField":"ad","actualPickupField":"ap","route":"vertikaTeknoLokaciptaDeliveryWorkspace","returnRoute":"vertikaTeknoLokaciptaReturnVehicle","text":"Stop Berikutnya◆Pilih sesuai kondisi lapangan◆Dilaporkan Gagal◆Sudah Selesai◆Pickup Only◆drop◆pickup◆Mulai Eksekusi◆✓ Selesai◆Customer confirmed◆! Dilaporkan gagal — menunggu admin reschedule◆🎉◆Semua Stop Selesai◆Lo bisa kembali ke gudang untuk closing check.◆Kembali ke Gudang`}
```

---

## 3. OPEN — field belum di task SSOT (jangan invent; flag)
- **`distance`** — `📍 8.4 km` di mockup. BUKAN field task → renderer compute GPS (`al`/site la-lo vs current). User: distance computed.
- **`stopNumber`** — avatar number. BUKAN field → renderer assign by route order (index 1-based dari urutan task assigned).
- **`completedAt`** — `✓ Selesai HH:MM`. Field completion-time belum jelas (kandidat `tce`?). Konfirmasi.
- **`customerConfirmed`** — `· Customer confirmed`. = signature flag saat submit P11. Field belum ada (submit/movement deferred). 
- **grouping `on_delivery`** — task mid-eksekusi (`tst=on_delivery`) masuk section mana? Mockup cuma assigned/failed/completed. Asумsi on_delivery≈assigned (belum kelar). Konfirmasi.

`returnRoute` → `vertikaTeknoLokaciptaReturnVehicle` (P12, belum dibuat — forward ref).

---

## 4. Op1Screen
P10 `vertikaTeknoLokaciptaTaskFeed`@1066: row 1067 = `routeFeedHeader`, 1068 = `taskFeedList`. Ganti `routeProgressHeaderFull`/`driverStopCardFull` (216/217 → orphaned, P4 pakai base 200/203). Tap card assigned → DeliveryWorkspace (P11).
