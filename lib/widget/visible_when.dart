// lib/widget/visible_when.dart
//
// `visibleWhen` — conditional rendering driven by LIVE FORM VALUES.
// Dev spec: visiblewhen-conditional-rendering, §3.1 grammar / §3.2 evaluation
// / §3.3 hide effects / §3.4 duplicate positions.
//
// ONE optional string field readable on ANY page-JSON component. It is NOT a
// new component type and adds NO branch to build_display_component's dispatch
// chain — it is a cross-cutting field, wrapped once at that function's single
// `return result;`.
//
// Every decision lives here as a top-level function with no DIRECT
// Flutter-widget, Firebase or GetX dependency. The transitive graph does reach
// global2.dart through input_controller.dart, but Dart imports execute nothing
// and the `finalData` setter is try/catch guarded — which is why `flutter test`
// drives all of this with no binding and no pump (same shape as
// get_images_required_support.dart and rbt_visibility.dart). The GetBuilder
// wrapper and the txfController read stay in the call sites; this file only
// ever sees a `Map<int, InputController>` handed to [visibleWhenReader].
//
// NOT the same dialect as its three siblings, deliberately:
//   * evaluateRbtSearch (approver_sticky_bar.dart)  — fail-CLOSED, UPPERCASES.
//   * filterByMultiClause (driver_home_support.dart)— fail-CLOSED on value.
//   * rbtChildVisible (rbt_visibility.dart)         — fail-CLOSED; those
//     buttons WRITE, so a wrongly-shown one is a double-accept.
//   * this file                                     — fail-OPEN (§3.2.2): the
//     worst outcome of a bad `visibleWhen` is a static form, not a broken one.
// Do NOT harmonize them.

import '../global.dart'; // autheniumDecode, devPrint
import '../model/input_controller.dart'; // InputController (reader factory)
import 'dsl_eq.dart'; // eq — type-tolerant equality, UNCHANGED
import 'get_images_required_support.dart'; // getImagesSlotValue

/// `⭘` U+2B58 — clause AND separator. Server escape: `_u2B58_`.
const String kVisibleWhenAnd = '\u{2B58}';

/// `◼` U+25FC — position/operand separator. Server escapes: `_u25FC_`, `_25FC_`.
const String kVisibleWhenSep = '\u{25FC}';

/// `★` U+2605 — IN-list separator, valid ONLY with `==` (§3.2.7).
const String kVisibleWhenIn = '\u{2605}';

const String _kRefOpen = '\u{25C1}'; // ◁
const String _kRefClose = '\u{25B7}'; // ▷

/// Comparison operators. No prefix in the config means [eq] (§3.1).
enum VisibleWhenOp { eq, ne, gt, gte, lt, lte }

/// One parsed `posisi ◼ [operator] operand` clause.
///
/// Exactly one of [literal] / [refPosition] / [inList] carries the operand:
/// `refPosition != null` for a `◁N▷` operand, `inList != null` for a `★` list,
/// otherwise [literal].
class VisibleWhenClause {
  const VisibleWhenClause({
    required this.position,
    required this.op,
    required this.literal,
    this.refPosition,
    this.inList,
  });

  /// The form position whose LIVE value is the left-hand side.
  final int position;

  final VisibleWhenOp op;

  /// Literal right-hand side; `''` when [refPosition] or [inList] is set.
  final String literal;

  /// `◁N▷` — resolve N's live form value as the right-hand side (§3.2.4).
  final int? refPosition;

  /// `a★b★c` — IN list. Non-null only when [op] is [VisibleWhenOp.eq].
  final List<String>? inList;

  @override
  String toString() =>
      'VisibleWhenClause($position $op '
      'literal:"$literal" ref:$refPosition in:$inList)';
}

/// Reads the LIVE form value at a position. Unfilled/absent MUST read as `''`
/// (§3.2.3) — never null, never a skip.
typedef VisibleWhenValueReader = String Function(int position);

