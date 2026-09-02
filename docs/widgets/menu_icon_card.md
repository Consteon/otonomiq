# menuIconCard (shared shell)

Shared visual shell for home-menu icon buttons. Source:
[lib/widget/menu_icon_card.dart](../../lib/widget/menu_icon_card.dart).
Not a component type — a plain function used by the `horizontal_icon`
children and their single modes:

| Caller | Modes |
|---|---|
| `goto.dart` | single + grid |
| `gps_send.dart` | single + grid |
| `attendance_qr_selfie_gps_verify.dart` | single + grid |
| `ftz_checker.dart` | single |
| `ui_component.dart` `disabledIcon` | grid (wrapped in `Opacity 0.55`) |
| `ui_component.dart` `buildGridList` | `vgr` / `hgr` grid items (Laporan, Formulir, dst.) |

## Look

White card, radius 16, hairline border `0xFFE2E8F0` (same as the
`time_presence` stat chips), flat — no shadow, ink ripple clipped to the
rounded shape. Content is vertically centered: fixed 36px icon
(`BoxFit.contain`), 6px gap, 2-line-max label weight 500 wrapped in
`Flexible` (shrinks instead of overflowing on very narrow screens); config
`fontSize` is **clamped to 12–13** so every menu section shares one caption
scale regardless of per-section sheet values.

## Grid layout (4 fixed columns)

The `horizontal_icon` and `hgr` branches in `build_display_component.dart`
render a **non-scrolling 4-column `GridView.count`** (`shrinkWrap`,
`NeverScrollableScrollPhysics`, `childAspectRatio: 0.85`) — more than 4
items wrap to new rows; the page scrolls, the grid never scrolls
horizontally. Cell size is screen-derived: sheet-config `width`/`row` no
longer size the cells (dead for these two branches; `vgr` still honours
`width`). In a tight grid cell the card fills the cell; in single mode
(unbounded height) it hugs content.

## Signature

```dart
Widget menuIconCard({
  required String imageUrl,   // '' falls back to defaultImage
  required String label,
  required double fontSize,
  void Function()? onTap,
  int badgeCount = 0,         // <= 0 renders nothing at all
})
```

## Menu badge (`HGR` / `VGR` children only)

A numeric "new since I last visited" badge, computed entirely on the device.
Logic lives in `class MenuBadge` in the same file; only `buildGridList`
(`ui_component.dart`) passes a non-zero `badgeCount`. The other seven callers
are untouched — the parameter is optional and defaults to `0`.

### Config (child level of the grid component)

| field | meaning | empty / absent |
|---|---|---|
| `badgeTable` | Collection path, same format as `table` on the destination `LIST_ITEM_CARD` (e.g. `84214220504259//report`) | **Hard gate** — no subscription, no `Obx`, no badge |
| `badgeSearch` | WHERE-clause DSL `key◼value⭘key◼value` (e.g. `7◼83674161979544`) | every doc counts |
| `badgeTs` | Epoch-ms field name compared against lastSeen | defaults to `t` — **diverges from the spec dictionary on purpose**, see the note below |
| `badgeVidtable` | Tenant VID owning the collection. Copy the destination `LIST_ITEM_CARD`'s `vidtable` value into this key. **The name must be exact** — a near-miss such as `badgeVid` is not read, it is silently ignored | falls through the `resolveAppVid` chain: `vidtable` on the same child, else `getTableVid(com)`, else `applicationTableVid`. A child that already carries a correct `vidtable` therefore still resolves correctly. Only when *none* of those is right does the badge land on another tenant — and then the collection is simply never found, so it sits at `0` with no error and no log |
| `vidtable` | The repo-wide tenant field (`resolveAppVid`). Read **only** when `badgeVidtable` is blank | `getTableVid(com)` → `applicationTableVid` |

Copy `badgeTable` / `badgeSearch` / `badgeVidtable` **verbatim** from the
destination page's `LIST_ITEM_CARD` (its `table` / `search` / `vidtable`) — that
is what guarantees the number matches the list. Take **all three**, not two of
three.

Do not, however, "fix" a working tile by adding `badgeVidtable` to it. A child
that already carries a correct `vidtable` resolves the right tenant through
`resolveAppVid` on its own; pasting a `badgeVidtable` value copied from
somewhere else *overrides* that and is how a working badge becomes a
permanently-zero one. Copy the destination card's own `vidtable`, or leave the
key out.

> **Deliberate divergence — blank `badgeTs`.** The spec dictionary (§8) says a
> blank `badgeTs` means the badge is **not rendered** (fail-closed). This
> renderer instead defaults it to `t` and renders normally. That is a decision,
> not an oversight: spec §3.2 itself establishes `t` as the real per-document
> stamp for `addToTable` collections, and `MobileTableController.addContent`
> (`lib/states/mobile_table_controller.dart:137`) writes `t` on **every**
> content document — so the default is a known fact, not a guess. `badgeTable`
> remains the only hard config gate (plus `route`, trap 4). A builder reading §8
> should expect a rendered badge here, not silence.

