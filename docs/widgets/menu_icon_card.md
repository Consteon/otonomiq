# menuIconCard (shared shell)

Shared visual shell for home-menu icon buttons. Source:
[lib/widget/menu_icon_card.dart](../../lib/widget/menu_icon_card.dart).
Not a component type — a plain function used by the `horizontal_icon`
children and their single modes:

| Caller | Modes |
|---|---|
| `goto.dart` | single + grid |
| `gps_send.dart` | single + grid |
| `attendance_qr_selfie_gps_verify.dart` | single + grid |
| `ftz_checker.dart` | single |
| `ui_component.dart` `disabledIcon` | grid (wrapped in `Opacity 0.55`) |
| `ui_component.dart` `buildGridList` | `vgr` / `hgr` grid items (Laporan, Formulir, dst.) |

## Look

White card, radius 16, hairline border `0xFFE2E8F0` (same as the
`time_presence` stat chips), flat — no shadow, ink ripple clipped to the
rounded shape. Content is vertically centered: fixed 36px icon
(`BoxFit.contain`), 6px gap, 2-line-max label weight 500 wrapped in
`Flexible` (shrinks instead of overflowing on very narrow screens); config
`fontSize` is **clamped to 12–13** so every menu section shares one caption
scale regardless of per-section sheet values.

## Grid layout (4 fixed columns)

The `horizontal_icon` and `hgr` branches in `build_display_component.dart`
render a **non-scrolling 4-column `GridView.count`** (`shrinkWrap`,
`NeverScrollableScrollPhysics`, `childAspectRatio: 0.85`) — more than 4
items wrap to new rows; the page scrolls, the grid never scrolls
horizontally. Cell size is screen-derived: sheet-config `width`/`row` no
longer size the cells (dead for these two branches; `vgr` still honours
`width`). In a tight grid cell the card fills the cell; in single mode
(unbounded height) it hugs content.

## Signature

```dart
Widget menuIconCard({
  required String imageUrl,   // '' falls back to defaultImage
  required String label,
  required double fontSize,
  void Function()? onTap,
})
```
