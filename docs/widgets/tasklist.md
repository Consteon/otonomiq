# Tasklist

Single checklist task rendered as a card — user picks a status from a bottom sheet (or toggles "done") and the result is written to `txfController` for submission.

- **File:** [lib/widget/tasklist.dart](../../lib/widget/tasklist.dart)
- **Class:** `Tasklist` (StatefulWidget)
- **Status:** draft
- **Companion widget:** [ProgressBar](progress_bar.md) — shows aggregated progress across multiple `Tasklist` items.

## Purpose

Use one `Tasklist` per checklist item on a screen. Each instance is a self-contained card with a title, optional subtitles, and a status picker. On submit, the slot at `position` in the screen's `txfController` is written as `title:statusLabel`, so the server receives a self-describing entry like `"Bersihkan meja:Selesai"`.

A page typically has many `Tasklist` instances + one [`ProgressBar`](progress_bar.md) whose `positionId` lists the task positions to aggregate.

## Signature / Constructor

```dart
const Tasklist({
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
| `single` | `bool` | yes | — | Standard flag from the v2 component family (mirrors usage in other widgets) |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `position` | `int?` | Slot in `txfController[scrName]`. Required for the value to reach the server. If absent or `0`, the widget renders but writes nothing. |
| `text` | `String` | Diamond-separated (`◆`) bundle: `[0]` task title, `[1]` "completed at" prefix, `[2..4]` subtitle text shown for `not_available` / `skipped` / `issue`. |
| `options` | `String` | Diamond-separated triplets `(icon, label, description)` — one triplet per status (done, not_available, skipped, issue). Drives the bottom-sheet picker and the `statusLabel` written to `finalData`. |
| `category` | `String?` | Category tag rendered as a small badge. |
| `width` | `num?` | Card minimum width (px). |
| `height` | `num?` | Card minimum height (px). |
| `borderRadius` | `num?` | Card corner radius (default `10`). |
| `margin` | `String?` | Margin spec parsed by `marginArray(...)`. |
| `pendingLabel` | `String?` | Override the placeholder written to `finalData` before the user picks anything. Defaults to `"belum"`. |

### Status keys (internal)

The widget tracks one of: `pending`, `done`, `not_available`, `skipped`, `issue`. Mapping to user-facing labels comes from `component['options']`:

| Status key | Label source | Color |
|---|---|---|
| `done` | `options[0].label` | `#22C55E` (green) |
| `not_available` | `options[1].label` | `#9CA3AF` (gray) |
| `skipped` | `options[2].label` | `#F59E0B` (amber) |
| `issue` | `options[3].label` | `#EF4444` (red) |
| `pending` | `pendingLabel` (default `"belum"`) | `#D1D5DB` |

## Usage Example (Screen JSON)

```json
{
  "type": "TASKLIST",
  "position": 1,
  "width": 100,
  "height": 40,
  "borderRadius": 10,
  "category": "12",
  "margin": "0,5,0,0",
  "text": "Bersihkan meja◆Selesai pada◆Tidak tersedia di area ini◆Dilewati - kunjungi kembali nanti◆Masalah - jelaskan dalam laporan.",
  "options": "✓◆Selesai◆Tandai Selesai◆✖◆Tidak Tersedia◆Barang tidak ada di area ini◆>◆Dilewati◆Kembali lagi nanti◆!◆Masalah◆Lapor masalah"
}
```

## State / Bloc / Dependencies

- **Globals:** `txfController`, `txfControllerCheck` from [`global2.dart`](../../lib/global2.dart); `canInitializePage` from [`api.dart`](../../lib/api.dart); `diamondTextToList`, `marginArray` from [`global.dart`](../../lib/global.dart).
- **Companion store:** [`TaskProgressStore`](../../lib/widget/task_progress_store.dart) — singleton `ChangeNotifier` registry of `{scrName: {position: statusKey}}`. Used by [`ProgressBar`](progress_bar.md) to compute aggregate progress.
- **No bloc** — local `_status` state, mirrored to both stores.

## Important Behavior

- `_position` is read once in `initState`. If `> 0`, two side effects happen:
  1. **`TaskProgressStore.register`** is queued via `addPostFrameCallback` so [`ProgressBar`](progress_bar.md) can pick up the new entry once registered.
  2. **`txfControllerCheck` + seed** — when `canInitializePage(scrName)` is true, the controller is seeded with `'$title:$_pendingLabel'` (e.g. `"Bersihkan meja:belum"`), so a submit before the user touches anything still produces a meaningful payload (not `null` and not empty).
- On selection (`_updateStore(status)`), the widget:
  - Pushes the status key into `TaskProgressStore` so [`ProgressBar`](progress_bar.md) updates.
  - Writes `'$title:$label'` to `txfController[scrName][position].finalData` and `controller.text` (both, so `saveSend`'s `finalData == emptyString` fallback works either way).
- `pending` status keeps the placeholder label (`pendingLabel`) — re-toggling from `done` back to `pending` writes `'$title:belum'` again.
- `dispose` calls `TaskProgressStore.unregister` (with `addPostFrameCallback`) to keep the aggregate count accurate when navigating away.
- The bottom-sheet picker is built from `_options`. If `options` has fewer than 4 triplets, the missing status keys still work but fall back to English defaults (`Done`, `Not Available`, `Skipped`, `Issue`).

## See Also

- [progress_bar.md](progress_bar.md) — visual aggregator that listens to `TaskProgressStore`
- [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — submits the screen, reads `txfController[scrName]` to build the row sent to Firestore
- Source: [api.dart `saveSend`](../../lib/api.dart) — payload builder that picks up each Tasklist's `finalData`
