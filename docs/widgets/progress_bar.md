# ProgressBar

Visual-only progress indicator that aggregates the status of multiple [`Tasklist`](tasklist.md) widgets on the same screen.

- **File:** [lib/widget/progress_bar.dart](../../lib/widget/progress_bar.dart)
- **Class:** `ProgressBar` (StatelessWidget)
- **Status:** draft
- **Companion widget:** [Tasklist](tasklist.md) — each `Tasklist` registers itself in `TaskProgressStore`; `ProgressBar` reads from that registry to render the bar.

## Purpose

Renders a card with: task title, subtitle, "X / Y tasks", percent, animated progress bar, and a green "Verified" badge when all tracked tasks are done. **It does not submit any data** — it has no `position` field and never writes to `txfController`. Each [`Tasklist`](tasklist.md) is responsible for writing its own `title:value` entry; `ProgressBar` is purely a UI affordance.

## Signature / Constructor

```dart
const ProgressBar({
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
| `positionId` | `List<int>` | **Required.** Positions of the [`Tasklist`](tasklist.md) widgets to aggregate. Empty list → "0 / 0 tasks" and 0% bar. |
| `text` | `String` | Diamond-separated (`◆`) bundle of label strings — see table below. |
| `bgColor` | `String?` | Card background, hex (`"#FFF"` or `"#FFFFFF"`). Defaults to white. |
| `lineColor` | `String?` | Filled bar color, hex. Defaults to `#22C55E` (green). |
| `showPercent` | `bool/String?` | Whether to render the percent label. Accepts `true` or string `"TRUE"`. Default `true`. |
| `showCount` | `bool/String?` | Whether to render the "X / Y tasks" count. Accepts `true` or string `"TRUE"`. Default `true`. |
| `height` | `num?` | Bar height in px. Default `8`. |
| `borderRadius` | `num?` | Card corner radius. Default `10`. |
| `width` | `num?` | (Read by other widgets in the family; not used in layout here.) |

### `text` parts

`component['text']` is split by `◆` into up to 9 parts:

| Index | Purpose | Default |
|---|---|---|
| `0` | Card title | `""` |
| `1` | Subtitle word 1 | — |
| `2` | Subtitle word 2 | — |
| `3` | Subtitle word 3 | — |
| `4` | Count separator (between done & total) | `/` |
| `5` | Verified icon | `✓` |
| `6` | Verified label | `Verified` |
| `7` | Tasks label | `tasks` |
| `8` | Percent suffix | `%` |

Subtitle parts `[1..3]` are joined with spaces; if all three are missing the subtitle row is hidden.

> **Important:** The widget has **no `position` field**. It is intentionally not connected to `txfController`. If you need the aggregated state on the server, encode it via the individual [`Tasklist`](tasklist.md) entries (each writes `title:value` to its own slot).

## Usage Example (Screen JSON)

```json
{
  "type": "PROGRESS_BAR",
  "bgColor": "#FFF",
  "lineColor": "#000",
  "showPercent": "TRUE",
  "showCount": "TRUE",
  "width": 100,
  "height": 20,
  "borderRadius": 10,
  "positionId": [1, 2, 3, 4, 5, 6, 7, 8],
  "text": "Kondisi Area◆◆·◆◆/◆✓◆Verified◆tasks◆%"
}
```

This pairs with eight `TASKLIST` entries at positions `1..8`. The card shows `0 / 8 tasks` at first; the green "Verified" badge appears once all eight are marked `done`.

## State / Bloc / Dependencies

- **Store:** [`TaskProgressStore`](../../lib/widget/task_progress_store.dart) — singleton `ChangeNotifier`. The widget is rebuilt via `ListenableBuilder` whenever the store notifies (a `Tasklist` registers, updates, or unregisters).
- **Helpers:** `diamondTextToList` from [`global.dart`](../../lib/global.dart) for parsing the `text` bundle.
- **No `txfController` access** — by design.

### Counts derived from the store

| API call | What it returns |
|---|---|
| `totalFor(scrName, positions)` | How many of the `positions` are currently registered (i.e. how many `Tasklist` widgets are on screen). |
| `doneFor(scrName, positions)` | How many of those have `statusKey == 'done'`. |
| `progressFor(scrName, positions)` | `done / total` (0.0 if total is 0). |

## Important Behavior

- **Stateless** — the widget rebuilds only when `TaskProgressStore` notifies, not when individual statuses change in any other store.
- The "Verified" badge appears when `total > 0 && done == total` — that is, all tracked tasks are not just registered but marked `done`. Other final statuses (`not_available`, `skipped`, `issue`) do not satisfy "verified".
- Color parsing accepts 3-char shorthand (`#FFF` → `#FFFFFF`) and falls back to default on parse error.
- The animated bar uses a 400 ms `easeInOut` curve.

## See Also

- [tasklist.md](tasklist.md) — sibling widget that drives this aggregator
- [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — submits the screen using the per-task entries
