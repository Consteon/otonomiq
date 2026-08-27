# OcrCapture

Photograph a document/meter, run Google ML Kit Latin text recognition **on-device**, and write the recognised values into OTHER form positions listed in `ocrTargets`; the widget's own `position` holds the photo URL.

- **File:** [lib/widget/ocr_capture.dart](../../lib/widget/ocr_capture.dart) (+ [lib/widget/ocr_capture_support.dart](../../lib/widget/ocr_capture_support.dart))
- **Class:** `OcrCapture` (StatefulWidget), plus `OcrTapScreen` / `OcrTapResult` / `OcrCaptureEntry`
- **Status:** draft
- **Widget version:** v1
- **SDUI type:** `ocr_capture` (also accepts `ocrcapture`) — dispatch branch in [lib/widget/build_display_component.dart](../../lib/widget/build_display_component.dart), immediately before `tip == 'signature_pad'`
- **Replaces:** the earlier, never-shipped `ocr` / `OcrField` widget (deleted; no page JSON used `type:"ocr"`)

## Purpose

Field agents mistype meter readings and invoice totals. This widget lets the agent photograph the value once and have the machine transcribe it, while keeping the human in charge: the recognised value is written into an ordinary form field the agent can still edit, and the photo itself is uploaded as evidence.

Use it instead of `GET_IMAGES` + a manual `TXF` when the photo already contains the number the form needs. Use plain `GET_IMAGES` when the photo is only evidence.

Two variants:

| variant | behaviour |
|---|---|
| `auto` | the machine picks ONE value from inside the guide box; the agent confirms by editing the target field. Never auto-submits. |
| `tap` | the agent taps TextElements on the captured photo; each tap fills the active chip's target and auto-advances. |

## Signature / Constructor

```dart
OcrCapture({
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
| `key` | `Key` | yes | — | `ObjectKey("$scrName-${component['position']}")` (the dispatcher's `txfKey`) |
| `component` | `dynamic` | yes | — | Component config; server JSON, read through `SduiSpec` |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Outer padding |

There is no `cnt` parameter: the widget always uses `txfController[scrName][position].controller`.

### `component` shape

All config reads go through `SduiSpec` ([lib/sdui_spec.dart](../../lib/sdui_spec.dart)) — decode (`autheniumDecode`) → ◆-split (`diamondTextToList`) → index-guard, in one place. **These names are frozen**; a renamed parameter makes sheet config silently dead.

| key | read via | notes |
|---|---|---|
| `variant` | `spec.str('variant','auto').toLowerCase()` | anything not `tap` ⇒ `auto` |
| `position` | `component['position']` | the widget's OWN slot — receives the photo URL |
| `ocrTargets` | `ocrParsePositions(spec.str('ocrTargets'))` | split on `separator[4]` (`,`) — **not** a hardcoded comma |
| `ocrPattern` | `spec.list('ocrPattern')` | ◆-split, index-guarded, per target |
| `ocrType` | `spec.list('ocrType')` | ◆-split, index-guarded; `text` \| `number` \| `date`, default `text` |
| `metaTargets` | `ocrParsePositions(...)` | ≥1 ⇒ write src; ≥2 ⇒ write raw; empty ⇒ write nothing at all |
| `guide` | `ocrParseRatio(spec.str('guide'))` | `"4:1"`→4.0, `"1.6:1"`→1.6, `"4"`→4.0; invalid/empty ⇒ `null` (full frame) |
| `ocrMaxSide` | `ocrMaxSideOf(spec)` | default 1600, clamped to `[320, 4000]` |
| `source` | `spec.str('source').toLowerCase()` | `gallery` · `both` (2-icon chooser) · anything else ⇒ camera |
| `max` | read, **ignored** | v1 is one photo (spec §11). Deliberate and documented, not an oversight. |
| `folder` `filename` `imageParameter` `previewSize` `currentValue` `isEnabled` | same semantics as `GET_IMAGES` | see [otq_get_images_2.dart](../../lib/widget/otq_get_images_2.dart) |
| `camera` | `spec.intOr('camera',1)` | `0` ⇒ front lens, anything else ⇒ back |
| `text` | `spec.text(i)` | ◆-slots, see below |

#### `text` ◆-slots and their fallbacks

**Zero hardcoded user-visible Indonesian lives in Dart.** Every fallback is either "render nothing" or a position marker; icons carry the rest.

| # | meaning | fallback when blank/absent |
|---|---|---|
| 0 | widget label in the form | render NO label row |
| 1 | camera-screen hint (becomes the `acquireCamera` dialog title) | falls back to slot 0, then `''` |
| 2 | tap-screen hint | render NO hint row |
| 3 | failure message / rejected-tap message | render NOTHING (silent) |
| 4 | "from photo" badge prefix | render the value chip without a prefix |
| 5.. | chip name per target, index-aligned with `ocrTargets` | `◁<pos>▷` (a position marker, not Indonesian) |

#### Alignment rules (must not crash)

`ocrPattern` / `ocrType` / `text[5..]` may be SHORTER than `ocrTargets` ⇒ defaults apply (pattern = accept anything, type = `text`, label = `◁pos▷`). LONGER ⇒ the excess is ignored. `variant:"auto"` uses index 0 only, but `ocrTargets` with several entries must not error.

Every fixed index is written `arr.length > N ? arr[N] : def` — never `arr[N] ?? def`, which still throws `RangeError` on a lean tenant sheet.

> `diamondTextToList('')` returns `['']` (length 1), NOT `[]` — the `empty` sentinel is `"--"`. `SduiSpec` short-circuits that trap for us.

## Usage Examples

### `auto` — water meter (dev spec §8a)

```json
{"type":"OCR_CAPTURE","variant":"auto","position":4,
 "ocrTargets":"7","ocrPattern":"\\d{4,6}","ocrType":"number",
 "metaTargets":"8,9","guide":"4:1","ocrMaxSide":1600,
 "folder":"meteran","filename":"stand","imageParameter":"400,400,80",
 "previewSize":120,"isEnabled":"TRUE",
 "text":"Foto Meteran◆Pas-in angka ke kotak◆◆Gak kebaca — ketik manual◆dari foto◆Stand Meter"}
