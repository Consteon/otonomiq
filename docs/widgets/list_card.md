# ListCard (`LIST_CARD`)

Universal config-driven keyed-collection list renderer — one widget that consolidates the intent of the ~7 overlapping list types (`LIST_ITEM_CARD`, `PICKER_LIST`, `LIST_MULTIPLE_PANEL_CARD`, `LIST_STATISTIC_CARD`, `TASK_FEED_LIST`, `taskFeedListFlat`, `displayList`). The standard list going forward; old types stay for back-compat.

- **File:** [lib/widget/list_card.dart](../../lib/widget/list_card.dart) · support: [lib/widget/list_card_support.dart](../../lib/widget/list_card_support.dart)
- **Class:** `ListCard` (StatefulWidget)
- **Status:** done (Dart renderer) — deploy-coupled: inert until a screen JSON references `type:"LIST_CARD"`
- **Widget version:** v1
- **Introduced on branch:** `feat/list-card-universal`
- **Dev spec:** `list-card-universal-dev-spec.md`

## Purpose

Renders a single Firestore keyed collection (`{tenant}//table`) as a card list, filtered/sorted/grouped entirely from JSON config. Every display string comes from config (no hardcoded labels). Every optional field left empty = that element is not rendered (the card shrinks itself). Whole-card tap navigates via multi-pair `routeParams` (row-first resolution, session fallback — the `rbt-route-params` §9 contract).

Use `LIST_CARD` for any new keyed list. Reach for a legacy type only when maintaining an already-deployed screen that uses it.

## Signature / Constructor

```dart
ListCard({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

Dispatched from `build_display_component.dart` on `tip == 'list_card'`, cached in `linkElement[scrName][position]` like every other component.

### `component` shape

All separators are server-encoded and `autheniumDecode`-d before splitting: `◼` (`_u25FC_`), `⭘` (`_u2B58_`), `★` (entry separator), `◆` (`text` segment separator). All fields are optional unless noted — an empty field hides its element, never crashes.

| Key | Description |
|---|---|
| `vidtable` | App vid for the vid-scoped subscription key (`resolveAppVid`). |
| `table` | Keyed collection, `{tenant}//name` (e.g. `84214220504259//fate_project`). **Required** to show anything. |
| `search` | WHERE DSL `key◼value⭘key2◼value2`; `{token}` resolved from `screenTx` (e.g. `pn◼{projectVid}`). **Fail-closed:** an unresolved `{token}` yields an empty list, not "show all". |
| `conditions` | Second live-query filter, same DSL, applied after `search`. |
| `sortField` / `sortDir` | Numeric-coerced sort; `sortDir` = `asc`\|`desc`. Empty `sortField` = arrival order. |
| `groupBy` | Field key to section by; empty = flat list. |
| `groupLabels` | `value◼Label★value2◼Label2` — section order follows this list; data values not listed here append at the bottom as-is; empty sections are hidden. |
| `lead` | `""` = no leading · `initial` = first letter of the resolved title · else an icon name (`panelIcon`). |
| `title` | Template, `<field>` tokens from the row doc (e.g. `<tt>`). |
| `subtitle` / `meta` | Templates (e.g. `<bn> · <vn>`, `<dt> · <st>–<et>`); empty = hidden. |
| `badgeField` | Row key whose value selects the badge; empty = no badge. |
| `badgeMap` | `value◼Label◼tier★…` — `tier` ∈ `danger`\|`warn`\|`ok`\|`neutral`. Colors come from the theme (`statusColor`/`statusBgColor`); `neutral` aliases to the `info` palette. Missing tier defaults to `info`. |
| `trailing` | Right-aligned value template; empty = hidden. |
| `trailingLabel` | Small caption under `trailing`. |
| `stats` | `Label◼filter★Label2◼filter2` — one count box per entry. **Label is split from filter at the FIRST `◼` only** (the filter DSL itself uses `◼`). Empty filter = count all rows from `search`. Counts come from the `search`/`conditions` result, before the search-bar text. Empty `stats` = strip hidden. |
| `searchFields` | `key◆key2` — fields the search bar matches (case-insensitive contains). Empty = search bar hidden. |
| `route` | Destination route on card tap. |
| `routeParams` | `key◼{field}⭘key2◼{field2}` — multi-pair. `{field}` resolves from the tapped row first, then session token; the `key` becomes a bare `screenTx` token on the destination page; all pairs pushed. Literal (non-`{}`) values pushed as-is. |
| `text` | Static labels, `◆`-joined: `headerTitle◆headerSubtitle◆countLabel◆searchHint◆emptyText`. Any empty segment hides its element. |

## Templates use `<field>` angle syntax

`title`/`subtitle`/`meta`/`trailing`/`trailingLabel` resolve `<field>` tokens from the row doc via `resolveMapTokens`. `{field}` (curly) is **not** substituted in these templates and renders literally — use angle brackets. (Curly `{field}` is only for `search`/`conditions`/`routeParams`, which resolve against `screenTx`/the tapped row.)

## Anatomy

```
[HEADER  title + subtitle + count]     text[0..2]   (hidden if text[0] empty)
[STATS   count box ×N]                  stats        (hidden if stats empty)
[SEARCH  bar]                           searchFields (hidden if empty)
[GROUP   section label]                 groupBy      (flat if empty)
[CARD]  (lead) title [badge] / subtitle / meta … trailing+trailingLabel
[EMPTY  text[4]]                        when 0 rows
```

## Reused machinery (no reinvention)

`filterDriverHomeDocs` (search/conditions + token resolve), `resolveMapTokens` (`<field>`), `writeRouteParamsFromRow` (routeParams §9), `groupByField`, `statusColor`/`statusBgColor` (badge tiers), `evaluateGate` (stats counts), `subscribeToMapCollection` + `resolveAppVid` (vid-scoped subscription), `coerceNum` (sort), `panelIcon` (lead icon). Pure config parsers (`parseBadgeMap`/`parseGroupLabels`/`parseStatsDefs`/`computeStatsCounts`/`lookupBadge`) live in `list_card_support.dart` and are unit-tested in [test/list_card_support_test.dart](../../test/list_card_support_test.dart).

## Notes / gotchas

- **`list_card_support.dart` is consumed by direct import, NOT the `all_widget.dart` barrel** — its public `class BadgeEntry` (`String tier`) would collide (`ambiguous_export`) with `timeline_ledger_support.dart`'s `BadgeEntry` (`int index`). This matches the `panel_card_support`/`statistic_card_support` precedent.
- **Header count** shows the total (`search`/`conditions` result), not the live search-bar subset.
- **Viewport height** is a fixed `MediaQuery.height * 0.79` (house convention, mirrors `ListMultiplePanelCard`).
- **Read-only** — no history writes, no offline queue involvement.
