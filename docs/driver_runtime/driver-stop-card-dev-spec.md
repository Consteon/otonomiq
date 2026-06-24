# Driver Stop Card — Dev Spec

Feed list widget for the Driver Runtime: renders the route as state-grouped delivery-stop cards (Stop Berikutnya / Dilaporkan Gagal / Sudah Selesai). Each card shows stop identity, drop/pickup badges, and a state-driven footer (CTA / completed line / failure note). Only `assigned` cards navigate to the workspace.

Source: `src/component/Driverruntimeintegrated.jsx` — `TaskCard` (499-647), `StateChip` (169-179), feed grouping (753-817).
Parent: `docs/driver-runtime-widgets-MASTER-handoff.md`. Format ref: `docs/stepper-widget-dev-spec.md`.

**Widget tab name:** `driverStopCard`
**Type code:** `DRIVER_STOP_CARD`
**Base template row:** `Widget!J199`
**Master index entry:** `◆driverStopCard▶Widget!J199`

> **Relationship to `displayListItemCard`:** new widget rather than a variant — adds dual drop/pickup quantity badges, a per-`state` footer with three distinct renders, and built-in state grouping. Could be modeled as a `displayListItemCard` variant if dev prefers; flagged as an option, not the default.

---

## 1. Konsep

A single list widget bound to the driver's task table, rendering 3 ordered sections by `state`:

| Section | Filter | Header | Tap behavior |
|---------|--------|--------|--------------|
| Stop Berikutnya | `state == assigned` | label + count + italic hint | navigates to workspace |
| Dilaporkan Gagal | `state == failed` | amber label + count | read-only (no nav) |
| Sudah Selesai | `state == completed` | dim label + count | read-only (no nav) |

Per-card content: stop-number icon (`✓`/`!`/number), task id (mono) + optional "Pickup Only" chip, customer (bold), state chip, address, distance, drop/pickup badges, state footer.

Badge/footer values are storage fields (`<>`); section counts are computed (`{}`).

---

## 2. Base JSON Template

`Widget!J199`:

```json
{"type":"DRIVER_STOP_CARD","source":"[SRC]","navState":"[NAVSTATE]","route":"[ROUTE]","text":"[SEC_ASSIGNED]◆[SEC_FAILED]◆[SEC_COMPLETED]◆[ASSIGNED_HINT]◆[CTA_LABEL]◆[COMPLETED_PREFIX]◆[CONFIRMED_LABEL]◆[FAILED_MSG]◆[DROP_UNIT]◆[PICKUP_UNIT]◆[PICKUP_ONLY_LABEL]"}
```

**Demo resolved, `Widget!G199`:**

```json
{"type":"DRIVER_STOP_CARD","source":"[SRC:driverTasks]","navState":"assigned","route":"[ROUTE:deliveryWorkspace]","text":"Stop Berikutnya◆Dilaporkan Gagal◆Sudah Selesai◆Pilih sesuai kondisi lapangan◆Mulai Eksekusi◆Selesai◆Customer confirmed◆Dilaporkan gagal — menunggu admin reschedule◆drop◆pickup◆Pickup Only"}
```

---

## 3. Placeholder Catalog

| Placeholder | Type | Required | Default | Notes |
|-------------|------|----------|---------|-------|
| `[SRC]` | route token | YES | — | `[SRC:page]` ref to driver task list (memory: Web URL = SSOT, never hardcode URL) |
| `[NAVSTATE]` | enum | NO | `assigned` | Which `state` is tappable → navigates |
| `[ROUTE]` | route token | YES | — | Destination page for a tapped card; selected stop passed via injected nav token (memory: no `passParams`) |
| `[SEC_ASSIGNED]` | string | NO | `Stop Berikutnya` | ◆0 |
| `[SEC_FAILED]` | string | NO | `Dilaporkan Gagal` | ◆1 |
| `[SEC_COMPLETED]` | string | NO | `Sudah Selesai` | ◆2 |
| `[ASSIGNED_HINT]` | string | NO | `Pilih sesuai kondisi lapangan` | ◆3, italic subtitle under assigned header |
| `[CTA_LABEL]` | string | NO | `Mulai Eksekusi` | ◆4, footer button on assigned cards |
| `[COMPLETED_PREFIX]` | string | NO | `Selesai` | ◆5, rendered `✓ {prefix} {completedAt}` |
| `[CONFIRMED_LABEL]` | string | NO | `Customer confirmed` | ◆6, appended when `customerConfirmed` |
| `[FAILED_MSG]` | string | NO | `Dilaporkan gagal — menunggu admin reschedule` | ◆7 |
| `[DROP_UNIT]` | string | NO | `drop` | ◆8, badge suffix |
| `[PICKUP_UNIT]` | string | NO | `pickup` | ◆9, badge suffix |
| `[PICKUP_ONLY_LABEL]` | string | NO | `Pickup Only` | ◆10, chip when `taskType==pickup_return` |

