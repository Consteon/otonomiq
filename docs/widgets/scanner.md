# Scanner

In-page rounded viewport card with a **live inline camera** that auto-starts
and auto-detects QR/barcodes. On successful scan:

- If `component['qr'] == 'uqr'`: decrypts the encrypted QR via `getVidUQR`
  to obtain the VID.
- If `qr` is absent, empty, or any other value: uses the raw scan string
  directly as the VID (plain-QR path).

Both paths then store the resolved VID as `#has_user_login`, validate against
the workforce table (local-first with Firestore fallback), write a session
event via saveSend, and navigate to a target route. Decrypt-fail (uqr path)
and workforce-not-found scans show a snackbar and restart the camera for
re-scan. Permission-denied or camera-unavailable renders an inline fallback
with retry inside the same card frame.

- **File:** [lib/widget/scanner.dart](../../lib/widget/scanner.dart)
- **Class:** `Scanner` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1 (round 11 -- optional `routeParams`)
- **Introduced in commit/version:** (pending)

## Purpose

Generic scan-to-event widget for driver session open/resume, scan pegawai/aset,
etc. Unlike `location`/`AttendQrGpsSelfie`, Scanner has NO attendance baggage
(no GPS geofencing, selfie, locList, tolerance, actionLast).

## Signature / Constructor

```dart
Scanner({
  super.key,
  required dynamic component,
  required String scrName,
  double lPad = 0,
  double tPad = 0,
  double rPad = 0,
  double bPad = 0,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | no | -- | Unique key per instance (via `super.key`) |
| `scrName` | `String` | yes | -- | Name of the screen this widget is mounted on |
| `component` | `dynamic` | yes | -- | Component config (see below) |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | no | `0` | System padding |

### Public helpers

```dart
String scannerSlot(List<String> arr, int index, String fallback)
```

Top-level function exported from `scanner.dart`. Length-guarded slot access:
returns `fallback` when `index` is out of range or when the value is empty.
Used by the widget internally and importable by tests.

```dart
String scannerSearchField(String raw)
```

Top-level function exported from `scanner.dart`. Extracts the first search
field name from the component `search` value (multi-field separated by
`★` / U+2605; v1 uses first field only). Returns empty string for
empty/whitespace input.

```dart
Map<String, dynamic> scannerBlankRouteParams(String rawDsl)
```

Top-level function exported from `scanner.dart`. Returns `{key: ''}` for every
key a `routeParams` DSL declares (`autheniumDecode` → `parseRouteParams`).
Dispatched before resolution so an unresolvable key reads as `''` instead of
carrying a previous scan's value. Empty/malformed input → empty map.

```dart
ScannerMatch scannerMatchFromRows(List<Map<String, dynamic>> rows, {required bool needRow})
```

Top-level function exported from
`lib/firestore_repository/scanner_validate.dart`, where
`typedef ScannerMatch = ({bool found, Map<String, dynamic>? row})`. The pure
decision seam for the >1-match rule: empty → not-found; `needRow` and >1 row →
not-found (ambiguous); otherwise found + first row. Unit-tested.

### `component` shape

| Key | Type | Required | Description |
|---|---|---|---|
| `type` | `String` | yes | `"scanner"` |
| `text` | `String` | yes | Diamond-delimited slot string (see slot map below) |
| `url` | `String` | no | Parsed but unused in standalone (no icon overlay) |
| `flag` | `String` | yes | Event flag passed to saveSend |
| `route` | `String` | yes | Page to navigate to after success |
| `routeParams` | `String` | no | `key◼{token}⭘key◼{token}…` — same DSL as `LIST_CARD` / `routeBtn`. Tokens resolve from the **document the validation lookup matched**, then dispatch as BARE screen-tx keys for the destination page. Empty/absent = pre-existing behaviour, byte-for-byte |
| `addToTable` | `String` | yes | Event-write DSL passed to saveSend |
| `qr` | `String` | no | QR decode mode: `"uqr"` = worker card, decrypt via `getVidUQR`; `"lqr"` = location point, decrypt via `lqrVerify`; absent/empty/other = plain (raw scan IS the value) |
| `table` | `String` | yes | Validation table name (e.g. `"workforce"` or `"docId//subColl"`) |
| `search` | `String` | yes | Search field name(s), `★`-separated for multi-field (v1: first only) |
| `width` | `int` | yes | Display width in px (clamped to screen width) |
| `height` | `int` | yes | Display height in px |
| `folder` | `String` | no | Photo folder (v1: parsed, unused) |
| `filename` | `String` | no | Photo filename (v1: parsed, unused) |
| `imgHeight` | `int` | no | Photo height (v1: parsed, unused) |
| `imgWidth` | `int` | no | Photo width (v1: parsed, unused) |
| `opMode` | `String` | no | Fixed "qr-single" in v1 |
| `displayMode` | `String` | no | Informational; renders inline card |
| `beforeSpacing`/`afterSpacing` | `num` | no | Vertical margin |
| `leftPadding`/`rightPadding` | `num` | no | Extra horizontal padding |

### Text slot map (v1, server location-style)

| Index | Meaning | Read | Default |
|---|---|---|---|
| 0 | Card title | yes | `'Scan'` |
| 1 | Card subtitle | yes | `''` |
| 2-6 | (server-reserved) | no | -- |
| 7 | Success snackbar message | yes | `'Berhasil'` |
| 8 | OK label | no | -- |
| 9 | Wrong-result snackbar title | yes | `'QR salah'` |
| 10 | Wrong-result snackbar message | yes | `''` |
| 11 | Retry label | no | -- |

## `routeParams` — carrying the scanned identity to the destination

`scanner` already validates a scan by looking the value up in
`table`/`search`. `routeParams` takes the **document that lookup matched** and
resolves `{token}`s from it, dispatching each pair as a BARE screen-tx key
(no `#` prefix) that the destination page reads. This is the identical
mechanism and identical DSL that `LIST_CARD.routeParams` uses for a tapped
card — the same `writeRouteParamsFromRow` function
(`lib/widget/driver_home_support.dart`) is called.

