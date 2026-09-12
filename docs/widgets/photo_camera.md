# PhotoCamera

`lib/widget/photo_camera.dart`

The app's only still camera. Not an SDUI component — no `type` dispatches to it;
callers reach it through `acquireCamera()` (raw path back) or
`getPhotoCameraImage()` (path uploaded/queued and a URL back).

## Callers

| Caller | Entry | Screen |
|---|---|---|
| Attendance selfie (`type: "location"`) | `attendance_qr_selfie_gps_verify.dart` ×3 | classic, or **v6** when the block opts in |
| Timeline evidence | `timeline.dart` | classic |
| `GET_IMAGES` v2 | `otq_get_images_2.dart` | classic |
| OCR capture | `ocr_capture.dart` | classic (+ `preset: high`, `guideRatio`) |

`lib/part/{ios,android}_part/attendance_qr_selfie_gps_verify.dart_` are legacy
hand-swap copies. They are **not compiled** and have not been updated.

## Parameters

| Param | Type | Default | Description |
|---|---|---|---|
| `cameras` | `List<CameraDescription>` | required | From `ensureCams()`. |
| `label` | `String?` | `null` | Dialog title (classic); v6 bar fallback. |
| `direction` | `int?` | `0` | Index into `cameras`; `getCameraIndex` maps `'front'`/`'back'`. |
| `maxSize` / `quality` | `int?` | `500` / `80` | Watermark-bake resize + JPG quality. |
| `preset` | `ResolutionPreset?` | `medium` | `high` for OCR. |
| `guideRatio` | `double?` | `null` | Centred guide box over the preview (OCR). |
| `variant` | `String` | `''` | `v6` (trimmed, case-folded) selects the v6 selfie screen. Anything else keeps the classic tree. |
| `barTitle` | `String` | `''` | v6 bar title, e.g. `Absen Masuk · Selfie`. Blank falls back to `label`. |

The captured path comes back through the `imageUrl` list the caller passes in;
`acquireCamera` returns `imageUrl[0]`, empty when the user cancelled.

## Classic

`Get.dialog(AlertDialog(title: label, content: PhotoCamera(...)))` — a sheet over
the page it was opened from, with four unlabelled icons (flash cycle, shutter,
flip, then ✕ / ✓). Unchanged; every caller that does not pass `variant: "v6"`
still gets exactly this.

## `variant: "v6"` — the Vertika v6 selfie screen

Opted into by the attendance block (`horizontal_icon` with `variant: "v6"`);
see [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md).
It uses the **same skeleton** as the v6 QR camera
([ftz_scanner_screen.md](ftz_scanner_screen.md)) — bar over the scrim, frame,
one live-region hint, white bottom sheet — so a guard who has scanned a QR
already knows this screen.

`acquireCamera` pushes it as a **full-screen route** (`Get.to`) rather than a
dialog. v6's first finding about the old screen was that a sheet leaves the page
behind it visible under a generic "Camera" title, with no clue which action the
photo belongs to.

**Bar** — 56 dp, one close button (cancel, always). Title from
`scannerBarTitle(blockTitle, tileLabel, label)`, the same composition the QR bar
uses, so both read `Absen Masuk · Selfie` / `Absen Pulang · QR + Selfie` in the
sheet's own words. Subtitle is **state**, not a parameter: `Ambil foto wajah` →
`Periksa foto`.

**Oval** — sized from the **screen**, not from a fixed dp box: 77 % of the
width (300 dp on a 390 dp phone), clamped to 280–340 dp, height 1.27× the
width. That is face *plus shoulders*: on an attendance selfie the uniform and
the post behind it are half the evidence, so the frame has to hold them.

It sits 32 dp under the bar. `selfieOvalRect()` places it — the gap collapses
first and only then does the oval shrink, ratio held, floored at 170 dp wide.
Locked by `test/selfie_v6_test.dart`.

**Scrim — 35 %, not the QR screen's 62 %.** The oval reads as a guide, not a
mask; what surrounds the face stays legible. That alone would put white text at
**2.23:1**, so the same painter lays a stronger veil behind the bar and behind
the hint, and *only* there — neither band reaches the oval, so the shoulders and
the background keep their 35 %. The ring is white over a dark halo, because a
bare white line on a 35 % scrim over a white wall is 2.23:1 too, under the 3:1 a
graphical guide owes.

