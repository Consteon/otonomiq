# DigitPad

N locked digit boxes shaped like a mechanical water-meter face, filled **only** by the widget's own numpad, with an inline 3-tier verdict against the last stored reading.

- **File:** [lib/widget/digit_pad.dart](../../lib/widget/digit_pad.dart) (+ [lib/widget/digit_pad_support.dart](../../lib/widget/digit_pad_support.dart))
- **Class:** `DigitPad` (StatefulWidget) — state class `DigitPadState` is public
- **Status:** draft
- **Widget version:** v2 — spec rev **2026-08-20f** + **meter-serial-verify** (2026-08-25). §7.8 (OCR vs typed digits) is **CANCELLED**; §7.7 is now the serial-number identity check
- **SDUI type:** `DIGIT_PAD` (dispatch accepts `digit_pad` and `digitpad`)

## Purpose

A field officer copies digits off a water meter and that number becomes a tenant's bill. Two expensive failure modes: the **wrong digit count** (bill off by 10×) and **copying the red litre drum** too (off by 1000×). This widget makes both structurally impossible rather than merely validated — there are exactly N boxes, there is no box for red digits, and there is no decimal separator anywhere.

Product decisions this implements (`docs/handoff-meter-pascal.md`, 2026-08-18):

| # | Decision | How it lands here |
|---|---|---|
| 13 | Locked digit boxes, count **per point** | Extra digits are impossible, not rejected. rev d: when the point has no config the officer picks the count and the pick is written back |
| 14 | **REVISED 18 Aug — red digits ARE used at some sites.** Stored as TWO numbers, black + red | rev c: red boxes are rendered red with a **visible comma** between the groups. `dgm: 0` ⇒ no red boxes and no comma |
| 15 | Photo first, number second | The widget sits **below** `getImages1` on the page |
| 15b | **REVISED 19 Aug — the verdict is a BOTTOM SHEET, and only when something is wrong** | rev e: `sane` raises nothing; `spike`/`backward` raise a dismissable sheet that leaves a tappable compact row |
| 16 | Check runs while the officer is still at the meter | Verdict fires the moment the last box fills |
| 17 | The officer always wins | Verdict **does not block**; a backward reading is stored and flagged |
| 21 | Except initial survey | `blockOnBackward` — the only blocking path in the whole system |
| 6 | OCR is inverted: the officer fills, OCR checks | OCR **never** writes into the boxes |

## Signature / Constructor

