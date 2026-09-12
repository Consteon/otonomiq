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

## Vertika v6 attendance block (`variant: "v6"`)

Opt-in on the **`HORIZONTAL_ICON` container**, not on the tiles. Absent, blank
or unrecognised, the branch draws the 4-column card grid it always has — which
is what the Checker block on the same screen and every other menu still use.

### Container keys

| Key | Type | Description |
|---|---|---|
| `variant` | `String?` | Only `v6` (trimmed, case-folded) selects the block. |
| `tone` | `String?` | `in` (default, tenant primary family) or `out` (design-system orange family). |
| `text` | `String?` | `◆`-separated, see the slot table below. Blank title hides the head. |
| `vidtable` | `String?` | Firestore container VID for the live meta. Resolved by `resolveAppVid`; set it explicitly — the fallback can read the wrong tenant silently. |
| `table` | `String?` | Event ledger, e.g. `84214220504259//event`. With `search`, makes the meta LIVE. |
| `search` | `String?` | `key◼value⭘…` scope, e.g. `cv◼{userVid}`. Blank ⇒ no subscription and the slot-1 literal stands (fail-closed). |
| `lastAction` | `String?` | Same 5-position grammar TIME_PRESENCE uses: `sortField◆dir◆valueField◆format◆filter`. Position 5 scopes the block to one event type (`ty◼clock-in`) and is AND-ed onto `search` by `composeLedgerSearch`. Absent ⇒ `t◆desc◆t◆HH:mm`. |

### `text` slots

| # | Purpose | Default |
|---|---|---|
| 0 | Block title | *(blank hides the head)* |
| 1 | Literal meta — used only when the meta is **not** live | — |
| 2 | Empty-state sentence for the grid | Belum ada metode absensi aktif. Hubungi admin. |
| 3 | Live-meta prefix | Terakhir |
| 4 | Live-meta word for yesterday | kemarin |
| 5 | Live-meta text when nothing matched | Belum ada |

### Live meta

`table` + `search` together switch the head's right-hand meta from a sheet
literal to the newest matching ledger row, repainting as attendance is recorded:

| Newest match | Rendered |
|---|---|
| Today | `Terakhir 11:38` |
| Yesterday | `Terakhir kemarin 17:04` |
| Older | `Terakhir 3 Sep 17:04` |
| None | `Belum ada` |

The day is decided by `sortField` (always epoch ms), never by `valueField`,
which may legitimately hold text. Both keys blank ⇒ no query at all and the
slot-1 literal stands.

### Tile keys (on each `location` child)

`variant`, `tone` and `row` are **stamped onto the child by the container** —
do not set them in the sheet. The sheet's own optional key is:

| Key | Type | Description |
|---|---|---|
| `subtitle` | `String?` | Caption under the label. **The sheet always wins.** Absent, blank, whitespace-only or the `--` sentinel ⇒ the `opMode` default below, so a tile is never captionless by accident. |

The icon is always the child's own `url` PNG from the sheet, 22 dp — the same
source every other menu tile uses. It is never derived from `opMode` and never
recoloured. Only the caption has an `opMode` default:

| `opMode` | default `subtitle` |
|---|---|
| `qr-single`, `qr-checker-single`, `qr-checker-continuous` | Pindai di pos |
| `qr-selfie` | Pindai, lalu foto |
| `selfie` | Foto wajah |
| `gps-single` | Pakai lokasi |
| anything else | *(none)* |

### Camera screens

`variant: "v6"` also re-skins **both** cameras the tiles push. The block's
slot-0 heading is stamped onto each child as `blockTitle`, and both bars compose
their title the same way — `scannerBarTitle(blockTitle, tileLabel, fallback)` —
so the wording is always the sheet's.

| Tile | Screen | Bar reads | Spec |
|---|---|---|---|
| `qr-single`, `qr-selfie` (step 1) | QR camera | `Absen Masuk · QR`, subtitle = text slot 26 | [ftz_scanner_screen.md](ftz_scanner_screen.md) |
| `selfie`, `qr-selfie` (step 2) | Selfie camera | `Absen Masuk · Selfie`, subtitle = `Ambil foto wajah` → `Periksa foto` | [photo_camera.md](photo_camera.md) |

The selfie screen goes from an `AlertDialog` over the page to a full-screen
route with an oval face frame, a labelled shutter row and an explicit
Ulangi / Gunakan foto step. All three attendance call sites opt in together
(`takePicture`, the `selfie`/`back` branch of `acquireData`, and the qr-selfie
step-4 `acquireCamera`), so a `qr-selfie` tile never mixes a v6 QR screen with a
classic camera.

A block without `variant: "v6"` gets the camera screens it has today, unchanged.
So do the `checker` children of a v6 block, `otq_txf`'s QR field, and every
non-attendance `acquireCamera` caller (timeline, `GET_IMAGES`, OCR).

### Grid shape

Derived from how many children the block has, never configured:

| Methods | Layout | Tile |
|---|---|---|
| 0 | Empty state, 56 dp, muted, warning icon | — |
| 1 | Full width | horizontal, 56 dp |
| 2 | One row | horizontal, 56 dp |
| 3 | One row | vertical, 80 dp |
| 4 | 2×2 | horizontal, 56 dp |
| 5+ | Wraps in pairs | horizontal, 56 dp |

Type and tile heights sit one step below the v6 mockup (which specifies 64 / 92
dp tiles, 15 / 13 type and an 18 / 600 head): on a handset those read oversized,
the same finding the "Absensi hari ini" strip produced. Shipped: head 16 / 600
with 13 / 500 meta, tile label 14 / 600, caption 12 / 600.

### Colour

`tone: "in"` is derived from `Theme.of(context).primaryColor` — the same source
the app bar and the v4 location panel read, so the three cannot drift. The tile
fill lifts that colour's **lightness** in HSL (0.93 fill, 0.84 pressed) with
saturation capped at 0.55; from the production navy that yields `#E3E8F7` /
`#C0CAED`, matching v6's `--color-primary-soft` / `-pressed` to within one step.
An alpha blend does **not** work here: navy at 12 % over white gives `#E0E4EE`,
visibly greyer than the system colour. The label colour is **measured** against
the resulting tint — a tenant primary that misses 4.5:1 steps down to the
foreground rather than shipping unreadable text.

The block also draws a 1 dp `--color-border` rule above its head (`rule: false`
suppresses it), so the flat home sections are separated the way v6 asks without
threading a divider component through the screen JSON.

`tone: "out"` is the design system's orange family and is **not** tenant-derived.
Disabled state wins over both.

Children that are not `location` (a `checker`, a `goto`) keep the classic card
inside a v6 block; only the attendance tile has been re-skinned so far.

Locked by `test/attendance_block_v6_test.dart`.


Both v4/v6 widgets pad themselves up to a **16 dp content edge** via
`otqContentInset()`: the page body is padded by the sheet's
`systemUIComponent['Mobile']['leftPad']` (8 in this workbook) and the design
system asks for 16. It tops up the difference, so raising the sheet value to
16 later makes it a no-op instead of double-padding.

## See Also

- [FtzScannerScreen](ftz_scanner_screen.md) — QR scanner screen pushed via real Flutter Navigator
- [photo_camera.md](photo_camera.md) — Camera widget used by `acquireCamera`
