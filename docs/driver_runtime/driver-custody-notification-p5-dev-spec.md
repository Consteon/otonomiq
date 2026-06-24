# P5 CustodyNotification — Dev Spec (per-page)

**Buat:** Flutter dev. Page custody **notifikasi/blok** sebelum driver mulai rute. Read-only (display) + 1 tombol → P6.
**Flow:** P4 gate "Konfirmasi Penerimaan" → **P5 (ini)** → P6 CustodyCount → reveal → P7 match / P8 selisih.
**Source:** `json/driver-runtime/p5-custody-notification.json`. Runtime req (path + token) = lihat `docs/driver-p4-handoff-dev.md` §0.

---

## 0. Konsep

Vehicle udah dimuat gudang (opening custody dibuat) → driver dikasih tau muatannya + diblok mulai task sampe konfirmasi (P6). P5 cuma **nampilin** (manifest + total), gak nulis apa-apa. Tombol → P6.

Urutan (match mockup): **warn banner → vehicle card → task manifest → total circulation → button**.

---

## 1. Widget (5)

### 1.1 `noticeBar` (warn) — udah ada
Banner blok di atas.
```json
{"type":"noticeBar","variant":"warn","icon":"[ICON]","label":"KONFIRMASI DIPERLUKAN","title":"Vehicle siap berangkat, butuh konfirmasi penerimaan","text":"Lo belum bisa mulai task hari ini sebelum konfirmasi load dari warehouse."}
```
3-tier: `label` (caps kecil) · `title` (bold) · `text` (body). Spec: `docs/notice-bar-widget-dev-spec.md`.

### 1.2 `vehicleCustodyHeader` — BARU
Kartu vehicle: plat + dimuat oleh + jam + custody event. Baca `vehicle_check` opening.
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` |
| `vehicleTable` / `vehicleSearch` | `84214220504259//stock_location` / `lv◼{vehicleId}` |
| `plateField` | `ln` — plat (join via vehicle, sama kaya header P4) |
| `eventField` | `cnm` — custody event id |
| `loaderField` | `gn` — "Dimuat oleh" (**gudang-flow, PENDING** — belum di-seed) |
| `loadtimeField` | `ldt` — "Waktu loading" (**gudang-flow, PENDING**) |
| `text` (◆, 4 slot) | `Penerimaan Muatan◆Dimuat oleh◆Waktu loading◆Custody event` |

Render: plat dari `stock_location.ln`; event dari `cnm`; loader/jam dari `gn`/`ldt` (kosong dulu sampe gudang-flow ada → tampil "—" atau hide baris).

### 1.3 `taskManifestList` — BARU
List per-task (1 task = 1 baris) + agregat drop/pickup. **Collection-of-docs (task) + per-row Σ dari nested `it[]`.**
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//task` / `vv◼{vehicleId}⭘tdt◼{today}` |
| `idField` | `tnm` — badge "T-050" |
| `titleField` | `kn` — nama customer (denorm) |
| `subtitleField` | `al` — alamat (denorm) |
| `itemsField` | `it` — sumber agregat |
| `dropField` | `pd` — ↓ = **Σ `it[].pd`** per task |
| `pickupField` | `pp` — ↑ = **Σ `it[].pp`** per task |
| `route` | `[ROUTE:taskDetail]` — tap baris → detail (page belum ada) |
| `text` (◆, 6 slot) | `Task Manifest◆task◆item line◆drop◆pickup◆tap untuk lihat detail` |

Render: tiap task → baris `[tnm] kn / al  ↓Σpd ↑Σpp →`. Header "N task · M item line" = count(task) + **Σ `it[].length`**. (Drop & pickup = field terpisah `pd`/`pp`; GAK pake `cd`+arah lagi.)

### 1.4 `circulationSummary` — BARU
Total seluruh rute.
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//task` / `vv◼{vehicleId}⭘tdt◼{today}` |
| `itemsField` | `it` |
| `dropField` / `pickupField` | `pd` / `pp` |
| `text` (◆, 4 slot) | `Total Circulation◆Muat◆Total ↓ drop◆Total ↑ pickup◆Muat awal = jumlah drop total. Pickup nambah ke vehicle selama rute.` |