/// The RAW (undecoded) `visibleWhen` of a component, trimmed. `''` when absent,
/// null or blank — which §3 defines as "always visible", so every pre-existing
/// config keeps working untouched.
///
/// Deliberately NOT read through [SduiSpec]: this runs for EVERY component on
/// EVERY page build, and SduiSpec's constructor eagerly decodes and ◆-splits
/// `component['text']`, which would be pure waste on the ~100% of components
/// that carry no `visibleWhen`. Decoding happens inside [parseVisibleWhen],
/// mirroring how rbt_visibility.dart passes a RAW `search` down.
String visibleWhenOf(dynamic component) {
  if (component is! Map) return '';
  final dynamic raw = component['visibleWhen'];
  if (raw == null) return '';
  return raw.toString().trim();
}

/// Parse [raw] into clauses. Returns `null` on ANY malformed input, which the
/// caller MUST treat as "visible" (§3.2.2 fail-open).
///
/// An EMPTY clause (trailing or doubled `⭘`) is skipped rather than failing —
/// identical to filterByMultiClause, rbtChildVisible and evaluateRbtSearch, and
/// a plausible artefact of a sheet SUBSTITUTE that concatenated a blank helper
/// cell. Skipping keeps the remaining real clause live instead of silently
/// disabling the whole condition.
///
/// Operator parsing is a prefix scan on the operand, LONGEST MATCH FIRST
/// (§3.1): `>=`, `<=`, `!=`, then `>`, `<`. Order matters — testing `>` first
/// would parse `>=5` as `> "=5"`.
List<VisibleWhenClause>? parseVisibleWhen(String raw) {
  final String decoded = (autheniumDecode(raw) ?? raw).trim();
  if (decoded.isEmpty) return const <VisibleWhenClause>[];

  final List<VisibleWhenClause> out = <VisibleWhenClause>[];
  for (final String part in decoded.split(kVisibleWhenAnd)) {
    final String clause = part.trim();
    if (clause.isEmpty) continue;

    final int sep = clause.indexOf(kVisibleWhenSep);
    if (sep < 0) return null; // no ◼
    final int? position = int.tryParse(clause.substring(0, sep).trim());
    if (position == null) return null; // non-numeric or empty key

    String rest = clause.substring(sep + 1).trim();
    VisibleWhenOp op = VisibleWhenOp.eq;
    if (rest.startsWith('>=')) {
      op = VisibleWhenOp.gte;
      rest = rest.substring(2);
    } else if (rest.startsWith('<=')) {
      op = VisibleWhenOp.lte;
      rest = rest.substring(2);
    } else if (rest.startsWith('!=')) {
      op = VisibleWhenOp.ne;
      rest = rest.substring(2);
    } else if (rest.startsWith('>')) {
      op = VisibleWhenOp.gt;
      rest = rest.substring(1);
    } else if (rest.startsWith('<')) {
      op = VisibleWhenOp.lt;
      rest = rest.substring(1);
    }
    final String operand = rest.trim();

    // ★ IN list. Checked BEFORE ◁N▷, so a list entry is always a literal.
    if (operand.contains(kVisibleWhenIn)) {
      if (op != VisibleWhenOp.eq) return null; // §3.2.7
      out.add(
        VisibleWhenClause(
          position: position,
          op: op,
          literal: '',
          inList: operand
              .split(kVisibleWhenIn)
              .map((String e) => e.trim())
              .toList(growable: false),
        ),
      );
      continue;
    }

    // ◁N▷ live-value reference.
    if (operand.length >= 2 &&
        operand.startsWith(_kRefOpen) &&
        operand.endsWith(_kRefClose)) {
      final int? ref = int.tryParse(
        operand.substring(1, operand.length - 1).trim(),
      );
      if (ref == null) return null; // ◁abc▷ -> fail open, not a literal
      out.add(
        VisibleWhenClause(
          position: position,
          op: op,
          literal: '',
          refPosition: ref,
        ),
      );
      continue;
    }

    out.add(VisibleWhenClause(position: position, op: op, literal: operand));
  }
  return out;
}

