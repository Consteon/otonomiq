// lib/widget/digit_pad_support.dart
//
// Pure helpers for the DIGIT_PAD SDUI component (spec: digit-pad-widget-dev-spec).
//
// EVERY decision this feature makes lives here as a top-level function with no
// Flutter, no Firebase and no global state beyond the `emptyString` sentinel, so
// `flutter test` can drive all of it without a binding. digit_pad.dart is a thin
// shell over this file.

import '../global.dart'; // emptyString ('--')

/// Placeholder character for an empty digit box inside the buffer.
///
/// The buffer is stored in the slot's TextEditingController.text (see
/// digit_pad.dart §"two-slot contract" for why), so it must be a character that
/// is neither a digit nor one of the repo's structural delimiters. Every entry
/// in `forbiddenCharacter` (global.dart) is a geometric shape; '_' is not one.
const String digitPadHole = '_';

/// Hard ceiling on rendered boxes. Input validation at a trust boundary: a bad
/// sheet cell (`dg: 500`) must not try to paint 500 boxes.
const int digitPadMaxBoxes = 12;

/// Normalise a record-slot seed value to ''.
///
/// Three values all mean EMPTY in this repo and a bare `.isEmpty` catches only
/// one of them:
///   * ''      — genuinely empty
///   * 'null'  — getInitialValue stringifies an absent `currentValue`
///               (init_values.dart: `component['currentValue'].toString()`,
///               and `null.toString()` is "null", which passes .isNotEmpty)
///   * '--'    — `emptyString`, the InputController birth value. '--'.isEmpty
///               is FALSE.
///
/// Returns [raw] UNTRIMMED when usable: the trim is for the test only.
String digitPadNormalizeSeed(String raw) {
  final String v = raw.trim();
  if (v.isEmpty || v == 'null' || v == emptyString) return '';
  return raw;
}

/// Parse a `position`-shaped config value into a form position.
///
/// Accepts `7`, `◁7▷`, `◀7▶`, and blank. NEVER throws — unlike `getPosition`
/// (global2.dart), which does `int.parse(inp!)` and dies on a lean tenant sheet.
///
/// ◁N▷ resolves to form position N. Do NOT add 1: the older "+1" rule was wrong.
int? digitPadParsePosition(String raw) {
  final String v = raw.trim();
  if (v.isEmpty) return null;
  final Match? m = RegExp(r'\d+').firstMatch(v);
  if (m == null) return null;
  return int.tryParse(m.group(0)!);
}

/// Coerce a Firestore field to a number.
///
/// Fields come off Firestore as `dynamic` and flip between num and String per
/// tenant. Parse, never cast. Returns null for every empty sentinel.
num? digitPadNum(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw;
  final String s = raw.toString().trim();
  if (s.isEmpty || s == 'null' || s == emptyString) return null;
  return num.tryParse(s);
}

/// Render a number for a `text` token: whole values lose the `.0`.
String digitPadFmt(num v) {
  if (v is int) return v.toString();
  final double d = v.toDouble();
  if (d.isFinite && d == d.truncateToDouble() && d.abs() < 1e15) {
    return d.toInt().toString();
  }
  return v.toString();
}

/// Fixed-length digit buffer, one char per box: a digit or [digitPadHole].
///
/// Sanitises (anything that is not a digit or a hole is dropped — a stale value
/// written by some other slot writer can never paint) and refits:
///   * too long  -> truncate from the RIGHT (spec §11: "kotak kelebihan dibuang
///                  dari kanan")
///   * too short -> pad on the right with holes
/// [boxes] <= 0 -> ''.
String digitPadNormalizeBuffer(String raw, int boxes) {
  if (boxes <= 0) return '';
  final String seed = digitPadNormalizeSeed(raw);
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < seed.length; i++) {
    final String ch = seed[i];
    final int c = ch.codeUnitAt(0);
    if ((c >= 0x30 && c <= 0x39) || ch == digitPadHole) sb.write(ch);
  }
  final String buf = sb.toString();
  if (buf.length > boxes) return buf.substring(0, boxes);
  if (buf.length < boxes) return buf.padRight(boxes, digitPadHole);
  return buf;
}

