# OtqGetImages2

Image-capture widget, version 2 — opens the device camera, stores the captured image, and registers each captured URL into the screen's controller and the GetX `GeneralGetXController` widget store.

- **File:** [lib/widget/otq_get_images_2.dart](../../lib/widget/otq_get_images_2.dart)
- **Class:** `OtqGetImages2` (StatefulWidget, with `AutomaticKeepAliveClientMixin`)
- **Status:** draft
- **Widget version:** v2
- **Previous version:** [OtqGetImages](otq_get_images.md) (`lib/widget/otq_get_images.dart`)

## Purpose

Use `OtqGetImages2` for photo capture in v2 forms. It pulls camera descriptors from the transaction store, calls `getPhotoCameraImage(...)` with image-size and quality parameters, and pushes the resulting URLs through `GeneralGetXController.addWidget(...)` so a list of preview thumbnails renders inside the field.

## Signature / Constructor

```dart
const OtqGetImages2({
  required Key key,
  required Key wKey,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per widget instance (required by `StatefulWidget`) |
| `wKey` | `Key` | yes | — | Secondary key used inside the widget tree (e.g. for the inner image-list builder). Distinct from `key`. |
| `component` | `dynamic` | yes | — | Component config (Map; see shape below) |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `lPad` / `tPad` / `rPad` / `bPad` | `double` | yes | — | Outer padding on left/top/right/bottom |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `position` | `int?` | Slot in `txfController[scrName]` and key for `GeneralGetXController`. |
| `label` | `String?` | Camera screen title. Defaults to `'Camera'`. |
| `camera` | `int?` | `0` = front camera, otherwise back. Defaults to back. |
| `imageParameter` | `String?` | Comma-separated `"width,height,quality"` (e.g. `"400,400,80"`). Falls back to `[400, 400, 80]` on parse error. |
| `folder` | `String?` | Storage folder name. Defaults to `'default'`. |
| `filename` | `String?` | Filename prefix; a 5-char UUID slice is appended. Defaults to `'file'`. |
| `source` | `String?` | `"gallery"` opens device gallery picker instead of camera. Absent or unknown = camera (default). `"both"` is reserved but not yet implemented. |
| `currentValue` | `String?` | Pre-existing image URL list (will seed the preview thumbs). |
| `max` | `int?` | Maximum number of photos. **Ships as a String (`"1"`) from the sheet, which throws and falls back to `9999`** — a pre-existing quirk, unrelated to `optional`. |
| `text` | `String?` | ◆-separated. Segment `0` is unread. Segment **`1` is the refusal message** shown when `optional:"FALSE"` blocks a submit — never rendered in the form. Segment `2` = counter noun (default `foto`), segment `3` = add-button label (default `Tambah Foto`). |
| `optional` | `String?` | `"TRUE"` / `"FALSE"` (String, not bool — matches `SIGNATURE_PAD`). `"FALSE"` = at least one photo is required before any `savesend` on the page succeeds. **Absent, blank, `"TRUE"`, or an unresolved `[OPTIONAL]` placeholder all mean "not required" = today's behavior.** |

## Usage Example

```dart
OtqGetImages2(
  key: const ValueKey('proof_photos'),
  wKey: const ValueKey('proof_photos_inner'),
  scrName: 'submitClaim',
  component: const {
    'position': 7,
    'label': 'Capture Proof',
    'camera': 1,                    // back
    'imageParameter': '800,600,75',
    'folder': 'claims',
    'filename': 'proof',
  },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
)
```

## State / Bloc / Dependencies

- **GetX controller:** [`GeneralGetXController`](../../lib/model/general_get_controller.dart) holds the dynamic list of preview widgets per `(scrName, position)`. Captured URLs are written through `addWidget(...)`.
- **API helpers:** `getPhotoCameraImage`, `processData`, `errorReport`, `txfControllerCheck`, `buildImageWidget` — from [`api.dart`](../../lib/api.dart) and [`global.dart`](../../lib/global.dart) / [`global2.dart`](../../lib/global2.dart).
- **Camera descriptors:** read from `transactionStore.state.screenTx['#CAMS']` (a `List<CameraDescription>`).
- **Sentinels:** `emptyImageUrl`, `separator`, `emptyString` from [`init_values.dart`](../../lib/init_values.dart).

## Important Behavior

- `with AutomaticKeepAliveClientMixin` → captured images persist across scroll events.
- `imageParameter` parsing is defensive: any malformed value silently falls back to `[400, 400, 80]`. Width/height are passed as `max(width, height)` (a single dimension to the capture helper).
- The filename is suffixed with a random 5-char slice of a UUID (`UUID().v4()...substring(2, 7)`) — collisions are theoretically possible but extremely unlikely in practice.
- After a successful capture, the controller's `text` is replaced with the joined URL list (`processData(...)`) so the field's `finalData` reflects every captured image.
- When the widget is mounted with `isEnabled == false`, pressing the button calls `redraw(...)` instead of capturing — the field becomes a read-only thumbnail list.
- Errors from the controller-write block are routed through `errorReport(e)`.
- **`optional:"FALSE"` = required photo.** The check is NOT in this widget. It runs in
  [`ftz_row_of_button_2.dart`](../../lib/widget/ftz_row_of_button_2.dart) as the first statement of
  `case 'savesend':`, using the pure helpers in
  [`get_images_required_support.dart`](../../lib/widget/get_images_required_support.dart). A blocked
  press writes no event, changes no route and runs no chain; every other field keeps its value.
- **Scope of the gate:** `case 'savesend':` only. `case 'update':` is deliberately NOT gated — it is
  a direct table-update path with different semantics. The gate also covers a `savesend` button
  inside a `DO_BOTTOM_SHEET`, because the sheet is built with the same `scrName`
  ([`do_otq_bottom_sheet.dart`](../../lib/widget/do_otq_bottom_sheet.dart) →
  `buildPage(..., scrName, dialog: true, clear: false)`).
- **A refused save inside a `DO_BOTTOM_SHEET` leaves the sheet open by design.** The blocked
  press also skips the sheet's own `Get.back()`, so "Simpan alasan" keeps the sheet and its
  inputs on screen behind the refusal dialog: the officer takes the photo and presses again.
  (A `dataOk` refusal, by contrast, closes the sheet.)
- **A slot counts as "no photo" for FIVE values**, not one: `''`, whitespace, `'--'` (`emptyString`
  — `'--'.isEmpty` is FALSE), `'aum__--__mua'` (`emptyImageUrl`), and the literal string `'null'`
  (an absent `currentValue` becomes `"null"` in `init_values.dart` — a known repo-wide bug this gate
  defends against). Multi-photo slots are `separator[5]` (`◇`) joined; ANY surviving segment counts.
- **The gate always has a reachable exit.** Two components are skipped rather than enforced: one with
  no parseable `position` (it writes to no record slot, so nothing could satisfy it), and one whose
  record slot is **disabled at press time** (a disabled field cannot be tapped, so the officer could
  not produce a photo). A component whose slot does not exist yet is NOT treated as disabled — it is
  still enforced.
- **Config note — `optional:"FALSE"` + `isEnabled:"FALSE"` is not enforced.** The pairing is
  tolerated (the page stays submittable) but the field still shows the red `wajib` chip, so it reads
  as a requirement while behaving as an option. Pick one.
- **Config note — a refused save has already run the button's `run:` commands and `routeParams`.**
  Do not pair a required `GET_IMAGES` with a `generate_number` run-command on the same savesend
  button unless gaps in the generated sequence are acceptable: each refused press consumes a number.
  No event is written, no route is pushed and no chain runs — but those two side effects happen
  before the gate is reached.
- When required, the header renders a red **`wajib`** chip beside the label (same styling as the
  `SELECTABLE_BTN` badge). It is suppressed for a component with no `position`, so the badge cannot
  advertise a requirement the gate skips.
- When `source == "gallery"`, the `#CAMS` transactionStore check is bypassed (gallery does not need camera hardware). The icon changes to `Icons.photo_library_outlined` in both the header and empty-state areas. Upload pipeline is identical — the picked file goes through `prepareImageAsLocal(forceRename: true)` → `saveImagePutInImageMap` like a camera capture, ensuring the file is moved out of the OS cache dir into `<appSupport>/otq_images` with the correct `FTZIMG%2F<folder>___<fileName>.jpg` name.

## See Also

- [otq_get_images.md](otq_get_images.md) — v1 version (`OtqGetImages`)
- [photo_camera.md](photo_camera.md) — the lower-level camera widget invoked by `getPhotoCameraImage`
- [otq_txf_2.md](otq_txf_2.md), [otq_rdo_2.md](otq_rdo_2.md), [otq_dropdown_2.md](otq_dropdown_2.md), [display_list_2.md](display_list_2.md), [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — v2 component family
- Package: [`camera`](https://pub.dev/packages/camera), [`uuid`](https://pub.dev/packages/uuid)
