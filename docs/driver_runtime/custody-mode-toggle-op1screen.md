# Custody Mode Toggle — op1Screen page JSON (paste-ready)

**Slug:** `custody-mode-toggle` · **Route:** `vertikaTeknoLokaciptaCustodyAck`
**Source spec:** `custody-mode-toggle-dev-spec.md` (rev1, 2026-08-07)
**Status:** server config artifact — NOT deployable from the repo. Paste into the Sheets/proxy op1Screen for this route. Until then, the Mode B CTA shows a dead-route snackbar (`'Layar belum tersedia'`).

> **ZERO Dart change.** All infra already exists and is verified against live source:
> - `VEHICLE_CUSTODY_HEADER` publishes `{vehicleId}` into DriverHomeState (`vehicle_custody_header.dart:146-151`).
> - `CIRCULATION_SUMMARY` reads task `it[]` and sums per item; `excludeStatus` filters by raw `tst` (`circulation_summary.dart`).
> - `DRIVER_STOP_CARD` with empty `gateSearch` always renders `_buildPending` (Tolak buttons visible) (`driver_home_support.dart:725`).
> - `OTQ_GET_IMAGES_2` stores captured images in `txfController[scrName][position].finalData` (`otq_get_images_2.dart`).
> - `CUSTODY_EVENT_SUBMIT` is ungated (true 1-tap) when BOTH `gateNotePosition` and `gatePhotoPosition` are absent (`custody_event_submit.dart:216`).
> - `updateEventRow` search uses `★`/`☆` inside the `search◼` clause, NOT `◼`/`⭘` (`docs/firestore/update_event_row.md` line 13; parser `parseUpdateEventRow`).

> **WARNING (spec §7b): Enabling Mode B before `custody_confirm.go` deploys the `ip`-absent guard zeroes the vehicle's `asset_cache`.** This page is safe to paste at any time; the destructive path is flipping the tenant dropdown to B without the CF guard live.

---

## How to deploy

This is a literal D-cell paste into the op1Screen Google Sheet. Each child is one row (A=route, B=position, C=type, D=component JSON). The page row itself must also be created.

1. Create the page row: A = `vertikaTeknoLokaciptaCustodyAck`
2. Paste each child below as the D-cell value of its row (B = position 1–5)
3. Republish the proxy Firestore doc

No Widget-col drag is needed (D-cell literal JSON, same pattern as other driver pages).

---

## Dependencies (verify before flipping dropdown to Mode B)

- [ ] `custody_confirm.go` guard deployed: `if len(ParseCustodyLines(f, fieldIp)) == 0 { return nil }` — Mode B writes NO `ip`, so without this guard `custodyAdjustments(ie, nil)` zeroes asset_cache.
- [ ] `resolveAmbiguousEventTarget` committed and deployed (parked in `lib/firestore_repository/table_repository.dart:1614`, currently uncommitted).
- [ ] Reject task page (`vertikaTeknoLokaciptaRejectTask`) pasted in op1Screen — the DRIVER_STOP_CARD Tolak button navigates to it.

---

## Children

### Child 1 -- VEHICLE_CUSTODY_HEADER (position 1)

```json
{"type":"VEHICLE_CUSTODY_HEADER","table":"84214220504259//vehicle_check","vidtable":"20342033315492","search":"cty◼opening⭘vv◼{vehicleId}⭘cdt◼{today}","vehicleTable":"84214220504259//stock_location","text":"Muatan◆Dimuat oleh◆Waktu loading◆Custody ID"}
```

**Notes:**
- **Load-bearing: this is the page's `{vehicleId}` publisher.** Without it, every other widget's `{vehicleId}` token stays unresolved and renders blank. This was the P5 r1 Critical — the driver page with no vehicleId publisher rendered every widget blank.
- `table` + `search` find the vehicle_check opening doc for display (plate, cnm, loader info).
- `vehicleTable` subscribes to `stock_location` for the vehicle doc lookup (`lt=='vehicle' && dv==driverVid`).
- `vidtable` is REQUIRED — `resolveAppVid` reads it for the Firestore subscription path.

### Child 2 -- CIRCULATION_SUMMARY (position 2)

