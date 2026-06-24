# routeParams — Dev Spec (navigasi bawa data)

**Buat:** Flutter dev. Nambah field **`routeParams`** ke tombol navigasi — **utama widget `rbtCta`** (CTA navigate-to-route: ini widget yang dipakai tiap kali pindah ke route yang butuh parameter), generalisasi ke `RBT` child + semua widget yang punya `route` — supaya pas pindah halaman bisa **bawa data** ke route tujuan secara deklaratif.

**Status:** DRAFT, usulan 2026-06-23.

---

## 1. Masalah

Sekarang passing data antar-halaman dilakukan **bespoke per-route**. Contoh live `DRIVER_STOP_CARD` (Widget!J203):
```json
"route":"vertikaTeknoLokaciptaTaskFeed","rejectRoute":"vertikaTeknoLokaciptaRejectTask","taskIdField":"tnm"
```
Renderer hardcode: pas tombol "Tolak" → navigate ke `rejectRoute`, ambil `taskIdField` (tnm) item terpilih, taruh sebagai token `{rejectTaskVid}` di halaman tujuan. **Nama token + field-nya dihardcode di renderer.** Tiap route baru yang butuh data = nambah field bespoke (`xxxRoute` + `xxxField`) + logika token baru di renderer. Gak skalabel.

Kebutuhan konkret: tombol "Lapor sebagai gagal" di P11 DeliveryWorkspace harus pindah ke `vertikaTeknoLokaciptaFailedDelivery` sambil bawa id task aktif sebagai `{failedTaskVid}`.

---

## 2. Konsep `routeParams`

Satu field deklaratif di tombol: **peta `key → value`**. Pas navigate, renderer resolve tiap value di **konteks sumber** (data widget/halaman sekarang), terus push sebagai argumen route. Di **halaman tujuan**, tiap `key` jadi token `{key}` yang bisa dipakai di config (search, text, dll).

```json
{"text":"Lapor sebagai gagal","action":"route","route":"vertikaTeknoLokaciptaFailedDelivery","routeParams":"failedTaskVid◼{tnm}"}
```
- `failedTaskVid` = **key** → jadi token `{failedTaskVid}` di halaman tujuan.
- `{tnm}` = **value**, token yang di-resolve di konteks sumber (mis. `tnm` task yang lagi dibuka).

Gak ada nama token / field yang dihardcode di renderer lagi. Tambah route baru = cukup deklarasi `routeParams`, **tanpa ubah renderer**.

---

## 3. Encoding

String DSL, konsisten sama `search`/`addToEvent`: `◼` = pisah key/value, `⭘` = pisah antar-pasangan.
```
key1◼value1⭘key2◼value2⭘…
```
Value bisa:
- **token** `{x}` → di-resolve dari data konteks sumber (resolusi sama kayak token display).
- **literal** → dipakai apa adanya.

Contoh:
```
failedTaskVid◼{tnm}                       // 1 param, dari field tnm
failedTaskVid◼{tnm}⭘customerName◼{kn}     // 2 param
mode◼edit                                  // literal
```

> Alternatif encoding: object JSON `"routeParams":{"failedTaskVid":"{tnm}"}`. Lebih natural tapi beda dari konvensi string-DSL lain. Lihat §7.1 — pilih satu.

---

## 4. Kontrak renderer

1. Tombol punya `route` (atau `rejectRoute`/sejenis) + `routeParams`.
2. Pas navigate (`action:"route"` atau setelah `savesend` selesai):
   a. Parse `routeParams` (`◼`/`⭘`).
   b. Resolve tiap **value**: kalau `{x}` → ambil dari konteks data sumber widget/halaman ini; selain itu literal.
   c. Push pasangan `key→resolvedValue` sebagai argumen route ke halaman tujuan.
3. Di halaman tujuan, token `{key}` resolve dari argumen route ini — **selain** token global/session yang udah ada (`{vehicleId}`, `{today}`, `{driverVid}`, `{driverName}`).
4. Scope: argumen route hidup selama halaman tujuan (+ chain dialog-nya). Navigate lebih jauh **tidak** auto-propagate kecuali dideklarasi ulang.