/// Number of still-empty boxes -> the `{n}` token.
int digitPadHoleCount(String buffer) {
  int n = 0;
  for (int i = 0; i < buffer.length; i++) {
    if (buffer[i] == digitPadHole) n++;
  }
  return n;
}

/// The value written to `finalData`.
///
/// Spec §5: a half-filled set of boxes is NOT a number -> ''. Leading zeros are
/// display, not storage -> `00987` becomes `987`, `00000` becomes `0`.
String digitPadSubmitValue(String buffer) {
  if (buffer.isEmpty) return '';
  if (buffer.contains(digitPadHole)) return '';
  return buffer.replaceFirst(RegExp(r'^0+(?=.)'), '');
}

/// Buffer + cursor after one interaction. Cursor lives in [0, buffer.length];
/// `buffer.length` means "past the last box" and paints the caret on the last.
class DigitPadEntry {
  const DigitPadEntry(this.buffer, this.cursor);
  final String buffer;
  final int cursor;
}

String _setDigit(String buffer, int index, String digit) =>
    buffer.substring(0, index) + digit + buffer.substring(index + 1);

/// Digit key. Past the last box this is a NO-OP — not an error, not a shift
/// (spec §11: "Ketik angka ke-6 -> tidak ada yang terjadi").
DigitPadEntry digitPadPressDigit(String buffer, int cursor, String digit) {
  final int n = buffer.length;
  final int c = cursor < 0 ? 0 : cursor;
  if (digit.length != 1) return DigitPadEntry(buffer, c);
  final int code = digit.codeUnitAt(0);
  if (code < 0x30 || code > 0x39) return DigitPadEntry(buffer, c);
  if (n == 0 || c >= n) return DigitPadEntry(buffer, c);
  return DigitPadEntry(_setDigit(buffer, c, digit), c + 1);
}

/// Backspace: clear the box before the cursor and move there. At box 0, clear
/// box 0 and stay.
DigitPadEntry digitPadPressBackspace(String buffer, int cursor) {
  final int n = buffer.length;
  if (n == 0) return const DigitPadEntry('', 0);
  final int c = cursor < 0 ? 0 : (cursor > n ? n : cursor);
  final int target = c > 0 ? c - 1 : 0;
  return DigitPadEntry(_setDigit(buffer, target, digitPadHole), target);
}

/// Tap a box -> move the cursor there (clamped).
DigitPadEntry digitPadTapBox(String buffer, int index) {
  final int n = buffer.length;
  if (n == 0) return const DigitPadEntry('', 0);
  final int c = index < 0 ? 0 : (index >= n ? n - 1 : index);
  return DigitPadEntry(buffer, c);
}

/// Box count. `digitsPosition`'s resolved slot value wins when it parses to a
/// positive int; otherwise fall through to the doc's `digitsField`; neither ->
/// null, which means "render nothing" (spec §7.2). Capped at [digitPadMaxBoxes].
int? digitPadResolveCount({
  required String slotValue,
  required dynamic docValue,
}) {
  final int? fromSlot = int.tryParse(digitPadNormalizeSeed(slotValue).trim());
  if (fromSlot != null && fromSlot > 0) {
    return fromSlot > digitPadMaxBoxes ? digitPadMaxBoxes : fromSlot;
  }
  final num? fromDoc = digitPadNum(docValue);
  if (fromDoc != null && fromDoc > 0) {
    final int n = fromDoc.toInt();
    return n > digitPadMaxBoxes ? digitPadMaxBoxes : n;
  }
  return null;
}

/// The 3-tier verdict (spec §7.5).
enum DigitPadVerdict { none, sane, spike, backward }

