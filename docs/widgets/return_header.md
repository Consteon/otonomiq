# ReturnHeader

Back arrow + label + title header for P12 ReturnVehicle end-of-day handover.

- **File:** [lib/widget/return_header.dart](../../lib/widget/return_header.dart)
- **Class:** `ReturnHeader` (StatelessWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Presentational header for the P12 ReturnVehicle page. Renders a back arrow
(navigates to `backRoute` via routeStack + gotoRoute), an uppercase gray
label ("AKHIR HARI"), and a bold dark title ("Return Kendaraan"). All text
is server-driven via diamond-separated `text` field.

## Signature / Constructor

```dart
ReturnHeader({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

| Key | Type | Description |
|---|---|---|
| `type` | `String` | `"RETURN_HEADER"` |
| `backRoute` | `String` | Route name for back navigation (e.g. `vertikaTeknoLokaciptaDriverHome`) |
| `text` | `String` | Diamond-separated: `label◆title` (2 segments) |

## State / Bloc / Dependencies

- None. Pure display, read-only.

## Important Behavior

- Back arrow uses `routeStack.push(backRoute)` then `gotoRoute(backRoute)`.
  Mirrors route_feed_header._onBackTap.
- Text slots are length-guarded per index with sensible defaults.

## See Also

- [route_feed_header.md](route_feed_header.md) -- another header with a back arrow
- [custody_step_header.md](custody_step_header.md) -- a simple driver header
