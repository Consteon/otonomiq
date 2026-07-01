# Admin Create Task — Dev Spec (P1–S3 wizard)

**Runtime:** Admin (Koordinasi) · mobile op1Screen. Sibling of `admin-home-dev-spec.md` (H1).
**Mockup:** `src/component/AdminCreateTaskIntegrated.jsx` (semua screen) · prototype routing `AdminRuntimeFlow.jsx` · overview `AdminRuntimeGallery.jsx`.
**Scope:** the create-task flow yang dilaunch dari H1 (Order Masuk / Customer Baru / Walk-in). Satu doc, section per-page.

> Legend: ✅ reuse (renderer BUILT) · 🔶 reuse (template ada, renderer shared-pending dgn driver) · 🆕 NEW · write = DSL scalar / **native array** / addToEvent

**Routing (entry dari H1):**
```
H1 ─Customer Baru/Order Masuk→ P1 ─pilih→ P2 ─→ P3 ─→ P4 ─submit→ P5 ─→ H1
                                 └+baru→ N1 → N2 → P2
                                              P2 ─Seed(genesis pending)→ S1 → S2 → S3 → P2
H1 ─Walk-in→ W1 ─counter→ W3(selesai)
                 └dikirim→ P3 → P4 → P5
```

---

## §1. `taskItemBuilder` 🆕 — widget INTI (P2 · W1 · re-skin S1)

Bangun array baris transaksi. Add/remove baris, tiap baris punya **jenis transaksi** (`tx`) → field `it[]` beda. **Output = `task.it[]` (native array).**

### 1.1 Jenis baris → mapping `it[]` (grounded ke `driver-runtime-field-dictionary.md`)

| UI line | `tx` | qty field | kondisi | catatan |
|---|---|---|---|---|
| **Antar** (LOAN, default returnable) | `deliver` | `pd` (drop) + `pp` (pickup) | `cdo` keluar / `cdi` masuk | Model B: `pp` = `pd` + outstanding |
| **Jual** | `sale` | `ps` | `cdo` (kosong/penuh) | no pickup; outstanding untouched |
| **Beli** | `purchase` | `pb` | `cdi` (kosong/penuh) | masuk pool; outstanding untouched |
| **Tukar / Refill** | `refill` | `pr` | — | galon customer, tukar 1:1; `wt` (ro/refill) di `item`, label konten |
| **Consumable** (walk-in) | `sale` | `ps` | — | jual lepas, no return |

Tiap baris juga: `ii` (item id, FK→item), `in` (nama, denorm). Actual (`ad`/`ap`/`as`/`ab`/`ar`) **TIDAK** ditulis Admin — itu CF-derived saat driver eksekusi.

**Harga per baris (`hg`) — FIELD BARU di line.** Baris berbayar (SALE; deliver kalau ditagih) bawa `hg` = harga satuan. ⚠ **JANGAN `pr`** — `pr` udah = `plan_refill`. Usul **`hg`** (harga). Subtotal = `hg × qty` ({dev}). Default = harga produk (pricelist global §11.8), override per-baris boleh. Refill = harga terpisah/parkir (bukan `hg`).

### 1.2 Model B (logic note — {dev}-computed)
`pp_suggested = pd + outstanding(client,item)`.
- `outstanding` = net `asset_cache` row di client itu (`lt=client`, `lv={kl}`, `ii`, `cd`). Lihat `driver-runtime-movement-cf-handoff.md`.
- recompute `pp` tiap `pd` berubah **kecuali** user udah adjust manual (`pickupManuallyAdjusted` flag — internal widget state, bukan field tersimpan).
- **genesis pending** (client belum di-seed → gak ada asset_cache row) → suggestion **OFF**, `pp` manual. "belum di-seed" = derived, BUKAN field (lihat cover).

### 1.3 Sub-komponen (reuse)
- qty stepper → `stepper` ✅ (palette per tx: drop/pickup/sale/buy/refill).
- pilih jenis transfer (Jual/Beli) + kategori → `selectableGrid` ✅.
- toggle kondisi (kosong/penuh) + water (RO/isi ulang) → `switch` ✅ / `selectableGrid`.
- picker produk (katalog) → `displayList` ✅ over `item` (filter: belum di-task; tandai yg ada outstanding).