---

## 4. Per-card field binding (from each task record)

Storage fields (`<>`) read from the bound row:

| Field | Use |
|-------|-----|
| `id` | mono id line |
| `customer` | bold title |
| `address` | address line |
| `distance` | `📍 {distance}` |
| `stopNumber` | icon number (when not completed/failed) |
| `state` | section grouping + state chip + footer branch |
| `taskType` | `pickup_return` ⇒ "Pickup Only" chip |
| `completedAt` | completed footer time |
| `customerConfirmed` | append confirmed label |
| `items[]` | badge sums (see §5) |

---

## 5. Computed values (`{}`)

| Variable | Formula |
|----------|---------|
| section counts | count tasks per section filter (shown as `· N` in each header) |
| `{totalDrop}` / `{totalPickup}` | Σ `planDrop` / `planPickup` over card's items |
| `{actualDrop}` / `{actualPickup}` | Σ `actualDrop` / `actualPickup` |
| badge value | completed card → `{actualX}`; otherwise → `{totalX}` |

Drop badge hidden when `{totalDrop}==0`; pickup badge hidden when `{totalPickup}==0`.

---

## 6. State chip (shared mapping)

Standard status chip (reuse existing chip component):

| state | label | variant |
|-------|-------|---------|
| `assigned` | Menunggu | slate |
| `in_execution` | Berjalan | indigo |
| `completed` | Selesai | emerald |
| `failed` | Gagal | amber |
| `blocked` | Blocked | amber |

---

## 7. Renderer Contract

1. Resolve `source`; group rows into assigned / failed / completed (in that order); skip empty sections.
2. Section header: label + `· {count}`; assigned section adds the italic `[ASSIGNED_HINT]` line.
3. Card:
   - icon square: `✓` (completed, emerald) / `!` (failed, amber) / `stopNumber` (slate).
   - id (mono dim) + "Pickup Only" chip if `taskType==pickup_return`.
   - customer (bold, ellipsis), state chip (right).
   - address (ellipsis) + `📍 {distance}`.
   - badges: `↓ {value} {DROP_UNIT}` (indigo / emerald if completed), `↑ {value} {PICKUP_UNIT}` (violet / emerald if completed).
   - footer by state: assigned → `[CTA_LABEL]` button (indigo); completed → `✓ [COMPLETED_PREFIX] {completedAt}` (+ `· [CONFIRMED_LABEL]` if confirmed); failed → `! [FAILED_MSG]` (amber).
4. completed/failed cards: 0.75 opacity, amber50 bg for failed.
5. Tap: navigate to `[ROUTE]` only when `state == [NAVSTATE]`; pass selected stop via injected nav token.

---

## 8. Op1Screen Integration

### 8.1 Widget row
col B = `driverStopCard`, col D = resolved JSON, col E = `,`+JSON, col F = `TRUE`. Placed after `routeProgressHeader` on the feed page.

### 8.2 Param columns (sibling convention)

| Col | Param | | Col | Param |
|-----|-------|-|-----|-------|
| G | SRC | | M | CTA_LABEL |
| H | NAVSTATE | | N | COMPLETED_PREFIX |
| I | ROUTE | | O | CONFIRMED_LABEL |
| J | SEC_ASSIGNED | | P | FAILED_MSG |
| K | SEC_FAILED / SEC_COMPLETED | | Q | DROP_UNIT / PICKUP_UNIT |
| L | ASSIGNED_HINT | | R | PICKUP_ONLY_LABEL |