```json
{"type":"CIRCULATION_SUMMARY","table":"84214220504259//task","vidtable":"20342033315492","search":"vv◼{vehicleId}⭘tdt◼{today}","excludeStatus":"load_rejected","text":"Muatan◆Muat◆Total Drop◆Total Pickup◆Jumlah rencana, sesuaikan sama kondisi lapangan"}
```

**Notes:**
- Shows what the driver is carrying. Sums `pd` (planned drop) and `pp` (planned pickup) per item across all tasks.
- `excludeStatus:"load_rejected"` drops rejected tasks from totals — driver sees only what they are actually carrying.
- `text` slots: [0] title, [1] muat column header, [2] drop footer, [3] pickup footer, [4] italic note.
- `{vehicleId}` resolves after VEHICLE_CUSTODY_HEADER publishes it (child ordering matters — this MUST come after the header).

### Child 3 -- DRIVER_STOP_CARD (position 3)

```json
{"type":"DRIVER_STOP_CARD","table":"84214220504259//task","vidtable":"20342033315492","search":"vv◼{vehicleId}⭘tdt◼{today}","rejectRoute":"vertikaTeknoLokaciptaRejectTask","excludeStatus":"load_rejected","text":"Stop Berikutnya◆Dilaporkan Gagal◆Sudah Selesai◆Pilih sesuai kondisi lapangan◆Mulai Eksekusi◆Selesai◆Customer confirmed◆Dilaporkan gagal — menunggu admin reschedule◆kirim◆ambil◆Pickup Only◆Tujuan Hari Ini◆{closed} dari {total} stop◆lanjut:◆semua kelar◆{total} tujuan◆Tolak task di bawah sebelum terima muatan — ini tujuan lo hari ini:◆Buka Tasklist (eksekusi)◆Tolak◆Ada stop nggak searah? Tolak sebelum terima muatan, biar dikembalikan ke Admin."}
```

**Notes:**
- **`gateSearch` is intentionally ABSENT (empty).** `evaluateGateSearch()` returns false when `rawGateSearch.trim().isEmpty` (`driver_home_support.dart:725`), so the card ALWAYS takes `_buildPending`. This keeps the Tolak buttons visible — spec section 4.2a-2 requires reject pre-custody.
- **`gateTable` is also absent** — no gate subscription needed since the card never evaluates the gate.
- `rejectRoute` points to the existing reject task page. On Tolak tap, the widget dispatches `#REJECT_TASK` with the task VID and navigates to the reject sheet. If the reject page is not yet deployed, a dead-route snackbar appears (`'Layar belum tersedia'`). **Reject flow:** the reject sheet's chain returns to **DriverHome**, not back to this ack page — the driver re-enters via the PRECONDITION_GATE_CARD CTA.
- `excludeStatus:"load_rejected"` is explicit (an empty string would also default to `load_rejected` via `kDefaultExcludeStatus` in `driver_stop_card.dart:110`, but explicit is clearer).
- `text` has 20 diamond-delimited slots (0–19). Slots 11, 15, 16, 18, 19 are used in pending mode. Slot [16] is adapted for ack context: "Tolak task di bawah sebelum terima muatan — ini tujuan lo hari ini:" (original DriverHome P4: "Konfirmasi muatan dulu buat mulai"). Slot [19] adapted: "...Tolak sebelum terima muatan..." The builder MAY adjust these labels.
- **No `{activeTrip}` on this page.** `{activeTrip}` is published only as a side-effect of `evaluateGateSearch` (`driver_home_support.dart:734`), and this card has no `gateSearch`/`gateTable`, so the publisher never fires. `DriverHomeState` is keyed per `scrName`, so DriverHome's resolved value does not carry to this screen. Do NOT add `tr◼{activeTrip}` to the search — the token would stay unresolved and `filterDriverHomeDocs` would return empty, blanking the stop card entirely. For multi-trip tenants, trip scoping is handled by the `cst★awaiting_custody` clause on the submit's `updateEventRow`, which already narrows to the active opening.

### Child 4 -- GET_IMAGES (position 4, form position 5)

```json
{"type":"GET_IMAGES","position":5,"label":"Foto Muatan","imageParameter":"800,600,80","folder":"custody","filename":"ack"}
```

