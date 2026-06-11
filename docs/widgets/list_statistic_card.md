# ListStatisticCard

Per-point patrol/cleaning statistic list for one cost center, rendering official points from the site doc `ll[]` array as status cards.

- **File:** [lib/widget/list_statistic_card.dart](../../lib/widget/list_statistic_card.dart)
- **Class:** `ListStatisticCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Dispatch:** `tip == 'list_statistic_card'` (non-keyed variant; `variant:"keyed"` routes to `ListStatisticCardKeyed`)

## Purpose

Renders a period-selectable list of patrol/cleaning points for a cost center. Each card shows visit count, recency, evidence quality, and a severity status strip. Supports searching and tapping through to a point timeline.

## `component` shape

| Key | Type | Description |
|---|---|---|
| `type` | `String` | `"LIST_STATISTIC_CARD"` |
| `vidtable` | `String` | App VID for Firestore subscription |
| `table` | `String` | `"<tableDocId>//<subColl>"` (e.g. `"84214220504259//site"`) |
| `mergeTyped` | `String?` | Char-code field used as dedup key for merge (e.g. `"ln"`). When present and non-empty, enables typed-location merge mode. |
| `search` | `String` | Equality filter, e.g. `"av◼{ccVid}"` |
| `conditions` | `String` | Alternative filter syntax `"[[◀av▶◼{ccVid}]]"` |
| `text` | `String` | Diamond-separated: `searchHint◆inputPlaceholder◆emptyMessage` |
| `period` | `String` | Period tabs: `label◼ms★label◼ms...` (autheniumDecode first) |
| `periodDefault` | `String` | Default period in ms |
| `staleMs` | `String?` | Staleness threshold in ms (default 43200000 = 12h) |
| `stats` | `String` | Stat boxes: `{token}◆label★...` (autheniumDecode first) |
| `content` | `String` | Card template: `<field>◆literal◆{token} text◆...` |
| `status` | `String` | Status token template (e.g. `"{ps}"`) |
| `badge` | `String` | Badge token template (e.g. `"{evidence}"`) |
| `route` | `String` | Route name for card tap |

## Merge Mode (`mergeTyped`)

When `mergeTyped` is present and non-empty:

1. Events are scoped: `ty` contains `'report-patrol'`, `av` == resolved `{ccVid}`, and epoch within the active period window.
2. Events are grouped by `ln.toLowerCase()` (case-insensitive).
3. Orphan events (not matching any official `ll[].ln` by lowercase) are collapsed N-to-1 and rendered as additional cards with forced `ps:'warn'` and `evidence:'GPS saja'`.
4. Stats change: `{totalVisits}` = all scoped events; `{typedCount}` = distinct orphan group count.

Without `mergeTyped`, behavior is unchanged (exact-case matching, old `typedCount` = empty-lq events at official points).

## Notes

- `ledgerCode` field: referenced in some older JSON specs but NEVER read by this widget or any list widget. It is only relevant to the `addToEvent` write path. Safely ignored.
- Tap handler sets screenTx keys: `point`, `pointId`, `pointName`, `point_route`, `site`. Typed-only cards set `pointId: ''`.
- Navigation uses `routeStack.push(route)` before `gotoRoute(route)`.

## See Also

- [ListStatisticCardKeyed source](../../lib/widget/list_statistic_card_keyed.dart) (keyed variant for attendance)
- Support functions: `lib/widget/statistic_card_support.dart`

## Variant: keyed (attendance / generic keyed collection)

- **File:** [lib/widget/list_statistic_card_keyed.dart](../../lib/widget/list_statistic_card_keyed.dart)
- **Class:** `ListStatisticCardKeyed`
- **Dispatch:** `tip == 'list_statistic_card'` with `component['variant'] == 'keyed'`

### Chip content (`content`)

The `content` field is diamond-separated (`diamondTextToList`). Each segment is classified:

- **No `◼`** -- plain text. First plain segment = title row (name); subsequent = text lines (backward compat with pre-chip configs).
- **Contains `◼`** -- chip spec: `iconName◼valueTemplate`. Icon resolved via `stringToIconData()` (global2.dart). Value resolved via `resolveMapTokens`, then `formatTimeShort` (extracts first `HH:MM`; empty = em-dash).

Parts beyond the second `◼` are ignored (forward-compat for a future `iconName◼value◼tone` extension).

Note: the title row is the first PLAIN segment, not necessarily segment index 0. A config that starts with a chip segment (e.g. `login◼<is>◆<n>◆logout◼<os>`) still picks `<n>` as the title.

Example: `<n>◆login◼<is>◆logout◼<os>` produces a name title, then a chip row with login-icon + clock-in time and logout-icon + clock-out time.

### Chip tone

- Value filled (non-empty, not placeholder) -- tone `'ok'` (green).
- Value empty/placeholder -- tone inherits the card's `{status}` (danger=red, warn=amber, ok=green).

### Badge pill (`badge`)

Template resolved via `resolveMapTokens` with per-worker doc + computed tokens. Empty/whitespace result suppresses the pill entirely. Rendered on the title row before the chevron. Style: `statusBgColor(cardStatus)` background, `statusColor(cardStatus)` text, 11px w700, radius 20, padding h10 v4.

### Icon names

Uses `stringToIconData()` lookup (global2.dart, ~400 entries, lowercase match). Fallback: `Icons.help_outline`. Entries added for kehadiran: `login`, `logout`, `camera_alt`.

### `autheniumDecode` on content

The raw `content` string is decoded via `autheniumDecode()` before `diamondTextToList` splitting. This handles server-encoded `◼` (`_25FC_`) within chip specs.
