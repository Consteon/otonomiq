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
/// Safe-integer guard: strings longer than 15 chars skip the numeric branch
/// entirely (int64/double precision loss above ~18 digits; epochs = 13 digits,
/// barcodes = 13 digits, tenant VIDs = 14 digits — all safe under 15).
/// Checked on BOTH sides: if either operand is ultra-long, string fallback is
/// used, because precision loss on either side could cause a false match.
/// The 15-char limit sits exactly on the epoch-as-double boundary: a 13-digit
/// epoch stored as `double` stringifies to `"1782838800000.0"` (15 chars),
/// still within the guard so the `.0` suffix is tolerated.
bool eq(dynamic a, dynamic b) {
  final String sa = a?.toString() ?? '';
  final String sb = b?.toString() ?? '';
  final num? na = num.tryParse(sa);
  final num? nb = num.tryParse(sb);
  // Safe-integer guard: skip numeric for >15-char strings
  if (na != null &&
      nb != null &&
      sa.trim().length <= 15 &&
      sb.trim().length <= 15 &&
      na.toString() == sa.trim() &&
      nb.toString() == sb.trim()) {
    return na == nb;
  }
  return sa == sb; // string fallback
}
