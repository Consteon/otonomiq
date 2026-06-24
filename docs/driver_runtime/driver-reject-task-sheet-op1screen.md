# Reject Task Sheet -- op1Screen page JSON

Route: `vertikaTeknoLokaciptaRejectTask`

## How to deploy

This is a literal D-cell paste into the op1Screen Google Sheet. Each child is one row (A=route, B=position, C=type, D=component JSON). The page row itself (route cell) must also be created.

1. Create the page row: A = `vertikaTeknoLokaciptaRejectTask`
2. Paste each child below as the D-cell value of its row (B = position 1-4)
3. Republish the proxy Firestore doc

No Widget-col drag is needed (D-cell literal JSON, same pattern as other driver pages).

## Children

### Child 1 -- WORKSPACE_HEADER (position 1)

```json
{"type":"WORKSPACE_HEADER","table":"84214220504259//task","vidtable":"20342033315492","search":"tnm◼{rejectTaskVid}","titleField":"kn","addressField":"al","backRoute":"vertikaTeknoLokaciptaDriverHome","text":"Tolak Task◆Tolak"}
```

**Notes:**
- `search:"tnm◼{rejectTaskVid}"` resolves `{rejectTaskVid}` from `#REJECT_TASK` (dispatched by P4 stop card Tolak tap) via `filterDriverHomeDocs` -> `resolveDriverCurlyTokens`.
- `text` slot [0] = "Tolak Task" (stop label prefix; replaces "Stop" since the reject context does not need stop numbering), slot [1] = "Tolak" (chip label; replaces default "Berjalan" since the task is not running).
- **Known degrade: "Stop N" will not render.** The stopNumber derivation (`_deriveStopNumber`) requires a `{vehicleId}` publisher (via `DriverHomeState.vehicleId`), but this page has no vehicleId publisher widget. The `listSearch` default `vv◼{vehicleId}⭘tdt◼{today}` leaves `{vehicleId}` unresolved, so `filterDriverHomeDocs` returns empty, and stopNumber = 0. The mono line renders just the task ID (e.g. "T-051") without "Stop N". Customer name (`kn`) and address (`al`) still render correctly from the task doc. This degrade is acceptable for v1 -- the driver knows which stop they are rejecting from the P4 card.

### Child 2 -- NOTICE_BAR warn (position 2)

```json
{"type":"NOTICE_BAR","variant":"warn","title":"Tolak Task — Tidak Searah","text":"Task ini dikembalikan ke Admin buat di-assign ke mobil lain. Barang tetap di gudang, nggak naik ke kendaraan lo. Cuma bisa sebelum berangkat."}
```

**Notes:**
- `variant:"warn"` -> amber (statusColor `#D97706` / statusBgColor `#FEF3C7`).
- `title:"Tolak Task — Tidak Searah"` carries the spec §2.1 page heading; notice_bar renders `title` bold above the amber body text (notice_bar.dart:41).
- No `label`, no `icon` -- title + body notice bar. Renders as amber-bg card with left accent bar, bold title, and amber body text.

### Child 3 -- TXF (position 3, alasan textarea)

```json
{"type":"TXF","position":5,"line":3,"border":true,"hint":"Kenapa nggak searah? mis. arah berlawanan, kejauhan…"}
```

**Notes:**
- `position:5` is the form slot for the reason text. The CUSTODY_EVENT_SUBMIT's `gateNotePosition:5` references this slot.
- `line:3` renders a 3-line textarea.
- `border:true` shows the outlined input decoration.
- The hint uses `…` (ellipsis) for "..." in the JSON string.

### Child 4 -- CUSTODY_EVENT_SUBMIT (position 4, gated submit)

```json
{"type":"CUSTODY_EVENT_SUBMIT","table":"84214220504259//task","vidtable":"20342033315492","search":"tnm◼{rejectTaskVid}","gateNotePosition":5,"minNoteLength":10,"updateEventRow":"84214220504259//task⭘tablevid◼20342033315492⭘search◼tnm★{rejectTaskVid}⭘tst◼load_rejected","addToEvent":"84214220504259//evidence⭘r◼4320⭘tablevid◼20342033315492⭘ety◼notes⭘ept◼task⭘erf◼{rejectTaskVid}⭘d◼◁5▷⭘cv◼{driverVid}⭘cn◼{driverName}⭘t◼◀2▶⭘ts◼◀2|T7|Ddd MMM yyyy HH:mm:ss▶","route":"vertikaTeknoLokaciptaDriverHome","text":"Kembalikan ke Admin◆Kembalikan ke Admin◆min 10 karakter","chain":{"type":"DO_DIALOG","title":"Tolak Task","children":[{"type":"TXT","data":"Dikembalikan ke Admin · ga searah"},{"type":"RBT","alignment":"center","children":[{"text":"Ok","route":"vertikaTeknoLokaciptaDriverHome"}]}]}}
```

**Notes:**
- `gateNotePosition:5` + `minNoteLength:10` -- button disabled until alasan TXF (position 5) has >= 10 trimmed characters.
- No `gatePhotoPosition` -- note-only gate (no photo required for reject).
- `text` slots: [0] "Kembalikan ke Admin" (enabled label), [1] "Kembalikan ke Admin" (disabled label), [2] "min 10 karakter" (disabled hint below button).
- `updateEventRow` DSL: searches task doc by `tnm★{rejectTaskVid}`, sets `tst◼load_rejected`. Does NOT touch `vv` (vehicle assignment preserved for Admin audit + re-assign).
- `addToEvent` DSL: creates evidence doc with `ety◼notes`, `ept◼task`, `erf◼{rejectTaskVid}` (reference), `d◼◁5▷` (reason from TXF position 5), `cv◼{driverVid}` + `cn◼{driverName}` (rejecting driver identity), timestamps.
- `route` is the fallback direct-nav target (only used if `chain` is absent/empty -- defensive).
- `chain` is the DO_DIALOG confirmation: title "Tolak Task", body "Dikembalikan ke Admin · ga searah", Ok button routes to DriverHome.
- `table`/`search` are present for the widget's own vehicle_check subscription (reads checkDoc for `{cnm}`). On this page, `{cnm}` is NOT used in the DSL strings, so the subscription result is harmless -- `cnm` will resolve to empty string and no `{cnm}` replacement occurs.

## DSL token resolution chain

| Token | Resolver | Source |
|---|---|---|
| `{rejectTaskVid}` | `resolveDriverCurlyTokens` | `screenTx['#REJECT_TASK']` |
| `{driverVid}` | `resolveDriverCurlyTokens` | `screenTx['#has_user_login']` |
| `{driverName}` | `resolveDriverCurlyTokens` | `DriverHomeState.driverName` |
| `◁5▷` | `replacePlaceholders` (saveSend) | `txfController[scrName][5].finalData` |
| `◀2▶` / `◀2\|T7\|..▶` | `resolveValueTokens` (historySync) | GPS timestamp at sync time |

All curly tokens are pre-resolved by `_resolveCustodyTokens` in the widget before `saveSend`. Position tokens (`◁N▷`) and value tokens (`◀N▶`) are resolved at saveSend/historySync time respectively -- unchanged.