/// Ordering comparison for `>` `<` `>=` `<=` (§3.2.5).
///
/// Numeric when `num.tryParse` succeeds on BOTH sides, string-ordinal
/// otherwise. There is NO date parsing by design (§8): config discipline is
/// ISO (`yyyy-MM-dd`, `HH:mm`), whose string order IS time order.
///
/// Returns `null` when either side is empty, which §3.2.6 defines as making an
/// ordering clause FALSE. That is what stops the spec §4 noticeBar
/// (`5◼<=◁4▷`) from firing prematurely while position 5 is still blank.
int? visibleWhenCompare(String a, String b) {
  final String sa = a.trim();
  final String sb = b.trim();
  if (sa.isEmpty || sb.isEmpty) return null;
  final num? na = num.tryParse(sa);
  final num? nb = num.tryParse(sb);
  if (na != null && nb != null) return na.compareTo(nb);
  return sa.compareTo(sb);
}

bool _clauseTrue(VisibleWhenClause c, VisibleWhenValueReader valueAt) {
  final String left = valueAt(c.position);

  final List<String>? options = c.inList;
  if (options != null) {
    for (final String option in options) {
      if (eq(left, option)) return true;
    }
    return false;
  }

  final int? ref = c.refPosition;
  final String right = ref == null ? c.literal : valueAt(ref);

  switch (c.op) {
    // eq() is used UNCHANGED: its round-trip guard and 17-char safe-integer
    // ceiling are load-bearing (see dsl_eq.dart). Do not copy it, do not wrap
    // it in toUpperCase — this dialect is case-SENSITIVE.
    case VisibleWhenOp.eq:
      return eq(left, right);
    case VisibleWhenOp.ne:
      return !eq(left, right);
    case VisibleWhenOp.gt:
      final int? r = visibleWhenCompare(left, right);
      return r != null && r > 0;
    case VisibleWhenOp.gte:
      final int? r = visibleWhenCompare(left, right);
      return r != null && r >= 0;
    case VisibleWhenOp.lt:
      final int? r = visibleWhenCompare(left, right);
      return r != null && r < 0;
    case VisibleWhenOp.lte:
      final int? r = visibleWhenCompare(left, right);
      return r != null && r <= 0;
  }
}

/// Evaluate one component's `visibleWhen`. `true` == render it.
///
/// [scrName] is used only for the fail-open log line, so bad config is
/// findable in a debug run.
bool visibleWhenVisible(
  String raw,
  VisibleWhenValueReader valueAt, {
  String scrName = '',
}) {
  if (raw.trim().isEmpty) return true; // §3.2.1
  final List<VisibleWhenClause>? clauses = parseVisibleWhen(raw);
  if (clauses == null) {
    // §3.2.2 fail-OPEN. Logged so a malformed sheet cell is findable instead
    // of silently producing a permanently-visible field.
    devPrint(
      'visibleWhen: unparseable "$raw" on "$scrName" '
      '-> visible (fail-open)',
    );
    return true;
  }
  for (final VisibleWhenClause c in clauses) {
    if (!_clauseTrue(c, valueAt)) return false; // §3.2.8
  }
  return true;
}