### 1.4 Picker sheets (di-trigger dari builder)
| sheet | isi | widget |
|---|---|---|
| productPicker | item catalog (returnable+consumable), exclude in-task | `displayList` ✅ |
| transferKepemilikan | Jual/Beli → kategori returnable | `selectableGrid` ✅ |
| refillCategory | kategori galon (Water) | `selectableGrid` ✅ |
| consumablePicker (walk-in) | consumable only | `displayList` ✅ |

### 1.5 Config schema (usul)
```
type: taskItemBuilder
mode: order | walkin | (seed = widget lain, lihat §9)
itemTable: item ; tablevid: 20342033315492
itemIdField: ii ; itemNameField: in ; itemCatField: ic ; itemUnitField: un ; waterTypeField: wt
outstandingTable: asset_cache    # Model B suggestion source (lt=client, lv={kl})
outstandingQtyField: qt ; outstandingCondField: cd
txTypes: [deliver, sale, purchase, refill]    # mode-gated
writeTarget: task.it              # NATIVE ARRAY (lihat §10)
text: "◆Tambah Item◆Transfer Kepemilikan◆Refill◆Jual◆Beli◆Kosong◆Penuh◆Air RO◆Isi Ulang"
```

### 1.5b JSON resolved — LIVE (op1Screen P2 row 1169, mode order)
```json
{
  "type": "TASK_ITEM_BUILDER",
  "vidtable": "20342033315492",
  "mode": "order",
  "itemTable": "84214220504259//item",
  "itemIdField": "ii",
  "itemNameField": "in",
  "itemCatField": "ic",
  "itemUnitField": "un",
  "waterTypeField": "wt",
  "searchField": "in",
  "searchHint": "Cari produk…",
  "outstandingTable": "84214220504259//asset_cache",
  "outstandingSearch": "lt◼client⭘lv◼{kl}",
  "outstandingQtyField": "qt",
  "outstandingCondField": "cd",
  "txTypes": "deliver",
  "writeTarget": "it",
  "dropField": "pd",
  "pickupField": "pp",
  "saleField": "ps",
  "buyField": "pb",
  "refillField": "pr",
  "priceField": "hg",
  "condOutField": "cdo",
  "condInField": "cdi",
  "text": "Tambah Item◆Transfer Kepemilikan◆Refill◆Jual◆Beli◆Kosong◆Penuh◆Air RO◆Isi Ulang"
}
```
`{kl}` = customer id dari P1 (`idField:lv`). `outstandingSearch` Model B per-client. Output draft `it[]` → di-carry P3/P4, ditulis native di P4 submit.

**Search (productPicker):** `searchField:"in"` = filter katalog lokal by nama item; `searchHint` = placeholder box cari (config-driven, BUKAN hardcode — sejajar customer-picker P1 "Cari customer…"). Picker sheet = search box di atas + list `availableProducts` (exclude yg udah di-task). Empty katalog = "Semua item sudah ditambahkan" (mockup `ProductPickerSheet`).

**⚠ Tx-button gating (BUG live 2026-06-29 — RENDERER FIX):** tombol transaksi (Tambah Item=`deliver` · Jual=`sale` · Beli=`purchase` · Refill=`refill`) **WAJIB di-render dari `txTypes` doang** — type yg gak ada di list = tombol HILANG; urutan `txTypes` = urutan tombol. **Live-test:** set `txTypes:"deliver"` di app live → **4 tombol tetep muncul semua** = renderer SEKARANG hardcode tombol, gak baca `txTypes`. Fix = renderer loop `txTypes` buat bikin tombol (config-driven, no deploy buat tambah/kurang). Owner mau mulai `deliver` aja, tambah `sale`/`purchase`/`refill` nanti via JSON. Field-map per type (`saleField`/`buyField`/`refillField`/cond) tetep ada di config — cuma kepake kalau type-nya aktif.

### 1.6 Render states
- empty → CTA "Tambah Item / Transfer / Refill".
- per baris kartu sesuai tx (lihat mockup `TaskItemCard`: LOAN=2 stepper, SALE/PURCHASE=kondisi toggle+1 qty, REFILL=water toggle+1 qty).
- footer summary {dev}: Drop / Pickup / Beli / Refill totals.

### 1.7 Write
`task.it[]` = **NATIVE ARRAY**. DSL gak bisa rakit array (sama kayak custody `ip[]`/`dp[]`). Renderer assemble objek `it[]` dari state → native Firestore. Config cuma declare field-map. **Submit aktual di P4 (§5).**

