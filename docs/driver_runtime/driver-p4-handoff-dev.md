# P4 DriverHome — Dev Handoff (self-contained)

**Buat:** Flutter dev yg bikin renderer + binding data DriverHome.
**1 file ini cukup buat mulai.** Detail lebih dalam / future variant → lihat §8 References.
**Live:** op1Screen proxy `18v3w5YJ6QuTaFOkIYoPE6fNRXbyq6GQm3Bdytfagaxg`, page `vertikaTeknoLokaciptaDriverHome`.

---

## 0. BACA INI DULU — 2 runtime requirement (kalau ga di-handle, page kosong)

Spec di bawah cuma kontrak tampilan. Supaya data KELUAR, app WAJIB:

### (A) Resolve table path
Tiap field `table`/`vehicleTable`/`itemsTable`/`gateTable` isinya `{tableVID}//{coll}`, cth `84214220504259//task`. Resolve ke:
```
MobileTable / {db} / tables / {tableVID} / {coll}
```
- `{tableVID}` = bagian sebelum `//` (cth `84214220504259`).
- `{db}` = dari config app (live = `6093608774765…`).
- **Semua doc-id AUTO** — FK dicari by FIELD (query `where <field> == <value>`), bukan get-by-id. cth resolve task: `where tnm == mrf`.

### (B) Inject / derive token runtime
Token `{...}` di-substitusi app SEBELUM query/render:
| token | sumber |
|---|---|
| `{driverVid}` | sesi scan P2 (driver.session) — VID orang yg scan |
| `{vehicleId}` | **derive**: `stock_location` where `lt=vehicle ⭘ dv={driverVid}` → `lv`. (1 driver = 1 vehicle = 1 trip SEKARANG → balik 1) |
| `{today}` | epoch-midnight hari ini (TZ tetap, cth WIB). Dipakai eq-match ke `cdt`/`tdt` (yg juga epoch-midnight) |

`{}` = namespace runtime tunggal: token-sesi (`{vehicleId}`) + computed (`{total}`, `{allClosed}`, dll) sama-sama di-resolve by name.

### search DSL
`◼` = field **eq** value · `⭘` = **AND** · kiri = field code Firebase. Cth `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}`.
`◆` = pemisah slot di field `text`. `<N>` = posisi param op1Screen (static).

---

## 1. Page overview

**1 page, 2 state** (gak ada page P4b terpisah):
- **locked** = custody belum dikonfirmasi → card kuning "Perlu Aksi", rute dikunci.
- **confirmed** = custody beres → card hijau, inventory muncul, rute kebuka + progress, return aktif.

State ditentuin 1 hal: **ada/gak doc `vehicle_check` opening hari ini** (lihat §4).

---

## 2. Widget (6) — kontrak field

> Urutan render: header → TXT → gate → inventory → stop → nav.

### 2.1 `ROUTE_PROGRESS_HEADER` (identityOnly) — SELALU tampil
Nama driver + plat + tombol Keluar. **Data-bound, NO avatar.**
| field | nilai |
|---|---|
| `variant` | `identityOnly` |
| `table` / `search` | `84214220504259//workforce` / `VID◼{driverVid}` |
| `nameField` | `n` (nama driver) |
| `vehicleTable` / `vehicleSearch` | `84214220504259//stock_location` / `lv◼{vehicleId}` |
| `plateField` | `ln` (plat) |
| `logoutRoute` | `[ROUTE:pauseConfirm]` |
| `text` (◆, 8 slot LABEL) | `Rute Hari Ini◆stop◆gagal◆Drop◆Pickup◆kendaraan ditugaskan◆Keluar◆Belum ditugaskan kendaraan` |

Render: nama `workforce.n` + plat `stock_location.ln`. `vehicleSearch` KOSONG → tampil slot-7 fallback "Belum ditugaskan kendaraan". (Detail + variant `full`/progress: header dev-spec, §8.)

### 2.2 `TXT` — SELALU (label ganti per-state)
`{"type":"TXT","size":14,"data":"SEBELUM BERANGKAT"}` (locked) / `"HARI INI"` (confirmed).

