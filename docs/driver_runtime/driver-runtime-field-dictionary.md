# Driver Runtime — Field Dictionary (short code, UNIK per fungsi)

Acuan reuse = dictionary book `1_XHmo5…` (tab `addToEvent`, `location`). Aturan: **fungsi sama → key lama; fungsi beda → key UNIK (gak nabrak, gak dipakai 2 collection untuk arti beda).**
Legend src: ✓ = reuse key existing · ✚ = key baru.

---

## A. Key DIPAKAI BARENG (fungsi IDENTIK di semua collection)
| code | field | kenapa boleh bareng |
|---|---|---|
| `r` `tablevid` `p` `ev` | envelope DSL | sama di tiap doc |
| `t` (/ `ts`) | occurred_at: `t`=epoch (semua coll, sort/query) / `ts`=string **cuma `movement`** (ledger; coll lain format `t` di widget) | "kapan kejadian" |
| `et` | waktu server tulis | synchronized_at / last_computed_at |
| `search` | kunci cari `★…☆…` | doc yg di-update |
| `VID` / `n` | driver vid / nama | identitas orang (workforce) |
| `cv` / `cn` | creator/actor vid / nama | pembuat doc (task admin / evidence uploader / investigation supervisor). **movement actor = `dv`/`dn`** (driver yg scan) per SSOT |
| `ii` | item id | identitas item (master + FK) — barang yg sama |
| `lv` | location id | identitas stock_location (master + FK) |
| `lt` | location_type | tipe lokasi (warehouse/vehicle/client) |
| `ln` | location name | nama lokasi |
| `la` / `lo` | geo lat / long | titik koordinat |
| `i` | image url | foto / tanda tangan |
| `d` | free text | catatan / notes / content |
| `cd` | kondisi (full\|empty) | nilai kondisi 1 baris |
| `qt` | quantity (unit count) | jumlah unit |

> Ini SATU barang yg muncul di banyak tempat (item id, lokasi id, waktu, aktor, foto, qty). Bukan "key beda arti" — jadi tetap 1 key.

## B. Key UNIK per collection (fungsi BEDA → key beda)
Yg dulu dipakai ulang (`ty`,`st`,`nm`,`rf`,`dt`,`ce`) sekarang dipecah:
| konsep | task | movement | vehicle_check | evidence | investigation | item | stock_location |
|---|---|---|---|---|---|---|---|
| **type** | `tty` | `mt` | `cty` | `ety` | — | `ic`(kategori) | — |
| **status/state** | `tst` | — | `rs`(rekon) | — | `vst` | `ist` | `lst` |
| **doc number/id** | `tnm` | (auto) | `cnm` | (auto) | `vnm` | `ii` | `lv` |
| **ref induk** | — | `mrf`→task | — | `erf`→induk | `vrf`→sumber | — | — |
| **parent type** | — | — | — | `ept` | `vpt` | — | — |
| **date (bisnis)** | `tdt` | — | `cdt` | — | — | — | — |
| **end time** | `tce` | — | — | — | `vce` | — | — |

---

## workforce — driver (REUSE, no field baru) — Delta 9
`VID`✓ vid · `n`✓ nama · `st`✓ status(existing "on") · `search`✓ `VID★…☆sv★…`
> buang `role` & `active`.

## item — master barang
| code | src | field | allowed / contoh |
|---|---|---|---|
| `ii` | ✓ | item id | galon |
| `in` | ✚ | nama | Galon Air 19L |
| `ic` | ✚ | kategori | returnable \| consumable |
| `tc` | ✚ | kondisi dilacak (array) | [full, empty] (returnable) \| [full] (consumable) |
| `un` | ✚ | unit | pcs \| kg |
| `ist` | ✚ | status | active \| inactive |