---

## §2. P1 — CustomerPicker (Step 1/4) — reuse

| # | elemen | widget | st | data |
|---|---|---|---|---|
| 1 | Header (✕ · step · "Pilih Customer") | `workspaceHeader` | 🔶 | static |
| 2 | Search | `searchFromTable` | ✅ | filter `stock_location(client)` `ln`/`al` |
| 3 | "{N} Customer" | `text` | ✅ | count {dev} |
| 4 | List customer | `displayStatisticCard` keyed | ✅ | `stock_location` `lt=client`: `ln`,`al`, badge outstanding (Σ `asset_cache` qt {dev}), badge "belum di-seed" (derived), → route P2 (bawa `{kl}`) |
| 5 | "+ Customer Baru" | `buttonRoute` | ✅ | → N1 |

**Write:** none. **Open:** badge outstanding butuh agg asset_cache per client — {dev}.

> ⚠ **UPDATE (live-test 2026-06-29):** list customer **bukan** `displayStatisticCard` lagi — itu render BLANK (stat-card, gak ada renderer name-list). Diganti **`TASK_FEED_LIST` flat-mode** (LIVE row 1163). JSON resolved + perubahan renderer (`groupField` optional) = **`customer-namelist-and-creator-token-dev-spec.md` §1**. Tap row bawa `lv`→`{kl}` ke P2.

---

## §3. P2 — ItemBuilder (Step 2/4)

| # | elemen | widget | st | data/write |
|---|---|---|---|---|
| 1 | Header + customer strip | `workspaceHeader` | 🔶 | `stock_location` `ln`/pic by `{kl}` |
| 2 | Banner genesis-guard (amber+Seed) / outstanding-aware (violet) | `noticeBar` | ✅ | derived; Seed → S1 |
| 3 | **Item builder** | `taskItemBuilder` (mode order) | 🆕 | §1; read item+asset_cache; build `it[]` |
| 4 | Hint outstanding belum di-clear | `noticeBar` | ✅ | derived (cond) |
| 5 | Summary + "Lanjut · Pilih Kendaraan" | summary {dev} + `buttonRoute` | ✅ | → P3 |

**State carry:** `it[]` (in-progress) + `{kl}`/`{kn}`/`{al}` → P3/P4. Token nav (atau routeParams).

---

## §4. P3 — VehicleAssignment (Step 3/4) — reuse

> 📄 **Spec widget lengkap: `picker-list-widget-dev-spec.md`** (type `PICKER_LIST` — generic single-select picker, shared P3+H1, di-genericize dari VEHICLE_PICKER). App live skrg: "wrong widget name" (renderer belum ada).

| # | elemen | widget | st | data |
|---|---|---|---|---|
| 1 | Header | `workspaceHeader` | 🔶 | static |
| 2 | Context strip (customer · ↓drop ↑pickup) | `text` | ✅ | totals {dev} |
| 3 | Vehicle list (plat·type·status·taskCount·✓·ad-hoc) | `PICKER_LIST` (mode capture) | 🆕 | `stock_location` `lt=vehicle`; capture `{vv}`. **Spec `picker-list-widget-dev-spec.md`** |
| 4 | Doctrine note (assign kendaraan ≠ orang) | `noticeBar` | ✅ | static |
| 5 | "Lanjut · Review" | `buttonRoute` | ✅ | → P4 |

`PICKER_LIST` (mode capture) di-share dgn H1 (assign/reassign/jadwal). Di sini = capture `vv` buat task baru (belum nulis sampai P4 submit). **JSON resolved LIVE (row 1178) = `picker-list-widget-dev-spec.md` §7 Contoh A.**

---

## §5. P4 — TaskSummary (Step 4/4) — SUBMIT (write task)

| # | elemen | widget | st | data/write |
|---|---|---|---|---|
| 1 | Header | `workspaceHeader` | 🔶 | static |
| 2 | Customer card | compose | ✅ | `stock_location` read |
| 3 | Item list read-only (tx-aware + totals) | `taskManifestList` | 🔶 | render `it[]` in-progress |
| 4 | Vehicle card | compose | ✅ | `stock_location(vehicle)` read |
| 5 | Pickup breakdown (exchange + clearing) | `noticeBar` | ✅ | {dev} cond |
| 6 | "Setelah submit" | `noticeBar` | ✅ | static |
| 7 | **Submit "Buat Task & Assign"** | `sendButtonGpsWithEvent` (reuse base-lib, GANTI submitConfirmSheet) | 🔶 | addToEvent header + savesend renderer append `it[]` native (§5/§10) → P5 |

