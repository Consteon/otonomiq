# Customer name-list + creator-token — Dev Spec

Dua ketahan yang muncul saat test live Admin P1 (`vertikaTeknoLokaciptaCreateTaskCustomer`):

1. **Customer list blank** walau data di `stock_location` ada (`ln:"Halooo"`, `lt:"client"`, `lst:"active"`).
2. Customer baru hasil N1 nyimpen **creator field literal** (`cv:"{adminVid}"`, `cn:"{adminName}"`) — token gak ke-resolve.

Keduanya = **renderer/wiring gap**, bukan config sheet. Query + data udah bener (udah diverifikasi di Firestore console). Doc ini kasih perubahan renderer + JSON resolved siap-pakai.

---

## 1. Customer list — extend `TASK_FEED_LIST` jadi `groupField` optional

### Kenapa bukan widget lain
- `LIST_STATISTIC_CARD` (keyed) = render **BLANK** untuk data non-attendance (udah lo konfirmasi di feedback H1). Itu yg lagi kepasang di P1 → makanya blank.
- `LIST_ITEM_CARD` baca **positional `<N>`** — `ln` di doc customer nyangkut di tail `★`-join field `ev`, bukan ◆-index bersih → gak kebaca.
- `TASK_FEED_LIST` = SATU-SATUNYA list yg udah live+tested baca **named field** (`titleField`/`addressField`/`idField`) dari koleksi keyed. Reuse ini, **bukan** bikin widget baru.

### Yang ngeblok
`TASK_FEED_LIST` sekarang **wajib grouped** (`groupField:"tst"` di driver, section-header per status delivery). Customer-picker = flat, gak ada status grouping. Repoint dengan `groupField:"lst"` → group value `"active"` gak dikenal renderer driver → resiko blank lagi.

### Perubahan renderer (kecil, additive, backward-compat)
`groupField` jadi **optional**:

| `groupField` | perilaku |
|---|---|
| non-empty (`"tst"`) | **MODE GROUPED** (sekarang) — section-header per nilai, label dari `text` ◆-segment. Driver TaskFeed gak berubah. |
| `""` (kosong) | **MODE FLAT** (BARU) — render SEMUA row yg match `search`, urut as-is, **tanpa** section-header, **tanpa** status-filter. |

Di MODE FLAT, field delivery-only yg kosong **di-skip total** (jangan render badge/counter): `typeField`, `itemsField`, `dropField`, `pickupField`, `actualDropField`, `actualPickupField`, `returnGateTable`, `returnGateSearch`, `returnRoute`. Tiap card = `titleField` (judul) + `addressField` (sub) + tap→`route` doang.

`text` di MODE FLAT: cuma segment depan dipakai sbg judul/sub list (gak ada group label). Segment sisanya diabaikan.

Tap row → `route` + bawa nilai `idField` (sama mekanisme kaya driver: tap card kirim `idField` ke route tujuan). Di sini `idField:"lv"` → P2 (`CreateTaskItem`) baca sbg customer id (`{kl}`). Pastikan P2 nerima token id yg sama yg dikirim renderer (samain konvensi sama driver `{activeTaskVid}`).

### JSON resolved — MODE FLAT (customer picker, P1 row 1163)
```json
{
  "type": "TASK_FEED_LIST",
  "vidtable": "20342033315492",
  "table": "84214220504259//stock_location",
  "search": "lt◼client⭘lst◼active",
  "groupField": "",
  "idField": "lv",
  "titleField": "ln",
  "addressField": "al",
  "iconField": "",
  "searchHint": "Cari customer atau alamat…",
  "typeField": "",
  "itemsField": "",
  "dropField": "",
  "pickupField": "",
  "actualDropField": "",
  "actualPickupField": "",
  "route": "vertikaTeknoLokaciptaCreateTaskItem",
  "returnGateTable": "",
  "returnGateSearch": "",
  "returnRoute": "",
  "countLabel": "Customer",
  "emptyText": "Belum ada customer",
  "text": "Customer◆Pilih customer untuk order"
}
```
Hasil yg diharapin: 1 card "Halooo" / sub "mantap", tap → CreateTaskItem bawa `lv`.

### §1b Visual MODE FLAT — REFACTOR "sama persis" mockup P1
Flat-mode SEKARANG masih ke-render gaya driver-task-feed (kartu task + drop/pickup) → **jelek buat list customer**. Refactor tampilan flat-mode jadi **PERSIS card mockup** `src/component/AdminCreateTaskIntegrated2.jsx` → `CustomerPickerScreen` (**L343–405**, empty L407). **TETEP GENERIC** — config-driven, customer cuma 1 config; card ini reusable buat list keyed apapun (NOL "customer" baked).

**Anatomi card (per row) — match mockup:**
| bagian | mockup | config |
|---|---|---|
| container | surface, border 1px, radius 12, pad 12×14, mb 8, tap-feedback | — |
| kiri (avatar) | 40×40 radius 10 bg slate100, emoji | `iconField` (emoji/char) ATAU fallback huruf depan `titleField` |
| judul | 14px bold, ellipsis 1 baris | `titleField` |
| sub | 11px textMid, ellipsis 1 baris | `addressField` |
| badge (opsional) | Chip "↑ {N} outstanding" + warn aging | `badgeTable`+`badgeSearch` (count per-row, token baris `{lv}`) + `badgeLabel` + tier |
| kanan | chevron `›` textDim | — |
| header list | "{N} {countLabel}" uppercase dim | `countLabel` (N = jumlah match) |
| empty | 🔍 + teks (L407) | `emptyText` |

