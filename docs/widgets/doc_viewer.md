# DocViewer

Inline PDF viewer — renders a PDF embedded on an SDUI page from a URL or Firebase Storage path, with optional fullscreen overlay.

- **File:** [lib/widget/doc_viewer.dart](../../lib/widget/doc_viewer.dart)
- **Class:** `DocViewer` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **SDUI type:** `DOC_VIEWER` (dispatch also accepts `docviewer`)

## Purpose

Display a PDF document inline on a detail page. First consumer: payslip (slip gaji) detail. The viewer embeds directly in the page scroll — it is NOT a "card you tap to open a separate page". An optional fullscreen icon in the corner opens the existing `OtqPdfViewer` page.

Uses `flutter_pdfview` (already installed) — NOT `syncfusion_flutter_pdfviewer` (rejected for licensing).

## Signature / Constructor

```dart
DocViewer({
  required Key key,
  required String scrName,
  required dynamic component,
})
```

### `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `String` | yes | — | `DOC_VIEWER` |
| `source` | `String` | yes (variant A) | — | PDF link (supports `{token}` markers) |
| `sourceType` | `String` | no | `url` | `url` = direct link; `path` = Firebase Storage ref |
| `swipe` | `String` | no | `vertical` | Scroll direction: `vertical` or `horizontal` |
| `fullscreen` | `String` | no | `true` | Show fullscreen icon: `true` or `false` |
| `text` | `String` | no | `''` | Title displayed above the viewer |
| `emptyText` | `String` | no | `Dokumen tidak tersedia` | Shown when source is empty/unresolved/failed |
| `height` | `int` | no | `480` | Fixed height in logical pixels (required for ListView layout) |
| **`table`** | — | — | — | **INERT. Variant B is NOT implemented. Do NOT add to a sheet.** Setting `table` with unusable `source` renders: "Konfigurasi table (Variant B) belum didukung. Gunakan source dengan link langsung." Also emits `devPrint` warning. |
| **`search`** | — | — | — | **INERT. Variant B is NOT implemented.** |
| **`sourceField`** | — | — | — | **INERT. Variant B is NOT implemented.** |
| **`vidtable`** | — | — | — | **INERT. Variant B is NOT implemented.** |

## Usage Examples

### URL source (Variant A)

```json
{
  "type": "DOC_VIEWER",
  "source": "{link}",
  "sourceType": "url",
  "swipe": "vertical",
  "fullscreen": "true",
  "text": "Slip Gaji",
  "emptyText": "Slip belum tersedia",
  "height": 480
}
```

### Firebase Storage path

```json
{
  "type": "DOC_VIEWER",
  "source": "documents/payslip/2026-08.pdf",
  "sourceType": "path",
  "fullscreen": "true",
  "text": "Slip Gaji Agustus"
}
```

## State / Dependencies

- **State:** Widget-local only (loading/path/error in `State`). No Redux, Bloc, or GetX.
- **`#STORAGE_BUCKET`:** Read from transactionStore for `sourceType: "path"`. Null/type-guarded — fails closed with `emptyText` if absent.
- **`TokenResolver.curly`:** Resolves `{token}` markers in `source`.
- **`createFileOfPdfUrl`:** Top-level function in `lib/page/otq_pdf_viewer.dart` — downloads URL to local file for `PDFView`.
- **Fullscreen:** Opens `OtqPdfViewer` via `Navigator.push` with the already-downloaded local file (`remote: false`) — not routeStack (plain Flutter overlay).

## Important Behavior

- PDF renders INLINE in the page, not behind a tap-to-open gate.
- `height` is MANDATORY for layout correctness — SDUI pages use `ListView.builder` with unbounded vertical constraints.
- Unresolved `{token}` (still contains `{`) → detected by `docViewerSourceIsUsable` → treated as empty → `emptyText`.
- All async errors (download, Storage resolve) caught with `mounted` guard — never an uncaught fatal.
- Variant B keys (`table`, `search`, `sourceField`, `vidtable`) are accepted but **INERT** — the widget always falls through to Variant A. Only `table` triggers the `devPrint` warning (`doc_viewer.dart` guards `_spec.has('table')` alone); `search`, `sourceField` or `vidtable` set **without** `table` are ignored in total silence. **When `table` IS set and the resolved `source` is unusable, the widget renders a distinct on-screen message** (`docViewerVariantBMessage`: "Konfigurasi table (Variant B) belum didukung. Gunakan source dengan link langsung.") instead of `emptyText`, so a config author can distinguish "Variant B unsupported" from "PDF failed to load". The message audience is the sheet author (Indonesian); an end user should never see it because `table` should not be added to a production sheet.
- Fullscreen passes the already-downloaded local file path (`remote: false`), not the original URL. This avoids a redundant re-download and dodges expired Firebase Storage signed-URL tokens.
- `SduiSpec.str()` runs `autheniumDecode()` on all values, including the `source` URL. This is harmless for ordinary URLs (no `_25FC_`/`_2B58_` sequences), but a URL is the one config value an author might expect to arrive byte-exact.
- **Platform-view gesture conflict:** `PDFView` is a native platform view inside the page's `ListView.builder`. A vertical drag starting ON the PDF may be ambiguous (scroll page vs scroll PDF). See device QA scenario 10 — the observed behavior should be recorded here once tested.
- **`onRender` never fires:** If a corrupt PDF neither triggers `onError` nor fires `onRender`, the loading spinner overlays the PDF view indefinitely. No timeout is implemented; this is a known limitation of the underlying `flutter_pdfview` package.

## Extracted Decision-Rule Functions

Four top-level pure functions (plus one message constant) live in the same file and are called by `_DocViewerState`. They are extracted so tests can reach them directly (same pattern as `pdfFileNameFromUrl` in `otq_pdf_viewer.dart`).

| Function | Rule |
|---|---|
| `docViewerSourceIsUsable(String resolved)` | `false` if empty or contains `{` (unresolved token) |
| `docViewerNeedsStorageResolve(String sourceType, String resolved)` | `true` if `sourceType == 'path'` or `!resolved.startsWith('http')` |
| `docViewerSwipeHorizontal(String swipe)` | `true` if `swipe != 'vertical'` (mirrors `OtqPdfViewer`) |
| `docViewerVariantBMessage` (const) | Fixed message string for Variant B unusable source — exported so tests assert against it without coupling to wording |
| `docViewerUnusableSourceMessage(bool hasTable, String emptyText)` | Returns `docViewerVariantBMessage` when `hasTable` is true; returns `emptyText` otherwise |

## See Also

- [pdf_viewer.dart](../../lib/widget/pdf_viewer.dart) — the older `PDF_VIEW` card-that-opens-a-route (different component type, different UX)
- [otq_pdf_viewer.dart](../../lib/page/otq_pdf_viewer.dart) — the fullscreen PDF page (reused by DOC_VIEWER's fullscreen icon)