### Submit payload (task baru — grounded)
```
task (doc baru, key tnm):
  tnm  = {generated id}
  tty  = delivery | pickup_return
  tst  = assigned                    # langsung ke gudang, nunggu loading
  kl   = {kl}        kn = {kn}        # customer (stock_location client) + denorm name
  al   = {al}                          # address denorm
  vv   = {vv}                          # vehicle (stock_location vehicle) — TANPA driver
  gl   = {origin warehouse}            # OPEN: dari mana? (lihat §11)
  tdt  = {today}|{scheduled}           # epoch midnight
  cv   = {userVid}   cn = {userName}    # creator (session current-user — lihat customer-namelist-and-creator-token §2; BUKAN {adminVid})
  t    = {now}
  it[] = [ {ii,in,tx, pd,pp,cdo,cdi | ps,cdo | pb,cdi | pr,wt}, … ]   # NATIVE ARRAY
```
**Admin set `vv` + `cv/cn`; TIDAK set driver** (`dv` di-set Gudang). `cv-driver` ≠ `cv-creator` — `cv` di task = creator (lihat dict).

### Resolved target doc — JSON KONKRET (= bentuk akhir task doc: header via `sendButtonGpsWithEvent` addToEvent + `it[]` native-append)
Field code semua grounded ke config live P2 (`taskItemBuilder`: `ii/in/tx/pd/pp/ps/pb/pr/hg/cdo/cdi/wt`) + dict. Nilai `ii/in` = contoh (asli dari `//item`); `vv` dari P3 capture; `tdt` epoch midnight.
```json
{
  "tnm": "TSK-1782699404538-0001",
  "tty": "delivery",
  "tst": "assigned",
  "kl": "JBurL9Bpi2mjORSlwntZ",
  "kn": "Halooo",
  "al": "mantap",
  "vv": "<vehicle lv — P3 captureToken vv>",
  "gl": "<warehouse lv — OPEN §11>",
  "tdt": "1782604800000",
  "cv": "{userVid}",
  "cn": "{userName}",
  "t": "1782699404538",
  "ts": "29 Jun 2026 09:16:44",
  "it": [
    { "ii": "ITM-G19", "in": "Galon 19L RO", "tx": "deliver", "pd": 10, "pp": 10, "cdo": "penuh", "cdi": "kosong" },
    { "ii": "ITM-G19", "in": "Galon 19L RO", "tx": "sale", "ps": 2, "cdo": "penuh", "hg": 45000 }
  ]
}
```
⚠ **KEYSTONE (split):** submit pakai **`sendButtonGpsWithEvent`** (reuse base-lib row 192, bukan widget baru). Button `addToEvent` nulis **HEADER scalar** (`tty/tst/kl/kn/al/vv/tdt/cv/cn/t`) — itu jalan. TAPI **`it[]` = array, `addToEvent` GAK BISA nest array**. Jadi renderer `savesend` WAJIB **ALSO append draft `it[]` sbg native Firestore array** ke task doc yg sama (cap = custody `ip[]`/`dp[]`; solve sekali). `it` di JSON atas = hasil gabungan (header DSL + it[] native). Begitu doc lengkap ke-tulis (`tst:assigned`+`vv`+`it[]`), Gudang muat & Driver eksekusi (path warehouse→driver tested via seed). Token `{kl}/{kn}/{al}/{vv}` dari draft (butuh draft-carry); `{userVid}/{userName}` session; `{today}` system.