/// Spec §7.5, exactly:
///   value < prev                              -> backward
///   value - prev > avg * spikeMultiplier      -> spike
///   otherwise                                 -> sane
///   value null (incomplete) / prev null       -> none  (SILENT, not an error)
///
/// DEVIATION, deliberate: `avg <= 0` also switches the spike check off. A
/// CF-computed `avg: 0` means "no history yet", semantically the same as a blank
/// `avgField`; taking §7.5 literally there would flag EVERY reading as a spike,
/// which spec §12 names as the failure that trains officers to ignore warnings
/// and thereby kills the backward verdict too.
DigitPadVerdict digitPadVerdict({
  required num? value,
  required num? prev,
  required num? avg,
  required num spikeMultiplier,
}) {
  if (value == null || prev == null) return DigitPadVerdict.none;
  if (value < prev) return DigitPadVerdict.backward;
  if (avg != null && avg > 0 && (value - prev) > avg * spikeMultiplier) {
    return DigitPadVerdict.spike;
  }
  return DigitPadVerdict.sane;
}

/// The ONLY blocking path in the system (product decision #21). A spike NEVER
/// blocks (spec §10: leaks are real and must be reported).
bool digitPadShouldBlock(DigitPadVerdict verdict, bool blockOnBackward) =>
    blockOnBackward && verdict == DigitPadVerdict.backward;

/// The CLOSED token list of spec §3.1. Deliberately NOT routed through
/// TokenResolver: that would open the list to every screenTx key, so a screenTx
/// entry named `value` or `n` could hijack a verdict message.
///
/// Dialect: a token with no value (or an empty one) stays LITERAL — the same
/// pending-safe rule as the `{token}` grammar in TokenResolver. Do not
/// "harmonise" it with the `<KEY>` grammar, which resolves empty to ''.
///
/// `serial` joined the list with meter-serial-verify §3.2 and carries the
/// serial number RECORDED on the meter doc, never what OCR read off the photo.
///
/// ★ `ocr` was REMOVED by that same section. Removing it from the pattern is
/// behaviour-preserving: it used to match and then stay literal for want of a
/// value, and now it never matches and stays literal. Do not put it back —
/// with §3.1's substring rule there is no single "OCR value" to display.
final RegExp _digitPadToken = RegExp(r'\{(value|prev|delta|avg|serial|n)\}');

String digitPadFillTokens(String template, Map<String, String> values) {
  if (template.isEmpty) return template;
  return template.replaceAllMapped(_digitPadToken, (Match m) {
    final String v = values[m.group(1)] ?? '';
    return v.isEmpty ? m.group(0)! : v;
  });
}