### 2.3 `PRECONDITION_GATE_CARD` — SELALU (kuning↔hijau) · INI sumber state
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` |
| `itemsTable` / `itemsField` | `84214220504259//task` / `it` |
| `labelField` / `qtyField` | `in` (nama item) / `pd` (planned_drop) |
| `route` | `[ROUTE:custodyConfirm]` (→ P6) |
| `text` (◆, 9 slot) | `Perlu Aksi◆Konfirmasi Penerimaan Muatan◆Muat dari <2>. Cek & konfirmasi sebelum berangkat.◆Konfirmasi Penerimaan◆…◆Muatan dikonfirmasi◆{confirmedSummary} · jumlah aktual◆! Ada selisih dari catatan gudang◆…` |

Render: `search` KETEMU doc → **confirmed** (hijau, baca `vehicle_check.ip` aktual). KOSONG → **pending** (kuning, list item dari `task.it[]` `in`+`pd`). `rs=discrepancy_detected` → + banner selisih.

### 2.4 `INVENTORY_BUCKET_CARD` — HIDDEN saat locked
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//asset_cache` / `lv◼{vehicleId}` |
| `categoryField` | `cd` |
| `buckets` | `full◼ok⭘empty◼warn` (value = data `cd` `full`/`empty`; display "Isi"/"Kosong" = mapping renderer) |
| `gateTable` / `gateSearch` | `84214220504259//vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` |
| `text` (◆, 2 slot) | `Isi Kendaraan Sekarang◆Update otomatis tiap serah-terima…` |

Render: per item → "N isi · M kosong" dari `asset_cache.qt` group by `cd`. **gateSearch KOSONG → SEMBUNYI.**

### 2.5 `DRIVER_STOP_CARD` (preview) — locked=🔒preview, confirmed=kebuka+progress
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//task` / `vv◼{vehicleId}⭘tdt◼{today}` |
| `navState` | `assigned` |
| `route` | `[ROUTE:taskFeed]` |
| `gateTable` / `gateSearch` | `84214220504259//vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` |
| `icon` / `iconLocked` | ref |
| `text` (◆, banyak slot) | `Stop Berikutnya◆…◆{closed} dari {total} stop◆…` |

Render: list task hari ini (1 doc=1 stop), progress = Σ `tst` selesai / total. gateSearch KOSONG → 🔒 locked-preview.

### 2.6 `NAV_ACTION_CARD` — HIDDEN saat locked, aktif kalau semua stop kelar
| field | nilai |
|---|---|
| `table` / `search` | `84214220504259//task` / `vv◼{vehicleId}⭘tdt◼{today}` |
| `ready` | `{allClosed}` (computed: semua `tst`=closed?) |
| `route` | `[ROUTE:returnVehicle]` |
| `gateTable` / `gateSearch` | `84214220504259//vehicle_check` / `cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}` |
| `text` (◆, 3 slot) | `Return Kendaraan◆…◆Semua kelar — balik & serahkan ke gudang` |

---

## 3. Gating (locked vs confirmed)

**Gate = existence `vehicle_check` opening** (`cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}`). Tiap widget downstream bawa `gateTable`+`gateSearch` sendiri (search sama). **KETEMU doc → tampil/unlock. KOSONG → hidden/lock.** (Renderer boleh cache query identik.) Gak ada token sihir `{gateStatus}` — murni ada/gak doc.

| widget | locked | confirmed |
|---|---|---|
| ROUTE_PROGRESS_HEADER | ✅ | ✅ |
| TXT | ✅ "SEBELUM BERANGKAT" | ✅ "HARI INI" |
| PRECONDITION_GATE_CARD | ✅ kuning (blok) | ✅ hijau "dikonfirmasi" |
| INVENTORY_BUCKET_CARD | ❌ hidden | ✅ |
| DRIVER_STOP_CARD | ✅ 🔒 preview | ✅ kebuka + progress |
| NAV_ACTION_CARD | ❌ hidden | ✅ (kalau semua stop closed) |

---

## 4. Field codes (subset P4) — arti field

> Full dictionary: §8. Doc-id AUTO; FK = field.