### JSON resolved — LIVE (op1Screen P4)
`taskManifestList` (row 1190) — render draft `it[]` read-only (tx-aware):
```json
{
  "type": "TASK_MANIFEST_LIST",
  "source": "draft",
  "itemsField": "it",
  "dropField": "pd",
  "pickupField": "pp",
  "txField": "tx",
  "saleField": "ps",
  "refillField": "pr",
  "buyField": "pb",
  "text": "Item Order◆item line◆drop◆pickup◆"
}
```
`sendButtonGpsWithEvent` (LIVE row 1190 — reuse base-lib row 192, GANTI submitConfirmSheet) — RBT `savesend` nulis task header + chain dialog → P5:
```json
{"type":"RBT","alignment":"spaceevenly","children":[{"text":"✓ Buat Task & Assign","action":"savesend","route":"vertikaTeknoLokaciptaCreateTaskSuccess","delay":5,"gpsPosition":"","flag":"task-create","addToEvent":"84214220504259//task⭘r◼4320⭘tablevid◼20342033315492⭘tty◼delivery⭘tst◼assigned⭘kl◼{kl}⭘kn◼{kn}⭘al◼{al}⭘vv◼{vv}⭘tdt◼{today}⭘cv◼{userVid}⭘cn◼{userName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","chain":{"type":"DO_DIALOG","title":"Task Dibuat","children":[{"type":"TXT","data":"Task masuk antrian Gudang · status assigned, nunggu loading"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaCreateTaskSuccess"}]}]}}]}
```
- `addToEvent` → task header scalar (jalan via DSL). **`it[]` TIDAK di sini** → renderer `savesend` append draft `it[]` native (keystone di atas).
- `taskManifestList` baca **draft state in-memory** (review read-only). `gpsPosition:""` = admin office, no GPS.

**Design (mockup `TaskSummaryScreen` L1595–2061):** render review sbg **kartu ringkasan menarik** (kartu customer · kartu items/manifest · kartu kendaraan · tombol submit besar) — JANGAN TXT polos `Customer: {kn}`. Renderer styling, samain mockup biar konsisten sama P1.

---

## §6. P5 — Success — reuse

`text`(taskId) + `noticeBar`(ok, ✓ Berhasil) + compose summary (customer/vehicle/drop/pickup) + `noticeBar`(info next) + `buttonRoute`×2 ("+ Buat Lagi" → reset H1/P1 · "Kembali ke Feed" → H1). **Full reuse.**

---

## §7. W1–W3 — Walk-in Counter (POS) — FINAL

Mockup final: `src/component/AdminCreateTaskIntegrated2.jsx` (walk-in di-update; sisanya = v1). Counter = **point-of-sale**: jual consumable + refill, **berharga**, bayar di tempat (LUNAS), **cetak nota**. 2 jalur: counter (selesai di tempat) / dikirim (jadi delivery task).

### 7.1 W1 Intake
| # | elemen | widget | st | data |
|---|---|---|---|---|
| 1 | Header | `workspaceHeader` | 🔶 | static |
| 2 | Toggle Dibawa-Langsung / Dikirim | `switch`/`choiceButtonGroup` | ✅ | `fulfillment` |
| 3 | refillBlocked hint (refill = counter only) | `noticeBar` | ✅ | cond |
| 4 | Pembeli nama (+alamat kalau dikirim) | `textField` | ✅ | buyer |
| 5 | Item list: consumable (qty + **harga**) · refill (water + qty) | `taskItemBuilder` walkin + **`getMoneyInput`** (harga) | 🆕 + ✅ | item + harga |
| 6 | + Produk / + Refill | `displayList` + `selectableGrid` | ✅ | katalog |
| 7 | Footer: {N} item · **total Rp** + proceed | summary {dev} + `buttonRoute` | ✅ | → W3 / P3 |

**Harga model (grounded ke v2):** harga = **atribut produk** (single source; editor = settings produk GLOBAL di luar fitur, READ-only). Per baris disimpan sbg **`hg`** (harga satuan — FIELD BARU di line; `pr` udah kepake plan_refill, §1.1). Default baris = harga katalog; **override per-baris boleh** (`getMoneyInput`) → "diubah · katalog {X} · reset". Total = Σ SALE (`hg × qty`). **Refill = harga terpisah (parkir)**. Line walk-in counter = bentuk sama (`ii`,`qt`,`hg`) tapi masuk **nota**, bukan `task.it[]` (counter = tanpa task; §11.9).

