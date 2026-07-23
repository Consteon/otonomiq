# SharePdf (PRN variant `share-pdf`)

Third variant of the PRN widget family: renders the PRN template dialect to a PDF file and opens the OS native share sheet.

- **File:** [lib/widget/ftz_bluetooth_printer.dart](../../lib/widget/ftz_bluetooth_printer.dart) (variant `share-pdf` inside existing widget)
- **Renderer:** [lib/template_pdf.dart](../../lib/template_pdf.dart)
- **Class:** `FtzBluetoothPrinter` (StatefulWidget), variant branching in `_FtzBluetoothPrinterState`
- **Status:** draft
- **Widget version:** v1
- **SDUI type:** `PRN` with `variant: "share-pdf"`

## Purpose

Share a templated PDF (QR card, invoice, etc.) via the OS share sheet instead of printing to a bluetooth thermal printer. Uses the same template dialect as the `keyed` bluetooth variant (`<TEXT>`, `<QRCODE>`, `<LOOP>`, `{{field|formatter}}`).

## `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `String` | yes | - | Must be `"PRN"` |
| `variant` | `String` | yes | - | Must be `"share-pdf"` |
| `position` | `int` | no | null | Form position slot |
| `isEnabled` | `String` | no | `"true"` | Enable/disable button |
| `text` | `String` | no | `"Print"` | Diamond-separated labels (5 slots): 0 = idle, 1 = preparing, 2 = share-sheet, 3 = error (snackbar), 4 = not-found (snackbar). See slot table below. |
| `buttonIcon` | `String` | no | `"print"` | Icon name from `stringToIconData` map |
| `template` | `String` | yes | - | PRN-dialect template (`;`-separated) |
| `table` | `String` | yes | - | Keyed Firestore collection path (e.g. `84214220504259//location`) |
| `search` | `String` | yes | - | Search config (`field_25FC_value` -- autheniumDecode applied in initState) |
| `paperSize` | `String` | no | `"a6"` | PDF page size: `a4` or `a6` |
| `fileName` | `String` | no | `"share.pdf"` | Output file name template (`{{field}}` tokens resolved from doc) |
| `border` | `String` | no | (none) | Named color (`blue`) or hex (`#RRGGBB`) for thick page-edge border frame. Same vocab as `buttonColor`, plus hex. |
| `borderWidth` | `String` | no | `"8"` | Border thickness in pt (string). Only meaningful when `border` is present. Larger = thicker frame. Content margin auto-adjusts. |
| `grid` | `String` | no | (none) | Grid batch mode: `"KxB"` (e.g. `"4x4"` = 4 cols x 4 rows per page). Absent = single-doc mode. When present, search matches ALL docs, each rendered as a card in the grid. Cards sorted by `ln` A-Z. Overflow paginates. Border is per-card (not page-edge). fileName is literal (no per-doc token resolution). |
| `buttonColor` | `String` | no | `"teal"` | Button background color |
| `onButtonColor` | `String` | no | `"white"` | Button text/icon color |
| `width` | `String` | no | - | `"full"` for expanded, or numeric px |
| `alignment` | `String` | no | `"center"` | `left` / `center` / `right` |

### `text` label slots

| Slot | Purpose | Default (if slot absent) |
|---|---|---|
| 0 | Button label (idle) | `'Print'` (from `initState`) |
| 1 | Button label (loading data) | `'Loading...'` |
| 2 | Button label (sharing) | `'Sharing...'` |
| 3 | Error label (snackbar on render/share failure) | `'Failed to create PDF.'` |
| 4 | Not-found label (snackbar when search returns 0 docs) | `'Data not found.'` |

Example: `"text": "Bagikan QR◆Menyiapkan PDF...◆PDF siap — pilih aplikasi◆Gagal membuat PDF. Coba lagi.◆Data titik tidak ditemukan."`

## Template dialect

