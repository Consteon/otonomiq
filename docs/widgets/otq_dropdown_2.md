# OtqDropdown2

Dropdown picker, version 2 — opens a bottom sheet with a search field for selecting one item from a list. Supports parallel `data` / `subtitle` arrays for richer items.

- **File:** [lib/widget/otq_dropdown_2.dart](../../lib/widget/otq_dropdown_2.dart)
- **Class:** `OtqDropdown2` (StatefulWidget, with `AutomaticKeepAliveClientMixin`)
- **Status:** draft
- **Widget version:** v2
- **Previous version:** [OtqDropdown](otq_dropdown.md) (`lib/widget/otq_dropdown.dart`)

## Purpose

Single-select widget that scales to long option lists thanks to its built-in search. Unlike a classic `DropdownButton`, options are shown in a modal bottom sheet (up to 70% of screen height) — appropriate for mobile use with many items.

## Signature / Constructor

```dart
const OtqDropdown2({
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

### `component` shape

| Key | Type | Description |
|---|---|---|
| `position` | `int?` | Slot in `txfController[scrName]`. Stored in `_position`. |
| `menu` | `List<String>` | Selectable options. If absent, falls back to `option`. |
| `option` | `List<String>` | Legacy alias for `menu`. |
| `data` | `List<String>?` | Parallel array; when its length equals `menu.length`, each item gets a `dataMap` lookup (e.g. for an associated id). |
| `subtitle` | `List<String>?` | Parallel array of subtitle strings shown beneath each item. |
| `label` | `String?` | Field label. |
| `sheetTitle` | `String?` | Bottom sheet title. Defaults to `"Pilih <label>"`. |
| `searchHint` | `String?` | Search field hint. Defaults to `"Cari..."`. |
| `margin` | dynamic | Parsed by `marginArray(...)` into `[top, bottom, left, right]`. |
| `currentValue` | `String?` | Initial selection (resolved by `getInitialValue(scrName, component)`). Cleared if not in `menu`. |

> The default `sheetTitle` and `searchHint` are Indonesian strings — override them when localization is needed.

## Usage Example

```dart
OtqDropdown2(
  key: const ValueKey('city'),
  scrName: 'address',
  component: const {
    'position': 2,
    'label': 'City',
    'menu': ['Jakarta', 'Bandung', 'Surabaya'],
    'data': ['JKT', 'BDG', 'SBY'],
    'sheetTitle': 'Select City',
    'searchHint': 'Search city...',
    'margin': '0,8,0,0',
  },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
)
```

## State / Bloc / Dependencies

- **Globals:** `txfController`, `getInitialValue`, `marginArray` from [`global.dart`](../../lib/global.dart) / [`global2.dart`](../../lib/global2.dart).
- **`init_values.dart`:** for sentinel values like `emptyString`.
- **GetX:** `package:get/get.dart` (used for navigation/state utilities elsewhere in the v2 family).
- **No bloc** — selection state lives in the widget; `_searchController` is a local `TextEditingController` disposed in `dispose`.

## Important Behavior

- `with AutomaticKeepAliveClientMixin` → state is preserved when scrolled out of view.
- `dataSeparated` is `true` only when `data.length == menu.length`. When true, each option is associated with its parallel `data` value via `dataMap[menu[i]] = data[i]`.
- `_itemSelected` is reset to `''` if the resolved initial value is not present in `menu` — prevents stale selections after the option list changes.
- The bottom sheet is rebuilt with `StatefulBuilder` so search filtering re-renders without rebuilding the whole widget.
- Both `menu` and the legacy `option` key are read; `menu` takes precedence.

## See Also

- [otq_dropdown.md](otq_dropdown.md) — v1 version (`OtqDropdown`)
- [otq_rdo_2.md](otq_rdo_2.md) — sibling single-select widget (inline radios; better for short lists)
- [otq_txf_2.md](otq_txf_2.md), [otq_get_images_2.md](otq_get_images_2.md), [display_list_2.md](display_list_2.md), [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — v2 component family
