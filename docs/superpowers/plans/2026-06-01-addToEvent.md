# addToEvent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a component JSON contains an `addToEvent` string, additionally write the event as a keyed document into a named Firestore collection (the existing spreadsheet Event row is unchanged).

**Architecture:** `addToEvent` rides the existing offline-first history queue as a 4th `⬤`-segment of the `tb` field (`add⬤update⬤delete⬤event`). At `historySync`, the event segment is parsed (keyed `⭘`→`◼`→Map), its values are token-resolved with the SAME logic as `addToTable` (extracted into a shared `resolveValueTokens`), blank-prefilled, and batch-written to `collection(<line1>)`.

**Tech Stack:** Dart/Flutter, cloud_firestore, existing `table_repository.dart` pipeline. Tests via `flutter test`.

**Reference design:** `docs/superpowers/specs/2026-06-01-addToEvent-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `lib/firestore_repository/add_to_event.dart` (NEW) | Pure, Firebase-free: `canonicalEventCodes`, `parseAddToEvent`, `fillEventBlanks` |
| `lib/firestore_repository/table_repository.dart` (MOD) | `resolveValueTokens` (extracted from `parseTableInput`), `writeToEvent`, `historySync` dispatch |
| `lib/api.dart` (MOD) | `saveSend`: build & append the event `tb` segment |
| `lib/widget/ftz_checker.dart` (MOD) | `checkerSaveData`: append the event segment |
| `test/add_to_event_test.dart` (NEW) | Unit tests for the pure parser/fill |
| `test/resolve_value_tokens_test.dart` (NEW) | Parity tests for the extracted resolver |
| `docs/firestore/add_to_event.md` (NEW) | Operation doc, mirrors existing `docs/firestore/` pattern |

Separators used (from `lib/global.dart:342`): `⬤`=`separator[0]`, `◆`=`separator[1]`, `◼`=`separator[2]`, `⭘`=`separator[8]`.

---

## Task 1: Pure keyed parser `parseAddToEvent`

**Files:**
- Create: `lib/firestore_repository/add_to_event.dart`
- Test: `test/add_to_event_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/add_to_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/add_to_event.dart';
import 'package:otonomiq/global.dart';

