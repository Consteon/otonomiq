# Route Progress Header — Dev Spec

Sticky header DriverHome: identitas driver (orang yg scan) + plat mobil (trip aktif) + (opsional) progress rute + stat drop/pickup. **Identitas & plat = DATA-BOUND** (bukan hardcode text).

**Widget tab:** `routeProgressHeader` · **Type code:** `ROUTE_PROGRESS_HEADER` · **Live:** `Widget!J200` (op1Screen `18v3w5YJ…`) · dipakai DriverHome (op1Screen 1009). Parent: `docs/driverhome-p4-dev-spec.md`.

> **v2 (2026-06-17)** — REWRITE total. v1 (`source`/`[SRC]` + `[DRIVERNAME]`/`[PLATE]` hardcode, row 198) SUPERSEDED: identity dulu hardcode text → sekarang dibaca dari tabel (workforce/stock_location). Row betul = **200** (198 sekarang `scanner`).

---

## 1. Konsep

Kartu header, isi tergantung `variant`:
1. **Identity row** — nama driver + plat mobil + tombol logout (`Keluar`). NO avatar.
2. **(variant `full`) Progress block** — label `Rute Hari Ini` + `{completed}/{total} stop` (+ `· {failed} gagal`) + bar.
3. **(variant `full`) Stat row** — Drop (`{actualDrop}/{totalDrop}`) + Pickup (`{actualPickup}/{totalPickup}`).

**Identity = data-bound** (baca tabel). **Progress counters = computed** (`{}`) dari task list — bukan field tersimpan. ([[feedback_widget_division_of_labor]]: `<>`=storage, `{}`=computed.)

---

## 2. Sumber data (PENTING — 2-3 tabel)

| tampil | tabel | search | field |
|---|---|---|---|
| **nama driver** (orang yg scan) | `workforce` | `VID◼{driverVid}` | `nameField:"n"` |
| **plat** (mobil trip aktif) | `stock_location` | `vehicleSearch:lv◼{vehicleId}` | `plateField:"ln"` |
| **progress** (variant `full`) | `task` | `taskSearch:vv◼{vehicleId}⭘tdt◼{today}` | computed §5 |

- `{driverVid}` = REAL dari scan P2 (driver.session). `{vehicleId}` = mobil **trip aktif** (lihat §2.1). `{today}` = epoch-midnight hari ini.
- variant `identityOnly` (dipakai DriverHome skrg) **gak butuh** `taskTable` — cuma nama+plat+logout.

### 2.1 `{vehicleId}` = mobil trip aktif (KRUSIAL)
Scan kartu cuma dapet DRIVER. Mobil **gak di-scan** → `{vehicleId}` di-set runtime:
- **Sekarang (1 driver=1 vehicle=1 trip):** app derive `stock_location[lt=vehicle ⭘ dv={driverVid}].lv` (cuma 1).
- **Future (driver bisa N mobil/trip):** dari **pilihan driver** di home (list trip → pick). Token sama, sumber beda; JSON gak berubah.
- Semua widget P4 key ke `{vehicleId}` yg sama → konsisten.

---

## 3. Base JSON (live `Widget!J200`)

```json
{"type":"ROUTE_PROGRESS_HEADER","variant":"identityOnly","table":"84214220504259//workforce","search":"VID◼{driverVid}","nameField":"n","vehicleTable":"84214220504259//stock_location","vehicleSearch":"lv◼{vehicleId}","plateField":"ln","logoutRoute":"[ROUTE:pauseConfirm]","text":"Rute Hari Ini◆stop◆gagal◆Drop◆Pickup◆kendaraan ditugaskan◆Keluar◆Belum ditugaskan kendaraan"}
```

Variant `full` nambah: `"taskTable":"task","taskSearch":"vv◼{vehicleId}⭘tdt◼{today}"`.

---

## 4. Field

| field | wajib | isi |
|---|---|---|
| `type` | ✅ | `ROUTE_PROGRESS_HEADER` |
| `variant` | ✅ | `identityOnly` (P4) \| `full` (progress + stat) |
| `table` / `search` | ✅ | `workforce` / `VID◼{driverVid}` — driver yg scan |
| `nameField` | ✅ | `n` — nama driver (dari doc workforce) |
| `vehicleTable` / `vehicleSearch` | ✅ | `stock_location` / `lv◼{vehicleId}` — mobil trip aktif |
| `plateField` | ✅ | `ln` — plat |
| `taskTable` / `taskSearch` | variant `full` | `task` / `vv◼{vehicleId}⭘tdt◼{today}` — sumber agregat |
| `logoutRoute` | ✅ | `[ROUTE:pauseConfirm]` — tujuan tombol Keluar |
| `text` | ✅ | 8 slot LABEL statis (`◆`). Lihat §4.1. NO data di sini. |