Render: total muat/drop = **Σ semua `pd`**; total pickup = **Σ semua `pp`** (lintas semua task).

### 1.5 `RBT` (route button) — udah ada
```json
{"type":"RBT","alignment":"center","children":[{"text":"MULAI KONFIRMASI PENERIMAAN","route":"[ROUTE:custodyCount]"}]}
```
→ P6 CustodyCount. CTA nav; `children`=[{`text`,`route`}]. (button1 diganti RBT.)

---

## 2. Field codes (P5)

- `vehicle_check`: `cnm`(event)·`cty`·`vv`(FK mobil)·`cdt`(epoch-midnight)·`gn`/`ldt`(gudang, PENDING).
- `stock_location`: `lv`·`ln`(plat).
- `task`: `tnm`·`kn`(cust nama)·`al`(alamat)·`vv`·`tdt`·`it[]`.
  - `it[]`: `pd`(planned_drop)·`pp`(planned_pickup)·`ii`·`in`. (Drop=`pd`, Pickup=`pp` — eksplisit, gak ada field arah.)

Full: `docs/driver-runtime-field-dictionary.md`. Runtime path+token: `docs/driver-p4-handoff-dev.md` §0.

---

## 3. Register type baru (3)

`vehicleCustodyHeader`, `taskManifestList`, `circulationSummary`. (`noticeBar`/`button1` udah ada.)
- `taskManifestList`/`circulationSummary` = baca **collection task** + iterasi **nested `it[]`** tiap doc buat Σ `pd`/`pp`. Widget list lama (collection-per-doc, gak bisa agregat nested array) GAK cocok.

---

## 4. Open / confirm

| # | item | status |
|---|---|---|
| 1 | **gudang-flow** `gv`/`gn`(dimuat oleh)+`ldt`(jam) | **SEED WAJIB (gudang precedes driver)** — gudang muat SEBELUM driver dateng, jadi pas driver buka P5 data gudang HARUS udah ada di `vehicle_check` opening. Gudang-app belum dibikin ⇒ hand-seed manual SEKARANG (kaya `ie[]`): `gv`(vid),`gn`(nama, cth "Anton Pratama"),`ldt`(epoch jam muat). Bukan "tampil —"; data emang prasyarat custody. Nanti gudang-app yg nulis otomatis. |
| 2 | **custody event display** | **RESOLVED** — pakai `cnm` (live seed = `CHK-VEH-B1234XY-20260615-OPEN`). Mockup "CEC-0284" cuma ilustratif; GAK ada field CEC terpisah. |
| 3 | **tap → detail** `[ROUTE:taskDetail]` | **LATER** — page detail task dibikin setelah custody flow (P5–P9). Sementara placeholder. |
| 4 | **routing** P4 gate → P5 | logis: P4 gate `[ROUTE:custodyConfirm]` → **P5 ini** → (button) P6. (belum di-confirm eksplisit; ikut flow mockup) |
| 5 | "N item line" count | **CONFIRMED** = Σ `it[].length` lintas task. |
| 6 | 3 widget baru | **CONFIRMED** (opsi-A array iterate). |

---

## TX-DELTA + REJECT (2026-06-22) — transaksi jual/beli/tukar + exclude task ditolak

Acuan: `docs/driver-runtime-transaction-delta.md`. `taskManifestList` + `circulationSummary` baca **collection task** → kena 2 perubahan.

### A. Exclude `tst=load_rejected`
Task yg ditolak driver (Tolak @P4, lihat `driver-stop-card-dev-spec.md` §15 + `driver-reject-task-sheet-dev-spec.md`) = **barang gak naik mobil**. Manifest HARUS skip.

- `taskManifestList` + `circulationSummary` tambah filter: **`tst≠load_rejected`** pas agregasi.
- Config: `excludeStatus:"load_rejected"` (atau `statusField:"tst"` + skip-list). Kalau gak di-exclude → manifest (`ie`) ketinggian vs hitung fisik (`ip`) → **selisih palsu** (`dp`) di P6/reveal padahal data bener.

