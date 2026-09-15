# Integrasi otonomiq × pub-sub-gateway — Rencana Mobile & Kebutuhan dari Backend

**Status:** DRAFT rev 3 · fase 1 sudah diimplementasi di app (belum dirilis) · menunggu jawaban §5
**Untuk:** tim backend `pub-sub-gateway` dan pemilik ledger `WFREQLAP` / `WFREQLEX`
**Dari:** tim mobile `otonomiq`
**Tanggal:** 2026-09-11 · rev 2 & rev 3: 2026-09-14
**Acuan:** `FLUTTER_v2.md` (2026-09-14) · `pubsub-publishledger-flutter-dev-spec.md` (proposal pemilik config) · `pubsub_publishledger_reply.md` (balasan kami atas proposal itu)

---

## Riwayat revisi

| Rev | Tanggal | Perubahan |
|---|---|---|
| 1 | 2026-09-11 | Draft pertama |
| 2 | 2026-09-14 | Menyerap `FLUTTER_v2.md` (ledger uji `TESTMOBILE`) dan keputusan pemilik config: format `publishLedger` final, semua nilai string, `actionAt` disuntik app, status gagal wajib ditulis app, referensi foto berupa path Storage. Menambah status per pertanyaan (§5), Q14 (penulis tab Event), dan strategi uji (§6.1) |
| 3 | 2026-09-14 | URL gateway ditemukan dan dipasang sebagai default di app (§2.3, Q8, §6.1, §7); status fase 1 (sudah diimplementasi, belum dirilis); §6 disesuaikan |

---

## Ringkasan

Kami sudah mempelajari `FLUTTER.md` (kini v2) dan akan mengikuti kontraknya:
header, `Idempotency-Key`, tabel keputusan retry, dan App Check. Dokumen ini
menjelaskan bagaimana kontrak itu dipasang di otonomiq, apa dampaknya ke gateway
dan konsumen, dan apa yang kami butuhkan sebelum mulai.

Tiga hal terpenting:

1. **Publish bisa tertunda.** otonomiq offline-first: aksi user masuk antrean di
   device lebih dulu dan baru di-publish saat online — bisa berjam-jam atau
   berhari-hari kemudian. Setiap retry memakai `Idempotency-Key` dan body yang
   sama.
2. **Bentuk payload diatur konfigurasi, bukan kode.** Layar dan aksi otonomiq
   didefinisikan lewat konfigurasi (server-driven UI dari Google Sheets). Mapping
   field ke `data` juga ada di konfigurasi, dan semua nilainya string. Perubahan
   skema cukup dengan mengubah konfigurasi, tanpa rilis app, selama konversi
   tipe dilakukan gateway (§3 butir 7).
3. **Yang menghambat rilis ke produksi:** kontrak payload (Q1), konteks tenant
   (Q2), path dan bentuk dokumen status (Q3), pemilik ledger (Q13), dan
   keputusan masa transisi dua jalur (Q9). Pengiriman fase 1 sudah dibangun di
   app dan ledger uji sudah tersedia (`TESTMOBILE`). URL gateway kami temukan
   sendiri dan sudah dipasang di app — mohon konfirmasi (Q8); gateway dev
   terpisah masih kami tanyakan (Q7).

---

## 1. Konteks otonomiq

**Server-driven UI.** Layar tidak ditulis di kode Dart, melainkan dikirim
sebagai JSON yang disusun di Google Sheets. Keputusan "tombol ini mem-publish ke
ledger X dengan field Y" adalah konfigurasi per layar.

**Offline-first.** Setiap submit masuk antrean lokal yang tersimpan di device,
lalu dikirim saat online. Antrean ini sudah dipakai untuk penulisan data ke
Firestore, termasuk meng-upload gambar ke Firebase Storage sebelum datanya
dikirim. Aksi yang belum terkirim tidak dibuang karena umur; antrean hanya
dikosongkan saat user logout.

**White-label, satu project Firebase.** Satu codebase dirilis sebagai beberapa
app, semuanya di project Firebase `otq-01` — aturan "token hanya dari `otq-01`"
aman untuk semua brand:

