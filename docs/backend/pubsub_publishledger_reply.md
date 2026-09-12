# Balasan Tim Mobile — Dev Spec `publishLedger` (jalur publish ke pub-sub-gateway)

**Status:** BALASAN tim mobile · 2026-09-11
**Untuk:** pemilik config otonomiq · tembusan: tim backend `pub-sub-gateway` (terutama §1, §2, §4, §6, §10)
**Menjawab:** `pubsub-publishledger-flutter-dev-spec.md` (PROPOSAL pemilik config, 2026-09-11)
**Acuan:** `pubsub_gateway_integration_spec.md` (draft kami), `FLUTTER.md`

---

Kami sudah mencocokkan setiap keputusan di spec dengan kode otonomiq. Sebagian
besar kami setujui apa adanya, dan satu penyederhanaan — semua nilai string,
koersi tipe di gateway — langsung kami ambil. Ada satu premis yang perlu
dikoreksi karena menjadi dasar K5 dan §4 spec kembar (lihat §1). Rujukan file
(`lib/...`) disertakan supaya bisa dicek ulang.

## 0. Ringkasan jawaban

| # | Butir | Jawaban kami | Detail |
|---|---|---|---|
| K1 | Key `publishLedger`, format satu baris | **Setuju — final**, dengan dua aturan reserved | §3 |
| K2 | App menyuntik `actionAt` | **Setuju.** Nilai = waktu record antrean (NTP), string epoch ms | §3 |
| K3 | Status gagal terkirim wajib | **Setuju prinsipnya.** Kontrak minimumnya perlu dilengkapi | §4 |
| K4 | Antrean lama tidak disentuh | **Setuju**, dengan tafsiran: perilaku tidak berubah, kode tetap ditambah | §5 |
| K5 | Supersede `addToEvent` | **Usul alternatif** — premisnya keliru dan ada 4 efek samping | §1, §2 |
| O1 | Key & format final? | **Final** dari sisi mobile | §3 |
| O2 | Supersede — setuju? | **Tidak; usul tautan lewat Idempotency-Key** | §2 |
| O3 | Bentuk & path dokumen status | Milik backend; kebutuhan sisi app ada di §4 | §4 |
| O4 | `requestRef` = Idempotency-Key submit | **Setuju**, dengan 3 syarat | §6 |

Tambahan: `photo` (§7), `WORKFLOW_BTN` (§8), `ledgerCode` (§9), catatan untuk
backend (§10).

---

## 1. Koreksi premis: dari mana tab Event diisi

Spec §5 dan artifact "Alur visual v2" (tahap 4c) menganggap baris tab Event dan
laporan (kolom D) berasal dari `addToEvent`, sehingga request yang pindah ke
jalur gateway akan hilang dari laporan kecuali ada konsumen yang menulis Event.
Di kode otonomiq alurnya berbeda:

1. **Setiap** submit lewat `saveSend` menjadi satu record di antrean lokal. Saat
   sinkron, `historySync` menulis dokumen `Proxy/{ssid}/Event/{doc}` berisi
   waktu, halaman, dan isi mentah record itu — untuk semua record, dengan atau
   tanpa `addToEvent` (`lib/firestore_repository/table_repository.dart:3106-3121`,
   `:3328`). Dokumen inilah sumber baris tab Event; kolom D dihasilkan backend
   (`processEvent2`).
2. `addToEvent` hanya menulis **dokumen keyed tambahan** di Firestore — salinan
   kolom A–C plus field dari DSL — di samping baris tab Event yang tetap ada
   (`docs/firestore/add_to_event.md:3-5`, `:34-41`).

Konsekuensinya:

- Men-skip `addToEvent` **tidak** menghilangkan baris tab Event; build baru tetap
  mengirimnya lewat antrean.
- Konsumen backend yang ikut menulis baris tab Event akan membuat **baris dobel**
  untuk setiap aksi dari build baru.
- Yang benar-benar hilang bila `addToEvent` di-skip: dokumen keyed-nya dan push
  notifikasi (§2.1).

Kode `processEvent2` ada di backend dan tidak bisa kami baca. Mohon tim backend
mengonfirmasi bahwa penulis tab Event membaca `Proxy/{ssid}/Event`.

---

## 2. K5 / O2 — usulan alternatif: tautan lewat Idempotency-Key

### 2.1 Efek samping supersede

1. **Push notifikasi hilang.** Prop `notification` pada tombol
   (`ntf`/`nm`/`dp`/`bcc`) hanya dirangkai di dalam `addToEvent`
   (`lib/api.dart:5110-5125`), dan `ntf` inilah yang memicu Cloud Function
   `onEventCreated` (`docs/firestore/add_to_event.md:49-52`). Skip `addToEvent`
   berarti atasan/HR tidak menerima notifikasi.
