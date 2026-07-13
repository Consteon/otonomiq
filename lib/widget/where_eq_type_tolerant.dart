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
/// Guard (consistent with `dsl_eq.dart eq()`):
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
/// `dsl_eq.dart eq()`. Same semantics, same boundary.
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
