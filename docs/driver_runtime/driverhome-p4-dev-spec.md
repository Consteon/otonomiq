# Dev Spec — DriverHome (P4)

**Status:** LIVE (op1Screen 2026-06-15). Page `vertikaTeknoLokaciptaDriverHome` @ op1Screen rows 1008-1016. Widget templates: `routeProgressHeader@200`, `preconditionGateCard@201`, `inventoryBucketCard@202`, `driverStopCard@203`, `navActionCard@204`. Source design: `json/driver-runtime/p4-driver-home.json`. Behavior detail: `docs/driver-home-state-machine-dev-spec.md`.

Spec ini = **kontrak field per-widget** buat Flutter dev. Untuk logika state lengkap (visual locked/confirmed, search), baca juga state-machine spec.

---

## 1. Inti

**DriverHome = 1 page, 6 widget, tampilan beda by STATE.** Driver masuk sini abis scan kartu (`DriverScanLogin` → route `vertikaTeknoLokaciptaDriverHome`).

State ditentuin 1 hal: **ada gak doc custody opening hari ini?**
- **belum konfirmasi** (gak ada doc) → gate card kuning "Perlu Aksi", rute dikunci, inventory+return SEMBUNYI
- **udah konfirmasi** (ada doc) → gate hijau, inventory muncul, rute kebuka + progress, return aktif

Mekanisme: `gateSearch` ke `vehicle_check`. **KETEMU → tampil/unlock. KOSONG → kunci/sembunyi.** (lihat [[feedback_search_dsl]] — `◼`=eq, `⭘`=AND).

---

## 2. Aturan umum semua widget

- **`table` + `search`** = data yang DITAMPILIN (cth inventory `asset_cache`). **Nilai `table`/`vehicleTable`/`itemsTable`/`gateTable` = `{tableVID}//{coll}`** (cth `84214220504259//asset_cache`) → resolve ke `MobileTable/{db}/tables/{tableVID}/{coll}`. Prefix WAJIB, kalau gak read kosong.
- **`gateTable` + `gateSearch`** = boleh tampil/nggak (custody confirmed di `vehicle_check`). KETEMU→tampil, KOSONG→sembunyi/locked.
- **`text`** = `◆`-delimited slots (label + state messages). Renderer parse per index.
- **Token runtime** `{driverVid}` (REAL dari scan P2 / driver.session) · `{vehicleId}` (mobil trip aktif — **derive** `stock_location[dv={driverVid}].lv` sekarang / **pick** driver nanti; BUKAN dari scan) · `{today}` (epoch-midnight). Semua widget P4 key ke `{vehicleId}` yg sama.
- **`[PLACEHOLDER]`** (kurung siku) = belum diisi (avatar/icon/route ke page lain).

---

## 3. Kontrak per-widget (urut render)

### 3.1 `routeProgressHeader` — type `ROUTE_PROGRESS_HEADER`
Header identitas (nama driver · plat mobil · tombol Keluar). **DATA-BOUND** (bukan hardcode), NO avatar. Detail penuh: `docs/driver-route-progress-header-dev-spec.md` (v2).

| field | isi |
|---|---|
| `variant` | `"identityOnly"` (TANPA progress bar; progress di stop card) |
| `table` / `search` | `workforce` / `VID◼{driverVid}` — driver yg scan |
| `nameField` | `n` — nama driver |
| `vehicleTable` / `vehicleSearch` | `stock_location` / `lv◼{vehicleId}` — mobil trip aktif |
| `plateField` | `ln` — plat |
| `logoutRoute` | `[ROUTE:pauseConfirm]` |
| `text` (◆, 8 slot LABEL) | `Rute Hari Ini◆stop◆gagal◆Drop◆Pickup◆kendaraan ditugaskan◆Keluar◆Belum ditugaskan kendaraan` |

Render: nama (`workforce.n`) + plat (`stock_location.ln` via `vehicleSearch`). `vehicleSearch` KOSONG → fallback slot "Belum ditugaskan kendaraan". `[DRIVERNAME]`/`[PLATE]`/`[VEHICLEID]`/avatar DIBUANG → data-bound. Selalu tampil.

### 3.2 `text` (REUSE widget `text`) — type `TXT`
Label section. `{"type":"TXT","size":14,"data":"SEBELUM BERANGKAT"}`. **State-dependent:** locked=`SEBELUM BERANGKAT`, confirmed=`HARI INI`. Renderer switch by state (atau dev bake locked default). Reuse — bukan widget baru.

