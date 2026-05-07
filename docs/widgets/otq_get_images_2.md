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
| `currentValue` | `String?` | Pre-existing image URL list (will seed the preview thumbs). |

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

## See Also

- [otq_get_images.md](otq_get_images.md) — v1 version (`OtqGetImages`)
- [photo_camera.md](photo_camera.md) — the lower-level camera widget invoked by `getPhotoCameraImage`
- [otq_txf_2.md](otq_txf_2.md), [otq_rdo_2.md](otq_rdo_2.md), [otq_dropdown_2.md](otq_dropdown_2.md), [display_list_2.md](display_list_2.md), [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — v2 component family
- Package: [`camera`](https://pub.dev/packages/camera), [`uuid`](https://pub.dev/packages/uuid)