| Platform | App ID |
|---|---|
| Android | `com.agenia.mobile` |
| Android | `com.autsorz.mobile` |
| Android | `com.otonomiq.master1` |
| Android | `com.schania.mobile` |
| Android | `com.vertika.autsorz` |
| iOS | `com.otonomiq.master1` |

**Identitas.** Login lewat Firebase Auth `otq-01` (nomor telepon, Google,
Apple). App tidak memakai anonymous auth, jadi publish hanya terjadi dari user
yang login dan `subject` selalu UID user sungguhan. Satu device bisa dipakai
bergantian oleh beberapa user.

---

## 2. Rancangan di sisi mobile

### 2.1 Alur

```
User menekan tombol submit
   │  Idempotency-Key (UUID v4) dibuat saat itu dan disimpan bersama aksi
   ▼
Antrean lokal (tersimpan di device; tahan app ditutup dan offline)
   │  saat online: gambar di-upload ke Firebase Storage lebih dulu
   ▼
Payload dibangun (termasuk actionAt) dan di-encode SEKALI, lalu disimpan di outbox publish
   ▼
Outbox dikirim tiap ±1 menit, sesaat setelah submit, dan saat koneksi pulih
   ▼
POST {GATEWAY_URL}/v1/ledgers/{ledgerCode}/messages
   ├─ 202       → entry dihapus
   ├─ 4xx       → fase 1: entry ditandai failed (disimpan 30 hari)
   │              fase 2: status gagal ditulis ke Firestore (path Q3), lalu entry dihapus
   └─ 5xx/putus → entry disimpan, dicoba lagi di siklus berikutnya
```

Outbox publish sengaja dipisah dari antrean yang sudah ada. Antrean lama
dirancang untuk penulisan Firestore yang tidak idempoten, sehingga menyerah
setelah beberapa kali gagal; gateway idempoten dan meminta retry sampai
berhasil. Dengan dipisah, gangguan gateway tidak menahan data lain, dan
kegagalan data lain tidak ikut membuang message.

Perilaku antrean lama tidak berubah (keputusan pemilik config): segmen publish
hanya menumpang sampai gambar ter-upload, lalu dipindahkan ke outbox saat record
pertama kali diproses, tanpa ikut dihitung dalam hasil ok/gagal penulisan lain.

### 2.2 Contoh konfigurasi

Format ini sudah disepakati final dengan pemilik config. Tim konfigurasi
menambahkan satu entri di tombol submit:

```
"publishLedger": "WFREQLAP⭘_v◼1⭘requestType◼leave⭘days◼◁3▷"
```

Artinya: ledger `WFREQLAP`, `schemaVersion` 1, field `requestType` bernilai
literal `leave`, dan field `days` diambil dari isian form nomor 3. App
menghasilkan:

```json
{
  "schemaVersion": 1,
  "data": { "requestType": "leave", "days": "2", "actionAt": "1789101600000" }
}
```

- `"days": "2"` bertipe **string**: semua nilai dikirim sebagai string, dan app
  tidak mengonversi tipe. Menurut pemilik config, konversi dilakukan gateway
  berdasarkan skema (§3 butir 7).
- `actionAt` disuntik app, tidak ditulis di konfigurasi (§2.3).

### 2.3 Perilaku klien

