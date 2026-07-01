# PRECONDITION_GATE_CARD — manifest aggregation (Dev Spec)

**Buat:** Flutter dev. Benerin daftar item di card **"Konfirmasi Penerimaan Muatan"** (DriverHome) supaya: (B) ngitung item jual/tukar, (A) ngurang otomatis pas task ditolak, (C) sembunyiin item nol.

**Status:** DRAFT, 2026-06-23. Config udah ditambah live di Widget!J201 (proxy `18v3w5YJ…`). **Update 2026-06-25:** existence gate + `itemsSearch` (date-scope) ditambah live — lihat **§8 (DEV WAJIB)**.

---

## 1. Masalah

Daftar item di card sekarang = **Σ `pd` (deliver) per item** dari `task.it[]` hari ini. Akibatnya:
1. Item yang dimuat lewat **jual (`ps`) / tukar (`pr`)** punya `pd=0` → tampil **0 walau sebenernya dimuat** (undercount).
2. Item yang punya `pd` + `ps` (mis. sebagian dianter, sebagian dijual) cuma keitung `pd`-nya.
3. Reject task (`tst=load_rejected`) **gak ngurangin** manifest — task yang ditolak masih keitung.
4. Item yang total muatnya 0 tetep nongol (ramein layar).

## 2. Data flow

- **Status gate** (badge Perlu Aksi / Dikonfirmasi / Selisih) ← `table` (`vehicle_check`) + `search` + `statusField`(cst) + `reconcileField`(rs). **Tidak berubah.**
- **Daftar item** ← agregasi `itemsTable` (`task`), `itemsField` (`it[]`), grouped by item, label dari `labelField` (`in`). **Inilah yang dibenerin.**

Manifest = **muatan yang naik ke kendaraan di gudang** = `deliver + jual + tukar`. **Beli (`pb`) TIDAK** dihitung (dibeli di customer, bukan dimuat di gudang). **Pickup (`pp`) TIDAK** dihitung (tabung kosong balik, bukan muatan).

## 3. Tiga perilaku

### B. Qty = jumlah muat (tx-aware)
Per item: `qty = Σ(qtyField + saleField + refillField)` = `Σ(pd + ps + pr)` lintas semua `it[]` di semua task. **Jangan** masukin `buyField` (`pb`) dan pickup. Sama persis logika `computeManifestFull` di seed → hasilnya match `vehicle_check.ie[]`.

### A. Exclude task yang ditolak
Pas agregasi, **skip task** yang field `tst`-nya = `excludeStatus` (`load_rejected`). Query live (Firestore stream) → begitu sebuah task di-reject, dia ilang dari agregasi → manifest **otomatis berkurang** tanpa refresh.
**Opt-in:** kalau `excludeStatus` **kosong (`""`) / absent → JANGAN exclude** (tampil semua). Exclude cuma aktif kalau field-nya diisi. (Konsisten dgn `TASK_MANIFEST_LIST`/`CIRCULATION_SUMMARY`/`DRIVER_STOP_CARD`.)

### C. Hide item nol
Setelah agregasi, **drop** item yang `qty` total = 0. (Mis. item yang cuma punya `pb`/`pp`.)

## 4. Config (Widget!J201, live)

Field baru di `PRECONDITION_GATE_CARD`:
```json
"qtyField":"pd","txField":"tx","saleField":"ps","refillField":"pr","buyField":"pb","excludeStatus":"load_rejected","hideZero":"TRUE"
```
- `qtyField` (pd) + `saleField` (ps) + `refillField` (pr) → dijumlah jadi qty muat.
- `buyField` (pb) → dideklarasi biar jelas TIDAK dihitung.
- `txField` (tx) → diskriminator per-line (opsional, kalau dev mau klasifikasi by tx daripada by-field).
- `excludeStatus` (load_rejected) → status task yang di-skip.
- `hideZero` (string `"TRUE"`, bukan boolean) → buang item qty 0.

## 5. Contoh grounded (data seed `Barang`, 4 task)

| item | pd | ps | pr | pb | **qty muat (pd+ps+pr)** |
|---|---|---|---|---|---|
| LPG 3kg | 4 | - | - | - | **4** |
| Aqua Galon 19L | 11 | 4 | - | - | **15** |
| Amidis Galon 19L | 3 | - | - | 4 | **3** |
| LPG 12kg | 0 | 3 | - | 5 | **3** |
| Pristine RO 19L | 0 | - | 2 | - | **2** |
| LPG 15kg | 0 | 2 | - | - | **2** |
| Aqua 600ml Karton | 0 | 8 | - | - | **8** |

