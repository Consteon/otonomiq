# Integrasi otonomiq × pub-sub-gateway — Rencana Mobile & Kebutuhan dari Backend

**Status:** DRAFT · rencana sisi mobile, belum ada kode · menunggu jawaban §5
**Untuk:** tim backend `pub-sub-gateway` dan pemilik ledger `WFREQLAP` / `WFREQLEX`
**Dari:** tim mobile `otonomiq`
**Tanggal:** 2026-09-11
**Acuan:** `FLUTTER.md` (versi dengan tabel ledger `WFREQLAP`/`WFREQLEX` dan skema placeholder)

---

## Ringkasan

Kami sudah mempelajari `FLUTTER.md` dan akan mengikuti kontraknya: header,
`Idempotency-Key`, tabel keputusan retry, dan App Check. Dokumen ini menjelaskan
bagaimana kontrak itu dipasang di otonomiq, apa dampaknya ke gateway dan
konsumen, dan apa yang kami butuhkan sebelum mulai.

Tiga hal terpenting:

1. **Publish bisa tertunda.** otonomiq offline-first: aksi user masuk antrean di
   device lebih dulu dan baru di-publish saat online — bisa berjam-jam atau
   berhari-hari kemudian. Setiap retry memakai `Idempotency-Key` dan body yang
   sama.
2. **Bentuk payload diatur konfigurasi, bukan kode.** Layar dan aksi otonomiq
   didefinisikan lewat konfigurasi (server-driven UI dari Google Sheets). Mapping
   field ke `data` juga ada di konfigurasi, jadi perubahan skema umumnya cukup
   dengan mengubah konfigurasi tanpa rilis app — kecuali untuk kebutuhan tipe
   data baru (§3 butir 7).
3. **Yang menghambat kami mulai:** kontrak payload (Q1), konteks tenant (Q2),
   tempat konsumen menulis hasil dan cara korelasinya (Q3), lingkungan uji (Q7),
   dan pemilik ledger (Q13).

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
Payload dibangun dan di-encode SEKALI, lalu disimpan di outbox publish
   ▼
Outbox dikirim tiap ±1 menit, sesaat setelah submit, dan saat koneksi pulih
   ▼