```dart
DigitPad({
  Key? key,
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
| `key` | `Key?` | no | `null` | `txfKey` = `ObjectKey("$scrName-${component['position']}")` from the dispatcher |
| `component` | `dynamic` | yes | — | Server JSON component (shape below) |
| `scrName` | `String` | yes | — | Screen this widget is mounted on |
| `lPad`/`tPad`/`rPad`/`bPad` | `double` | yes | — | Left/top/right/bottom padding |

### `component` shape

| Key | Read as | Semantics if blank/absent |
|---|---|---|
| `position` | `digitPadParsePosition(component['position'])` | null → renders `--TYPE-- Error: position missing`. **Never `getPosition()`** — that throws on a lean sheet |
| `vidtable` / `com` | `resolveAppVid(component)` | — |
| `table` | `SduiSpec.str('table')` → `parseTablePath` | empty docId → no subscription, no doc, no verdict |
| `search` | **RAW** `component['search'].toString().trim()` | `filterDriverHomeDocs` owns the `autheniumDecode`; reading it through `SduiSpec.str` would decode twice |
| `digitsField` | `SduiSpec.str('digitsField')` | blank → count comes from the slot or the picker only |
| `digitsRedField` | `SduiSpec.str('digitsRedField')` | blank → red count falls to the slot, then to `0` |
| `digitsPosition` | `digitPadParsePosition(SduiSpec.str('digitsPosition'))` | **OUTPUT slot** (rev d) — also read first for the latch; blank → the count is never persisted and the picker returns next month |
| `digitsRedPosition` | `digitPadParsePosition(...)` | **OUTPUT slot**; blank → the red chip row is not rendered at all and the red count falls to `0` (a pick with nowhere to land would be dead UI) |
| `digitsSourcePosition` | `digitPadParsePosition(...)` | **OUTPUT slot**, `config` or `field`; blank → provenance not recorded |
| `digitsMode` | `SduiSpec.str('digitsMode', 'auto')` | `auto` = locked when config exists · `editable` = segment-10 link always available. **Config missing ⇒ the picker appears in BOTH modes** |
| `digitsOptions` | `digitPadParseOptions(SduiSpec.list('digitsOptions'), allowZero: false)` | **empty ⇒ the picker can never appear and never gates** (see "no pickable options" below). Same result when `digitsPosition` is blank/unparseable/equal to `position`: a pick that cannot be stored must not gate |
| `digitsRedOptions` | `digitPadParseOptions(SduiSpec.list('digitsRedOptions'), allowZero: true)` | empty → no red row in the picker. A `0` entry is the meaningful choice "no red digits" |
| `compareField` | `SduiSpec.str('compareField')` | blank → **no verdict at all** (silent) |
| `avgField` | `SduiSpec.str('avgField')` | blank → spike check off, backward check still on |
| `spikeMultiplier` | `num.tryParse(...) ?? 4` | default `4`; `num` not `int`, so `3.5` works |
| `blockOnBackward` | `str(...).toUpperCase() == 'TRUE'` | anything else → `false` |
| `photoPosition` | `digitPadParsePosition(SduiSpec.str('photoPosition'))` | The `getImages` slot the serial check reads. **Nulled when it equals the pad's own `position`** (that slot holds the digit buffer, and watching it would be a self-`setState` loop). Blank/unparseable ⇒ the serial check is silent |
| `serialField` | `SduiSpec.str('serialField')` | Field on the `meter` doc holding the serial (`msn`). **Blank ⇒ the serial check is dead and ZERO ML Kit calls are made** |
| `blockOnSerialMismatch` | `str(...).toUpperCase() == 'TRUE'` | `TRUE` ⇒ a mismatch kills the page save button. Anything else ⇒ warn only. **v1 must ship `FALSE`** — see the escape-hatch warning below |
| `ocrPattern` | **RETIRED 2026-08-25** — read by nobody, at any time | Its only consumer was the cancelled §7.8. A sheet that still carries the column is ignored **silently, with no code doing the ignoring**: `SduiSpec` only reads keys it is asked for |
| `isEnabled` | `txfController[…].isEnabled`, seeded by `buildDisplayComponent` | `false` → boxes greyed, all taps inert |
| `text` | `SduiSpec.text(i)` | see the segment table below |

### `text` segments (◆-separated)

A **blank segment means that feature is silent** — there is no hand-wrapped fallback anywhere, by design (spec §3.1: "Segmen kosong = fitur itu diam").

| # | Content | Rendered when |
|---|---|---|
| 0 | Field title | non-empty |
| 1 | Hint under the title | non-empty |
| 2 | Verdict — sane | non-empty **and** verdict == `sane` |
| 3 | Verdict — spike | non-empty **and** verdict == `spike` |
| 4 | Verdict — backward | non-empty **and** verdict == `backward` |
| 5 | Footer while submit is blocked | non-empty **and** the gate is engaged |
| 6 | **Serial mismatch** (bottom sheet only) | non-empty **and** the recorded serial was not found in the photo **and** the numeric verdict is `sane` or `none`. Blank ⇒ the serial verdict is silent even when a mismatch was proven |
| 7 | Incomplete message | non-empty **and** `0 < filled < N` (0-filled is silent) |
| 8 | Black picker label | picker visible **and** non-empty |
| 9 | Red picker label | picker visible, `digitsRedOptions` non-empty **and** segment non-empty |
| 10 | `editable` link that opens the picker | `digitsMode:"editable"`, config present **and** non-empty. **Blank ⇒ `editable` behaves exactly like `auto`** |
| 11 | Warning above the picker | picker visible **and** non-empty |
| 12 | Sheet primary button ("fix it") | sheet open **and** non-empty. Closes the sheet and **empties** the buffer |
| 13 | Sheet secondary button ("the officer wins") | sheet open, non-empty **and** the submit gate is NOT engaged (§4c rule 5). Closes the sheet, nothing else |
| 14 | Sheet footer sentence | sheet open **and** non-empty |

None of segments 8–14 has a hand-written default: §3.1 says a blank segment means that feature is silent, and `SduiSpec.text()` is a length guard only (not blank-aware), which is exactly those semantics.

Token substitution inside a segment is a **CLOSED list**: `{value} {prev} {delta} {avg} {serial} {n}`. **`{ocr}` was RETIRED 2026-08-25** (meter-serial-verify §3.2): with substring matching there is no single "OCR value" to display, so it was removed from the pattern and stays literal. `{serial}` carries the serial **recorded on the doc**, never what OCR read off the photo. It is handled by this widget's own `digitPadFillTokens`, **not** by `TokenResolver` — routing `text` through `TokenResolver` would open the list to every screenTx key, so a screenTx entry named `value` or `n` could hijack a verdict message. A token with no value stays **literal** (`{avg}` renders as `{avg}`), matching the `{token}` grammar's pending-safe dialect. `{ocr}` therefore always stays literal in v1.

## Usage Example

```jsonc
{
  "type": "DIGIT_PAD",
  "position": 7,
  "table": "84214220504259//meter",
  "search": "lk◼{lk}",
  "digitsPosition": "9",
  "digitsField": "dg",
  "compareField": "pv",
  "avgField": "avg",
  "spikeMultiplier": 4,
  "blockOnBackward": "FALSE",
  "currentValue": "",
  "text": "Angka di meter sekarang◆Salin kotak hitam saja◆Masuk akal — selisih {delta} m³ dari {prev}◆Lonjakan jauh — {delta} m³◆Angka lebih kecil dari {prev}◆Perbaiki dulu◆◆Kurang {n} angka"
}
```

> **Always author `currentValue` (even as `""`).** With the key absent entirely, `getInitialValue` (`lib/init_values.dart`) seeds the slot with the literal string `"null"` — `null.toString()` is `"null"`, which passes `.trim().isNotEmpty`. The pad overwrites that the moment it paints (`digitPadNormalizeSeed` catches `'null'`), but `AnyPage` renders through a lazy `ListView.builder`: a pad below the fold that the officer never scrolls to never runs its build, so the slot would submit the string `null` as the meter reading. This is a repo-wide trap for every field type, not specific to this widget — authoring `currentValue` closes it.

> **`search` matches the `meter` doc by `lk`, not `li`** (spec rev 2026-08-19b). A `meter` doc is keyed `lk` = `{li}-{sv}`; `li` alone is shared across sites, so `li◼{li}` can return more than one doc and pick the wrong meter. The widget parses neither token — `search` goes RAW to `filterDriverHomeDocs`, which resolves any `{key}` from the **bare screenTx keys the previous (scanner) page wrote via `routeParams`**. So that page must publish `lk`. If it does not, `{lk}` stays literal and `filterByMultiClause` fails **closed** (`value.contains('{')` → empty list): zero docs, zero `pv`, **zero verdict, silently, on every reading** — visually identical to the legitimate "`meter` doc does not exist yet" case in `MeterSurvey`.

## State / Bloc / Dependencies

- **No new state store.** All per-field state lives in the existing `txfController[scrName][position]` `InputController`. No Redux `#KEY`, no bloc, no GetX controller, no additions to `global.dart` / `global2.dart`. **Two** `ScreenSession` entries exist, both `static` maps on the widget class keyed by `scrName` and both `nav:screen, rebuild:none`: `DigitPad.sheetRaised` (the raise-once latch, rev e) and `DigitPad.serialMemo` (the OCR verdict memo, r2 — see the two bullets below).
- **Repository:** `subscribeToMapCollection` (`firestore_repository/table_repository.dart`) → `mapTableContent[_code]`, filtered by `filterDriverHomeDocs`.
- **Rebuild triggers:** `GetBuilder<WidgetUpdateController>(id: '$scrName-$position')` (for `clearData` / `isEnabled`), an inner `Obx` on `mapTableContent`, and a `TextEditingController` listener on the `digitsPosition` slot.
- ⚠️ **Config constraint — `digitsPosition`, `digitsRedPosition` and `digitsSourcePosition` are WIDGET-OWNED OUTPUT slots (rev d).** This widget writes all three, always: from config as much as from the picker, because the CF needs them to make the point's configuration permanent (§2.2 rule 1). **No other input widget may be pointed at them** — a second writer would fight the latch and could resurrect a count the officer just overrode. This replaces rev b's constraint that the `digitsPosition` source must write `controller.text`; the `TextEditingController` listener that rule existed for has been removed, because nothing external writes those slots any more.
- **The count LATCHES: whichever source resolves first wins.** `digitPadResolveCount` reads the slot first and the `meter` doc second (unchanged since rev b). Because the widget now writes the slot, the first resolved value becomes the source of truth and a doc landing late only seeds a slot that is still empty. That is deliberate: a late doc arrival must never make the boxes jump and silently wipe a partly typed reading.
- **Changing the pick EMPTIES the buffer, it does not truncate it** (§2.2 rule 4). A right-truncated number still looks like a valid number, which is precisely the failure mode this widget exists to prevent.
- **The picker stays on screen after the first pick.** Picking the black count *resolves* the count, which would otherwise flip the picker straight from "forced" to "hidden" and leave the red row unreachable — acceptance §11's "Setelah memilih 5+2" could never be satisfied in `auto` mode. So a chip tap latches the picker open. In `editable` mode the segment-10 link toggles it back off; after a forced pick it stays visible until navigation. That is deliberate: it also lets a mis-tap be corrected, and a wrong count is a 10×–100× billing error (§2.1).
- **The provenance latch has one deliberate bypass.** `digitPadResolveSource` never overwrites a slot that already holds `config` or `field` — otherwise a doc landing after the officer picked would relabel his pick as `config`, and (worse) a doc-seeded count would flip to `field` on build 2, because from then on the count is read back from the slot. The **picker tap** writes `field` directly, bypassing that latch: in `editable` mode the slot already says `config`, and without the bypass the office would never see the one row that needs review.
- **⚠️ No pickable options ⇒ no picker and no gate.** Spec §7 item 7 kills the submit button on an unfilled picker, but that only applies when the picker can actually be filled. With `digitsOptions` empty the widget resolves nothing and never disables the page's submit button — but it does **not** render nothing: it prints the `--DIGIT_PAD-- Error: no digit count …` marker (see the cross-slot note below for why silence cost a field trip). **One exception, added after code-review r1:** a configured `table` + `digitsField` that is still waiting for its FIRST snapshot — no `mapTableContent` entry exists for the widget's `_code` yet — renders nothing, because that state is *loading*, not broken config (spec rev f §12; spec (5).md:186 calls a not-yet-existing `meter` doc correct behaviour). Without it the marker fired on every cold entry of the widget's primary config shape. `finalData` is still cleared and the submit gate still lifted on that path. The discriminator is key **presence**, not an empty doc list: a snapshot that landed carrying no doc still shows the marker. Accepted trade: a table-backed config whose doc never arrives at all stays silent. **⚠️ Offline is NOT covered** (code-review r2 / W3): `main.dart:63-64` sets `persistenceEnabled:true`, so offline the listener still fires once from cache and `table_repository.dart:2180` writes the key regardless — an empty **cached** result is indistinguishable from a server-confirmed absent doc, so a first-ever offline visit to a meter whose doc was never cached still shows the marker. Telling them apart needs `snapshot.metadata.isFromCache` plumbed through `subscribeToMapCollection`, a shared-repository change and outside this widget. One bad sheet cell must not lock a field officer out of the page (product #17 "the officer always wins", §7.5 "nol pembanding = diam, bukan error").
- **⚠️ And no place to STORE the pick ⇒ likewise no picker and no gate** (`canPersist`). `digitsPosition` blank, unparseable, or equal to the pad's own `position` are the three positions the cross-slot writer refuses. Without this rule the picker would render, the gate would engage, and every chip tap would be silently swallowed — and because the gate deliberately keeps no memo of what it applied (see below), it would re-assert on every build forever, leaving the officer with a dead save button and no way out of the page. Same failure class as the empty-options case, same answer: **render the marker, gate nothing.**
- **⚠️ A DISABLED pad never engages the submit gate at all** — `_scheduleGate(block && enabled)`. Neither reason survives `isEnabled:"FALSE"`, because neither can be *cleared* from a pad whose inputs are inert: with the pad disabled every numpad key, the backspace, every digit box and both chip rows lose their `onTap`. So the officer can neither pick a count nor retype the digit that is blocking him, and with no gate memo (see below) the block re-asserts on every build — permanent, not transient, and it takes the whole page down with it (the photos, the GPS and every other field become unsubmittable too). Two reachable shapes: `isEnabled:"FALSE"` + `digitsOptions` set + no resolvable count (a `forced` picker with inert chips — new in rev d), and `isEnabled:"FALSE"` + a seeded backward reading + `blockOnBackward:"TRUE"` (inert keys and boxes — present since rev b). Same doctrine as `canPersist` and product #17: fail open.
  **This could not have been left to a config rule.** `isEnabled` is not only a config cell: `clearData` restores it from `initialIsEnabled` on navigation, and an RBT `run:"N:disable"` action can flip it at runtime — so "do not ship a `DIGIT_PAD` disabled" would have been a constraint the sheet author cannot actually honour. The guard has to live at the gate.
  **And not only the gate — the verdict-block UI goes with it.** `verdictBlock` carries the same `&& enabled` term *at its definition*, so on a disabled pad there is **no segment-5 footer on the card, no segment-5 blocked-foot in the sheet, and the segment-13 acknowledge button stays available**. Without that, the sheet would rise demanding "perbaiki dulu", suppress the one button that dismisses it, and repeat the demand in the card footer — while the save button was alive anyway. A "you are blocked" message the officer cannot act on is worse than no message. The verdict **sheet itself still rises** on a disabled pad, and that is deliberate: a read-only pad should still surface "this reading looks wrong"; it just no longer pretends to be a gate.
  **⚠️ Config consequence — a review page that wants a hard stop on backward readings must ship the pad ENABLED.** A disabled `DIGIT_PAD` no longer enforces `blockOnBackward` at all: no gate, no footer, no suppression. If the intent is "the officer may look but not edit, and must not submit a backward reading", `isEnabled:"FALSE"` will not deliver it — the pad must be enabled (or the stop enforced elsewhere on the page).