**Search bar (built-in, di ATAS list — mockup L300–331):** box "🔍 + `searchHint`" filter LOKAL row yg udah keload by `titleField`+`addressField` (mockup filter name OR address). ⚠ Di P1 live, TXT-search + TXT-label "Customer" terpisah udah **di-OFF-in (F=FALSE)** — owner mau **list self-contained**: search + count-header + cards + empty NYATU dalam 1 widget (persis mockup). Jadi widget ini WAJIB punya search box sendiri (config `searchHint`), bukan ngandelin TXT luar.

**Badge & genesis-chip = OPSIONAL.** Customer pasang badge outstanding (`badgeTable:asset_cache`, Σ qt). List lain boleh omit → badge gak muncul. Chip "belum di-seed" = **DERIVED customer-specific** (client tanpa GENESIS movement), BUKAN field (cover §4) → skip buat list non-customer.

**Field display tambahan (flat-mode, opsional kecuali title/sub):** `iconField`, `countLabel`, `emptyText`, `badgeTable`, `badgeSearch`, `badgeLabel`.

> GENERIC: card avatar/title/sub/badge/chevron + tap→route = list keyed apapun (customer, item, lokasi, dll). Grouped-mode driver TIDAK berubah.

### JSON — MODE GROUPED (driver TaskFeed, row 1066, TIDAK BERUBAH — ref backward-compat)
```json
{
  "type": "TASK_FEED_LIST",
  "vidtable": "20342033315492",
  "table": "84214220504259//task",
  "search": "vv◼{vehicleId}⭘tdt◼{today}",
  "groupField": "tst",
  "idField": "tnm",
  "titleField": "kn",
  "addressField": "al",
  "typeField": "tty",
  "itemsField": "it",
  "dropField": "pd",
  "pickupField": "pp",
  "actualDropField": "ad",
  "actualPickupField": "ap",
  "route": "vertikaTeknoLokaciptaDeliveryWorkspace",
  "returnRoute": "vertikaTeknoLokaciptaReturnVehicle",
  "text": "Stop Berikutnya◆Pilih sesuai kondisi lapangan◆Dilaporkan Gagal◆Sudah Selesai◆Pickup Only◆drop◆pickup◆Mulai Eksekusi◆✓ Selesai◆Customer confirmed◆! Dilaporkan gagal — menunggu admin reschedule◆🎉◆Semua Stop Selesai◆Lo bisa kembali ke gudang untuk closing check.◆Kembali ke Gudang"
}
```

> Dependency sama dengan 3 feed H1 (`RUNNING_TASK_LIST`/`UPCOMING_TASK_LIST`/`OUTSTANDING_PANEL`) — semua butuh render name-list dari koleksi keyed. `groupField`-optional ini bisa jadi fondasi bareng.

---

## 2. Creator token — wire 1 session token generik (role-agnostic)

### Bug
N1 (`NewCustomer`) `addToEvent` nulis `cv◼{adminVid}⭘cn◼{adminName}`. Doc kebuat nyimpen **string literal** `"{adminVid}"`/`"{adminName}"` — token gak ke-resolve.

### Root cause
`{driverVid}`/`{driverName}` ke-resolve cuma karena dev **wire** mereka ke session login (workforce VID + nama) **buat runtime driver** (lihat `driver-evidence-addToEvent-dev-spec.md` §6). Itu nama token **role-spesifik**. Admin session **gak punya** token setara yg ke-wire. `{adminVid}`/`{adminName}` = nama yg belum di-wire → diperlakukan literal.

### Fix — token current-user generik
Wire SATU token session role-agnostic = **VID + nama user yg lagi login** (workforce), kepake di SEMUA runtime (driver/admin/gudang). Rekomendasi nama:

| token | isi | sumber |
|---|---|---|
| `{userVid}` | VID user login (workforce VID) | session login |
| `{userName}` | nama user login (denorm) | session login |

> Nama `{userVid}`/`{userName}` = **rekomendasi**; kalau dev udah punya token current-user yg ke-wire (nama lain), pakai itu — kabarin nama persisnya, gue samain di sheet. Jangan reuse `{driverVid}` apa adanya buat admin (semantik salah).

Opsional: migrasi `{driverVid}`/`{driverName}` → `{userVid}`/`{userName}` biar konsisten (atau aliasin).

### N1 addToEvent — string betulan (ganti `{adminVid}`/`{adminName}`)
```
84214220504259//stock_location⭘r◼4320⭘tablevid◼20342033315492⭘lt◼client⭘ln◼◁1▷⭘al◼◁3▷⭘lst◼active⭘cv◼{userVid}⭘cn◼{userName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶
```
(`ln◼◁1▷` nama dari form pos 1, `al◼◁3▷` alamat pos 3 — udah bener; cuma creator yg diganti.)

---

## 3. Apply (urutan)
1. **Dev:** `groupField`-optional di renderer `TASK_FEED_LIST` (§1) + wire `{userVid}`/`{userName}` session token (§2).
2. **Sheet (design, SETELAH renderer ship — ship config+renderer bareng):**
   - `op1Screen!D1163` ← JSON MODE FLAT (§1). Label `B1163` ← `taskFeedList`.
   - `op1Screen!D1209` (N1 RBT) ← ganti `cv◼{adminVid}⭘cn◼{adminName}` → `cv◼{userVid}⭘cn◼{userName}`.
3. Verify live: card customer nongol + tap→CreateTaskItem bawa `lv`; bikin customer baru → cek doc `cv`/`cn` = nilai asli (bukan literal).

> ⚠️ Jangan pre-stage config token-bearing sebelum renderer support — widget bisa ke-DROP (lihat lesson `config-ahead-of-renderer`). Makanya step 2 NUNGGU step 1.
