# WorkspaceHeader

Top-bar header for P11 DeliveryWorkspace and admin wizard step pages.

- **File:** [lib/widget/workspace_header.dart](../../lib/widget/workspace_header.dart)
- **Class:** `WorkspaceHeader` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Provides the top-bar context for workspace screens. Two rendering modes:

1. **Driver-stop (default):** Task identity (stop number, customer name, "BERJALAN" chip, address band) for P11 DeliveryWorkspace. Subscribes to task collection and derives stop number from doc-order position.
2. **Step header (`variant:"step"`):** Clean title + step subtitle for admin create-task wizard (P2/P3/P4). No in-header back arrow (app bar handles back). No data subscription.

## Component JSON

### Default (driver-stop)

```json
{"type":"WORKSPACE_HEADER","vidtable":"20342033315492","table":"84214220504259//task","search":"tnm◼{activeTaskVid}","listSearch":"vv◼{vehicleId}⭘tdt◼{today}","idField":"tnm","titleField":"kn","addressField":"al","backRoute":"vertikaTeknoLokaciptaTaskFeed","text":"Stop◆Berjalan"}
```

### Step variant (admin wizard)

```json
{"type":"WORKSPACE_HEADER","variant":"step","text":"Pilih Kendaraan◆Langkah 3 dari 4"}
```

Step mode renders **title + step subtitle only** (no in-header back arrow) — back navigation is handled by the app bar (pops `routeStack`).

**No-data diagnostic (driver-stop):** when no task doc matches (`monoText` and customer both empty) the header still renders — the left title falls back to text slot **[0]** (uppercased), the chip keeps slot **[1]**. Before the fix the fallback reused slot [1], so both sides printed the same string.

| Field | Type | Required | Description |
|---|---|---|---|
| `variant` | string | No | `"step"` for admin step header; absent/other = driver-stop |
| `text` | diamond `◆` | Rec. | Step: slot 0 = title (bold), slot 1 = step subtitle (grey). Driver-stop: slot 0 = stop prefix (default `Stop`), slot 1 = chip label (default `Berjalan`). Absent = renders empty (safe). |
| `backRoute` | string | No | Driver-stop only. Ignored in step mode (app bar handles back). |

## Data Source

**Driver-stop:** Subscribes to `84214220504259//task` via `subscribeToMapCollection`. Finds the active task doc via `filterDriverHomeDocs` with `search:"tnm◼{activeTaskVid}"`. The `{activeTaskVid}` token is resolved from `#ACTIVE_TASK` in transactionStore via `resolveDriverCurlyTokens`.

**Step variant:** No data subscription. Reads only `text` and `backRoute` from the component JSON.

## Stop number (P10-scoped, driver-stop only)

The stop number is NOT counted over the raw subscription. It is derived by ordering ALL task docs with the SAME vehicle+today filter P10 uses (`listSearch`, default `vv◼{vehicleId}⭘tdt◼{today}` when the JSON omits it), then taking the 1-based doc-order position of the `{activeTaskVid}` match WITHIN that filtered list. This keeps the P11 stop number in lock-step with the card the driver tapped in P10 (mirrors `task_feed_list.dart` `_getFilteredTasks()` + `globalIndex`).

## See Also

- [route_feed_header.md](route_feed_header.md) -- P10 header (vehicleId publisher)
- [custody_step_header.md](custody_step_header.md) -- P6 header (similar pattern)
