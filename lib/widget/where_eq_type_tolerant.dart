import 'package:cloud_firestore/cloud_firestore.dart';

/// Server-side type-tolerant equality for Firestore `where()`.
///
/// Numeric fields (VID, timestamp) may be stored as `num` in Firestore while
/// the search config delivers the value as a String. A plain `isEqualTo`
/// matches by exact type and misses the document.
///
/// Uses `whereIn: [stringValue, numValue]` when the value round-trips as a
/// canonical number AND is safe-int sized (<=15 digits). Otherwise falls back
/// to `isEqualTo: stringValue`.
///
/// Guard (same ceiling as `dsl_eq.dart eq()`, expressed in digits not chars —
/// see [numArmValue]):
///   - `num.tryParse` succeeds
///   - `.toString()` reproduces the trimmed input (no leading-zero loss)
///   - digit-only portion is <=15 characters (precision safe)
///
/// Firestore constraint: only ONE `whereIn`/`arrayContainsAny` per query.
/// Use this for at most ONE clause per compound query.
Query<T> whereEqTypeTolerant<T>(Query<T> query, String field, String value) {
  final num? n = numArmValue(value);
  if (n != null) {
    return query.where(field, whereIn: <Object>[value, n]);
  }
  return query.where(field, isEqualTo: value);
}

/// Pure guard: returns the num to include in a `whereIn` dual-type query,
/// or `null` if the value should use string-only equality.
///
/// Conditions for a num arm:
///   1. `num.tryParse(value.trim())` succeeds
///   2. The parsed number's `.toString()` equals `value.trim()` (round-trip)
///   3. The digit-only portion is <=15 characters (safe-int precision)
///
/// This is the server-side counterpart of the client-side guard in
/// `dsl_eq.dart eq()` — same intent, **deliberately different unit**.
///
/// ★ DO NOT "sync" the two numbers. `eq()` guards on total STRING LENGTH
/// (`<= 17`) because it also sees doc-side values that Firestore returned as
/// `double`, which carry a `.0` suffix. This function only ever sees the
/// CONFIG side — a clean digit string, never `.0` — so it guards on DIGIT
/// COUNT (`<= 15`). 15 digits and 17 chars describe the SAME safe ceiling in
/// the two different shapes. Copying `17` into this digit-count check would
/// admit 17-digit values, well past 2^53, where `num.==` stops being exact.
num? numArmValue(String value) {
  final String v = value.trim();
  if (v.isEmpty) return null;
  final num? n = num.tryParse(v);
  if (n == null) return null;
  if (n.toString() != v) return null;
  // Safe-int guard: strip optional leading minus, check digit length
  final String digits = v.replaceAll(RegExp(r'^-'), '');
  if (digits.length > 15) return null;
  return n;
}