2. **`updateEventRow` jadi no-match.** Config lain yang mencari atau memperbarui
   dokumen hasil `addToEvent` tidak akan menemukan dokumen untuk request dari
   build baru. Hasil no-match dihitung "selesai", hanya dilaporkan ke
   Crashlytics, dan tidak dicoba ulang
   (`lib/firestore_repository/table_repository.dart:3155-3182`) — update approval
   bisa hilang tanpa terlihat. Selain itu dokumen buatan konsumen tiba
   asinkron, tidak sejalan dengan urutan antrean.
3. **Konsumen tidak bisa membuat padanan yang sama persis.** Dokumen
   `addToEvent` memuat kode field dari DSL plus `et`/`p`/`ev`; `ev` adalah isi
   mentah record antrean (`docs/firestore/add_to_event.md:35-38`) yang tidak ikut
   di message gateway. Layar atau config yang membaca field itu akan berbeda
   perilaku.
4. **Ketergantungan urutan rilis.** Konsumen harus hidup sebelum layar pertama
   dinyalakan (spec §5 sudah menyebutnya).

### 2.2 Usulan

- Build baru tetap menjalankan `addToEvent` persis seperti build lama.
- Bila tombol yang sama juga punya `publishLedger`, app menambahkan field
  **`idempotencyKey`** ke dokumen `addToEvent` — nilainya sama dengan header
  `Idempotency-Key` message. Config tidak perlu menulis apa pun.
- Konsumen **tidak** menulis dokumen event dan **tidak** menulis tab Event.
  Tugasnya memproses message (approval, expansion) dan menulis status/hasil ke
  dokumen status (Q3) ber-ID `idempotencyKey`. Bila perlu memperbarui dokumen
  event, dokumen itu dicari lewat field `idempotencyKey`.

| Build | Dokumen keyed + push | Message gateway | Baris tab Event |
|---|---|---|---|
| lama | dari `addToEvent` | tidak ada | 1 (dari antrean) |
| baru | dari `addToEvent`, + field `idempotencyKey` | 1 | 1 (dari antrean) |

Hasilnya: tidak ada dobel di mana pun, push tetap jalan, `updateEventRow` utuh,
tab Event tidak berubah, dan layar bisa dinyalakan tanpa menunggu konsumen
penulis event hidup.

**Harganya:** dokumen event tetap ditulis oleh app (dipercaya dari klien, sama
seperti hari ini), bukan hasil validasi gateway. Data yang divalidasi gateway
tetap menjadi dasar keputusan konsumen.

Bila owner tetap memilih K5, lima syarat berikut perlu masuk spec konsumen:

1. Konsumen menulis dokumen dengan koleksi dan kode field yang sama dengan
   `addToEvent`, dan menerima bahwa `ev` tidak tersedia.
2. Konsumen mengambil alih push notifikasi.
3. Semua config `updateEventRow` yang menarget dokumen itu diaudit.
4. Konsumen hidup sebelum saklar pertama dinyalakan.
5. Konsumen tidak menulis tab Event.

---

## 3. K1, O1, K2 — format final dan `actionAt`

**K1 / O1 — final.** Format berikut kami kunci:

```
<ledgerCode>⭘_v◼<schemaVersion>⭘<field>◼<nilai>⭘<field>◼<nilai>…
```

Parser yang dipakai sama dengan `addToEvent`
(`lib/firestore_repository/add_to_event.dart:7`). Dua aturan tambahan:

- Key berawalan `_` adalah meta dan tidak masuk `data`. `_v` = `schemaVersion`;
  `_k` dibuat app. Key `_` lain yang tidak dikenal diabaikan.
- `actionAt` adalah key milik app: kalau config menuliskannya, nilainya ditimpa.

**K2 — setuju.** `actionAt` diisi dari waktu record antrean, yaitu hasil
`getRealTime()` saat tombol ditekan: waktu NTP bila online, jam device plus
koreksi GPS bila offline (`lib/api.dart:5508-5517`). Dua keuntungan: lebih
akurat daripada jam device mentah, dan nilainya sama persis dengan waktu
dokumen Event di tab Event, sehingga konsumen bisa mencocokkan keduanya.
Formatnya string epoch milidetik, sesuai K1.

Konsekuensi "semua nilai string": rencana dukungan tipe di app kami batalkan;
koersi dilakukan gateway (lihat §10).

---

## 4. K3 — status gagal terkirim: yang perlu dilengkapi

Kami setuju app wajib menulis status gagal: message yang ditolak `4xx` tidak
pernah sampai ke konsumen, sehingga hanya app yang tahu. Supaya bisa dibangun,
kontraknya perlu dilengkapi:

1. **Lokasi tulis per ledger.** App perlu tahu `{vid}` dan nama tabel untuk
   setiap ledger. Pilihannya: konvensi tetap yang ditetapkan di Q3, atau meta di
   config (misalnya `_s◼<nama tabel>`). Mohon diputuskan.
2. **Bentuk dokumen = bentuk dokumen sukses.** Isi minimum di spec
   (`idempotencyKey`, `ledgerCode`, `errorId`, `error`, `status`, `actionAt`)
   belum cukup untuk layar. Perlu ditambah:
   - field pemilik (sama dengan yang ditulis konsumen di dokumen sukses), supaya
     layar bisa memfilter "ajuan saya";
   - ringkasan request (isi `data`), supaya user tahu ajuan mana yang gagal.
3. **ID dokumen = `idempotencyKey`**, untuk dokumen sukses maupun gagal — satu
   request menjadi satu baris, dan penulisan ulang aman.
4. **Hak tulis.** Rules Firestore harus mengizinkan app menulis dokumen status
   gagal di path tersebut.
5. **Urutan.** Entry baru dihapus dari outbox setelah penulisan status gagal
   berhasil. Kalau penulisan itu sendiri gagal, entry tetap disimpan dan dicoba
   lagi di siklus berikutnya.
6. **Jalur hilang yang tidak tertutup K3** — mohon keputusan per butir:
   - **Logout** menghapus antrean lokal (`lib/api.dart:3566`), termasuk ajuan
     yang belum terkirim. Usulan kami: peringatan sebelum logout bila masih ada
     ajuan yang belum terkirim. Ini tidak mengubah perilaku antrean, jadi K4
     tetap terjaga.
   - **Foto yang gagal di-upload** diganti gambar placeholder oleh antrean lama —
     lihat §7.
   - **Message berumur lebih dari 24 jam yang hasilnya tidak diketahui** (pernah
     timeout). Kalau konsumen melakukan dedupe dengan Idempotency-Key (Q5 spec
     kami, Titik 3 review), message itu tetap kami kirim.

---

## 5. K4 — tafsiran "antrean lama tidak disentuh"

Kami setuju perilaku antrean lama tidak berubah. Supaya jelas: kodenya tetap
mendapat tambahan, karena `publishLedger` menumpang di record antrean sampai
gambar selesai di-upload.

- `saveSend` merangkai `publishLedger` sebagai segmen tambahan di record
  antrean.
- `historySync` memindahkan segmen itu ke outbox saat record pertama kali
  diproses, **tanpa** ikut dihitung dalam hasil ok/gagal segmen lain.

Perilaku drop, retry, partial, dan give-up untuk `addToTable`,
`updateTableRow`, `deleteFromTable`, `addToEvent`, dan `updateEventRow` tidak
berubah. Publish juga tidak terkena drop-setelah-5-siklus, karena sudah dipindah
ke outbox pada pemrosesan pertama. Mohon konfirmasi tafsiran ini.

Koreksi kecil: drop-setelah-5-siklus di antrean lama dilaporkan lewat
`errorReport` ke Crashlytics, bukan hanya `devPrint`
(`lib/firestore_repository/table_repository.dart:3303`).

---

## 6. O4 — `requestRef`

Setuju: nilai `requestRef` adalah Idempotency-Key message submit. Tiga syarat:

1. **Tombol approve harus berupa child RBT dengan `"action": "savesend"`.**
   Rantai approval yang dipicu `actions` berjalan sesudahnya dan membuat event
   tanpa DSL sama sekali (`lib/widget/ftz_row_of_button_2.dart:1271-1286`;
   `createApprovalEvent` mengirim `tableString: null`, `lib/api.dart:5313-5324`).
   `publishLedger` yang hanya bergantung pada jalur itu tidak akan pernah
   terkirim.
2. **Nilainya harus berasal dari dokumen yang sedang dibuka.** Nilai yang dibawa
   lewat `routeParams` disimpan di state layar yang tidak dibersihkan saat pindah
   layar. Kalau satu list lupa mengirim key, tombol approve membawa `requestRef`
   milik request **sebelumnya**. Config wajib selalu mengirim key dari baris yang
   ditap, dan konsumen wajib memeriksa hak approver serta status request — jangan
   percaya `requestRef` begitu saja.
3. **Key sampai ke approver hanya lewat dokumen hasil konsumen.** App pengaju
   tidak menyimpan key setelah `202`, dan approver memakai device lain. Dokumen
   status (Q3) wajib menyimpan `idempotencyKey`.

`requestRef` perlu masuk kontrak Q1 untuk setiap ledger yang punya aksi
lanjutan.

---