**workforce** (driver): `VID` vid · `n` nama · `st` status.
**stock_location** (gudang/mobil/customer): `lv` id · `lt` `warehouse|vehicle|client` · `ln` nama/plat · `al` alamat · `la`/`lo` geo · `dv` active-driver-vid (vehicle only) · `lst` status.
**vehicle_check** (custody): `cnm` id · `cty` `opening|closing` · `cst` trip-status · `vv` mobil(FK) · `gl` gudang(FK) · `cv`/`cn` checker=driver · `cdt` check-date(epoch-midnight) · `ip[]` `{ii,cd,qt}` hitung-fisik · `ie[]` `{ii,cd,qt}` manifest-gudang · `rs` `matched|discrepancy_detected` · `dp[]` `{ii,cd,ex,ac,dl}` selisih.
**task** (1 stop): `tnm` id · `tty` type · `tst` exec-state(`assigned…closed`) · `kl` cust-loc(FK) · `kn` cust-nama(denorm) · `al` alamat(denorm) · `gl` gudang(FK) · `vv` mobil(FK) · `tdt` jadwal(epoch-midnight) · `it[]` `{ii,in,cdo,cdi,pd,pp,ad,ap}` · `tce` selesai.
  - `it[]`: `ii` item-id · `in` nama(denorm) · `cdo`/`cdi` cond out/in · `pd`/`pp` planned drop/pickup · `ad`/`ap` actual drop/pickup.
**asset_cache** (saldo, robot-written, app BACA): doc-id `{lv}__{ii}__{cd}` · `lv` lokasi · `lt` tipe · `ii` item · `cd` `full|empty` · `qt` saldo · `lm` last-movement · `t`/`et` waktu.

---

## 5. Live op1Screen mapping

| row | isi |
|---|---|
| 1007 | header page `vertikaTeknoLokaciptaDriverHome` |
| 1008 | routeProgressHeader |
| 1009 | text (SEBELUM BERANGKAT) |
| 1010 | preconditionGateCard |
| 1011 | inventoryBucketCard |
| 1012 | driverStopCard |
| 1013 | navActionCard |
| 1014-1015 | buffer |

Widget template (tab `Widget`): `routeProgressHeader@200` · `preconditionGateCard@201` · `inventoryBucketCard@202` · `driverStopCard@203` · `navActionCard@204`. (Nama widget ≠ JSON `type`.)

App fetch page → tiap baris col D = JSON widget resolved (udah ke-prefix `84214220504259//` + token `{}`). App tinggal resolve path (§0-A) + token (§0-B).

---

## 6. Register type baru

`ROUTE_PROGRESS_HEADER`, `PRECONDITION_GATE_CARD`, `INVENTORY_BUCKET_CARD`, `DRIVER_STOP_CARD`, `NAV_ACTION_CARD`. (`TXT` udah ada.)
- Yg baca **nested array** (gate/inventory item list ← `it[]`/`asset_cache`): renderer iterasi field array dalam doc (BUKAN collection-of-docs). Widget list lama (`displayItemCardDetail` dll) = collection-per-doc, GAK cocok buat array.

---

## 7. Blocker / open

- **(WAJIB)** §0-A resolve path + §0-B inject/derive token. Tanpa ini render kosong (header fallback, "0 tujuan", card lock terus) — bukan bug JSON.
- `[ROUTE:custodyConfirm]`=P6 · `[ROUTE:taskFeed]` · `[ROUTE:returnVehicle]` · `[ROUTE:pauseConfirm]` = placeholder route, resolve via routing app.
- `[ICON]`/`[ICON_LOCKED]`/`[ICON_READY]` = icon ref, isi.
- `cdt`/`tdt` = epoch-midnight (date eq-match). `{today}` harus emit format sama persis.
- Multi-trip (driver N mobil) = FUTURE; sekarang 1 trip, `{vehicleId}` auto-derive.

---

## 8. References (detail / future)

- `docs/driver-route-progress-header-dev-spec.md` — header full (variant `full`/progress, computed aggregate, edge case).
- `docs/driver-home-state-machine-dev-spec.md` — state machine + visual ASCII per-state.
- `docs/driverhome-p4-dev-spec.md` — kontrak per-widget asli.
- `docs/driver-runtime-field-dictionary.md` — full field dictionary (semua collection).
- `docs/driver-runtime-tables-dev-spec.md` — schema relationships + flow baca/tulis per-page (WAJIB pas lanjut P5/P6/P11 yg NULIS).