(Split label segments across columns as page layout requires.)

---

## 9. Validation Rules

1. `[SRC]` and `[ROUTE]` must be route tokens, not literal URLs.
2. `text` = 11 segments (10× `◆`).
3. `state` value outside the §6 enum ⇒ render with neutral chip + log warning.
4. List is read-only display; only nav action emitted (no addToTable from the card).
5. Empty source ⇒ render the all-done / empty state (host page handles celebration banner via REUSE `horizBanner`).

---

## 10. Edge Cases

| Case | Behavior |
|------|----------|
| section empty | section + header hidden |
| `taskType==pickup_return` | "Pickup Only" chip; drop badge likely hidden (totalDrop==0) |
| completed card with no `completedAt` | render `✓ [COMPLETED_PREFIX]` without time |
| tap on non-`navState` card | no-op (read-only) |
| `customerConfirmed` false | confirmed label omitted |

---

## 11. Add Widget to Spreadsheet (1-time)

`A199=driverStopCard`, `I199=driverStopCard`, `J199=`base template (§2), `G199=`demo resolved. Append `◆driverStopCard▶Widget!J199` to `Widget!G1`. Verify `G199` renders with no `[X]` leftover.

---

## 12. Reference Checklist

- [ ] `Widget!J199` base template written
- [ ] `Widget!G1` master index updated
- [ ] `G199` demo renders OK
- [ ] 3-section grouping + per-section counts
- [ ] dual badges with completed→actual swap
- [ ] per-state footer (CTA / completed / failed) renders correctly
- [ ] tap nav gated by `navState`, stop passed via injected token
- [ ] state chip mapping matches §6
- [ ] `widget-qa` sign-off

---

## 13. Test Cases

| # | Scenario | Expected |
|---|----------|----------|
| 1 | 3 assigned + 1 completed | two sections; completed dimmed |
| 2 | assigned card | "Mulai Eksekusi" CTA; tap → workspace |
| 3 | completed card, confirmed | `✓ Selesai 07:42 · Customer confirmed`, no CTA |
| 4 | failed card | amber `! Dilaporkan gagal …`, tap = no-op |
| 5 | pickup_return task | "Pickup Only" chip, no drop badge |
| 6 | all assigned cleared | list empty → host shows all-done banner |

---

## 14. Versi & History

- v1.0 (2026-06-10) — Initial spec. Row 199. State-grouped list, dual badges, per-state footer, nav gated by `navState`.
- v1.1 (2026-06-19) — tx-delta: tombol "Tolak" (reject task) di varian `preview`/locked, opening-only, route ke RejectTaskSheet bawa `{rejectTaskVid}`. Catatan: §2–§14 = spec lama (source-based feed); live P4 pakai varian `preview` table-bound (lihat §15), belum di-resync penuh.

---

## 15. Reject task — varian `preview` / locked (tx-delta 2026-06-19)

**Konteks:** live P4 DriverHome pakai `DRIVER_STOP_CARD` `variant:"preview"` (table-bound: `table`/`search` + `gateTable`/`gateSearch`), bukan source-based feed §2. Ini = "HomeRouteCard" di mockup `Driverruntimefull2.jsx` (`HomeRouteCard` 3634), kartu rute saat masih terkunci (custody belum confirmed). Fitur "Tolak" nempel di sini.

Mockup: tiap baris task di kartu locked ada tombol "Tolak" (amber outline). Driver bisa nolak stop yang tidak searah, dikembalikan ke Admin buat mobil lain. Hanya sebelum berangkat (sebelum Konfirmasi Penerimaan).

### 15.1 Kapan tombol muncul
- Hanya di **render locked** (custody belum confirmed, yaitu `gateSearch cst◼custody_confirmed` TIDAK match).
- Per baris task, "Tolak" muncul kalau task **bukan** `completed`. Task completed tampil chip "Selesai", tanpa Tolak.
- Begitu custody confirmed (kartu unlock), Tolak hilang. Setelah berangkat tidak bisa reject (opening-only).