- **The red chip row needs `digitsRedPosition` too.** It is hidden when that slot is absent, for the same reason: `_pickRed` goes through the same writer, so the chips would absorb taps, do nothing, and never highlight. The red count then falls to `0`, which is a complete configuration (the Kawasan Ruko shape), not a broken one.
- **The picker's chip highlight lags by one frame in `editable` mode.** `currentBlack` reads the `digitsPosition` slot only, and on the first frame the picker opens over doc-sourced config that slot may not have been written yet (the write is post-frame). No chip highlights until the next frame, then it settles. Cosmetic, and preferred to reading the doc a second time inside `_picker` just to pre-empt one frame.
- **The verdict sheet raises at most once per reason, and the TWO reasons are remembered INDEPENDENTLY.** `DigitPad._sheetRaised` (a `static Map<String, Map<int, String>>` keyed per screen, registered with `ScreenSession` as `DigitPad.sheetRaised` at `nav:screen, rebuild:none`) holds one composite entry per position, `'<numeric half>|<serial half>'`, and each half is compared against its own half (`digitPadSheetKeyNumeric` / `digitPadSheetKeySerial`, `digitPadNextSheetLatch`). It is a `static` and not a State field on purpose: `AnyPage` renders through a `ListView.builder` with no keep-alive and `buildPage(clear:true)` re-mints `linkElement[scrName]` on a background `readSettings` refresh — both destroy the State, and a State-local latch would let the sheet pop back up unprompted (the exact failure §4c rule 3 prevents).
  - The **numeric** half re-arms the moment the buffer goes incomplete, exactly as rev e did by dropping the entry — which is what makes segment 12 and `clearData`-on-navigation re-arm the raise with no extra hook. An entry empty on **both** halves is removed, so `''` remains the single re-arm signal.
  - The **serial** half is **sticky**: it changes only when the photo does (§7.7), and survives a numeric sheet taking its turn.
  - **⚠️ Do not fold the two comparisons back into one** (code-review r2 / W1, confirmed at runtime). Comparing the composite whole meant any change on either axis wiped the other's memory: with a mismatch live, every complete↔incomplete transition of the digit buffer minted a new key and re-raised the **serial** sheet — five modal sheets for one mismatch, so correcting a single digit cost two of them. §12 says a mismatch is common (an unreadable photo reads as one), which makes that the normal path, and it manufactures precisely the habit §4c rule 1 exists to prevent.
