# GroupPicker

Multi-group single/multi-select picker with internal toggle, bound to form positions.

- **File:** [lib/widget/group_picker.dart](../../lib/widget/group_picker.dart)
- **Class:** `GroupPicker` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1

## Purpose

Self-contained picker that hosts an internal group toggle (segmented control).
User picks a group (level), then picks target(s) within that group. The widget
emits 2-3 values to form positions: active group key, selected value(s),
optional label(s). Designed for the broadcast page (cost center / site / orang)
but generic enough for any grouped picker need.

The renderer has no cross-widget reactivity, so level-to-target reactivity
lives entirely within this one widget.

## Signature / Constructor

```dart
GroupPicker({
  required Key key,
  required dynamic component,
  required String scrName,
  required double lPad,
  required double tPad,
  required double rPad,
  required double bPad,
})
```

### Parameters

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | `Key` | yes | -- | Unique key per instance |
| `scrName` | `String` | yes | -- | Screen name |
| `component` | `dynamic` | yes | -- | Component config (see below) |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | -- | Padding |

### `component` shape

| Key | Type | Description |
|---|---|---|
| `mode` | `String` | `single` or `multi` |
| `selector` | `String` | `segmented`, `dropdown` (degrades to segmented), `none` |
| `display` | `String` | `inline` (v1 only); `sheet` degrades to `inline` |
| `keyPosition` | `int?` | Form position for active group key |
| `valuePosition` | `int` | Form position for selected id(s) |
| `labelPosition` | `int?` | Form position for selected name(s) |
| `pairSep` | `String` | Parse separator for static `options` (`name◆id`) AND the multi-join default (default `◆`) |
| `joinSep` | `String` | **Output-only** join separator for the multi-mode value/label lists. Defaults to `pairSep` when absent/empty (backward-compat). Set to a `stringCleanUp`-surviving char (e.g. `,`/`|`/`;`) so the emitted multi `bcc` survives the Firestore write (see separator warning). Does NOT affect `options` parsing (`pairSep` still does that) or single-mode output (bare, no join). |
| `itemSep` | `String` | Item separator for static options (default `⭘`) |
| `selectAll` | `bool` | Opt-in select-all-visible control row (multi mode only; default `false`; no-op in single mode) |
| `maxListHeight` | `double?` | Max height (px) of the internally-scrollable item-tile list. Absent → responsive default `screenHeight * 0.4`. Bounds only the person-tile list so the surrounding page (send button/CTA) stays reachable; title/hint/selector/search/select-all/count stay fixed outside the scroll. |
| `title` | `String` | Widget title |
| `hint` | `String` | Hint when no selection |
| `text` | `String` | Diamond-split labels: [0] searchHint, [1] emptyText, [2] confirmLabel, [3] cancelLabel, [4] countTemplate, [5] selectAllLabel (default `"Pilih semua"`) |
| `groups` | `List` | Array of group objects (key, label, src, options/vidtable/table/search/field/labelField/subField/valueField) |

### Per-group `src` modes

| `src` | Fields used | Behavior |
|---|---|---|
| `static` (default) | `options` | Parse inline `options` string with `pairSep`/`itemSep`. Each item = `name◆id`. |
| `table` | `vidtable`, `table`, `search`, `labelField`, `subField`, `valueField` | Subscribe to Firestore collection; each doc = one option. `search` gate filters docs (supports `{userVid}` token). |
| `doc` | `vidtable`, `table`, `search`, `field` | Subscribe to Firestore collection (same engine as `table`), find the FIRST doc matching `search`, read ONE string field (`field`), and split it with `pairSep`/`itemSep` (same parser as `static`). Multiple groups with the same `vidtable`/`table` share ONE subscription. |

**`{userVid}` token:** the `search` field supports `{userVid}`, which resolves to the logged-in user's vid (`screenTx['#VID']`). Use `{userVid}`, NOT `◁sessionVid▷` (which is the WHITE form-position token in this repo -- a name collision). If `#VID` is empty at picker load, the token stays literal, matches nothing, and the list shows `emptyText` (safe degradation).

**`field` value format:** the string stored in the Firestore doc field is `nama◆id⭘nama◆id⭘…` (literal `pairSep`/`itemSep` chars, NOT server-encoded). This matches the `src:static` `options` format. Items without a `pairSep` separator use the whole string as both name and id; malformed items are skipped.

**Misconfigured `src:"doc"`:** a `doc` group with `field` absent/empty/typo'd renders an EMPTY list (`emptyText`), never the raw source docs — the mode is discriminated by `src == 'doc'`, not by a non-empty `field`, so a typo cannot leak a Firestore `__docId` into the emitted value.