### 15.2 Config tambahan
```json
{
  "type":"DRIVER_STOP_CARD","variant":"preview","vidtable":"20342033315492",
  "table":"84214220504259//task","search":"vv◼{vehicleId}⭘tdt◼{today}",
  "navState":"assigned","route":"vertikaTeknoLokaciptaTaskFeed",
  "gateTable":"84214220504259//vehicle_check","gateSearch":"cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}⭘cst◼custody_confirmed",
  "nameField":"kn","addressField":"al",
  "rejectRoute":"vertikaTeknoLokaciptaRejectTask",
  "taskIdField":"tnm",
  "excludeStatus":"load_rejected",
  "text":"…(seg lama)…◆Tolak◆Ada stop nggak searah? Tolak sebelum berangkat, dikembalikan ke Admin."
}
```
Field baru:
| field | arti |
|---|---|
| `rejectRoute` | page RejectTaskSheet (widget baru, spec terpisah `driver-reject-task-sheet-dev-spec.md`) |
| `taskIdField` | field id task (`tnm`); nilainya dikirim sebagai `{rejectTaskVid}` ke reject page |
| `excludeStatus` | status task yang di-DROP dari list (`load_rejected`); lihat §15.5 |

Text +2 segmen di akhir: label tombol ("Tolak") + catatan kaki kartu.

### 15.3 Renderer
1. Render locked: tampilkan daftar task (sudah ada).
2. Tiap baris non-`completed`: tombol "Tolak" di kanan (amber outline).
3. Tap "Tolak" → buka `rejectRoute`, bawa id task (`taskIdField` → `{rejectTaskVid}`).
4. Yang menulis status = RejectTaskSheet (`tst=load_rejected` + evidence), bukan kartu ini. Kartu cuma navigasi.
5. Task `completed` → chip "Selesai", tanpa Tolak.

### 15.4 Catatan penting
- Reject **tidak** mengosongkan `vv` (mobil dipertahankan untuk audit Admin). Itu diatur di reject page.
- Task `tst=load_rejected` hilang dari daftar muatan + dikecualikan dari manifest custody (P5/P6).
- DSL submit reject ada di `driver-reject-task-sheet-dev-spec.md`. Token runtime baru: `{rejectTaskVid}`.

---

## 15.5 ⚠️ RENDERER WAJIB: drop `load_rejected` dari list (`excludeStatus`) — PENDING

**Config `excludeStatus:"load_rejected"`** (ditambah 2026-06-23, live di `Widget!J203`). Renderer **HARUS**: pas render/aggregate list task, **SKIP task yang `tst == excludeStatus`** (`load_rejected`). Task yang ditolak harus **HILANG** dari "Rute Hari Ini" + dari count "N tujuan".

**Kenapa:** reject = task dikembalikan ke Admin, **bukan tujuan driver lagi** → drop dari rute.

**Live (streaming):** pas reject submit flip `task.tst → load_rejected`, task **otomatis drop** (gak perlu refresh). **Sama mekanik kaya `PRECONDITION_GATE_CARD` `excludeStatus`** — yang **UDAH JALAN** di card "Konfirmasi Penerimaan Muatan". DRIVER_STOP_CARD harus implement logika yang sama.

**`failed` ≠ `load_rejected`:** task `failed` (gagal saat eksekusi) **tetap tampil** (relabel "Dilaporkan gagal", §15.3). Cuma `load_rejected` (tolak opening) yang di-DROP.

**Bukti test (2026-06-23):** reject 3 dari 4 task → **manifest udah drop** ke 1 task (renderer manifest jalan), TAPI **route list masih nampil 4** (renderer DRIVER_STOP_CARD belum baca `excludeStatus`). Ini gap yang harus dibenerin.

**Expected setelah implement:** reject 3 dari 4 → "Rute Hari Ini · **1 tujuan**", cuma task non-rejected.

**Default (opt-in filter):** kalau `excludeStatus` **kosong (`""`) atau gak ada** → renderer **TIDAK exclude apa-apa** → tampil SEMUA task (termasuk `load_rejected`). Exclude cuma aktif kalau field-nya diisi. (Sama buat `PRECONDITION_GATE_CARD` `excludeStatus` — konsisten.)
