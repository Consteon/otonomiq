# DocDownload (`DOC_DOWNLOAD`)

Download button that fetches a file from a URL (or Firebase Storage path) and presents the OS share sheet.

- **File:** [lib/widget/doc_download.dart](../../lib/widget/doc_download.dart)
- **Class:** `DocDownload` (StatefulWidget)
- **Status:** draft
- **Widget version:** v1
- **Introduced on branch:** `dev`

## Purpose

Provides a tap-to-download action for documents whose URL is known at render time (via `{token}` resolution from routeParams). The first consumer is slip gaji detail (payslip PDF).

## Signature / Constructor

```dart
DocDownload({
  required Key key,
  required dynamic component,
  required String scrName,
})
```

## `component` shape

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `url` | String | yes | `''` | Source URL. Supports `{token}` markers resolved via `TokenResolver.curly`. If the resolved value does not start with `http`, treated as a Firebase Storage path (resolved via `#STORAGE_BUCKET`). |
| `fileName` | String | no | basename from URL | Save-as filename. Supports `{token}`. Falls back to `pdfFileNameFromUrl(downloadUrl)` then `'document.pdf'`. |
| `mode` | String | no | `save` | **Parsed but INERT in v1.** Both `save` and `share` route to the OS share sheet. Upgrade path: MediaStore MethodChannel for direct-to-Downloads on Android. |
| `icon` | String | no | `download` | Icon name passed to `stringToIconData`. (The `'download'` key was added to the icon map for this widget.) |
| `text` | String (diamond-separated) | no | see below | 4 slots: `label`/`progress`/`success`/`failure`. |
| `biometrik` | String | no | absent (OFF) | `"true"` activates biometric gate before download. |
| `biometrikPin` | String | no | absent (bio-only) | `"true"` allows PIN/pattern/passcode. |
| `biometrikText` | String (diamond-separated) | no | ID defaults | `reason`/`failTitle`/`failMessage` for the gate. |

### `text` slots

| Index | Purpose | Default |
|---|---|---|
| `[0]` | Button label | `Unduh` |
| `[1]` | Progress label (while downloading) | `Mengunduh...` |
| `[2]` | Success toast | `Tersimpan` |
| `[3]` | Failure toast | `Gagal mengunduh` |

A single value (e.g. `"Unduh PDF"`) populates slot 0 only; remaining slots use Indonesian defaults. A **blank-but-present** slot (e.g. `"Unduh PDF◆◆Tersimpan◆Gagal"` — an empty slot 1) also falls back to its default: `docDownloadTexts` applies a `trim().isEmpty → default` guard (same idiom as `bioGateTexts`), because `SduiSpec.text` is a length guard only.

## Spec divergence (v1)

The spec says "Android -> folder Downloads." In v1, BOTH platforms route through `share_plus` (OS share sheet). Reason: `WRITE_EXTERNAL_STORAGE` is capped at `maxSdkVersion=28` in AndroidManifest, so direct file writes to `/Download` are impossible on Android 10+. Upgrade path: add a Kotlin MethodChannel using MediaStore API for Android 10+ direct-to-Downloads; keep share sheet for iOS.

## URL resolution

Mirrors DOC_VIEWER exactly:

1. `TokenResolver.curly(rawUrl, scrName)` resolves `{token}` markers
2. `docViewerSourceIsUsable(resolved)` -- empty or still contains `{` -> failure toast
3. `docViewerNeedsStorageResolve('url', resolved)` -- non-http -> Firebase Storage path: reads `#STORAGE_BUCKET` (must be `FirebaseStorage` instance, fail-closed on null/wrong type), calls `.ref(resolved).getDownloadURL()`
4. Direct http URL used as-is

## HTTP status handling (W3)

`createFileOfPdfUrl` (`lib/page/otq_pdf_viewer.dart`) now throws `HttpException` when `response.statusCode != 200` **inside the shared helper**. Previously an expired Firebase Storage token (403) or a wrong path (404) returned a small XML/HTML error body that was written to disk and "shared successfully" — nothing threw. The guard was placed in the shared helper (not per-caller) because both existing callers already `.catchError` a throw (`OtqPdfViewer.initState`, `DocViewer._downloadPdf`), so the change is strictly an improvement for them too; `DocDownload` catches the throw and shows the failure toast.

## Share result (W2)

`SharePlus.instance.share(...)` returns a `ShareResult`. The success toast is suppressed when `result.status == ShareResultStatus.dismissed` (user cancelled the sheet — nothing was saved). It is still shown on `ShareResultStatus.unavailable`, which is the normal Android outcome when the platform cannot report the action.

## Snackbars (W4)

User-facing toasts use a private `_showSnackBar` built on `ScaffoldMessenger` (same idiom as `ftz_bluetooth_printer._showSnackBar`), not `Get.snackbar`. `DocDownload` has no other GetX dependency — `bioGate` owns its own `Get.dialog` internally.

## Notes

- The temp file is named by `pdfFileNameFromUrl(downloadUrl)` in the platform cache dir. Two files sharing a basename overwrite each other there — harmless, because the share uses `fileNameOverrides` for the user-facing name.
- The widget renders `Padding → SizedBox(width: infinity) → ElevatedButton.icon`, which has an intrinsic height and is safe inside the SDUI `ListView.builder` (unbounded vertical constraints). Do NOT wrap it in a fixed height.

## Reused machinery

`bioGate` (biometric_gate.dart), `docViewerSourceIsUsable` / `docViewerNeedsStorageResolve` (doc_viewer.dart), `createFileOfPdfUrl` / `pdfFileNameFromUrl` (otq_pdf_viewer.dart), `TokenResolver.curly` (token_resolver.dart), `stringToIconData` (global2.dart), `SharePlus.instance.share` (share_plus, precedent: ftz_bluetooth_printer.dart).

> **Commit coupling (W6):** `docViewerSourceIsUsable` / `docViewerNeedsStorageResolve` live in `lib/widget/doc_viewer.dart`, which is currently **UNCOMMITTED** (prior DOC_VIEWER round, GATE-2 HOLD). Any commit of `doc_download.dart` MUST include `doc_viewer.dart`, or a fresh clone will not build.

## See Also

- [doc_viewer.md](doc_viewer.md) -- inline PDF renderer (same URL resolution path)
- [list_card.md](list_card.md) -- biometric gate fields documented there too
