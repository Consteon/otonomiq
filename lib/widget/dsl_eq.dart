/// Type-tolerant equality for the search-DSL `◼` operator.
///
/// Handles Number-vs-String mismatches that arise when writers (addEventRow /
/// updateEventRow) stringify values while native writes store Numbers.
///
/// Round-trip guard: the numeric branch fires ONLY when both sides parse to a
/// number AND that number's `.toString()` reproduces the original trimmed
/// string. This prevents `"0123" == "123"` (leading-zero barcode collision)
/// and similar false positives.
///
/// Safe-integer guard: strings longer than **17** chars skip the numeric
/// branch entirely. Checked on BOTH sides: if either operand is ultra-long,
/// string fallback is used, because precision loss on either side could cause
/// a false match.
///
/// **17 is a CEILING, not a floor. Do not raise it.**
///
/// `num.==` is NOT exact above 2^53: Dart promotes the `int` operand to
/// `double`, so two DIFFERENT integers compare equal —
/// `num.parse('9007199254740993') == num.parse('9007199254740992.0')` is
/// `true` (measured). Exact *representation* and exact *comparison* are not
/// the same property, and it is the comparison that matters here.
///
/// What makes 17 safe is a string-length fact, not a value fact: Dart's
/// canonical `double.toString()` needs at least 18 chars for any value
/// >= 1e15 (`"1000000000000000.0"`), and does not switch to exponent form
/// until 1e21. So at `<= 17` no double-shaped operand can exceed
/// 999999999999999, which is comfortably below 2^53 — the unsafe range is
/// unreachable. At 18 it becomes reachable and
/// `eq('9007199254740993', '9007199254740992.0')` starts returning true:
/// the same silent-false-match bug this guard exists to prevent, one size up.
/// `test/dsl_eq_test.dart` pins BOTH ends — 17 must match, 18 must not.
///
/// Why not lower than 17: a 15-digit integer as a `double` stringifies to
/// 17 chars (`"999999999999999.0"`), and 15-digit values are common at
/// VID scale. 17 is the largest limit that is still provably safe, and it
/// happens to be exactly the one that covers them.
///
/// The limit was 15 until 2026-09-02, sized for a 13-digit epoch-as-double
/// (`"1782838800000.0"`, 15 chars). That silently broke the NEXT size up: a
/// 14-digit tenant VID stored by Firestore as a `double` stringifies to
/// `"83674161979544.0"` — **16 chars** — so it fell past the guard into the
/// string branch and `"83674161979544.0" != "83674161979544"` returned false.
/// Every `filterByMultiClause` / `evaluateGate` search comparing a 14-digit
/// VID against an `index◼…★N`-promoted field matched nothing, with no error.
/// The old limit was sized for a 13-digit epoch-as-double and simply never
/// considered the next size up; its stated "precision loss above ~18 digits"
/// rationale did not describe what the constant actually did.
///
/// Length is NOT what prevents `"0123" == "123"`; the round-trip guard below
/// (`na.toString() == sa.trim()`) is. Raising the limit cannot introduce a
/// leading-zero, hex-ish or fractional false match — those still fail
/// round-trip regardless of length.
bool eq(dynamic a, dynamic b) {
  final String sa = a?.toString() ?? '';
  final String sb = b?.toString() ?? '';
  final num? na = num.tryParse(sa);
  final num? nb = num.tryParse(sb);
  // Safe-integer guard: skip numeric for >17-char strings (15 exact digits
  // plus a `.0` suffix). See the doc-comment for why 15 was wrong.
  if (na != null &&
      nb != null &&
      sa.trim().length <= 17 &&
      sb.trim().length <= 17 &&
      na.toString() == sa.trim() &&
      nb.toString() == sb.trim()) {
    return na == nb;
  }
  return sa == sb; // string fallback
}

/// Whether a resolved token value is "empty" for search-DSL purposes.
///
/// Returns `true` when [value] is:
///   - `null`
///   - `""` (empty string)
///   - whitespace-only (e.g. `"   "`)
///
/// This is the SINGLE source of truth for empty-token detection across the
/// search-DSL layer. Used by `resolveScreenTxTokens` (leave literal when
/// empty), `filterByMultiClause` (fail-closed on empty clause value), and
/// `writeNativeFields` (refuse to write with empty search clause).
///
/// CRITICAL: the system clears `stock_location.dv` to `""` on closing
/// (`dv◼⭘dn◼`), so `{vehicleId}` resolving from `dv◼{driverVid}` is born
/// as `""` (not null). A null-only check would still leak. This function
/// treats `""` as empty.
bool isTokenEmpty(String? value) {
  if (value == null) return true;
  return value.trim().isEmpty;
}
