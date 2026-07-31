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
| `note` | Optional display line template with `<field>` tokens. Empty = hidden. If any token resolves empty/missing, the whole line is hidden. If the note does not appear, check the token spelling first — a misspelled `<field>` is hidden exactly like an unstamped one. |
| `badgeField` | Row key whose value selects the badge; empty = no badge. |
| `badgeMap` | `value◼Label◼tier★…` — `tier` ∈ `danger`\|`warn`\|`ok`\|`neutral`. Colors come from the theme (`statusColor`/`statusBgColor`); `neutral` aliases to the `info` palette. Missing tier defaults to `info`. |
| `trailing` | Right-aligned value template; empty = hidden. |
| `trailingLabel` | Small caption under `trailing`. |
| `stats` | `Label◼filter★Label2◼filter2` — one count box per entry. **Label is split from filter at the FIRST `◼` only** (the filter DSL itself uses `◼`). Empty filter = count all rows from `search`. Counts come from the `search`/`conditions` result, before the search-bar text. Empty `stats` = strip hidden. |
| `searchFields` | `key◆key2` — fields the search bar matches (case-insensitive contains). Empty = search bar hidden. |
| `route` | Destination route on card tap. |
| `routeParams` | `key◼{field}⭘key2◼{field2}` — multi-pair. `{field}` resolves from the tapped row first, then session token; the `key` becomes a bare `screenTx` token on the destination page; all pairs pushed. Literal (non-`{}`) values pushed as-is. |
| `gateTable` | Slot gate: keyed collection for grant docs. Bare name (e.g. `grant`) = subcollection under the same `table` docId. Full path (`{tenantDocId}//grant`) also accepted. **This key alone decides whether gating is requested** — empty = gating OFF, non-empty = gating ON and every later failure is fail-closed. |
| `gateSearch` | Search DSL to find the current user's grant docs (passed raw to `filterDriverHomeDocs`). Example: `ty◼approver⭘vid◼{userVid}`. **Required whenever `gateTable` is set** — leaving it empty does NOT disable gating, it yields an empty list. **Must identify the user by the `{userVid}` token, never a literal vid** — see "Identity" below. |
| `gateSlot` | `slotField◆pointerField◆levelField` — names the fields in the grant doc (slot assignments) and request doc (pointer + level). Example: `sc◆ak◆cl`. **Required whenever `gateTable` is set** — empty/unparseable yields an empty list, not "gating off". |
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

## Slot gating (approval queue filter)

When `gateTable`, `gateSearch`, AND `gateSlot` are ALL non-empty, slot gating is active:

1. Subscribes to the gate collection and filters by `gateSearch` to find the logged-in user's grant docs.
2. Parses each grant doc's slot field (`sc`) into concrete terms (`ccVid-level`) and wildcard terms (`*-level`).
3. Unions across all matched grant docs (a user may have multiple grant entries).
4. Filters request docs: visible iff `row[pointerField] ∈ concrete` OR `row[levelField] ∈ wildcardLevels`.

### `gateTable` is the intent switch — everything else fails CLOSED

There are exactly two states, and they are deliberately not symmetric:

| `gateTable` | Result |
|---|---|
| absent / empty | Gating was never requested. Docs pass through untouched — identical to pre-gating behavior. This is the back-compat path for every screen that predates gating. |
| present | Gating WAS requested. From that point on **every** failure yields an EMPTY list, never the unfiltered set: `gateSlot` unparseable, `gateSearch` empty, gate subscription never resolved (`_gateCode` empty), no grant doc matched, slot field yielded no terms, or any thrown exception. |

**Why it is not symmetric:** an approval queue that cannot prove which slots the viewer holds must show nothing, not everything. Failing open leaks every pending request to every approver while still looking gated — and on `LIST_ACTION_CARD` it hands them working approve/reject buttons. A silently-empty queue is a visible, reportable bug; a silently-open one is not.

**Diagnosing an empty queue:** every fail-closed branch emits a `devPrint` naming the cause (`gate incomplete` with per-key flags · `no grant docs match gateSearch` with the gate-doc count and `gateCode` · `slot field yielded no terms` · `ERROR`). A successful gate logs `grants=N concrete={…} wildcardLevels={…} ptr="…" lvl="…" X→Y`. Silence on a screen showing rows means `gateTable` is absent, i.e. gating is off.

**Transient empty on first paint:** `subscribeToMapCollection` is async, so the grant collection may not have arrived on the first build. Fail-closed means the list is briefly empty, then fills on the next `Obx` rebuild once the stream lands. Self-correcting, by design.

### Identity — `{userVid}` is the logged-in session VID, and it MUST be the token

`{userVid}` resolves to `screenTx['#VID']` (`driver_home_support.dart:305-307`) — the VID written at login and nowhere else (`api.dart:1676` PIN path · `user_repository.dart:527` lif profile · `:798` Firestore user doc id). It is the **same value the approval writer stamps as the approver**: `api.dart:4699` / `:4802` read `state['#VID']` into `approverVid`, which lands in the event row and the chain step (`:4741`, `:4759`) — i.e. what becomes `l{N}by` on the request. Gate and stamp therefore agree by construction.

- **Never author a literal VID** in `gateSearch` (and never a tenant/app constant such as a Settings-sheet cell or a `dvby`-style baked value). A literal makes every device evaluate one person's slots — an approver would see, and could approve, another approver's queue. The token is what makes the gate per-session.
- **Logged out / `#VID` unset:** the token stays literal `{userVid}`, `filterByMultiClause` sees the `{` and returns empty — fail-closed, no queue. Free correctness, do not "fix" it.
- **Type:** `#VID` is an `int` (`api.dart:1676` `int.parse`) while grant `vid` is usually a String; comparison routes through `eq()` (`dsl_eq.dart:20`), which is type-tolerant. Do not add a manual cast.
- The detail-page button gate (`ApproverStickyBar`) resolves the identity through the **same** helper and token — see `docs/widgets/approval_detail.md`. One identity, one rule, two hosts.

**Level indicator:** uses the existing `meta` template slot. Set `meta:"Level <cl> / <nl>"` in the component JSON; `<cl>` and `<nl>` resolve from the request doc. Empty `meta` = no level line rendered (existing behavior).

**Scale ceiling:** client-side filter (v1). Fetches all docs matching `search`, then filters in-memory. Server-side `where ak in [...]` with composite index is the upgrade path.

**Cross-reference:** The ApproverStickyBar (detail page) uses the same gate infrastructure with a sibling key `gateRowSlot` (numeric row indexes instead of field names). See `docs/widgets/approval_detail.md` "Slot gate on ApproverStickyBar" for details. The RBT's `gateTable` MUST use the fully-qualified `{docId}//subColl` format (bare-name resolution is not available on the RBT). The RBT and list components SHOULD carry the same `vidtable`/`com` so they share a subscription key.

## Notes / gotchas

- **`list_card_support.dart` is consumed by direct import, NOT the `all_widget.dart` barrel** — its public `class BadgeEntry` (`String tier`) would collide (`ambiguous_export`) with `timeline_ledger_support.dart`'s `BadgeEntry` (`int index`). This matches the `panel_card_support`/`statistic_card_support` precedent.
- **Header count** shows the total (`search`/`conditions` result), not the live search-bar subset.
- **Viewport height** is a fixed `MediaQuery.height * 0.79` (house convention, mirrors `ListMultiplePanelCard`).
- **Read-only** — no history writes, no offline queue involvement.