### 4.1 `text` — 8 slot LABEL (statis, `◆`)
```
Rute Hari Ini◆stop◆gagal◆Drop◆Pickup◆kendaraan ditugaskan◆Keluar◆Belum ditugaskan kendaraan
```
| idx | slot | pakai |
|---|---|---|
| 0 | `Rute Hari Ini` | label progress block |
| 1 | `stop` | unit stop |
| 2 | `gagal` | suffix badge gagal |
| 3 | `Drop` | label box drop |
| 4 | `Pickup` | label box pickup |
| 5 | `kendaraan ditugaskan` | label sub-identity (mobil ke-assign) |
| 6 | `Keluar` | label tombol logout |
| 7 | `Belum ditugaskan kendaraan` | **fallback** kalau mobil/vehicleSearch KOSONG |

> Nama & plat **TIDAK** di `text` — dari `nameField`/`plateField`. `text` cuma label.

---

## 5. Computed (variant `full`, dari `taskTable` list)

| var | formula |
|---|---|
| `{completed}` | count task `tst==completed` (+`validated`/`closed`?) |
| `{failed}` | count task `tst==failed`/dilaporkan-gagal |
| `{total}` | total task |
| `{progress}` | `(completed+failed)/total*100` |
| `{totalDrop}` | Σ `it[].pd` semua task |
| `{totalPickup}` | Σ `it[].pp` |
| `{actualDrop}` | Σ `it[].ad` |
| `{actualPickup}` | Σ `it[].ap` |

`it[]` = array dalam tiap task doc → renderer iterasi nested array (sama isu opsi-A widget array). Badge gagal cuma muncul kalau `{failed}>0`. Guard `{total}==0` → bar 0%, no divide-by-zero.

---

## 6. Renderer contract

1. Baca `table`/`search` → doc driver → nama dari `nameField`.
2. Baca `vehicleTable`/`vehicleSearch` (`lv◼{vehicleId}`) → doc mobil → plat dari `plateField`. **KOSONG → tampil slot fallback (idx 7) "Belum ditugaskan kendaraan"** (kasus screenshot P4 awal).
3. variant `identityOnly`: stop di sini (identity + logout). variant `full`: + baca `taskTable`, compute §5, render bar + stat box.
4. Tombol Keluar → `logoutRoute`.
5. `{vehicleId}` = active trip vehicle (§2.1). Re-render kalau task list berubah (post-submit).

> **Resolve tabel (PENTING):** nilai `table`/`vehicleTable`/`taskTable` = **`{tableVID}//{coll}`** (cth `84214220504259//workforce`) → renderer resolve ke `MobileTable/{db}/tables/{tableVID}/{coll}` (`db` dari config app). Prefix tableVID WAJIB; tanpa itu read kosong → header tampil fallback "Belum ditugaskan kendaraan".

---

## 7. Op1Screen

- Widget `routeProgressHeader` @ `Widget!A200` / template `Widget!J200`.
- Dipakai DriverHome (op1Screen row 1009), widget pertama page.
- `[ROUTE:pauseConfirm]` = placeholder route, resolve via routing app.

---

## 8. Edge cases

| kasus | perilaku |
|---|---|
| `vehicleSearch` kosong (belum ada mobil aktif) | tampil fallback slot 7 "Belum ditugaskan kendaraan", no plat |
| `{vehicleId}` belum di-set (derive gagal / belum pick) | sama: fallback |
| `search` driver kosong | nama kosong / fallback identitas |
| variant `full`, `{total}==0` | bar 0%, `0/0 stop`, stat `0/0` |
| `{failed}==0` | badge gagal disembunyiin |
| `it[].ad/ap` null | hitung 0 di Σ |

---

## 9. Open / future

- **Multi-trip (future):** driver punya N mobil/trip → home list trip → pick → set `{vehicleId}`. Header otomatis ikut (key ke {vehicleId}). JSON gak berubah, cuma cara set token.
- **Trip status** (`vehicle_check.status`: loading→awaiting_custody→…→closed) — header variant `full` BISA nampilin fase trip; belum diputus, tahan dulu.
- Avatar — **dibuang** (workforce gak ada field foto; user: gak perlu).
- variant `full` belum dipakai di P4 (skrg `identityOnly`); aktifin pas feed/route page butuh progress.

---

## 10. Versi

- **v2.0 (2026-06-17)** — REWRITE. Data-bound identity (workforce.n + stock_location.ln via 2-source), buang avatar + `[DRIVERNAME]`/`[PLATE]`/`[VEHICLEID]` hardcode + `source`/`[SRC]`. `{vehicleId}`=active trip (derive now / pick future). Row 200. text=8 label slot. variant identityOnly|full.
- v1.0 (2026-06-10) — SUPERSEDED (source-based, identity hardcode, row 198).