## stock_location — gudang / mobil / customer (1 collection)
| code | src | field | allowed / contoh |
|---|---|---|---|
| `lv` | ✓ | location id | VEH-B1234XY |
| `lt` | ✓ | tipe | warehouse \| vehicle \| client |
| `ln` | ✓ | nama | B-1234-XY |
| `al` | ✚ | alamat | — |
| `la`/`lo` | ✓ | geo | -6.31 / 106.64 |
| `dv` | ✚ | driver aktif (vehicle only) | 8754… |
| `lst` | ✚ | status | active \| inactive |

## task — 1 stop pengiriman
| code | src | field | allowed / contoh |
|---|---|---|---|
| `tnm` | ✚ | task no (id) | TASK-20260612-001 |
| `tty` | ✚ | task_type | delivery \| pickup_return |
| `tst` | ✚ | execution_state | draft\|assigned\|ready\|on_delivery\|completed\|validated\|closed |
| `kl` | ✚ | lokasi customer (FK id) | →stock_location |
| `kn` | ✚ | nama customer (denorm, buat tampil) | Honda Bintaro |
| `al` | ✚ | alamat (denorm) | Jl. Sudirman 54 |
| `gl` | ✚ | gudang asal (FK id) | →stock_location |
| `vv` | ✚ | mobil | →stock_location |
| `cv`/`cn` | ✓ | dibuat oleh (admin) | — |
| `tdt` | ✚ | scheduled_date | 2026-06-12 |
| `it` | ✚ | items (array, plan vs aktual drop+pickup) | [{ii,in,cdo,cdi,pd,pp,ad,ap}] |
| `t` | ✓ | created_at (epoch; format widget) | — |
| `tce` | ✚ | completed_at | epoch |
| `search` | ✓ | `tnm★TASK-…` | — |

**`it[]`:** `ii`✓ item id (FK) · `in`✓ nama item (denorm) · `cdo`✚ condition_out (full\|empty) · `cdi`✚ condition_in (full\|empty\|null) · `pd`✚ planned_drop · `pp`✚ planned_pickup · `ad`✚ actual_drop · `ap`✚ actual_pickup

## movement — ledger pindah (collection sendiri → robot baca → asset_cache)
| code | src | field | allowed / contoh |
|---|---|---|---|
| `mt` | ✚ | movement_type | GENESIS\|DROP\|PICKUP\|INTERNAL\|SALE\|DAMAGE\|LOST\|ADJUSTMENT |
| `fl` | ✚ | from_location | →stock_location? |
| `tl` | ✚ | to_location | →stock_location? |
| `ii` | ✓ | item | galon |
| `cd` | ✓ | kondisi | full \| empty |
| `qt` | ✓ | qty (selalu +) | 5 |
| `dv`/`dn` | ✓ | driver yg scan (Delta 3) | 8754… |
| `mrf` | ✚ | ref task | →task `tnm` |
| `t`/`ts` | ✓ | occurred_at (HP) | — |
| `et` | ✓ | synchronized_at (server) | — |
| `er` | ✚ | emitter_runtime (Delta 4) | DRIVER\|VEHICLE\|SUPERVISOR |
| `d` | ✓ | notes | — |

## vehicle_check — custody opening + rekonsiliasi closing (driver, Delta 7)
| code | src | field | allowed / contoh |
|---|---|---|---|
| `cnm` | ✚ | check no (id) | CHK-VEH-B1234XY-20260612 |
| `cty` | ✚ | check_type | opening \| closing |
| `cst` | ✚ | **trip/custody status (NEW)** — anchor lifecycle di opening doc | loading\|awaiting_custody\|custody_confirmed\|custody_discrepancy\|on_delivery\|returning\|closed |
| `vv` | ✚ | mobil | →stock_location |
| `gl` | ✚ | gudang | →stock_location |
| `cv`/`cn` | ✓ | checker = DRIVER | Budi |
| `cdt` | ✚ | check_date | 2026-06-12 |
| `ip` | ✚ | items_physical | [{ii,cd,qt}] |
| `ie` | ✚ | items_expected — manifest GUDANG. Keisi saat **OPENING** juga (dibanding vs `ip` driver, P6 reveal), bukan cuma closing | [{ii,cd,qt}] |
| `rs` | ✚ | reconciliation_state | matched \| discrepancy_detected |
| `dp` | ✚ | discrepancies | [{ii,cd,ex,ac,dl}] |
| `t` | ✓ | occurred_at (epoch) | — |
| `gv`/`gn` | ✚ | loader gudang vid/nama ("dimuat oleh") — **gudang-flow, FUTURE** | Anton Pratama |
| `ldt` | ✚ | load datetime (jam muat, epoch) — **gudang-flow, FUTURE** | — |