- **The comma is the one glyph that does not come from a `text` segment.** It is structural, like the digit boxes themselves: §2.1 makes the m³ boundary the number-one risk in the feature, because a wrong boundary makes every unit in a site fail in the same direction and therefore look normal.
- **The sheet closes through the BUILDER's `ctx`**, never the State's captured `context`. A captured-context pop is a documented fatal here (`Null check operator used on a null value`, `_InkResponseState.handleTap`). Precedent copied from `list_action_card.dart`'s `_showNoteSheet`.
- **Side effects:** writes `controller.text` + `finalData` on its own slot; writes `isEnabled` on savesend slots (post-frame only).

### The two-slot storage contract

| Value | Lives in | Example (N=5, user typed `0 0 9 8 7`) |
|---|---|---|
| **Display buffer** — one char per box, `_` = empty box | `InputController.controller.text` | `"00987"`, partial `"01_2_"` |
| **Submitted value** — leading zeros stripped, `''` while incomplete | `InputController.finalData` | `"987"`, partial `""` |

`clearData` (`api.dart`) resets `controller.text`, `finalData` **and** `isEnabled` per slot on navigation, and its tail repaints every `'$scrName-$position'` id — so the digit buffer, the submitted value and the submit gate all reset for free when the officer leaves the page.

## Important Behavior

