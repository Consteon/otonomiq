# Failed Delivery — op1Screen page JSON (paste-ready)

**Slug:** `driver-failed-delivery-sheet` · **Route:** `vertikaTeknoLokaciptaFailedDelivery`
**Source spec:** `docs/driver-failed-delivery-sheet-dev-spec.md` (v2.0, 2026-06-23)
**Status:** server config artifact — NOT deployable from the repo. Paste into the Sheets/proxy op1Screen for this route. Until then, the P11 "Lapor gagal" button shows a dead-route snackbar.

> **ZERO Dart change.** All infra already exists and is verified against live source:
> - `SELECTABLE_BTN` `variant:"grid"` writes the selected label to `txfController[scrName][position].finalData` (`selectable_btn.dart`).
> - `CUSTODY_EVENT_SUBMIT` gate (`custody_event_submit.dart:214-241`) reads `txfController[gateNotePosition].finalData` length ≥ `minNoteLength` for ANY position; photo required ONLY if `gatePhotoPosition` is set (omitted here → no photo).
> - `chain`/`doChain` support added by the reject-task work (`custody_event_submit.dart:304-320`).
> - `★` key/value separator inside a `search` clause parsed by `update_event_row.dart:22-40`; `ec`/`d` field assembly is generic (no allowlist).
> - `{failedTaskVid}` resolves via the `resolveDriverCurlyTokens` default-branch bare-key fallback shipped in `rbt-route-params` (`driver_home_support.dart` default branch), written by the P11 button's `routeParams`.

---

## Design decisions (interview-ratified 2026-06-23)

| Topic | Decision | Why |
|---|---|---|
| Page vs sheet (§7.5) | **page route** | mirror RejectTask; default spec |
| Submit widget (§4) | **`CUSTODY_EVENT_SUBMIT`** | spec says "RBT savesend" but only this widget has a required-selection gate + token resolution + chain |
| Required-reason gate (§7.2) | **`gateNotePosition:7` + `minNoteLength:1`** pointed at the SELECTABLE_BTN slot | a selected reason writes a non-empty label (13–15 chars) into slot 7; gate fires. The optional note (slot 5) is NOT gated |
| Photo | **none** (omit `gatePhotoPosition`) | gate passes photo by default when unset |
| GPS (§4 `gpsPosition`) | **dropped** | CUSTODY_EVENT_SUBMIT hardcodes no-GPS locString; doctrine §1/§2 = no movement; reject precedent |
| `ec` value (§7.3) | **label** (e.g. "Customer Tutup") | spec default; queryable per-label for Admin |
| Heading placement | **`NOTICE_BAR.title`** carries "Lapor Delivery Gagal" | WORKSPACE_HEADER shows the customer (`kn`) via `titleField`, not a static title (reject GATE-1 lesson) |

---

## FILL-IN tokens (verify against your sheet before pasting)

These come verbatim from spec §4 — confirm they match your tenant:

- `84214220504259` — task/evidence table **doc id** (the `//task` and `//evidence` container).
- `20342033315492` — `tablevid` = driver container (P4 known vidtable).
- `r◼4320` — evidence dict **row ref** for the `evidence` table.
- `vertikaTeknoLokaciptaTaskFeed` — return route after submit (TaskFeed/DriverHome).
- backRoute below set to `vertikaTeknoLokaciptaTaskFeed`; change to the P11 DeliveryWorkspace route if you want back → P11.

---

## Page children (5, in order)

### 1 — WORKSPACE_HEADER (customer + stop)
```json
{"type":"WORKSPACE_HEADER","table":"84214220504259//task","vidtable":"20342033315492","search":"tnm◼{failedTaskVid}","titleField":"kn","addressField":"al","backRoute":"vertikaTeknoLokaciptaTaskFeed"}
```
> `table`+`vidtable` are REQUIRED: `WorkspaceHeader._subscribe()` (`workspace_header.dart:86-94`) only subscribes when `table` is non-empty. Without them the header shows no customer/address.

### 2 — NOTICE_BAR (warn; carries the page heading)
```json
{"type":"NOTICE_BAR","variant":"warn","title":"Lapor Delivery Gagal","text":"Stop ini dilaporkan gagal → dikembalikan ke Admin buat reschedule. Barang tetap di kendaraan."}
```
> Body prop is `text` (`notice_bar.dart:42`), NOT `data`. (TXT widgets use `data`; NOTICE_BAR uses `text`.)

### 3 — SELECTABLE_BTN grid (reason, REQUIRED, position 7)
```json
{"type":"SELECTABLE_BTN","variant":"grid","title":"PILIH ALASAN","icon":"pin_drop","height":50,"maxGrid":2,"position":7,"bgSelected":"gray","text":"Customer Tutup◆Akses Ditolak◆Customer Tolak◆Kapasitas Penuh"}
```

