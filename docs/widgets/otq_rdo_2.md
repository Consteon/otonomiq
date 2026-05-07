# OtqRdo2

Radio-button group, version 2 — renders a list of single-select options as a card-styled container with horizontal or vertical layout.

- **File:** [lib/widget/otq_rdo_2.dart](../../lib/widget/otq_rdo_2.dart)
- **Class:** `OtqRdo2` (StatefulWidget, with `AutomaticKeepAliveClientMixin`)
- **Status:** draft
- **Widget version:** v2
- **Previous version:** [OtqRdo](otq_rdo.md) (`lib/widget/otq_rdo.dart`)

## Purpose

Use `OtqRdo2` when you need a single-choice picker that integrates with the screen's `txfController` registry. The v2 version applies the modern card-style chrome (rounded corners, subtle border, soft shadow) used across the v2 component family ([OtqTxf2](otq_txf_2.md), [OtqDropdown2](otq_dropdown_2.md), etc.).

## Signature / Constructor

```dart
const OtqRdo2({
  required Key key,
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
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config (Map; see shape below) |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `lPad` / `tPad` / `rPad` / `bPad` | `double` | yes | — | Outer padding on left/top/right/bottom |

> No external controller param — selection state is held internally and mirrored to `txfController[scrName][position]` when `position` is set.

### `component` shape

| Key | Type | Description |
|---|---|---|
| `position` | `int?` | Slot in `txfController[scrName]` to store the selection. If `null`, the widget is not registered. |
| `menu` | `List<String>` | The radio options. Defaults to `['--']` if missing. |
| `currentValue` | `String?` | Initial selected value. |
| `buttonLayout` | `String` | `'horizontal'` or `'vertical'` (default). |
| `alignment` | `String` | Main-axis alignment, resolved via `mainAlignmentConst(...)` from `global2.dart`. |
| `icon` | `String?` | Icon key; resolved through `OtqIcons`. |
| `label` | `String?` | Label text (rendered uppercase). |
| `margin` | dynamic | Parsed by `marginArray(...)` into `[top, bottom, left, right]`. |

## Usage Example

```dart
OtqRdo2(
  key: const ValueKey('gender'),
  scrName: 'profile',
  component: const {
    'position': 3,
    'label': 'Gender',
    'menu': ['Male', 'Female'],
    'currentValue': 'Male',
    'buttonLayout': 'horizontal',
    'alignment': 'start',
    'margin': '0,8,0,0',
  },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
)
```

## State / Bloc / Dependencies

- **Globals:** `txfController` (registered per `scrName` + `position`), `marginArray`, `mainAlignmentConst`, `canInitializePage`, `txfControllerCheck` — all from [`global.dart`](../../lib/global.dart) / [`global2.dart`](../../lib/global2.dart).
- **Icons:** [`OtqIcons`](../../lib/otq_icons.dart) for the optional leading icon.
- **No bloc** — state is kept in the widget itself plus the `txfController` registry.

## Important Behavior

- `with AutomaticKeepAliveClientMixin` → state is preserved when the widget scrolls out of view.
- On selection (`_select`), `setState` updates `_picked` and writes to `txfController[scrName][position].finalData`.
- `txfControllerCheck(...)` is called both in `initState` and in `_select` to lazy-create the controller slot if it doesn't already exist.
- Initial `finalData` and `initialValue` are only seeded when `canInitializePage(scrName)` returns true — guards against re-seeding on rebuild.
- `label` is force-uppercased.

## See Also

- [otq_rdo.md](otq_rdo.md) — v1 version (`OtqRdo`)
- [otq_dropdown_2.md](otq_dropdown_2.md) — sibling v2 single-select component (uses a bottom sheet instead of inline radios)
- [otq_txf_2.md](otq_txf_2.md), [otq_get_images_2.md](otq_get_images_2.md), [display_list_2.md](display_list_2.md), [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — v2 component family
