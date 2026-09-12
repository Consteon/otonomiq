# FtzScannerScreen

`lib/widget/ftz_scanner_screen.dart`

A full-screen camera pushed with the **real Flutter Navigator** (not `gotoRoute`
/ `routeStack`), which pops the raw scanned string back to its caller. It is not
an SDUI component — no `type` dispatches to it.

## Callers

| Caller | Site | Screen |
|---|---|---|
| Attendance (`type: "location"`) | `lib/part/build_part/attend_qr_gps_selfie_state_part.dart` | classic, or **v6** when the block opts in |
| Checker (`type: "checker"`) | `lib/part/build_part/ftz_checker_part.dart` | classic |
| Text field (`otq_txf`) | `lib/part/build_part/otq_txf_part.dart` | classic |

`lib/part/ios_part/attend_qr_gps_selfie_state_part_ios.dart_` is a legacy
hand-swap stub on the old `barcode_scan2` package. It is **not compiled** — the
`build_part` copy above serves both platforms — and it has not been updated.

## Parameters

| Param | Type | Default | Description |
|---|---|---|---|
| `title` | `String` | required | AppBar title (classic) / bar title (v6). |
| `camera` | `String` | `'back'` | `'front'` selects the front lens at open. |
| `variant` | `String` | `''` | `v6` (trimmed, case-folded) selects the v6 layout. Anything else — absent, blank, `v7` — keeps the classic screen. |
| `subtitle` | `String` | `''` | Second line under `title`. **v6 only**; the classic AppBar ignores it. |

Returns the barcode's `rawValue` via `Navigator.pop`, or `null` when the user
closes the screen. Callers read `null`/empty as "cancelled".

## Classic

Black `AppBar`, a 250 dp square hole punched in a 50 % black scrim, and three
unlabelled white icons (close, flip, torch) floating at the top of the camera.
Unchanged; every caller that does not pass `variant: "v6"` still gets exactly
this.

## `variant: "v6"` — the Vertika v6 camera

Opted into by the attendance block (`horizontal_icon` with `variant: "v6"`);
see [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md).

**Bar** — 56 dp, transparent over the scrim. One close button (44 dp target)
that always means *cancel and go back*; the classic screen offered both an
AppBar arrow and a floating X with no stated difference. Title 17/600 white,
subtitle 13/500 white at 92 %.

The title is composed by `scannerBarTitle(block, method, fallback)`:

| `blockTitle` | tile label | Result |
|---|---|---|
| `Absen Masuk` | `QR` | `Absen Masuk · QR` |
| blank | `QR` | `QR` |
| blank | blank | text slot 26 (`Scan QR`) |

`blockTitle` is stamped onto the child by the `horizontal_icon` v6 branch from
the block's own slot-0 text, so the wording stays the sheet's — nothing is
invented in Dart. Text slot 26, which the classic screen shows as its AppBar
title, becomes the subtitle once the bar carries the action.

**Viewfinder** — 240 dp square, four 32 dp corner brackets (3 dp stroke, 14 dp
radius), scrim `#0F172A` at 62 % everywhere outside it. Scrim and brackets are
one `CustomPainter` so they cannot drift apart.

`scannerFrameRect()` places it. The mock's 240 dp square, 48 dp side margins and
120 dp top offset are written for a 390×844 screen; on anything shorter the
**gap collapses first**, and only then does the frame shrink, floored at 140 dp.
The hint never slides under the bottom sheet. Locked by
`test/ftz_scanner_v6_test.dart`.

**Sweep** — a 2 dp gradient line, 2.4 s, `reverse: true`. Not painted at all
when `MediaQuery.disableAnimations` is set, and stopped for good once a code is
read.

**Controls** — a white bottom sheet, not floating icons: an icon on the camera
contrasts against whatever happens to be behind it, which at a bright guard post
is nothing. Two 48 dp tonal buttons with text labels and a pressed state
(`primary` at 10 % + a 1.5 dp `primary` ring). On the front camera the torch
button is disabled with the reason spelled out underneath — there is no flash on
that lens.