## State / Dependencies

- **State:** `static` maps on `GroupPicker` keyed by `scrName` + `valuePosition`, cleared in `clearState(scrName)` from `buildPage`.
- **Dependencies:** `PickerList.filterRows` (search gate), `TablePicker.resolveValueFromDoc` + `TablePicker.clientSearch` (table-src helpers), `subscribeToMapCollection` / `mapTableContent` (Firestore keyed-table read).
- **Output:** writes to `txfController[scrName][pos].finalData`.

## Important Behavior

- **Bounded item list (R5):** the person-tile list renders inside a height-capped, internally-scrollable box (`ConstrainedBox` > `SingleChildScrollView` > `Column(min)`; default height `screenHeight * 0.4`, override via `maxListHeight` px). It shrink-wraps to content for a few items (no empty gap) and caps + scrolls internally for many, so a long list (~100 people) doesn't push the page's send button far down. Only the item tiles scroll — title, hint, selector tabs, search field, the select-all control, and the count label stay fixed.
- **Reset-on-tab-switch (R4):** switching tabs RESETS the tab you leave — only the currently-active group ever holds a selection (one level per broadcast; emitted output is always the active group's selection only). Because non-active tabs are never emitted, their checks are cleared on leave rather than preserved. Unconditional (no config flag).
- **Select-all (opt-in, `selectAll:true`, multi mode only):** renders a control row above the item tiles with a 3-state leading icon vs the currently-visible rows — all visible selected → `check_box`, some → `indeterminate_check_box`, none → `check_box_outline_blank`. Label = text segment [5] (default `"Pilih semua"`). Semantics are **select-all-VISIBLE**: it acts on the already-filtered rows (respects the search box + group gate), so with an active search only the filtered ids are added; tapping when all visible are already selected deselects them all. Acts on the ACTIVE group only (other tabs are reset on leave, R4). Never rendered in single mode or when rows are empty. **Note:** select-all can produce a large id list, which makes the multi-output `pairSep` corruption above bite harder — the surviving-separator + CF-split decision (GATE 1 path A) still stands and is an authoring + CF concern, not a widget change.
- `selector:"none"` or only 1 group: toggle hidden.
- Empty group: tab still shows, list renders emptyText.
- Multi output uses `joinSep`-join (NOT jsonEncode); `joinSep` defaults to `pairSep`. **★ Separator warning:** the default `pairSep`/`joinSep` `◆` is `forbiddenCharacter[0]` (global.dart:384) and is replaced by a SPACE in `stringCleanUp` (global.dart:1193) BEFORE the record is written, so a `◆`-joined multi value arrives in the Firestore `bcc` field SPACE-delimited (CF fanout then can't split it). Single-mode output (bare id) and the group `key` are unaffected. **Survival lever:** for a working multi/broadcast wiring, set **`joinSep`** to a `stringCleanUp`-surviving character (e.g. `,`/`|`/`;`) — `pairSep` stays `◆` so the static `options` remain readable/parseable, while `joinSep` controls the emitted `bcc` join. The consuming CF must split `bcc` on that same `joinSep` character. The widget itself is correct/config-driven; this remains an authoring + CF-coordination requirement (`joinSep` is the config lever, not a hardcode). For `src:doc` broadcast wiring (`notification` prop → `bcc`), set `joinSep` to `|` (or another `stringCleanUp`-surviving char). The consuming CF must split `bcc` on that same character. This is an authoring + CF coordination requirement, not a widget change. (Same latent defect affects event-push-v3 / whatsapp-send `bcc`.)
- Static `options` are parsed with literal pairSep/itemSep (NO autheniumDecode). Table/doc `search` goes through `autheniumDecode` + `resolveDriverCurlyTokens` (so `{userVid}` etc. resolve) before `PickerList.filterRows`, which re-decodes idempotently.
- **Doc source (`src:"doc"`):** reuses the `src:table` subscription engine and the `src:static` parser. The subscription code is `$appVid/$tableDocId/$subColl` -- the `field` name is NOT part of it, so multiple groups with the same `vidtable`/`table` but different `field` values share ONE subscription and ONE reactive `mapTableContent` entry. The `search` string goes through `autheniumDecode` + `resolveDriverCurlyTokens` before filtering. The doc field value is NOT decoded (it carries real `◆`/`⭘`, not server escapes). If several docs match `search`, the FIRST in Firestore snapshot order wins (contract: one grant doc per user).

## See Also

- [table_picker.md](table_picker.md) -- sibling single-source picker (form-position output, sheet display)
- [picker_list.md](picker_list.md) -- single-select collection picker (screenTx token output)