The preview is scaled to **cover** (`FittedBox` over a `SizedBox` sized from
`controller.value.aspectRatio`). `CameraPreview` is an `AspectRatio`, so filling
a Stack with it letterboxes — and the oval, positioned against the screen, would
then sit partly on a black bar.

**Controls** — a white sheet, `1fr · auto · 1fr`:

| Control | Size | Behaviour |
|---|---|---|
| Kilat layar / Kilat | 56 dp, icon 22 + label 12/600 | Toggle. On the **front** lens there is no flash, so it whitens the screen for 300 ms at the shutter instead; the label says which one it is. |
| Shutter | 72 dp circle, 4 dp `primaryColor` ring, 56 dp fill | One `HapticFeedback.mediumImpact()`, then the review step. |
| Balik kamera / Kamera belakang | 56 dp | Lens picked via `getCameraIndex`, not "index 0 or 1" — a phone with two back lenses lands on the wrong one otherwise. Front is the default and is not remembered. |

**Review** — the shot is shown **whole**, filling the screen with the oval and
the base scrim gone: the oval decides *sudah pas atau belum* while framing, it
never crops, and what gets uploaded is the full frame. An oval cut-out here
would have the guard approve an image that is not the one that gets sent. The
hint asks *Wajah terlihat jelas?*, and the sheet swaps to two
52 dp buttons: **Ulangi** (tonal) and **Gunakan foto** (the one filled accent
element on the screen). That replaces the classic ✕/✓ pair, where ✕ could mean
either cancel or delete and ✓ was disabled before the shot with nothing said.

`Gunakan foto` awaits the watermark bake — normally already finished behind the
preview — showing a spinner in the button when a slow device is still working.

**States the screen owns** — exactly two:

| State | Frame | Hint |
|---|---|---|
| capture | 35 % scrim, white ring over a dark halo | *Posisikan wajah di dalam bingkai* (front) / *Kamera belakang aktif* (back) |
| review | full photo, no scrim, no ring | *Wajah terlihat jelas?* |

It stops there. **The screen never says "terkirim" or "berhasil"** — the upload,
the offline queue, the geofence checks and the attendance write all live in the
caller (`getPhotoCameraImage` → `prepareImageAsLocal`, or the qr-selfie path's
`saveImageToCloud` retry loop). A screen that cannot promise the send is a
screen that would have to take the promise back.

**Camera error** — two different failures reach the same place and need
opposite advice, so the screen names which one:

| Cause | Copy | CTA |
|---|---|---|
| `CameraException` code containing `accessdenied` / `restricted` | *Kamera belum diizinkan* | Buka pengaturan (`openAppSettings()`) |
| anything else — camera still held by another process, wedged service | *Kamera tidak bisa dibuka* | Coba lagi (re-runs `initializeCamera`) |

Sending a guard to Settings for a busy camera wastes the walk; a wedged camera
usually clears on its own.

While it is still opening, the screen is a solid `#0F172A` with a spinner and a
caption — *Menyiapkan kamera…*, then *Kamera masih dipakai proses lain, mencoba
lagi…* once an attempt has failed. A camera open on this hardware has been
logged taking 4.2 s legitimately, so the wait has to be explicable rather than
short.

### Contrast

Worst realistic case — a fully white scene behind the overlay:

| Element | Composite | Ratio | Bar |
|---|---|---|---|
| White hint title 16/600 | veil band, 62 % | 5.02:1 | 4.5:1 ✔ |
| Hint body, white @ 92 % | veil band, 62 % | 4.54:1 | 4.5:1 ✔ |
| White bar title 17/600 | veil band, 62 % | 5.02:1 | 4.5:1 ✔ |
| Oval ring, white on its halo | ink @ 55 % | 3.99:1 | 3:1 (non-text) ✔ |
| `Gunakan foto` — `#1A1206` on `#F08118` | — | 6.94:1 | 4.5:1 ✔ |
| `Ulangi` — `#0F2A33` on `#EEF0F4` | — | 13.2:1 | 4.5:1 ✔ |

★ **The 35 % scrim is why the veils exist.** White text straight on it measures
**2.23:1** and a bare white ring the same. The base is 35 % because the
surroundings are evidence; the veils buy the text back the 62 % composite the
QR screen already measures, without ever touching the oval.

Same deliberate deviation as the QR screen: v6 writes the hint body at 86 %
white (4.22:1, under the 4.5:1 a 14 dp line owes); shipped at 92 %.

## Not done