- **No `TextField` / `TextFormField` / `EditableText` anywhere in the tree.** That is the only way spec §11's "the system keyboard never appears / there is no way to enter a comma, dot or minus" is *structurally* guaranteed instead of validated. A widget test asserts this. Do not add one "for convenience".
- **The verdict FAILS OPEN.** Product #17 and spec §7.5 ("nol pembanding ⇒ diam"): a throw, a missing doc, or an unreadable comparator must leave the submit button **alive**. This is the deliberate opposite of the usual permission-gate rule in this repo — it is not a fail-open defect.
- **A spike never blocks** (spec §10: leaks are real and must be reported). Only `backward` **and** `blockOnBackward:"TRUE"` blocks.
- **`avg <= 0` behaves like a blank `avgField`** (documented deviation). A CF-computed `avg: 0` means "no history yet"; taking §7.5 literally there would flag *every* reading as a spike, which spec §12 names as the failure that trains officers to ignore warnings — killing the backward verdict too.
- **`{prev}` renders the raw stored value**, not the zero-padded/grouped `01 234` form the §4b sketch draws. §3.1 defines `{prev}` as a value, not a format; no formatter was specified.
- **Box count is capped at `digitPadMaxBoxes` (12).** Input validation at a trust boundary: a bad sheet cell (`dg: 500`) must not try to paint 500 boxes.
- **The submit gate is DETECTED, not configured.** There is no param naming the submit button. The widget scans `screenUIComponent[scrName]['children']` for `type: 'rbt'` components and disables every child whose **singular** `action` is `savesend` **and that carries a `position`**. `actions` (plural) is the approval-chain field and is never read here. **A positionless savesend button cannot be gated** — the RBT builds it as a static button outside any `GetBuilder`, so its `isEnabled` is unreachable. Re-enable restores `initialIsEnabled`, not a hardcoded `true`, so a button the page config ships disabled stays disabled.
- **★ `finalData` is rewritten on EVERY build, unconditionally — and that is load-bearing.** Because the refit is derived per build and persisted only by `_apply`, `controller.text` may legitimately disagree with what is on screen. That is safe **only** because `finalData` is rewritten unconditionally every build. The two facts are one contract: anyone who later makes the `finalData` write conditional — "only when it changed", "only on tap" — re-opens the `saveSend` record-composer fallback (`api.dart`: when `finalData == emptyString` the composer submits `controller.text` instead) and turns the stale hole-buffer `01_2_` into a submitted meter reading. `txfControllerCheck` creates every slot with `finalData = '--'`, so that sentinel is the birth state, not an edge case. Note this is the **opposite** of `ocr_capture`, whose `ocrNormalizeSeed` deliberately preserves `'--'` because that widget *wants* the fallback.
- **⚠️ `digitsPosition` is an OUTPUT slot — never point it at another widget** (spec rev 2026-08-20f §12, proven in the field 2026-08-20). Config once aimed it at a `SELECTABLE_BTN` slot on the same page; the officer picked `5` and the widget never rendered at all. Two independent reasons, neither fixable from config: `selectable_btn` does write **both** slot halves (`selectable_btn.dart:166-167`, since `efe578b`), so its `controller.text` assignment does notify listeners — but rev d deleted the listener this widget used to keep on that slot, and its `GetBuilder` is keyed to its **own** `'$scrName-$position'` id (`digit_pad.dart:463`), so the pick can never reach a rebuild; and the first (and only) build sees an empty slot. What is dead is not cross-widget slot reads *in general* — it is a slot fed by a writer that signals nothing. `otq_dropdown_2.dart:203-208` records the split: `ocrWriteToPosition`, `otq_get_images_2` and the RBT `run:` actions (`ftz_row_of_button_2.dart:655-656`, a call split across two lines and therefore missed by a one-line grep) write **both** halves of the slot pair — `finalData` *and* `controller.text`, whose assignment notifies listeners by itself — or repaint the target id outright, while `otq_rdo_2` and `group_picker` write `finalData` alone and leave any reader non-reactive. This repro therefore pre-judges nothing about `photoPosition` reading `getImages1`: `otq_get_images_2` is named there as a writer that already sets both halves — **verify it before building §7.8.** The slot read that remains (`digit_pad.dart:490`) is this widget reading **its own** previous write back, which is what latches the count across a navigation that discards State.

