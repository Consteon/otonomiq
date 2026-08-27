# OtqTxt (`txt`)

Renders `component['data']` as text. Source: [lib/widget/otq_txt.dart](../../lib/widget/otq_txt.dart).
Dispatch: `build_display_component.dart` branch `tip == 'txt'`.

## Default (no `variant`)

Plain `Text` via [OtqFormattedText](../../lib/widget/otq_formatted_text.dart) —
honours `size`, `style`, `color`, `background`, `margin`, `route`.
**Unchanged.** A `txt` component with no `variant` field takes this path exactly
as before, so the thousands of existing `txt` rows across every screen are
untouched by the variants below.

## `variant: "section"`

Styled section header, two tiers keyed off how the sheet writes the title:
ALL-CAPS data (`ABSEN MASUK`) → compact overline (13.5px w800, wide
tracking); mixed case (`Laporan`) → large bold title (19px w800), rendered
as-is (no forced uppercase). Ignores `size`/`style`/`color` — the variant
owns its typography.

```json
{ "type": "txt", "variant": "section", "data": "Riwayat Absensi" }
```

### Trailing meta (date/time)

If `data` contains `" -- "` (what `replaceMarker` in `global.dart` turns a
sheet-side `\n` into), the part after the **first** `" -- "` renders as muted
meta on the RIGHT of the header row instead of inline: dashes become spaces
and the last space becomes `" · "`, so
`"ABSEN MASUK -- 18-Aug 8:34"` renders `ABSEN MASUK` left and `18 Aug · 8:34`
right. Split logic: `OtqTxt.splitSectionMeta()` (tested in
[test/section_meta_split_test.dart](../../test/section_meta_split_test.dart)).

## `variant: "history"`

Timeline rail. Each **non-empty line** of `data` becomes one entry: a dot, a
connector down to the next entry, and three text tiers.

```json
{ "type": "txt", "variant": "history",
  "data": "15-Jul 15:42 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora\n14-Jul 13:31 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora" }
```

### Line format

`<DD-MMM> <HH:MM> <head> @ <tail>` — parsed by `OtqTxt.parseHistoryLine()`:

| part | renders as |
|---|---|
| `15-Jul` + `15:42` | `15-Jul · 15:42`, 12px bold, primary colour |
| head (before `@`) | 15px semibold, body colour |
| tail (after `@`) | 13px, body colour at 60% |

Leading/trailing `-` left by empty server fields are stripped, so
`... 11:04 - Pengarahan @ - QA-check - Jalan Horizon` renders head `Pengarahan`
and tail `QA-check - Jalan Horizon` with no dangling dashes.

A line that does **not** start with a `DD-MMM HH:MM` stamp degrades to plain
text (whole line as head, no date chip) rather than being dropped — a server
format change loses styling, never data.

### Sheet-side note

Send every record in **one** `txt` separated by `\n` to get the connecting rail.
One record per `txt` component also renders correctly (dot + text), just without
the connector between components.

## Tests

[test/otq_txt_history_test.dart](../../test/otq_txt_history_test.dart) — parser
cases (real server strings, empty fields, unknown format, empty input) plus a
layout check for the `IntrinsicHeight`/`Expanded` rail.

## See Also

- [otq_txf_2.md](otq_txf_2.md) — text field v2
- [display_list.md](display_list.md) — bordered table-driven list
