# Dev Spec — driverHome State Machine (P4 / P4b)

**Status:** DRAFT (2026-06-15). Table & field key dari dictionary (`workforce`, `vehicle_check`, `asset_cache`, `task`). Token `{driverVid}`/`{vehicleId}`/`{today}` = di-inject dari sesi login, mekanisme final = LIKELY-TO-CHANGE.

## Inti: 1 page, 2 tampilan

**P4 = 1 page (`driverHome`).** GAK ada page "P4b" terpisah — itu cuma **state lain** dari page yang sama.

- **locked** = custody belum dikonfirmasi → card kuning "Perlu Aksi", rute dikunci
- **confirmed** = custody beres → card hijau, "Isi Kendaraan" muncul, rute kebuka + progress bar, return aktif

## Cara tau state-nya (SUPER SIMPEL)

Gate card jalanin 1 `search` ke `vehicle_check`:

```
table:  vehicle_check
search: cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}
```

> **KETEMU doc → confirmed (buka semua). GAK ketemu → locked (kunci semua). Titik.**

Gak ada `pendingValue`/`mismatchValue`/`stateMap` — dibuang, bikin bingung. Cuma **ada/gak ada doc**.

**Cara widget lain ikut nge-gate:** masing-masing bawa `gateTable` + `gateSearch` sendiri (isinya search yang sama — `vehicle_check` opening). Aturan: **`gateSearch` KETEMU → tampil/unlock. KOSONG → kunci/hidden.** Pakai field key beneran (`cty`/`vv`/`cdt`), BUKAN token sihir `{gateStatus}`. (Renderer boleh cache search identik biar gak query 3×.)

> Bedain 2 search di 1 widget:
> - `search` = **data apa yang ditampilin** (cth inventory: `asset_cache`)
> - `gateSearch` = **boleh tampil/nggak** (custody confirmed di `vehicle_check`)

`search` DSL: `◼` = field = value, `⭘` = AND, kiri = key Firebase, value bisa token `(…)`. Lihat [[feedback_search_dsl]].

## Visual — widget mana = box mana

**locked:**
```
(BS) Budi Santoso          [Keluar]   ← ROUTE_PROGRESS_HEADER (identityOnly)
     B1234XY · kendaraan ditugaskan
SEBELUM BERANGKAT                     ← TXT
╔════════════════════════════════╗
║● PERLU AKSI                    ║    ← PRECONDITION_GATE_CARD (kuning)
║ Konfirmasi Penerimaan Muatan   ║      search GAK ketemu → locked
║ Tabung Gas 13 · Galon Air 8    ║      item list ← task it[]
║ [ Konfirmasi Penerimaan → ]    ║
╚════════════════════════════════╝
╔════════════════════════════════╗
║🔒 Rute Hari Ini · 4 tujuan     ║    ← DRIVER_STOP_CARD (LOCKED, preview)
║ 1 Mandiri Tower  2 Honda …     ║      gate=pending → kunci
╚════════════════════════════════╝
   INVENTORY_BUCKET_CARD + NAV_ACTION_CARD = HIDDEN
```

**confirmed:**
```
(BS) Budi Santoso          [Keluar]   ← ROUTE_PROGRESS_HEADER
HARI INI                              ← TXT
╔════════════════════════════════╗
║✓ Muatan dikonfirmasi           ║    ← PRECONDITION_GATE_CARD (hijau)
║ 13 tabung · 8 galon · aktual   ║      search KETEMU → confirmed
╚════════════════════════════════╝
╔════════════════════════════════╗
║📦 Isi Kendaraan Sekarang       ║    ← INVENTORY_BUCKET_CARD ← asset_cache
║ Tabung 9 isi·0 kosong          ║      (muncul setelah confirmed)
║ Galon  6 isi·0 kosong          ║
╚════════════════════════════════╝
╔════════════════════════════════╗
║🚚 Rute Hari Ini          50%   ║    ← DRIVER_STOP_CARD ← task
║ ▓▓▓▓░░ 2 dari 4 stop           ║      (kebuka + progress + badge)
║ ✓ Mandiri Tower    [SELESAI]   ║
║ 2 Honda Bintaro    [LANJUT]    ║
║ [ Buka Tasklist → ]            ║
╚════════════════════════════════╝
[ Return Kendaraan → ]                ← NAV_ACTION_CARD ← task (aktif klo semua kelar)
```