**Notes:**
- `position:5` — form slot 5, aligned with both precedent driver sheets (`driver-reject-task-sheet-op1screen.md` TXF at `position:5`; `driver-failed-delivery-sheet-op1screen.md` TXF at `position:5`), keeping low slots free.
- Photo data stored in `txfController[scrName][5].finalData`.
- The CUSTODY_EVENT_SUBMIT's `addToEvent` references this slot via `◁5▷`.
- Photo is OPTIONAL — the submit button has no `gatePhotoPosition`, so it works with or without a photo.
- `source` absent = camera (default). Add `"source":"gallery"` if gallery is desired.
- `label:"Foto Muatan"` is the camera screen title.

### Child 5 -- CUSTODY_EVENT_SUBMIT (position 5)

```json
{"type":"CUSTODY_EVENT_SUBMIT","text":"✓ Terima & Berangkat","updateEventRow":"84214220504259//vehicle_check⭘tablevid◼20342033315492⭘search◼cty★opening☆vv★{vehicleId}☆cdt★{today}☆cst★awaiting_custody⭘cst◼custody_confirmed⭘dv◼{driverVid}","addToEvent":"84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼photo⭘ept◼custody⭘erf◼{vehicleId}⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","route":"vertikaTeknoLokaciptaDriverHome","chain":{"type":"DO_DIALOG","title":"Muatan Diterima","children":[{"type":"TXT","data":"Konfirmasi diterima · muatan jadi tanggung jawab driver"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaDriverHome"}]}]}}
```

**Notes:**
- **Ungated:** `gateNotePosition` and `gatePhotoPosition` both ABSENT -> `_evaluateGate()` returns true unconditionally (`custody_event_submit.dart:216`). Button is always enabled.
- **`text`:** single value "✓ Terima & Berangkat" (no diamond delimiter needed — only slot [0] matters for an always-enabled button).
- **No `table`/`search`/`vidtable`:** the ack page does not use `{cnm}` in any DSL string, so no vehicle_check subscription is needed. `vidtable` for the DSL is carried inline as `tablevid◼20342033315492`.
- **`updateEventRow` DSL breakdown:**
  - `84214220504259//vehicle_check` — target collection
  - `tablevid◼20342033315492` — Firestore path vid
  - `search◼cty★opening☆vv★{vehicleId}☆cdt★{today}☆cst★awaiting_custody` — 4-clause AND search. The `cst★awaiting_custody` clause ensures idempotency: after first submit flips `cst`, a re-tap's sync finds 0 matches and skips harmlessly.
  - `cst◼custody_confirmed` — field to write
  - `dv◼{driverVid}` — field to write (driver identity for audit trail)
  - **Does NOT write `ip`.** `ip` ABSENT is load-bearing: it tells the CF guard to skip `custodyAdjustments` and preserve `asset_cache = ie`.
- **`addToEvent` DSL breakdown:**
  - `84214220504259//evidence` — evidence subcollection
  - `r◼4320` — evidence dict row ref
  - `tablevid◼20342033315492` — Firestore path vid
  - `ety◼photo` — evidence type
  - `ept◼custody` — evidence parent type
  - `erf◼{vehicleId}` — evidence reference (vehicle id)
  - `d◼◁5▷` — photo data from GET_IMAGES form position 5 (may be empty if no photo taken). `◁5▷` resolves to form position 5: `parseEventString` yields `ref[1][0]` = position 1, and `resolveValueTokens` indexes `ref[1][N-1]` (`table_repository.dart:1411`), so the `-1` cancels and `◁N▷` = position N. No `+1` adjustment.
  - `cv◼{driverVid}` — confirming driver vid
  - `cn◼{driverName}` — confirming driver name
  - `t◼◀2▶` — timestamp (sync-time system token)
  - `ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶` — formatted timestamp
- **`chain`:** DO_DIALOG confirmation: "Muatan Diterima" title, "Konfirmasi diterima · muatan jadi tanggung jawab driver" body, Ok button -> DriverHome. The chain's inner RBT handles final navigation; the widget does NOT add a second `routeStack.push`.
- **`route`:** fallback direct-nav target (only used if `chain` is absent/empty — defensive).

---

## Section 2 — custodyMode setting-cell spec