Same as `lib/template_printer.dart`. Tags: `<TEXT align bold underline height color>`, `<QRCODE data align size/>`, `<IMAGE asset|url align width height/>`, `<ROW align><COL width bold align>`, `<LOOP source='x'>`, `<HR>`, `<FEED lines='n'>`. `{{field}}` with `|idr`/`|usd`/`|default:X`. `<CUT>` silently ignored. `<GROUP_BY>` and `<ACCUMULATE>` silently ignored (v1).

### Iteration 2 additions

- **`color` on TEXT:** Named color string (same vocab as `buttonColor` in component config). Resolved via `stringToColor` (global2.dart) -> `PdfColor`. Default: black.
- **`border` on component:** Named color string for a thick frame around every page edge. Absent: no border.
- **`<IMAGE asset='key' … />` or `<IMAGE url='https://…' … />`:** Renders an image. `asset` = Flutter bundle (`assets/images/{key}.png`, offline-safe). `url` = network fetch by the widget's loader (e.g. a Firebase Storage branding image); when both are set, **`url` wins**. Width/height in pt optional (default: natural size, fit container). Not found / offline / non-200 / load error: skipped silently (footer just missing — no crash). Works inline inside `<COL>`. **Quote a `url`** (it contains `/ ? & =`) and it must not contain `;` (the template line separator). Network images are re-fetched per share; offline shares lose them — bundle as an `asset` if offline branding is required.
- **QRCODE empty data:** Throws `StateError` (routes to `text[3]` error label). A QR-less PDF is never emitted.
- **TEXT alignment fix:** `align='center'` now correctly centers text across the full page width.
- **`text` 5 slots:** idx0=idle, idx1=preparing, idx2=share-sheet, idx3=error, idx4=not-found. Length-guarded.

### Grid mode

When `grid` is set to `"KxB"` (e.g. `"4x4"`), the widget enters batch mode:
- **Search** matches ALL docs (not just the first). Example: `lst_25FC_active`.
- **Template** is walked once per doc, producing identical card layouts.
- **Cell sizing** is automatic: page area / (K x B). Content scales uniformly via `FittedBox`.
- **Border** is per-card (each cell gets its own frame), not page-edge.
- **Pagination**: docs exceeding K*B overflow to additional pages.
- **Sort**: cards ordered by `ln` field A-Z.
- **fileName**: used as literal (no `{{field}}` resolution since multi-doc).
- **QR warning**: if estimated QR print size < 25mm for the chosen grid+paperSize, a devPrint WARN is emitted (render proceeds).
- **Malformed grid** (e.g. `"4"`, `"axb"`, `"0x4"`): falls back to single mode with a devPrint WARN.

### Color resolution

Both `border` and `<TEXT color='...'>` accept:
- **Hex**: `#RRGGBB` (e.g. `#1FA0A6`) -- parsed directly via `PdfColor.fromHex`.
- **Named**: any color in the `stringToColor` vocabulary (e.g. `blue`, `teal`, `red_500`).
- **Default**: absent/empty -> black.

## Divergences from `template_printer.dart`

The PDF renderer (`lib/template_pdf.dart`) intentionally diverges from the ESC/POS renderer in five places. This list is the contract between the two renderers — keep it complete.

1. **`_formatIdr` non-numeric passthrough:** The ESC/POS renderer's `_formatIdr` returns `'0'` for non-numeric input (e.g. pre-formatted `'1.250.000'`). The PDF renderer passes it through unchanged. This avoids silent data loss on pre-formatted strings.

2. **Expression fallback to path resolution:** When the expression evaluator fails (commonly triggered by the known `-` false-positive on hyphenated field names like `item-name`), the ESC/POS renderer emits `'!ERR!'`. The PDF renderer falls back to `_resolveByPath`, which resolves `item-name` as a map key lookup. This prevents raw error tokens from appearing in a shared PDF.

