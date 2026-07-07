import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/dsl_eq.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/vehicle_feed_support.dart';
import 'package:otonomiq/widget/admin_home_support.dart';

void main() {
  // ── eq() unit tests ─────────────────────────────────────────────────────

  group('eq() — spec §7 scenarios', () {
    // §7.1: epoch String↔Number match (THE BUG)
    test('epoch String "1782838800000" matches int 1782838800000', () {
      expect(eq('1782838800000', 1782838800000), true);
    });

    test('epoch int 1782838800000 matches String "1782838800000"', () {
      expect(eq(1782838800000, '1782838800000'), true);
    });

    test('epoch String matches String (identical)', () {
      expect(eq('1782838800000', '1782838800000'), true);
    });

    test('epoch int matches int (identical)', () {
      expect(eq(1782838800000, 1782838800000), true);
    });

    // §7.2: vv (hex-ish id) still string-matches
    test('vv "F621a02a983500" matches identical string', () {
      expect(eq('F621a02a983500', 'F621a02a983500'), true);
    });

    test('vv "F621a02a983500" does not match different string', () {
      expect(eq('F621a02a983500', 'F621a02a983501'), false);
    });

    test('vv with letters not parsed as number', () {
      // num.tryParse('F621a02a983500') returns null -> string compare
      expect(eq('F621a02a983500', 'f621a02a983500'), false); // case-sensitive
    });

    // §7.3: cst gate (enum string exact)
    test('cst "custody_confirmed" matches exact string', () {
      expect(eq('custody_confirmed', 'custody_confirmed'), true);
    });

    test('cst "custody_confirmed" does not match different enum', () {
      expect(eq('custody_confirmed', 'awaiting_custody'), false);
    });

    // §7.4: barcode no-collision
    test('barcode "8886008101138" matches identical barcode', () {
      expect(eq('8886008101138', '8886008101138'), true);
    });

    test('barcode "8886008101138" matches same value as int', () {
      // Both are canonical numeric representations under 15 chars
      expect(eq('8886008101138', 8886008101138), true);
    });

    test('barcode with leading zero "08886008101138" does NOT match "8886008101138"', () {
      // "08886008101138" -> num.tryParse = 8886008101138
      // but 8886008101138.toString() = "8886008101138" != "08886008101138"
      // -> round-trip fails -> string compare -> "08886..." != "8886..." -> false
      expect(eq('08886008101138', '8886008101138'), false);
    });

    test('leading-zero barcode matches only itself', () {
      expect(eq('08886008101138', '08886008101138'), true);
    });

    // §7.5: tst enum exact
    test('tst "assigned" matches exact string', () {
      expect(eq('assigned', 'assigned'), true);
    });

    test('tst "assigned" does not match "closed"', () {
      expect(eq('assigned', 'closed'), false);
    });

    // §7.6: mixed-type doc fields (t=Number, tdt=String)
    test('Number t matches same value as String', () {
      expect(eq(1782875462202, '1782875462202'), true);
    });
  });

  group('eq() — edge cases', () {
    test('null operands', () {
      expect(eq(null, null), true); // both toString -> ''
      expect(eq(null, ''), true);
      expect(eq('', null), true);
      expect(eq(null, 'x'), false);
    });

    test('bool operands (Firestore can store bools)', () {
      expect(eq(true, 'true'), true); // true.toString() = 'true'
      expect(eq(false, 'false'), true);
      expect(eq(true, false), false);
    });

    test('double with .0 suffix matches int', () {
      // This is the core fix: Firestore may return a double
      // 42.0.toString() = "42.0"; 42.toString() = "42"
      // String fallback would fail; numeric branch catches it
      expect(eq(42.0, 42), true);
      expect(eq(42.0, '42'), true);
      expect(eq('42.0', 42), true);
    });

    test('double without .0 suffix (fractional) does not match int', () {
      // 42.5 != 42
      expect(eq(42.5, 42), false);
    });

    test('whitespace-padded numeric string numerically matches (guard trims)', () {
      // num.tryParse(' 42 ') returns int 42 (Dart trims surrounding
      // whitespace; '42' is integer-valued). The round-trip guard compares
      // na.toString() ('42') against sa.trim() ('42') -> passes -> numeric
      // branch fires -> 42 == 42 -> true. Whitespace-padded numerics DO match;
      // this is a benign tolerance because production callers pre-trim both
      // operands before calling eq() (doc side: .toString().trim(); DSL side:
      // parsed value is .trim()'d), so padded input never occurs in practice.
      expect(eq(' 42 ', 42), true);
    });

    test('safe-integer guard: >15 char numeric string uses string compare', () {
      // 16 chars -> numeric branch skipped; string fallback still matches
      // identical digit strings (Dart int64 holds 16 digits exactly, so the
      // int operand's toString equals the string operand).
      expect(eq('1234567890123456', '1234567890123456'), true);
      expect(eq('1234567890123456', 1234567890123456), true);
    });

    test('13-digit epoch under 15-char limit works numerically', () {
      expect(eq('1782838800000', 1782838800000), true);
    });

    test('14-digit vid under 15-char limit works numerically', () {
      expect(eq('84214220504259', 84214220504259), true);
    });

    test('negative numbers work', () {
      expect(eq(-42, '-42'), true);
      expect(eq(-42, -42), true);
    });

    test('empty vs non-empty', () {
      expect(eq('', 'something'), false);
      expect(eq('', ''), true);
    });

    test('non-canonical numeric string skips numeric branch', () {
      // "00123" -> num.tryParse = 123 -> 123.toString() = "123" != "00123"
      // -> round-trip fails -> string compare: "00123" != "123" -> false
      expect(eq('00123', '123'), false);
      expect(eq('00123', 123), false);
    });
  });

  // ── CR-I1: epoch-as-double boundary (the REAL Firestore shape) ────────────
  //
  // The existing "Number" tests above feed a Dart `int` (e.g. 1782838800000),
  // which stringifies WITHOUT a decimal ("1782838800000") and therefore passes
  // under the OLD strict `==` too — so they do NOT actually exercise the fix.
  // The true production shape is a 13-digit epoch that Firestore returns as a
  // `double`, stringifying to "1782838800000.0" (exactly 15 chars — sitting ON
  // the `<= 15` guard boundary). These tests pin that boundary.

  group('eq() — CR-I1 epoch-as-double boundary', () {
    test('.0-double String (15 chars) matches clean int-String', () {
      // sa="1782838800000.0" (13 digits + ".0" = 15 chars) -> within <=15 guard.
      //   num.tryParse -> double 1782838800000.0, round-trips to "1782838800000.0".
      // sb="1782838800000" (13 chars) -> int 1782838800000, round-trips.
      // numeric branch: 1782838800000.0 == 1782838800000 -> true.
      expect(eq('1782838800000.0', '1782838800000'), true);
    });

    test('double operand (not String) stringifies to .0 and matches clean String', () {
      // a is a Dart double -> a.toString() == "1782838800000.0" (15 chars).
      expect(eq(1782838800000.0, '1782838800000'), true);
    });

    test('double operand matches int operand at epoch scale (both non-String)', () {
      // 1782838800000.0.toString()="1782838800000.0" (15) vs 1782838800000 -> true.
      expect(eq(1782838800000.0, 1782838800000), true);
    });

    test('REGRESSION TRIPWIRE: 15-char "1782838800000.0" must stay matched', () {
      // TRIPWIRE — do not delete. "1782838800000.0" is EXACTLY 15 chars and sits
      // on the `sa.trim().length <= 15` guard boundary. If a future edit weakens
      // `<= 15` to `< 15`, the numeric branch is skipped, the string fallback
      // runs ("1782838800000.0" != "1782838800000"), and this assertion flips to
      // false -> RED. That red is the whole point: it catches the silent
      // regression the int-sourced integration tests cannot.
      expect(eq('1782838800000.0', '1782838800000'), true);
    });

    test('boundary crossing: 13-digit .0 (15 chars) matches; 14-digit .0 (16 chars) string-compares', () {
      // 13 int digits + ".0" = 15 chars -> within guard -> numeric match -> true.
      expect(eq('1782838800000.0', '1782838800000'), true);
      // 14 int digits + ".0" = 16 chars -> exceeds guard -> string fallback ->
      // "17828388000000.0" != "17828388000000" -> false. The .0 tolerance is
      // deliberately LOST past 15 chars (int64/double precision protection).
      expect(eq('17828388000000.0', '17828388000000'), false);
    });
  });

  group('eq() — CR-I1 non-collision guards (tolerance must not over-match)', () {
    // The canonical id/enum guards already live in the §7 group above:
    //   leading-zero  eq('08886008101138','8886008101138') == false
    //   hex-ish id    eq('F621a02a983500','f621a02a983500') == false
    //   enum exact    eq('assigned','closed')               == false
    // These add the epoch-double-specific non-collision cases the NEW tolerance
    // introduces, so the .0 reconciliation can never silently over-match.
    test('.0-double epoch does NOT over-match a DIFFERENT epoch', () {
      // both parse & round-trip; numeric branch fires; 1782838800000.0 !=
      // 1782838800001 -> false. Tolerance reconciles TYPE, never VALUE.
      expect(eq('1782838800000.0', '1782838800001'), false);
    });

    test('fractional epoch does NOT match its integer floor', () {
      // "1782838800000.5" round-trips to itself; 1782838800000.5 != 1782838800000.
      expect(eq('1782838800000.5', '1782838800000'), false);
    });
  });

  // ── Integration-level tests: predicate functions with type-tolerant eq() ──

  group('filterByMultiClause type tolerance', () {
    // This test requires filterByMultiClause to import and use eq().
    // After Task 2 applies the fix, this test validates the end-to-end path.
    //
    // Note: filterByMultiClause is in driver_home_support.dart which
    // requires transactionStore for resolveDriverCurlyTokens. But
    // filterByMultiClause itself does NOT use transactionStore — it takes
    // pre-resolved conditions. So we can call it directly.
    test('§1 bug fix: String tdt matches Number-sourced todayEpoch', () {
      // Simulates: task doc has tdt as String, todayEpoch is String from int
      // The bug: if Firestore returns tdt as double, toString() adds ".0"
      // After fix, eq() handles this via numeric branch
      final docs = <Map<String, dynamic>>[
        {'vv': 'F621a02a983500', 'tdt': '1782838800000', 'tst': 'assigned'},
        {'vv': 'other', 'tdt': '1782838800000', 'tst': 'closed'},
      ];
      // Normal case: both sides String — always worked
      final r1 = filterByMultiClause(
        docs,
        'vv\u{25FC}F621a02a983500\u{2B58}tdt\u{25FC}1782838800000',
      );
      expect(r1.length, 1);
      expect(r1.first['vv'], 'F621a02a983500');
    });

    test('Number doc value matches String condition via eq()', () {
      // Doc has tdt as int (Firestore native write)
      final docs = <Map<String, dynamic>>[
        {'vv': 'F621a02a983500', 'tdt': 1782838800000},
      ];
      final r = filterByMultiClause(
        docs,
        'vv\u{25FC}F621a02a983500\u{2B58}tdt\u{25FC}1782838800000',
      );
      expect(r.length, 1);
    });

    test('enum field still matches exactly', () {
      final docs = <Map<String, dynamic>>[
        {'cst': 'custody_confirmed', 'cdt': '1782838800000'},
        {'cst': 'awaiting_custody', 'cdt': '1782838800000'},
      ];
      final r = filterByMultiClause(
        docs,
        'cst\u{25FC}custody_confirmed\u{2B58}cdt\u{25FC}1782838800000',
      );
      expect(r.length, 1);
      expect(r.first['cst'], 'custody_confirmed');
    });

    test('CR-I1 read path: DOUBLE tdt (real Firestore shape) matches String clause via eq()', () {
      // The genuine fix path. Firestore returns tdt as a double, so
      // (doc['tdt']).toString() == "1782838800000.0". Under the OLD strict `!=`
      // this doc was EXCLUDED (0 results); eq() reconciles the .0 -> 1 result.
      final docs = <Map<String, dynamic>>[
        {'tdt': 1782838800000.0}, // double, NOT int
      ];
      final r = filterByMultiClause(docs, 'tdt\u{25FC}1782838800000');
      expect(r.length, 1);
    });

    test('empty conditions -> all docs pass-through (no filter)', () {
      // Empty payload: filterByMultiClause returns docs unchanged (line 324).
      final docs = <Map<String, dynamic>>[
        {'tdt': '1782838800000'},
        {'tdt': '1782752400000'},
      ];
      final r = filterByMultiClause(docs, '');
      expect(r.length, 2);
    });

    test('malformed clause (no field-separator) skipped; valid clause still filters', () {
      // First clause has no U+25FC separator -> skipped (sep < 0); the second
      // clause still parses and filters. Proves partial-parse resilience.
      final docs = <Map<String, dynamic>>[
        {'vv': 'A', 'tdt': '1782838800000'},
        {'vv': 'B', 'tdt': '1782838800000'},
      ];
      final r = filterByMultiClause(docs, 'garbagenosep\u{2B58}vv\u{25FC}A');
      expect(r.length, 1);
      expect(r.first['vv'], 'A');
    });
  });

  group('buildVehicleFeed type tolerance', () {
    test('§1 B 1234X: task with String tdt matches todayEpoch', () {
      // After fix, buildVehicleFeed uses eq() for tdt comparison
      final stock = <Map<String, dynamic>>[
        {'lv': 'F621a02a983500', 'ln': 'B 1234X', 'dv': 'D1', 'dn': 'Driver'},
      ];
      final checks = <Map<String, dynamic>>[
        {
          'vv': 'F621a02a983500',
          'cty': 'opening',
          'cst': 'custody_confirmed',
          'cdt': '1782838800000',
        },
      ];
      // Task doc: tdt stored as String (from addEventRow)
      final tasks = <Map<String, dynamic>>[
        {
          'vv': 'F621a02a983500',
          'tdt': '1782838800000', // String
          'tst': 'assigned',
        },
      ];
      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: const {},
        todayEpoch: '1782838800000', // String from todayEpochMidnightWib()
      );
      // Vehicle should appear as inRoute (custody_confirmed + open task)
      expect(feed.length, 1);
      expect(feed.first.plate, 'B 1234X');
      expect(feed.first.tier, VehicleTier.inRoute);
      expect(feed.first.tasks.length, 1);
    });

    test('task with Number tdt matches todayEpoch via eq()', () {
      final stock = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'AB 1', 'dv': 'D1', 'dn': 'D'},
      ];
      final checks = <Map<String, dynamic>>[
        {'vv': 'V1', 'cty': 'opening', 'cst': 'custody_confirmed', 'cdt': '1782838800000'},
      ];
      // tdt stored as Number (from native write)
      final tasks = <Map<String, dynamic>>[
        {'vv': 'V1', 'tdt': 1782838800000, 'tst': 'assigned'},
      ];
      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: const {},
        todayEpoch: '1782838800000',
      );
      expect(feed.length, 1);
      expect(feed.first.tasks.length, 1);
    });

    test('completed tier cdt Number matches todayEpoch via eq()', () {
      final stock = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'AB 1', 'dv': 'D1', 'dn': 'D'},
      ];
      final checks = <Map<String, dynamic>>[
        {'vv': 'V1', 'cty': 'opening', 'cst': 'closed', 'cdt': 1782838800000},
        {'vv': 'V1', 'cty': 'closing'},
      ];
      final tasks = <Map<String, dynamic>>[];
      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: const {},
        todayEpoch: '1782838800000',
      );
      // Task 11: completed tier removed. closed opening + dv set -> loading.
      // (Number cdt vs String todayEpoch retained but no longer gates tier.)
      expect(feed.length, 1);
      expect(feed.first.tier, VehicleTier.loading);
    });

    test('completed tier cdt mismatch (different day) drops from feed', () {
      final stock = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'AB 1', 'dv': 'D1', 'dn': 'D'},
      ];
      final checks = <Map<String, dynamic>>[
        {'vv': 'V1', 'cty': 'opening', 'cst': 'closed', 'cdt': '1782752400000'},
        {'vv': 'V1', 'cty': 'closing'},
      ];
      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: const [],
        categoryMap: const {},
        todayEpoch: '1782838800000',
      );
      // Task 11: completed-drop removed. A closed opening whose vehicle still
      // has dv set now surfaces as loading backlog instead of being dropped.
      expect(feed.length, 1);
      expect(feed.first.tier, VehicleTier.loading);
    });

    test('CR-I1 §1 B 1234X (real shape): DOUBLE tdt matches todayEpoch -> inRoute with task', () {
      // The ACTUAL production bug path. Firestore returns task.tdt as a double,
      // so (tdt).toString() == "1782838800000.0". Under the OLD strict `==` the
      // task was dropped from tasksByVv -> vehicle fell to `returning` with 0
      // tasks; eq() reconciles the .0 -> task retained -> inRoute.
      final stock = <Map<String, dynamic>>[
        {'lv': 'F621a02a983500', 'ln': 'B 1234X', 'dv': 'D1', 'dn': 'Driver'},
      ];
      final checks = <Map<String, dynamic>>[
        {
          'vv': 'F621a02a983500',
          'cty': 'opening',
          'cst': 'custody_confirmed',
          'cdt': '1782838800000',
        },
      ];
      final tasks = <Map<String, dynamic>>[
        {'vv': 'F621a02a983500', 'tdt': 1782838800000.0, 'tst': 'assigned'}, // double
      ];
      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: tasks,
        categoryMap: const {},
        todayEpoch: '1782838800000',
      );
      expect(feed.length, 1);
      expect(feed.first.plate, 'B 1234X');
      expect(feed.first.tier, VehicleTier.inRoute);
      expect(feed.first.tasks.length, 1);
    });

    test('CR-I1 completed tier (E2): DOUBLE cdt (real shape) matches todayEpoch via eq()', () {
      // E2 path: opening cdt returned as a double -> "1782838800000.0".
      // Task 11: completed tier removed; closed opening + dv set -> loading.
      // (Double cdt retained but no longer gates tier.)
      final stock = <Map<String, dynamic>>[
        {'lv': 'V1', 'ln': 'AB 1', 'dv': 'D1', 'dn': 'D'},
      ];
      final checks = <Map<String, dynamic>>[
        {'vv': 'V1', 'cty': 'opening', 'cst': 'closed', 'cdt': 1782838800000.0}, // double
        {'vv': 'V1', 'cty': 'closing'},
      ];
      final feed = buildVehicleFeed(
        stockDocs: stock,
        vehicleCheckDocs: checks,
        taskDocs: const [],
        categoryMap: const {},
        todayEpoch: '1782838800000',
      );
      expect(feed.length, 1);
      expect(feed.first.tier, VehicleTier.loading);
    });
  });

  group('evaluateGate type tolerance', () {
    test('Number field value matches String gate value', () {
      final doc = <String, dynamic>{'tdt': 1782838800000, 'cst': 'assigned'};
      expect(
        evaluateGate(doc, 'tdt\u{25FC}1782838800000\u{2B58}cst\u{25FC}assigned'),
        true,
      );
    });

    test('String field value matches String gate value (unchanged)', () {
      final doc = <String, dynamic>{'tdt': '1782838800000'};
      expect(evaluateGate(doc, 'tdt\u{25FC}1782838800000'), true);
    });

    test('enum field still exact', () {
      final doc = <String, dynamic>{'cst': 'custody_confirmed'};
      expect(evaluateGate(doc, 'cst\u{25FC}awaiting_custody'), false);
    });

    test('CR-I1 §1 gate: DOUBLE field value (real shape) matches String gate via eq()', () {
      // doc.tdt returned as a double -> "1782838800000.0"; under the OLD strict
      // `!=` the gate failed, now eq() reconciles the .0.
      final doc = <String, dynamic>{'tdt': 1782838800000.0, 'cst': 'assigned'};
      expect(
        evaluateGate(doc, 'tdt\u{25FC}1782838800000\u{2B58}cst\u{25FC}assigned'),
        true,
      );
    });

    test('empty gate -> false (no gate = no match)', () {
      // Empty payload: evaluateGate returns false (line 415), NOT true.
      final doc = <String, dynamic>{'tdt': '1782838800000'};
      expect(evaluateGate(doc, ''), false);
    });

    test('malformed clause (no field-separator) skipped; valid clause still evaluated', () {
      // First clause lacks U+25FC -> skipped (sep < 0); the second clause
      // decides the result. Proves partial-parse resilience.
      final doc = <String, dynamic>{'cst': 'assigned'};
      expect(evaluateGate(doc, 'nosep\u{2B58}cst\u{25FC}assigned'), true);
      expect(evaluateGate(doc, 'nosep\u{2B58}cst\u{25FC}closed'), false);
    });
  });
}