| Situasi | Perilaku app |
|---|---|
| `Idempotency-Key` | UUID v4, dibuat saat tombol ditekan; dipakai untuk semua percobaan, termasuk setelah app ditutup lalu dibuka lagi |
| Body | Di-encode sekali setelah gambar ter-upload dan sebelum percobaan pertama, lalu disimpan sebagai string; setiap percobaan mengirim byte yang sama |
| Nilai `data` | Semua string, format datar (tanpa objek bertingkat atau array) |
| `actionAt` | Disuntik app ke `data`: waktu record antrean saat tombol ditekan (waktu NTP bila online, jam device dengan koreksi GPS bila offline), string epoch milidetik. Nilai `actionAt` dari konfigurasi ditimpa |
| `ledgerCode` | Wajib literal di konfigurasi dan cocok `^[A-Z0-9]{4,16}$`. Yang tidak valid tidak dikirim dan diperlakukan seperti `4xx` |
| `202`, termasuk `duplicate: true` | Selesai; dihapus dari outbox |
| `400`, `404`, `405`, `409`, `413`, `422` | Tidak di-retry. **Fase 1 (sudah dibangun):** entry ditandai `failed`, disimpan 30 hari, tidak dikirim ulang. **Fase 2 (setelah Q3):** app menulis dokumen status gagal ke path yang sama dengan status sukses (path Q3, ID dokumen = `Idempotency-Key`); entry baru dihapus dari outbox setelah dokumen itu tertulis. `errorId`, `error`, dan `ledgerCode` dicatat ke Crashlytics tanpa isi payload. Termasuk `404 ledger_not_found` akibat salah ketik `ledgerCode` di konfigurasi |
| `401` | Refresh token paksa sekali. Kalau masih `401`, message disimpan sampai user login ulang; app **tidak** logout otomatis dari proses latar belakang |
| `500`, `503`, timeout, koneksi putus | Disimpan dan dicoba lagi di siklus berikutnya (±1 menit), atau setelah `Retry-After` |
| Frekuensi | Satu percobaan per message per siklus; tidak ada retry beruntun di dalam satu siklus |
| Pergantian user | Message terikat ke UID pembuatnya dan hanya dikirim saat UID itu yang login. Logout menghapus antrean lokal; usulan peringatan sebelum logout bila masih ada ajuan belum terkirim menunggu keputusan pemilik config |
| Lewat 24 jam | App mencatat "sudah pernah dikirim ke jaringan" **sebelum** POST. Message yang belum pernah dikirim tetap aman walau sudah lewat 24 jam, karena belum mungkin ada terbitan pertama. Hanya message yang pernah timeout lalu lewat 24 jam yang berisiko ganda — lihat Q5 |
| Header | `X-Client-Source: mobile`; `X-Firebase-AppCheck` setelah App Check dipasang (§4) |
| `GATEWAY_URL` | Di-compile ke dalam app dengan default `https://pub-sub-gateway-721538991284.asia-southeast2.run.app` (Q8), sehingga build tanpa flag langsung mengirim. `--dart-define=GATEWAY_URL=…` menimpanya (misalnya untuk gateway lokal), dan nilai kosong mematikan fitur. Sengaja **tidak** bisa diubah dari konfigurasi sheet: request membawa ID token, jadi URL yang bisa diedit dari sheet memungkinkan siapa pun yang punya akses edit membelokkan token ke server lain |
| File dan gambar | Tidak pernah masuk body. Gambar di-upload ke Firebase Storage; payload membawa path `gs://<bucket>/<path>` yang diturunkan dari download URL (Q6). Foto yang gagal di-upload dan diganti gambar placeholder dikirim sebagai string kosong |
| Endpoint pendukung | App tidak memanggil `GET /v1/ledgers`, `/schema`, atau `/livez` di runtime |

Tombol submit tidak menunggu respons gateway; tampilan mengikuti pola
offline-first yang sudah ada. Karena penolakan `4xx` terjadi di latar belakang,
app menulis status gagal ke Firestore supaya penolakan itu terlihat di layar
yang sama dengan status sukses.

---

## 3. Dampak ke gateway dan konsumen

1. **`publishedAt` bukan waktu aksi.** Selisihnya bisa berjam-jam hingga
   berhari-hari. Waktu aksi dibawa di `data.actionAt` (§2.3).
2. **Lonjakan setelah gangguan.** Saat gateway pulih, atau banyak device kembali
   online bersamaan, antrean yang menumpuk terkirim berdekatan. Kami menghormati
   `Retry-After`; silakan dipakai untuk meredam.
3. **Versi skema di antrean tidak berubah.** Payload dibekukan dengan
   `schemaVersion` saat aksi dibuat. Setelah versi baru dirilis, message versi
   lama masih bisa datang lama sesudahnya, jadi mohon versi lama tetap diterima
   sebagai `deprecated` cukup lama (Q11). Kalau ledger di-`disabled`, message
   yang masih antre akan kami buang karena `404` tidak di-retry.
4. **Duplikat di luar 24 jam mungkin terjadi**, walau jarang — kasus timeout di
   §2.3. Dedupe di konsumen memakai `Idempotency-Key` akan menutup celah ini
   (Q5).