## 7. `photo` — path Storage

Setuju memakai path Storage, bukan download URL bertoken. Detail dari sisi app:

- **Format `gs://<bucket>/<path>`**, bukan path tanpa bucket. Bucket upload
  memang tunggal hari ini (`gs://otq-01-ase2`, hardcode yang ditandai untuk
  dipindah, `lib/api.dart:4771`), tetapi gambar placeholder app ada di bucket
  project lain (`collanium1-4babc.appspot.com`, `lib/global.dart:552`).
- **Tanpa config tambahan.** App menyimpan download URL
  (`lib/firestore_repository/firestore_generic_repository.dart:37-38`). Saat
  membangun payload, setiap download URL Firebase Storage di dalam nilai field
  diubah ke bentuk `gs://`. Slot yang berisi beberapa foto tetap memakai
  pemisah yang sudah ada (misalnya `◇`, `lib/widget/ftz_display_images.dart:107`)
  — mohon pemisah ini dicatat di kontrak Q1.
- **Foto yang hilang tidak boleh terkirim sebagai placeholder.** Antrean lama
  mengganti foto yang gagal di-upload dengan gambar placeholder
  (`lib/firestore_repository/table_repository.dart:3028-3046`). Usulan kami:
  nilai placeholder dikirim sebagai string kosong dan dilaporkan ke Crashlytics.
  Kalau foto wajib menurut skema, gateway akan menolaknya (`4xx`) dan K3
  menampilkan status gagal ke user.
- Minor: contoh config di §1 spec tidak memuat `photo◼◁N▷`, tetapi contoh
  request di §3 memuatnya.

---

## 8. `WORKFLOW_BTN`

Tipe `WORKFLOW_BTN` tidak ada di app. Dispatch mengenal `rbt`
(`lib/widget/build_display_component.dart:591`) dan `selectable_btn` (`:1054`),
dan `publishLedger` hanya dibaca lewat child RBT dengan `"action": "savesend"`
(`lib/widget/ftz_row_of_button_2.dart:678`, `:719`). Kalau `WORKFLOW_BTN` adalah
nama template di tab `Widget!`, pastikan hasil ekspansinya berbentuk seperti
itu. Mohon kirim satu contoh JSON hasil ekspansi untuk uji kami.

---

## 9. `ledgerCode` — §6 vs K1

§6 melarang `ledgerCode` di-resolve dari sumber yang bisa diedit saat runtime,
sementara K1 menaruhnya di config sheet. Tafsiran kami: `ledgerCode` wajib
**literal** di config, tanpa token `◁N▷`, `{…}`, atau `<…>`. App memvalidasinya
dengan `^[A-Z0-9]{4,16}$` sebelum masuk outbox; yang tidak valid tidak dikirim
dan diperlakukan sama dengan `4xx` (status gagal ditulis dan dilaporkan ke
Crashlytics). Mohon konfirmasi.

---

## 10. Catatan untuk tim backend

1. **Penulis tab Event** — lihat §1. Kalau yang dimaksud adalah penulis baris tab
   Event, jangan dibangun: baris itu sudah datang dari antrean app untuk setiap
   aksi.
2. **Koersi tipe di gateway** bertentangan dengan `FLUTTER.md` §6 ("gateway
   meneruskan byte `data` apa adanya"). Mohon `FLUTTER.md` diperbarui. Sidik jari
   idempotency harus tetap dihitung dari byte mentah **sebelum** koersi, supaya
   retry yang byte-identik tetap dijawab `duplicate: true`.
3. **Spec kembar** `pubsub-gateway-backend-dev-spec.md` belum kami terima. Bagian
   §2.3, §4, dan §5 yang dirujuk spec ini belum bisa kami cek.

---

## 11. Yang masih kami tunggu sebelum mulai

| Butir | Pemilik |
|---|---|
| Kontrak Q1 final: field, `actionAt`, `requestRef`, pemisah multi-foto | backend + pemilik ledger |
| Q3: path dan bentuk dokumen status, rules tulis app, sumber `{vid}`/tabel | backend |
| Keputusan O2: alternatif §2, atau K5 dengan lima syarat | pemilik config |
| Keputusan §4 butir 6 (logout, foto hilang, message > 24 jam) | pemilik config |
| Konfirmasi tafsiran K4 (§5) dan `ledgerCode` (§9) | pemilik config |
| Contoh JSON hasil ekspansi `WORKFLOW_BTN` (§8) | pemilik config |
| Spec kembar | backend |

Setelah butir-butir ini terjawab, kami memperbarui
`pubsub_gateway_integration_spec.md` dan mulai membangun: parser
`publishLedger`, outbox, suntikan `actionAt`, konversi path foto, dan penulis
status gagal.
