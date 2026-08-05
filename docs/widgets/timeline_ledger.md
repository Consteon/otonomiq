# TimelineLedger

Config-generic grouped + expandable audit timeline widget (TIMELINE variant `ledger`). Renders period-selectable, newest-first grouped cards from a Firestore map collection, with category-colored badge pills, configurable grouping, and expandable item lines.

- **File:** [lib/widget/timeline_ledger.dart](../../lib/widget/timeline_ledger.dart)
- **Support:** [lib/widget/timeline_ledger_support.dart](../../lib/widget/timeline_ledger_support.dart)
- **Class:** `TimelineLedger` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Dispatch:** `tip == 'timeline'` + `tlVariant == 'ledger'` in `build_display_component.dart`

## Purpose

Renders a scrollable, period-filtered timeline of audit/history documents from any Firestore map collection. Two modes: **grouped** (group by a configurable field, expand to see per-item lines) and **flat** (one card per doc, no expand). All labels, fields, and badge maps are config-driven -- zero hardcoded strings or colors.

First consumer: stock movement history (admin/supervisor). Reusable for nota history, task history, event timeline by swapping table + field params.

## `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `String` | yes | -- | `"TIMELINE"` |
| `variant` | `String` | yes | -- | `"ledger"` |
| `vidtable` | `String` | yes | -- | App VID for Firestore subscription |
| `table` | `String` | yes | -- | `"tableDocId//subColl"` |
| `conditions` | `String` | no | -- | Filter: `"[[field-value]]"`. `{key}` tokens resolve from screenTx bare keys via `resolveScreenTxTokens`. Fail-closed if unresolved. |
| `period` | `String` | no | -- | Period tabs: `"label-ms-star-label-ms"` |
| `periodDefault` | `String` | no | first tab | Default period ms |
| `timeField` | `String` | no | `"t"` | Doc field for epoch time (sort + period filter) |
| `title` | `String` | no | -- | Page title. `{count}` = total matched docs. |
| `subtitle` | `String` | no | -- | Page subtitle. `{count}` = total matched docs. |
| `groupField` | `String` | no | `""` | Empty = flat mode; non-empty = grouped mode. |
| `groupField2` | `String` | no | `""` | Empty = 1-level (existing). Non-empty = 2-level: SECTION (by groupField2) -> cards (by groupField). |
| `sectionText` | `String` | no | `""` | Section header template (2-level mode). `<field>` from representative doc, `{sectionCount}` = total movements, `{groupCount}` = event cards, `{sectionTime}` = HH:mm of earliest movement. |
| `badgeField` | `String` | no | -- | Doc field for badge value. |
| `badgeMap` | `String` | no | -- | `"value-Label-star-value-Label"` value-to-label mapping. |
| `condMap` | `String` | no | `""` | `"value-Label-star-value-Label"` condition value-to-label map. Applied to `<cd>` token at render time (all templates). Empty/absent = raw `cd` value passthrough (zero regression). |
| `headText` | `String` | no | -- | Template for card header (e.g. `"<ts>"`). `<field>` from doc. |
| `titleText` | `String` | no | -- | Template for card title (e.g. `"<fln> -> <tln>"`). |
| `subText` | `String` | no | -- | Template for card subtitle. `{n}` = items in group. Diamond-segmented. |
| `itemText` | `String` | no | -- | Per-item line template (expand). Diamond-segmented. |
| `refText` | `String` | no | -- | Reference line (small, muted) in expanded view. |
| `expandable` | `String` | no | `"TRUE"` | `"TRUE"`/`"FALSE"` for grouped mode. |

## Token resolution

Condition tokens (`{vehicleId}` etc.) resolve via `resolveScreenTxTokens` (statistic_card_support.dart), NOT `resolveDriverCurlyTokens` (driver_home_support.dart). The latter has a hardcoded `case 'vehicleId'` that reads from DriverHomeState (driver session), which is EMPTY for admin/supervisor users and SHADOWS the bare screenTx key from routeParams.

Templates resolve via `resolveMapTokens()`:
1. `<field>` -- replaced by `doc[field].toString()`. Missing = empty.
2. `{count}` -- total matched docs (title/subtitle only).
3. `{n}` -- number of docs in the group (subText only).
4. `{sectionCount}` -- total docs in the section (sectionText only).
5. `{groupCount}` -- number of event cards in the section (sectionText only).
6. `{sectionTime}` -- HH:mm of the earliest movement in the section (sectionText only).

## Badge coloring

Badge colors come from a category palette (8 colors), assigned by the ORDER of keys in `badgeMap`. Value not in badgeMap renders the raw value with neutral gray. The palette is defined in `timeline_ledger_support.dart`.

## Condition relabel (condMap)

The `condMap` param relabels the `cd` (condition) field value for DISPLAY only, using the same encoding as `badgeMap` (`value-Label-star-value-Label`). The underlying `cd` data value (`full`, `empty`, etc.) is never changed -- it stays canonical for grouping, filtering, badge logic, and all other widgets.

Applied at all three render entry points (`_buildItemRow`, `_buildCard`, `_buildSectionHeader`) so `<cd>` works in any template. When `condMap` is empty or absent, behavior is identical to before (raw passthrough).

## See Also

- [timeline_periodic.md](timeline_periodic.md) -- the `periodic` variant (patrol timeline)