5. **Urutan tidak dijamin.** Outbox di satu device berurutan, tapi retry dan
   banyaknya device bisa mengacak urutan kedatangan.
6. **Masa transisi.** Build app lama tidak mengenal konfigurasi publish,
   sehingga user yang belum update tidak mem-publish apa pun. Selama adopsi,
   Pub/Sub belum menjadi sumber yang lengkap. Cara menghindari dobel dengan
   jalur `addToEvent` yang sudah ada masih diputuskan (Q9).
7. **Tipe data.** Semua nilai dikirim sebagai string dan format konfigurasi
   datar. Pemilik config memutuskan konversi tipe menjadi tanggung jawab
   gateway. Dua hal perlu diselaraskan di sisi gateway:
   - `FLUTTER.md` §6 (masih sama di v2) menyebut gateway meneruskan byte `data`
     apa adanya — mohon diperbarui;
   - sidik jari idempotency tetap dihitung dari byte mentah **sebelum**
     konversi, supaya retry yang byte-identik tetap dijawab `duplicate: true`.
8. **Tab Event sudah terisi dari antrean app.** Setiap submit menghasilkan
   dokumen `Proxy/{ssid}/Event` lewat antrean, dengan atau tanpa `addToEvent`,
   dan dokumen itulah sumber baris tab Event. Konsumen yang ikut menulis baris
   tab Event akan membuat baris dobel (Q14).

---

## 4. Rencana App Check

- Kami akan menambahkan `firebase_app_check`: Play Integrity untuk Android, App
  Attest untuk iOS, dan debug provider untuk build debug.
- Mohon keenam app di §1 didaftarkan di Firebase Console → App Check. Setelah
  `enforce`, app yang belum terdaftar akan mendapat `401` untuk semua publish.
- Build yang dipasang di luar Google Play (APK langsung) kemungkinan tidak lolos
  Play Integrity. Kalau distribusi seperti itu ada, perlu dibahas sebelum
  `enforce`.
- Kami akan mengirim debug token untuk device QA dan emulator saat mulai uji.
- Mohon `enforce` baru dinyalakan setelah cakupan `appCheck: ok` memadai untuk
  **semua** app di atas, bukan hanya app utama. Kami akan mengabari saat build
  ber-App Check dirilis untuk tiap app.

---

## 5. Pertanyaan dan permintaan

**[blocking]** berarti kami tidak bisa mulai (atau tidak bisa rilis) tanpa
jawabannya. Status per 2026-09-14: **terbuka**, **sebagian**, atau
**diputuskan** (sudah ada keputusan, tinggal konfirmasi atau masuk kontrak).

### Q1. Kontrak payload `WFREQLAP` dan `WFREQLEX` — [blocking]

**Status: terbuka** — `FLUTTER_v2.md` masih memakai skema placeholder.

- Mohon daftar field, tipe, status wajib/opsional, dan contoh payload untuk
  masing-masing ledger.
- Apakah skema asli akan menggantikan `v1` (placeholder) di tempat, atau
  dirilis sebagai `v2`? Kami usul **`v2`**, supaya message yang sudah terbit
  dengan placeholder `v1` tetap bisa dibedakan.
- Kontrak perlu memuat:
  - `actionAt` sebagai field wajib semua ledger (string epoch milidetik,
    disuntik app — Q4);
  - `requestRef` untuk ledger yang punya aksi lanjutan, bernilai
    `Idempotency-Key` message submit asalnya;
  - pemisah untuk nilai yang berisi beberapa foto (Q6).
- Payload datar, semua nilai string (§3 butir 7).

### Q2. Konteks tenant — [blocking]

**Status: terbuka.**

otonomiq multi-tenant, dan UID saja belum tentu cukup untuk menentukan tenant
pengirim. Apakah konsumen butuh tenant di `data`? Apa nama dan format
field-nya? Usulan kami, yang juga disetujui pemilik config: `vid` bertipe
string.

### Q3. Hasil pemrosesan dan korelasi — [blocking]

**Status: sebagian** — status gagal sudah diputuskan wajib ditulis app;
path dan bentuk dokumen belum.