### 3.3 `preconditionGateCard` — type `PRECONDITION_GATE_CARD`
Card custody (kuning↔hijau). **INI sumber state page.**

| field | isi |
|---|---|
| `table` / `search` | `vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` — KETEMU=confirmed, KOSONG=pending |
| `itemsTable` | `task` — sumber daftar item rencana muat |
| `itemsField` / `labelField` / `qtyField` | `it` / `in` / `pd` — render baris item (nama item + qty planned_drop). `iv`/`pq` LAMA → sekarang `in`/`pd` (it[]=`{ii,in,cdo,cdi,pd,pp,ad,ap}`) |
| `route` | `[ROUTE:custodyConfirm]` — page hitung custody (P6) |
| `text` (◆, 9 slot) | `Perlu Aksi◆Konfirmasi Penerimaan Muatan◆Muat dari <2>. Cek & konfirmasi sebelum berangkat.◆Konfirmasi Penerimaan◆membuka layar...◆Muatan dikonfirmasi◆{confirmedSummary} · jumlah aktual◆! Ada selisih dari catatan gudang◆udah dilaporkan, Supervisor lagi review. Kerjaan tetap jalan.` |

Render: **pending** → kuning "Perlu Aksi" + daftar item + tombol → custodyConfirm. **confirmed** → hijau "Muatan dikonfirmasi". **mismatch** (opsional, `rs=discrepancy`) → + banner selisih. Selalu tampil (cuma ganti variant).

### 3.4 `inventoryBucketCard` — type `INVENTORY_BUCKET_CARD`
"Isi Kendaraan Sekarang" — saldo mobil real-time per kondisi.

| field | isi |
|---|---|
| `table` / `search` | `asset_cache` / `lv◼{vehicleId}` — saldo mobil (robot-computed) |
| `categoryField` | `cd` — pisah isi(full)/kosong(empty) |
| `buckets` | `full◼ok⭘empty◼warn` — **value◼status** (value = data `cd` = `full`/`empty`, BUKAN isi/kosong). Display "Isi"/"Kosong" = renderer map (`full`→Isi, `empty`→Kosong) |
| `gateTable` / `gateSearch` | `vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` — tampil HANYA kalau confirmed |
| `icon` | `[ICON]` |
| `text` (◆, 2 slot) | `Isi Kendaraan Sekarang◆Update otomatis tiap serah-terima (kirim isi, ambil kosong).` |

Render: per item → "N isi · M kosong" (`cd:full`→isi, `cd:empty`→kosong). **SEMBUNYI saat pending** (gateSearch kosong).

### 3.5 `driverStopCard` — type `DRIVER_STOP_CARD`
"Rute Hari Ini" — daftar stop + progress.

| field | isi |
|---|---|
| `variant` | `"preview"` |
| `table` / `search` | `task` / `vv◼{vehicleId}⭘tdt◼{today}` — semua stop hari ini |
| `navState` | `"assigned"` |
| `route` | `[ROUTE:taskFeed]` — page tasklist eksekusi |
| `gateTable` / `gateSearch` | `vehicle_check` / `cty◼opening⭘...` — kebuka kalau confirmed |
| `icon` / `iconLocked` | `[ICON]` / `[ICON_LOCKED]` |
| `text` (◆, 18 slot) | `Stop Berikutnya◆Dilaporkan Gagal◆Sudah Selesai◆Pilih sesuai kondisi lapangan◆Mulai Eksekusi◆Selesai◆Customer confirmed◆Dilaporkan gagal — menunggu admin reschedule◆kirim◆ambil◆Pickup Only◆Rute Hari Ini◆{closed} dari {total} stop◆lanjut:◆semua kelar◆{total} tujuan◆Konfirmasi muatan dulu buat mulai — ini tujuan lo hari ini:◆Buka Tasklist (eksekusi)` |

Render: **pending** → 🔒 preview list (judul + tujuan, gak bisa di-tap). **confirmed** → list aktif + **progress bar** (`{closed}/{total}`) + badge per stop (SELESAI/LANJUT/KIRIM/GAGAL) + tombol Buka Tasklist. Stop = doc `task`; status dari `tst`; progress = Σ `tst`.

### 3.6 `navActionCard` — type `NAV_ACTION_CARD`
"Return Kendaraan".