**`dp[]`:** `ii`✓ · `cd`✓ · `ex`✚ expected · `ac`✚ actual · `dl`✚ delta

> **Trip model (2026-06-17):** opening vehicle_check = **anchor 1 trip** (1 driver=1 vehicle=1 trip SEKARANG; future driver bisa N trip & pilih). `cst` = status trip (loading→…→closed), maju tiap fase; closing update `cst`=closed. `cv`/`cn` = checker DRIVER (yg jalanin); `gv`/`gn` = loader GUDANG (yg muat) — beda aktor. Link task↔trip = `(vv, tanggal)`, bukan FK. `gv`/`gn`/`ldt`/`ie`@opening = **gudang-flow (next feature)**, struktur disiapin dari sekarang.

## evidence — foto / ttd / gps / note
| code | src | field | allowed / contoh |
|---|---|---|---|
| `ety` | ✚ | evidence_type | photo \| gps \| signature \| notes |
| `erf` | ✚ | ref induk | id |
| `ept` | ✚ | tipe induk | movement \| task \| check \| investigation |
| `i` | ✓ | storage_path (photo/ttd) | gs://… |
| `la`/`lo` | ✓ | gps | — |
| `d` | ✓ | content (note) | — |
| `cv`/`cn` | ✓ | uploaded_by | Budi |
| `t` | ✓ | occurred_at (epoch) | — |

## investigation — tindak lanjut selisih (supervisor)
| code | src | field | allowed / contoh |
|---|---|---|---|
| `vnm` | ✚ | inv no (id) | INV-2026-001 |
| `vst` | ✚ | investigation_state | pending_review\|under_investigation\|clarification_requested\|resolved\|closed |
| `rt` | ✚ | resolution_type | clean\|with_adjustment\|damage_confirmed\|loss_confirmed |
| `vrf` | ✚ | sumber | id (check/movement) |
| `vpt` | ✚ | tipe sumber | check \| movement |
| `cv`/`cn` | ✓ | supervisor | — |
| `t` | ✓ | opened_at (epoch) | — |
| `vce` | ✚ | resolved_at | epoch |
| `search` | ✓ | `vnm★INV-…` | — |

## asset_cache — saldo (ROBOT tulis, app BACA)
doc id = `{lv}__{ii}__{cd}` (cth `VEH-B1234XY__galon__full`)
| code | src | field | contoh |
|---|---|---|---|
| `lv` | ✓ | location | VEH-B1234XY |
| `lt` | ✓ | location_type (denorm) | vehicle |
| `ii` | ✓ | item | galon |
| `cd` | ✓ | kondisi | full |
| `qt` | ✓ | qty terkini | 25 |
| `lm` | ✚ | last_movement ref | mov-id |
| `t` | ✓ | last_movement_at | — |
| `et` | ✓ | last_computed_at (sistem) | — |

---

## Daftar key BARU (✚) — 8 tab SUDAH ditulis ke `1_XHmo5…` (2026-06-15)
**item:** `ii`(id) `in ic tc un ist`
**stock_location:** `lt al dv lst` (+`lv` baru sbg id; `ad`→`al` biar gak nabrak task `ad`=actual_drop)
**task:** `tnm tty tst kl kn al gl vv tdt it tce` · it[]: `ii in cdo cdi pd pp ad ap` · (`kl`/`gl`/`vv`=FK id ke stock_location; `kn`=denorm nama buat tampil; "kirim/ambil N"=derive Σpd/Σpp)
**movement:** `mt fl tl er mrf` (+`cd qt`; actor `dv`/`dn`)
**vehicle_check:** `cnm cty cdt ip ie rs dp ex ac dl`
**evidence:** `ety erf ept`
**investigation:** `vnm vst rt vrf vpt vce`
**asset_cache:** `lm`