/// Record positions whose value must be EXCLUDED from submit (§3.3).
///
/// A position is excluded only when it is BOTH declared-conditional AND
/// currently hidden:
///
///   declared = { p : some child at p carries a non-empty visibleWhen }
///   visible  = { p : some child at p has NO visibleWhen }
///            u { p : some child at p evaluates VISIBLE }
///   excluded = declared \ visible
///
/// A position nothing declares can never enter `declared`, so a page with no
/// `visibleWhen` produces an empty set and submits byte-for-byte as today.
/// That is the regression-zero guarantee (spec §9 item 1).
///
/// It also delivers §3.4 for free: duplicate positions share ONE
/// InputController (txfController is keyed by position — global2.dart
/// `txfControllerCheck`), so if ANY widget at position N is visible the slot
/// survives, and "◁N▷ takes the visible one" is structural rather than a rule
/// this function has to implement.
///
/// [children] is `screenUIComponent[scrName]['children']` — a FLAT List. Chain
/// children (DO_BOTTOM_SHEET / DO_DIALOG / RBT children) are deliberately NOT
/// descended into, matching getImagesRequiredBlock: a sheet is built with the
/// SAME scrName and its RBT runs this same page-level scan.
///
/// Positions below 1 are skipped because saveSend's composer only ever writes
/// `1 <= input.position && input.position <= 100`.
///
/// The position is read with `int.tryParse`, NOT with the existing
/// `getPosition` (global2.dart) — on purpose, do not "correct" it toward the
/// helper. `getPosition` is `(inp!.runtimeType == String) ? int.parse(inp!)
/// : inp!`, which throws on a null, on a non-numeric string and on a double.
/// This function runs over untrusted page JSON inside a SUBMIT path, where a
/// throw would lose the record; `tryParse` skips the bad child instead.
Set<int> hiddenVisibleWhenPositions(
  dynamic children,
  VisibleWhenValueReader valueAt, {
  String scrName = '',
}) {
  if (children is! List) return const <int>{};
  final Set<int> declared = <int>{};
  final Set<int> visible = <int>{};
  for (final dynamic c in children) {
    if (c is! Map) continue;
    final int? pos = int.tryParse((c['position'] ?? '').toString().trim());
    if (pos == null || pos < 1) continue;
    final String raw = visibleWhenOf(c);
    if (raw.isEmpty) {
      visible.add(pos); // an unconditional widget protects the slot outright
      continue;
    }
    declared.add(pos);
    if (visibleWhenVisible(raw, valueAt, scrName: scrName)) visible.add(pos);
  }
  return declared.difference(visible);
}

/// [children] with the currently-hidden ones removed (§3.3 "validation
/// skipped"). Non-Map entries are passed through untouched.
///
/// Returns a plain `List<dynamic>`, which is exactly what
/// getImagesRequiredBlock accepts — no typed-collection cast is introduced.
List<dynamic> visibleWhenChildren(
  dynamic children,
  VisibleWhenValueReader valueAt, {
  String scrName = '',
}) {
  if (children is! List) return const <dynamic>[];
  return children.where((dynamic c) {
    if (c is! Map) return true;
    final String raw = visibleWhenOf(c);
    if (raw.isEmpty) return true;
    return visibleWhenVisible(raw, valueAt, scrName: scrName);
  }).toList();
}

/// A [VisibleWhenValueReader] over one page's `txfController[scrName]` slice.
///
/// The value MUST be exactly what saveSend would submit, so this delegates to
/// the already-named [getImagesSlotValue] rather than restating
/// `finalData == emptyString ? controller.text : finalData`. That helper exists
/// precisely so the record composer's selection rule cannot silently drift; if
/// api.dart's rule ever changes, that one line changes with it and this reader
/// follows for free.
///
/// A fresh untouched slot is born `finalData == '--'` (emptyString) with an
/// empty controller, so this yields `''` — spec §3.2.3's "unfilled". A position
/// with no slot at all also yields `''`.
///
/// The map is PASSED IN, never imported, which is what keeps this file free of
/// global2.dart / GetX / Firebase.
VisibleWhenValueReader visibleWhenReader(Map<int, InputController>? slots) {
  return (int position) {
    final InputController? ic = slots?[position];
    if (ic == null) return '';
    return getImagesSlotValue(ic.finalData, ic.controller.text);
  };
}
