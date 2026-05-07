# TimePresence

Display-only card showing check-in time, live elapsed counter, and last action time in a three-column layout.

- **File:** [lib/widget/time_presence.dart](../../lib/widget/time_presence.dart)
- **Class:** `TimePresence` (StatefulWidget)
- **Status:** done
- **Widget version:** v1

## Purpose

Shows a compact time-presence summary card with three columns:
1. **Check-in** — the time the user checked in (static display).
2. **Live** — a real-time counter (HH:MM) ticking every second since check-in.
3. **Last Action** — the time of the most recent recorded action.

When the user has already checked out, both check-in and last-action columns show the no-data placeholder and the live counter stops.

Use this widget on attendance/presence screens where the user needs to see how long they've been on-site.

## Signature / Constructor

```dart
const TimePresence({
  required Key key,
  required dynamic component,
  required String scrName,
  required bool single,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `component` | `dynamic` | yes | — | Component config (see shape below) |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `single` | `bool` | yes | — | Standard flag from the v2 component family |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `text` | `String` | Diamond-separated (`◆`) bundle of label and time strings — see text parts table below. |
| `borderRadius` | `num?` | Card corner radius in px. Default `12`. |

### `text` parts

`component['text']` is split by `◆` into up to 8 parts:

| Index | Purpose | Default |
|---|---|---|
| `0` | Header label (displayed uppercase-style) | `"TIME PRESENCE"` |
| `1` | Check-in column label | `"CHECK-IN"` |
| `2` | Live counter column label | `"LIVE"` |
| `3` | Last action column label | `"LAST ACTION"` |
| `4` | No-data fallback display | `"--:--"` |
| `5` | Check-in time value (`HH:mm`) or placeholder | `""` |
| `6` | Last action time value (`HH:mm`) or placeholder | `""` |
| `7` | Checkout time value (`HH:mm`) or placeholder / empty = no checkout | `""` |

### Time value format

- **Valid time**: `"HH:mm"` format (e.g. `"08:30"`, `"14:05"`).
- **Placeholder**: Empty string `""` or bracket-wrapped token like `"[CHECKIN]"`, `"[LASTACTION]"`, `"[CHECKOUT]"`. Treated as "no data".

## Display Logic

```
if checkout time is set (text[7] is valid):
  → check-in column = noDataLabel
  → last action column = noDataLabel
  → live counter = noDataLabel (timer not started)

else if check-in time is set (text[5] is valid):
  → check-in column = formatted check-in time
  → live counter = elapsed time since check-in (ticking every second)
  → last action column = formatted last action time (or noDataLabel)

else:
  → all columns show noDataLabel
  → live counter not started
```

## Usage Example (Screen JSON)

### Active session (checked in, not yet checked out)

```json
{
  "type": "TIME_PRESENCE",
  "text": "TIME PRESENCE◆CHECK-IN◆LIVE◆LAST ACTION◆--:--◆08:30◆09:45◆",
  "borderRadius": 12
}
```

Displays: Check-in `08:30` | Live `01:15` (ticking) | Last Action `09:45`

### Pre-check-in (no data yet)

```json
{
  "type": "TIME_PRESENCE",
  "text": "WAKTU KEHADIRAN◆MASUK◆DURASI◆TERAKHIR◆-:-◆[CHECKIN]◆[LASTACTION]◆"
}
```

Displays: Masuk `-:-` | Durasi `-:-` | Terakhir `-:-`

### After checkout (session ended)

```json
{
  "type": "TIME_PRESENCE",
  "text": "TIME PRESENCE◆CHECK-IN◆LIVE◆LAST ACTION◆--:--◆08:30◆16:00◆17:00"
}
```

Displays: Check-in `--:--` | Live `--:--` | Last Action `--:--` (all reset because checkout is present)

## Internal Widgets

| Class | Type | Purpose |
|---|---|---|
| `_TimeColumn` | StatelessWidget | Renders a single label + value column (used for check-in and last action). |
| `_LiveCounter` | StatefulWidget | Renders the live elapsed counter with a 1-second `Timer.periodic`. |
| `_ColumnDivider` | StatelessWidget | 8px horizontal spacer between columns. |

## State / Bloc / Dependencies

- **Timer:** `_LiveCounter` starts a 1-second periodic timer only when `checkInDt` is non-null. Timer is cancelled on dispose.
- **No external state** — this widget is purely display. It does not read from or write to `txfController`, Redux store, or any repository.
- **Helpers:** `diamondTextToList` from `global.dart` for parsing the text bundle.

## Important Behavior

- **Live counter ticks every second** — uses `Timer.periodic(Duration(seconds: 1))`. Display updates are `HH:MM` (no seconds shown), but the timer fires per second for smooth minute transitions.
- **Negative duration clamped to zero** — if the parsed check-in time is somehow in the future, the counter shows `00:00` instead of negative values.
- **Checkout resets all displays** — when `text[7]` contains a valid time (not placeholder), the widget intentionally hides check-in and last-action data. This signals "session ended" to the user.
- **Timer only created when needed** — if there's no valid check-in or if checkout is present, no timer is allocated (no unnecessary resource usage).
- **Mounted check** — timer callback verifies `mounted` before calling `setState`.
- **Tabular figures** — time values use `FontFeature.tabularFigures()` so digits don't shift when the counter ticks.

## UI Layout

```
┌─────────────────────────────────────────────┐
│ 🕐 TIME PRESENCE                            │  ← header (text[0])
│                                             │
│ ┌───────────┐  ┌───────────┐  ┌──────────┐ │
│ │ CHECK-IN  │  │   LIVE    │  │LAST ACTION│ │
│ │   08:30   │  │   01:15   │  │   09:45  │ │
│ └───────────┘  └───────────┘  └──────────┘ │
└─────────────────────────────────────────────┘
```

## See Also

- [location_detector.md](location_detector.md) — often paired on attendance screens
- [attendance_qr_selfie_gps_verify.md](../../lib/widget/attendance_qr_selfie_gps_verify.dart) — full attendance verification flow