| field | isi |
|---|---|
| `route` | `[ROUTE:returnVehicle]` |
| `table` / `search` | `task` / `vv◼{vehicleId}⭘tdt◼{today}` |
| `ready` | `{allClosed}` — aktif kalau semua stop kelar |
| `gateTable` / `gateSearch` | `vehicle_check` / `cty◼opening⭘...` |
| `icon` / `iconReady` | `[ICON]` / `[ICON_READY]` |
| `text` (◆, 3 slot) | `Return Kendaraan◆Balik & serahkan kendaraan + sisa muatan ke gudang◆Semua kelar — balik & serahkan ke gudang` |

Render: **SEMBUNYI saat pending**. Confirmed → tampil; aktif penuh kalau `{allClosed}`.

---

## 4. Matrix tampil per state

| widget | pending (belum konfirmasi) | confirmed |
|---|---|---|
| `routeProgressHeader` | ✅ | ✅ |
| `text` (label) | ✅ "SEBELUM BERANGKAT" | ✅ "HARI INI" |
| `preconditionGateCard` | ✅ kuning (blok) | ✅ hijau |
| `inventoryBucketCard` | ❌ hidden | ✅ |
| `driverStopCard` | ✅ 🔒 preview locked | ✅ kebuka + progress |
| `navActionCard` | ❌ hidden | ✅ |

---

## 5. Catatan renderer

1. Register 5 type: `ROUTE_PROGRESS_HEADER`, `PRECONDITION_GATE_CARD`, `INVENTORY_BUCKET_CARD`, `DRIVER_STOP_CARD`, `NAV_ACTION_CARD`. `TXT` udah ada.
2. Tiap widget jalanin `search` (data) + `gateSearch` (visibility) sendiri. KETEMU→tampil, KOSONG→sembunyi/locked. Boleh cache `gateSearch` identik (semua sama: `vehicle_check` opening) biar gak query berkali-kali.
3. `gate` di P4 polaritas SERAGAM: "ketemu = confirmed = tampil/unlock". GAK butuh gateMode/polarity (itu cuma kalau ada widget yg tampil-saat-kosong; di P4 gak ada).
4. Render `◆` slot per index; slot kosong = skip.
5. Token `(…)` di-resolve runtime dari sesi.

---

## 6. Placeholder buat diisi (forward ref / belum ada page/value)

| placeholder | widget | isi |
|---|---|---|
| ~~`[AVATAR]`/`[DRIVERNAME]`/`[VEHICLEID]`/`[PLATE]`~~ DIBUANG | header | sekarang data-bound: nama=`workforce.n`, plat=`stock_location.ln`; avatar dibuang |
| `[ICON]` `[ICON_LOCKED]` `[ICON_READY]` | inventory/stop/nav | icon ref |
| `[ROUTE:pauseConfirm]` | header | page pause/keluar |
| `[ROUTE:custodyConfirm]` | gate card | **P6 CustodyCount** (belum dibikin) |
| `[ROUTE:taskFeed]` | stop card | page tasklist eksekusi |
| `[ROUTE:returnVehicle]` | nav card | page return kendaraan |

---

## 7. Live op1Screen mapping

| op1Screen row | isi |
|---|---|
| 1007 | header `vertikaTeknoLokaciptaDriverHome` |
| 1008 | routeProgressHeader |
| 1009 | text (SEBELUM BERANGKAT) |
| 1010 | preconditionGateCard |
| 1011 | inventoryBucketCard |
| 1012 | driverStopCard |
| 1013 | navActionCard |
| 1014-1015 | buffer |

> Layout verified live 2026-06-17 (col A = widget index 1–6; routeProgressHeader@1008 D re-resolved data-bound). Templates `routeProgressHeader@200`…`navActionCard@204` (Widget tab).

Plug row 74. Widget templates rows 200-204. Masuk sini dari scanner `DriverScanLogin` (route → `vertikaTeknoLokaciptaDriverHome`).

## 8. Open

- Label section state-switch (SEBELUM BERANGKAT↔HARI INI) — renderer atau static? Confirm.
- `mismatch` state (selisih custody, `rs=discrepancy_detected`) belum dirender di P4 — sementara 2-state (pending/confirmed). Tambah badge selisih kalau perlu.
- Route target `custodyConfirm`/`taskFeed`/`returnVehicle`/`pauseConfirm` = page belum dibikin.