## Table beneran per widget

> Nilai `table` ditulis ringkas di sini (cth `task`); LIVE = **`{tableVID}//{coll}`** (`84214220504259//task`) → resolve `MobileTable/{db}/tables/{tableVID}/{coll}`.

| widget | box UI | `table` | `search` | field kunci |
|---|---|---|---|---|
| `ROUTE_PROGRESS_HEADER` | header identitas | `workforce` | `VID◼{driverVid}` | `n` nama (nameField); plat dari `stock_location.ln` (vehicleSearch `lv◼{vehicleId}`) |
| `TXT` | label "SEBELUM BERANGKAT"/"HARI INI" | — | — (statis/token) | — |
| `PRECONDITION_GATE_CARD` | card konfirmasi (kuning↔hijau) | `vehicle_check` | `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` | ketemu=confirmed; item list ← `task` `it[]` (`in`,`pd`) |
| `INVENTORY_BUCKET_CARD` | "Isi Kendaraan Sekarang" | `asset_cache` | `lv◼{vehicleId}` | `ii`, `cd`(value=`full`/`empty`; display isi/kosong), `qt` |
| `DRIVER_STOP_CARD` | "Rute Hari Ini" + stop + progress | `task` | `vv◼{vehicleId}⭘tdt◼{today}` | `kl` lokasi, `tst` state, `it[]`; progress = Σ `tst` |
| `NAV_ACTION_CARD` | "Return Kendaraan" | `task` | `vv◼{vehicleId}⭘tdt◼{today}` | aktif klo semua `tst`=closed |

## Widget muncul kapan

| widget | locked | confirmed |
|---|---|---|
| `ROUTE_PROGRESS_HEADER` | ✅ | ✅ |
| `TXT` | ✅ "SEBELUM BERANGKAT" | ✅ "HARI INI" |
| `PRECONDITION_GATE_CARD` | ✅ kuning (blok) | ✅ hijau "dikonfirmasi" |
| `INVENTORY_BUCKET_CARD` | ❌ hidden | ✅ |
| `DRIVER_STOP_CARD` | ✅ 🔒 locked (preview) | ✅ kebuka + progress |
| `NAV_ACTION_CARD` | ❌ hidden | ✅ (klo semua stop kelar) |

## Token sesi

| token | isi | dari |
|---|---|---|
| `{driverVid}` | vid driver yg scan | sesi login (scanner P2) |
| `{vehicleId}` | id mobil (`VEH-B1234XY`) | sesi / penugasan |
| `{today}` | tanggal hari ini `YYYY-MM-DD` | device |

## Catatan renderer

1. Gate card: jalanin `search` di `vehicle_check`. Doc ADA → confirmed. KOSONG → locked. (existence check via `gateSearch`; gak ada token `{gateStatus}`.)
2. Tiap widget downstream punya `gateTable`+`gateSearch` (kondisi custody confirmed). Ketemu doc → tampil/unlock. Kosong → kunci — **hidden** (inventory, return) atau **preview locked** (stop card).
3. Item list gate card ← `task` (`itemsTable:task`, `itemsField:it`, label `in`, qty `pd`). `in` udah denorm di `it[]` (gak perlu join).
4. `INVENTORY_BUCKET_CARD` baca `asset_cache` (saldo real-time robot). `cd:full`→"isi", `cd:empty`→"kosong".
5. `DRIVER_STOP_CARD` baca `task` (1 doc = 1 stop). Progress = jumlah `tst` selesai / total.

## Open / LIKELY-TO-CHANGE

- Sumber "load plan" (Tabung 13/Galon 8 di locked) sementara = agregat `task` `it[].pd`. Kalau gudang bikin manifest sendiri (`vehicle_check.ie`@opening) → ganti `itemsTable`.
- Mismatch (selisih custody, flow P8) BELUM masuk P4 — sengaja, biar simpel 2-state dulu. Kalau perlu badge selisih di card hijau → tambah field baca `vehicle_check.rs` nanti.
- Token inject `(…)` mekanisme final nunggu sesi/schema.
