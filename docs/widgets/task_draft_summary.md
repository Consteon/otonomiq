# TaskDraftSummary

Read-only item preview for the Admin create-task wizard (P4).

- **File:** [lib/widget/task_draft_summary.dart](../../lib/widget/task_draft_summary.dart)
- **Class:** `TaskDraftSummary` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** admin-create-task slice

## Purpose

Renders the in-flight draft `it[]` as a read-only card with per-line rows
(item name + tx chip + qty) and aggregate totals. Placed above the submit
button in the P4 op1Screen layout (spec S5 #3). Pure display, no write path.

## Signature / Constructor

(Standard SDUI widget: key, scrName, component, lPad, tPad, rPad, bPad.)

### `component` shape

| Key | Type | Description |
|-----|------|-------------|
| `wizardKey` | String | Draft holder key (default `admin_create_task`) |
| `text` | String | Diamond-separated label slots (7 slots) |

## See Also

- [task_item_builder.md](task_item_builder.md) -- P2 builder (produces the draft)
- [task_create_submit.md](task_create_submit.md) -- P4 submit button