**Where:** 1 cell in the tenant config tab (e.g. `auzSettings` or equivalent for VTL).

| Cell | Dropdown values | Default |
|---|---|---|
| `custodyMode` | `A`, `B` | `A` |

**Data validation:** List of items `A,B`. Cell note (visible to builder):
```
A = driver hitung (count flow). B = driver terima tanpa hitung (ack flow).
⚠ B butuh CF guard custody_confirm.go live dulu — tanpa guard, asset_cache mobil ke-ZERO.
```

This is an owner flip. No dev needed. No regeneration needed on change (the formula evaluates at page-build time from the proxy cache).

---

## Section 3 — DriverHome PRECONDITION_GATE_CARD formula recipe

On the DriverHome(617) row's D-cell component JSON, modify exactly TWO values. All other JSON keys and text slots MUST be left byte-identical.

**1. `route` field — in-place replacement:**

Find the existing `"route":"..."` key in the D-cell JSON. Replace only its value with an IF formula referencing the custodyMode setting cell. The existing route value (whatever the cell holds today — do NOT retype from memory) becomes the Mode A branch:

```
"route":"=IF($custodyMode=""B"",""vertikaTeknoLokaciptaCustodyAck"",""<current route value>"")"
```

**2. `text` field — in-place edit of slot [3] ONLY:**

The `text` value is a 9-slot `◆`-delimited string. Slots 0–2 and 4–8 MUST NOT be touched. Find slot [3] (the fourth segment between `◆` delimiters) — its current value is `Konfirmasi Penerimaan`. Replace only that segment with an IF formula:

```
<slot 2 unchanged>◆=IF($custodyMode=""B"","Terima & Berangkat","Konfirmasi Penerimaan")◆<slot 4 unchanged>
```

The widget appends ` →` to the CTA label automatically (`precondition_gate_card.dart:570`), so:
- Mode A: "Konfirmasi Penerimaan →"
- Mode B: "Terima & Berangkat →"

**No other fields change.** Gate logic, items display, confirmed/pending state — all identical in both modes. The mode flip is purely a route + label swap.

---

## DSL token resolution chain (ack page)

| Token | Resolver | Source |
|---|---|---|
| `{vehicleId}` | `resolveDriverCurlyTokens` | `DriverHomeState.vehicleId` (published by VEHICLE_CUSTODY_HEADER on this page) |
| `{today}` | `resolveDriverCurlyTokens` | `todayEpochMidnightWib()` |
| `{driverVid}` | `resolveDriverCurlyTokens` | `screenTx['#has_user_login']` |
| `{driverName}` | `resolveDriverCurlyTokens` | `DriverHomeState.driverName` |
| `◁5▷` | `resolveValueTokens` (historySync) | `txfController[scrName][5].finalData` (photo data from GET_IMAGES) |
| `◀2▶` / `◀2\|T7\|..▶` | `resolveValueTokens` (historySync) | GPS timestamp at sync time |

---

## Deploy checklist

- [ ] Verify table doc id `84214220504259` and vidtable `20342033315492` match your tenant.
- [ ] Verify evidence dict row ref `r◼4320` matches your tenant's evidence table.
- [ ] `custody_confirm.go` CF guard deployed (section Dependencies).
- [ ] `resolveAmbiguousEventTarget` committed and deployed.
- [ ] Reject task page (`vertikaTeknoLokaciptaRejectTask`) pasted in op1Screen.
- [ ] Create page row A = `vertikaTeknoLokaciptaCustodyAck` in op1Screen, then paste each of the 5 children as D-cell values with B = 1–5 (one row per child).
- [ ] Add IF formulas to DriverHome(617) PRECONDITION_GATE_CARD `route` + `text` slot [3] per Section 3 recipe.
- [ ] Add `custodyMode` dropdown cell to tenant config tab.
- [ ] On-device: with `custodyMode=A`, verify existing count flow unchanged (regression).
- [ ] On-device: flip `custodyMode=B`, tap CTA -> ack page renders: header (vehicle info), manifest (items), stop card (with Tolak), photo widget, submit button -> tap submit -> dialog "Muatan Diterima" -> Ok -> DriverHome. Opening doc has `cst=custody_confirmed`, `dv` set, NO `ip`.