**States the screen owns** — exactly two:

| State | Brackets | Hint |
|---|---|---|
| scanning | white | *Arahkan kamera ke kode QR* + torch/lens-specific line |
| read | `#6EE7B7` + 64 dp spinner badge, one haptic | *Kode terbaca · Memverifikasi…* |

It stops there. **The screen never says "berhasil"** — it knows a code was
*read*, not that it is *valid*; the caller verifies (geofence, LQR lookup,
workforce match) and owns the reject dialog and the re-scan loop. A success this
screen cannot promise is a success it would have to take back. The read state is
held ~420 ms so the green frame is actually seen before the pop.

**Releasing the camera** — both trees call `_controller.stop()` *before*
`Navigator.pop`, not only in `dispose()`. `dispose()` runs after the pop
transition finishes, and the attendance flow opens the selfie camera on the same
back-camera hardware a few hundred ms later; that overlap is what leaves the
next screen on a black preview (camerax logs `Unknown camera ID 0`, then an
open-retry loop that never recovers). The v6 tree held it longest — the 420 ms
read state ran with the camera still streaming. Nothing changes visually: the
last frame stays until the route is gone.

Both start/stop go through `_fireAndForget`, which swallows the rejection these
calls produce when the platform side is already torn down — an un-awaited
rejection is an unhandled async error, which this app reports as a fatal.

**Permission denied** — `MobileScannerErrorCode.permissionDenied` replaces the
whole screen with an empty state: why, a filled accent CTA into the system
settings (`openAppSettings()`), and a link back. The v6 lifecycle handler retries
`start()` on resume, because permission is exactly what may have changed while
the user was in Settings. The classic handler keeps its original guard.

### Contrast

Measured against the worst realistic case — the scrim over a **fully white**
scene, composite `#6A6F7B`:

| Element | Ratio | Bar |
|---|---|---|
| White hint title 16/600 | 5.03:1 | 4.5:1 ✔ |
| Hint body, white @ 92 % | 4.54:1 | 4.5:1 ✔ |
| Corner brackets `#6EE7B7` | 3.30:1 | 3:1 (non-text) ✔ |
| Accent CTA `#F08118` on `#1A1206` | 6.94:1 | 4.5:1 ✔ |

Two deliberate deviations from the mock, both because the mock's own value
fails:

- v6 writes the hint body at **86 %** white — 4.22:1, under the 4.5:1 a 14 dp
  line owes. Shipped at 92 %, which is the same line to look at.
- v6 turns the hint **title** green on read (`.hint.good b`). At 16/600 that is
  3.30:1, well under 4.5:1. The label stays white and the brackets plus the
  badge icon carry the state — the rule `theme_tokens.dart` already states for
  every `*OnDark` colour: colour the mark, not the label.

`#FCA5A5` (`dangerOnDark`) measures **2.65:1** on the same composite and clears
neither bar. There is no error state on this screen today; if one is ever added,
it cannot be that colour on that scrim.

## Not done

- **No verify / success / error state inside the camera.** The v6 mock shows
  them; delivering them means moving the caller's verification (and its overtime
  dialogs, its selfie step, its write) into the screen. The caller's existing
  "QR salah" dialog and re-scan loop are untouched.
- **Hint microcopy is hardcoded Indonesian**, not sheet-driven. Four
  instructional strings that no tenant varies; adding four `text` slots for them
  is more sheet surface than it buys.
- Checker and `otq_txf` still get the classic screen even inside a v6 block.

## Tests

`test/ftz_scanner_v6_test.dart` — 11 tests over `scannerBarTitle` and
`scannerFrameRect`. The screen itself cannot be pumped: `MobileScanner` reaches
for the camera plugin and this repo carries no mock packages. The look is
checked on a device.

## See Also

- [attendance_qr_selfie_gps_verify.md](attendance_qr_selfie_gps_verify.md)
- [photo_camera.md](photo_camera.md) — the v6 selfie camera, same skeleton
- [scanner.md](scanner.md) — the in-page live-camera SDUI card (different widget)