```
scan          →  0lefc05bc4c884bd590a3a13c8d99663b1dfd371d8
table         →  84214220504259//location
search        →  li
doc matched   →  { li:"0lefc05…", lk:"0lefc05…-32639062303108",
                   ln:"BSD Tech Center #18", sv:"32639062303108", … }
routeParams   →  lk◼{lk}⭘li◼{li}⭘ln◼{ln}
destination   →  screenTx['lk'], screenTx['li'], screenTx['ln']
```

**Why this exists.** `search` on the destination page resolves at page LOAD,
while a `◁N▷` slot is only filled after the operator does something. So any
widget that must READ a document chosen by the scan — `DETAIL_CARD`,
`DIGIT_PAD`, `LIST_CARD` — cannot be served by moving the scan into the
destination page. Tokens are taken from the matched document, never from the
raw QR text, which is also what disambiguates a non-unique `li`: once one
document is selected, the `{lk}` carried points at exactly one row. Every field
of the matched document is available as `{field}`, plus `{__docId}` for the
document's own id — the same token set `LIST_CARD` exposes.

### Rules

- **Empty / absent `routeParams` = pre-existing behaviour, byte-for-byte.** No
  extra query, no extra document read, no change to the local-first path. The
  live `DriverScanLogin` page is unaffected.
- **More than one matching document = FAILURE, but only when `routeParams` is
  non-empty.** The query fetches up to two docs and a 2-doc result shows the
  existing slot-9/10 "QR salah" snackbar, restarts the camera, and does **not**
  route and does **not** write. Silently taking the first document would pick
  an arbitrary site. With `routeParams` empty the query stays `limit(1)` and
  first-match-wins is untouched.
- **Non-empty `routeParams` always resolves the document from Firestore**, even
  when the table happens to be cached locally. The local `#TABLE` cache stores
  POSITIONAL rows with no field names, so `{li}`/`{lk}`/`{ln}` cannot be read
  from it. For a `docId//subColl` table (like `location`) this costs nothing —
  `subscribeToTable` cannot load a subcollection, so that path was always the
  Firestore one.
- **The keys are dispatched BEFORE `saveSend`.** They are therefore also
  resolvable as `<lk>` / `<li>` / `<ln>` markers inside `addToTable` on the
  same scan.
- **Validation skipped (both `table` and `search` empty) = no params.** There
  is no matched document, so there is no token source.