- **No face detection.** The fit rule is specified — a face counts as framed
  when its height is ≥ 45 % of the oval's height — but nothing produces a face
  box yet. It needs `google_mlkit_face_detection`: a new native dependency and
  model on every white-label build, plus a `startImageStream` running against
  `takePicture` on the low-end phones this app targets. Until it lands the ring
  never turns green and the shutter is never gated; the explicit review step is
  what catches the ceiling photo, since the guard sees the ceiling and taps
  **Ulangi**.
- **No send / success / face-mismatch state**, for the reason above — those
  frames belong to the caller.
- **Hint microcopy is hardcoded Indonesian** (6 strings), not sheet-driven.
- **`Kilat layar` uses the phone's current brightness.** Raising it for the
  300 ms needs a plugin (`screen_brightness`).
- Timeline, `GET_IMAGES` and OCR still get the classic dialog even inside a v6
  block.

## Gotchas

- ★★★ **`initialize()` succeeding does not mean the camera opened.**
  `initializeCamera` binds the use cases (`bindToLifecycle`) and returns; it
  never waits for the physical camera. CameraX reports the real failure later on
  `onCameraError`, and the plugin lands it in `value.errorDescription`
  **without clearing `value.isInitialized`**
  (`camera-0.12.0+1/lib/src/camera_controller.dart:359-365`). A guard that only
  asks `isInitialized` therefore renders `CameraPreview` on a dead camera — a
  texture that never receives a frame, i.e. a **black preview with no error
  anywhere**. Worse, nothing rebuilt when the error landed: only
  `onNewCameraSelected` attached a listener, and the open path never goes
  through it. `_newController` now attaches one, `_cameraDead` reads
  `value.hasError`, and both trees refuse to draw a preview on it.
- ★★ **A second, different way it never finishes:** `initialize()` awaits
  `initializeCompleter`, fed by `onCameraInitialized`. If CameraX never gets far
  enough to emit that event the Future does not settle at all, so each attempt
  is bounded (6 s on the first, 3 s after) and the timeout is raised as a
  `CameraException`. Device logs for the wedged case read `Unknown camera ID 0`,
  `onError 4` (`ERROR_CAMERA_DEVICE`), then
  `Timeout expired, retrying camera open for camera CameraId-0` without end.
- ★★★ **Giving up must UNBIND, or CameraX never stops.** A failed open is not
  final to CameraX: it logs `Failed to open camera CameraId-N after 21 attempts`
  and then `Restarting Camera2CameraController(CameraGraph-N)...`, forever. On a
  device log that is a single CameraGraph churning through VirtualCamera-7..-14
  while the Flutter isolate sits idle behind the empty state. The retry keeps a
  client bound to a camera service that is already refusing, so nothing can
  recover and the NEXT screen inherits the wedge — QR black, then selfie black.
  `_doInitializeCamera` disposes the controller before it rethrows.
- ★★ **Hardware contention with the QR scanner is the usual cause.** One back
  camera, two plugins: `mobile_scanner` for QR, `camera` for the selfie, and
  the attendance flow runs them back to back. `FtzScannerScreen` now releases
  the camera *before* it pops rather than in `dispose()` (which runs only after
  the pop transition). See
  [ftz_scanner_screen.md](ftz_scanner_screen.md) and the 500 ms settle in
  `doQrSelfieFlow`.
- ★ **`_shotId`.** The watermark bake runs *behind* the preview, so a v6
  retake can start while the discarded shot is still being processed. Without
  the token the late bake finishes last and points `currentImage` back at the
  photo the user threw away — and `Gunakan foto` sends it. Bumped on every
  shutter press and every `Ulangi`; `_finalizeCapture` only assigns when it
  still matches.
- ★ `CameraController.dispose()` does **not** reset `value.isInitialized` — see
  `_disposedController`, and `project_camera_dispose_surface_producer_fatal`.
- `flashIndex` stays the single source of truth for the flash. v6 only ever
  parks it at 1 (`always`) or 3 (`off`), so the "restore flash after the shot"
  path is correct for both trees.

## Tests

- `test/selfie_v6_test.dart` — 10 tests over `selfieOvalRect`.
- `test/photo_camera_process_image_test.dart` — the watermark/resize isolate.

The screen itself cannot be pumped: `PhotoCamera` reaches for the camera plugin
and this repo carries no mock packages. The look is checked on a device.

## See Also

- [ftz_scanner_screen.md](ftz_scanner_screen.md) — the v6 QR camera, same skeleton
- [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md)
- [ocr_capture.md](ocr_capture.md) — the other `acquireCamera` caller with an overlay
