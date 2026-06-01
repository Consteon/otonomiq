# addToEvent — Implementation Design

**Date:** 2026-06-01
**Status:** Draft for review
**Source spec:** `~/Downloads/addToEvent-flutter-dev-spec (1).md` (v0.2)
**Grounded in:** existing `addToTable` pipeline in this repo (not the spec's idealized flow)

---

## 1. Goal

Add `addToEvent`: a **keyed sibling** of `addToTable`. When a component JSON contains an
`addToEvent` string, the submit ALSO writes the event as a **keyed document into a named
Firestore collection** — *in addition to* the existing spreadsheet Event-tab row.

**Additive, not a replacement.** The current event write (`appendToSheet` → Submit bloc →
spreadsheet Event tab cols A/B/C) is unchanged. `addToEvent` only adds a Firestore write.

---

## 2. Key facts established from the codebase (reconcile vs spec)

The source spec describes an idealized "resolve-at-submit, write-immediately" flow. The real
codebase differs; this design follows the **real** `addToTable` mechanism so the two stay
consistent.

1. **One pipeline, timing depends on connectivity.** `addToTable` is not "submit vs sync" — it
   rides the offline-first history queue. `saveSend` carries the DSL string as `tb`; on submit a
   sync is attempted — online ⇒ writes immediately, offline ⇒ deferred to next `historySync`.
   `addToEvent` rides the same queue.
2. **Token resolution is split across two times:**
   - **Submit-time pre-pass** (`saveSend` api.dart:3621-3627): `autheniumDecode` → `replacePlaceholders` (`{{POS(n)}}`/`{{DOC(n)}}`) → `_resolveScreenTxMarkers` (`<screenTxKey>`, incl. `<no_request>`).
   - **Sync-time** (`parseTableInput` table_repository.dart:1100): `◀N▶` (system/`ref[0]`), `◁N▷` (form/`ref[1]`), `<N>` field index, `|T7|format`. `ref` is rebuilt from the carried event row by `parseEventString` (table_repository.dart:1077).
3. **`<no_request>` is a screenTx key**, not a string literal generator. Resolved at submit by `_resolveScreenTxMarkers`. The real ref id is the request row's column-1 value, written into screenTx by `list_item_card.dart` on card tap/action. `addToEvent` reuses this unchanged.
4. **Separators (exact codeUnits):** `⬤`=`separator[0]` (U+2B24), `◆`=`separator[1]` (U+25C6), `◼`=`separator[2]` (U+25FC), `★`=`separator[3]` (U+2605), `⭘`=`separator[8]` (U+2B58). `addToEvent` uses `⭘` (field sep), `◼` (key/value sep), `◆` (multi-doc sep).

---

## 3. Architecture & data flow

```
[component JSON has "addToEvent"]
        │  (parallel to "addToTable")
        ▼
saveSend()  api.dart:3530        ftz_checker checkerSaveData()  ftz_checker.dart:342
        │  submit-time pre-pass (decode + replacePlaceholders + screenTxMarkers)
        │  on the addToEvent string
        ▼
   eventString  (still a template for ◀▶/◁▷ tokens)
        │
        ▼  carried as a NEW 4th segment of tb:
   tb = addStr ⬤ updateStr ⬤ deleteStr ⬤ eventStr
        │
        ▼  appendToSheet → Submit.tb → history index 14   (UNCHANGED carry path)
        ▼
historySync()  table_repository.dart:2442
        │  split tb by ⬤ → [add, update, delete, event]
        │  eventRowString = json([t, p, c])     (same as table writes)
        ▼
   if eventStr not empty → writeToEvent(eventStr, eventRowString)   ◄── NEW
        │
        ▼  for each ◆-block:
        │    parseAddToEvent → keyed Map           ◄── NEW parser
        │    resolve ◀▶/◁▷/<N>/|T7| per value using ref=parseEventString(eventRow)
        │    blank-prefill canonical codes, overwrite present keys
        ▼  WriteBatch (atomic): collection(<line1>).add(doc) per block
   Firestore
```

The spreadsheet Event row (A/B/C) is still produced by the existing `appendToSheet` path and is
untouched.

---

## 4. Components (units, each one purpose)

### 4.1 `parseAddToEvent(String body) → Map<String,dynamic>` — new, in `table_repository.dart`
- Input: a single decoded event block (one `◆`-segment), token-resolution already applied to values by the caller (see 4.2), OR raw + a resolver callback. **Decision: parser does structure only; token resolution is a separate pass** (mirrors `parseTableInput` separation).
- Split body by `⭘` (`separator[8]`); trim; drop empties.
- First part = collection name → `result['_collection']`.
- Remaining parts: split at first `◼` (`separator[2]`) → `key`, `rawValue`. Store `result[key] = rawValue`.
- Malformed part (no `◼`) → skip silently.
- Unknown char-codes pass through unchanged (forward-compatible). No validation, no throw.

### 4.2 Token resolution for values — reuse existing primitives
- For each `result[key]` value, run the SAME resolution `parseTableInput` applies to a field value:
  `◀N▶`→`ref[0][N-1]`, `◁N▷`→`ref[1][N-1]`, `◁%N▷`→`getDocumentName(ref[1][N-1])`, `|T7|format` via `parseField`+`stringFormat`.
- Extract a small shared helper `resolveValueTokens(String, ref)` from `parseTableInput`'s per-value logic so both table and event paths call it (no duplication). `ref` comes from `parseEventString(eventRow)`.

### 4.3 `writeToEvent(String inp, String eventRowString)` — new, in `table_repository.dart`
- Mirror the shape of `writeToTable` (table_repository.dart:695): `eventRow = jsonDecode(eventRowString)`; `ref = parseEventString(eventRow)`; `decoded = autheniumDecode(inp)`.
- Split `decoded` by `◆` (`separator[1]`) → blocks.
- For each block: `map = parseAddToEvent(block)`; resolve each value via `resolveValueTokens(v, ref)`; build `fullDoc = { for code in canonicalEventCodes: '', ...map }` minus `_collection`; collect `(collectionName, fullDoc)`.
- Write all blocks in one `WriteBatch` (atomic). On any failure: do not commit, surface one error (leave nothing half-written). Mirror existing error/lock handling used by `writeToTable`.

### 4.4 `canonicalEventCodes` — new const list (global2.dart or table_repository.dart)
- The dictionary char-codes from spec §4: `r, fc, tablevid, ty, t, ts, ln, lq, i, d, cv, cn, av, an, sv, sn, cl, rf, tv, tn, st, nm, ll, VID, n, ci, co, is, os, ta`.
- `et, p, ev, ld` are **excluded** (those are the spreadsheet Event columns, not Firestore doc fields).
- Used only at the write boundary for blank-prefill.

### 4.5 Submit-handler hook — `saveSend` (api.dart) + `checkerSaveData` (ftz_checker.dart)
- Read `component['addToEvent']`; if non-empty: `autheniumDecode` → `replacePlaceholders(.., ref)` → `_resolveScreenTxMarkers`. Append to `tb` as the 4th `⬤` segment.
- When `addToEvent` is absent, behavior is byte-identical to today (segment empty).

### 4.6 `historySync` dispatcher (table_repository.dart:2442)
- Extend the `tbParts` split to read a 4th element; if present and non-empty → `writeToEvent(eventStr, eventRowString)`. Backward compatible: old 3-segment history (no 4th part) skips the event write.

---

## 5. Output shape (sample)

DSL (`component['addToEvent']`, after decode):
```
vtl.event-report-incident⭘r◼4320⭘ty◼report-incident⭘t◼◀2▶⭘cv◼87544551624342⭘d◼◁3▷⭘i◼◁5▷⭘rf◼<no_request>
```
With form `{3:"Lift macet di lantai 4", 5:"https://.../img.jpg"}`, `<no_request>`→ resolved at submit:
```dart
{
  "_collection": "vtl.event-report-incident",   // stripped before write
  "r":"4320","ty":"report-incident","t":1780275650000,
  "cv":"87544551624342","d":"Lift macet di lantai 4","i":"https://.../img.jpg",
  "rf":"<resolved-ref-id>",
  // blank-prefilled dictionary keys:
  "fc":"","tablevid":"","ts":"","ln":"","lq":"","cn":"","av":"","an":"","sv":"","sn":"","cl":"", ...
}
```
Written: `firestore.collection("vtl.event-report-incident").add(doc)` (auto-id).

---

## 6. Error handling

- Parser never throws (malformed parts skipped, unknown codes pass through, missing keys allowed).
- `writeToEvent` reuses `writeToTable`'s lock + try/catch + `errorReport` pattern.
- Multi-doc: `WriteBatch` — all-or-nothing per submit.
- Offline: stays in history queue; retried by `historySync` like table writes. Failure does not drop the event row from the spreadsheet path (independent).

---

## 7. Testing

Unit (`test/fixtures/addToEvent/`):
| # | Case | Assert |
|---|------|--------|
| 1 | Minimal sparse (`r,ty,t,ts`) | Map 4 keys + `_collection`; blanks filled at write boundary |
| 2 | Full report-incident (§5) | matches expected Map |
| 3 | Multi-doc `◆` | 2 docs, one atomic batch |
| 4 | Unknown code `⭘xx◼hi` | `xx:"hi"`, no throw |
| 5 | Missing form field `◁3▷` | `d:""` |
| 6 | `◀2▶` / `◁5▷` / `\|T7\|fmt` | resolves via ref (same as `parseTableInput`) |
| 7 | `<no_request>` present | replaced by screenTx value at submit |
| 8 | No `addToEvent` in JSON | tb 4th segment empty; zero behavior change |

Resolution tests should assert `resolveValueTokens` parity with `parseTableInput` on identical inputs.

---

## 8. Out of scope

- `et/p/ev/ld` generation (spreadsheet path, already exists).
- `ld` transform (op1-sheet formula).
- Type coercion (`t` stays string; spec open-Q deferred).
- Sheets↔Firestore atomicity across the two stores (spec open-Q; independent failures accepted).
- Dictionary versioning.

---

## 9. Files touched

| File | Change |
|------|--------|
| `lib/api.dart` | `saveSend`: build `addToEvent` segment, append to `tb` |
| `lib/widget/ftz_checker.dart` | `checkerSaveData`: same segment append |
| `lib/firestore_repository/table_repository.dart` | new `parseAddToEvent`, `writeToEvent`, `resolveValueTokens` (extracted from `parseTableInput`); extend `historySync` split |
| `lib/global2.dart` (or table_repository) | `canonicalEventCodes` const |
| `test/fixtures/addToEvent/` + tests | vectors above |
| `docs/firestore/` | short addToEvent op doc (mirror existing pattern) |