/// Form positions of every savesend button on a screen.
///
/// [children] is `screenUIComponent[scrName]['children']` — a FLAT List of
/// components. RBT buttons live one level down, in the RBT's own `children`.
///
/// ★ SINGULAR `action`. `actions` (plural) is the approval-chain field and is a
/// different contract entirely — never read it here.
///
/// The comparison mirrors ftz_row_of_button_2's own switch
/// (`(buttonData['action'] ?? emptyString).toString().trim().toLowerCase()`)
/// with NO autheniumDecode, so the two sets cannot diverge.
///
/// A savesend child with no `position` is SKIPPED: the RBT builds it as a static
/// button outside any GetBuilder, so its isEnabled is unreachable.
List<int> digitPadSaveSendPositions(dynamic children) {
  final List<int> out = <int>[];
  if (children is! List) return out;
  for (final dynamic comp in children) {
    if (comp is! Map) continue;
    if ((comp['type'] ?? '').toString().trim().toLowerCase() != 'rbt') continue;
    final dynamic kids = comp['children'];
    if (kids is! List) continue;
    for (final dynamic kid in kids) {
      if (kid is! Map) continue;
      final String action =
          (kid['action'] ?? '').toString().trim().toLowerCase();
      if (action != 'savesend') continue;
      final int? pos = int.tryParse((kid['position'] ?? '').toString().trim());
      if (pos == null) continue;
      if (!out.contains(pos)) out.add(pos);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// rev c — red digit group (spec §2.1)
// ---------------------------------------------------------------------------

/// Number of RED boxes.
///
/// Deliberately NOT [digitPadResolveCount] with a different default: the two
/// have opposite semantics for `0`. For BLACK, `0` means "no config" and must
/// fall through to the doc. For RED, `0` is a real answer — "this site bills in
/// whole m³" (Kawasan Ruko: 5 black, 0 red) — and must WIN, or the site default
/// would resurrect the moment the officer chose "no red digits".
///
/// Nothing anywhere -> 0, never null. A resolved black count with no red config
/// is a COMPLETE configuration, not a missing one.
int digitPadResolveRedCount({
  required String slotValue,
  required dynamic docValue,
}) {
  final int? fromSlot = int.tryParse(digitPadNormalizeSeed(slotValue).trim());
  if (fromSlot != null && fromSlot >= 0) {
    return fromSlot > digitPadMaxBoxes ? digitPadMaxBoxes : fromSlot;
  }
  final num? fromDoc = digitPadNum(docValue);
  if (fromDoc != null && fromDoc >= 0) {
    final int n = fromDoc.toInt();
    return n > digitPadMaxBoxes ? digitPadMaxBoxes : n;
  }
  return 0;
}

/// The rendered box layout: [black] dark boxes, a visible comma, [red] red ones.
class DigitPadLayout {
  const DigitPadLayout(this.black, this.red);

  final int black;
  final int red;

  int get total => black + red;

  /// §2.1: `digitsRedField == 0` -> zero red boxes AND zero comma. The comma is
  /// what tells the officer where the m³ boundary is; drawing one with nothing
  /// after it would invent a boundary that does not exist on the meter face.
  bool get hasComma => red > 0;
}

/// Clamp a (black, red) pair into something paintable.
///
/// The total cap trims RED, never BLACK: black is the m³ part that becomes the
/// bill, so a cap that ate a black digit would be a 10x billing error, while a
/// cap that eats a red digit is a rounding loss. A runaway sheet cell
/// (`dgh: 500`) must not try to paint 500 boxes — input validation at a trust
/// boundary.
DigitPadLayout digitPadLayout(int black, int red) {
  final int b = black < 0
      ? 0
      : (black > digitPadMaxBoxes ? digitPadMaxBoxes : black);
  final int room = digitPadMaxBoxes - b;
  final int r = red < 0 ? 0 : (red > room ? room : red);
  return DigitPadLayout(b, r);
}

// ---------------------------------------------------------------------------
// rev d — the field picker (spec §2.2)
// ---------------------------------------------------------------------------

/// Provenance recorded in `digitsSourcePosition`. The value set is CLOSED
/// (spec §2.2 rule 2) — these exact two words go into the office report, so they
/// are not a bool and not a number.
const String digitPadSourceConfig = 'config';
const String digitPadSourceField = 'field';

/// Sanitise a `digitsOptions` / `digitsRedOptions` ◆-list into pickable counts.
///
/// Feed this from `SduiSpec.list(key)`, never a hand-rolled split:
/// `diamondTextToList('')` returns `['']`, not `[]`, and `list()` short-circuits
/// that trap.
///
/// Non-numeric entries are dropped, duplicates collapse, order is preserved,
/// and an over-cap entry is DROPPED rather than clamped — a clamped chip would
/// show the officer a number that is not the one he tapped.
///
/// [allowZero] is the whole difference between the two lists: `0` is a
/// meaningful RED option ("no red digits") and a nonsense BLACK one.
List<int> digitPadParseOptions(List<String> raw, {required bool allowZero}) {
  final List<int> out = <int>[];
  for (final String s in raw) {
    final int? v = int.tryParse(s.trim());
    if (v == null) continue;
    if (v < 0) continue;
    if (v == 0 && !allowZero) continue;
    if (v > digitPadMaxBoxes) continue;
    if (!out.contains(v)) out.add(v);
  }
  return out;
}

/// Which of spec §2.2's three states the picker is in.
enum DigitPadPickerState {
  /// No picker, no link. Either the config is locked (`auto`) or nothing is
  /// pickable at all.
  hidden,

  /// Config exists and `digitsMode:"editable"`: the segment-10 link is shown
  /// and toggles the SAME inline picker.
  link,

  /// No config: the picker is shown unconditionally and the page submit button
  /// is dead until a count is picked.
  forced,
}

/// Spec §2.2's table, exactly.
///
/// ★ [hasOptions] and [canPersist] short-circuit FIRST and that is deliberate.
/// Spec §7 item 7 kills the submit button on an unfilled picker — but a picker
/// that can never be FILLED, or whose answer can never be STORED, would leave
/// the officer permanently locked out of the page over one bad sheet cell.
/// Product #17 (the officer always wins) and §7.5 ("nol pembanding = diam,
/// bukan error") both say fail open here. With either flag false the widget
/// behaves exactly as rev b did.
///
/// [canPersist] is false when `digitsPosition` is blank, unparseable, or equal
/// to the pad's own `position` — the three cases where the widget's cross-slot
/// writer refuses the write. Without this term the officer taps a chip, nothing
/// moves, and the gate re-asserts on every build forever (§2.6 deliberately
/// removed the gate memo, so there is no self-healing path).
DigitPadPickerState digitPadPickerState({
  required bool hasCount,
  required String mode,
  required bool hasOptions,
  required bool canPersist,
}) {
  if (!hasOptions || !canPersist) return DigitPadPickerState.hidden;
  if (!hasCount) return DigitPadPickerState.forced;
  return mode.trim().toLowerCase() == 'editable'
      ? DigitPadPickerState.link
      : DigitPadPickerState.hidden;
}

/// The page submit gate. TWO independent reasons, ORed:
///
///  * spec §7 item 7 — a MANDATORY picker nobody has filled: there are no boxes,
///    so there is no legitimate number to send. Independent of
///    `blockOnBackward` (the `MeterRead` example ships it FALSE and acceptance
///    §11 still requires the block).
///  * product #21 — a backward reading with the switch on. Still the only
///    verdict-driven block in the whole system; [digitPadShouldBlock] is
///    untouched underneath.
bool digitPadBlockSubmit({
  required DigitPadVerdict verdict,
  required bool blockOnBackward,
  required DigitPadPickerState picker,
}) =>
    picker == DigitPadPickerState.forced ||
    digitPadShouldBlock(verdict, blockOnBackward);

/// The value for `digitsSourcePosition` (spec §2.2 rule 2).
///
/// ★ LATCH. Once a provenance is recorded it is never overwritten, for two
/// reasons that pull in opposite directions and are both closed by the same
/// clause:
///   * a `meter` doc that arrives AFTER the officer picked must not relabel his
///     pick as `config` — the office would then never review the one row that
///     needs reviewing;
///   * a doc-seeded count is read back from the SLOT on every later build, so
///     [fromDoc] is false from build 2 onward — without the latch every point
///     would flip to `field` and the office would review all of them.
///
/// The officer's own tap bypasses this by writing `field` straight into the
/// slot (see `_pick*` in digit_pad.dart). The latch guards against MACHINE
/// overwrites, not against an explicit human override.
String digitPadResolveSource(String current, {required bool fromDoc}) {
  final String v = digitPadNormalizeSeed(current).trim().toLowerCase();
  if (v == digitPadSourceConfig || v == digitPadSourceField) return v;
  return fromDoc ? digitPadSourceConfig : digitPadSourceField;
}

// ---------------------------------------------------------------------------
// rev e — the verdict bottom sheet (spec §4c)
// ---------------------------------------------------------------------------

/// Should the verdict sheet rise unprompted (spec §4c rules 1-2)?
///
/// ★ `sane` NEVER raises. That is what keeps the pattern usable: §4c rule 1 —
/// a sheet on every unit trains officers to close it without reading, and once
/// that habit exists the BACKWARD verdict is closed without reading too.
///
/// [alreadyRaisedFor] is the submitted value the sheet last rose for. A value
/// that already had its turn does not get another one, so a rebuild — a
/// background readSettings refresh, or a scroll that re-creates the State —
/// cannot re-raise it (§4c rule 3). A NEW complete value earns a fresh raise.
///
/// [verdictText] blank means the config author silenced that segment, and §3.1
/// says a blank segment means the feature is silent — so there is nothing to
/// raise a sheet for.
bool digitPadShouldRaiseSheet({
  required DigitPadVerdict verdict,
  required String submitValue,
  required String verdictText,
  required String? alreadyRaisedFor,
}) {
  if (submitValue.isEmpty) return false;
  if (verdictText.isEmpty) return false;
  if (verdict != DigitPadVerdict.spike && verdict != DigitPadVerdict.backward) {
    return false;
  }
  return alreadyRaisedFor != submitValue;
}

// ---------------------------------------------------------------------------
// meter-serial-verify — the serial-number guard (spec §3.1)
// ---------------------------------------------------------------------------
//
// ZERO ML Kit in this file, deliberately. Same rule that kept
// ocrFlattenElements out of ocr_capture_support.dart: a support file that
// other widgets import must never be able to take an ML Kit resolution failure
// with it. The one ML Kit call lives in digit_pad.dart.

/// Spec §3.1 step 2: uppercase, then drop every character that is not A-Z or
/// 0-9 (spaces, dashes, dots and slashes all disappear).
///
/// Applied to BOTH sides — the OCR text and the recorded serial — which is the
/// only reason `A21-4471908` and a photo printed `A21 4471908` are the same
/// serial (acceptance §11).
///
/// ASCII-only on purpose: a meter serial is stamped in Latin characters, and
/// folding unicode digit look-alikes here would silently widen what counts as
/// a match, which §3.1 forbids ("nol ambang kemiripan").
String digitPadNormalizeSerial(String raw) {
  final String up = raw.toUpperCase();
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < up.length; i++) {
    final int c = up.codeUnitAt(i);
    if ((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A)) {
      sb.writeCharCode(c);
    }
  }
  return sb.toString();
}

/// Spec §3.1 steps 2-3 as ONE question: "is there anything to warn about?"
///
/// TRUE  = say nothing (the serial was found, or there is no serial to look for)
/// FALSE = the recorded serial is not in this text
///
/// Substring, NOT equality: a real photo also carries the brand, an SNI mark, a
/// burned-in watermark and coordinates. §12 notes the watermark cannot make a
/// WRONG serial match — it only adds text — which is exactly why substring is
/// the safe direction here.
///
/// ★ The empty-needle case returns TRUE deliberately. `''.contains` is always
/// true, so a naive substring call reaches the right ANSWER for the wrong
/// REASON; and returning false would raise a mismatch on every point that has
/// no serial recorded — §12's failure mode where officers learn to dismiss the
/// sheet unread, taking the backward verdict down with it. This is only the
/// SECOND line: the caller must skip the OCR call entirely when the serial is
/// blank, because acceptance §11 measures "nol ML Kit dipanggil", not "nol
/// peringatan".
bool digitPadSerialSatisfied({
  required String ocrText,
  required String serial,
}) {
  final String needle = digitPadNormalizeSerial(serial);
  if (needle.isEmpty) return true;
  return digitPadNormalizeSerial(ocrText).contains(needle);
}

/// Local image file paths held in a `getImages` slot.
///
/// The slot holds `aum__<path>__mua` entries joined by `separator[5]` (`◇`):
/// `processData` (init_values.dart) does the join and `prepareImageAsLocal`
/// (api.dart) does the wrapping, and `renamePath` under it makes `<path>`
/// ABSOLUTE — which is what `InputImage.fromFilePath` needs.
///
/// ★ Anything NOT so wrapped is DROPPED rather than attempted. An edit page
/// seeds this slot from `currentValue`, where a previously synced photo is a
/// plain https Storage URL that ML Kit cannot open from a file path. The
/// `aum__--__mua` cancel sentinel (`emptyImageUrl`) goes the same way, and
/// `digitPadNormalizeSeed` catches the `''` / `'--'` / `'null'` seeds first.
///
/// Split on `◇` and NOT on `◆`: this value is image data, not widget config.
List<String> digitPadPhotoPaths(String slotValue) {
  final String v = digitPadNormalizeSeed(slotValue).trim();
  if (v.isEmpty) return const <String>[];
  final List<String> out = <String>[];
  for (final String part in v.split(whiteDiamond)) {
    final String s = part.trim();
    if (!s.startsWith(localImagePrefix)) continue;
    if (!s.endsWith(localImagePostfix)) continue;
    final String path = s
        .substring(localImagePrefix.length, s.length - localImagePostfix.length)
        .trim();
    if (path.isEmpty || path == emptyString) continue;
    if (out.contains(path)) continue;
    out.add(path);
  }
  return out;
}

/// Who owns the bottom sheet when a numeric verdict and a serial mismatch are
/// live at the same time.
///
/// ★ The NUMERIC verdict wins. §12 concedes the substring rule cannot tell a
/// wrong meter from an unreadable photo, so a mismatch has a high
/// false-positive rate; letting it mask a BACKWARD reading would kill the one
/// check product #21 exists for. The serial message therefore only surfaces
/// when the numbers have nothing to say — `sane`, or no reading typed yet.
bool digitPadSerialOwnsSheet({
  required DigitPadVerdict verdict,
  required bool serialMismatch,
}) =>
    serialMismatch &&
    (verdict == DigitPadVerdict.none || verdict == DigitPadVerdict.sane);

/// The raise-once latch key.
///
/// TWO independent reasons can raise the sheet and each must re-raise
/// INDEPENDENTLY of the other: a new reading (rev e §4c) and a new photo
/// (meter-serial-verify §7.7). One composite string is what lets
/// `DigitPad._sheetRaised` stay a single entry per position instead of growing
/// a second map.
///
/// ★ `''` means "nothing to raise for at all", and `''` is ALSO the re-arm
/// signal `_applySheet` keys on — so an incomplete buffer with no serial verdict
/// re-arms exactly as it did before this feature existed. Never make this
/// return a non-empty constant.
///
/// [ocrKey] enters the key only when the serial actually OWNS the sheet, so a
/// retaken photo cannot re-raise a spike warning the officer already dismissed.
///
/// ★★ The two halves are compared SEPARATELY — see [digitPadSheetKeyNumeric],
/// [digitPadSheetKeySerial] and the per-axis comparison in
/// [digitPadShouldRaiseAnySheet]. Comparing the whole string was r1's defect:
/// with a mismatch live, every complete/incomplete transition of the digit
/// buffer minted a new key and re-raised the SERIAL sheet, so correcting one
/// digit cost two modal sheets — the exact habit §4c rule 1 exists to prevent.
String digitPadSheetKey({
  required String submitValue,
  required String ocrKey,
  required bool serialOwns,
}) {
  final String serialPart = serialOwns ? ocrKey : '';
  if (submitValue.isEmpty && serialPart.isEmpty) return '';
  return '$submitValue|$serialPart';
}

/// The NUMERIC half of a composite key or latch entry — the submitted value.
///
/// Split at the FIRST `|`, never the last: the serial half is itself
/// `'<photo slot value>|<doc serial>'` and carries `|` of its own. A submitted
/// value cannot — [digitPadSubmitValue] returns digits only — which is what
/// makes the first separator unambiguous.
String digitPadSheetKeyNumeric(String key) {
  final int i = key.indexOf('|');
  return i < 0 ? key : key.substring(0, i);
}

/// The SERIAL half of a composite key or latch entry — the `ocrKey`.
String digitPadSheetKeySerial(String key) {
  final int i = key.indexOf('|');
  return i < 0 ? '' : key.substring(i + 1);
}

/// The latch entry `_applySheet` should store after this pass. `''` means
/// "no entry at all" — remove it.
///
/// The two axes remember INDEPENDENTLY, which is the whole point:
///
///  * the NUMERIC half RE-ARMS the moment the buffer is incomplete, which is
///    byte for byte what rev e did by dropping the entry (segment 12 "Perbaiki
///    angkanya" and clearData-on-navigation both keep working with no extra
///    hook);
///  * the SERIAL half is STICKY — a numeric sheet taking its turn must not
///    make the pad forget which photo the officer already dismissed, or
///    backspacing out of a spike would re-raise the serial sheet he closed two
///    taps ago.
///
/// [raised] is whether the sheet actually rose on this pass; only then does a
/// half take a new value. WHICH half rose is read off the key itself: the
/// serial part is non-empty only when the serial owns the sheet (a mismatch
/// requires a non-empty `ocrKey`), so no extra staged flag is needed.
String digitPadNextSheetLatch({
  required String previous,
  required String sheetKey,
  required bool raised,
}) {
  final String keySerial = digitPadSheetKeySerial(sheetKey);
  final String keyNumeric = digitPadSheetKeyNumeric(sheetKey);
  final String nextNumeric = keyNumeric.isEmpty
      ? ''
      : (raised && keySerial.isEmpty
          ? keyNumeric
          : digitPadSheetKeyNumeric(previous));
  final String nextSerial = (raised && keySerial.isNotEmpty)
      ? keySerial
      : digitPadSheetKeySerial(previous);
  if (nextNumeric.isEmpty && nextSerial.isEmpty) return '';
  return '$nextNumeric|$nextSerial';
}

/// Should the sheet rise, counting BOTH reasons?
///
/// The numeric half DELEGATES to the unchanged [digitPadShouldRaiseSheet] so
/// rev e's rules cannot drift: `sane` never raises (§4c rule 1 — a sheet on
/// every unit trains officers to close it unread, and once that habit exists
/// the BACKWARD verdict is closed unread too) and an incomplete buffer never
/// raises.
///
/// The serial half needs its own rule because it must raise with the digit
/// boxes still EMPTY — spec §5's sketch is exactly that — so it cannot pass
/// through the `submitValue` guard.
///
/// [sheetKey] and [alreadyRaisedFor] are both composites — from
/// [digitPadSheetKey] and [digitPadNextSheetLatch] respectively — and each
/// half is compared against its OWN half, which is why the delegated call is
/// handed the numeric half rather than `null`.
///
/// ★ A WHOLE-STRING comparison is what let the numeric axis invalidate the
/// serial axis's memory (r1 W1): with a mismatch live, typing or backspacing a
/// digit changed the key and re-raised the serial sheet on every
/// complete/incomplete transition. Do not fold the two comparisons back into
/// one.
bool digitPadShouldRaiseAnySheet({
  required DigitPadVerdict verdict,
  required String submitValue,
  required String sheetText,
  required bool serialOwns,
  required String sheetKey,
  required String? alreadyRaisedFor,
}) {
  if (sheetText.isEmpty) return false;
  if (sheetKey.isEmpty) return false;
  final String latch = alreadyRaisedFor ?? '';
  if (serialOwns) {
    final String serial = digitPadSheetKeySerial(sheetKey);
    return serial.isNotEmpty && digitPadSheetKeySerial(latch) != serial;
  }
  return digitPadShouldRaiseSheet(
    verdict: verdict,
    submitValue: submitValue,
    verdictText: sheetText,
    alreadyRaisedFor: digitPadSheetKeyNumeric(latch),
  );
}
