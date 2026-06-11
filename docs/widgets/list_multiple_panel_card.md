# ListMultiplePanelCard

Reusable card-list widget that renders Firestore map-collection docs as cards
with N nav panels each, config-driven layout and labels.

- **File:** [lib/widget/list_multiple_panel_card.dart](../../lib/widget/list_multiple_panel_card.dart)
- **Support:** [lib/widget/panel_card_support.dart](../../lib/widget/panel_card_support.dart)
- **Class:** `ListMultiplePanelCard` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Dispatch type:** `list_multiple_panel_card`

## Purpose

Renders a list of cost-center (or any domain) cards from a Firestore
subcollection. Each card shows a header (name/subtitle from `<charcode>` doc
tokens), a colored status strip, and N tappable nav panels. Supports two
layout variants: `grouped` (accordion-by-status with rollup summary) and
`flat` (plain list). Labels, search fields, grouping, and route params are
all JSON-configurable for cross-domain reuse.

## Signature / Constructor

```dart
ListMultiplePanelCard({
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

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | `String` | -- | `LIST_MULTIPLE_PANEL_CARD` |
| `vidtable` | `String` | -- | Collection VID (app-level) |
| `table` | `String` | -- | `tableDocId//subColl` |
| `variant` | `String` | `flat` | `"grouped"` for accordion+summary; absent/`"flat"` for plain list |
| `thresholdMs` | `String` | `43200000` | Stale threshold (ms) for patrol aggregation |
| `statusLabels` | `String` | patrol defaults | `value◼groupLabel◼pillLabel` entries joined by `★` |
| `groupBy` | `String` | `{ws}` | Token resolved per card for grouping (grouped only) |
| `searchFields` | `String` | `an◆sn` | `◆`-separated doc char-codes for client search |
| `search` | `String` | `""` | Client-side equality filter (`field◼value`) |
| `conditions` | `String` | `""` | Client-side compound filter (`[[◀field▶◼value]]`) |
| `routeParam` | `String` | `av◼ccVid` | `docField◼token` for nav context dispatch |
| `showIcon` | `String` | `TRUE` | `"FALSE"` hides the 48px icon box |
| `showProgress` | `String` | -- | Reserved, no-op |
| `text` | `String` | -- | `◆<an>◆<sn>◆labelSearch◆hint◆emptyText` |
| `status` | `String` | -- | Card strip status token (`{ws}`, `<charcode>`, literal) |
| `panels` | `List` | `[]` | Array of panel configs (see below) |

Panel config:

| Key | Type | Default | Description |
|---|---|---|---|
| `icon` | `String` | -- | Icon name (`users`, `clipboard-check`, etc.) |
| `text` | `String` | -- | `label◆headline◆details` template |
| `status` | `String` | -- | Panel pill status token |
| `route` | `String` | -- | Target route name |
| `okText` | `String` | `""` | Override details when panel status is ok |
| `routeParam` | `String` | `""` | Per-panel routeParam override |

## State / Dependencies

- **GetX:** `mapTableContent` (reactive map-collection data via `subscribeToMapCollection`)
- **Redux:** `transactionStore` -- dispatches `{token, request_vid, panel_route}` on panel tap
- **Subscriptions:** site + workforce + event subcollections (unconditional, harmless empty reads)
- **Aggregation:** `computeKehadiran` (workforce) + `computePatroli` (event joined to site `ll[].ln`)

## Important Behavior

- **variant absent = FLAT** -- this is intentional (spec-strict). Existing patrol configs must add `variant:"grouped"` to keep accordion layout.
- **statusLabels** must be `autheniumDecode`d before parsing (server sends `_25FC_` for `◼`).
- **groupBy** only read when variant is `grouped`; a group key outside the statusLabels tier set falls into the LAST entry of `statusLabels` (so the card still renders and stays counted).
- **Unknown status values** (a resolved pill/strip status not in `statusLabels`) render the pill with the raw value text and ok-tier colors (agreed fallback).
- **Patrol join** uses `ln` (location name), NOT `lq` (QR id).
- **Dropped fields:** `staleMs` (renamed to `thresholdMs`), `ledgerCode`, `computeMode`, `toDo` -- these are not read.

## See Also

- [panel_card_support.dart](../../lib/widget/panel_card_support.dart) -- parse/aggregate helpers
- [statistic_card_support.dart](../../lib/widget/statistic_card_support.dart) -- `filterByCharCodeEquality`