- **Growing the box count back resurrects truncated digits.** `5 → 3` displays `123` while the slot still holds `12345`, so `3 → 5` brings `45` back. Spec §11 mandates only the shrink direction, and the window is narrow: any tap after the shrink persists the 3-char buffer and closes it permanently. Nothing is lost silently — the boxes always render exactly what `finalData` will submit. Known and accepted; the alternative (writing the refit back during `build()`) is a notify-during-build hazard.
- **The serial verdict memo OUTLIVES the State, on purpose.** The OCR key and its answer live in `DigitPad._serialMemo` (`static Map<String, Map<int, _DigitPadSerialMemo>>`, registered as `DigitPad.serialMemo` at `nav:screen, rebuild:none`), not on `DigitPadState`. While they were State fields (code-review r2 / W2) a scroll away and back re-ran **ML Kit** on every return — a fresh native recogniser each time, and with `blockOnSerialMismatch:"TRUE"` the savesend button re-enabled for the whole in-flight window — and briefly collapsed the sheet key to `''`, whose re-arm branch deleted the latch and let the dismissed sheet rise again. Both fields live in ONE object so the verdict can never drift away from the key it was computed for.
- **⚠️ The memo holds ANSWERS ONLY — never "a read is in flight"** (code-review r2 / W4). r2 claimed the key *before* the ML Kit round-trip and wrote the answer *after* it, so a pass abandoned in between — the officer scrolls away, or ML Kit throws — left a claimed key with **no answer** behind it in a `static` map. Every later pass then returned at that guard, and the check went silently dead for that photo: no sheet, no gate, no log, until a new photo or a navigation. With `blockOnSerialMismatch:"TRUE"` that is a gate that never engages and says nothing. Three rules keep it shut, and they are one design, not three patches: what is **in flight** is a per-State field (`_dispatchedOcrKey`) that dies with its State; the answer is recorded **before** the `mounted` check, so a pass abandoned by a scroll still delivers the verdict it already computed; and a **dead** State never overwrites an entry holding a *different* key, because a newer State has answered for a newer photo since. **Never put an `inFlight` flag in the memo** — a State that dies with it set reproduces the wedge exactly. And never write one half of an entry: nulling `match` while leaving `ocrKey` set is the same defect wearing a different hat.
- **The caret is not durable.** `_cursor` is State-local and `AnyPage`'s list has no keep-alive, so scrolling the pad off-screen and back returns the caret to box 0. The typed digits survive — they live in `controller.text`, not in element state.
- **Shrinking the count drops boxes from the RIGHT** (spec §11), and tapping a box beyond the filled prefix is honoured — holes are a supported buffer state.
- **The gate re-asserts on every build; it does not memoise what it already applied.** `isEnabled` is one flag with several writers, and one of them is ambient: `buildDisplayComponent`'s `rbt` else-branch rewrites every positioned RBT child's `isEnabled` (and `initialIsEnabled`) straight from config with no `isFieldUntouched`-style guard, and `constructAllPageElements` runs that for every screen on any server UI push. A form page is not repainted by `rePaintScreen` (home-only), so the widget's State survives that reset. A gate that remembered "I already blocked" would therefore never re-assert and the only blocking path in the system would un-latch silently. Re-asserting per build is cheap: `_applyGate` diffs against the observed `isEnabled` and repaints only when something actually changed.
- **★ Config constraint — on a page with a `DIGIT_PAD`, this widget OWNS the savesend `isEnabled` flag in BOTH directions.** An RBT `run:"N:disable"` action writes the same flag, and within a frame last writer wins — but this widget re-asserts on every build, so it re-wins on its next rebuild *whatever its verdict is*. Blocking is not the only direction: with a sane verdict `_applyGate` writes `next = ic.initialIsEnabled` (normally `true`) over whatever it finds, so a savesend button some other action deliberately disabled is **re-enabled**. Do not combine `run:"N:disable"` on a savesend button with a `DIGIT_PAD` on the same page — the pad will undo it. Config that ships the button disabled is still honoured, because that path sets `initialIsEnabled` from config too.
- **Two `DIGIT_PAD`s on one screen fight over the same savesend flag** — each gates the same positions from its own verdict, so the last to transition wins. Spec §10 already forbids that layout (one meter per widget, one page per point); it is a **config constraint**, not a supported configuration. Do not add a "who owns the gate" registry for it.
- **Test contract:** numpad keys carry `ValueKey('digitPadKey-<0-9|back>')` and boxes carry `ValueKey('digitPadBox-<i>')`. These are not decoration — without them a text finder cannot tell a filled box from the numpad key showing the same digit (both are `Container > … > Text('0')`, and the boxes come first in tree order), and the icon-only backspace key is unaddressable entirely. Do not remove or rename them.

### The serial-number check (meter-serial-verify, 2026-08-25)

`serialField` names a field on the `meter` doc (`msn`). When it is filled, ML Kit Latin OCRs the photo(s) in the `photoPosition` slot and looks for that serial inside the recognised text. Not found ⇒ the existing bottom sheet rises with segment 6. **§7.8 (OCR reads the digits and compares them to what the officer typed) is CANCELLED** — a typo is already caught twice, more cheaply, by the backward and spike verdicts; what nothing guarded was an officer standing at the **wrong meter**.

