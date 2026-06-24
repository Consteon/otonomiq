# P12 ReturnVehicle — Dev Spec

**Buat:** Flutter dev. P12 = akhir hari, driver serahkan kendaraan + sisa muatan ke gudang. Route `vertikaTeknoLokaciptaReturnVehicle`. Grounded mockup `src/component/Driverruntimefull.jsx` — `ReturnScreen`(3597), `deriveCargo`(3279).

**Flow:** P10 TaskFeed allDone → "Kembali ke Gudang" → **P12 ReturnVehicle** → "Serahkan ke Gudang" → handover gudang → sesi auto-close (logout terminal).

**Doctrine (penting):** driver CUMA serahkan. **Reconciliation/validasi = domain gudang (Vehicle Runtime), BUKAN driver.** Gudang yang hitung & confirm return → baru sesi ketutup + `cst=closed`.

---

## STATUS — display shell (data + write DEFERRED)
- **Cargo "Sisa di Kendaraan"** = `asset_cache` (CF-derived vehicle stock). CF belum ada (movement/CF deferred) → card render struktur, value nunggu CF. `deriveCargo` mockup recompute dari task `it[]` (loaded−drop, pickup) krn prototype; runtime REAL baca `asset_cache`.
- **Submit "Serahkan ke Gudang"** = handover SIGNAL + logout. `cst=closed` = gudang yang set saat confirm (bukan driver). Write driver-side deferred (sinyal handover) → RBT placeholder route DriverHome skrng.

---

## Widget (dedicated, match mockup) — Widget tab

| widget | type | row | render |
|---|---|---|---|
| `returnHeader` | `RETURN_HEADER` | 227 | header |
| `vehicleCargoSummary` | `VEHICLE_CARGO_SUMMARY` | 228 | intro + cargo card |

> op1Screen pakai **literal D-cell** (bukan VLOOKUP) → resolve tanpa nunggu drag col A/G/H. Registry Widget I+J tetep diisi (reference dev).

### 1. `RETURN_HEADER` (mockup 3601-3610)
Header: back `←`→`backRoute` (DriverHome) + label uppercase "Akhir Hari" + title "Return Kendaraan". text 2 seg.
```json
{"type":"RETURN_HEADER","backRoute":"vertikaTeknoLokaciptaDriverHome","text":"Akhir Hari◆Return Kendaraan"}
```

### 2. `VEHICLE_CARGO_SUMMARY` (mockup 3612-3623)
- intro: "Serahkan kendaraan **{plate}** + sisa muatan ke gudang. Gudang yang hitung & validasi (reconciliation = domain Vehicle Runtime)." — plate = `stock_location.ln` (`lv◼{vehicleId}`).
- card "Sisa di Kendaraan" — 4 baris: **Tabung isi** / **Tabung kosong** / **Galon isi** / **Galon kosong** + qty mono. Source = `asset_cache` (vehicle), bucket = kategori (gas/tabung vs galon) × kondisi (isi/kosong).
```json
{"type":"VEHICLE_CARGO_SUMMARY","vidtable":"20342033315492","vehicleTable":"84214220504259//stock_location","vehicleSearch":"lv◼{vehicleId}","plateField":"ln","cacheTable":"84214220504259//asset_cache","cacheSearch":"lv◼{vehicleId}","text":"Serahkan kendaraan◆ + sisa muatan ke gudang. Gudang yang hitung & validasi (reconciliation = domain Vehicle Runtime).◆Sisa di Kendaraan◆Tabung isi◆Tabung kosong◆Galon isi◆Galon kosong"}
```
text 7 seg: introA◆introB◆cardTitle◆Tabung isi◆Tabung kosong◆Galon isi◆Galon kosong.

---

## op1Screen — P12 page @1079 (`vertikaTeknoLokaciptaReturnVehicle`)
4 children (literal D):
| row | widget | catatan |
|---|---|---|
| 1080 | `returnHeader` (`RETURN_HEADER`) | back + Akhir Hari / Return Kendaraan |
| 1081 | `vehicleCargoSummary` (`VEHICLE_CARGO_SUMMARY`) | intro + Sisa di Kendaraan (asset_cache, deferred data) |
| 1082 | `NOTICE_BAR` info | "Setelah gudang konfirmasi return, sesi lo otomatis ketutup (logout terminal)." |
| 1083 | `RBT` | "Serahkan ke Gudang →" → handover (deferred) + logout, route DriverHome |

---

## OPEN (jangan invent)
1. **`asset_cache` schema** — field kategori/kondisi/qty + location-key buat `cacheSearch` (skrng best-guess `lv◼{vehicleId}`). Dev punya schema asset_cache → sesuaikan. Bucket gas-isi/gas-kosong/galon-isi/galon-kosong mapping = renderer.
2. **CF dependency** — asset_cache value nunggu movement-CF (deferred). Spec CF `driver-runtime-movement-cf-handoff.md`.
3. **Handover write** — sinyal driver "serahkan" (status trip handed-over?) + `cst=closed` di-set GUDANG saat confirm. Field/mekanisme handover-signal driver-side belum diputus.
4. **Type baru** (`RETURN_HEADER`/`VEHICLE_CARGO_SUMMARY`) butuh renderer build dev-side.

Source mockup: `src/component/Driverruntimefull.jsx` 3597 / 3279.