### 7.2 W3 Counter Success = Nota Penjualan
| # | elemen | widget | st |
|---|---|---|---|
| 1 | Header "Nota Penjualan" | `workspaceHeader`/`text` | ✅ |
| 2 | Metode bayar (Tunai / Transfer) | `switch`/`selectableGrid` | ✅ |
| 3 | **Nota thermal 80mm** (header depo · line item qty×harga · TOTAL · metode · cap LUNAS) | **Document Engine + template nota** | reuse (doc-engine) |
| 4 | Cetak Nota | **`printBluetooth`** | ✅ |
| 5 | Transaksi Baru | `buttonRoute` | ✅ |

**Counter = SELALU LUNAS** (bayar di tempat, tanpa piutang/saldo). Metode: tunai/transfer. **Nota = snapshot BEKU** — "harga & status bayar = fakta di nota ini, immutable".

### 7.3 Write
- **counter (W1→W3):** per baris SALE → movement `mt=SALE` (`fl={warehouse}`, `tl=null`, `ii`, `qt`, `er=ADMIN`, `t`) **+ record komersial beku** (harga jual, metode, LUNAS, total, no-nota) — **schema gap, lihat §11**. Refill → `mt=REFILL` (harga terpisah). Nota terbit (No.={id}). Stok turun via CF, **tanpa custody, tanpa task**.
- **dikirim (W1→P3→P4):** synthesize customer umum → task biasa (§5).

⚠ Harga/bayar/nota = **data komersial yang BELUM ada di schema** (dict gak punya price/payment/nota). Lihat §11.8–11.11.

---

## §8. N1–N2 — Customer Baru — reuse + write scalar

| page | elemen | widget | st |
|---|---|---|---|
| N1 | Header | `workspaceHeader` | 🔶 |
| N1 | Nama* | `textField` | ✅ |
| N1 | Tipe* (korporat/horeca/retail/rumah) | `selectableGrid` | ✅ |
| N1 | Alamat · PIC | `textField` ×2 | ✅ |
| N1 | Doctrine note (saldo 0 = verified) | `noticeBar` | ✅ |
| N1 | Lanjut · Review | `buttonRoute` | ✅ |
| N2 | Review card + code-preview | compose + `text` | ✅ |
| N2 | "Daftarkan & Lanjut" | `submitConfirmSheet`/`rbtCta` | 🔶 |

**Write (N2):** create `stock_location` (scalar doc) → **DSL OK** (`addToEvent`/`updateEventRow`):
```
stock_location (doc baru):
  lv = {generated} ; lt = client ; ln = {nama} ; al = {alamat} ; lst = active
```
→ nav P2 (customer kepilih, outstanding 0).
**Catatan:** mockup nampilin "GENESIS opening_qty 0 / seed_confidence verified" — **itu kosmetik**. Real: cukup create client; outstanding 0 = implisit (gak ada asset_cache row). Genesis qty-0 movement **opsional** (gak nambah info). `seed_confidence` BUKAN field.

---

## §9. S1–S3 — Seed Saldo Awal — write GENESIS movement

Detour dari P2 (client belum di-seed). Catat saldo awal customer (carryover buku lama).

| page | elemen | widget | st |
|---|---|---|---|
| S1 | Header + customer strip | `workspaceHeader` | 🔶 |
| S1 | Doctrine note (saldo = custody) | `noticeBar` | ✅ |
| S1 | Qty per kategori returnable (single-value stepper) | `stepper` ✅ (atau `taskItemBuilder` seed-skin) | ✅ |
| S1 | + Tambah Kategori (returnable only) | `selectableGrid` | ✅ |
| S1 | Total + Lanjut | `buttonRoute` | ✅ |
| S2 | occurred_at anchor + Doctrine | `datePicker` ✅ + `noticeBar` | ✅ |
| S2 | Basis (min 10, audit) | `textField` | ✅ |
| S3 | Review list + code-preview | `taskManifestList`/compose + `text` | 🔶 |
| S3 | Doctrine provisional + once-only | `noticeBar` ×2 | ✅ |
| S3 | "Catat & Kembali ke Item" | `submitConfirmSheet`/`rbtCta` | 🔶 |

**Write (S3):** per kategori → **`addToEvent` movement** `mt=GENESIS`:
```
movement (per baris):
  mt = GENESIS ; tl = {kl} (client) ; fl = null ; ii = {kategori} ; cd = {kondisi} ; qt = {saldo}
  er = ADMIN ; t = {occurred_at backdated} ; d = {basis}
```
CF derive `asset_cache(client)` → outstanding. **`provisional`/`verified` = mockup-only** (derived state, bukan field). occurred_at = backdated (S2 anchor), BUKAN today.

