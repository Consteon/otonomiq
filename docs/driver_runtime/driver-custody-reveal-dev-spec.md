# custodyReveal — Dev Spec (STEP 2/2: reveal + compare + branch)

**Buat:** Flutter dev. Page **STEP 2/2** custody — buka angka gudang, banding vs hitungan driver, lalu **branch** ke P7 (match) / P8 (selisih). Dituju dari **P6** (tombol "Lihat Catatan Warehouse").
**Flow:** P5 → P6 count (STEP 1/2) → **custodyReveal (ini, STEP 2/2)** → P7 CustodySuccess / P8 MismatchReport → P9.
**Source:** `json/driver-runtime/custody-reveal.json`. Runtime: `docs/driver-p4-handoff-dev.md` §0.

---

## 0. Kenapa page terpisah (bukan in-place di P6)

Sistem = **semua page JSON pre-loaded**, page statis, **no `passParams`**. Data nyebrang antar-page lewat **Firestore**. Jadi:
- **P6** tulis `ip[]` (native) ke opening doc → nav ke sini.
- **custodyReveal** baca opening doc (`ie[]` gudang + `ip[]` driver dari P6) → reveal + compare + branch.

Tiap page 1 tugas, gak perlu koordinasi state antar-widget. (Pilihan dev, align mockup STEP 1/2 → STEP 2/2.)

---

## 1. Widget

| widget | isi |
|---|---|
| `CUSTODY_STEP_HEADER` | plat + "KONFIRMASI PENERIMAAN◆STEP 2/2" (§2a) |
| `TXT` | "Verifikasi hitungan lo vs catatan warehouse" |
| `CUSTODY_REVEAL` | §2b — read-only compare + computed branch |

### 2a. `CUSTODY_STEP_HEADER` (BARU, dipake P6 + sini)
| field | nilai |
|---|---|
| `vehicleTable`/`vehicleSearch`/`plateField` | `84214220504259//stock_location` / `lv◼{vehicleId}` / `ln` |
| `text` | `judul◆step` (cth "KONFIRMASI PENERIMAAN◆STEP 2/2") |

### 2b. `CUSTODY_REVEAL` (BARU)
| field | nilai | fungsi |
|---|---|---|
| `table`/`search` | `84214220504259//vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` | opening doc |
| `expectedField` | `ie` | angka GUDANG (manifest) |
| `actualField` | `ip` | hitungan DRIVER (ditulis P6) |
| `joinTable`/`joinKey`/`labelField`/`categoryField` | `…//item` / `ii` / `in` / `ic` | nama + group section |
| `discrepancyField` | `dp` | tulis selisih `{ii,cd,ex,ac,dl}` |
| `reconcileField` | `rs` | `matched` \| `discrepancy_detected` |
| `matchRoute` | `[ROUTE:custodySuccess]` (P7) | branch kalau semua cocok |
| `mismatchRoute` | `[ROUTE:mismatchReport]` (P8) | branch kalau selisih |
| `recountRoute` | `[ROUTE:custodyCount]` (P6) | balik hitung ulang |
| `text` | slot ◆ (§3) | label kolom + status + tombol |

## 3. `text` slot (◆)
`RETURNABLE◆CONSUMABLE◆warehouse◆hitungan lo◆Match◆Ada selisih dengan catatan warehouse◆Konfirmasi Load · Siap Berangkat◆Lanjut · Report Mismatch◆Hitung Ulang`
header returnable · consumable · label kolom gudang · label kolom driver · status match · status selisih · tombol match · tombol mismatch · tombol recount

## 4. Behaviour
1. Render per item (grouped `ic`): **gudang (`ie.qt`) vs driver (`ip.qt`)** side-by-side + per-item match/selisih.
2. Compute overall: semua `ip==ie`? → match : mismatch.
3. Tombol (computed):
   - **match** → "Konfirmasi Load · Siap Berangkat" → tulis `rs=matched` → nav `matchRoute` (P7).
   - **mismatch** → "Lanjut · Report Mismatch" → compute `dp[]` (`ex=ie.qt, ac=ip.qt, dl=ac-ex` tiap item beda) → tulis `dp[]` + `rs=discrepancy_detected` → nav `mismatchRoute` (P8).
   - **"Hitung Ulang"** → nav `recountRoute` (P6).

## 5. Write — NATIVE (array) vs DSL (scalar)
| tulis | tipe | cara |
|---|---|---|
| `dp[]` | ARRAY | **NATIVE** (Flutter Firestore `doc.update({dp:[...]})`) — DSL updateEventRow/updateTableRow GAK support array |
| `rs` | scalar | DSL boleh / native |
| `cst` | scalar | **BUKAN di sini** — di P7/P8 |

> Widget custom (CUSTODY_REVEAL) → write native, bukan addToTable/updateTableRow DSL. Config cuma declare target (`table`/`search`/`discrepancyField`/`reconcileField`).

## 6. Field codes
`vehicle_check` opening: `ie[]`{ii,cd,qt}(gudang) · `ip[]`{ii,cd,qt}(driver, dari P6) · `dp[]`{ii,cd,ex,ac,dl}(TULIS) · `rs`(TULIS) · `cty`/`vv`/`cdt`. `item`: `ii`→`in`+`ic`.

## 7. References
- `json/driver-runtime/custody-reveal.json` (source)
- `docs/driver-custody-count-p6-dev-spec.md` (P6, sebelumnya), `docs/driver-runtime-field-dictionary.md`
- Lanjutan: **P7 CustodySuccess** (`cst=custody_confirmed`) / **P8 MismatchReport** (baca `dp[]` + note/foto → submit `cst=custody_discrepancy`) / **P9** — belum di-spec.