- **A page that declares `routeParams` never auto-skips.** The session gate
  (`_maybeAutoSkip`) normally jumps straight to `route` when
  `#has_user_login` is already set. A `routeParams` scanner exists to PRODUCE
  the identity the destination reads, so skipping it would open that page on
  whatever a previous scan left in the merge-only screenTx. Such a page always
  shows the camera and waits for a real scan.
- Resolution order per value: matched-document fields first, then session
  tokens (`{today}`, `{driverVid}`, …). A pair whose value stays empty or
  still contains `{` is skipped.

### Deploy caveats for the config author

- **Bare keys are a FLAT GLOBAL NAMESPACE for the whole app session.**
  `updateScreenTx` merges and never removes, and `DeleteAllScreenTxRowAction`
  is never dispatched anywhere in `lib/`. Two different screens using the same
  short key name (`li`, `lk`, `ln`, `id`, `name`…) silently overwrite each
  other. Prefix keys when a name could collide.
- **Never use a `routeParams` key to gate visibility or permission.** Carrying
  a display/lookup token is its designed and only safe job.
- **Do not name a key `SCAN_RESULT`.** The widget blanks that marker right
  after `saveSend`, so the value would be wiped before navigation.
- **If a matched document is missing one of the declared fields**, that key is
  blanked rather than left at the previous scan's value, and the destination
  renders EMPTY (`resolveScreenTxTokens` leaves the `{token}` literal for an
  empty value exactly as for an absent key, and `filterByMultiClause` is
  fail-closed). Empty is the intended failure; a stale value would render the
  WRONG document with no visible signal.
- **Separator escapes:** `autheniumDecode` decodes `_25FC_` (→ `◼`) and
  `_u2B58_` (→ `⭘`), but its bare `_2B58_` line is commented out. A sheet
  emitting the legacy bare `_2B58_` form produces ONE pair and silently
  swallows the rest — use the literal `⭘` or `_u2B58_`.
- **A literal `routeParams` value must not contain `{`.** The pending-safe
  guard drops any resolved value that still contains a brace.