---

## §10. Write/DSL reference (ringkas)

| aksi | mekanisme | kenapa |
|---|---|---|
| **task create (P4)** | **NATIVE ARRAY write** | `it[]` array — DSL gak support (= custody `ip[]`/`dp[]`). Renderer rakit doc + native set |
| task reassign / set vv (H1 sheet) | `updateEventRow` scalar | `vv`/`tst` scalar |
| customer create (N2) | `addToEvent`/`updateEventRow` scalar | `stock_location` doc scalar |
| seed (S3) | `addToEvent` × N | `movement` GENESIS, 1 doc/kategori, sparse |
| walk-in counter (W3) | `addToEvent` × N | `movement` SALE/REFILL, no task |

Prefix: `84214220504259//{coll}⭘tablevid◼20342033315492⭘…`. Token: `{adminVid}`,`{adminName}`,`{today}`,`{kl}`,`{kn}`,`{al}`,`{vv}`. Detail DSL: `reference_driver_write_dsl` / `docs/2026-06-04-updateEventRow-design.md` + `docs/2026-06-01-addToEvent-design.md`.

---

## §11. Open / decisions
1. **`task.it[]` native array** — butuh capability yg sama dgn custody. Solve sekali, kebuka P4 + custody. **(blocker utama)**
2. **`gl` (origin warehouse)** task dari mana? single-warehouse default, atau Admin pilih? CONFIRM.
3. **`tty`** = `delivery` selalu, atau derive (pickup-only task = `pickup_return`)? CONFIRM.
4. ~~W1 jsx final HOLD~~ → **RESOLVED**: final = `AdminCreateTaskIntegrated2.jsx` (counter POS). §7 updated.
5. **N2 GENESIS qty-0** — skip (kosmetik) atau tetap tulis movement marker? rekomendasi skip.
6. **vehiclePicker** baru vs reuse `displayStatisticCard` keyed single-select — lihat H1 §6.
7. **Model B `cd`** — outstanding net dihitung per kondisi mana (empty owed)? confirm vs movement CF spec.
8. **Harga per baris = `hg` (FIELD BARU di `it[]`/line).** ⚠ User usul `pr` tapi `pr`=`plan_refill` (collision) → pakai **`hg`**. Default dari atribut produk (pricelist GLOBAL, editor luar fitur). CONFIRM: produk harga di `item.harga` atau pricelist collection terpisah? Tambah `hg` ke `it[]` di dict book.
9. **Nota / payment — COLLECTION BARU (REKOMENDASI gue).** Counter sale butuh record komersial **beku**. **Usul: collection `nota` terpisah** — BUKAN nempel di `movement` (movement = ledger fisik per-item, gak cocok multi-line + 1 payment). Pola mirror `task`(order)↔`movement`(fisik) → `nota`(komersial)↔`movement` SALE(fisik). PROPOSED shape (tech-lead/dict ratifikasi): `nota{ nv(id), kl/kn(pembeli/Umum), it[]{ii,in,qt,hg}, tot(total), bm(metode cash/transfer), bl(lunas), t, er=ADMIN, mrf(task ref opsional) }`. Movement SALE tetap (fisik); nota = SSOT komersial + cetak. **Semua kode di-PROPOSED, tech-lead finalize.**
10. **Nota render + cetak** = Document Engine (konsisten) + `printBluetooth`. Confirm template nota 80mm thermal di doc-engine.
11. **Refill harga terpisah (parkir)** — gimana dihitung & dicatat (bukan PRODUCT_CATALOG.harga)? OPEN.

---

## §12. Data deps
read: `item`(ii,in,ic,un,wt, **harga**) · `stock_location`(client+vehicle) · `asset_cache`(client, Model B) · `workforce`(admin) · pricelist (harga, schema TBD §11.8).
write: `task`(+it[] native) · `stock_location`(client) · `movement`(GENESIS/SALE/REFILL) · **nota/payment record (schema TBD §11.9)**.
CF-dep: `asset_cache` (outstanding/Model B) — `driver-runtime-movement-cf-handoff.md`.
doc-engine: nota 80mm thermal + `printBluetooth` (W3).
{dev}-computed: totals, Model B suggestion, outstanding agg, "belum di-seed" derive, summary breakdown, total Rp nota.
