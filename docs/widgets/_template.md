# WidgetName

One-sentence summary of what this widget does.

- **File:** [lib/widget/file_name.dart](../../lib/widget/file_name.dart)
- **Class:** `WidgetName` (StatefulWidget / StatelessWidget)
- **Status:** draft / done
- **Widget version:** v1 / v2
- **Introduced in commit/version:** `c556732` or version tag

## Purpose

Brief description of the problem this widget solves and when to use it (vs. its alternatives).

## Signature / Constructor

```dart
WidgetName({
  required Key key,
  required String scrName,
  required dynamic component,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
  TextEditingController? cnt,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | — | Unique key per instance |
| `scrName` | `String` | yes | — | Name of the screen this widget is mounted on |
| `component` | `dynamic` | yes | — | Component config (structure described below) |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Left/top/right/bottom padding |
| `cnt` | `TextEditingController?` | no | `null` | External controller; `null` means stand-alone widget |

### `component` shape

Describe the keys this widget reads from `component` (when applicable):

| Key | Type | Description |
|---|---|---|
| `name` | `String` | Component identifier |
| `label` | `String` | Display label |
| `...` | | |

## Usage Examples

### Basic usage

```dart
WidgetName(
  key: ValueKey('field_x'),
  scrName: 'screenA',
  component: { 'name': 'field_x', 'label': 'Field X' },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
)
```

### With an external controller

```dart
final controller = TextEditingController();

WidgetName(
  key: ValueKey('field_y'),
  scrName: 'screenB',
  component: { ... },
  lPad: 8, tPad: 8, rPad: 8, bPad: 8,
  cnt: controller,
)
```

## State / Bloc / Dependencies

- **Bloc / state used:** `MainBloc`, `TimerBloc`, etc.
- **Repository:** `TableRepository`, `Api`, etc.
- **Side effects:** what gets dispatched / persisted / read.

## Important Behavior

- Non-obvious behavior: validation, auto-formatting, keep-alive, debouncing, etc.
- Known limitations.

## See Also

- Related widgets (older version / newer version / companion)
- e.g. [otq_txf.md](otq_txf.md) for the v1 version
