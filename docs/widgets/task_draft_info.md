# TaskDraftInfo

**SDUI type:** `task_draft_info`
**File:** `lib/widget/task_draft_info.dart`
**Status:** draft
**Added:** 2026-06-30

## Purpose

Read-only P4 info card for the Admin create-task wizard. Displays customer
and vehicle data captured into the wizard draft from P1 (TaskFeedList
flat-mode tap) and P3 (PickerList capture). Obx-rebuilds via
`TaskItemBuilder.draftRev`.

Pure display: no Firestore subscription, no txfController, no saveSend.

## Component fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | string | — | `task_draft_info` |
| `wizardKey` | string | `admin_create_task` | Cross-screen wizard identity |
| `text` | string | — | Diamond-separated labels: [0] Customer section label, [1] Vehicle section label, [2] Customer empty text, [3] Vehicle empty text |

## Data source

Reads from `AdminCreateTaskSupport.getCustomer(wizardKey)` and
`AdminCreateTaskSupport.getVehicle(wizardKey)` (static maps, not Firestore).

## Deploy coupling (op1Screen config) — REQUIRED for draft-carry to work

The draft-carry path is **wizardKey-gated end to end**. All four wizard
components must share the **same non-empty** `wizardKey` (convention:
`admin_create_task`), or the captured customer/vehicle will not reach P4 and
this card renders the empty state ("Belum dipilih") despite a successful pick:

| Page | Component | Required config |
|------|-----------|-----------------|
| P1 (row 1163) | `TASK_FEED_LIST` (flat) | `wizardKey:"admin_create_task"`; `idField` MUST be the customer-id column (e.g. `lv`) — it is captured into `kl`. `titleField`→`kn`, `addressField`→`al`. Default `idField` is `tnm` (driver), so the override is mandatory. |
| P3 (row 1178) | `PICKER_LIST` (capture) | `wizardKey:"admin_create_task"`; `titleField` is captured as the vehicle display name (`vn`). |
| P4 (this widget) | `TASK_DRAFT_INFO` | `wizardKey:"admin_create_task"` (matches P1/P3). |
| P4 (row 1190) | `TASK_CREATE_SUBMIT` | `wizardKey:"admin_create_task"` (reads the same draft). |

When `wizardKey` is **absent** on P1/P3, the renderer keeps the legacy behavior
(flat tap dispatches `#ACTIVE_TASK`; picker only writes `captureToken` into
screenTx) — backward-compatible, but no draft-carry. The code ships safely
before the config; the feature activates when the keys above are deployed.

P2 `TASK_ITEM_BUILDER._republishClient` resolves the picked customer's full
`kn`/`al` from `stock_location` and mirrors them into the draft, so re-picking a
different customer on back-nav refreshes the card (no stale address).

## See also

- [task_draft_summary.md](task_draft_summary.md) — item preview on P4
- [task_create_submit.md](task_create_submit.md) — submit button on P4
