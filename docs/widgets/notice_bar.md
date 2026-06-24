# NoticeBar

A notification strip/callout widget that renders up to 3 text tiers with
variant-driven theme colors, an optional left accent bar, and an optional icon.

- **File:** [lib/widget/notice_bar.dart](../../lib/widget/notice_bar.dart)
- **Class:** `NoticeBar` (StatelessWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Display server-driven notification banners on any page. Used for login warnings,
scan confirmations, custody alerts, and informational notices. Colors are
resolved from the `variant` enum via `statusColor()`/`statusBgColor()` in
`panel_card_support.dart` -- no hex values in JSON.

## Signature / Constructor

```dart
NoticeBar({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | -- | Unique key per instance |
| `scrName` | `String` | yes | -- | Name of the screen this widget is mounted on |
| `component` | `dynamic` | yes | -- | Component config (structure below) |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | -- | System-level padding |

### `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `String` | yes | -- | `"noticeBar"` |
| `variant` | `String` | yes | -- | `"danger"` / `"warn"` / `"ok"` / `"info"` |
| `icon` | `String?` | no | `null` | Icon key for `panelIcon()` (e.g. `"info"`, `"alert"`) |
| `iconAlign` | `String?` | no | `"center"` | `"top"` or `"center"` |
| `label` | `String?` | no | `null` | Eyebrow text (rendered UPPERCASE) |
| `title` | `String?` | no | `null` | Bold heading (dark neutral color) |
| `text` | `String` | yes | -- | Body text (variant color, supports `**bold**` and `*italic*`) |
| `beforeSpacing` | `num?` | no | `0.0` | Top margin |
| `afterSpacing` | `num?` | no | `0.0` | Bottom margin |
| `margin` | `String?` | no | -- | Additional margins (top,bottom,left,right) -- comma-separated, split by `separator[4]` via `marginArray()` |

## Usage Examples

### Body-only strip (P2 login warning)

```json
{
  "type": "noticeBar",
  "variant": "danger",
  "text": "Sesi driver lain masih aktif. Logout dulu sebelum scan."
}
```

### Thin info strip

```json
{
  "type": "noticeBar",
  "variant": "info",
  "text": "Trip di-pause. Scan kartu untuk lanjutkan."
}
```

### Card form with icon + all tiers (P5 custody notification)

```json
{
  "type": "noticeBar",
  "variant": "warn",
  "icon": "info",
  "iconAlign": "top",
  "label": "KONFIRMASI DIPERLUKAN",
  "title": "Vehicle siap berangkat, butuh konfirmasi penerimaan",
  "text": "Lo belum bisa mulai task hari ini sebelum konfirmasi load dari warehouse."
}
```

### Card form with icon centered (P6 custody count)

```json
{
  "type": "noticeBar",
  "variant": "info",
  "icon": "info",
  "iconAlign": "center",
  "title": "3 item belum di-scan",
  "text": "Scan semua item sebelum berangkat."
}
```

### Success strip

```json
{
  "type": "noticeBar",
  "variant": "ok",
  "text": "Semua item sudah di-scan. Siap berangkat."
}
```

## State / Bloc / Dependencies

- **None.** Pure display widget: no txfController slot, no Redux key, no GetX,
  no Bloc, no navigation, no history/imageMap.
- Color palette from `panel_card_support.dart` (`statusColor`, `statusBgColor`, `panelIcon`).
- Margin helper from `global.dart` (`marginArray`).

## Important Behavior

- **Left accent bar** renders ONLY when `label` or `title` is present ("card form").
  Body-only strips have no bar.
- **Inline emphasis** in `text` field only: `**bold**` and `*italic*`. Label and
  title are always plain text.
- **Unknown variant** falls through to the `default:` branch in statusColor /
  statusBgColor, yielding green (ok). The widget still renders -- it never
  crashes on an unknown variant.
- **All fields empty** (empty text, no label, no title) renders `SizedBox.shrink()`.
- No diamond-delimited fields. No fixed-index access. No `autheniumDecode` needed.

## See Also

- [panel_card_support.dart](../../lib/widget/panel_card_support.dart) -- color palette (`statusColor`, `statusBgColor`, `panelIcon`)
- [otq_txt.md](otq_txt.md) -- the `txt` component (similar layout pattern)
