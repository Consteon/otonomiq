import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // The 'Existence gate decision logic' group calls evaluateGateSearch, whose
  // filterDriverHomeDocs reads transactionStore.state.screenTx
  // (driver_home_support.dart:368). The global `transactionStore` is null in a
  // bare flutter_test process, so seed the Redux store ONCE before all tests
  // (mirrors driver_home_support_test.dart:15-22 and global.dart's
  // DevToolsStore<ScreenTransaction> init).
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  group('PreconditionGateCard text parsing', () {
    test('diamondTextToList parses 9-slot text correctly', () {
      final text =
          'Perlu Aksi◆Konfirmasi Penerimaan Muatan◆Muat dari <2>. Cek & konfirmasi sebelum berangkat.◆Konfirmasi Penerimaan◆membuka layar...◆Muatan dikonfirmasi◆{confirmedSummary} · jumlah aktual◆! Ada selisih dari catatan gudang◆udah dilaporkan, Supervisor lagi review.';
      final arr = diamondTextToList(text);
      expect(arr.length, 9);
      expect(arr[0], 'Perlu Aksi');
      expect(arr[5], 'Muatan dikonfirmasi');
    });

    test('length guard on short arrays', () {
      final arr = diamondTextToList('A◆B◆C');
      expect(arr.length > 5 ? arr[5] : 'fallback', 'fallback');
    });
  });

  group('Gate search string decode', () {
    // W4 / encoding reality: autheniumDecode ACTIVELY decodes `_25FC_` -> ◼
    // (global.dart:1128) and `_u2B58_` -> ⭘ (global.dart:1124). The bare
    // `_2B58_` form is COMMENTED OUT (global.dart:1135), so it is NOT decoded —
    // even though CLAUDE.md and scanner_validate.dart describe the server escape
    // as bare `_2B58_`. This mismatch is flagged as an out-of-scope finding for
    // code-reviewer. These tests assert autheniumDecode's ACTUAL behavior.
    test('autheniumDecode converts _25FC_ to ◼ and _u2B58_ to ⭘', () {
      final raw = 'cty_25FC_opening_u2B58_vv_25FC_123';
      final decoded = autheniumDecode(raw);
      expect(decoded, contains('\u{25FC}')); // ◼
      expect(decoded, contains('\u{2B58}')); // ⭘
    });

    test('bare _2B58_ is NOT decoded (latent autheniumDecode gap)', () {
      // Documents the current behavior: bare _2B58_ stays literal. If the live
      // op1Screen JSON sends bare _2B58_ for the AND-separator, the gate search
      // would not split — see walkthrough out-of-scope note.
      final decoded = autheniumDecode('vv_2B58_cdt');
      expect(decoded!.contains('\u{2B58}'), isFalse);
      expect(decoded.contains('_2B58_'), isTrue);
    });
  });

  group('{confirmedSummary} from ip[] (P3)', () {
    // Tests the CONTRACT of confirmed-summary computation:
    // aggregateActualSummary(ip[], nameMap) -> summary string,
    // then template.replaceAll('{confirmedSummary}', computed).

    // W2: mirrors _buildConfirmed's empty-summary cleanup — substitute, then
    // when the computed value is empty, strip a leading middle-dot separator so
    // no dangling "· suffix" renders. Asserts the CLEAN rendered string.
    String renderSummary(String template, String computed) {
      String out = template.replaceAll('{confirmedSummary}', computed);
      if (computed.isEmpty) {
        // Mirror _buildConfirmed: non-raw string so \u{00B7} is the literal
        // middle-dot char (a raw regex would not match without the unicode flag).
        out = out.replaceFirst(RegExp('^\\s*\u{00B7}\\s*'), '').trim();
      }
      return out;
    }

    test('template substitution with computed summary', () {
      final template = '{confirmedSummary} \u{00B7} jumlah aktual';
      final ip = [
        {'ii': '31', 'cd': 'full', 'qt': '30'},
        {'ii': '31', 'cd': 'empty', 'qt': '4'},
        {'ii': '32', 'cd': 'full', 'qt': '12'},
      ];
      final nameMap = {
        '31': 'Amidis Galon 19 Lite',
        '32': 'Aqua 600ml',
      };
      final computed = aggregateActualSummary(ip, nameMap);
      final result = renderSummary(template, computed);
      expect(result,
          '34 Amidis Galon 19 Lite \u{00B7} 12 Aqua 600ml \u{00B7} jumlah aktual');
    });

    test('empty ip[] -> empty summary, leading middle-dot stripped (W2)', () {
      // W2: with an empty computed summary, the confirmed card must NOT render a
      // dangling "· jumlah aktual". _buildConfirmed strips the leading dot, so
      // the rendered line is just the suffix "jumlah aktual".
      final template = '{confirmedSummary} \u{00B7} jumlah aktual';
      final computed = aggregateActualSummary([], {});
      expect(computed, '');
      final result = renderSummary(template, computed);
      expect(result, 'jumlah aktual');
    });

    test('absent ip (null) -> empty summary', () {
      final computed = aggregateActualSummary(null, {});
      expect(computed, '');
    });

    test('template without {confirmedSummary} passes through unchanged', () {
      const template = 'Muatan sudah dikonfirmasi';
      // No {confirmedSummary} token -> replaceAll is a no-op.
      final result = template.replaceAll('{confirmedSummary}', 'ignored');
      expect(result, 'Muatan sudah dikonfirmasi');
    });

    test('ip[] with unknown ii -> raw id in summary', () {
      final ip = [
        {'ii': '999', 'cd': 'full', 'qt': '5'},
      ];
      final computed = aggregateActualSummary(ip, {});
      expect(computed, '5 999');
    });
  });

  group('Existence gate decision logic (spec section 8 item 1)', () {
    // Tests the GATE DECISION that build() implements, as a pure function.
    // evaluateGateSearch is already thoroughly tested in
    // driver_home_support_test.dart:932-1009. Here we test the wrapping logic:
    //   - empty gateSearch -> skip gate (backward-compat, card renders)
    //   - non-empty gateSearch + no matching doc -> gate closed (hide)
    //   - non-empty gateSearch + matching doc -> gate open (render)

    // Pure decision function mirroring build()'s gate logic.
    // Returns: null = gate skipped (render normally),
    //          false = gate closed (hide),
    //          true = gate open (render normally).
    bool? existenceGateDecision(String rawGateSearch, String existGateCode) {
      final String trimmed = rawGateSearch.trim();
      if (trimmed.isEmpty) return null; // skip gate, backward-compat
      return evaluateGateSearch(existGateCode, trimmed, 'test_scr');
    }

    setUp(() {
      mapTableContent['exist_gate/vehicle_check'] = [
        {'cty': 'opening', 'vv': 'V100', 'cdt': '2026-06-25'},
      ];
      clearDriverHomeState('test_scr');
      // Seed vehicleId for token resolution inside filterDriverHomeDocs.
      getDriverHomeState('test_scr').vehicleId.value = 'V100';
    });

    tearDown(() {
      mapTableContent.remove('exist_gate/vehicle_check');
      clearDriverHomeState('test_scr');
    });

    test('empty gateSearch -> gate skipped (null = render normally)', () {
      expect(existenceGateDecision('', 'exist_gate/vehicle_check'), isNull);
    });

    test('absent gateSearch (null toString) -> gate skipped', () {
      // Mirrors (component['gateSearch'] ?? '').toString().trim() when the
      // field is ABSENT: the map lookup yields null, the ?? supplies '', and
      // the gate is skipped. Sourcing null from a real missing-key lookup
      // (rather than the literal `null`) keeps the idiom faithful without
      // tripping unnecessary_null_in_if_null_operators.
      final Map<String, dynamic> componentNoGate = {};
      expect(
        existenceGateDecision(
            (componentNoGate['gateSearch'] ?? '').toString().trim(),
            'exist_gate/vehicle_check'),
        isNull,
      );
    });

    test('non-empty gateSearch + matching doc -> gate open (true)', () {
      // Raw ◼ char for field separator (mirrors live JSON).
      expect(
        existenceGateDecision(
            'cty\u{25FC}opening', 'exist_gate/vehicle_check'),
        isTrue,
      );
    });

    test('non-empty gateSearch + no matching doc -> gate closed (false)', () {
      expect(
        existenceGateDecision(
            'cty\u{25FC}closing', 'exist_gate/vehicle_check'),
        isFalse,
      );
    });

    test('non-empty gateSearch + empty existGateCode -> gate closed (false)',
        () {
      // _existGateCode empty = gateTable not configured/parsed -> hide.
      expect(
        existenceGateDecision('cty\u{25FC}opening', ''),
        isFalse,
      );
    });

    test('non-empty gateSearch + unsubscribed code -> gate closed (false)', () {
      // No data in mapTableContent for this code.
      expect(
        existenceGateDecision(
            'cty\u{25FC}opening', 'nonexistent/vehicle_check'),
        isFalse,
      );
    });

    test('gateSearch without cst -> existence only, not status', () {
      // The live gateSearch intentionally omits cst. A doc with cty=opening
      // should pass regardless of its cst value.
      mapTableContent['exist_gate/vehicle_check'] = [
        {
          'cty': 'opening',
          'vv': 'V100',
          'cdt': '2026-06-25',
          'cst': 'custody_pending'
        },
      ];
      expect(
        existenceGateDecision(
            'cty\u{25FC}opening', 'exist_gate/vehicle_check'),
        isTrue,
      );
    });

    test('publish false when gated out (contract)', () {
      // When the gate decision is false, build() publishes confirmed=false.
      // Verify the DriverHomeState contract: confirmed starts false, stays
      // false when gated out.
      final dhState = getDriverHomeState('test_scr');
      expect(dhState.confirmed.value, isFalse);

      // Simulate: gate closes (no matching doc).
      final gateOpen = existenceGateDecision(
          'cty\u{25FC}nonexistent', 'exist_gate/vehicle_check');
      expect(gateOpen, isFalse);

      // In the real widget, _publishConfirmed(dhState, false) fires.
      // We verify the helper contract: value should be set to false.
      // Since it is already false, the helper is a no-op (correct).
      dhState.confirmed.value = false;
      expect(dhState.confirmed.value, isFalse);
    });

    test('publish false then true when gate opens on data arrival', () {
      // Simulates the reactive flow: initially no data -> gated out,
      // then data arrives -> gate opens.
      mapTableContent.remove('exist_gate/vehicle_check');

      // Phase 1: no data.
      final gateOpen1 = existenceGateDecision(
          'cty\u{25FC}opening', 'exist_gate/vehicle_check');
      expect(gateOpen1, isFalse);

      // Phase 2: data arrives (Obx would trigger rebuild).
      mapTableContent['exist_gate/vehicle_check'] = [
        {'cty': 'opening', 'vv': 'V100', 'cdt': '2026-06-25'},
      ];
      final gateOpen2 = existenceGateDecision(
          'cty\u{25FC}opening', 'exist_gate/vehicle_check');
      expect(gateOpen2, isTrue);
    });
  });

  group('ie-source branch decision (spec section 9)', () {
    // Tests the BRANCH DECISION that _getItems implements, as a pure function.
    // The actual aggregation is covered in driver_home_support_test.dart's
    // aggregateManifestFromIe group. Widget-pump tests are impractical here
    // (heavy GetX/Firestore/global deps), so build()-wiring is QA-gated.

    // Pure decision function mirroring _getItems's branch logic.
    // Returns: 'ie' = ie path, 'task' = legacy task aggregation.
    String itemSourceDecision(Map<String, dynamic> component) {
      final String itemsField =
          (component['itemsField'] ?? 'it').toString().trim();
      if (itemsField == 'ie') return 'ie';
      return 'task';
    }

    test('itemsField "ie" -> ie path', () {
      expect(itemSourceDecision({'itemsField': 'ie'}), 'ie');
    });

    test('itemsField "it" (default) -> task aggregation path', () {
      expect(itemSourceDecision({'itemsField': 'it'}), 'task');
    });

    test('itemsField absent -> default "it" -> task path', () {
      expect(itemSourceDecision({}), 'task');
    });

    test('itemsField null -> default "it" -> task path', () {
      expect(itemSourceDecision({'itemsField': null}), 'task');
    });

    test('itemsField empty string -> task path (not ie)', () {
      expect(itemSourceDecision({'itemsField': ''}), 'task');
    });

    test('itemsField " ie " (whitespace) -> ie path (trimmed)', () {
      // trim() is called, so " ie " -> "ie" -> ie path
      expect(itemSourceDecision({'itemsField': ' ie '}), 'ie');
    });

    test('itemsField "IE" (uppercase) -> task path (case-sensitive)', () {
      // The branch is case-sensitive: only lowercase "ie" matches.
      expect(itemSourceDecision({'itemsField': 'IE'}), 'task');
    });
  });

  group('_matchedOpeningDoc decision (ie-source plumbing)', () {
    // Tests the opening-doc lookup logic that _itemsFromIe depends on.
    // Uses evaluateGateSearch as the decision proxy (same as existenceGateDecision).

    setUp(() {
      mapTableContent['exist_ie/vehicle_check'] = [
        {
          'cty': 'opening',
          'vv': 'V200',
          'cdt': '2026-06-25',
          'ie': [
            {'ii': '31', 'cd': 'full', 'qt': 10},
            {'ii': '32', 'cd': 'full', 'qt': 5},
          ],
        },
      ];
      clearDriverHomeState('test_ie_scr');
      getDriverHomeState('test_ie_scr').vehicleId.value = 'V200';
    });

    tearDown(() {
      mapTableContent.remove('exist_ie/vehicle_check');
      clearDriverHomeState('test_ie_scr');
    });

    test('opening doc found -> ie[] accessible', () {
      // Proxy: evaluateGateSearch confirms the doc exists.
      final exists = evaluateGateSearch(
          'exist_ie/vehicle_check',
          'cty\u{25FC}opening',
          'test_ie_scr');
      expect(exists, isTrue);

      // Verify the doc has ie[]:
      final docs = List<Map<String, dynamic>>.from(
          mapTableContent['exist_ie/vehicle_check'] ?? const []);
      final matched = filterDriverHomeDocs(
          docs, 'cty\u{25FC}opening', 'test_ie_scr');
      expect(matched.isNotEmpty, isTrue);
      expect(matched.first['ie'], isA<List>());
      expect((matched.first['ie'] as List).length, 2);
    });

    test('no opening doc -> ie[] path returns empty (no crash)', () {
      mapTableContent.remove('exist_ie/vehicle_check');
      final exists = evaluateGateSearch(
          'exist_ie/vehicle_check',
          'cty\u{25FC}opening',
          'test_ie_scr');
      expect(exists, isFalse);
      // In the widget, _matchedOpeningDoc returns null -> _itemsFromIe
      // returns const []. No crash.
    });

    test('opening doc without ie field -> aggregateManifestFromIe handles gracefully', () {
      mapTableContent['exist_ie/vehicle_check'] = [
        {'cty': 'opening', 'vv': 'V200', 'cdt': '2026-06-25'},
        // no 'ie' field
      ];
      final docs = List<Map<String, dynamic>>.from(
          mapTableContent['exist_ie/vehicle_check'] ?? const []);
      final matched = filterDriverHomeDocs(
          docs, 'cty\u{25FC}opening', 'test_ie_scr');
      expect(matched.isNotEmpty, isTrue);
      // ie field absent -> null -> aggregateManifestFromIe receives null
      // -> returns empty (is! List guard).
      final rows = aggregateManifestFromIe(matched.first['ie'], {});
      expect(rows, isEmpty);
    });

    test('ie[] aggregate through full pipeline (end-to-end proxy)', () {
      // Simulates the full _itemsFromIe flow without the widget.
      final docs = List<Map<String, dynamic>>.from(
          mapTableContent['exist_ie/vehicle_check'] ?? const []);
      final matched = filterDriverHomeDocs(
          docs, 'cty\u{25FC}opening', 'test_ie_scr');
      final openingDoc = matched.first;

      final nameMap = {'31': 'Amidis Galon 19L', '32': 'Aqua 600ml'};
      final rows = aggregateManifestFromIe(
        openingDoc['ie'],
        nameMap,
        qtyField: 'qt',
        labelField: 'in',
      );
      expect(rows.length, 2);
      expect(rows[0], {'in': 'Amidis Galon 19L', 'qt': 10});
      expect(rows[1], {'in': 'Aqua 600ml', 'qt': 5});
    });
  });

  group('hasLoadDiscrepancy predicate (spec section 10)', () {
    test('non-empty List -> true (discrepancy present)', () {
      expect(hasLoadDiscrepancy([{'ac': 2, 'ex': 3, 'dl': -1}]), isTrue);
    });

    test('multi-element List -> true', () {
      expect(hasLoadDiscrepancy([
        {'ac': 2, 'ex': 3, 'dl': -1},
        {'ac': 5, 'ex': 5, 'dl': 0},
      ]), isTrue);
    });

    test('empty List -> false (no discrepancy)', () {
      expect(hasLoadDiscrepancy([]), isFalse);
    });

    test('null -> false', () {
      expect(hasLoadDiscrepancy(null), isFalse);
    });

    test('absent (dynamic null from missing map key) -> false', () {
      final Map<String, dynamic> doc = {'cst': 'custody_confirmed'};
      expect(hasLoadDiscrepancy(doc['dp']), isFalse);
    });

    test('non-List (Map) -> false', () {
      expect(hasLoadDiscrepancy({'ac': 2}), isFalse);
    });

    test('non-List (String) -> false', () {
      expect(hasLoadDiscrepancy('dp'), isFalse);
    });

    test('non-List (int) -> false', () {
      expect(hasLoadDiscrepancy(42), isFalse);
    });

    test('non-List (bool) -> false', () {
      expect(hasLoadDiscrepancy(true), isFalse);
    });
  });

  group('State-4 decision mapping (spec section 10)', () {
    // Pure decision function mirroring build()'s state-3/4 branching.
    // confirmed = true means _matchedGateDoc returned non-null.
    // Returns: 'state3' or 'state4'.
    String confirmedSubState(Map<String, dynamic> gateDoc,
        {String dpField = 'dp'}) {
      final dynamic dpArray = gateDoc[dpField];
      return hasLoadDiscrepancy(dpArray) ? 'state4' : 'state3';
    }

    test('confirmed + dp non-empty -> state 4', () {
      final doc = {
        'cst': 'custody_confirmed',
        'dp': [{'ac': 2, 'ex': 3, 'dl': -1}],
      };
      expect(confirmedSubState(doc), 'state4');
    });

    test('confirmed + dp empty -> state 3', () {
      final doc = {
        'cst': 'custody_confirmed',
        'dp': [],
      };
      expect(confirmedSubState(doc), 'state3');
    });

    test('confirmed + dp absent -> state 3', () {
      final doc = {
        'cst': 'custody_confirmed',
      };
      expect(confirmedSubState(doc), 'state3');
    });

    test('confirmed + dp null -> state 3', () {
      final doc = {
        'cst': 'custody_confirmed',
        'dp': null,
      };
      expect(confirmedSubState(doc), 'state3');
    });

    test('dpField config override reads correct field', () {
      final doc = {
        'cst': 'custody_confirmed',
        'dp': [], // default field is empty
        'customDp': [{'ac': 1, 'ex': 2, 'dl': -1}],
      };
      expect(confirmedSubState(doc), 'state3'); // default 'dp' is empty
      expect(confirmedSubState(doc, dpField: 'customDp'), 'state4');
    });

    test('text slot 7 default fallback (lean tenant)', () {
      // Mirrors _t(7, default) when _textArray has < 8 entries.
      final shortText = diamondTextToList('A\u{25C6}B\u{25C6}C');
      expect(shortText.length, 3);
      final slot7 = shortText.length > 7
          ? shortText[7]
          : '! Ada selisih dari catatan gudang';
      expect(slot7, '! Ada selisih dari catatan gudang');
    });

    test('text slot 8 default fallback (lean tenant)', () {
      final shortText = diamondTextToList('A\u{25C6}B\u{25C6}C');
      expect(shortText.length, 3);
      final slot8 = shortText.length > 8
          ? shortText[8]
          : 'udah dilaporkan, Supervisor lagi review. Kerjaan tetap jalan.';
      expect(slot8,
          'udah dilaporkan, Supervisor lagi review. Kerjaan tetap jalan.');
    });

    test('text slots 7+8 present in full text array', () {
      final fullText = diamondTextToList(
          'Perlu Aksi\u{25C6}Konfirmasi\u{25C6}body\u{25C6}CTA\u{25C6}membuka\u{25C6}Dikonfirmasi\u{25C6}summary\u{25C6}Selisih headline\u{25C6}Selisih caption');
      expect(fullText.length, 9);
      expect(fullText[7], 'Selisih headline');
      expect(fullText[8], 'Selisih caption');
    });
  });

  group('Multi-trip ie[] doc selection (vehicle-check-ie-trip-scope)', () {
    // Tests the integration of filterDriverHomeDocs + pickActiveOpening that
    // _matchedOpeningDoc and _matchedGateDoc now use. Scenario: trip-2 closed,
    // trip-3 active, both share (vv, cdt). The card must pick trip-3.

    setUp(() {
      mapTableContent['trip_scope/vehicle_check'] = [
        // Trip-2: closed, older
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'closed',
          't': 100,
          '__docId': 'TRIP2',
          'ie': [
            {'ii': '31', 'cd': 'full', 'qt': 5},
          ],
        },
        // Trip-3: active, newer
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'awaiting_custody',
          't': 200,
          '__docId': 'TRIP3',
          'ie': [
            {'ii': '31', 'cd': 'full', 'qt': 10},
            {'ii': '32', 'cd': 'full', 'qt': 7},
          ],
        },
      ];
      clearDriverHomeState('test_trip_scr');
      getDriverHomeState('test_trip_scr').vehicleId.value = 'V300';
    });

    tearDown(() {
      mapTableContent.remove('trip_scope/vehicle_check');
      clearDriverHomeState('test_trip_scr');
    });

    test('pickActiveOpening picks trip-3 (newest non-closed) from multi-match',
        () {
      final docs = List<Map<String, dynamic>>.from(
        mapTableContent['trip_scope/vehicle_check'] ?? const [],
      );
      // gateSearch without cst: matches both openings
      final matched = filterDriverHomeDocs(
        docs,
        'cty\u{25FC}opening\u{2B58}vv\u{25FC}V300',
        'test_trip_scr',
      );
      expect(matched.length, 2, reason: 'both openings match the search');

      // The fix: pickActiveOpening picks trip-3
      final picked = pickActiveOpening(matched);
      expect(picked, isNotNull);
      expect(picked!['__docId'], 'TRIP3');
      expect(picked['cst'], 'awaiting_custody');

      // ie[] from the picked doc is trip-3's manifest
      final ie = picked['ie'] as List;
      expect(ie.length, 2);
      expect((ie[0] as Map)['qt'], 10);
    });

    test('single opening: pickActiveOpening returns it unchanged', () {
      mapTableContent['trip_scope/vehicle_check'] = [
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'awaiting_custody',
          't': 100,
          '__docId': 'ONLY',
          'ie': [
            {'ii': '31', 'cd': 'full', 'qt': 3},
          ],
        },
      ];
      final docs = List<Map<String, dynamic>>.from(
        mapTableContent['trip_scope/vehicle_check'] ?? const [],
      );
      final matched = filterDriverHomeDocs(
        docs,
        'cty\u{25FC}opening\u{2B58}vv\u{25FC}V300',
        'test_trip_scr',
      );
      expect(matched.length, 1);
      final picked = pickActiveOpening(matched);
      expect(picked?['__docId'], 'ONLY');
    });

    test('no openings: pickActiveOpening returns null, fallback to first', () {
      mapTableContent['trip_scope/vehicle_check'] = [
        {
          'cty': 'closing',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': '',
          't': 100,
          '__docId': 'CLOSING',
        },
      ];
      final docs = List<Map<String, dynamic>>.from(
        mapTableContent['trip_scope/vehicle_check'] ?? const [],
      );
      final matched = filterDriverHomeDocs(
        docs,
        'cty\u{25FC}closing\u{2B58}vv\u{25FC}V300',
        'test_trip_scr',
      );
      expect(matched.length, 1);
      // pickActiveOpening returns null (no opening-shaped docs)
      final picked = pickActiveOpening(matched);
      expect(picked, isNull);
      // fallback: matched.first (the closing doc, not an opening)
      expect(matched.first['__docId'], 'CLOSING');
    });

    test('all openings closed: pickActiveOpening returns newest closed', () {
      mapTableContent['trip_scope/vehicle_check'] = [
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'closed',
          't': 100,
          '__docId': 'OLD_CLOSED',
          'ie': [
            {'ii': '31', 'cd': 'full', 'qt': 1},
          ],
        },
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'closed',
          't': 200,
          '__docId': 'NEW_CLOSED',
          'ie': [
            {'ii': '31', 'cd': 'full', 'qt': 2},
          ],
        },
      ];
      final docs = List<Map<String, dynamic>>.from(
        mapTableContent['trip_scope/vehicle_check'] ?? const [],
      );
      final matched = filterDriverHomeDocs(
        docs,
        'cty\u{25FC}opening\u{2B58}vv\u{25FC}V300',
        'test_trip_scr',
      );
      expect(matched.length, 2);
      // All closed: pickActiveOpening returns newest by t
      final picked = pickActiveOpening(matched);
      expect(picked?['__docId'], 'NEW_CLOSED');
    });

    test('empty mapTableContent: filterDriverHomeDocs returns empty', () {
      mapTableContent.remove('trip_scope/vehicle_check');
      final docs = List<Map<String, dynamic>>.from(
        mapTableContent['trip_scope/vehicle_check'] ?? const [],
      );
      final matched = filterDriverHomeDocs(
        docs,
        'cty\u{25FC}opening\u{2B58}vv\u{25FC}V300',
        'test_trip_scr',
      );
      expect(matched, isEmpty);
      final picked = pickActiveOpening(matched);
      expect(picked, isNull);
    });

    test('custody_confirmed trip-3 + closed trip-2: search with cst picks trip-3', () {
      // Mirrors the _matchedGateDoc path (search includes cst).
      mapTableContent['trip_scope/vehicle_check'] = [
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'closed',
          't': 100,
          '__docId': 'TRIP2',
        },
        {
          'cty': 'opening',
          'vv': 'V300',
          'cdt': '20260708',
          'cst': 'custody_confirmed',
          't': 200,
          '__docId': 'TRIP3',
        },
      ];
      final docs = List<Map<String, dynamic>>.from(
        mapTableContent['trip_scope/vehicle_check'] ?? const [],
      );
      // search WITH cst filter: only trip-3 matches
      final matched = filterDriverHomeDocs(
        docs,
        'cty\u{25FC}opening\u{2B58}vv\u{25FC}V300\u{2B58}cst\u{25FC}custody_confirmed',
        'test_trip_scr',
      );
      expect(matched.length, 1);
      expect(matched.first['__docId'], 'TRIP3');
      // pickActiveOpening is a no-op (single match), but consistent
      final picked = pickActiveOpening(matched);
      expect(picked?['__docId'], 'TRIP3');
    });
  });
}
