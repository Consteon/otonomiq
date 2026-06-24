# Evidence addToEvent — Dev Spec (token injection `ept` / `erf` / parent-id)

Cara nulis dokumen **`evidence`** lewat `addToEvent` (keyed append-only ledger) di driver runtime, dengan fokus: **dari mana nilai `ept`, `erf`, dan id induk (`cnm`/`tnm`/`vnm`) didapat saat dirakit**, plus injeksi token aktor (`cv`/`cn`).

Parent dictionary: `docs/driver-runtime-field-dictionary.md` (§evidence baris 126–136). DSL ref: `docs/driver-runtime-dsl-preview.md` §3. Pola tulis driver: `updateEventRow` + `addToEvent` (2-write, MASTER §4).

> **Kenapa spec ini ada:** `evidence` itu **polymorphic** — satu collection nempel ke induk apa aja (task / check / movement / investigation). Dev sering bingung `ept`/`erf` diisi apa & kapan id induknya ada. Spec ini ngunci aturannya.

---

## 1. Konsep

`evidence` = lampiran (foto / ttd / gps / note) yang **selalu nunjuk ke 1 doc induk**. Induk ditentukan **2 field berpasangan**:

- **`ept`** = *tipe* induk (`movement` | `task` | `check` | `investigation`) — **discriminator**.
- **`erf`** = *id* doc induk — isinya tergantung `ept`.

`erf` TANPA `ept` gak ke-resolve (gak tau id itu nunjuk ke collection mana). **Selalu pasangkan.**

Ditulis via `addToEvent` → 1 row baru di collection `evidence` (flat keyed, sparse, append-only). Gak ada update — tiap upload = row baru.

---

## 2. Anatomy string (contoh `evidence` — mismatch report)

```
="84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼photo⭘ept◼check⭘erf◼{cnm}⭘i◼◁3▷⭘d◼◁10▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶"
```

Per-field, **dikelompokkan per SUMBER nilai** (ini inti yang dev wajib paham):

| field | nilai contoh | sumber | siapa isi |
|---|---|---|---|
| `84214220504259//evidence` | — | **target tulis** (tableVID + collection) | static, dari config halaman |
| `r` | `4320` | envelope DSL (replikasi/route) | static literal |
| `tablevid` | `20342033315492` | envelope DSL (event row VID) | static literal |
| `ety` | `photo` | **literal / form** evidence_type | authoring (atau pilihan UI) |
| `ept` | `check` | **LITERAL** — page tau induknya | authoring (fixed per page) |
| `erf` | `{cnm}` | **RUNTIME TOKEN** — id doc induk yang lagi dibuka | state page (auto, bukan ngetik) |
| `i` | `◁3▷` | **FORM INPUT** — path foto/ttd | driver (ambil foto, posisi field 3) |
| `d` | `◁10▷` | **FORM INPUT** — catatan | driver (posisi field 10) |
| `cv` | `{driverVid}` | **RUNTIME TOKEN** — vid uploader | session driver |
| `cn` | `{driverName}` | **RUNTIME TOKEN** — nama uploader | session driver |
| `t` | `◀2▶` | **SYSTEM STREAM** — epoch kejadian | runtime device clock (stream 2) |
| `ts` | `◀2\|T7\|Ddd MMM yyyy HH:mm:ss▶` | **SYSTEM STREAM** + transform T7 (timezone+format) | runtime |

> `i` & `d` sparse — kalau `ety◼gps` → kirim `la`/`lo` ganti `i`; kalau `ety◼notes` → cukup `d`. Field gak relevan = **omit** (sparse = NULL).

---

## 3. Token taxonomy (4 jenis — JANGAN ketuker)

| simbol | jenis | diisi kapan | contoh di evidence |
|---|---|---|---|
| `text` polos | **LITERAL** | saat authoring DSL (fixed di sheet) | `ept◼check`, `ety◼photo`, `r◼4320` |
| `{xxx}` | **RUNTIME TOKEN** | runtime, ditarik dari **state page yang lagi kebuka** | `{cnm}` `{driverVid}` `{driverName}` |
| `◁N▷` | **FORM INPUT** | runtime, dari **input driver** (N = posisi field di form) | `i◼◁3▷` `d◼◁10▷` |
| `◀N▶` | **SYSTEM STREAM** | runtime, dari **device/session** (N = index stream; `\|T7\|fmt` = transform) | `t◼◀2▶` `ts◼◀2\|T7\|…▶` |

**Aturan keras:**
- `ept` = **selalu LITERAL.** 1 page = 1 tipe induk, fixed. Page mismatch-report tau dia nempel ke `check` → bake `ept◼check`. JANGAN bikin `ept` dinamis/form.
- `erf` = **selalu RUNTIME TOKEN** `{…}`. Driver **gak pernah ngetik** id induk. Ditarik dari doc yang lagi di-bind page.
- `cv`/`cn` = RUNTIME TOKEN dari session (`{driverVid}`/`{driverName}`), bukan form.
- `i`/`d` = FORM INPUT (`◁N▷`) — satu-satunya yang driver isi manual.

---