> **⚠️ RENDERER STATUS (2026-06-23) — PENDING.** Config `excludeStatus:"load_rejected"` UDAH live di `taskManifestList` + `circulationSummary`, **tapi renderer belum baca** → test nunjukin keduanya masih nampil SEMUA task (termasuk yang `load_rejected`). Implement = **SAMA mekanik kaya `PRECONDITION_GATE_CARD` `excludeStatus`** — yang **UDAH JALAN** di card "Konfirmasi Penerimaan Muatan" (DriverHome). Yaitu: pas agregasi, **skip task yang `tst == excludeStatus`** (`load_rejected`), live stream (drop otomatis pas task di-reject).
> - **Opt-in:** kalau `excludeStatus` **kosong (`""`) / absent → JANGAN exclude** (tampil semua). Exclude cuma aktif kalau field-nya diisi.
> - **`failed` ≠ `load_rejected`:** task `failed` (gagal eksekusi) tetep keitung; cuma `load_rejected` (tolak opening) yang di-skip dari muat awal.

### B. tx-aware agregasi (slot qty per tx)
Dulu `dropField:pd`/`pickupField:pp` asumsi **semua deliver**. Sekarang tiap baris `it[]` punya `tx` → slot qty beda:

| tx | full keluar gudang (muat awal) | empty masuk (selama rute) | kontribusi manifest |
|---|---|---|---|
| **deliver** | `pd` (full) | `pp` (empty) | muat `pd`, pickup `pp` |
| **sale** | `ps` (full, permanen) | — | muat `ps` |
| **refill** | `pr` (full) | `pr` (empty, swap) | muat `pr` |
| **purchase** | **0** (gak dimuat gudang) | `pb` (empty, dari customer) | **EXCLUDE dari muat awal** |

> **Purchase (`pb`) TIDAK dimuat di gudang** — barang naik mobil mid-rute dari customer. Jangan ikut "barang naik mobil" / manifest awal. Cuma nambah empty selama rute (relevan di reveal/closing, bukan opening count).

**Manifest awal (full loaded @gudang)** per task = `Σ(pd + ps + pr)` baris non-purchase, non-rejected.
**Total circulation:**
- Muat awal (full) = `Σ(pd + ps + pr)` lintas task (exclude rejected, exclude purchase).
- Keluar permanen (sale) = `Σ ps`.
- Masuk empty selama rute = `Σ(pp + pr + pb)`.

### C. Config delta
- `taskManifestList`: +`txField:"tx"` · +`saleField:"ps"` · +`refillField:"pr"` · +`buyField:"pb"` · +`excludeStatus:"load_rejected"`. `dropField`/`pickupField` tetep (deliver). Σ muat = `pd+ps+pr` (skip purchase).
- `circulationSummary`: idem + 3 text seg baru (`Jual (full keluar)◆Tukar (swap)◆Beli (empty masuk)`).
- `it[]` field codes (P5): tambah `tx`·`ps`·`pr`·`pb` (+`as`/`ar`/`ab` aktual, gak dipake di manifest awal). Full: `driver-runtime-field-dictionary.md`.

### D. Catatan badge per baris
Baris manifest task boleh kasih chip kecil tx kalau mixed (mis. "JUAL"/"TUKAR"/"BELI") biar driver paham. Default deliver = tanpa chip.

---

## 5. References
- `json/driver-runtime/p5-custody-notification.json` (source)
- `docs/driver-runtime-transaction-delta.md` (tx + reject schema delta)
- `docs/driver-p4-handoff-dev.md` (runtime req: path+token)
- `docs/driver-runtime-field-dictionary.md` · `docs/driver-runtime-tables-dev-spec.md` (schema)
- `docs/notice-bar-widget-dev-spec.md` (banner)
- Custody flow lanjutan: P6 CustodyCount → P7 Success / P8 MismatchReport → P9 Submitted (belum di-spec).
