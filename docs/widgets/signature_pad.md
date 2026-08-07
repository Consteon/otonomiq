# SignaturePad

Hand-drawn stroke capture widget for P11 DeliveryWorkspace using CustomPaint + GestureDetector.

- **File:** [lib/widget/signature_pad.dart](../../lib/widget/signature_pad.dart)
- **Class:** `SignaturePad` (StatefulWidget)
- **Status:** draft — built; pending builder config (unique position, `F=TRUE`) + QA
- **Widget version:** v1

## Purpose

Provides a signature capture area for customer confirmation. On each pen stroke, the signature is rendered to a JPEG, saved to local storage via `prepareImageAsLocal(forceRename: true)`, registered in `imageMap`, and written to `txfController[scrName][position]` as an `aum__...__mua` token. The existing submit/historySync pipeline uploads the JPEG to Firebase Storage and writes the URL to the event doc (e.g. `task.sig`).

Empty state shows a placeholder with a dashed slate border; filled state shows the signature with a solid emerald border and a "Hapus" clear button.

## Component JSON

```json
{
  "type": "SIGNATURE_PAD",
  "optional": true,
  "position": 4,
  "writeField": "sig",
  "folder": "signature",
  "filename": "sig",
  "text": "placeholder◆clearLabel◆hintEmpty◆hintFilled"
}
```

### Config fields

| Field | Default | Description |
|---|---|---|
| `position` | (required) | Integer slot in the submitted record. Must be unique per screen. |
| `folder` | `'signature'` | Firebase Storage subfolder for the JPEG. |
| `filename` | `'sig'` | Base filename; a 5-char UUID suffix is appended and rolled per signature **session** (see Per-screen state), not per State. |
| `optional` | `false` | Whether the field is optional. |
| `text` | (built-in defaults) | Diamond-separated 4-slot text: placeholder, clearLabel, hintEmpty, hintFilled. |

## Write path

1. `_onPanEnd` -> `_exportAndSave()` (async, guarded by `_saving` flag)
2. `PictureRecorder` + `Canvas` -> opaque white background + strokes -> `ui.Image`
3. `toByteData(format: rawRgba)` -> `image` package `Image.fromBytes` -> `encodeJpg(quality: 90)`
4. Write JPEG to temp file -> `prepareImageAsLocal(forceRename: true)` -> `saveImagePutInImageMap`
5. Write `aum__` token to `txfController[scrName][position]`

**CRITICAL:** `forceRename: true` is mandatory. Without it, the signature JPEG path (no `OTQC` artifact) falls to `renamePath`'s else branch, the file is never moved, and the history queue wedges on an `aum__` entry with no `___` separator.

## Per-screen state (why it is static, not instance fields)

Per-screen state is reset through `clearData` (which calls `clearSignatureState`) on every route change — the codebase's per-screen-state convention. This does **not** rely on `State` lifetime: a normal `gotoRoute` disposes the route's `State` (its `ObjectKey` is a `LocalKey`, not a `GlobalKey`, so nothing preserves it across the unmount), but an `AnyPage` in-place reconciliation (`any_page.dart:115`, `buildPage(clear:false)`) can rebuild widgets onto an already-mounted subtree with identical `ObjectKey`s and reuse the `State`. Holding the leak-prone state statically and clearing it via `clearData` resets it in both cases, so signature A's ink and file identity never leak onto signature B — which would otherwise overwrite A at the same deterministic Storage key (`folder/filename.jpg`), a silent loss of a customer proof-of-delivery signature.

The leak-prone state (stroke list, file identity, `saving`/`pendingExport` flags) lives in a **static `Map<String, _SigWriteState>` keyed by `scrName`** on `SignaturePad`, never on the `State`. Two guards keep signatures distinct:

- **Reset on route change** — `SignaturePad.clearSignatureState(scrName)` drops the screen's entry. It is registered in `clearData` (`api.dart`) alongside the sibling driver widgets (`CustodyCountList.clearCountStore`, `NfcReader.clearCollectorState`, …), so every navigation starts the pad empty.
- **Roll per signature session** — the file identity is minted fresh on the empty→non-empty stroke edge (`_onPanStart`) and reset on `_onClear`. It stays stable across the strokes of one signature (so history-sync's re-upload targets one key) but changes for the next submitted signature, so B never reuses A's key even without a navigation in between.

### Static API

| Symbol | Description |
|---|---|
| `SignaturePad.clearSignatureState(scrName)` | Drop a screen's signature write-state (called from `clearData`). |
| `SignaturePad.rollFileName(scrName, prefix)` | Mint + store a fresh file identity for a new signature session; returns it. |
| `SignaturePad.fileNameOf(scrName)` | Current stored file identity (`''` if no active session). |

## Builder handoff (Google Sheet config)

The widget change is INERT until the builder:

1. Sets a **unique `position`** (not 3 -- collision with GET_IMAGES).
2. Flips **`F` to `TRUE`** (currently FALSE / disabled).
3. Adds the submit reference in `addToEvent`/`updateEventRow`: note that `◁N▷` white-triangle tokens resolve to form position `N-1`, so a widget at `position:4` is read by `◁5▷`, not `◁4▷`. The spec's suggested `⭘sig◼◁4▷` would read position 3 (the GET_IMAGES position).
