# visibleWhen

Optional per-component string field that shows or hides ANY page-JSON component based on LIVE form values.

- **File:** [lib/widget/visible_when.dart](../../lib/widget/visible_when.dart)
- **Class:** none — top-level pure functions (not a widget, not a dispatch type)
- **Status:** draft
- **Widget version:** v1
- **Spec:** `visiblewhen-conditional-rendering-dev-spec` (2026-09-07)

## Purpose

Request forms (izin / cuti / sakit / tukar-shift / koreksi) need fields that appear
only for certain choices. `visibleWhen` is ONE generic primitive for that, rather
than a per-form hack. It reads LIVE FORM VALUES; for conditions over Firestore
document data use the existing `search` field instead.

Absent or empty `visibleWhen` means "always visible", so every pre-existing page
config keeps working with no edit.

## `component` shape

| Key | Type | Description |
|---|---|---|
| `visibleWhen` | `String` | Condition. `""` / absent = always visible. |

## Grammar

```
visibleWhen := klausa (⭘ klausa)*            ⭘ U+2B58 = AND
klausa      := posisi ◼ [operator] operand   ◼ U+25FC
operator    := (no prefix = ==) | != | > | >= | < | <=
operand     := literal | ◁N▷ | literal★literal★…   ★ U+2605 = IN, only with ==
```

Operator parsing is a prefix scan, longest match first: `>=`, `<=`, `!=`, then `>`, `<`.
Server escapes are decoded by `autheniumDecode` (`lib/global.dart`) before splitting.
The `_u`-prefixed family is live and is what config must emit: `_u25FC_` (◼), `_u2B58_`
(⭘), `_u2605_` (★), `_u25C1_` (◁), `_u25B7_` (▷). `_25FC_` is the SOLE un-prefixed
exception that still decodes; every other un-prefixed form (`_2B58_`, `_2605_`, `_25C1_`,
`_25B7_`, `_25C0_`, `_25B6_`, `_2B24_`) is commented out in `autheniumDecode` and reaches
the parser as literal text.

## Evaluation rules

1. Empty or absent -> visible.
2. Parse failure -> **visible** (fail-open) + a `devPrint` line. Worst outcome of bad
   config is a static form, not a broken one.
3. An unfilled position reads as `""`.
4. `◁N▷` resolves to the live value of position N (`""` when unfilled).
5. `num.tryParse` on both sides -> numeric compare, else string ordinal. **No date
   parsing** — config discipline is ISO (`yyyy-MM-dd`, `HH:mm`), whose string order is
   time order.
6. An ordering operator with `""` on either side makes the clause false. `==` and `!=`
   compare against `""` normally, so `9◼!=` means "position 9 is filled".
7. `★` with any operator other than `==` is a parse failure -> rule 2.
8. All clauses true -> visible; any false -> hidden.

Comparison is **case-SENSITIVE** (via `eq()` in `dsl_eq.dart`), matching
`filterByMultiClause` and unlike `evaluateRbtSearch`, which uppercases.

## Hide effects

| Aspect | Behavior |
|---|---|
| Render | Not rendered — `const SizedBox.shrink()`, takes no space. |
| Validation | The GET_IMAGES `optional:"FALSE"` gate skips hidden components. |
| Submit / `◁N▷` | The position submits `''` when EVERY widget declaring it is hidden. |
| Static-table write | Also suppressed for that position. A widget's `InputController.table` (today only `ftz_multi_scan`) is the other half of its submit contribution, so hiding suppresses the `writeToStaticTable` call as well as the record slot. |
| In-memory value | Retained in `txfController` — toggling back does not lose the submitted value. |
| Re-evaluation | On every `InputController.finalData` change, debounced to one post-frame repaint. |

## Duplicate `position` (official per-mode label pattern)

Two widgets may share a `position` when their `visibleWhen` are mutually exclusive.
They share ONE `InputController` (txfController is keyed by position), so `◁N▷`
structurally takes the visible one, and the slot survives as long as ANY widget at
that position is visible. If both are visible (misconfig) both render — no crash.

## Example (form Izin, spec §4)

```json
{"type":"SELECTABLE_BTN","variant":"grid","position":2,
 "text":"Seharian◆Paruh hari◆Telat masuk◆Pulang cepat"}
{"type":"TXF","variant":"time","label":"Jam mulai","position":4,
 "visibleWhen":"2◼Paruh hari"}
{"type":"TXF","variant":"time","label":"Perkiraan jam tiba","position":6,
 "visibleWhen":"2◼Telat masuk"}
{"type":"noticeBar","variant":"danger","text":"Jam selesai harus setelah jam mulai",
 "visibleWhen":"2◼Paruh hari⭘5◼<=◁4▷"}
```

## Important Behavior / limitations

- The wrapper defers **rendering only**. Side effects that run earlier in
  `buildDisplayComponent` still happen for a hidden component:
  `txfControllerCheck`, the `getInitialValue` seed, and
  `ApproverStickyBar.register`. **`visibleWhen` on an `rbt` with `search:"sticky"`
  is unsupported in v1** — the sticky overlay would still register.
- Hiding returns `const SizedBox.shrink()`, so the component is removed from the tree
  and **any** widget's `State` is disposed and re-created on re-show — this is not
  TXF-specific. What survives is `finalData` in `txfController` (that is the "value
  retained" guarantee); anything a widget holds in its own `State` fields does not.
  Worked example: re-showing a hidden `TXF` re-runs `otq_txf_2`'s `initState`, which
  resets the VISIBLE text to the config's `currentValue` while the submitted value
  (`finalData`) is retained. Known, not fixed in v1.
  **One carve-out to the retention guarantee:** that same `initState` also rewrites
  `finalData` — but only inside `if (canInitializePage(scrName))`, and
  `canInitializePage` (`lib/api.dart`) is `thePage == home && asHomeArray.contains(thePage)`.
  So on a HOME page listed in `asHomeArray`, a re-shown `TXF` loses its submitted value
  too. Request forms are not home pages, so the pilot is unaffected — but do not rely on
  retention for a conditional `TXF` placed on home.
- `★` is checked BEFORE `◁N▷`, so an operand mixing the two (`◁4▷★x`) parses as a
  two-entry IN list whose entries are the LITERALS `◁4▷` and `x` — no live value is
  resolved. The spec does not define that combination; do not rely on it.
- A `⭘` arriving as the LEGACY un-prefixed `_2B58_` is not decoded, so the whole
  condition collapses into ONE clause and the widget is **hidden** — fail-CLOSED, the
  opposite of the fail-open rule, and **silent**: parsing succeeds, so no `devPrint`
  fires. Pinned by a test. Config must emit `_u2B58_`.
- Only positions `1..100` participate in submit exclusion, matching `saveSend`.
- Chain children (DO_BOTTOM_SHEET / DO_DIALOG / RBT children) are not descended into
  by the exclusion scan, matching `getImagesRequiredBlock`.

## See Also

- [rbt_visibility](../../lib/widget/rbt_visibility.dart) — RBT child `search` gate, the
  fail-CLOSED sibling of this predicate.
- [ftz_row_of_button_2.md](ftz_row_of_button_2.md) — where the submit gate is filtered.
- [otq_get_images_2.md](otq_get_images_2.md) — the only submit-blocking validation today.
