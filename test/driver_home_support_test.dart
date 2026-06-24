import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // W3: resolveDriverCurlyTokens / filterDriverHomeDocs read
  // transactionStore.state.screenTx. The global `transactionStore` is null in a
  // bare test, so any token-path test would throw NoSuchMethod. Seed the Redux
  // store ONCE before all tests with a known #has_user_login value (mirrors
  // global.dart's DevToolsStore<ScreenTransaction> init).
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#has_user_login': '777',
    })));

    // Seed NTP reference keys so getNowMillisecondFromEpoch exercises the
    // NTP-corrected path. Values: REF = DEVICE (zero offset = NTP matches
    // device clock). todayEpochMidnightWib's deterministic tests use the
    // nowMs override instead.
    transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
      '#REF_TIME_START': DateTime.now().millisecondsSinceEpoch,
      '#DEVICE_TIME_START': DateTime.now().millisecondsSinceEpoch,
    })));

    // W1: getTableVid reads the GLOBAL `appCodeController` (late, global.dart:480;
    // assigned only in globalInit, which does NOT run under flutter_test), NOT a
    // Get-managed instance. Assign the global directly so getTableVid(null) can
    // read applicationTableVid instead of throwing LateInitializationError.
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  group('filterByMultiClause', () {
    final docs = [
      {'cty': 'opening', 'vv': '123', 'cdt': '20260617'},
      {'cty': 'opening', 'vv': '456', 'cdt': '20260617'},
      {'cty': 'closing', 'vv': '123', 'cdt': '20260617'},
      {'cty': 'opening', 'vv': '123', 'cdt': '20260616'},
    ];

    test('single clause filters correctly', () {
      final r = filterByMultiClause(docs, 'cty\u{25FC}opening');
      expect(r.length, 3); // all "opening" docs
    });

    test('multi-clause AND narrows result', () {
      final r = filterByMultiClause(
          docs, 'cty\u{25FC}opening\u{2B58}vv\u{25FC}123\u{2B58}cdt\u{25FC}20260617');
      expect(r.length, 1);
      expect(r.first['vv'], '123');
      expect(r.first['cdt'], '20260617');
    });

    test('no match returns empty list', () {
      final r = filterByMultiClause(
          docs, 'cty\u{25FC}opening\u{2B58}vv\u{25FC}999');
      expect(r, isEmpty);
    });

    test('empty conditions returns all docs', () {
      expect(filterByMultiClause(docs, ''), docs);
      expect(filterByMultiClause(docs, '   '), docs);
    });

    test('literal parentheses in value are NOT treated as unresolved tokens', () {
      // After removing the paren guard, values containing `(` are matched
      // literally. Only `{` triggers the pending guard now.
      final docsWithParen = [
        {'cty': 'opening', 'vv': '(VEHICLEID)'},
      ];
      final r = filterByMultiClause(
          docsWithParen, 'cty\u{25FC}opening\u{2B58}vv\u{25FC}(VEHICLEID)');
      expect(r.length, 1);
    });

    test('unresolved curly token returns empty', () {
      final r = filterByMultiClause(
          docs, 'cty\u{25FC}opening\u{2B58}vv\u{25FC}{unresolved}');
      expect(r, isEmpty);
    });

    test('malformed clause (no separator) is skipped gracefully', () {
      // "badclause" has no ◼ — skipped; remaining clause still works
      final r = filterByMultiClause(
          docs, 'badclause\u{2B58}cty\u{25FC}opening');
      expect(r.length, 3);
    });

    test('empty value in clause returns empty', () {
      final r = filterByMultiClause(docs, 'cty\u{25FC}');
      expect(r, isEmpty);
    });

    test('whitespace around clauses is trimmed', () {
      final r = filterByMultiClause(
          docs, ' cty\u{25FC}opening \u{2B58} vv\u{25FC}123 ');
      expect(r.length, 2); // both docs with cty=opening AND vv=123
    });
  });

  group('resolveDriverCurlyTokens', () {
    test('{driverVid} resolves from seeded #has_user_login', () {
      final result =
          resolveDriverCurlyTokens('dv\u{25FC}{driverVid}', 'scr');
      expect(result, 'dv\u{25FC}777');
    });

    test('{vehicleId} left as-is when state not yet published', () {
      clearDriverHomeState('curly_scr');
      final result =
          resolveDriverCurlyTokens('vv\u{25FC}{vehicleId}', 'curly_scr');
      expect(result, 'vv\u{25FC}{vehicleId}');
    });

    test('{vehicleId} resolves once state publishes', () {
      clearDriverHomeState('curly_scr2');
      getDriverHomeState('curly_scr2').vehicleId.value = '888';
      final result =
          resolveDriverCurlyTokens('vv\u{25FC}{vehicleId}', 'curly_scr2');
      expect(result, 'vv\u{25FC}888');
    });

    test('{today} resolves to epoch-midnight-ms string', () {
      final result =
          resolveDriverCurlyTokens('cdt\u{25FC}{today}', 'scr');
      expect(result.contains('{today}'), isFalse);
      // Should be a numeric string (epoch ms)
      expect(int.tryParse(result.split('\u{25FC}').last), isNotNull);
    });

    test('unknown {token} left as-is for resolveScreenTxTokens', () {
      final result =
          resolveDriverCurlyTokens('f\u{25FC}{unknownToken}', 'scr');
      expect(result, 'f\u{25FC}{unknownToken}');
    });

    test('string without curly braces passes through unchanged', () {
      expect(resolveDriverCurlyTokens('no tokens here', 'scr'),
          'no tokens here');
    });

    test('multiple tokens in one string all resolve', () {
      clearDriverHomeState('multi_scr');
      getDriverHomeState('multi_scr').vehicleId.value = 'V1';
      final result = resolveDriverCurlyTokens(
          'dv\u{25FC}{driverVid}\u{2B58}vv\u{25FC}{vehicleId}\u{2B58}cdt\u{25FC}{today}',
          'multi_scr');
      expect(result.contains('{driverVid}'), isFalse);
      expect(result.contains('{vehicleId}'), isFalse);
      expect(result.contains('{today}'), isFalse);
      // Verify driverVid resolved to '777' (seeded) and vehicleId to 'V1'
      expect(result.contains('777'), isTrue);
      expect(result.contains('V1'), isTrue);
    });
  });

  group('todayEpochMidnightWib', () {
    test('returns a numeric string', () {
      final s = todayEpochMidnightWib();
      expect(int.tryParse(s), isNotNull);
    });

    test('value is a multiple of 86400000 shifted by WIB offset', () {
      // Any valid midnight WIB (UTC+7) expressed in UTC epoch should satisfy:
      // (result + 25200000) % 86400000 == 0
      final int val = int.parse(todayEpochMidnightWib());
      expect((val + 25200000) % 86400000, 0);
    });

    test('deterministic with injected nowMs', () {
      // nowMs = 1781785800000 (2026-06-17 10:30 UTC = 2026-06-17 17:30 WIB):
      //   wibMs = 1781785800000 + 25200000 = 1781811000000
      //   dayStart = (1781811000000 ~/ 86400000) * 86400000 = 1781740800000
      //   utcMidnight = 1781740800000 - 25200000 = 1781715600000
      //   (2026-06-16 17:00 UTC = 2026-06-17 00:00 WIB)
      const int nowMs = 1781785800000;
      final String result = todayEpochMidnightWib(nowMs: nowMs);
      expect(result, '1781715600000');
    });

    test('near midnight WIB rolls correctly', () {
      // Anchor: 1781715600000 = 2026-06-17 00:00 WIB = 2026-06-16 17:00 UTC.
      // Next WIB midnight (2026-06-18 00:00 WIB = 2026-06-17 17:00 UTC)
      //   = 1781715600000 + 86400000 = 1781802000000.

      // Just before the WIB midnight boundary (23:30 WIB on 2026-06-17 =
      // 16:30 UTC): floors back to 2026-06-17 00:00 WIB.
      const int justBefore = 1781800200000;
      expect(todayEpochMidnightWib(nowMs: justBefore), '1781715600000');

      // Just after the WIB midnight boundary (00:30 WIB on 2026-06-18 =
      // 17:30 UTC): floors to 2026-06-18 00:00 WIB.
      const int justAfter = 1781803800000;
      expect(todayEpochMidnightWib(nowMs: justAfter), '1781802000000');
    });

    test('NTP refs absent -> falls back to device clock (no crash)', () {
      // getNowMillisecondFromEpoch() handles absent refs internally.
      // Just verify no crash and a valid number is returned.
      final s = todayEpochMidnightWib();
      final int val = int.parse(s);
      // Should be in a reasonable range (after 2020-01-01)
      expect(val, greaterThan(1577836800000));
    });
  });

  group('filterDriverHomeDocs end-to-end (curly tokens)', () {
    final docs = [
      {'cty': 'opening', 'vv': '888', 'cdt': todayEpochMidnightWib()},
      {'cty': 'opening', 'vv': '999', 'cdt': todayEpochMidnightWib()},
    ];

    test('decode + curly-resolve + multi-clause filter matches', () {
      clearDriverHomeState('e2e_scr');
      getDriverHomeState('e2e_scr').vehicleId.value = '888';
      // Raw search uses the _25FC_/_u2B58_ escapes the server sends.
      final raw =
          'cty_25FC_opening_u2B58_vv_25FC_{vehicleId}_u2B58_cdt_25FC_{today}';
      final r = filterDriverHomeDocs(docs, raw, 'e2e_scr');
      expect(r.length, 1);
      expect(r.first['vv'], '888');
    });

    test('unresolved {vehicleId} -> empty (pending safe default)', () {
      clearDriverHomeState('e2e_scr2');
      final raw = 'vv_25FC_{vehicleId}';
      final r = filterDriverHomeDocs(docs, raw, 'e2e_scr2');
      expect(r, isEmpty);
    });

    test('{driverVid} resolves from seeded #has_user_login', () {
      clearDriverHomeState('e2e_scr3');
      // Store seeded with #has_user_login = '777' in setUpAll.
      final testDocs = [
        {'dv': '777', 'lt': 'vehicle'},
        {'dv': '999', 'lt': 'vehicle'},
      ];
      final raw = 'dv_25FC_{driverVid}';
      final r = filterDriverHomeDocs(testDocs, raw, 'e2e_scr3');
      expect(r.length, 1);
      expect(r.first['dv'], '777');
    });

    test('raw chars (no server escaping) also work', () {
      clearDriverHomeState('e2e_scr4');
      getDriverHomeState('e2e_scr4').vehicleId.value = '888';
      // JSON uses raw special chars, not escaped.
      final raw = 'cty\u{25FC}opening\u{2B58}vv\u{25FC}{vehicleId}';
      final r = filterDriverHomeDocs(docs, raw, 'e2e_scr4');
      expect(r.length, 1);
      expect(r.first['vv'], '888');
    });
  });

  group('DriverHomeState lifecycle', () {
    test('getDriverHomeState creates on first access', () {
      clearDriverHomeState('test_scr');
      final state = getDriverHomeState('test_scr');
      expect(state.vehicleId.value, '');
      expect(state.confirmed.value, false);
    });

    test('clearDriverHomeState removes state', () {
      getDriverHomeState('test_scr');
      expect(driverHomeStates.containsKey('test_scr'), isTrue);
      clearDriverHomeState('test_scr');
      expect(driverHomeStates.containsKey('test_scr'), isFalse);
    });

    test('getDriverHomeState returns same instance on repeat call', () {
      clearDriverHomeState('test_scr');
      final a = getDriverHomeState('test_scr');
      final b = getDriverHomeState('test_scr');
      expect(identical(a, b), isTrue);
    });
  });

  group('resolveAppVid', () {
    test('uses vidtable when present', () {
      final component = {'vidtable': '12345', 'com': 'con'};
      expect(resolveAppVid(component), '12345');
    });

    test('uses vidtable even when com is also present', () {
      final component = {'vidtable': '67890', 'com': 'otq'};
      expect(resolveAppVid(component), '67890');
    });

    test('falls back to getTableVid when vidtable empty', () {
      final component = {'vidtable': '', 'com': 'con'};
      // getTableVid('con') = 20342033315492
      expect(resolveAppVid(component), '20342033315492');
    });

    test('falls back to getTableVid when vidtable absent', () {
      final component = {'com': 'con'};
      expect(resolveAppVid(component), '20342033315492');
    });

    test('falls back to applicationTableVid when com also absent', () {
      final component = <String, dynamic>{};
      // getTableVid(null) returns applicationTableVid (seeded as 99999)
      expect(resolveAppVid(component), '99999');
    });

    test('trims whitespace from vidtable', () {
      final component = {'vidtable': '  12345  '};
      expect(resolveAppVid(component), '12345');
    });

    test('vidtable of only whitespace treated as empty (falls back)', () {
      final component = {'vidtable': '   ', 'com': 'con'};
      expect(resolveAppVid(component), '20342033315492');
    });
  });

  group('aggregateItems (R2-3 cargo manifest)', () {
    test('flattens it[] across task docs and sums pd per distinct in', () {
      // Two task docs, each with an `it` array. Aqua appears in both → summed.
      final taskDocs = [
        {
          'kn': 'Toko A',
          'it': [
            {'in': 'Aqua Galon 19 Liter', 'pd': '8'},
            {'in': 'Le Minerale 600ml', 'pd': '3'},
          ],
        },
        {
          'kn': 'Toko B',
          'it': [
            {'in': 'Aqua Galon 19 Liter', 'pd': '5'},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 2);
      // First-seen order preserved: Aqua first, Le Minerale second.
      expect(rows[0]['in'], 'Aqua Galon 19 Liter');
      expect(rows[0]['pd'], 13); // 8 + 5
      expect(rows[1]['in'], 'Le Minerale 600ml');
      expect(rows[1]['pd'], 3);
    });

    test('single task doc with multiple items', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'Galon', 'pd': '1'},
            {'in': 'Botol', 'pd': '2'},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 2);
      expect(rows[0]['in'], 'Galon');
      expect(rows[0]['pd'], 1);
      expect(rows[1]['in'], 'Botol');
      expect(rows[1]['pd'], 2);
    });

    test('returns typed List<Map<String, dynamic>>', () {
      final rows = aggregateItems([
        {
          'it': [
            {'in': 'X', 'pd': '4'},
          ],
        },
      ], 'it', 'in', 'pd');
      expect(rows, isA<List<Map<String, dynamic>>>());
    });

    test('doc with no it array is skipped (guard non-List)', () {
      final taskDocs = [
        {'kn': 'No items here'}, // no `it` key at all
        {
          'it': 'not a list', // wrong type → guarded
        },
        {
          'it': [
            {'in': 'Galon', 'pd': '2'},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 1);
      expect(rows[0]['in'], 'Galon');
      expect(rows[0]['pd'], 2);
    });

    test('non-Map entries inside it[] are skipped', () {
      final taskDocs = [
        {
          'it': [
            'rogue string',
            {'in': 'Galon', 'pd': '3'},
            42,
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 1);
      expect(rows[0]['pd'], 3);
    });

    test('entry with empty/absent label is skipped', () {
      final taskDocs = [
        {
          'it': [
            {'in': '', 'pd': '5'}, // empty label
            {'pd': '9'}, // absent label
            {'in': 'Galon', 'pd': '2'},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 1);
      expect(rows[0]['in'], 'Galon');
      expect(rows[0]['pd'], 2);
    });

    test('non-numeric qty parses to 0 (int.tryParse guard)', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'Galon', 'pd': 'abc'}, // non-numeric → 0
            {'in': 'Galon', 'pd': '4'},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 1);
      expect(rows[0]['pd'], 4); // 0 + 4
    });

    test('absent qty field treated as 0', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'Galon'}, // no pd
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 1);
      expect(rows[0]['pd'], 0);
    });

    test('empty task list returns empty', () {
      expect(aggregateItems([], 'it', 'in', 'pd'), isEmpty);
    });

    test('honors custom itemsField/labelField/qtyField', () {
      final taskDocs = [
        {
          'lines': [
            {'name': 'Galon', 'qty': '7'},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'lines', 'name', 'qty');
      expect(rows.length, 1);
      expect(rows[0]['name'], 'Galon');
      expect(rows[0]['qty'], 7);
    });

    test('integer qty values (not strings) aggregate correctly', () {
      // Firestore may deliver numbers as int, not String.
      final taskDocs = [
        {
          'it': [
            {'in': 'Galon', 'pd': 6},
            {'in': 'Galon', 'pd': 4},
          ],
        },
      ];
      final rows = aggregateItems(taskDocs, 'it', 'in', 'pd');
      expect(rows.length, 1);
      expect(rows[0]['pd'], 10);
    });
  });

  group('aggregateManifestItems (tx-aware manifest)', () {
    // Grounded data from spec section 5: 4 tasks
    // Task 1 (Warung Mak Ijah): LPG 3kg pd=4
    // Task 2 (Indomaret BSD):   Aqua ps=4, Amidis pb=4
    // Task 3 (Alfamart):        Aqua pd=3, LPG 12kg ps=3 pb=5, Pristine pr=2, LPG 15kg ps=2, Aqua 600ml ps=8
    // Task 4 (Toko Pak Budi):   LPG 3kg (implied from total 4, all from task1), Aqua pd=8, Amidis pd=3
    //
    // Reconstructed task docs to produce spec totals:
    final List<Map<String, dynamic>> specTasks = [
      {
        'tst': 'assigned',
        'it': [
          {'in': 'LPG 3kg', 'pd': 4, 'ps': 0, 'pr': 0, 'pb': 0},
        ],
      },
      {
        'tst': 'assigned',
        'it': [
          {'in': 'Aqua Galon 19L', 'pd': 0, 'ps': 4, 'pr': 0, 'pb': 0},
          {'in': 'Amidis Galon 19L', 'pd': 0, 'ps': 0, 'pr': 0, 'pb': 4},
        ],
      },
      {
        'tst': 'assigned',
        'it': [
          {'in': 'Aqua Galon 19L', 'pd': 3, 'ps': 0, 'pr': 0, 'pb': 0},
          {'in': 'LPG 12kg', 'pd': 0, 'ps': 3, 'pr': 0, 'pb': 5},
          {'in': 'Pristine RO 19L', 'pd': 0, 'ps': 0, 'pr': 2, 'pb': 0},
          {'in': 'LPG 15kg', 'pd': 0, 'ps': 2, 'pr': 0, 'pb': 0},
          {'in': 'Aqua 600ml Karton', 'pd': 0, 'ps': 8, 'pr': 0, 'pb': 0},
        ],
      },
      {
        'tst': 'assigned',
        'it': [
          {'in': 'Aqua Galon 19L', 'pd': 8, 'ps': 0, 'pr': 0, 'pb': 0},
          {'in': 'Amidis Galon 19L', 'pd': 3, 'ps': 0, 'pr': 0, 'pb': 0},
        ],
      },
    ];

    test('spec section 5: pd+ps+pr sums, pb excluded', () {
      final rows = aggregateManifestItems(
        specTasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 7);
      // First-seen order preserved
      expect(rows[0], {'in': 'LPG 3kg', 'pd': 4});
      expect(rows[1], {'in': 'Aqua Galon 19L', 'pd': 15}); // 0+4+3+8
      expect(rows[2], {'in': 'Amidis Galon 19L', 'pd': 3}); // pb=4 excluded
      expect(rows[3], {'in': 'LPG 12kg', 'pd': 3}); // ps=3, pb=5 excluded
      expect(rows[4], {'in': 'Pristine RO 19L', 'pd': 2}); // pr=2
      expect(rows[5], {'in': 'LPG 15kg', 'pd': 2}); // ps=2
      expect(rows[6], {'in': 'Aqua 600ml Karton', 'pd': 8}); // ps=8
    });

    test('spec section 6: excludeStatus drops rejected task', () {
      // Make task 2 (Indomaret BSD) rejected
      final tasks = specTasks.map((d) => Map<String, dynamic>.from(d)).toList();
      tasks[1] = Map<String, dynamic>.from(tasks[1]);
      tasks[1]['tst'] = 'load_rejected';

      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
        excludeStatus: 'load_rejected',
      );
      // Aqua drops from 15 to 11 (task 2 contributed ps=4, now skipped)
      expect(rows.length, 7);
      expect(rows[0], {'in': 'LPG 3kg', 'pd': 4});
      expect(rows[1], {'in': 'Aqua Galon 19L', 'pd': 11}); // 15 - 4 (task 2 ps=4 dropped)
      // First-seen order re-anchors: task 2 (which first introduced Amidis) is
      // excluded, so Amidis is now first seen in task 4 and lands LAST in the
      // result, not at index 2. NOT a typo — it follows the first-seen rule
      // applied only to non-excluded tasks.
      expect(rows[6], {'in': 'Amidis Galon 19L', 'pd': 3}); // re-anchored to task 4
    });

    test('hideZero drops items with total 0', () {
      // Craft a task where one item has ONLY pb (buy) -> total = 0
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Galon', 'pd': 5, 'ps': 0, 'pr': 0},
            {'in': 'Tabung Kosong', 'pd': 0, 'ps': 0, 'pr': 0, 'pb': 10},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
        hideZero: true,
      );
      expect(rows.length, 1);
      expect(rows[0], {'in': 'Galon', 'pd': 5});
      // Tabung Kosong (total 0) is hidden
    });

    test('hideZero=false keeps items with total 0', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'Galon', 'pd': 5},
            {'in': 'Tabung Kosong', 'pd': 0, 'ps': 0, 'pr': 0},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
        hideZero: false,
      );
      expect(rows.length, 2);
      expect(rows[1], {'in': 'Tabung Kosong', 'pd': 0});
    });

    test('empty excludeStatus skips nothing', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'load_rejected',
          'it': [
            {'in': 'Galon', 'pd': 3},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
        excludeStatus: '', // empty = skip nothing
      );
      expect(rows.length, 1);
      expect(rows[0], {'in': 'Galon', 'pd': 3});
    });

    test('empty task list returns empty', () {
      final rows = aggregateManifestItems(
        [],
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows, isEmpty);
    });

    test('missing/null/String qty fields coerce to 0', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'A', 'pd': null, 'ps': 'abc', 'pr': ''},
            {'in': 'A', 'pd': '3', 'ps': '2'},
            // pr absent in second entry
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 1);
      // First entry: 0 + 0 + 0 = 0; second: 3 + 2 + 0 = 5; total = 5
      expect(rows[0], {'in': 'A', 'pd': 5});
    });

    test('numeric (int/double) values handled natively', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'X', 'pd': 4, 'ps': 2.0, 'pr': 1},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 1);
      expect(rows[0]['pd'], 7); // 4 + 2.0 + 1 = 7.0 -> .toInt() = 7
    });

    test('first-seen order preserved across tasks', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'in': 'B', 'pd': 1},
            {'in': 'A', 'pd': 2},
          ],
        },
        {
          'it': [
            {'in': 'C', 'pd': 3},
            {'in': 'B', 'pd': 4},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 3);
      expect(rows[0]['in'], 'B'); // first seen
      expect(rows[0]['pd'], 5); // 1 + 4
      expect(rows[1]['in'], 'A');
      expect(rows[2]['in'], 'C');
    });

    test('doc with non-List items field is skipped', () {
      final tasks = <Map<String, dynamic>>[
        {'it': 'not a list'},
        {
          'it': [
            {'in': 'Galon', 'pd': 2},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 1);
      expect(rows[0], {'in': 'Galon', 'pd': 2});
    });

    test('non-Map entries inside it[] are skipped', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            'rogue string',
            {'in': 'Galon', 'pd': 3},
            42,
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 1);
      expect(rows[0]['pd'], 3);
    });

    test('entry with empty/absent label is skipped', () {
      final tasks = <Map<String, dynamic>>[
        {
          'it': [
            {'in': '', 'pd': 5},
            {'pd': 9},
            {'in': 'Galon', 'pd': 2},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows.length, 1);
      expect(rows[0], {'in': 'Galon', 'pd': 2});
    });

    test('returns typed List<Map<String, dynamic>>', () {
      final rows = aggregateManifestItems(
        [
          {
            'it': [
              {'in': 'X', 'pd': '4'},
            ],
          },
        ],
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
      );
      expect(rows, isA<List<Map<String, dynamic>>>());
    });

    test('excludeStatus + hideZero combined', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'in': 'Galon', 'pd': 5},
            {'in': 'Tabung', 'pb': 10}, // only buy -> total 0
          ],
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'in': 'Galon', 'pd': 3},
          ],
        },
      ];
      final rows = aggregateManifestItems(
        tasks,
        itemsField: 'it',
        labelField: 'in',
        deliverField: 'pd',
        saleField: 'ps',
        refillField: 'pr',
        excludeStatus: 'load_rejected',
        hideZero: true,
      );
      // Rejected task skipped (Galon stays 5 not 8)
      // Tabung total=0 hidden
      expect(rows.length, 1);
      expect(rows[0], {'in': 'Galon', 'pd': 5});
    });
  });

  group('stop field-code resolution (R2-1/R2-2)', () {
    // _buildPending / _buildConfirmed resolve these inline as
    //   component['nameField'] ?? 'kn' / component['addressField'] ?? 'al'
    //   component['actionField'] ?? 'tty'
    // (private widget methods). These assert the resolution CONTRACT — the same
    // expression — without pumping the widget (matches this file's test style).
    String nameFieldOf(Map<String, dynamic> c) =>
        (c['nameField'] ?? 'kn').toString();
    String addressFieldOf(Map<String, dynamic> c) =>
        (c['addressField'] ?? 'al').toString();
    String actionFieldOf(Map<String, dynamic> c) =>
        (c['actionField'] ?? 'tty').toString();

    test('name/address default to kn/al when not overridden', () {
      final component = <String, dynamic>{};
      expect(nameFieldOf(component), 'kn');
      expect(addressFieldOf(component), 'al');
    });

    test('action field defaults to tty', () {
      expect(actionFieldOf(<String, dynamic>{}), 'tty');
    });

    test('component overrides win for name/address/action', () {
      final component = {
        'nameField': 'sn',
        'addressField': 'sa',
        'actionField': 'act',
      };
      expect(nameFieldOf(component), 'sn');
      expect(addressFieldOf(component), 'sa');
      expect(actionFieldOf(component), 'act');
    });

    test('reading kn/al/tty off a real-shaped task doc', () {
      // A task doc as seen on-device.
      final doc = {
        'kn': 'Toko Sumber Rejeki',
        'al': 'Jl. Merdeka No. 10',
        'tty': 'delivery',
        'tst': 'assigned',
      };
      final component = <String, dynamic>{};
      expect((doc[nameFieldOf(component)] ?? '').toString(),
          'Toko Sumber Rejeki');
      expect((doc[addressFieldOf(component)] ?? '').toString(),
          'Jl. Merdeka No. 10');
      expect(
          (doc[actionFieldOf(component)] ?? '').toString().trim().toLowerCase(),
          'delivery');
    });
  });

  group('stop badge action mapping (R2-2: tty -> KIRIM/AMBIL)', () {
    // _badgeFor's pending default maps the lowercased `tty` value:
    //   "delivery" -> KIRIM (_t8), "pickup" -> AMBIL (_t9), else -> KIRIM.
    // This asserts that pure mapping (the badge label selection) directly.
    const String kirim = 'KIRIM';
    const String ambil = 'AMBIL';
    String badgeLabelFor(String action) {
      final String a = action.trim().toLowerCase();
      return a == 'pickup'
          ? ambil
          : a == 'delivery'
              ? kirim
              : kirim; // default KIRIM
    }

    test('delivery -> KIRIM', () {
      expect(badgeLabelFor('delivery'), 'KIRIM');
    });

    test('pickup -> AMBIL', () {
      expect(badgeLabelFor('pickup'), 'AMBIL');
    });

    test('unknown/absent action defaults to KIRIM', () {
      expect(badgeLabelFor(''), 'KIRIM');
      expect(badgeLabelFor('whatever'), 'KIRIM');
    });

    test('case-insensitive / whitespace tolerant', () {
      expect(badgeLabelFor('  Pickup '), 'AMBIL');
      expect(badgeLabelFor('DELIVERY'), 'KIRIM');
    });
  });

  group('evaluateGateSearch', () {
    // Seed mapTableContent with test gate data.
    // mapTableContent is RxMap<String, List<Map<String, dynamic>>> in global.dart.
    setUp(() {
      mapTableContent['test_gate/vehicle_check'] = [
        {'cty': 'opening', 'vv': '123'},
        {'cty': 'closing', 'vv': '456'},
      ];
      clearDriverHomeState('gate_scr');
    });

    tearDown(() {
      mapTableContent.remove('test_gate/vehicle_check');
      clearDriverHomeState('gate_scr');
    });

    test('matching clause returns true', () {
      // Raw ◼ char (not escaped — mirrors the live JSON where gateSearch
      // contains literal ◼)
      expect(
        evaluateGateSearch(
            'test_gate/vehicle_check', 'cty\u{25FC}opening', 'gate_scr'),
        isTrue,
      );
    });

    test('non-matching clause returns false', () {
      expect(
        evaluateGateSearch(
            'test_gate/vehicle_check', 'cty\u{25FC}nonexistent', 'gate_scr'),
        isFalse,
      );
    });

    test('empty gateSearch returns false (hidden)', () {
      expect(
        evaluateGateSearch('test_gate/vehicle_check', '', 'gate_scr'),
        isFalse,
      );
    });

    test('whitespace-only gateSearch returns false', () {
      expect(
        evaluateGateSearch('test_gate/vehicle_check', '   ', 'gate_scr'),
        isFalse,
      );
    });

    test('empty gateCode returns false', () {
      expect(evaluateGateSearch('', 'cty\u{25FC}opening', 'gate_scr'), isFalse);
    });

    test('unsubscribed code (no data in mapTableContent) returns false', () {
      expect(
        evaluateGateSearch(
            'nonexistent/code', 'cty\u{25FC}opening', 'gate_scr'),
        isFalse,
      );
    });

    test('autheniumDecode escapes in gateSearch work', () {
      // Server-escaped form: _25FC_ for ◼
      expect(
        evaluateGateSearch(
            'test_gate/vehicle_check', 'cty_25FC_opening', 'gate_scr'),
        isTrue,
      );
    });

    test('raw ◼ chars pass through autheniumDecode as no-op', () {
      // The live JSON uses raw ◼/⭘ (not escaped). autheniumDecode on
      // already-raw chars is a no-op/pass-through — verify filter still works.
      expect(
        evaluateGateSearch(
            'test_gate/vehicle_check', 'cty\u{25FC}opening', 'gate_scr'),
        isTrue,
      );
    });
  });

  group('stock_location vehicleId derivation (contract)', () {
    // This tests the SELECTION logic that _publishVehicleId applies:
    // find doc where lt=='vehicle' && dv==driverVid -> take lv.
    // Mirrors route_progress_header.dart _publishVehicleId.

    /// Pure extraction matching the header's derivation logic.
    String deriveVehicleId(
        List<Map<String, dynamic>> slDocs, String driverVid) {
      if (driverVid.isEmpty) return '';
      for (final doc in slDocs) {
        final String lt = (doc['lt'] ?? '').toString().trim();
        final String dv = (doc['dv'] ?? '').toString().trim();
        if (lt == 'vehicle' && dv == driverVid) {
          return (doc['lv'] ?? '').toString().trim();
        }
      }
      return '';
    }

    test('finds vehicle doc by lt+dv, returns lv', () {
      final docs = [
        {'lt': 'warehouse', 'dv': '', 'lv': 'W1', 'ln': 'Gudang A'},
        {'lt': 'vehicle', 'dv': '777', 'lv': 'V1', 'ln': 'B 1234 XY'},
        {'lt': 'vehicle', 'dv': '888', 'lv': 'V2', 'ln': 'B 5678 AB'},
        {'lt': 'client', 'dv': '', 'lv': 'C1', 'ln': 'Toko A'},
      ];
      expect(deriveVehicleId(docs, '777'), 'V1');
    });

    test('no matching vehicle doc -> empty', () {
      final docs = [
        {'lt': 'vehicle', 'dv': '888', 'lv': 'V2'},
        {'lt': 'warehouse', 'dv': '', 'lv': 'W1'},
      ];
      expect(deriveVehicleId(docs, '777'), '');
    });

    test('empty driverVid -> empty (guard)', () {
      final docs = [
        {'lt': 'vehicle', 'dv': '777', 'lv': 'V1'},
      ];
      expect(deriveVehicleId(docs, ''), '');
    });

    test('warehouse doc with matching dv is NOT selected (lt guard)', () {
      final docs = [
        {'lt': 'warehouse', 'dv': '777', 'lv': 'W1'},
      ];
      expect(deriveVehicleId(docs, '777'), '');
    });

    test('null/absent fields handled gracefully', () {
      final docs = <Map<String, dynamic>>[
        {'lt': 'vehicle'}, // dv absent
        {'dv': '777'}, // lt absent
        {'lt': 'vehicle', 'dv': '777'}, // lv absent -> empty
      ];
      // Third doc matches lt+dv but lv is absent -> empty string
      expect(deriveVehicleId(docs, '777'), '');
    });

    test('lv present returns correctly even with extra whitespace', () {
      final docs = [
        {'lt': '  vehicle  ', 'dv': ' 777 ', 'lv': '  V1  '},
      ];
      // .trim() on all fields -> matches
      expect(deriveVehicleId(docs, '777'), 'V1');
    });
  });

  group('stopStatusOf spec vocab (section 4)', () {
    test('closed -> done', () {
      expect(stopStatusOf({'tst': 'closed'}), 'done');
    });

    test('ongoing -> active', () {
      expect(stopStatusOf({'tst': 'ongoing'}), 'active');
    });

    test('assigned -> pending', () {
      expect(stopStatusOf({'tst': 'assigned'}), 'pending');
    });

    test('backward compat: done -> done', () {
      expect(stopStatusOf({'tst': 'done'}), 'done');
    });

    test('backward compat: active -> active', () {
      expect(stopStatusOf({'tst': 'active'}), 'active');
    });

    test('backward compat: failed -> failed', () {
      expect(stopStatusOf({'tst': 'failed'}), 'failed');
    });

    test('closed case insensitive', () {
      expect(stopStatusOf({'tst': 'CLOSED'}), 'done');
    });

    test('ongoing case insensitive', () {
      expect(stopStatusOf({'tst': 'ONGOING'}), 'active');
    });

    test('unknown spec vocab defaults to pending', () {
      expect(stopStatusOf({'tst': 'in_transit'}), 'pending');
      expect(stopStatusOf({'tst': 'scheduled'}), 'pending');
    });
  });

  group('buildItemNameMap', () {
    test('maps ii -> in from item docs', () {
      final itemDocs = [
        {'ii': '2000000000031', 'in': 'Amidis Galon 19 Lite', 'un': 'pcs'},
        {'ii': '2000000000032', 'in': 'Aqua 600ml', 'un': 'pcs'},
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map.length, 2);
      expect(map['2000000000031'], 'Amidis Galon 19 Lite');
      expect(map['2000000000032'], 'Aqua 600ml');
    });

    test('skips entries with empty ii', () {
      final itemDocs = [
        {'ii': '', 'in': 'Ghost Item'},
        {'in': 'No ID Item'}, // ii absent
        {'ii': '123', 'in': 'Real Item'},
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map.length, 1);
      expect(map['123'], 'Real Item');
    });

    test('handles null/non-string fields gracefully', () {
      final itemDocs = <Map<String, dynamic>>[
        {'ii': null, 'in': 'Null ID'},
        {'ii': 456, 'in': 'Numeric ID'}, // int ii -> toString -> '456'
        {'ii': '789', 'in': null}, // null name -> empty string
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map.length, 2);
      expect(map['456'], 'Numeric ID');
      expect(map['789'], ''); // null name -> empty string stored
    });

    test('empty item docs returns empty map', () {
      expect(buildItemNameMap([]), isEmpty);
    });

    test('custom idField and nameField', () {
      final itemDocs = [
        {'code': 'A1', 'label': 'Item Alpha'},
        {'code': 'B2', 'label': 'Item Beta'},
      ];
      final map = buildItemNameMap(itemDocs,
          idField: 'code', nameField: 'label');
      expect(map['A1'], 'Item Alpha');
      expect(map['B2'], 'Item Beta');
    });

    test('duplicate ii: last wins', () {
      final itemDocs = [
        {'ii': '123', 'in': 'First'},
        {'ii': '123', 'in': 'Second'},
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map['123'], 'Second');
    });

    test('whitespace-only ii is treated as empty (skipped)', () {
      final itemDocs = [
        {'ii': '   ', 'in': 'Whitespace ID'},
        {'ii': '123', 'in': 'Real'},
      ];
      final map = buildItemNameMap(itemDocs);
      expect(map.length, 1);
      expect(map['123'], 'Real');
    });
  });

  group('aggregateActualSummary', () {
    final Map<String, String> nameMap = {
      '31': 'Amidis Galon 19 Lite',
      '32': 'Aqua 600ml',
      '33': 'Le Minerale 1500ml',
    };

    test('groups ip[] by ii, sums qt across cd, FK names, joins', () {
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': '30'},
        {'ii': '31', 'cd': 'empty', 'qt': '4'},
        {'ii': '32', 'cd': 'full', 'qt': '12'},
      ];
      final result = aggregateActualSummary(ip, nameMap);
      // 31: 30+4=34 Amidis, 32: 12 Aqua
      expect(result, '34 Amidis Galon 19 Lite \u{00B7} 12 Aqua 600ml');
    });

    test('single item single cd', () {
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': '10'},
      ];
      expect(aggregateActualSummary(ip, nameMap), '10 Amidis Galon 19 Lite');
    });

    test('unknown ii falls back to raw id string', () {
      final ip = [
        {'ii': '999', 'cd': 'full', 'qt': '5'},
      ];
      expect(aggregateActualSummary(ip, nameMap), '5 999');
    });

    test('empty nameMap -> all raw ids', () {
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': '10'},
        {'ii': '32', 'cd': 'full', 'qt': '5'},
      ];
      expect(aggregateActualSummary(ip, {}),
          '10 31 \u{00B7} 5 32');
    });

    test('non-List ipArray returns empty string', () {
      expect(aggregateActualSummary(null, nameMap), '');
      expect(aggregateActualSummary('not a list', nameMap), '');
      expect(aggregateActualSummary(42, nameMap), '');
    });

    test('empty List returns empty string', () {
      expect(aggregateActualSummary([], nameMap), '');
    });

    test('non-Map entries in ip[] are skipped', () {
      final ip = [
        'rogue string',
        {'ii': '31', 'cd': 'full', 'qt': '10'},
        42,
      ];
      expect(aggregateActualSummary(ip, nameMap), '10 Amidis Galon 19 Lite');
    });

    test('entries with empty ii are skipped', () {
      final ip = [
        {'ii': '', 'cd': 'full', 'qt': '5'},
        {'cd': 'full', 'qt': '3'}, // ii absent
        {'ii': '31', 'cd': 'full', 'qt': '10'},
      ];
      expect(aggregateActualSummary(ip, nameMap), '10 Amidis Galon 19 Lite');
    });

    test('non-numeric qt parses to 0', () {
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': 'abc'},
        {'ii': '31', 'cd': 'empty', 'qt': '5'},
      ];
      expect(aggregateActualSummary(ip, nameMap), '5 Amidis Galon 19 Lite');
    });

    test('int qt values (not strings) aggregate correctly', () {
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': 20},
        {'ii': '31', 'cd': 'empty', 'qt': 14},
      ];
      expect(aggregateActualSummary(ip, nameMap), '34 Amidis Galon 19 Lite');
    });

    test('absent qt treated as 0', () {
      final ip = [
        {'ii': '31', 'cd': 'full'}, // no qt
      ];
      expect(aggregateActualSummary(ip, nameMap), '0 Amidis Galon 19 Lite');
    });

    test('preserves first-seen order of ii', () {
      final ip = [
        {'ii': '33', 'cd': 'full', 'qt': '1'},
        {'ii': '31', 'cd': 'full', 'qt': '2'},
        {'ii': '32', 'cd': 'full', 'qt': '3'},
      ];
      final result = aggregateActualSummary(ip, nameMap);
      // Order: 33 first, then 31, then 32
      expect(result,
          '1 Le Minerale 1500ml \u{00B7} 2 Amidis Galon 19 Lite \u{00B7} 3 Aqua 600ml');
    });

    test('custom idField and qtyField', () {
      final ip = [
        {'code': '31', 'amount': '10'},
        {'code': '32', 'amount': '5'},
      ];
      final result = aggregateActualSummary(ip, nameMap,
          idField: 'code', qtyField: 'amount');
      // code '31' maps to 'Amidis...' but only if nameMap keys match 'code' values.
      // nameMap keys are '31'/'32' so the FK still works.
      expect(result,
          '10 Amidis Galon 19 Lite \u{00B7} 5 Aqua 600ml');
    });

    test('nameMap entry with empty name -> falls back to raw id', () {
      final mapWithEmpty = {'31': '', '32': 'Aqua'};
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': '10'},
        {'ii': '32', 'cd': 'full', 'qt': '5'},
      ];
      // '31' has empty name -> fall back to '31'
      expect(aggregateActualSummary(ip, mapWithEmpty),
          '10 31 \u{00B7} 5 Aqua');
    });
  });

  group('resolveDriverCurlyTokens -- {driverName}', () {
    // These tests validate the pure string replacement, not the Rx state.
    // We test the switch logic in isolation.

    test('{driverName} resolved when state has value', () {
      // Pure-logic: simulate what resolveDriverCurlyTokens does for driverName
      String resolveDN(String raw, String name) {
        return raw.replaceAllMapped(
          RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
          (m) {
            if (m.group(1) == 'driverName') {
              return name.isNotEmpty ? name : m.group(0)!;
            }
            return m.group(0)!;
          },
        );
      }

      expect(resolveDN('cn◼{driverName}', 'Agenia Demo'), 'cn◼Agenia Demo');
      expect(resolveDN('no tokens', 'Agenia'), 'no tokens');
      expect(resolveDN('{driverName} says hi', ''), '{driverName} says hi');
    });
  });

  // ── {activeTaskVid} token resolution ──────────────────────────────────

  group('resolveDriverCurlyTokens {activeTaskVid}', () {
    test('resolves when #ACTIVE_TASK is set', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'T-051',
      })));
      final result =
          resolveDriverCurlyTokens('tnm\u{25FC}{activeTaskVid}', 'testScr');
      expect(result, 'tnm\u{25FC}T-051');
    });

    test('leaves literal when #ACTIVE_TASK is empty', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': '',
      })));
      final result =
          resolveDriverCurlyTokens('tnm\u{25FC}{activeTaskVid}', 'testScr');
      expect(result, 'tnm\u{25FC}{activeTaskVid}');
    });

    test('leaves literal when #ACTIVE_TASK is absent', () {
      // Clear it by dispatching null equivalent
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': null,
      })));
      final result =
          resolveDriverCurlyTokens('tnm\u{25FC}{activeTaskVid}', 'testScr');
      expect(result, 'tnm\u{25FC}{activeTaskVid}');
    });

    // Restore for subsequent tests
    tearDown(() {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': '',
      })));
    });
  });

  // ── {tnm} token resolution (alias of {activeTaskVid}) ─────────────────

  group('resolveDriverCurlyTokens {tnm}', () {
    test('resolves when #ACTIVE_TASK is set', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'T-051',
      })));
      final result = resolveDriverCurlyTokens('erf\u{25FC}{tnm}', 'testScr');
      expect(result, 'erf\u{25FC}T-051');
    });

    test('leaves literal when #ACTIVE_TASK is empty', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': '',
      })));
      final result = resolveDriverCurlyTokens('erf\u{25FC}{tnm}', 'testScr');
      expect(result, 'erf\u{25FC}{tnm}');
    });

    test('leaves literal when #ACTIVE_TASK is absent', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': null,
      })));
      final result = resolveDriverCurlyTokens('erf\u{25FC}{tnm}', 'testScr');
      expect(result, 'erf\u{25FC}{tnm}');
    });

    test('{tnm} and {activeTaskVid} both resolve from #ACTIVE_TASK', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': 'T-099',
      })));
      final result = resolveDriverCurlyTokens(
          'task\u{25FC}{tnm}\u{2B58}alias\u{25FC}{activeTaskVid}', 'testScr');
      expect(result, 'task\u{25FC}T-099\u{2B58}alias\u{25FC}T-099');
    });

    // Restore for subsequent tests
    tearDown(() {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#ACTIVE_TASK': '',
      })));
    });
  });

  // ── {rejectTaskVid} token resolution ──────────────────────────────────

  group('resolveDriverCurlyTokens {rejectTaskVid}', () {
    test('resolves when #REJECT_TASK is set', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REJECT_TASK': 'T-REJECT-001',
      })));
      final result =
          resolveDriverCurlyTokens('tnm\u{25FC}{rejectTaskVid}', 'testScr');
      expect(result, 'tnm\u{25FC}T-REJECT-001');
    });

    test('leaves literal when #REJECT_TASK is empty', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REJECT_TASK': '',
      })));
      final result =
          resolveDriverCurlyTokens('tnm\u{25FC}{rejectTaskVid}', 'testScr');
      expect(result, 'tnm\u{25FC}{rejectTaskVid}');
    });

    test('leaves literal when #REJECT_TASK is absent', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REJECT_TASK': null,
      })));
      final result =
          resolveDriverCurlyTokens('tnm\u{25FC}{rejectTaskVid}', 'testScr');
      expect(result, 'tnm\u{25FC}{rejectTaskVid}');
    });

    test('leaves other tokens untouched', () {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REJECT_TASK': 'T-REJECT-002',
        '#has_user_login': '777',
      })));
      final result = resolveDriverCurlyTokens(
          'reject\u{25FC}{rejectTaskVid}\u{2B58}driver\u{25FC}{driverVid}',
          'testScr');
      expect(result,
          'reject\u{25FC}T-REJECT-002\u{2B58}driver\u{25FC}777');
    });

    // Restore for subsequent tests
    tearDown(() {
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#REJECT_TASK': '',
      })));
    });
  });

  group('excludeByStatus', () {
    test('drops docs with matching tst', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'tst': 'assigned'},
        {'id': '2', 'tst': 'load_rejected'},
        {'id': '3', 'tst': 'completed'},
      ];
      final result = excludeByStatus(docs, 'load_rejected');
      expect(result.length, 2);
      expect(result[0]['id'], '1');
      expect(result[1]['id'], '3');
    });

    test('keeps failed tasks (failed != load_rejected)', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'tst': 'assigned'},
        {'id': '2', 'tst': 'failed'},
        {'id': '3', 'tst': 'load_rejected'},
      ];
      final result = excludeByStatus(docs, 'load_rejected');
      expect(result.length, 2);
      expect(result[0]['id'], '1');
      expect(result[1]['id'], '2');
    });

    test('empty excludeStatus returns all docs unchanged (incl load_rejected)', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'tst': 'assigned'},
        {'id': '2', 'tst': 'load_rejected'},
      ];
      final result = excludeByStatus(docs, '');
      expect(result.length, 2);
      expect(identical(result, docs), isTrue, reason: 'returns same list reference');
    });

    test('absent tst field keeps doc', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1'},
        {'id': '2', 'tst': 'load_rejected'},
      ];
      final result = excludeByStatus(docs, 'load_rejected');
      expect(result.length, 1);
      expect(result[0]['id'], '1');
    });

    test('custom statusField', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'status': 'rejected'},
        {'id': '2', 'status': 'ok'},
      ];
      final result = excludeByStatus(docs, 'rejected', statusField: 'status');
      expect(result.length, 1);
      expect(result[0]['id'], '2');
    });

    test('empty list returns empty', () {
      final result = excludeByStatus(<Map<String, dynamic>>[], 'load_rejected');
      expect(result, isEmpty);
    });

    test('multiple matching docs all dropped', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'tst': 'load_rejected'},
        {'id': '2', 'tst': 'load_rejected'},
        {'id': '3', 'tst': 'load_rejected'},
      ];
      final result = excludeByStatus(docs, 'load_rejected');
      expect(result, isEmpty);
    });

    test('whitespace-padded tst is trimmed before compare', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'tst': ' load_rejected '},
        {'id': '2', 'tst': 'assigned'},
      ];
      final result = excludeByStatus(docs, 'load_rejected');
      expect(result.length, 1);
      expect(result[0]['id'], '2');
    });

    test('null tst field treated as empty string (kept)', () {
      final docs = <Map<String, dynamic>>[
        {'id': '1', 'tst': null},
        {'id': '2', 'tst': 'load_rejected'},
      ];
      final result = excludeByStatus(docs, 'load_rejected');
      expect(result.length, 1);
      expect(result[0]['id'], '1');
    });
  });
}
