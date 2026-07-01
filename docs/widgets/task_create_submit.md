# TaskCreateSubmit

Submit button for the Admin create-task wizard (P4).

- **File:** [lib/widget/task_create_submit.dart](../../lib/widget/task_create_submit.dart)
- **Class:** `TaskCreateSubmit` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** admin-create-task slice

## Purpose

Assembles the complete task doc (scalars from screenTx bare keys + it[] from
the draft) and writes it via `createNativeDoc` (one native Firestore set,
offline-safe). On success: clears draft, navigates to P5. Mirrors
`CustodyCountSubmit` O1 path.

## Signature / Constructor

(Standard SDUI widget: key, scrName, component, lPad, tPad, rPad, bPad.)

### `component` shape

| Key | Type | Description |
|-----|------|-------------|
| `table` | String | Firestore table path for task collection |
| `vidtable` | String | appVid override |
| `wizardKey` | String | Draft holder key (default `admin_create_task`) |
| `originWarehouse` | String | gl value (warehouse FK) |
| `klKey`/`knKey`/`alKey`/`vvKey`/`glKey` | String | screenTx key name overrides |
| `route` | String | P5 route on success |
| `chain` | dynamic | Chain config (optional) |
| `text` | String | Diamond-separated label slots (4 slots) |

## See Also

- [task_item_builder.md](task_item_builder.md) -- P2 builder
- [task_draft_summary.md](task_draft_summary.md) -- P4 preview
- [custody_count_submit.md](custody_count_submit.md) -- structural mirror