Sekarang (pd-only) card nampil `4 / 11 / 3 / 0 / 0 / 0 / 0`. Harusnya `4 / 15 / 3 / 3 / 2 / 2 / 8`. (Tidak ada qty 0 → `hideZero` tidak buang apa-apa di data ini.)

## 6. Contoh reject (excludeStatus)

Task **Indomaret BSD** (TASK-…-102) isinya: LPG 3kg pickup (pd=0), Aqua **jual ps=4**, Amidis beli (pb=4). Muatannya = **Aqua 4** doang.

Reject Indomaret (`tst=load_rejected`) → agregasi skip task itu → **Aqua 15 → 11**. Item lain tetap (Indomaret gak nyumbang muat selain Aqua). Live, tanpa refresh.

> Catatan: tanpa perilaku **B**, reject Indomaret = **0 perubahan keliatan** (Indomaret gak punya `pd`). B + A wajib bareng biar reject sale/tukar keliatan.

## 7. Open
1. ✅ **RESOLVED 2026-06-25** → `itemsSearch` ditambah, lihat §8.
2. **vehicle_check.ie[] vs agregasi task** — `ie[]` (manifest gudang, statis) udah = `pd+ps+pr`. Card sengaja agregasi `task.it[]` (live) biar bisa react ke reject. Dua-duanya harus konsisten; kalau beda, `ie[]` = baseline gudang, agregasi task = rencana live.
3. ✅ **RESOLVED 2026-06-25** → existence gate (`gateSearch`) misahin "ada doc hari ini" dari "state cst", lihat §8.

## 8. Date-scope: existence gate + itemsSearch (DEV WAJIB) — 2026-06-25

**Bug ketemu (seed lintas-hari):** seed dibikin H-1, gak di-re-seed. Besoknya **"Rute Hari Ini" = 0 tujuan** (driverStopCard `tdt◼{today}` no-match karena `tdt` firebase = kemarin) **TAPI card "Konfirmasi Penerimaan Muatan" tetap nongol + nampilin item kemarin** (Amidis ×3). Inkonsisten: konfirmasi muatan tanpa rute gak masuk akal.

**Akar:** card ini gak honor date di 2 tempat —
1. **Existence**: renderer nentuin card muncul dari `search` (`…cdt◼{today}⭘cst◼custody_confirmed`). Pas kosong, gak bisa bedain **"gak ada doc hari ini"** vs **"ada tapi belum confirmed"** → dua-duanya jatoh ke state "Perlu Aksi" → card nongol walau gak ada opening doc hari ini.
2. **Item list**: agregasi `task.it[]` di-scope `vv` doang (date-agnostic) → ketarik task kemarin.

**Fix config (LIVE — Widget!J201 + op1Screen D1011):** 3 field baru di `PRECONDITION_GATE_CARD`:
```json
"gateTable":"84214220504259//vehicle_check",
"gateSearch":"cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}",
"itemsSearch":"vv◼{vehicleId}⭘tdt◼{today}"
```
- `gateTable`/`gateSearch` = **existence gate**, `cst`-agnostic (sengaja TANPA `cst◼…`). Mirror pola `INVENTORY_BUCKET_CARD`/`DRIVER_STOP_CARD`.
- `itemsSearch` = scope agregasi item, **sama persis** kaya `search`-nya driverStopCard/taskManifestList.

**Dev WAJIB:**
1. **Existence (hide kalau no-match):** cari opening doc pakai `gateSearch` (honor `cdt◼{today}`, **abaikan `cst`**). **KOSONG → HIDE seluruh card** (jangan render "Perlu Aksi"). KETEMU → render; state badge (Perlu Aksi / Dikonfirmasi / Selisih) tetap dari `statusField` (`cst`) via `search`+`reconcileField`. Ini misahin **ada-load-hari-ini** dari **status-confirm** — fix §7 #3.
2. **Item scope:** agregasi `itemsTable` pakai **`itemsSearch`** (`vv◼{vehicleId}⭘tdt◼{today}`), BUKAN `vv`-only. Hasil = mirror route. Fix §7 #1.

**Efek:** besoknya (data basi / gak ada task hari ini) card **ilang barengan** sama route — konsisten. Re-seed → dua-dua balik muncul.

> Backward-compat: kalau `gateSearch`/`itemsSearch` kosong/absent → fallback perilaku lama (jangan gate / scope vv-only). Opt-in, sama kaya `excludeStatus`.