- `202` hanya berarti terbit. Layar otonomiq membaca Firestore, jadi status
  request (diproses, disetujui, ditolak) hanya bisa tampil kalau konsumen
  menulis hasilnya ke Firestore. Di path mana, dan seperti apa bentuk
  dokumennya? Kalau ditulis ke struktur yang sudah dipakai app
  (`MobileTable/{vid}/tables/{name}/content/{id}`), status bisa tampil tanpa
  rilis app.
- Korelasi: satu-satunya id yang **pasti** dimiliki app adalah
  `Idempotency-Key`, karena dibuat saat tombol ditekan. `messageId` bisa tidak
  pernah sampai ke app kalau respons `202` hilang di jaringan. Mohon dokumen
  hasil menyimpan `Idempotency-Key`.
- App menulis dokumen status gagal untuk setiap penolakan `4xx`. Supaya bisa
  dibangun, kami butuh:
  - bentuk dokumen gagal = bentuk dokumen sukses (termasuk field pemilik dan
    ringkasan request), plus `status: "failed"`, `errorId`, `error`;
  - ID dokumen = `Idempotency-Key` untuk dokumen sukses maupun gagal;
  - rules Firestore yang mengizinkan app menulis dokumen status gagal;
  - cara app menentukan `{vid}` dan nama tabel per ledger: konvensi tetap, atau
    meta di konfigurasi.

### Q4. Waktu aksi

**Status: diputuskan.** App menyuntik `actionAt` ke `data`: waktu record antrean
saat tombol ditekan, string epoch milidetik. Nilainya sama dengan waktu dokumen
Event di tab Event, sehingga konsumen bisa mencocokkan keduanya. Tinggal masuk
kontrak Q1.

### Q5. `Idempotency-Key` sampai ke konsumen

**Status: terbuka** — `FLUTTER_v2.md` masih hanya menyebut attribute `subject`,
`requestId`, dan `publishedAt`.

Bisakah gateway meneruskan `Idempotency-Key` sebagai attribute message Pub/Sub
(misalnya `idempotencyKey`), dan apakah konsumen akan dedupe dengannya? Ini
menutup celah duplikat di luar 24 jam (§3 butir 4) sekaligus menjadi kunci
korelasi di Q3.

- Kalau **ya**: message yang pernah timeout lalu lewat 24 jam tetap kami kirim.
- Kalau **tidak**: mohon keputusan — tetap dikirim (risiko ganda) atau dibuang
  dan dilaporkan (risiko hilang).

### Q6. Referensi gambar

**Status: diputuskan pemilik config** — path Storage, bukan download URL
bertoken.

Format dari sisi app: `gs://<bucket>/<path>`, diturunkan dari download URL yang
disimpan app. Bucket upload app saat ini `otq-01-ase2`, tetapi gambar
placeholder app ada di bucket project lain; karena itu bucket selalu ikut
ditulis. Foto yang gagal di-upload dikirim sebagai string kosong (§2.3). Mohon
konfirmasi bahwa konsumen bisa membaca path tersebut dengan service account-nya
sendiri.

### Q7. Lingkungan uji — [blocking untuk mulai uji]

**Status: sebagian.**

- ✓ Ledger uji `TESTMOBILE` sudah tersedia (`FLUTTER_v2.md`).
- Masih perlu: URL gateway dev dengan `ERROR_DETAIL=full`.
- Contoh `curl` di `FLUTTER_v2.md` §8 masih publish ke `WFREQLAP`. Mohon diganti
  `TESTMOBILE`, supaya uji dari `curl` tidak sampai ke topic yang nanti dibaca
  konsumen sungguhan.

Strategi uji dari sisi app ada di §6.1.

### Q8. URL gateway — [blocking untuk rilis]

**Status: sebagian.** Kami menemukan URL gateway sendiri dari format URL standar
Cloud Run: `https://pub-sub-gateway-721538991284.asia-southeast2.run.app`. Tanpa
kredensial, `/livez` menjawab `200 {"status":"ok","version":"d68a3d4"}` dan
`/v1/ledgers` menjawab `401 unauthenticated` (2026-09-14). URL ini sudah dipasang
sebagai default di app. Mohon konfirmasi:

- ini gateway yang benar untuk build rilis, bukan hanya untuk dev;
- apakah ada gateway dev terpisah (Q7);
- kabari kami sebelum URL berubah (service di-rename atau pindah region), karena
  perubahan URL butuh rilis app baru.

### Q9. Masa transisi — [blocking sebelum konfigurasi diaktifkan]

**Status: terbuka, ada dua usulan.**

Konfigurasi dipakai bersama oleh build lama dan build baru. Kalau tombol punya
`addToEvent` (untuk build lama) dan `publishLedger`, build baru menjalankan
keduanya. Dua usulan untuk menghindari dobel:

- **Supersede** (usulan pemilik config): build baru men-skip `addToEvent` di
  tombol yang punya `publishLedger`, dan konsumen menulis padanannya.
- **Tautan lewat key** (usulan kami): `addToEvent` tetap jalan dan app menambahkan
  field `idempotencyKey` ke dokumennya; konsumen hanya menulis status/hasil.

Pertimbangan lengkapnya, termasuk efek supersede pada push notifikasi dan
`updateEventRow`, ada di `pubsub_publishledger_reply.md` §2.

### Q10. Format `Retry-After`

**Status: terbuka.** Apakah selalu dalam detik (bukan HTTP-date)? Berapa nilai
tipikalnya? Rencana kami hanya membaca format detik.

### Q11. Kebijakan deprecation

**Status: terbuka.** Berapa lama versi skema `deprecated` dijamin tetap
diterima? Karena antrean offline tidak membuang aksi berdasarkan umur (§1), kami
usul versi lama tidak pernah dihapus — cukup ditandai `deprecated` — atau
dijamin minimal 30 hari. Pemilik config menyetujui usulan "tidak pernah
dihapus".

### Q12. Kapasitas

**Status: terbuka.** Apakah gateway dan penyimpanan idempotency siap untuk
lonjakan setelah gangguan (§3 butir 2)? Perlukah kami membatasi laju kirim di
sisi app? Kalau butuh perkiraan jumlah device atau aksi per hari, kami bisa
siapkan.

### Q13. Pemilik ledger — [blocking untuk Q1]

**Status: terbuka** — `FLUTTER_v2.md` masih "belum ditetapkan" untuk
`WFREQLAP` dan `WFREQLEX`. Siapa yang menyetujui kontrak kedua ledger itu?

### Q14. Penulis tab Event

**Status: baru (rev 2).**

Mohon konfirmasi bahwa proses yang menulis tab Event (`processEvent2`) membaca
dokumen `Proxy/{ssid}/Event`, dan bahwa tidak ada konsumen ledger yang ikut
menulis baris tab Event (§3 butir 8).

---

## 6. Usulan urutan kerja

1. **Backend:** jawab Q1–Q3, Q7 (URL dev), Q8 (konfirmasi URL), Q13, dan Q14.
   Ledger uji sudah tersedia.
2. **Mobile:** ✓ pengiriman fase 1 sudah dibangun (client, outbox, parser
   konfigurasi) dan siap diuji terhadap `TESTMOBILE`; penulis status gagal
   menyusul setelah Q3 (fase 2).
3. **Mobile:** pasang App Check, sementara gateway tetap di mode `log`.
4. **Bersama:** uji end-to-end di gateway dev (`ERROR_DETAIL=full`) lewat
   `TESTMOBILE` (§6.1).
5. **Mobile:** rilis app ke store dan pantau adopsi.
6. **Konfigurasi:** aktifkan publish di layar terkait **setelah** build yang
   mendukung tersebar dan Q9 diputuskan, karena build lama mengabaikan
   konfigurasi ini.
7. **Backend:** pantau cakupan App Check untuk semua app, lalu `enforce`.

### 6.1 Strategi uji dengan `TESTMOBILE`

`FLUTTER_v2.md` menyarankan "satu submit per layar sebelum layar itu
dinyalakan". Di otonomiq, konfigurasi layar berlaku untuk semua user di tenant
yang sama. Mengganti `ledgerCode` sebuah layar produksi ke `TESTMOBILE` membuat
semua user build baru ikut publish ke ledger uji selama masa uji; kalau
supersede (Q9) berlaku, ajuan asli mereka hilang. Cara yang aman:

- **Sebelum build baru dirilis:** build lama mengabaikan `publishLedger`, jadi
  konfigurasi produksi yang berisi `publishLedger` hanya berpengaruh ke device
  QA.
- **Setelah rilis:** uji di tenant atau workbook demo, bukan di konfigurasi
  produksi.
- **Build developer ikut mengirim.** URL gateway sudah menjadi default di app,
  jadi `flutter run` tanpa flag pun mem-publish. Aman selama layar uji memakai
  `TESTMOBILE`. Untuk gateway lokal:
  `--dart-define=GATEWAY_URL=http://10.0.2.2:8080` (`http` hanya diterima di
  build debug).
- **Opsional (belum dibangun):** build QA di-compile dengan `--dart-define` yang
  mengarahkan semua publish ke `TESTMOBILE`. Cara ini tidak menangkap salah
  ketik `ledgerCode` di konfigurasi, jadi `ledgerCode` tetap dicek manual ke
  `GET /v1/ledgers`.

`202` dari `TESTMOBILE` tidak memvalidasi nama field. Selama skema `WFREQLAP`
dan `WFREQLEX` masih placeholder, nama field baru bisa dicocokkan setelah Q1
dijawab.

---

## 7. Checklist `FLUTTER.md` §9 — status rencana

| Item | Rencana otonomiq |
|---|---|
| `GATEWAY_URL` lewat `--dart-define` | Sebagian — default URL gateway di-compile ke app (Q8) dan `--dart-define` menimpanya. Menyimpang dari saran "bukan hardcode" supaya build rilis tidak bisa lupa flag; alasan keamanannya tetap terpenuhi karena URL tidak bisa diubah dari sheet |
| `Idempotency-Key` dibuat saat aksi dan dipakai ulang | Ya — disimpan bersama aksi di antrean |
| Body di-encode sekali | Ya — setelah gambar ter-upload, sebelum percobaan pertama |
| Tombol nonaktif selama request | Tombol tidak menunggu jaringan; satu tekan = satu aksi dijaga gerbang tombol yang sudah ada (diverifikasi saat QA) |
| `duplicate: true` = sukses | Ya |
| `401` → refresh paksa sekali, lalu login ulang | Ya — tanpa logout otomatis dari latar belakang |
| `503` → hormati `Retry-After`; `4xx` tidak di-retry | Ya |
| Parser error tahan body non-JSON | Ya |
| `errorId` dicatat dan ditampilkan | Dicatat ke Crashlytics; ke user lewat dokumen status gagal — path menunggu Q3 |
| Tidak ada payload di log | Ya |
| App Check | Dijadwalkan (§4) |
| Payload sesuai skema asli | Menunggu Q1 |

---

## Lampiran A — format konfigurasi (final)

```
<ledgerCode>⭘_v◼<schemaVersion>⭘<field>◼<nilai>⭘<field>◼<nilai>…
```

- `<ledgerCode>` wajib literal (tanpa token) dan cocok `^[A-Z0-9]{4,16}$`.
- `<nilai>` bisa berupa literal, isian form (`◁N▷` = isian form nomor N),
  atribut sistem yang direkam app saat submit (misalnya lokasi), atau nilai dari
  state app.
- Key berawalan `_` adalah meta dan tidak masuk `data`. `_v` menjadi
  `schemaVersion`; app menambahkan `_k` (`Idempotency-Key`) sendiri. Key `_`
  lain yang tidak dikenal diabaikan.
- `actionAt` adalah key milik app: disuntik otomatis, dan nilai dari
  konfigurasi ditimpa.
- Semua nilai dihasilkan sebagai string. Download URL Firebase Storage di dalam
  nilai diubah menjadi `gs://<bucket>/<path>`.

## Lampiran B — alternatif yang kami pertimbangkan

Setiap submit sudah tersimpan ke Firestore lewat antrean yang ada. Trigger
Firestore → Pub/Sub di sisi backend akan menghasilkan message tanpa perubahan
app sama sekali, tapi kehilangan dua hal yang disediakan gateway: `subject` dari
token terverifikasi dan validasi skema di tepi. Kalau dua hal itu memang alasan
gateway dibangun, abaikan lampiran ini — rancangan di atas sudah mengikuti
gateway.
