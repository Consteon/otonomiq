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
  num deltaMax = 0,
  int pow10 = 1,
}) {
  if (value == null || prev == null) return DigitPadVerdict.none;
  if (value < prev) return DigitPadVerdict.backward;
  final num delta = digitPadDelta(value: value, prev: prev, pow10: pow10)!;
  if (avg != null && avg > 0 && delta > avg * spikeMultiplier) {
    return DigitPadVerdict.spike;
  }
  // ── ABSOLUTE ceiling (digit-pad-deltamax-serial §3, 2026-09-04) ──
  //
  // The relative rule above is nothing at all on a point with no `avg`, and a
  // point with fewer than two readings has no avg — i.e. EVERY new point. This
  // branch is the floor under it.
  //
  // UNITS. [value] and [prev] are RAW meter stands; [pow10] converts to m³,
  // which is the unit [deltaMax] is authored in and the unit `avg` already
  // carries. Comparing a raw dgm:2 stand against a m³ ceiling would miss by
  // 100x, so the conversion has to happen — but it happens HERE, on the
  // DIFFERENCE, exactly once (see [digitPadDelta]). Pre-divided m³ values with
  // the default `pow10: 1` also work and are what the dgm:0 shape reduces to;
  // what must never happen again is the caller dividing both sides and this
  // function subtracting the two quotients.
  //
  // ★ STRICT `>`, exactly like the avg branch above: segment 15 says "melewati
  // batas", and exceeding a limit is not reaching it. A reading exactly at
  // [deltaMax] is `sane` — which is only decidable because [digitPadDelta]
  // divides once.
  //
  // deltaMax <= 0 (blank cell, `0`, a negative, an unparseable value that
  // num.tryParse turned into the 0 default) switches the branch off, which is
  // what makes "deltaMax absent == the pre-2026-09-04 behaviour" structural.
  if (deltaMax > 0 && delta > deltaMax) return DigitPadVerdict.spike;
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
/// ★ `deltaMax` is listed BEFORE `delta`. Dart's RegExp backtracks, so the
/// other order happens to work too — but only by luck, and a reader cannot tell
/// the two apart. Longest-alternative-first makes it unambiguous, and
/// digit_pad_support_test.dart pins both `{delta}` and `{deltaMax}` resolving
/// correctly from the SAME template.
final RegExp _digitPadToken = RegExp(
  r'\{(value|prev|deltaMax|delta|avg|serial|n)\}',
);

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
      final String action = (kid['action'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
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

/// Who owns the bottom sheet when a numeric verdict and a serial mismatch are
/// live at the same time.
///
/// ★ The NUMERIC verdict wins. §12 concedes the substring rule cannot tell a
/// wrong meter from an unreadable photo, so a mismatch has a high
/// false-positive rate; letting it mask a BACKWARD reading would kill the one
/// check product #21 exists for. The serial message therefore only surfaces
/// when the numbers have nothing to say — `sane`, or no reading typed yet.
///
/// ★★ AMENDED 2026-09-04: whichever problem is LOCKING wins.
///
/// [serialBlocking] is `blockOnSerialMismatch && <serial problem> && enabled`.
/// When it is true the serial message takes the sheet from ANY numeric verdict,
/// because only the serial message names the thing the officer can do to
/// unlock — and with the gate engaged `_sheetBlocked` suppresses the segment-13
/// acknowledge button, so a sheet carrying the SPIKE copy would demand a
/// correction that cannot lift the block. Nothing is hidden by this: the card's
/// inline banner still renders the numeric verdict in every case (spec §5 gives
/// the serial the sheet and nothing else).
///
/// When the serial problem does NOT block, the rule above is unchanged.
///
/// [serialMismatch] means "the serial has a PROBLEM" and since 2026-09-04 that
/// covers `missing` as well as `mismatch` — one switch owns both.
bool digitPadSerialOwnsSheet({
  required DigitPadVerdict verdict,
  required bool serialMismatch,
  required bool serialBlocking,
}) {
  if (!serialMismatch) return false;
  if (serialBlocking) return true;
  return verdict == DigitPadVerdict.none || verdict == DigitPadVerdict.sane;
}

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
/// ★ [ocrKey] keeps its name for continuity; since 2026-09-04 it carries the
/// SERIAL-STATE key from `digitPadSerialKey`, not an OCR key. This widget has
/// no OCR any more.
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

// ---------------------------------------------------------------------------
// digit-pad-deltamax-serial (2026-09-04) — the m³ basis and the serial state
// ---------------------------------------------------------------------------

/// `10^[red]` as an exact int — the raw-stand -> m³ divisor.
///
/// A loop rather than dart:math's `pow`: `pow` returns `num` and its
/// int-vs-double result for int arguments is an implementation detail, and this
/// value divides a number that becomes a tenant's bill. Multiplying by ten
/// [red] times is exact for every [red] this widget can produce — [red] is
/// capped at [digitPadMaxBoxes] (12), so at most 10^12, well inside int64.
int digitPadPow10(int red) {
  final int n = red < 0 ? 0 : (red > digitPadMaxBoxes ? digitPadMaxBoxes : red);
  int p = 1;
  for (int i = 0; i < n; i++) {
    p *= 10;
  }
  return p;
}

/// A raw meter stand (the meter's finest unit) -> m³.
///
/// §2.1 stores the WHOLE integer and calls the `/ 10^red` display-only. That
/// was true until `deltaMax` arrived: the ceiling is authored in m³ and `avg` is
/// authored in m³/month (the same page's DETAIL_CARD renders it as
/// `<avg> m³/bln`), while `compareField` is raw — so the comparison has to
/// happen after this division, not before, or a dgm:2 point misses by 100x.
///
/// ★ Returns [raw] UNCHANGED when [pow10] is 1 — the `dgm: 0` shape, which is
/// the one live point today and every test component that configures no red
/// digits. That short-circuit is what makes "no red digits == byte-identical to
/// the pre-2026-09-04 behaviour" structural instead of argued: with no division
/// there is no int -> double promotion, so `{prev}` and `{delta}` render exactly
/// the strings they always did.
///
/// SCOPE: this converts ONE number, for DISPLAY — `{value}` and `{prev}`.
/// It is correctly rounded (IEEE-754 requires that of a single division), so
/// 12600 / 100 is exactly 126.0 and 2802 / 100 is the double nearest 28.02,
/// which is the best `{prev}` that exists.
///
/// ★ DO NOT build a delta out of two of these. `a / p - b / p` is a difference
/// of two SEPARATELY rounded quotients, and a difference of correctly-rounded
/// values is not itself correctly rounded: at dgm:2, (12802 / 100) - (2802 /
/// 100) is 100.00000000000001, so a reading of exactly 100 m³ tripped a
/// `deltaMax: 100` ceiling and segment 15 rendered "Pemakaian
/// 100.00000000000001 m³". Measured on 1.64% of raw prev values in 0..999999
/// at that config, always in the same direction (sane -> spike), i.e. a false
/// positive generator. Use [digitPadDelta], which divides the difference once.
num? digitPadCubic(num? raw, int pow10) {
  if (raw == null || pow10 <= 1) return raw;
  return raw / pow10;
}

/// THE delta, in m³. One subtraction on the RAW stands, then ONE division.
///
/// The single definition of "how much was used", and deliberately the only
/// one: [digitPadVerdict] calls it for the `avg * spikeMultiplier` branch AND
/// the `deltaMax` branch, and DigitPad's token map calls it for `{delta}`. Two
/// invocations, one expression — so the number the officer reads in the sheet
/// is by construction the number the verdict decided on. Recomputing it
/// anywhere else re-opens the defect described on [digitPadCubic].
///
/// Exactness: the subtraction of two whole meter stands is exact in binary64
/// (they are integers far below 2^53), and the one division that follows is
/// correctly rounded, so an exactly-representable quotient IS exact — 10000 /
/// 100 is 100.0, never 100.000...1. That, and nothing weaker, is what makes
/// the strict-`>` threshold decidable at the boundary.
///
/// Null in either operand (an incomplete reading, or no `compareField` doc) ->
/// null: "no delta", never 0.
num? digitPadDelta({required num? value, required num? prev, int pow10 = 1}) {
  if (value == null || prev == null) return null;
  return digitPadCubic(value - prev, pow10);
}

/// What the serial slot and the `meter` doc say about each other.
///
/// FOUR states, not two, and the difference is a product decision (spec §3):
///   * [off]      — nothing recorded on the doc, or the feature is not wired.
///                  ZERO checks, ZERO warnings, ZERO gate. Never train officers
///                  to dismiss a signal.
///   * [ok]       — they agree.
///   * [missing]  — a serial IS recorded but the slot is empty. Skipping the
///                  capture is NOT an escape hatch: an officer at the wrong
///                  meter could simply not fill it. Segment 16.
///   * [mismatch] — both filled, they disagree. Segment 6.
enum DigitPadSerialState { off, ok, missing, mismatch }

/// The serial comparison, mirroring the CF's `serialVerdict`
/// (`internal/meter/meter.go`).
///
/// ⚠ That Go repository is NOT on this machine. This function was written from
/// the spec's prose description of the CF rule, so "the two agree" is an
/// intention, not a verified equivalence. If the CF rule ever moves, this is
/// the second copy that has to move with it — do NOT invent a third rule here.
///
/// Both sides are normalised INTERNALLY (uppercase, keep only A-Z0-9), which is
/// the only reason `B21-4471902` and a field holding `B214471902` are the same
/// serial. Then:
///   * either side empty        -> false (the caller decides what empty MEANS;
///                                 see [digitPadSerialState])
///   * min length < 4           -> exact equality required. A 1-3 character
///                                 string substring-matches almost anything.
///   * otherwise                -> substring in EITHER direction. The recorded
///                                 value may be a prefix of what was read, or
///                                 the read value may carry a brand/SNI prefix
///                                 around it.
///
/// ZERO fuzzy matching, ZERO similarity threshold, ZERO Levenshtein. A check
/// loosened until it always passes is worse than no check: officers learn to
/// dismiss the sheet unread, and the backward verdict dies with it because it
/// uses the same sheet.
///
/// ★ Two-way, unlike the deleted `digitPadSerialSatisfied`, which only asked
/// whether the OCR text contained the serial.
bool digitPadSerialMatch(String recorded, String read) {
  final String a = digitPadNormalizeSerial(recorded);
  final String b = digitPadNormalizeSerial(read);
  if (a.isEmpty || b.isEmpty) return false;
  final int shortest = a.length < b.length ? a.length : b.length;
  if (shortest < 4) return a == b;
  return a.contains(b) || b.contains(a);
}

/// Spec §3's two sentences as one state.
///
/// ★ [digitPadNormalizeSeed] runs BEFORE [digitPadNormalizeSerial] on the read
/// side, and that ORDER is load-bearing. `digitPadNormalizeSerial('null')` is
/// `'NULL'` — the letters survive. `getInitialValue` (init_values.dart) seeds a
/// slot whose component omits `currentValue` with the literal string "null", so
/// without the seed normaliser first an unauthored TXF would compare the serial
/// `NULL` against the doc and report a mismatch on a page the officer never
/// touched. `'--'` (the InputController birth value) and `''` go the same way.
///
/// An officer typing `"---"` is not one of those sentinels, but
/// [digitPadNormalizeSerial] strips the dashes and it lands on [missing]
/// anyway, which is the right answer.
///
/// [recorded] blank -> [off] and nothing else is even looked at: that is the
/// "gak ada seri = aman, nol apa pun" half of the owner's rule.
DigitPadSerialState digitPadSerialState({
  required String recorded,
  required String read,
}) {
  if (digitPadNormalizeSerial(recorded).isEmpty) {
    return DigitPadSerialState.off;
  }
  if (digitPadNormalizeSerial(digitPadNormalizeSeed(read)).isEmpty) {
    return DigitPadSerialState.missing;
  }
  return digitPadSerialMatch(recorded, read)
      ? DigitPadSerialState.ok
      : DigitPadSerialState.mismatch;
}

/// The SERIAL half of the raise-once key (see [digitPadSheetKey]).
///
/// ★★ Keyed on the STATE, NEVER on the value the officer is typing. The serial
/// slot is an ordinary TXF: in the SDUI path `OtqTxf2` uses the slot's own
/// controller (otq_txf_2.dart:365-369, no `cnt` is passed by
/// build_display_component.dart:339), so the pad's listener fires on EVERY
/// keystroke, and otq_txf_2's onChanged default branch writes `finalData` per
/// character. A key carrying the read value would mint a new key per character
/// — and the sheet is MODAL, so the officer would dismiss a bottom sheet
/// between every two keystrokes. That is r1's W1 defect (five modal sheets for
/// one mismatch) coming back through a different door, and §4c rule 1 is the
/// first thing it breaks.
///
/// The bound is therefore ONE raise per serial STATE TRANSITION, not a fixed
/// total per meter. `missing -> mismatch` is genuinely new information ("not
/// just blank — actually wrong"), so it earns its own raise; a second,
/// DIFFERENT wrong value does not, which is the safe direction, and the gate
/// plus the dead save button are still there either way.
///
/// ★ Do NOT restate that bound as a raise COUNT. [digitPadNextSheetLatch] keeps
/// exactly ONE serial key and REPLACES it on each raise
/// (`nextSerial = raised && keySerial.isNotEmpty ? keySerial : previous`), so it
/// remembers the last state raised, never a set of them. `missing -> mismatch ->
/// missing` therefore raises THREE times when the reading is complete
/// throughout, and only twice when the middle step is silent for an unrelated
/// reason (an incomplete buffer). A count is order-dependent; the per-transition
/// bound is not. What matters — and what holds in every order — is that no raise
/// is ever keyed on the value being typed, so the per-keystroke sheet storm
/// stays impossible.
///
/// ★★ [readingComplete] gates the MISSING raise only. Spec §2 says the slot is
/// evaluated "saat vonis/submit ... BUKAN saat page-load", and an empty slot is
/// the birth state of EVERY meter — raising on page load would put a modal in
/// front of the officer on 100% of visits, which is §4c rule 1 again. A
/// complete digit buffer is the closest in-widget proxy for "about to submit",
/// and it matches the page flow (the OCR_CAPTURE that fills the slot sits ABOVE
/// the pad). A MISMATCH cannot fire on page load at all — the slot has to be
/// filled for that state to exist — so it is not gated.
///
/// The literal state words are written out rather than taken from `.name`, so
/// renaming an enum value cannot silently change a latch key.
String digitPadSerialKey({
  required DigitPadSerialState state,
  required String recorded,
  required bool readingComplete,
}) {
  switch (state) {
    case DigitPadSerialState.mismatch:
      return 'mismatch|$recorded';
    case DigitPadSerialState.missing:
      return readingComplete ? 'missing|$recorded' : '';
    case DigitPadSerialState.off:
    case DigitPadSerialState.ok:
      return '';
  }
}