> **Not the same keys as `TASK_FEED`'s.** `badgeTable` / `badgeSearch` also exist
> in [task_feed_list.md](task_feed_list.md) with unrelated semantics (a per-row
> outstanding chip summed via `badgeField`, with `{idField}` row-token
> substitution). No runtime collision — these keys sit on a **grid child**,
> those on the `TASK_FEED` component itself — but do not copy a value from one
> page to the other.

### Five config traps

1. **Never put a row-slot number in `badgeTs`.** `<N>` in an `addToTable` DSL is
   a SLOT, not a field name; only slots named in `index◼…` become top-level
   document fields. A non-promoted slot yields `null` → `coerceNum` → `0` → a
   badge that is permanently zero with no error. Leave `badgeTs` blank unless
   the collection genuinely uses a different field name; `t` is stamped on every
   content doc by `MobileTableController.addContent`.
2. **`badgeSearch` keys must exist as document fields** — promoted `index◼`
   slots, or real keyed-collection keys. A key that is absent compares as `''`
   and matches nothing, silently. A debug-only `devPrint` fires for exactly
   this case, and **for nothing else**: the collection is non-empty and no
   document carries every search key. Its clause parsing mirrors
   `filterByMultiClause`, so a `◼`-less fragment is skipped, not reported as a
   key.
3. **A zero badge can also come from a fail-closed clause, and nothing warns
   about that one.** `filterByMultiClause` returns *no documents at all* when a
   clause's value is empty (`7◼`) or still contains an unresolved `{token}`
   (`7◼{driverVid}` on a screen with no driver context). Neither is detectable
   from the raw `badgeSearch` string — `{driverVid}` looks identical before
   resolution whether or not it will resolve — so trap 2's `devPrint` stays
   silent. **Badge stuck at zero and no warning printed → check the clause
   *values*, not the keys.**
4. **`badgeTable` without a `route` renders no badge at all.** The seen-store is
   keyed by `route`, and only the navigate guard stamps it, so such a badge
   could never be cleared once lit. `MenuBadge.codeFor` returns `''` for it —
   no subscription, no bubble. Give the child a `route` (which a menu tile
   needs anyway) to get its badge back.
5. **A fresh sheet edit may not reach the device on a relaunch. Use the AppBar
   refresh, not logout–login.** Two caches sit in front of a grid child's JSON.
   `_persistUiCache()` (`api.dart`, the `prefs.setString('@screenUI', …)` write
   — line 2104 at time of writing) stores the whole screen map in
   `SharedPreferences`, and the startup-critical loader (`opt == 1`) renders
   from it immediately. That alone would be harmless, because
   `asyncAppStartup2()` runs unconditionally at `main_page.dart:114` and
   re-fetches in the background. The real lag is the **proxy**: `/Proxy/<lif>`
   is a materialized copy that trails the sheet (`api.dart`, the `proxyBootSkip`
   doc-comment, ~line 2245), and opt 2 is proxy-first — so a just-made sheet
   edit can still be absent after a relaunch, and logging out and back in does
   not help because that path is proxy-first too. **The AppBar refresh reads the
   sheet directly** (`readSettingsContext` → `/readSS`) and writes the fresh
   pages to `@screenUI`. Tap it before concluding a badge is broken.

### Behaviour

| count | render |
|---|---|
| `0` | nothing at all — no circle, no "0" |
| `1`–`99` | the number |
| `> 99` | `99+` (same rule as `otq_bottom_nav_bar.dart` `_buildIcon`) |

Bubble: top-right of the 36×36 icon area (never over the label), ⌀18dp minimum
widening for 2–3 characters, `right: -6 / top: -6`, 2dp white ring, 11sp bold
tabular figures, solid `0xFFD32F2F` (Material red 700 — 4.98:1 on white; the
bottom bar's `red.shade400→shade600` gradient is 3.49–4.23:1 and fails WCAG AA
for 11sp bold).

Storage: `badgeSeen_<route>` in `SharedPreferences` (int, epoch ms). Written in
`buildGridList`'s tap handler inside the navigate guard and before
`routeStack.push`, so a tap that does not navigate never clears the badge. The
route is `trim()`ed on BOTH write and read, so a sheet route with stray
whitespace still clears (`routeExist` does an exact, untrimmed `linkElement`
lookup, so such a route navigates normally and the mismatch would be silent).
Persistent by design — **not** registered with `ScreenSession`, because a
per-navigation clear would mean the badge never zeroes.

Known limitation: `subscribeToMapCollection` has no unsubscribe API and the
subscription code is deliberately shared, so a badged grid item subscribes for
the app's lifetime. Do not put a badge on many menus without measuring.
