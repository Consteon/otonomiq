# AdminOutstandingList

"PRIORITAS PENGAMBILAN" collapsible card for Admin Home (H1): client-grouped outstanding items with aging-tier badges and a (deferred) "Jadwalkan" button.

- **File:** [lib/widget/admin_outstanding_list.dart](../../lib/widget/admin_outstanding_list.dart)
- **Class:** `AdminOutstandingList` (StatefulWidget, `SingleTickerProviderStateMixin`)
- **Status:** draft
- **Widget version:** v1
- **Introduced in commit/version:** Admin Home R2 (slice 2)
- **Dispatch type:** `ADMIN_OUTSTANDING_LIST` (matched lowercase as `adminoutstandinglist`)

## Purpose

A single white, collapsible card listing clients with outstanding (net-positive) returnable inventory, sorted oldest-first, each tagged with an aging tier (KRITIS / PERHATIAN / NORMAL). It cross-collection-derives from `asset_cache` + `stock_location`. The "Jadwalkan" action is DEFERRED in this slice (snackbar only — no nav, no create-with-array). CF-gated: collapses entirely until `asset_cache` client docs exist.

## Signature / Constructor

```dart
AdminOutstandingList({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### `component` shape

| Key | Type | Description |
|---|---|---|
| `vidtable` | `String` | appVid, resolved via `resolveAppVid` |
| `assetTable` | `String` | `asset_cache` table path `tableDocId//asset_cache` |
| `clientTable` | `String` | `stock_location` table path (client-name lookup, `lt=client`) |
| `text` | `String` | `◆`-separated label slots (see below) |

### `text` slots (◆-separated, length-guarded via `_t(i, def)`)

| Index | Default | Meaning |
|---|---|---|
| `[0]` | `PRIORITAS PENGAMBILAN` | collapsible header (UPPERCASE) |
| `[1]` | `Jadwalkan` | per-row schedule button label |
| `[2]` | `KRITIS` | aging-tier badge (> `dangerAge` days, default 14) |
| `[3]` | `PERHATIAN` | aging-tier badge (> `warnAge` days, default 7) |
| `[4]` | `NORMAL` | aging-tier badge (≤ `warnAge` days, default 7) |
| `[5]` | `Fitur ini sedang dikembangkan` | deferred-action snackbar message |

### Config params (R3)

All optional; absent = current defaults (backward-compatible). Threaded through to `groupOutstanding`.

| Key | Default | Meaning |
|---|---|---|
| `titleField` | `'lv'` | field on `asset_cache` used as the client grouping key (passed as `lvField`) |
| `itemField` | `'ii'` | field for the item identifier (passed as `iiField`) |
| `qtyField` | `'qt'` | field for quantity (passed as `qtField`) |
| `ageAnchorField` | `'t'` | field for the aging anchor timestamp (passed as `tField`) |
| `locationNameField` | `'ln'` | field on `stock_location` for the client name (passed as `lnField`) |
| `dangerAge` | `14` | days threshold for the KRITIS tier |
| `warnAge` | `7` | days threshold for the PERHATIAN tier |
| `emptyText` | `'Tidak ada outstanding \u{00B7} semua sudah tertagih'` | Text rendered when the grouped result is empty (spec section 5.3). Panel chrome (header + chevron) always renders. |

## Data sources / derive

- **Group:** `groupOutstanding(assetCacheDocs, stockLocations, ...field/threshold overrides)` from `admin_home_support.dart`:
  - Filters `asset_cache` to `lt == 'client'`; skips items with `qt <= 0`.
  - Groups by `lv` (client id); sums `qt` per group; **hideZero** — drops groups whose net total ≤ 0.
  - Aging days = oldest item's `(now - t) / 86400000` (now = `getNowMillisecondFromEpoch()`).
  - Tier via `agingTierDays(days, dangerDays:, warnDays:)` — `kritis` (> danger), `perhatian` (> warn), else `normal`. Defaults are the consts `kKritisThresholdDays = 14` / `kPerhatianThresholdDays = 7` (dev-spec section-3.2), overridable per-component via `dangerAge` / `warnAge`.
  - Client name from `stock_location` (indexed by `lv`, `lt=client`, field `ln`/`locationNameField`); falls back to the raw `lv` id.
  - `itemSummary` = `"{firstItemName} · {totalQty} pcs · {agingDays} hari"` (via `formatAgeDays`); falls back to `"{totalQty} pcs · {agingDays} hari"` when the first item name is empty.
  - Sorted by aging desc (oldest = most urgent first).

## State / Dependencies

- **Subscriptions:** `subscribeToMapCollection` into `mapTableContent`; typed reads via `List<Map<String,dynamic>>.from(...)`.
- **Pure helpers:** `groupOutstanding`, `agingTierDays`, `formatAgeDays` + the `OutstandingGroup` / `OutstandingItem` models (admin_home_support.dart).
- **Expand/collapse state:** local widget `State` — a `bool _expanded` (default `true`) + an `AnimationController` driving a chevron `RotationTransition` (200ms, respects platform reduced-motion). Deliberately NOT an RxMap mutated in build (avoids setState-during-build).
- **Side effects:** none — "Jadwalkan" only shows a snackbar (deferred).

## Important Behavior

- Empty groups → panel still renders (Container + collapsible header + chevron); body shows muted `emptyText` when expanded (spec section 5.3: "panel tetap muncul"). CF-gated: `emptyText` appears until `asset_cache` data is seeded.
- "Jadwalkan" tap → snackbar from `text[5]`; no navigation, no write. The schedule wizard is a future slice.
- Each "Jadwalkan" button carries a `minHeight: 44` constraint (≥44pt touch target).

## See Also

- [admin_active_trip_list.md](admin_active_trip_list.md) — "BERJALAN" sibling.
- [admin_upcoming_task_list.md](admin_upcoming_task_list.md) — "AKAN DATANG" sibling.
- [coordination_signal_list.md](coordination_signal_list.md) — the "Perlu Tindakan" panel on the same screen.
