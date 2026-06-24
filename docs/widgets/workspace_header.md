# WorkspaceHeader

Top-bar header for P11 DeliveryWorkspace showing task identity, stop number, customer name, status chip, and address band.

- **File:** [lib/widget/workspace_header.dart](../../lib/widget/workspace_header.dart)
- **Class:** `WorkspaceHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Provides the top-bar context for the delivery workspace screen. Displays the active task's ID, stop number (derived from doc-order position), customer name, a "BERJALAN" status chip, and an address band. Includes a back arrow that navigates to the TaskFeed via routeStack.push + gotoRoute.

## Component JSON

```json
{"type":"WORKSPACE_HEADER","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","listSearch":"vv◼{vehicleId}⭘tdt◼{today}","idField":"tnm","titleField":"kn","addressField":"al","backRoute":"vertikaTeknoLokaciptaTaskFeed","text":"Stop◆Berjalan"}
```

## Data Source

Subscribes to `84214220504259//task` via `subscribeToMapCollection`. Finds the active task doc via `filterDriverHomeDocs` with `search:"tnm◼{activeTaskVid}"`. The `{activeTaskVid}` token is resolved from `#ACTIVE_TASK` in transactionStore via `resolveDriverCurlyTokens`.

## Stop number (P10-scoped)

The stop number is NOT counted over the raw subscription. It is derived by ordering ALL task docs with the SAME vehicle+today filter P10 uses (`listSearch`, default `vv◼{vehicleId}⭘tdt◼{today}` when the JSON omits it), then taking the 1-based doc-order position of the `{activeTaskVid}` match WITHIN that filtered list. This keeps the P11 stop number in lock-step with the card the driver tapped in P10 (mirrors `task_feed_list.dart` `_getFilteredTasks()` + `globalIndex`).

## See Also

- [route_feed_header.md](route_feed_header.md) -- P10 header (vehicleId publisher)
- [custody_step_header.md](custody_step_header.md) -- P6 header (similar pattern)