POST {GATEWAY_URL}/v1/ledgers/{ledgerCode}/messages
```

Outbox publish sengaja dipisah dari antrean yang sudah ada. Antrean lama
dirancang untuk penulisan Firestore yang tidak idempoten, sehingga menyerah
setelah beberapa kali gagal; gateway idempoten dan meminta retry sampai
berhasil. Dengan dipisah, gangguan gateway tidak menahan data lain, dan
kegagalan data lain tidak ikut membuang message.

### 2.2 Contoh konfigurasi

Tim konfigurasi menambahkan satu entri di tombol submit (nama key dan formatnya
masih usulan):

```
"publishLedger": "WFREQLAP⭘_v◼1⭘requestType◼leave⭘days◼◁3▷"
```

Artinya: ledger `WFREQLAP`, `schemaVersion` 1, field `requestType` bernilai
literal `leave`, dan field `days` diambil dari isian form nomor 3. App
menghasilkan:

```json
{ "schemaVersion": 1, "data": { "requestType": "leave", "days": "2" } }
```

Perhatikan `"days": "2"` bertipe **string**: format konfigurasi ini datar
(key–value) dan nilainya string secara default. Lihat §3 butir 7 dan Q1.

### 2.3 Perilaku klien

| Situasi | Perilaku app |
|---|---|
| `Idempotency-Key` | UUID v4, dibuat saat tombol ditekan; dipakai untuk semua percobaan, termasuk setelah app ditutup lalu dibuka lagi |
| Body | Di-encode sekali setelah gambar ter-upload dan sebelum percobaan pertama, lalu disimpan sebagai string; setiap percobaan mengirim byte yang sama |
| `202`, termasuk `duplicate: true` | Selesai; dihapus dari outbox |
| `400`, `404`, `405`, `409`, `413`, `422` | Tidak di-retry; dihapus; `errorId`, `error`, dan `ledgerCode` dicatat ke Crashlytics tanpa isi payload. Termasuk `404 ledger_not_found` akibat salah ketik `ledgerCode` di konfigurasi |
| `401` | Refresh token paksa sekali. Kalau masih `401`, message disimpan sampai user login ulang; app **tidak** logout otomatis dari proses latar belakang |
| `500`, `503`, timeout, koneksi putus | Disimpan dan dicoba lagi di siklus berikutnya (±1 menit), atau setelah `Retry-After` |
| Frekuensi | Satu percobaan per message per siklus; tidak ada retry beruntun di dalam satu siklus |
| Pergantian user | Message terikat ke UID pembuatnya dan hanya dikirim saat UID itu yang login. Logout mengosongkan outbox, sama seperti antrean lokal yang sudah ada |
| Lewat 24 jam | App mencatat "sudah pernah dikirim ke jaringan" **sebelum** POST. Message yang belum pernah dikirim tetap aman walau sudah lewat 24 jam, karena belum mungkin ada terbitan pertama. Hanya message yang pernah timeout lalu lewat 24 jam yang berisiko ganda — lihat Q5 |
| Header | `X-Client-Source: mobile`; `X-Firebase-AppCheck` setelah App Check dipasang (§4) |
| `GATEWAY_URL` | Di-compile lewat `--dart-define`. Sengaja **tidak** bisa diubah dari konfigurasi sheet: request membawa ID token, jadi URL yang bisa diedit dari sheet memungkinkan siapa pun yang punya akses edit membelokkan token ke server lain |
| File dan gambar | Tidak pernah masuk body. Gambar di-upload ke Firebase Storage; payload membawa referensinya (Q6) |
| Endpoint pendukung | App tidak memanggil `GET /v1/ledgers`, `/schema`, atau `/livez` di runtime |

Tombol submit tidak menunggu respons gateway; tampilan mengikuti pola
offline-first yang sudah ada. Akibatnya, penolakan `4xx` terjadi di latar
belakang dan tidak langsung terlihat oleh user — lihat Q3.

---

## 3. Dampak ke gateway dan konsumen

1. **`publishedAt` bukan waktu aksi.** Selisihnya bisa berjam-jam hingga
   berhari-hari. Kalau konsumen butuh waktu aksi, perlu field di `data` (Q4).
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
   Pub/Sub belum menjadi sumber yang lengkap (Q9).
7. **Tipe data.** Nilai dari form defaultnya string, dan format konfigurasi
   datar. Angka, boolean, objek bertingkat, atau array butuh dukungan tambahan
   di app yang hanya bisa sampai ke user lewat rilis app — karena itu kami minta
   skema final lebih awal (Q1).

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
jawabannya.

### Q1. Kontrak payload `WFREQLAP` dan `WFREQLEX` — [blocking]

- Mohon daftar field, tipe, status wajib/opsional, dan contoh payload untuk
  masing-masing ledger.
- Apakah skema asli akan menggantikan `v1` (placeholder) di tempat, atau
  dirilis sebagai `v2`? Kami usul **`v2`**, supaya message yang sudah terbit
  dengan placeholder `v1` tetap bisa dibedakan.
- Bila memungkinkan: payload datar (tanpa objek bertingkat atau array) dan
  identifier sebagai string, sejalan dengan saran `FLUTTER.md` §6.

### Q2. Konteks tenant — [blocking]

otonomiq multi-tenant, dan UID saja belum tentu cukup untuk menentukan tenant
pengirim. Apakah konsumen butuh tenant di `data`? Apa nama dan format
field-nya? Usulan kami: `vid` bertipe string.

### Q3. Hasil pemrosesan dan korelasi — [blocking]

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
- Penolakan `4xx` di latar belakang tidak terlihat oleh user (§2.3). Perlukah
  app menulis status "gagal terkirim" ke tempat yang sama supaya user tahu?

### Q4. Waktu aksi

Perlukah field waktu aksi di `data`, mengingat publish bisa tertunda (§3 butir
1)? Usulan: `actionAt`, epoch milidetik, dari jam device saat tombol ditekan
(bisa meleset bila jam device salah). Bisa digabung ke kontrak Q1.

### Q5. `Idempotency-Key` sampai ke konsumen

Bisakah gateway meneruskan `Idempotency-Key` sebagai attribute message Pub/Sub
(misalnya `idempotencyKey`), dan apakah konsumen akan dedupe dengannya? Ini
menutup celah duplikat di luar 24 jam (§3 butir 4) sekaligus menjadi kunci
korelasi di Q3.

- Kalau **ya**: message yang pernah timeout lalu lewat 24 jam tetap kami kirim.
- Kalau **tidak**: mohon keputusan — tetap dikirim (risiko ganda) atau dibuang
  dan dilaporkan (risiko hilang).

### Q6. Referensi gambar

Saat ini app meng-upload gambar ke Firebase Storage dan menyimpan download URL
bertoken (`https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?alt=media&token=…`);
siapa pun yang memegang URL itu bisa membaca file. Apakah konsumen menerima
bentuk ini, atau lebih suka path Storage yang dibaca dengan kredensial konsumen
sendiri?

### Q7. Lingkungan uji — [blocking untuk mulai uji]

Hanya ada satu project Firebase (`otq-01`), dan menurut `FLUTTER.md` §8 gateway
lokal pun menerbitkan ke topic sungguhan. Mohon:

- ledger khusus uji (misalnya `TESTMOBILE` dengan skema placeholder) atau cara
  resmi menandai message uji, supaya uji tidak sampai ke konsumen produksi;
- URL gateway dev dengan `ERROR_DETAIL=full`.

### Q8. URL gateway — [blocking untuk rilis]

URL produksi dan dev untuk `--dart-define=GATEWAY_URL`.

### Q9. Masa transisi — [blocking sebelum konfigurasi diaktifkan]

Kalau alur request ini sekarang sudah berjalan lewat Firestore (event atau
approval yang sudah ada di app), apakah alur lama tetap berjalan paralel selama
adopsi build baru? Mana sumber kebenarannya, dan siapa yang dedupe kalau satu
request lewat dua jalur?

### Q10. Format `Retry-After`

Apakah selalu dalam detik (bukan HTTP-date)? Berapa nilai tipikalnya? Rencana
kami hanya membaca format detik.

### Q11. Kebijakan deprecation

Berapa lama versi skema `deprecated` dijamin tetap diterima? Karena antrean
offline tidak membuang aksi berdasarkan umur (§1), kami usul versi lama tidak
pernah dihapus — cukup ditandai `deprecated` — atau dijamin minimal 30 hari.

### Q12. Kapasitas

Apakah gateway dan penyimpanan idempotency siap untuk lonjakan setelah gangguan
(§3 butir 2)? Perlukah kami membatasi laju kirim di sisi app? Kalau butuh
perkiraan jumlah device atau aksi per hari, kami bisa siapkan.

### Q13. Pemilik ledger — [blocking untuk Q1]

Kolom "Pemilik" di `FLUTTER.md` masih "belum ditetapkan". Siapa yang menyetujui
kontrak `WFREQLAP` dan `WFREQLEX`?

---

## 6. Usulan urutan kerja

1. **Backend:** jawab Q1–Q3, Q7, dan Q13; siapkan ledger uji.
2. **Mobile:** bangun pengiriman (client, outbox, konfigurasi) terhadap ledger
   uji — bisa paralel dengan finalisasi kontrak.
3. **Mobile:** pasang App Check, sementara gateway tetap di mode `log`.
4. **Bersama:** uji end-to-end di gateway dev (`ERROR_DETAIL=full`).
5. **Mobile:** rilis app ke store dan pantau adopsi.
6. **Konfigurasi:** aktifkan publish di layar terkait **setelah** build yang
   mendukung tersebar, karena build lama mengabaikan konfigurasi ini.
7. **Backend:** pantau cakupan App Check untuk semua app, lalu `enforce`.

---

## 7. Checklist `FLUTTER.md` §9 — status rencana

| Item | Rencana otonomiq |
|---|---|
| `GATEWAY_URL` lewat `--dart-define` | Ya |
| `Idempotency-Key` dibuat saat aksi dan dipakai ulang | Ya — disimpan bersama aksi di antrean |
| Body di-encode sekali | Ya — setelah gambar ter-upload, sebelum percobaan pertama |
| Tombol nonaktif selama request | Tombol tidak menunggu jaringan; satu tekan = satu aksi dijaga gerbang tombol yang sudah ada (diverifikasi saat QA) |
| `duplicate: true` = sukses | Ya |
| `401` → refresh paksa sekali, lalu login ulang | Ya — tanpa logout otomatis dari latar belakang |
| `503` → hormati `Retry-After`; `4xx` tidak di-retry | Ya |
| Parser error tahan body non-JSON | Ya |
| `errorId` dicatat dan ditampilkan | Dicatat ke Crashlytics; tampilan ke user menunggu Q3 |
| Tidak ada payload di log | Ya |
| App Check | Dijadwalkan (§4) |
| Payload sesuai skema asli | Menunggu Q1 |

---

## Lampiran A — format konfigurasi

```
<ledgerCode>⭘_v◼<schemaVersion>⭘<field>◼<nilai>⭘<field>◼<nilai>…
```

- `<nilai>` bisa berupa literal, isian form (`◁N▷` = isian form nomor N),
  atribut sistem yang direkam app saat submit (misalnya lokasi), atau nilai dari
  state app.
- `_v` menjadi `schemaVersion`. App menambahkan `_k` (`Idempotency-Key`)
  sendiri. Keduanya tidak masuk `data`.
- Semua nilai dihasilkan sebagai string. Dukungan tipe lain menunggu kontrak Q1.

## Lampiran B — alternatif yang kami pertimbangkan

Setiap submit sudah tersimpan ke Firestore lewat antrean yang ada. Trigger
Firestore → Pub/Sub di sisi backend akan menghasilkan message tanpa perubahan
app sama sekali, tapi kehilangan dua hal yang disediakan gateway: `subject` dari
token terverifikasi dan validasi skema di tepi. Kalau dua hal itu memang alasan
gateway dibangun, abaikan lampiran ini — rancangan di atas sudah mengikuti
gateway.
