# TabSections (`TAB`)

One SDUI component that owns several page sections and decides how they are
laid out. It exists so that moving the Formulir / Log / Terbaru menus between
the home page and a separate menu page is a **one-field edit**, not a JSON
restructure.

The sections themselves are ordinary components (`HGR`, `TXT`, …). They are
built by `buildDisplayComponent` before `TabSections` ever sees them and each
keeps its own `variant`, so a `TAB` may hold classic grids, v6 grids, or a mix.

Widget: `lib/widget/tab_sections.dart`.
Branch: `tip == 'tab'` in `lib/widget/build_display_component.dart`.
Tests: `test/tab_sections_test.dart`.

## Keys

| Key | Meaning |
|---|---|
| `data` | ◆-separated section labels, e.g. `Laporan◆Formulir◆Log◆Terbaru`. Also the tab labels. |
| `mode` | `inline` · `link` · `tab`. Absent or unrecognised → `inline`. |
| `variant` | `v6` opts into the v6 look. Absent → plain headings, brand-coloured indicator. |
| `route` | `link` mode only: the screen the link opens. |
| `link` | `link` mode only: the link label. Blank → `Lainnya`. |
| `source` | Borrow another screen's `TAB` children instead of declaring them here. |
| `children` | The section components. Each carries `tab` (int) naming its group. |

`tab` indexes may be sparse; groups render in ascending index order and a group
whose index is past the end of `data` renders with no heading.

## Modes

- **`inline`** — every section stacked, each under its own heading. No tab bar,
  no link. This is the layout the home page has today.
- **`link`** — the first section only, plus a link that pushes `route`. Used on
  home when the rest of the menu lives on its own page.
- **`tab`** — an underline tab bar, one section visible at a time. Used on that
  menu page.

Every narrowing of `mode` **fails open to `inline`**, which shows everything:

- `link` needs a `route` that some screen declares. The gate reads
  `screenUIComponent`, *not* `routeExist`: `routeExist` reads `linkElement`,
  which is filled screen by screen, so gating on it would make the rendering
  depend on which screen happened to be built first. `routeExist` is still
  checked on tap, matching `buildGridList`'s card tap.
- `tab` (or `link`) with fewer than two sections is pointless.

A typo'd route must never be able to hide three quarters of the menu behind a
dead link, so the fallback direction is deliberate and is pinned by tests.

## `source`

`{"type":"TAB","mode":"tab","source":"<screen>"}` copies the labels and children
of that screen's own `TAB`. Without it the menu page would carry a second copy
of grids that already live on home, and the two would drift apart with nothing
to catch it. A `TAB` nested inside a `TAB` is skipped — a `source` cycle would
otherwise recurse until the page build blew the stack.

`source` **adds to** the borrowed children rather than replacing them: borrowed
first, then this component's own. That is how the menu page carries a log
preview of its own without duplicating the four grids it borrowed. Replacing
would drop the local children silently — a block that simply never appears.

If neither `children` nor `source` yields anything, the component renders
`--TAB-- no sections (source: …)` rather than a blank page.

## Selected tab

`TabSections.activeTab` is a `static Map<String, int>` keyed by `scrName`, not
widget State. `any_page` re-runs `buildPage` inside its StoreConnector builder,
so an unrelated redux dispatch rebuilds the whole page with a fresh widget tree;
a selection held in State would jump back to the first tab every time.

## Look

`variant` gates presentation only. With `v6`: a 1 dp `v6Border` rule above each
heading, headings 16/600 (16 rather than v6's own 18 — on home this heading sits
directly under the 16/600 "Absen Pulang" head), and the active tab underlined
3 dp in `v6AccentStrong`, the one orange v6 allows on these screens. Without it:
plain 18 pt headings, no rule, indicator in `primaryColor`.

The heading itself is `otqSectionHead` in
[theme_tokens.dart](../../lib/theme_tokens.dart), shared with the v6 log list —
the two sit on the same screen one under the other, so two copies would drift
visibly.

The tab bar is a `Row` of `Expanded` tabs, so a fifth or sixth tab ellipsizes
instead of throwing a RenderFlex overflow. It is **not** sticky — the page is a
`ListView.builder`, and pinning the bar would mean rebuilding the page as
slivers.

## Example

Home (`mode` is the flag — `link` puts the rest on their own page,
`inline` stacks them here):

```json
{ "type":"TAB", "variant":"v6", "mode":"link",
  "data":"Laporan◆Formulir◆Log◆Terbaru",
  "link":"Lainnya", "route":"vertikaTeknoLokaciptaMenu", "width":100,
  "children":[
    {"type":"HGR","tab":0,"variant":"v6","columns":5,"width":86,"row":2,"children":[…]},
    {"type":"HGR","tab":1,"variant":"v6","columns":5,"width":86,"row":2,"children":[…]},
    {"type":"HGR","tab":2,"variant":"v6","columns":5,"width":86,"row":2,"children":[…]},
    {"type":"HGR","tab":3,"variant":"v6","columns":4,"width":86,"row":2,"children":[…]}
  ]}
```

The menu screen:

```json
{"title":"Menu","children":[
  {"type":"TAB","variant":"v6","mode":"tab","source":"vertikaTeknoLokacipta","width":100}]}
```