- **`search:"li"` is ambiguous on the live `location` data — prefer `lk`.**
  Read 2026-08-19, all 16 documents: 6 of the 7 distinct `li` values appear on
  TWO documents each (same `li`, different `sv`), i.e. 12 of the 13 valid
  points. One pair even carries different `ln` values (BSD Tech Center #17 vs
  #26), so it is two real places sharing an id, not a mirror. With
  `routeParams` set, every one of those scans fails with "QR salah" by design
  (§2.2 of the dev spec — silently choosing one would bill a reading to the
  wrong site). `lk` (`li` + `-` + `sv`) IS unique across all 13. **Fix without
  touching Dart:** print the sticker with `<QRCODE data='{{lk}}'/>` in the
  TitikDetail share-pdf template and set `search:"lk"`, keeping
  `routeParams:"lk◼{lk}⭘li◼{li}⭘ln◼{ln}"`. The deferred alternative is
  multi-field narrowing (`search:"li★sv"`), which the parent spec §2.2 leaves
  open.

## Usage Examples

### Session-open (driver scan login, encrypted QR)

```json
{
  "type": "scanner",
  "text": "Scan kartu ID lo◆Arahkan QR...◆◆◆◆◆◆Berhasil!◆OK◆QR salah◆QR gak cocok. Coba lagi.◆Scan Lagi",
  "flag": "driver-session-open",
  "route": "driverHome",
  "qr": "uqr",
  "table": "workforce",
  "search": "VID",
  "addToTable": "...",
  "width": 600,
  "height": 600,
  "opMode": "qr-single",
  "displayMode": "full-screen"
}
```

### Location scan carrying identity to the destination (`routeParams`)

```json
{
  "type": "scanner",
  "text": "Scan QR Meter◆Arahkan QR di stiker dekat meter ke kamera.◆Titik ditemukan◆Lanjut ke pembacaan◆◆◆◆✔️ Titik terbaca. Lanjut isi angka meter.◆OK◆QR salah◆Stiker ini belum terdaftar sebagai titik meter. Coba scan lagi.◆Scan Lagi",
  "flag": "meter-scan",
  "route": "vertikaTeknoLokaciptaMeterRead",
  "routeParams": "lk◼{lk}⭘li◼{li}⭘ln◼{ln}",
  "qr": "lqr",
  "table": "84214220504259//location",
  "search": "li",
  "com": "con",
  "addToTable": "",
  "width": 300,
  "height": 300,
  "opMode": "qr-single",
  "displayMode": "full-screen"
}
```

The destination `MeterRead` then reads the meter document with
`search: "lk◼{lk}"` on its `DETAIL_CARD` and `DIGIT_PAD`, and writes with
`addToEvent … lq◼{li}⭘ln◼{ln}`.

### Plain QR scan (no decrypt, raw value = VID)

```json
{
  "type": "scanner",
  "text": "Scan Aset◆Arahkan QR ke kamera◆◆◆◆◆◆Berhasil!◆OK◆QR salah◆Aset tidak ditemukan◆Scan Lagi",
  "flag": "asset-scan",
  "route": "assetDetail",
  "table": "assets",
  "search": "assetCode",
  "addToTable": "...",
  "width": 600,
  "height": 600
}
```

## State / Bloc / Dependencies

- **No Bloc/GetX/Redux for widget state.** Processing-in-progress tracked as a `bool _isProcessing` on `_ScannerState`. Camera state managed by `MobileScannerController`.
- **`#has_user_login` (`#`-prefixed Redux transactionStore key):** Resolved VID string. Set on valid scan (after qr-gate: decrypted VID for uqr, raw value for plain). Cleared (set to `''`) when VID not found in workforce table. Kept set on success (widget navigates away). Documented in `documentation.md` "Screen Transaction DataStore Keys".
- **Screen-tx marker `SCAN_RESULT`:** Scanner writes the bare key `'SCAN_RESULT'` (no `#` prefix) to `transactionStore` before calling `saveSend`, then clears it immediately after. Holds the resolved VID (decrypted for uqr, raw for plain). Resolvable as `<SCAN_RESULT>` in the addToTable DSL via `_resolveScreenTxMarkers` (api.dart:3779). It is NOT a `#`-prefixed datastore key and is NOT documented in `documentation.md`.
- **QR gate:** `component['qr']` read as `(component['qr'] ?? '').toString().trim().toLowerCase()`. `'uqr'` = worker-card decrypt via `getVidUQR`; `'lqr'` = location decrypt via `lqrVerify`; anything else = plain path (raw scan IS the value). Mirrors `otq_txf_2.dart:338-356`.
- **Decrypt (uqr):** `getVidUQR(rawQR)` from `lib/crypto/auth_crypto.dart`. Returns `Future<int>`: VID on success, `-1` on failure.
- **Decrypt (lqr):** `lqrVerify(p, q, rawQR)` with `p`/`q` from `omLqrReaderP()`/`osLqrMakerQ()` — the same call shape `getQRContent`'s `qrType == 'L'` branch uses (`api.dart:986-991`), so a location QR that resolves in `otq_txf_2` resolves here. It delegates to `aecDecrypt(qrText, 'l')`, which handles encryption version `'0'` (plaintext) and `'2'` (AEC) and returns `errorString` for anything else.
  - ★ **Off-by-one that this exists to fix.** `aecDecrypt` splits its input as version = `input[0]`, body = `input[1:]`, and returns only the **body** — so a stored `0l<sha1>` code comes back as `l<sha1>`, one character short of the `li` value it must match. `scannerLqrCode()` re-adds the marker. Comparing them raw is what produced the "QR salah" toast.
  - ★★ **The lqr path never touches the driver session.** `#has_user_login` and `persistDriverLogin`/`clearDriverLogin` are skipped (`isLocationScan`, and `_doInvalidNotFound(clearLogin: false)`). A location scan resolves a PLACE; writing it into the login key would replace whoever is signed in, and a failed point scan would sign them out.
- **Hybrid compare:** `scannerVidInWorkforce` (`lib/firestore_repository/scanner_validate.dart`). Returns `ScannerMatch` = `({bool found, Map<String, dynamic>? row})`. Local-first: checks `#TABLE<code>` via `findData` and returns `row: null` (the local row is positional, not named-field); Firestore fallback via `scannerValidateQr` if the table is not loaded. With `needRow: true` (non-empty `routeParams`) the local path is skipped entirely — only Firestore can supply named fields.
- **Validation helper:** `scannerValidateQr` (`lib/firestore_repository/scanner_validate.dart`) -- queries the Firestore `table` collection where the `search` field equals the scan value, and returns `ScannerMatch`. Dual-query (string + numeric) for type safety; the string query short-circuits the numeric one. `needRow: true` raises the limit from 1 to 2 so an ambiguous match is detected. Known deliberate limitation: a cross-type pair (`'123'` in one doc, `123` in another) is not flagged as ambiguous.
- **routeParams dispatch:** `writeRouteParamsFromRow` (`lib/widget/driver_home_support.dart`) -- the SAME function `LIST_CARD`, `PICKER_LIST`, `LIST_ACTION_CARD` and `SIGNAL_LIST` use. Called BEFORE `saveSend`, so the keys are also resolvable as `<KEY>` markers in the `addToTable` DSL.
- **transactionStore (read-only via saveSend):** `#VID`, `#INTERFACE_KEY`, `#SUBMIT_BLOC`, `#TIMER_BLOC` (all via saveSend internally).
- **saveSend:** `lib/api.dart:3787` -- enqueues the event to offline history queue.
- **MobileScanner:** `package:mobile_scanner ^7.2.0` -- inline camera widget with auto-detect.
- **Navigation:** `routeStack.push` + `gotoRoute`.

## Important Behavior

- **QR gate (round 6):** `component['qr'] == 'uqr'` selects the encrypted-URL decrypt path (`getVidUQR`). Absent/empty/other `qr` values select the plain path (raw scan string IS the VID). Both paths then converge on `#has_user_login` store + hybrid workforce compare + success/not-found. This mirrors `otq_txf_2.dart:274-279` where `component['qr']` gates between UQR/LQR/AQR/G modes.
- **Decrypt pipeline (round 5, uqr only):** `onDetect rawQR` -> `getVidUQR(rawQR)` decrypt -> VID int or -1. Decrypt-fail -> "tidak dikenal" snackbar + camera restart. Valid -> vidStr = vid.toString() -> continues to store+compare.
- **Plain pipeline (round 6):** `onDetect rawQR` -> rawQR.trim() = vidStr. Empty -> "tidak dikenal" snackbar + camera restart. Non-empty -> continues to store+compare.
- **Validation gate (round 4, retained):** After the qr-gate resolves vidStr, queries the workforce table. Uses local `findData` if `#TABLE<code>` is loaded (preferred), else Firestore `scannerValidateQr` fallback. Only on FOUND does saveSend + navigate fire. NOT-FOUND or query error shows slot 9/10 snackbar and restarts camera. If BOTH `table` AND `search` are empty, validation is skipped (backward-compatible fail-open). If only ONE of `table`/`search` is set (or `search` resolves to empty), the component is treated as misconfigured and fails closed (clears `#has_user_login`, wrong-result snackbar + re-scan).
- **Live inline camera**: auto-starts on render, no tap needed. Renders inside a rounded card sized from JSON `width`x`height` with neon corner-bracket and scan-line overlays.
- **Auto-detect**: `onDetect` fires on barcode detection; first valid non-empty `rawValue` triggers the qr-gated pipeline.
- **Permission fallback**: if camera permission is denied or unavailable, an inline fallback (icon + message + retry button) renders inside the same card. Tap "Coba Lagi" calls `_cameraController.start()` to retry.
- Length-guards every `diamondTextToList` index via `scannerSlot(arr, N, default)`.
- `routeStack.push(route)` BEFORE `gotoRoute(route)` (Convention #1) -- success path only.
- `mounted` checked after every `await`.
- `_isProcessing` flag prevents multiple barcode detections from triggering parallel submit paths.
- Camera stopped immediately on first valid detection (resource release).
- saveSend internally calls `autheniumDecode` on the addToTable string -- scanner does NOT double-decode.
- Photo fields (folder, filename, imgHeight, imgWidth) are parsed but unused in v1.
- `url` field parsed but not rendered (standalone mode).

## See Also

- [ftz_scanner_screen.md](ftz_scanner_screen.md) -- full-screen scanner (used by otq_txf, attendance, ftz_checker; NOT used by Scanner)
- [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md) -- the attendance version (GPS + selfie + geofencing)