void main() {
  final hollow = separator[8]; // ⭘
  final square = separator[2]; // ◼

  test('parses collection name + key/value pairs', () {
    final body = 'vtl.event-report-incident'
        '${hollow}r${square}4320'
        '${hollow}ty${square}report-incident';
    final m = parseAddToEvent(body);
    expect(m['_collection'], 'vtl.event-report-incident');
    expect(m['r'], '4320');
    expect(m['ty'], 'report-incident');
  });

  test('unknown char-codes pass through, malformed parts skipped', () {
    final body = 'col${hollow}xx${square}hi${hollow}broken${hollow}d${square}desc';
    final m = parseAddToEvent(body);
    expect(m['xx'], 'hi');
    expect(m['d'], 'desc');
    expect(m.containsKey('broken'), false);
  });

  test('value containing ◼ keeps everything after the first ◼', () {
    final body = 'col${hollow}d${square}a${square}b';
    final m = parseAddToEvent(body);
    expect(m['d'], 'a${square}b');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/add_to_event_test.dart`
Expected: FAIL — `add_to_event.dart` / `parseAddToEvent` not defined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/firestore_repository/add_to_event.dart
import '../global.dart';

/// Canonical addToEvent field char-codes (spec §4). `et`/`p`/`ev`/`ld` are
/// excluded — those are spreadsheet Event columns, not Firestore doc fields.
const List<String> canonicalEventCodes = [
  'r', 'fc', 'tablevid', 'ty', 't', 'ts', 'ln', 'lq', 'i', 'd',
  'cv', 'cn', 'av', 'an', 'sv', 'sn', 'cl', 'rf', 'tv', 'tn',
  'st', 'nm', 'll', 'VID', 'n', 'ci', 'co', 'is', 'os', 'ta',
];

/// Structure-only parse of one decoded addToEvent block (a single `◆`-segment).
/// Splits by `⭘` (separator[8]); first part is the collection name; remaining
/// parts split at the first `◼` (separator[2]) into key/value. Never throws:
/// malformed parts (no `◼`) are skipped; unknown keys pass through.
Map<String, dynamic> parseAddToEvent(String body) {
  final hollow = separator[8]; // ⭘
  final square = separator[2]; // ◼
  final parts = body
      .split(hollow)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final result = <String, dynamic>{};
  if (parts.isEmpty) return result;
  result['_collection'] = parts.first;
  for (final part in parts.skip(1)) {
    final eq = part.indexOf(square);
    if (eq < 0) continue; // malformed, skip silently
    final key = part.substring(0, eq).trim();
    result[key] = part.substring(eq + 1);
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/add_to_event_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/firestore_repository/add_to_event.dart test/add_to_event_test.dart
git commit -m "feat(addToEvent): pure keyed parser parseAddToEvent"
```

---

## Task 2: Blank-prefill `fillEventBlanks`

**Files:**
- Modify: `lib/firestore_repository/add_to_event.dart`
- Test: `test/add_to_event_test.dart`

- [ ] **Step 1: Write the failing test** (append to `test/add_to_event_test.dart` `main()`)

```dart
  test('fillEventBlanks prefills canonical codes, drops _collection, keeps present', () {
    final doc = fillEventBlanks({
      '_collection': 'col', 'ty': 'x', 'xx': 'passthrough',
    });
    expect(doc.containsKey('_collection'), false);
    expect(doc['ty'], 'x');           // present value kept
    expect(doc['r'], '');             // canonical blank prefilled
    expect(doc['rf'], '');            // canonical blank prefilled
    expect(doc['xx'], 'passthrough'); // unknown code kept
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/add_to_event_test.dart`
Expected: FAIL — `fillEventBlanks` not defined.

- [ ] **Step 3: Write minimal implementation** (append to `add_to_event.dart`)

```dart
/// Builds the Firestore document: every canonical code pre-filled with '',
/// then overwritten by present keys. `_collection` is removed (it is the
/// write target, not a stored field).
Map<String, dynamic> fillEventBlanks(Map<String, dynamic> parsed) {
  final doc = <String, dynamic>{
    for (final code in canonicalEventCodes) code: '',
  };
  parsed.forEach((k, v) {
    if (k == '_collection') return;
    doc[k] = v;
  });
  return doc;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/add_to_event_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/firestore_repository/add_to_event.dart test/add_to_event_test.dart
git commit -m "feat(addToEvent): fillEventBlanks blank-prefill at write boundary"
```

---

## Task 3: Extract `resolveValueTokens` from `parseTableInput`

This is a behavior-preserving refactor: lift the per-value token resolution (current
`table_repository.dart:1184-1316`, the `default:` case body that turns `inpArray[i][1]` into the
resolved `notation`) into a standalone function, and call it from `parseTableInput`. No behavior
change — `addToTable` must keep working identically.

**Files:**
- Modify: `lib/firestore_repository/table_repository.dart` (add function ~after `parseTableInput`; edit the `default:` case)
- Test: `test/resolve_value_tokens_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/resolve_value_tokens_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';
import 'package:otonomiq/global.dart';

void main() {
  // forbiddenCharacter[7/9]=◀/▶ (system/ref[0]); [8/10]=◁/▷ (form/ref[1]).
  final lo = forbiddenCharacter[7], lc = forbiddenCharacter[9];
  final ro = forbiddenCharacter[8], rc = forbiddenCharacter[10];

  test('◀N▶ pulls from ref[0] (system), 1-based', () {
    final ref = [['sysA', 'sysB'], ['formA', 'formB']];
    final out = resolveValueTokens('${lo}2${lc}', ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(out, 'sysB');
  });

  test('◁N▷ pulls from ref[1] (form), 1-based', () {
    final ref = [['sysA'], ['formA', 'formB']];
    final out = resolveValueTokens('${ro}1${rc}', ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(out, 'formA');
  });

  test('literal passes through unchanged', () {
    final ref = [<String>[], <String>[]];
    final out = resolveValueTokens('hello', ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(out, 'hello');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/resolve_value_tokens_test.dart`
Expected: FAIL — `resolveValueTokens` not defined.

- [ ] **Step 3a: Add `resolveValueTokens`** — insert this function immediately AFTER `parseTableInput` ends (`table_repository.dart:1350`, after `} // end of parseTableInput`):

```dart
/// Resolves `◀N▶` (system / ref[0]) then `◁N▷` (form / ref[1]) tokens inside a
/// single field value — byte-identical to the per-value logic previously inline
/// in parseTableInput's `default:` case. Shared by addToTable and addToEvent.
String resolveValueTokens(
  String notation,
  List<dynamic> ref, {
  required int tableVid,
  required int appVid,
  required int timeReceived,
  required String receivingPage,
  int sourceIndex = 0,
}) {
  const vidNotation = '%vid%';
  const appVidNotation = '%appVid%';
  const timeReceivedNotation = '%timeReceived%';
  const receivingPageNotation = '%receivingPage%';
  const errorNotation = '*';
  final openNotation = forbiddenCharacter[7];
  final closeNotation = forbiddenCharacter[9];
  final openNotation2 = forbiddenCharacter[8];
  final closeNotation2 = forbiddenCharacter[10];
  const openReplacement = '<<||';
  const closeReplacement = '||>>';
  const subSourceSeparator = '.';
  final dataSeparator = forbiddenCharacter[0];
  final RegExp exp = RegExp(r'<<\|\|(.*?)\|\|>>');

  notation = notation.replaceAll(
      '$openNotation$receivingPageNotation$closeNotation', receivingPage);
  notation = notation.replaceAll(
      '$openNotation2$receivingPageNotation$closeNotation2', receivingPage);
  notation = notation
      .replaceAll(openNotation, openReplacement)
      .replaceAll(closeNotation, closeReplacement);
  String origin = notation;
  Iterable<RegExpMatch> matches = exp.allMatches(origin);
  for (Match match in matches) {
    String contentString = match.group(1) ?? '';
    String replacement = errorNotation;
    try {
      replacement = ref[sourceIndex][int.parse(contentString) - 1];
    } catch (e) {
      try {
        Map<String, dynamic> fieldMap = parseField(contentString);
        String? sourceValue;
        switch (fieldMap['c']) {
          case vidNotation:
            sourceValue = tableVid.toString();
            break;
          case appVidNotation:
            sourceValue = appVid.toString();
            break;
          case timeReceivedNotation:
            sourceValue = timeReceived.toString();
            break;
          default:
            int dotPosition =
                fieldMap['c'].toString().trim().indexOf(subSourceSeparator);
            if (dotPosition < 0) {
              sourceValue =
                  ref[0][int.parse(fieldMap['c'].toString().trim()) - 1];
            } else {
              List<String> eventArray =
                  fieldMap['c'].toString().trim().split(subSourceSeparator);
              if (eventArray.length > 1) {
                int index = int.parse(eventArray[0]) - 1;
                int subIndex = int.parse(eventArray[1]) - 1;
                List<String> dataArray =
                    ref[0][index].toString().split(dataSeparator);
                sourceValue = dataArray[subIndex];
              }
            }
        }
        replacement = stringFormat(sourceValue, fieldMap);
      } catch (e) {
        replacement = errorNotation;
      }
    }
    if (replacement != errorNotation) {
      notation = notation.replaceAll(match.group(0).toString(), replacement);
    }
  }

  notation = notation
      .replaceAll(openNotation2, openReplacement)
      .replaceAll(closeNotation2, closeReplacement);
  origin = notation;
  matches = exp.allMatches(origin);
  for (Match match in matches) {
    String substring = match.group(1) ?? '';
    String replacement = errorNotation;
    try {
      if (substring.startsWith('%')) {
        final String indexStr = substring.substring(1);
        final int refIndex = int.parse(indexStr) - 1;
        final String valueToProcess = ref[1][refIndex];
        replacement = getDocumentName(valueToProcess);
      } else {
        replacement = ref[1][int.parse(substring) - 1];
      }
    } catch (e) {
      try {
        try {
          Map<String, dynamic> fieldMap = parseField(substring);
          String? sourceValue;
          int dotPosition =
              fieldMap['c'].toString().trim().indexOf(subSourceSeparator);
          if (dotPosition < 0) {
            sourceValue =
                ref[1][int.parse(fieldMap['c'].toString().trim()) - 1];
          } else {
            List<String> eventArray =
                fieldMap['c'].toString().trim().split(subSourceSeparator);
            if (eventArray.length > 1) {
              int index = int.parse(eventArray[0]) - 1;
              int subIndex = int.parse(eventArray[1]) - 1;
              List<String> dataArray =
                  ref[1][index].toString().split(dataSeparator);
              sourceValue = dataArray[subIndex];
            }
          }
          replacement = stringFormat(sourceValue, fieldMap);
        } catch (e2) {
          replacement = errorNotation;
        }
      } catch (e) {
        replacement = errorNotation;
      }
    }
    notation = notation.replaceAll(match.group(0).toString(), replacement);
  }
  return notation;
}
```

- [ ] **Step 3b: Replace the inline body in `parseTableInput`'s `default:` case** — `table_repository.dart`. Replace the block from `int start = inpArray[i][0].toString().trim().indexOf(openField);` through `tempResult[tableIndex] = notation;` (the current lines ~1179-1324) with:

```dart
        default:
          int start = inpArray[i][0].toString().trim().indexOf(openField);
          int end = inpArray[i][0].toString().trim().indexOf(closeField);
          int tableIndex =
              int.parse(inpArray[i][0].substring(start + 1, end)) - 1;
          String notation = resolveValueTokens(
            inpArray[i][1].toString(),
            ref,
            tableVid: tableVid,
            appVid: appVid,
            timeReceived: timeReceived,
            receivingPage: receivingPage,
            sourceIndex: sourceIndex,
          );
          int maxIndex = tempResult.length - 1;
          if (maxIndex < tableIndex) {
            for (int c = maxIndex; c < tableIndex; c++) {
              tempResult.add('');
            }
          } // end if (tableIndex > len)
          tempResult[tableIndex] = notation;
```

Note: `openField`/`closeField` consts and the `errorNotation`/`openNotation*`/`exp` locals at the top of `parseTableInput` (lines 1103-1119) that are now ONLY used by the extracted function may become unused. Leave the `openField`/`closeField` (still used in `default:`). Remove any that the analyzer flags as unused inside `parseTableInput` after this edit, in Step 4b.

- [ ] **Step 4a: Run resolver tests**

Run: `flutter test test/resolve_value_tokens_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 4b: Verify no analyzer errors / regressions**

Run: `flutter analyze lib/firestore_repository/table_repository.dart`
Expected: 0 errors (warnings for any now-unused locals inside `parseTableInput` — delete those specific lines if flagged).

- [ ] **Step 5: Commit**

```bash
git add lib/firestore_repository/table_repository.dart test/resolve_value_tokens_test.dart
git commit -m "refactor(table): extract resolveValueTokens from parseTableInput"
```

---

## Task 4: `writeToEvent` — build + batch-write event docs

**Files:**
- Modify: `lib/firestore_repository/table_repository.dart` (add `buildEventDoc` + `writeToEvent`; add import)
- Modify: `lib/firestore_repository/add_to_event.dart` (none — imported)
- Test: `test/add_to_event_test.dart` (add `buildEventDoc` test)

- [ ] **Step 1: Write the failing test** (append to `test/add_to_event_test.dart` `main()`; add imports at top)

Add to the top imports of `test/add_to_event_test.dart`:
```dart
import 'package:otonomiq/firestore_repository/table_repository.dart';
```
Add test:
```dart
  test('buildEventDoc parses, resolves tokens, blank-prefills', () {
    final hollow = separator[8], square = separator[2];
    final ro = forbiddenCharacter[8], rc = forbiddenCharacter[10];
    // ref[1] = form fields; ◁1▷ -> ref[1][0]
    final ref = [<String>[], ['Lift macet']];
    final block = 'vtl.event-report-incident'
        '${hollow}ty${square}report-incident'
        '${hollow}d${square}${ro}1${rc}';
    final built = buildEventDoc(block, ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(built.collection, 'vtl.event-report-incident');
    expect(built.doc['ty'], 'report-incident');
    expect(built.doc['d'], 'Lift macet');   // ◁1▷ resolved
    expect(built.doc['r'], '');              // blank-prefilled
    expect(built.doc.containsKey('_collection'), false);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/add_to_event_test.dart`
Expected: FAIL — `buildEventDoc` / `EventDoc` not defined.

- [ ] **Step 3: Implement** — in `table_repository.dart`, add the import near the other repo imports at the top of the file:

```dart
import 'add_to_event.dart';
```

Then add, after `resolveValueTokens`:

```dart
/// Result of building one event document: its target collection + the doc map.
class EventDoc {
  final String collection;
  final Map<String, dynamic> doc;
  EventDoc(this.collection, this.doc);
}

/// Parse one decoded `◆`-block, resolve each value's tokens, blank-prefill.
EventDoc buildEventDoc(
  String block,
  List<dynamic> ref, {
  required int tableVid,
  required int appVid,
  required int timeReceived,
  required String receivingPage,
}) {
  final parsed = parseAddToEvent(block);
  final resolved = <String, dynamic>{};
  parsed.forEach((k, v) {
    if (k == '_collection') {
      resolved[k] = v;
    } else {
      resolved[k] = resolveValueTokens(
        v.toString(),
        ref,
        tableVid: tableVid,
        appVid: appVid,
        timeReceived: timeReceived,
        receivingPage: receivingPage,
      );
    }
  });
  return EventDoc(
    (parsed['_collection'] ?? '').toString(),
    fillEventBlanks(resolved),
  );
}

/// Decode + ◆-split the event segment, build each doc, batch-write atomically
/// to `collection(<line1>)`. Mirrors writeToTable's decode/ref handling.
Future<void> writeToEvent(String? inp, String eventRowString) async {
  if (inp == null || inp.trim().isEmpty) return;
  try {
    final List<dynamic> eventRow = jsonDecode(eventRowString);
    final List<dynamic> ref = parseEventString(eventRow);
    final String decoded = autheniumDecode(inp) ?? '';
    final int tableVid = appCodeController.applicationTableVid;
    final int timeReceived =
        int.tryParse(eventRow[0].toString()) ?? 0;
    final String receivingPage = eventRow[1].toString();

    final blocks =
        decoded.split(separator[1]).where((b) => b.trim().isNotEmpty);
    final WriteBatch batch = firestoreDb.batch();
    bool hasWrite = false;
    for (final block in blocks) {
      final built = buildEventDoc(
        block,
        ref,
        tableVid: tableVid,
        appVid: appCodeController.applicationTableVid,
        timeReceived: timeReceived,
        receivingPage: receivingPage,
      );
      if (built.collection.isEmpty) continue;
      final docRef = firestoreDb.collection(built.collection).doc();
      batch.set(docRef, built.doc);
      hasWrite = true;
    }
    if (hasWrite) await batch.commit();
  } catch (e) {
    devPrint('error in writeToEvent $e');
  }
}
```

(`WriteBatch`/`firestoreDb`/`appCodeController`/`devPrint`/`parseEventString`/`autheniumDecode` are already in scope in this file; `jsonDecode` via `dart:convert` already imported.)

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/add_to_event_test.dart`
Expected: PASS (5 tests).
Run: `flutter analyze lib/firestore_repository/table_repository.dart lib/firestore_repository/add_to_event.dart`
Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/firestore_repository/table_repository.dart test/add_to_event_test.dart
git commit -m "feat(addToEvent): buildEventDoc + writeToEvent batch writer"
```

---

## Task 5: Carry the event segment from `saveSend`

**Files:**
- Modify: `lib/api.dart` (`saveSend`, around `:3615-3664`)

- [ ] **Step 1: Add event-segment build** — in `saveSend`, immediately AFTER the existing `deleteString` try/catch block (after `lib/api.dart:3659` `}` that closes the deleteString block, BEFORE the `if (updateString.isNotEmpty || deleteString.isNotEmpty)` block at `:3661`), insert:

```dart
    String eventString = '';
    try {
      String raw = component['addToEvent'] ?? '';
      if (raw.isNotEmpty) {
        eventString = autheniumDecode(raw) ?? '';
        eventString = replacePlaceholders(eventString, ref);
        eventString = _resolveScreenTxMarkers(eventString);
      }
    } catch (e) {
      eventString = '';
    }
```

- [ ] **Step 2: Replace the `tb` assembly** — replace the existing block at `lib/api.dart:3661-3664`:

```dart
    if (updateString.isNotEmpty || deleteString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString';
    }
```

with (event present forces the full 4-segment shape so `event` lands at index 3):

```dart
    if (eventString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString${separator[0]}$eventString';
    } else if (updateString.isNotEmpty || deleteString.isNotEmpty) {
      tableString =
          '${tableString ?? ''}${separator[0]}$updateString${separator[0]}$deleteString';
    }
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/api.dart`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/api.dart
git commit -m "feat(addToEvent): saveSend appends event tb segment"
```

---

## Task 6: Carry the event segment from `ftz_checker`

**Files:**
- Modify: `lib/widget/ftz_checker.dart` (`checkerSaveData`, `:342-348`)

- [ ] **Step 1: Replace the checker `tb` assembly** — replace `lib/widget/ftz_checker.dart:342-348`:

```dart
      String checkerTableString = widget.component['addToTable'] ?? '';
      String updateRaw = widget.component['updateTableRow'] ?? '';
      String deleteRaw = widget.component['deleteFromTable'] ?? '';
      if (updateRaw.isNotEmpty || deleteRaw.isNotEmpty) {
        checkerTableString =
            '$checkerTableString${separator[0]}$updateRaw${separator[0]}$deleteRaw';
      }
```

with:

```dart
      String checkerTableString = widget.component['addToTable'] ?? '';
      String updateRaw = widget.component['updateTableRow'] ?? '';
      String deleteRaw = widget.component['deleteFromTable'] ?? '';
      String eventRaw = widget.component['addToEvent'] ?? '';
      if (eventRaw.isNotEmpty) {
        checkerTableString =
            '$checkerTableString${separator[0]}$updateRaw${separator[0]}$deleteRaw${separator[0]}$eventRaw';
      } else if (updateRaw.isNotEmpty || deleteRaw.isNotEmpty) {
        checkerTableString =
            '$checkerTableString${separator[0]}$updateRaw${separator[0]}$deleteRaw';
      }
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/widget/ftz_checker.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/widget/ftz_checker.dart
git commit -m "feat(addToEvent): ftz_checker appends event tb segment"
```

---

## Task 7: Dispatch `writeToEvent` from `historySync`

**Files:**
- Modify: `lib/firestore_repository/table_repository.dart` (`historySync`, `:2445-2464`)

- [ ] **Step 1: Add the 4th-segment read + dispatch** — replace the block at `table_repository.dart:2445-2464`:

```dart
                      final List<String> tbParts = rawTb.split(separator[0]);
                      final String addStr = tbParts[0];
                      final String updateStr =
                          tbParts.length > 1 ? tbParts[1] : '';
                      final String deleteStr =
                          tbParts.length > 2 ? tbParts[2] : '';
                      final String eventRowString = jsonEncode([
                        eventHistory[0],
                        eventHistory[1],
                        eventHistory[2]
                      ]);
                      if (addStr.isNotEmpty) {
                        writeToTable(addStr, eventRowString);
                      }
                      if (updateStr.isNotEmpty) {
                        updateTableRow(updateStr, eventRowString);
                      }
                      if (deleteStr.isNotEmpty) {
                        deleteFromTable(deleteStr, eventRowString);
                      }
```

with (append event handling; everything else unchanged):

```dart
                      final List<String> tbParts = rawTb.split(separator[0]);
                      final String addStr = tbParts[0];
                      final String updateStr =
                          tbParts.length > 1 ? tbParts[1] : '';
                      final String deleteStr =
                          tbParts.length > 2 ? tbParts[2] : '';
                      final String eventStr =
                          tbParts.length > 3 ? tbParts[3] : '';
                      final String eventRowString = jsonEncode([
                        eventHistory[0],
                        eventHistory[1],
                        eventHistory[2]
                      ]);
                      if (addStr.isNotEmpty) {
                        writeToTable(addStr, eventRowString);
                      }
                      if (updateStr.isNotEmpty) {
                        updateTableRow(updateStr, eventRowString);
                      }
                      if (deleteStr.isNotEmpty) {
                        deleteFromTable(deleteStr, eventRowString);
                      }
                      if (eventStr.isNotEmpty) {
                        writeToEvent(eventStr, eventRowString);
                      }
```

- [ ] **Step 2: Analyze + full test suite**

Run: `flutter analyze lib/firestore_repository/table_repository.dart`
Expected: 0 errors.
Run: `flutter test`
Expected: all tests pass (existing widget_test + new addToEvent/resolver tests).

- [ ] **Step 3: Commit**

```bash
git add lib/firestore_repository/table_repository.dart
git commit -m "feat(addToEvent): historySync dispatches writeToEvent (4th tb segment)"
```

---

## Task 8: Operation doc

**Files:**
- Create: `docs/firestore/add_to_event.md`

- [ ] **Step 1: Write the doc**

```markdown
# addToEvent (Firestore event ledger)

Sibling of `addToTable`. When a component JSON has `addToEvent`, the submit ALSO
writes a keyed document into a named Firestore collection — in addition to the
existing spreadsheet Event row (unchanged).

## Flow
saveSend / checkerSaveData append the event string as the **4th `⬤` segment** of
`tb` (`add⬤update⬤delete⬤event`). At `historySync` (online), `tbParts[3]` →
`writeToEvent()`:
1. `autheniumDecode` → split by `◆` (separator[1]) into blocks.
2. `parseAddToEvent` — split `⭘` (sep[8]) → first part = collection, rest split at
   first `◼` (sep[2]) into key/value.
3. `resolveValueTokens` — `◀N▶`=system/ref[0], `◁N▷`=form/ref[1] (shared with addToTable).
4. `fillEventBlanks` — prefill canonical codes with `""`, drop `_collection`.
5. `WriteBatch` atomic → `collection(<line1>).add(doc)` per block.

## Notes
- `et/p/ev/ld` (Event-tab cols A–D) are NOT addToEvent fields — they remain on the
  spreadsheet path (`appendToSheet`).
- `rf` `<no_request>` resolves at submit via `_resolveScreenTxMarkers` (screenTx key),
  same as addToTable.
- Token output is string; no type coercion.
```

- [ ] **Step 2: Commit**

```bash
git add docs/firestore/add_to_event.md
git commit -m "docs(addToEvent): firestore operation doc"
```

---

## Final verification

- [ ] Run `flutter analyze` (whole project) — no NEW errors vs baseline.
- [ ] Run `flutter test` — all green.
- [ ] Manual smoke (device): a screen whose component JSON has `addToEvent` → submit online → confirm a doc appears in the named Firestore collection AND the spreadsheet Event row still appears. Offline → submit → reconnect → confirm the doc lands on sync.

---

## Spec-coverage check

| Spec requirement | Task |
|---|---|
| Header branch addToTable vs addToEvent | Implicit — JSON key selects branch (Task 5/6); no string-header detection needed |
| `parseAddToEvent` → Map with `_collection` | Task 1 |
| Shared token resolver (no duplication) | Task 3 (`resolveValueTokens`) |
| Multi-doc `◆` split before per-doc parse | Task 4 (`writeToEvent` splits by `◆`) |
| Firestore writer pre-fills canonical keys `""` | Task 2 + Task 4 (`fillEventBlanks`) |
| Event-tab pushes only A/B/C; never D | Unchanged existing `appendToSheet`; out of scope |
| No validation throws on missing/unknown codes | Task 1 (skip/pass-through) |
| Multi-doc writes batched & atomic | Task 4 (`WriteBatch`) |
| `rf`/`<no_request>` placeholder | Task 5 (`_resolveScreenTxMarkers`); reused, no new code |
| Offline-first | Tasks 5–7 (history queue) |
