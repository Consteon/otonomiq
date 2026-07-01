# TaskCreateSuccess

**SDUI type:** `task_create_success`
**File:** `lib/widget/task_create_success.dart`
**Status:** draft
**Added:** 2026-06-30

## Purpose

P5 success confirmation screen for the Admin create-task wizard (Stage-2
redesign, mockup `AdminCreateTaskIntegrated2.jsx` `SuccessScreen`). Renders an
eyebrow header + emerald success banner + summary card (customer / vehicle +
drop / pickup pills) + blue info hint + two navigation buttons.

Pure display: no Firestore subscription, no saveSend, no write path, no Obx.

## Data source

Reads `AdminCreateTaskSupport.getLastCreated(wizardKey)` — an in-memory snapshot
`{tnm, kn, vn, totalDrop, totalPickup}` stashed by `task_create_submit` AFTER a
successful create and BEFORE `clearDraft`. The draft itself is gone by the time
P5 renders, so the snapshot is the only source. `lastCreated` is deliberately
NOT cleared by `clearDraft`/`clearAllDrafts` (the latter fires on the P5 page's
own `buildPage`), and is overwritten on the next successful create.

When `getLastCreated` returns null (direct nav with no prior create) the widget
renders `SizedBox.shrink()` — defensive no-op (P5 is only reached via submit).

## Component fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | string | — | `task_create_success` |
| `wizardKey` | string | `admin_create_task` | Shared wizard identity (matches P1–P4) |
| `createAgainRoute` | string | — | Route for the primary "+ Buat Task Lagi" button |
| `backRoute` | string | — | Route for the secondary "Kembali ke Admin Feed" button |
| `text` | string | — | Diamond-separated labels (all optional, defaults below) |

### `text` slots
`[0]` eyebrow ("TASK CREATED") · `[1]` banner title ("Task Berhasil Dibuat") ·
`[2]` customer label · `[3]` vehicle label · `[4]` drop label · `[5]` pickup
label · `[6]` primary button · `[7]` secondary button · `[8]` info-hint text.

## Behavior

- Buttons navigate via `routeStack.push` BEFORE `gotoRoute`, guarded by
  `routeExist` + `stripRouteWrapper` (dead route → silent no-op).
- Success glyph is `Icons.check` (vector), not an emoji.
- Touch targets ≥44pt (primary 48h, secondary 44h).

## Deploy coupling (op1Screen)

Place a `task_create_success` component on the P5 success page
(`vertikaTeknoLokaciptaCreateTaskSuccess`) with `wizardKey` matching P1–P4 and
`createAgainRoute` / `backRoute`. Inert (renders nothing) until placed.

## See also

- [task_create_submit.md](task_create_submit.md) — P4 submit (stashes the snapshot)
- [task_draft_info.md](task_draft_info.md) — P4 cards + aggregate pickup breakdown