- **Matching rule (spec §3.1, do not improvise).** Uppercase both sides, drop every character that is not `A-Z` or `0-9`, then ask whether the OCR text **contains** the serial. Substring, not equality — a real photo also carries the brand, an SNI mark and a burned-in watermark. **Zero fuzzy match, zero similarity threshold.** A check loosened until it always passes is worse than no check: officers learn to dismiss the sheet unread, and the backward verdict dies with it.
- **Total silence, ZERO ML Kit calls, when any of these holds:** `serialField` blank · the doc's value blank/absent/punctuation-only · `photoPosition` blank, unparseable, or equal to the pad's own `position` · no `aum__…__mua` path in the slot. Each is a `return` **before** the OCR call, and a widget test counts the calls. The **last** one is the only branch that `devPrint`s (code-review r2 / I1): the first three mean the check was never requested, but a slot that holds an https URL or `emptyImageUrl` means it WAS requested and cannot run — in the field the two are otherwise indistinguishable.
- **Multi-photo: every photo is OCR'd separately; a match on ANY one is a match.** The texts are never concatenated — a serial straddling two photos' texts would otherwise read as a false match.
- **The photo slot must be a LOCAL path.** `otq_get_images_2` writes `aum__<absolute path>__mua` entries joined by `separator[5]` (`◇`). An https Storage URL (what an edit page seeds from `currentValue`) is dropped, not attempted: `InputImage.fromFilePath` cannot open one.
- **⚠️ It FAILS OPEN, deliberately.** Any throw — missing file, `MissingPluginException`, ML Kit model resolution failure — leaves the verdict *unknown*: no sheet, no gate, one `devPrint`. This is spec §10 ("blokir waktu OCR gagal baca apa pun" is Not Doing) plus product #17, and it is the deliberate opposite of the repo's usual fail-closed gate rule. **Retry semantics — one attempt per key per State lifetime.** The throw leaves the memo untouched, so nothing durable blocks a later attempt; `_dispatchedOcrKey` is what stops *this* State retrying, and it is load-bearing: `_applySerial` runs from a post-frame pass on **every** build, so on a build with no ML Kit plugin (every pass throws, the memo stays empty) dropping it means one native call **per keystroke**. A new State — a scroll back, a navigation — tries once more, which is right for the transient half of this branch (an ML Kit first-call model init) and costs one silent failure per State for the permanent half.
- **⚠️ Precedence: the NUMERIC verdict wins the sheet.** Segment 6 surfaces only when the verdict is `sane` or there is no reading yet. §12 concedes the substring rule cannot tell a wrong meter from an unreadable photo, so letting a mismatch mask a backward reading would kill the one check product #21 exists for.
- **The serial gets the SHEET only.** No card banner, no new render element, no new tappable row (spec §5). The inline banner still shows the numeric verdict and nothing else. Consequence: **a dismissed serial sheet comes back only when the PHOTO changes** (§7.7). Typing, backspacing and retyping the reading do not re-raise it — that was r2's W1 fix; the reading re-raises the **numeric** sheet only, exactly as rev e did.
- **⚠️ Consequence of "the sheet only": a dismissed serial mismatch can leave NOTHING on screen.** The tappable compact row (`digitPadVerdictRow`) is rendered only for `spike`/`backward`, and with no reading typed the numeric verdict is `none`, so no banner renders at all. Measured, not assumed. The officer's remaining signals are the save button (with `blockOnSerialMismatch:"TRUE"`) and retaking the photo. Adding a row would need a `text` segment and a spec change — §5 is explicit that this feature gets "nol elemen baru".

#### `photoPosition` reactivity — how the photo reaches this widget

`otq_get_images_2` writes **both** halves of the slot on every photo taken (`.controller.text` **and** `.finalData`; the call is split across two lines and is missed by a one-line `grep 'controller.text'`). But it repaints only its **own** position, and this widget's `GetBuilder` is keyed to its own id — so **a photo taken produces no rebuild here by itself**. This widget therefore keeps a `TextEditingController` listener on the `photoPosition` slot.

That is **not** a walk-back of rev d's removal of the `digitsPosition` listener. `digitsPosition` is a slot this widget **writes**, where a listener fires on its own post-frame write (a self-`setState` loop). `photoPosition` is an **input** slot this widget never writes. The one config shape that could recreate the loop — `photoPosition` equal to the pad's own `position` — is refused in `initState`.

Attachment happens from the `_scheduleSide` **post-frame** pass, never `initState`: the `getImages` component can sit anywhere in the page's `children`, so its `InputController` may not exist yet while this widget is building. By the end of the first frame every component is built. Detach holds the controller **by reference** (never a fresh map lookup), because `buildPage(clear:true)` re-mints `txfController[scrName]` and the map entry at `dispose()` time can be a different object.

The rebuild is deferred by one frame **only** during `SchedulerPhase.persistentCallbacks` — `otq_get_images_2` assigns `controller.text` from its own `initState`, which runs inside the build phase, and marking an already-built element dirty there is a `setState() called during build` assertion. Deferring *unconditionally* would be wrong: `addPostFrameCallback` appends to a list and does **not** schedule a frame, so an idle-phase write (the normal case — a tap callback) would be dropped.

#### ⚠️ Open debt and known risks