## 4. Resolusi `ept` → `erf` (polymorphic)

`ept` literal nentuin id mana yang masuk `erf`:

| `ept` (literal) | `erf` (runtime token) | induk |
|---|---|---|
| `check` | `{cnm}` | vehicle_check doc (custody / rekon) |
| `task` | `{tnm}` | task doc (stop pengiriman) |
| `movement` | `{mrf}` / mov id | movement ledger row |
| `investigation` | `{vnm}` | investigation doc (supervisor) |

Contoh per skenario:

- Foto **bukti drop** di stop → `ept◼task` + `erf◼{tnm}`
- Foto **selisih** pas tutup custody → `ept◼check` + `erf◼{cnm}`
- Foto **tindak-lanjut** supervisor → `ept◼investigation` + `erf◼{vnm}`

---

## 5. Lifecycle id induk — kapan `cnm`/`tnm`/`vnm` LAHIR

`erf` **cuma valid kalau doc induk SUDAH ke-create.** Tiap id lahir di moment create doc-nya, oleh aktor beda, di waktu beda:

| id | doc | lahir KAPAN | siapa create | format | jadi token kapan |
|---|---|---|---|---|---|
| `tnm` | task | **pre-trip** (dispatch assign rute) | backend / dispatcher | `T-051` (seq backend) | dari awal trip (task feed udah bawa) |
| `cnm` | vehicle_check | driver **custody OPEN** (P7) & **CLOSE/rekon** (P12) | driver app (submit) | `CHK-VEH-{plate}-{yyyymmdd}-{OPEN\|CLOSE}` — **deterministik komposit** | begitu doc OPEN/CLOSE di-create; app bisa **rakit sendiri** dari `{plate}+{date}+phase` tanpa nunggu backend |
| `vnm` | investigation | **post-mismatch**, supervisor buka investigasi | supervisor | `INV-2026-001` (seq) | baru ada SETELAH supervisor open — **gak ada pas driver report** |

**Urutan create:** `tnm` (dispatch) → `cnm` (driver open/close) → `vnm` (supervisor).

Konsekuensi: **window mismatch report driver = setelah `cnm`, sebelum `vnm` ada.** Makanya induk evidence driver = `check` (`erf◼{cnm}`), BUKAN `investigation`. Evidence ke `investigation` baru muncul nanti pas supervisor tindak-lanjut.

---

## 6. Dari mana runtime token `{…}` di-source (buat dev)

Semua `{…}` ditarik dari **state page yang lagi kebuka**, bukan input:

| token | sumber state | catatan |
|---|---|---|
| `{driverVid}` | session login (workforce VID) | konsisten 1 trip |
| `{driverName}` | session login (workforce nama, denorm) | tampil + simpan |
| `{cnm}` | doc vehicle_check yang lagi di-bind page CLOSE | deterministik → app bisa compute `CHK-VEH-{plate}-{date}-CLOSE` |
| `{tnm}` | task aktif di workspace stop | dari task feed |
| `{vnm}` | doc investigation aktif (page supervisor) | gak ada di page driver |

Dev wiring: page mismatch-report **dibuka DARI** context vehicle_check CLOSE → doc id-nya udah di state. Inject `{cnm}` dari situ. Driver gak lihat/ngetik id-nya.

---

## 7. Skenario MISMATCH REPORT (lengkap)

Driver tutup custody (P12), rekon nemu selisih (cth LPG3: 6 expected vs 5 fisik). Flow tulis:

1. **`updateEventRow`** → vehicle_check CLOSE: `rs◼discrepancy_detected` + `dp` (delta −1). Ini yang bikin/finalize doc `cnm` CLOSE.
2. **`addToEvent`** → `evidence` (string §2): `ety◼photo` `ept◼check` `erf◼{cnm}` + foto `◁3▷` + note `◁10▷` + `cv`/`cn` session + `t`/`ts`.

Saat (2) jalan, `{cnm}` udah ke-resolve (doc CLOSE udah ke-create di step 1, atau di-compute deterministik). `vnm` belum ada → JANGAN coba `ept◼investigation`.

Lanjutan (di luar driver): supervisor buka `investigation` (`vnm` lahir) dengan `vrf◼{cnm}` + `vpt◼check` (nunjuk balik ke check yang sama). Evidence tambahan pas investigasi → `ept◼investigation` + `erf◼{vnm}`.

---

## 8. Checklist dev (DO / DON'T)

**DO**
- `ept` selalu literal sesuai page.
- `erf` selalu `{…}` runtime token dari doc yang di-bind page.
- Pasangkan `ept` + `erf` selalu barengan.
- Pastikan doc induk udah ke-create sebelum nulis evidence (cek urutan §5).
- Sparse: omit field gak relevan (foto → `i`; note → `d`; gps → `la`/`lo`).

**DON'T**
- ❌ `ept` dari form input / dinamis.
- ❌ `erf` diketik manual driver.
- ❌ `ept◼investigation` di page driver (`vnm` belum lahir).
- ❌ `cv`/`cn` dari form (ambil dari session token).
- ❌ kirim `erf` tanpa `ept` (gak ke-resolve).