### 4 — 3-line border form (note, OPTIONAL, position 5)
```json
{"type":"TXF","position":5,"line":3,"border":true,"hint":"Detail tambahan (opsional)…"}
```

### 5 — CUSTODY_EVENT_SUBMIT (gated submit)
```json
{"type":"CUSTODY_EVENT_SUBMIT","text":"Lapor Gagal","gateNotePosition":7,"minNoteLength":1,"route":"vertikaTeknoLokaciptaTaskFeed","updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{failedTaskVid}⭘tst◼failed","addToEvent":"84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{failedTaskVid}⭘ec◼◁7▷⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","chain":{"type":"DO_DIALOG","title":"Delivery Gagal","children":[{"type":"TXT","data":"Dilaporkan gagal · nunggu admin reschedule"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaTaskFeed"}]}]}}
```

**DSL notes:**
- `gateNotePosition:7` → the SELECTABLE_BTN slot. `minNoteLength:1` → any selected reason (≥13 chars) passes; nothing selected → slot 7 empty → button disabled. This IS the "pilih alasan wajib" gate.
- `updateEventRow`: `★` separates key/value inside the `search` clause (`◼` is the pair separator at the outer level). Flips `tst=failed`; `vv` untouched (no `vv` write). No movement.
- `addToEvent`: `ec◼◁7▷` = reason label (slot 7), `d◼◁5▷` = note (slot 5). `cv`/`cn` = reporter. `◁N▷` resolve at sync from form slots; `◀2▶`/`◀2|T7|…▶` are stream time tokens filled from the submit locString (slot 2) at sync — same as reject (no `gpsPosition` needed).
- `chain` DO_DIALOG: the inner "Ok" RBT owns the final nav to TaskFeed; the widget's chain branch does NOT add a second push.

---

## Combined `children` array (single paste)
```json
[
  {"type":"WORKSPACE_HEADER","table":"84214220504259//task","vidtable":"20342033315492","search":"tnm◼{failedTaskVid}","titleField":"kn","addressField":"al","backRoute":"vertikaTeknoLokaciptaTaskFeed"},
  {"type":"NOTICE_BAR","variant":"warn","title":"Lapor Delivery Gagal","text":"Stop ini dilaporkan gagal → dikembalikan ke Admin buat reschedule. Barang tetap di kendaraan."},
  {"type":"SELECTABLE_BTN","variant":"grid","title":"PILIH ALASAN","icon":"pin_drop","height":50,"maxGrid":2,"position":7,"bgSelected":"gray","text":"Customer Tutup◆Akses Ditolak◆Customer Tolak◆Kapasitas Penuh"},
  {"type":"TXF","position":5,"line":3,"border":true,"hint":"Detail tambahan (opsional)…"},
  {"type":"CUSTODY_EVENT_SUBMIT","text":"Lapor Gagal","gateNotePosition":7,"minNoteLength":1,"route":"vertikaTeknoLokaciptaTaskFeed","updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{failedTaskVid}⭘tst◼failed","addToEvent":"84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{failedTaskVid}⭘ec◼◁7▷⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","chain":{"type":"DO_DIALOG","title":"Delivery Gagal","children":[{"type":"TXT","data":"Dilaporkan gagal · nunggu admin reschedule"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaTaskFeed"}]}]}}
]
```

---

## P11 trigger button (DeliveryWorkspace) — add `routeParams`

The "Lapor sebagai gagal" RBT child in the P11 page passes `{failedTaskVid}` declaratively via the `routeParams` field (shipped in `rbt-route-params`):

```json
{"type":"RBT","alignment":"center","children":[{"text":"Tidak bisa dieksekusi · Lapor sebagai gagal","action":"route","route":"vertikaTeknoLokaciptaFailedDelivery","routeParams":"failedTaskVid◼{tnm}"}]}
```

On tap: `{tnm}` resolves to the active task's `#ACTIVE_TASK` value → dispatched as bare key `screenTx['failedTaskVid']` → the FailedDelivery WORKSPACE_HEADER `search:"tnm◼{failedTaskVid}"` resolves it via the resolver default branch.

---

## Deploy checklist
- [ ] `ec` (Evidence Category) field exists in the `evidence` dict (spec §7.1 says added row 11, 2026-06-23) — confirm present.
- [ ] Paste the 5-child array into op1Screen `vertikaTeknoLokaciptaFailedDelivery`.
- [ ] Add `routeParams:"failedTaskVid◼{tnm}"` to the P11 "Lapor gagal" RBT child.
- [ ] Verify table doc id / tablevid / `r` row ref match your tenant.
- [ ] On-device: P10 → task card (sets `#ACTIVE_TASK`) → P11 → "Lapor gagal" → page renders customer + stop, reason grid, gated "Lapor Gagal" → submit flips `tst=failed`, writes evidence, dialog → TaskFeed.
```