1. **0b is UNVERIFIED FIELD DEBT.** Nobody has opened 10 real "Foto Muka Meter" photos to confirm the serial is inside the frame and legible (spec §7 Langkah 0b, §12). The renderer shipped anyway because the feature is silent while `msn` is empty and the `msn` seed does not exist yet — so it ships **inert** and the retraction cost is one sheet cell (`serialField:""`), zero app releases. **Do this before the seed lands.**
2. **ML Kit's native side has NEVER been compiled in this repo.** Every green test is zero evidence about ML Kit at runtime. `flutter test` cannot reach it at all (MethodChannel ⇒ `MissingPluginException`), which is why `digitPadOcrRead` is a replaceable top-level seam.
3. **Offline OCR depends on the BUNDLED model and that is fragile.** `google_mlkit_text_recognition`'s `android/build.gradle` uses `implementation("com.google.mlkit:text-recognition:16.0.1")`, which ships `libmlkit_google_ocr_pipeline.so` in the APK. If a future version moves to `play-services-mlkit-text-recognition`, offline OCR dies **silently** — the check would simply start "mismatching" everything without connectivity.
4. **A mismatch cannot be told from an unreadable photo** (spec §12, the headline risk). If ML Kit misses the serial on, say, 40% of photos, officers are warned on 40% of **correct** readings — and within a month they press "Angkanya memang segitu" without reading, which kills the backward verdict too because it uses the same sheet. **Measure the hit rate; do not assume it.**
5. **⚠️ `blockOnSerialMismatch:"TRUE"` — the officer's only escape is retaking the photo, in a DIFFERENT widget.** There is no acknowledge button (segment 13 is suppressed) and no way to clear the block from this widget at all. If the page's `getImages` is absent or disabled, `TRUE` bricks the page. Spec §10 mandates `FALSE` for v1 for exactly this reason; flip it only after the hit rate is measured, and only on a page whose photo widget is enabled.
6. **The gate carries `&& enabled`, like the other two.** On a disabled pad no serial block is raised — the page is normally read-only there, so the retake that would clear it is not available either.

### Known spec gaps (rev 2026-08-20e)

1. **Segment 13 has no output wire.** §4c rule 4 says the secondary button stores the reading "apa adanya + tandai", but §3 and §5 define **no slot** for that mark. The button therefore closes the sheet and leaves the reading exactly as typed; nothing is flagged anywhere. Do not "fix" this by inventing a `flagPosition` or by overloading `digitsSourcePosition` — §2.2 rule 2 pins that slot's value set to exactly `config`/`field`, and both words already mean something else to the office report. Reopen with product.
2. **The sheet's "KAMU ISI / BULAN LALU" comparison chips are not rendered.** The §4c sketch draws them, but neither label has a `text` segment, and §7 item 9 plus the last §11 acceptance line forbid any hardcoded string. Both numbers already reach the officer through `{value}` and `{prev}` inside the verdict segment. Add the chips when the spec adds the segments.
3. **`{delta}` / `{value}` / `{prev}` / `{avg}` are in the meter's FINEST unit, not m³.** §2.1 makes storage the raw whole integer and says the `÷ 10^red` is display-only, and rev c states the comparison logic is untouched. With `dgm: 2`, `{delta}` therefore reads `3400`, not `34`. No token formatter was specified, so none was written: the sheet copy must say what unit it means. Reopen with product if the office wants m³ in the message.

## Test coverage — what is and is not verified

Two flat suites: `test/digit_pad_support_test.dart` (105 pure-function tests) and `test/digit_pad_widget_test.dart` (70 pump tests). Counts are measured by running the suites, not by grepping for `test(` — a `test("…")` with double quotes is invisible to that grep.

**Covered:** the buffer/refit/submit-value model, the keypress model, count resolution, the 3-tier verdict, token filling, the savesend scan, and — driven by seeding `mapTableContent['']`, which a table-less component reads with zero Firebase — the full comparator → verdict → banner → **submit gate** chain, including the gate actually disabling the savesend slot, restoring it to `initialIsEnabled`, leaving non-savesend siblings untouched, never blocking on a spike, and re-asserting after an external writer re-enables the button.

**Covered since r2 — SEQUENCES, which is the gap W1 and W2 slipped through.** Every test r1 added asserts a single state, and neither defect is visible in one: type → backspace → retype with a live mismatch (the sheet must rise **once**), a spike sheet between two serial states (the dismissed serial sheet must not re-open), and an unmount/re-pump State re-creation (no re-raise, and `ocrCalls` must not increment). Plus the two shapes that reach `paths.isEmpty` — an https Storage URL and `emptyImageUrl` — each asserting zero ML Kit calls, no sheet and a live save button under `blockOnSerialMismatch:"TRUE"`.

**Covered since r3 — what happens INSIDE the ML Kit round-trip.** The r2 sequence tests all let the OCR *complete* before disturbing the pad, which is why none of them could see W4. The r3 tests hold the `digitPadOcrRead` seam open with a `Completer` (per photo path, so a test can also choose which of two in-flight reads answers first) and then act while the read is still out: a State destroyed mid-read still records its verdict and the next mount raises the sheet and kills savesend; a mid-read **throw** leaves the memo re-armable, so the next mount reads again; a build with no plugin reads **once**, not once per keystroke; a dead State never overwrites a newer State's verdict; an older read answering last never overwrites the newer one; and a photo that leaves the slot and comes back finds its verdict still there. Every one of them is killed by a named mutation — see the plan's §6.4.

**NOT covered, by construction:** the real Firestore subscription (`subscribeToMapCollection` is never reached — the test components carry no `table` key, which is what keeps Firebase uninitialised), `search` resolution through `filterDriverHomeDocs`, and the real `meter` document's shape and field types (still unratified). Those remain device work — see the manual flow in the plan's §7.3.

## See Also

- [ocr_capture.md](ocr_capture.md) — the inverted-direction sibling (OCR fills, human checks). This widget's serial check is the third direction: OCR neither fills nor is filled, it only **verifies identity**. `ocrFlattenElements` lives in `ocr_capture.dart` rather than its support file so an ML Kit failure cannot take `photo_camera.dart` down with it; this widget follows the same rule — the ML Kit call is in `digit_pad.dart`, and `digit_pad_support.dart` imports **no** ML Kit
- [otq_dropdown_2.md](otq_dropdown_2.md) — the usual `digitsPosition` source; its slot-write now sets `controller.text` as well as `finalData`, which is what makes the box count react to a pick