**Scope token (penting, 2 arah):**
- Value `routeParams` di-resolve di **konteks sumber** (halaman/widget asal).
- Key `routeParams` jadi token di **konteks tujuan**.

---

## 5. Cakupan widget

- **Utama: `rbtCta`** — widget CTA khusus navigate-to-route. Inilah widget yang dipakai kalau navigasi butuh kirim parameter. `routeParams` selevel `route`.
- **Juga: `RBT` child** (tombol yang punya `route`/`action`). `routeParams` per-child, selevel `route`/`action`.
- **Generalisasi (disarankan):** taruh `routeParams` di **layer navigasi**, jadi semua widget route-capable dapet seragam — `navActionCard`, tombol di `DRIVER_STOP_CARD`, tap item list, dsb. Satu implementasi, semua dapet.

---

## 6. Contoh pakai

**P11 DeliveryWorkspace → FailedDelivery** (kebutuhan utama):
```json
{"type":"RBT","alignment":"center","children":[{"text":"Tidak bisa dieksekusi · Lapor sebagai gagal","action":"route","route":"vertikaTeknoLokaciptaFailedDelivery","routeParams":"failedTaskVid◼{tnm}"}]}
```
Halaman FailedDelivery (`vertikaTeknoLokaciptaFailedDelivery`) udah baca `{failedTaskVid}` di WORKSPACE_HEADER `search:"tnm◼{failedTaskVid}"` + RBT submit. Tinggal nyambung.

**Retrofit reject (gantiin bespoke):**
```json
// SEBELUM (driverStopCard): rejectRoute + taskIdField → renderer hardcode {rejectTaskVid}
// SESUDAH: tombol Tolak pakai routeParams
"route":"vertikaTeknoLokaciptaRejectTask","routeParams":"rejectTaskVid◼{tnm}"
```

**Yang BUKAN routeParams — token session/global.** `{driverVid}`, `{driverName}`, `{vehicleId}`, `{today}` di-set sekali saat login/scan dan **otomatis tersedia di setiap page**. JANGAN di-routeParams. routeParams cuma buat data yang **(a) beda per-navigasi DAN (b) belum ada di session** — praktisnya cuma id task yang dipilih (`{rejectTaskVid}`/`{activeTaskVid}`). Contoh: reject submit pakai `erf◼{rejectTaskVid}` (dari routeParams) + `cv◼{driverVid}`/`cn◼{driverName}` (dari session) — cuma `{rejectTaskVid}` yang lewat routeParams.

---

## 7. Open / flag dev
1. **Encoding** — string DSL `key◼value⭘…` (konsisten) **vs** object JSON `{"key":"{val}"}` (lebih natural). Pilih satu. Default usulan: string DSL.
2. **Precedence** — kalau key `routeParams` bentrok sama token global (mis. someone passes `vehicleId`), siapa menang? Usul: route-param menang (lebih spesifik).
3. **Resolusi value di konteks sumber** — konfirmasi renderer bisa resolve `{tnm}` dari data scope tombol (di dalam card per-task vs di page-level). Untuk P11 (page punya 1 task aktif) harusnya langsung.
4. **Migrasi bespoke** — `rejectRoute`/`taskIdField` (driverStopCard) bisa diganti `routeParams`. Boleh dibiarin dulu buat back-compat, `routeParams` jadi standar baru.
5. **savesend + routeParams** — tombol `savesend` yang abis nulis lalu navigate juga ngebawa `routeParams` (sama mekanik).

---

## 8. Checklist
- [ ] `RBT` child nerima `routeParams` (string DSL `key◼value⭘…`)
- [ ] resolve value `{x}` dari konteks sumber, literal kalau bukan token
- [ ] push key→value sebagai argumen route
- [ ] halaman tujuan resolve `{key}` dari argumen route (+ token global tetap jalan)
- [ ] generalisasi ke widget route-capable lain (opsional tapi disarankan)
- [ ] P11 tombol "Lapor gagal" pakai `routeParams:"failedTaskVid◼{tnm}"`
- [ ] (opsional) retrofit reject: `routeParams:"rejectTaskVid◼{tnm}"`