Semua dicek gak nabrak key existing (`r fc tablevid p et ld ev ty t ts ln lq i d cv cn av an sv sn cl rf tv tn st nm ll VID n ci co is os ta la li lo ra sf en search`) DAN gak ada 1 key dipakai 2 collection untuk arti beda.

## Next
8 tab driver-runtime SUDAH ditulis ke `1_XHmo5…` (2026-06-15): `item stock_location task movement vehicle_check evidence investigation asset_cache`. Plus `site` dipisah dari `location` (location = titik geo + `sv` FK ke site).

**Dummy data (seed Firestore) — skenario AKHIR-HARI lengkap, day 2026-06-15, vehicle F621a02a983500 / driver 87544551624342 Budi:**
- `item` (7) · `stock_location` (1 gudang + 2 mobil + 3 client) · `task` (3 stop, `tst=completed`, `it[].ad/ap` terisi = `pd/pp`, `tce` set).
- `vehicle_check` (2: OPEN custody + CLOSE rekon). OPEN `ip` full = Σ`pd`; CLOSE `ie` empty = Σ`pp` (returnable only — Aqua600 consumable gak balik); CLOSE `ip` LPG3 = 5 vs `ie` 6 → `rs=discrepancy_detected` + `dp` (−1).
- `movement` (25 baris ledger; `mid`=seed-key): 6 GENESIS@gudang + 6 INTERNAL load gudang→mobil + 7 DROP mobil→client + 6 PICKUP client→mobil. Aqua600 = **SALE** (`tl=null`, exit system). `dv/dn` actor.
- `asset_cache` (11 baris, **hand-seed = simulasi CF**, doc-id `{lv}__{ii}__{cd}`): gudang full = GENESIS−load (Aqua41 LPG12-17 Aqua600-20 LPG3-34 LPG15-13 Amidis22); mobil empty = Σpickup (Aqua9 LPG12-3 **LPG3-6** LPG15-2 Amidis3). Mobil full = 0 (omit). Client outstanding = net 0 (DROP=PICKUP balanced, Model B) → no client row. **LPG3 mobil = 6 (ledger truth) ≠ 5 fisik** = persis selisih yg di-flag vehicle_check CLOSE (belum di-adjust, nunggu investigation).
- BELUM seed: `evidence` · `investigation`.

> ⚠️ `asset_cache` + `task.it[].ad/ap` aslinya **DITURUNKAN Cloud Function** dari `movement` (app gak pernah nulis). Hand-seed di atas = bootstrap test biar UI ada data tanpa deploy CF. Kalau CF live → CF jadi SSOT, JANGAN hand-push asset_cache lagi (`scripts/driver-runtime-seed.js` udah ada warning + skip-guidance). CF: `docs/driver-runtime-movement-cf-handoff.md`.

**Divergensi doc↔sheet — RESOLVED 2026-06-17 (SSOT = sheet `1_XHmo5…`):**
- movement_type: **`mt`** (bukan `mty`) ✓
- movement actor: **`dv`/`dn`** (Driver VID/Name, bukan `cv`/`cn`) ✓
- `ts` (occurred string): cuma di `movement`; coll lain simpan epoch `t`, format di widget (ikut `task.tdt` "raw; format in widget").

> ⚠️ `docs/driver-runtime-tables-dev-spec.md` MASIH stale (pakai `iv`/`mty`/movement `cv`-`cn`/`it[]` `pq`-`aq`/`ad`=alamat). Dokumen ini (field-dictionary) = SSOT-aligned. Re-sync tables-dev-spec belum dilakukan.