3. **`_replaceItemPlaceholders` type-tests the loop item instead of casting it:** `template_printer.dart` casts `context['item']` to `List<dynamic>?`, but both renderers' LOOP walkers deliberately allow a **Map** item (the keyed PRN variant). That call sits *outside* `interpolate`'s try/catch, so in the ESC/POS renderer a Map item throws a `_TypeError` past the renderer and aborts the whole job — which also means divergence 2 above never actually took effect there. The PDF renderer returns the expression unchanged for non-List items, so the divergence-2 fallback genuinely runs. Consequence: `{{item.qt * item.hg}}` over Map items yields `''` here (no `item[N]` placeholders to substitute, then path resolution fails) rather than crashing.

4. **Missing / non-List LOOP source is silent:** `template_printer.dart` throws `Exception('Source "$sourceName" for LOOP not found or is not a List.')`. The PDF renderer returns no widgets — an unknown or failed source must render EMPTY, never a raw tag. Note the interaction with the empty-document guard below: if that LOOP was the template's *only* content, the render fails loudly at `generateBytes()` instead.

5. **Path-traversal failure yields `''`:** `_resolveByPath` returns an empty string on any failure; the ESC/POS renderer returns the raw `{{…}}` token. A PDF must never show a raw template token to a recipient.

## Failure modes

- **Empty document is refused.** `generateBytes()` throws `StateError` when the template produces zero widgets. `pw.MultiPage` would otherwise allocate no page at all, and `save()` returns a 427-byte file whose page tree is `<</Type/Pages/Kids[]/Count 0>>` — a document no viewer opens. Reachable on a nota with zero line items (`{'li': []}`), a missing/null LOOP source, or a template of only unknown tags. The widget catches it, shows the error snackbar and shares nothing. `bytes.isNotEmpty` is TRUE for that broken file, so byte length is never a valid guard.
- **Oversized `QRCODE` throws.** `size` is multiplied by 20 to get points, so any `size` above roughly **18 at A6** (~39 at A4) exceeds the page height and throws `PdfException: Widget won't fit into the page`. Caught by the widget → error snackbar. `size='8'` (160pt) is the tested value for A6.
- **`pw.MultiPage` caps at 20 pages** (`maxPages`), then throws. Fine for a QR card; relevant for a large invoice `<LOOP>`.
- **`<LOOP>` *elements* must each be a `Map` or a `List`.** Divergence 4 above covers a missing or non-List *source*; this is the element level, which is NOT guarded. Both LOOP walkers coerce each row with `(row as List)` (`template_pdf.dart:309`, `:364`), so a source whose elements are plain scalars — a Firestore array-of-strings like `{'li': ['a','b']}` — or that contains a `null` element throws `_TypeError`, caught by the widget → error snackbar, no PDF. Reachable because the keyed read copies doc fields verbatim. Behavior is identical in `template_printer.dart`; if a tenant's array-of-strings field ever needs looping, fix it in both renderers rather than only here.

## Important Behavior

- Keyed read only: requires `table` + `search`. Missing config shows snackbar error.
- PDF rendered locally (no network after doc fetch). Works offline if doc is in Firestore cache.
- Uses `pw.MultiPage` so content longer than one page flows automatically (no clipping).
- Busy flag cleared in `finally` on every exit path (no wedge).
- No per-screen persistent state. No `#KEY`s added.
- `fileName` tokens are simple `{{field}}` only (no formatters). Illegal filename chars (including `{` and `}`) stripped.
- Default Helvetica font is Latin-1 only. Non-Latin-1 glyphs (typographic quotes, en-dashes) may render as substitutions or blanks. If this becomes a problem, embed a TTF font that covers the needed range.

## See Also

- [lib/widget/ftz_bluetooth_printer.dart](../../lib/widget/ftz_bluetooth_printer.dart) for the bluetooth variants (source file; widget doc not yet written)
- `lib/template_printer.dart` for the ESC/POS renderer (same dialect, different sink)
