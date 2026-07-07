# AttendQrGpsSelfie

Multi-mode attendance verification widget: QR scan, GPS geofence, selfie capture, or combinations thereof.

- **File:** [lib/widget/attendance_qr_selfie_gps_verify.dart](../../lib/widget/attendance_qr_selfie_gps_verify.dart)
- **Class:** `AttendQrGpsSelfie` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **SDUI type:** `location`
- **Dispatch:** `build_display_component.dart` line ~938 (single) and ~1015 (horizontal_icon child)

## Purpose

Employee attendance widget rendered from server-driven `type:"location"` component. Supports multiple operation modes via `opMode` field. Handles geofence validation, QR code scanning + verification against `#LQR_LIST`, selfie camera capture, and attendance recording via `addToEvent`/`updateEventRow` through the existing `saveSend` pipeline.

## Signature / Constructor

```dart
AttendQrGpsSelfie({
  required Key key,
  required String scrName,
  required dynamic component,
  required bool single,
})
```

### Parameters

| Param | Type | Required | Description |
|---|---|---|---|
| `key` | `Key` | yes | Unique key per instance |
| `scrName` | `String` | yes | Screen name this widget belongs to |
| `component` | `dynamic` | yes | Component config from server JSON |
| `single` | `bool` | yes | `true` = standalone widget; `false` = child of horizontal_icon |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `type` | `String` | Always `"location"` |
| `opMode` | `String?` | `gps-single` (default), `qr-single`, `selfie`, `qr-checker-single`, `qr-selfie` |
| `url` | `String` | Icon image URL |
| `text` | `String` | Diamond-separated (`◆`) text segments (up to 31 slots) |
| `route` | `String` | Route to navigate after success |
| `flag` | `String` | Flag written to attendance output |
| `imgHeight` / `imgWidth` | `int` | Selfie image dimensions (pixels) |
| `folder` | `String` | Firebase Storage folder path |
| `filename` | `String` | Base filename for captured images |
| `locList` | `List<List<double>>` | Geofence reference points `[[lat,lon],...]` |
| `tolerance` | `int` | Geofence tolerance in meters (default 50) |
| `actionLast` | `String` | Last attendance action: `check-in`, `check-out`, or checkpoint |
| `timeClockOut1` / `timeClockOut2` | `int` | UTC ms window for normal clock-out |
| `fakeGpsAllowed` | `String` | `"TRUE"` or `"FALSE"` |
| `outPositionAllowed` | `String` | `"TRUE"` or `"FALSE"` |
| `addToEvent` | `String` | Event write template |
| `updateEventRow` | `String` | Event update template |
| `quality` | `int` | JPEG quality for camera capture |
| `label` | `String` | Camera dialog title |

## Operation Modes

| Mode | Geofence | QR | Selfie | Write timing |
|---|---|---|---|---|
| `gps-single` | yes | no | no | after GPS |
| `qr-single` | yes | yes (1 attempt) | no | after QR valid |
| `selfie` | yes | no | yes (deferred upload) | after selfie capture |
| `qr-checker-single` | location-based | yes | fallback | after QR or selfie |
| `qr-selfie` | yes (QR step only) | yes (indefinite loop) | yes — direct to camera on QR valid, no confirm dialog (synchronous upload) | after upload succeeds |

## State / Dependencies

- **Redux transactionStore:** reads `#CAMS`, `#LQR_LIST`, `#CAMERA`; writes `#NEXTROUTE`, `#TIMER_CONTEXT`, `#TIMER_DURATION`
- **Part file:** `lib/part/build_part/attend_qr_gps_selfie_state_part.dart` (extension with `attendanceTakeQR`)
- **Side effects:** `saveSend` (history queue), `saveImageToCloud` (qr-selfie only), `routeStack.pop()`

## Important Behavior

- `qr-selfie` is online-required (synchronous upload bypasses the deferred imageMap path).
- Text array is padded to 31 elements via `padTextArray` static method. Index 26 (scanner title) defaults to `'Scan QR'`; index 30 is the final success message. Indexes 27-29 are **reserved (not read by the renderer since r3)** — the QR-success confirmation dialog was removed in favor of going straight to the selfie camera (mirrors `ftz_checker`'s QR-verify → capture flow). The sheet may leave 27-29 empty but must still ship segments up to index 30.
- The `tapped` boolean + `actionLock()` prevent double-tap during async operations.
- All exit paths without a write call `setDataOK('2')` to reset the widget state.
- Upload retry uses a pre-normalized file path (via `renamePath`) so the OTQC camera artifact move is idempotent across retries.

## See Also

- [FtzScannerScreen](ftz_scanner_screen.md) — QR scanner screen pushed via real Flutter Navigator
- [photo_camera.md](photo_camera.md) — Camera widget used by `acquireCamera`
