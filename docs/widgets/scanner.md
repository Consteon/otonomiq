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
- **Widget version:** v1 (round 6 -- qr-gate + import fix)
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

### `component` shape

| Key | Type | Required | Description |
|---|---|---|---|
| `type` | `String` | yes | `"scanner"` |
| `text` | `String` | yes | Diamond-delimited slot string (see slot map below) |
| `url` | `String` | no | Parsed but unused in standalone (no icon overlay) |
| `flag` | `String` | yes | Event flag passed to saveSend |
| `route` | `String` | yes | Page to navigate to after success |
| `addToTable` | `String` | yes | Event-write DSL passed to saveSend |
| `qr` | `String` | no | QR decode mode: `"uqr"` = decrypt via getVidUQR; absent/empty/other = plain (raw scan = VID) |
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
- **QR gate:** `component['qr']` read as `(component['qr'] ?? '').toString().trim().toLowerCase()`. `'uqr'` = decrypt path via `getVidUQR`; anything else = plain path (raw scan = VID). Mirrors `otq_txf_2.dart:274-279`.
- **Decrypt (uqr only):** `getVidUQR(rawQR)` from `lib/crypto/auth_crypto.dart` (gitignored secret). Returns `Future<int>`: VID on success, `-1` on failure.
- **Hybrid compare:** `scannerVidInWorkforce` (`lib/firestore_repository/scanner_validate.dart`). Local-first: checks `#TABLE<code>` via `findData`; Firestore fallback via `scannerValidateQr` if table not loaded.
- **Validation helper:** `scannerValidateQr` (`lib/firestore_repository/scanner_validate.dart`) -- queries Firestore `table` collection where `search` field equals scan value. Dual-query (string + numeric) for type safety.
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