```

The agent taps the empty zone, frames the register inside the guide box, and shoots. Position `7` receives plain digits; position `4` receives the photo URL; positions `8`/`9` receive `ocr` and the raw ML Kit text.

### `tap` — invoice header (dev spec §8b)

```json
{"type":"OCR_CAPTURE","variant":"tap","position":10,
 "ocrTargets":"11,12,13","ocrType":"text◆date◆number",
 "ocrPattern":"◆\\d{2}[/-]\\d{2}[/-]\\d{2,4}◆[\\d.,]+",
 "metaTargets":"14","folder":"invoice","filename":"inv",
 "text":"Foto Invoice◆Foto seluruh halaman◆Ketuk nilainya◆Bukan itu◆dari foto◆Supplier◆Tanggal◆Total"}
```

Three chips appear under the photo. Each tap fills the active chip and advances to the next EMPTY one; tapping a chip makes it active again; `✓` closes the screen even with empty chips (the rest is typed manually).

## State / Bloc / Dependencies

- **Per-field state:** `txfController[scrName][position]` — `controller.text` (what the field shows) and `finalData` (what submit reads).
- **Per-screen widget state:** `static Map<String, Map<int, OcrCaptureEntry>> OcrCapture._store`, outer key `scrName`, inner key `position`. Nothing is added to `global.dart` / `global2.dart`, and no `#KEY` / secure-storage / `@` key is introduced by this widget.
- **Reset:** `ScreenSession.ensure('OcrCapture.store', …, nav: NavPolicy.all, clearAllFn: OcrCapture.clearAll, rebuild: RebuildPolicy.none)`.
- **Repaint:** `GetBuilder<WidgetUpdateController>(id: '$scrName-$position')` + an `Obx` reading `OcrCapture.resetRev`.
- **Plugins:** `google_mlkit_text_recognition` (on-device Latin), `camera` (via the repo's `PhotoCamera`), `image_picker`, `image`, `path_provider`, `uuid`.
- **Side effects:** `prepareImageAsLocal` (moves the file into `otq_images`), `saveImagePutInImageMap` (registers the `imageMap` entry; the Storage upload inside is `safeUnawaited`), and cross-position writes into sibling record slots.
- **Untouched:** `lib/api.dart`, `lib/global.dart`, `lib/global2.dart`, `lib/init_values.dart`, `otq_txf_2.dart`, `otq_get_images_2.dart`.

## Important Behavior

### Pipeline order — read first, shrink after

```
capture at ORIGINAL resolution (ResolutionPreset.high ⇒ 1280×720)
  → [1] optional guide crop → ML Kit reads it → fills target positions
  → [2] resize to imageParameter (400,400,80) → prepareImageAsLocal → saveImagePutInImageMap
```

**Reversing this kills the feature.** Reading from the 400×400 upload copy turns invoice text and a meter register into mush — ML Kit needs the full-resolution frame, and the small copy exists only so agent quota and Storage cost stay exactly what `GET_IMAGES` already costs.

`acquireCamera` receives `ocrMaxSide` as its `maxSize` (not `imageParameter`), otherwise the file handed back is already 400 px. The decode/crop/resize all run inside `compute()`: Flutter 3.44 merged the UI thread into main, so heavy pure-Dart work on the main isolate is an ANR, not jank. (Debug builds run the pure-Dart `image` pipeline 10–30× slower than AOT — never judge decode speed from `flutter run`.)

### `PhotoCamera` additions are default-off

`acquireCamera` gained two OPTIONAL named parameters, `preset` and `guideRatio`. A call site that passes neither behaves EXACTLY as before (`ResolutionPreset.medium`, no overlay). `OCR_CAPTURE` passes `high` because `medium` caps at 720×480 (camerax) / 480×360 (avfoundation) — a 0.35 MP frame no OCR can read reliably.

### The guide box — one geometry function, two consumers

`ocrGuideRect(w, h, ratio, {widthFraction: 0.86, pad: 0.08})` returns `[x, y, cropW, cropH]`, or `[]` when degenerate. The camera overlay painter (`OcrGuidePainter`, in `photo_camera.dart`) calls it with `pad: 0` so the agent sees the tight box; the ML Kit crop uses the default pad, giving 8 % slack per side to absorb the mismatch between the `CameraPreview` rect and the captured frame. If the crop throws or degenerates, OCR falls back to the FULL frame (fail-open). `tap` ALWAYS reads the full frame — the agent must see the whole document — so `guide` affects `auto` only.

### `date` targets

`ocrType:"date"` writes the same convention a `txf` with `variant:"date"` writes:

- `finalData` = **epoch millis as a String**, tz-adjusted (`DateTime(y,m,d).add(Duration(minutes: tzOffset)).millisecondsSinceEpoch.toString()`), equal to `DateTime.utc(y,m,d).millisecondsSinceEpoch`.
- `controller.text` = `DateFormat(format).format(DateTime(y,m,d))`, where `format` is read from the **TARGET component's own** `format` key in `screenUIComponent[scrName]['children']`, defaulting to `d-MMM-yyyy`.

`utc` is deliberately NOT consulted: `otq_txf_2`'s `isDate` branch ignores it too — the `utc` flag only branches the `dateTime` case, and OCR of a date yields no time. `ocrType:"date"` therefore always writes the DATE convention. Documented, not silently dropped.

**Known limitation (accepted, not a bug):** after an OCR date fill, if the agent then taps the date field, `chooseDate` immediately re-writes `controller.text` and `finalData` from its own untouched `selectedDate`. That is an explicit agent action, not a silent regression.

### Reset policy — `NavPolicy.all` + `resetRev` (do NOT simplify)

Two independent failure modes, two required fixes:

**(a) `NavPolicy.screen` LEAKS for state that is RENDERED.** Navigation is `gotoRoute` → `reloadPage`, which returns the CACHED `linkElement[scrName]` and schedules `clearData` POST-frame — the re-entered page has ALREADY painted. `NavPolicy.screen` clears only the ENTERING screen's slice, so leaving screen A never clears A, and the next visit paints the PREVIOUS capture's chips and crop, live and tappable, writing stale values into record slots. `NavPolicy.all` + `clearAllFn` wipes the whole store on the nav AWAY, off-screen, before the next visit's first paint. `SignaturePad`'s `NavPolicy.screen` precedent does NOT transfer — its store holds a filename consumed by submit, not content that is rendered; only rendered state can paint stale. The precedent to copy is `GroupPicker`.

**(b) A `clearData` WITHOUT navigation** (`saveSend`, the `clear` RBT) wipes the store while stale UI stays painted. Two layers:

1. `GetBuilder<WidgetUpdateController>(id: '$scrName-$position')` — `clearData` calls `ScreenSession.navReset` FIRST and `WidgetUpdateController.update(widgetsToUpdate)` LAST, and `widgetsToUpdate` contains `'$scrName-$position'` for every position on the screen. A same-screen `clearData` therefore repaints us after the store was cleared.
2. `clearData('someOtherScreen')` still runs `clearAll()` and drops OUR slice with no update sent to us — so `static final RxInt resetRev` is bumped in `clearState`/`clearAll` and read as the **first unconditional statement** inside an `Obx` nested in the `GetBuilder`. An `Obx` that registers ZERO observables is a documented fatal class in this repo; hoisting the read is what prevents it.

`_store` stays a PLAIN `Map` with a SEPARATE `RxInt` — making the map itself an `RxMap` would notify during `build()` (it is mutated there via `putIfAbsent`) and crash.

**Consequence (accepted):** navigating away DISCARDS an unsubmitted capture, same semantics as `GroupPicker`. `clearData` resets the form's `finalData` to `initialValue` anyway, so the form was being reset regardless — but the photo URL goes with it.

### Watermark caveat — always set `guide` for `auto`

`processCapturedImage` bakes a `dd MMM yyyy HH:mm` timestamp into the top-left of EVERY capture, and ML Kit will read it.

- `auto` **with** `guide` (the recommended config): the watermark is outside the centred crop. Not seen. ✔
- `auto` **without** `guide`: the watermark's digits compete for "longest digit run". `ocrPattern` is the filter. **Set `guide` on every `auto` config.**
- `tap`: the watermark is one more tappable element. Harmless.

### Normalisation — anti-locale by construction

`ocrNormalizeNumber` never touches a locale formatter: keep only `0-9 . ,`, trim edge separators, then let the LAST `.`/`,` decide — a 3-digit tail means it was a THOUSANDS separator, anything else means DECIMAL — then strip leading zeros. Executed outcomes: `"3.663.000"`→`3663000`, `"3 663 000"`→`3663000`, `"01234"`→`1234`, `"12,345"`→`12345`, `"1.234,56"`→`1234.56`, `"0,5"`→`0.5`, `"PDAM"`→`""`. `"1.234"`→`1234` is a documented ambiguity resolved in favour of id_ID thousands.

`ocrMinCandidateDigits = 2` is load-bearing: a water meter prints its unit beside the register and ML Kit reads `m3` as a Latin `3`, so **`ocrDigits('m3') == '3'`** — without the floor every capture yields a junk `3` candidate. Applied to `ocrType:"number"` only; a 1-character register/plate/serial does not exist.

`ocrPickAuto` ranks on the **RAW** digit count, not the normalised one: normalisation strips leading zeros, and a meter prints them as standard, so ranking normalised would make a `012345` register measure 5 and lose to any 6-digit junk in the frame. Ties resolve to reading order.

### Pattern semantics

`ocrAccepts(rx, raw, normalized)` returns true when `rx == null` **or** the pattern matches EITHER side. It has to accept both because the spec's own examples target both: `\d{4,6}` fits the normalised meter reading, while `\d{2}[/-]\d{2}[/-]\d{2,4}` (date) and `[\d.,]+` (invoice total) target the RAW. A malformed sheet regex compiles to `null` (= accept anything) instead of crashing.

In `tap`, the pattern validates **on tap**; it NEVER filters what is tappable. A rejected tap keeps the chip active, does not advance, and shows `text[3]` briefly. Elements are never dimmed or disabled — stranding the agent is forbidden.

### `metaTargets`

| condition | `metaTargets[0]` (src) | `metaTargets[1]` (raw) |
|---|---|---|
| OCR wrote at least one target | `ocr` | raw ML Kit text, `,`-joined per target |
| any written target's controller text later diverges | `ocr_edit` (one-shot flip) | unchanged |
| ML Kit returned nothing / nothing matched | `manual` | `ocrRawSummary(elements)`, truncated to 200 chars |
| `×` delete pressed | `manual` | unchanged |
| `metaTargets` empty | nothing written at all | — |

Implemented as a `TextEditingController` listener, NOT a submit hook — the `api.dart` submit path is untouched. The listener compares against the exact string WE wrote (so our own write never trips it), flips once, and detaches itself; `dispose()` detaches unconditionally, because a leaked listener on a SHARED `TextEditingController` outlives the widget.

Raw values are joined with `separator[4]` (`,`). **Not ◆ or any other `forbiddenCharacter`**: `saveSend` replaces all 36 of them with SPACE, so a ◆-joined raw column would arrive mangled. A comma inside a raw OCR string makes this column ambiguous — accepted; it is a measurement column, never parsed.

### Failure is never an error

No dialog, no retry button. The target field is left empty, `text[3]` is shown inline, **the photo still uploads**, and the form stays submittable. `failed` is a render flag and nothing more.

### Retake and delete

- Tapping the existing thumbnail = RETAKE: everything re-runs and target values are OVERWRITTEN (the agent is correcting).
- `×` removes the PHOTO only (own position cleared, thumbnail dropped) and sets `metaTargets[0]` to `manual`. The human-approved numbers are NOT touched.

### `isEnabled` / `run:"N:disable"`

`buildDisplayComponent` seeds `isEnabled`/`initialIsEnabled` from `component['isEnabled']`, and `run:"N:disable"` flips it at runtime. The widget reads `ic.isEnabled` inside the `GetBuilder` and nulls every `onTap`/`onPressed` when false — matching `OtqGetImages2`.

### Divergence from the dev spec: badge placement

Dev spec §4a draws the `text[4]` "from photo" badge **inside the TARGET field**. This implementation renders it as a chip on the OCR widget instead: injecting a badge into a sibling `txf`'s `InputDecoration` would mean editing `otq_txf_2.dart`, a deferred refactor. Raise it with the spec owner if the in-field badge is load-bearing.

### Divergence from `GET_IMAGES`: `source:"both"`

In `GET_IMAGES`, `both` is currently dead config (anything ≠ `gallery` is treated as camera). `OCR_CAPTURE` implements a real 2-icon chooser instead — shipping dead config is a failure mode this repo has been bitten by before.

## Testing

Covered:

- [test/ocr_capture_support_test.dart](../../test/ocr_capture_support_test.dart) — 57 pure-logic tests: seed normalisation, config parsing, alignment/length guards, number and date normalisation, candidate selection, geometry, the two `compute()` entry points' fail-open behaviour, sibling lookup and the cross-position write. Each test names the production change that turns it RED.
- [test/ocr_capture_widget_test.dart](../../test/ocr_capture_widget_test.dart) — 8 pump tests: label/hint slot routing, blank-slot suppression, `isEnabled`, the failure banner, the badge chip, the `"null"` seed normalisation, a missing position, and the §2.5 reset regression (`clearAll()` must repaint back to the empty state).

**Not covered, and why:**

- **The native ML Kit side.** `TextRecognizer.processImage` is a MethodChannel; under `flutter test` it raises `MissingPluginException`. **No test in this repo says anything about the native side** — that is device QA.
- `ocrFlattenElements` — needs ML Kit types; it is a dumb 3-loop mapper with no decision in it.
- The camera preview, the guide overlay paint, `OcrTapScreen` with a real photo, and the real Storage upload.

The accuracy harness for `auto` is a separate entrypoint, [lib/dev/ocr_spike_main.dart](../../lib/dev/ocr_spike_main.dart) (`flutter run -t lib/dev/ocr_spike_main.dart`), NOT a `flutter test` — for the same MethodChannel reason. Nothing imports it, so `flutter build` (which targets `lib/main.dart`) tree-shakes it out of every release artifact. It gates `auto` TUNING only; it does not gate shipping the widget, and `tap` is unaffected by 7-segment accuracy.

The widget pump harness deliberately gives the component **NO `table` key** — that omission is what keeps `subscribeToMapCollection`, and therefore Firebase, out of the tree.

## ⚠ Maintenance tripwire — the offline guarantee

The offline promise rests on ONE line in the plugin's own build file:

```
~/.pub-cache/hosted/pub.dev/google_mlkit_text_recognition-<version>/android/build.gradle
    implementation("com.google.mlkit:text-recognition:16.0.1")
```

That is the **BUNDLED** artifact — it ships `jni/<abi>/libmlkit_google_ocr_pipeline.so` inside the APK, so recognition works on a handset that has never been online.

**If the plugin ever switches to `com.google.android.gms:play-services-mlkit-text-recognition`, offline OCR dies SILENTLY** — no compile error, no test failure, just a handset in the field that cannot read. Re-check that line on every plugin bump. It also means the APK carries the model: the arm64 pipeline `.so` is ≈11 MB before R8, and the real cross-ABI delta should be measured on the first release build.

## See Also

- [otq_get_images_2.md](otq_get_images_2.md) — the plain photo-upload widget this one borrows `folder` / `filename` / `imageParameter` / `previewSize` semantics from
- [otq_txf_2.md](otq_txf_2.md) — the usual target widget; its `variant:"date"` branch defines the epoch-millis contract above
- [group_picker.md](group_picker.md) — the `NavPolicy.all` + `resetRev` reset precedent this widget copies
- [signature_pad.md](signature_pad.md) — the `NavPolicy.screen` precedent that deliberately does NOT apply here
