// test/item_execution_submit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/item_execution_list.dart';
import 'package:otonomiq/widget/item_execution_submit.dart';

void main() {
  // ── rebuildItWithActuals ────────────────────────────────────────────────

  group('rebuildItWithActuals', () {
    // Config mirrors live server JSON field names.
    final ItemExecutionSubmitConfig cfg = ItemExecutionSubmitConfig(
      itemsField: 'it',
      txField: 'tx',
      planDropField: 'pd',
      planPickupField: 'pp',
      saleField: 'ps',
      buyField: 'pb',
      refillField: 'pr',
      actualDropField: 'ad',
      actualPickupField: 'ap',
      actualSaleField: 'as',
      actualBuyField: 'ab',
      actualRefillField: 'ar',
    );

    test('deliver: writes ad/ap from executionStore', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Galon 19L', 'ii': 'galon', 'pd': 3, 'pp': 2, 'tx': 'deliver'},
      ];
      final execMap = <String, ExecutionEntry>{
        '0': ExecutionEntry(
            dropActual: 2, pickupActual: 1, dropPlan: 3, pickupPlan: 2),
      };
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result.length, 1);
      expect(result[0]['ad'], 2);
      expect(result[0]['ap'], 1);
      // Original fields preserved
      expect(result[0]['in'], 'Galon 19L');
      expect(result[0]['ii'], 'galon');
      expect(result[0]['pd'], 3);
      expect(result[0]['pp'], 2);
    });

    test('deliver with empty tx (backward-compat): writes ad/ap', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Aqua', 'pd': 5, 'pp': 0},
      ];
      final execMap = <String, ExecutionEntry>{
        '0': ExecutionEntry(
            dropActual: 4, pickupActual: 0, dropPlan: 5, pickupPlan: 0),
      };
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result[0]['ad'], 4);
      expect(result[0]['ap'], 0);
    });

    test('deliver untouched stepper: actual == plan (always-write)', () {
      final items = <Map<String, dynamic>>[
        {'in': 'LPG', 'pd': 3, 'pp': 2, 'tx': 'deliver'},
      ];
      // Execution entry with default = plan (stepper untouched)
      final execMap = <String, ExecutionEntry>{
        '0': ExecutionEntry(
            dropActual: 3, pickupActual: 2, dropPlan: 3, pickupPlan: 2),
      };
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result[0]['ad'], 3);
      expect(result[0]['ap'], 2);
    });

    test('deliver with no executionStore entry: falls back to plan', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Mystery', 'pd': 7, 'pp': 3, 'tx': 'deliver'},
      ];
      final execMap = <String, ExecutionEntry>{}; // empty
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result[0]['ad'], 7); // fallback to pd
      expect(result[0]['ap'], 3); // fallback to pp
    });

    test('sale: writes as = ps (actual = plan)', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Tabung', 'tx': 'sale', 'ps': 5},
      ];
      final execMap = <String, ExecutionEntry>{}; // no entry for sale
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result[0]['as'], 5);
      // ad/ap NOT written for sale
      expect(result[0].containsKey('ad'), false);
      expect(result[0].containsKey('ap'), false);
    });

    test('purchase: writes ab = pb (actual = plan)', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Kompor', 'tx': 'purchase', 'pb': 10},
      ];
      final result = rebuildItWithActuals(items, {}, cfg);
      expect(result[0]['ab'], 10);
      expect(result[0].containsKey('ad'), false);
    });

    test('refill: writes ar = pr (actual = plan)', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Galon Customer', 'tx': 'refill', 'pr': 4},
      ];
      final result = rebuildItWithActuals(items, {}, cfg);
      expect(result[0]['ar'], 4);
      expect(result[0].containsKey('ad'), false);
    });

    test('mixed items: each tx kind writes correct actual fields', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Galon', 'pd': 3, 'pp': 2, 'tx': 'deliver'},
        {'in': 'Tabung', 'tx': 'sale', 'ps': 5},
        {'in': 'Aqua', 'pd': 10, 'pp': 0, 'tx': ''},
        {'in': 'Kompor', 'tx': 'purchase', 'pb': 2},
        {'in': 'CustGalon', 'tx': 'refill', 'pr': 4},
      ];
      final execMap = <String, ExecutionEntry>{
        '0': ExecutionEntry(
            dropActual: 2, pickupActual: 1, dropPlan: 3, pickupPlan: 2),
        '2': ExecutionEntry(
            dropActual: 8, pickupActual: 0, dropPlan: 10, pickupPlan: 0),
      };
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result.length, 5);
      // deliver
      expect(result[0]['ad'], 2);
      expect(result[0]['ap'], 1);
      // sale
      expect(result[1]['as'], 5);
      expect(result[1].containsKey('ad'), false);
      // deliver (empty tx)
      expect(result[2]['ad'], 8);
      expect(result[2]['ap'], 0);
      // purchase
      expect(result[3]['ab'], 2);
      // refill
      expect(result[4]['ar'], 4);
    });

    test('preserves unknown fields on item maps', () {
      final items = <Map<String, dynamic>>[
        {
          'in': 'Galon',
          'pd': 3,
          'pp': 2,
          'tx': 'deliver',
          'ii': 'galon',
          'ic': 'returnable',
          'customField': 'keep-me',
          'nested': {'a': 1},
        },
      ];
      final execMap = <String, ExecutionEntry>{
        '0': ExecutionEntry(
            dropActual: 2, pickupActual: 1, dropPlan: 3, pickupPlan: 2),
      };
      final result = rebuildItWithActuals(items, execMap, cfg);
      expect(result[0]['ii'], 'galon');
      expect(result[0]['ic'], 'returnable');
      expect(result[0]['customField'], 'keep-me');
      expect(result[0]['nested'], {'a': 1});
    });

    test('empty items array returns empty', () {
      final result = rebuildItWithActuals([], {}, cfg);
      expect(result, isEmpty);
    });

    test('sparse items (missing plan fields) default to 0', () {
      final items = <Map<String, dynamic>>[
        {'in': 'Sparse', 'tx': 'deliver'},
      ];
      final execMap = <String, ExecutionEntry>{};
      final result = rebuildItWithActuals(items, execMap, cfg);
      // No executionEntry -> fallback to plan -> plan missing -> 0
      expect(result[0]['ad'], 0);
      expect(result[0]['ap'], 0);
    });

    test('sale with missing ps field defaults to 0', () {
      final items = <Map<String, dynamic>>[
        {'in': 'EmptySale', 'tx': 'sale'},
      ];
      final result = rebuildItWithActuals(items, {}, cfg);
      expect(result[0]['as'], 0);
    });

    test('items with dynamic types (string plan values) parse correctly', () {
      final items = <Map<String, dynamic>>[
        {'in': 'StringPlan', 'pd': '3', 'pp': '2', 'tx': 'deliver'},
      ];
      final execMap = <String, ExecutionEntry>{};
      final result = rebuildItWithActuals(items, execMap, cfg);
      // No entry -> fallback to plan parsed from string
      expect(result[0]['ad'], 3);
      expect(result[0]['ap'], 2);
    });

    test('custom config field names are honored', () {
      final customCfg = ItemExecutionSubmitConfig(
        itemsField: 'items',
        txField: 'type',
        planDropField: 'planDrop',
        planPickupField: 'planPickup',
        saleField: 'planSale',
        buyField: 'planBuy',
        refillField: 'planRefill',
        actualDropField: 'actDrop',
        actualPickupField: 'actPickup',
        actualSaleField: 'actSale',
        actualBuyField: 'actBuy',
        actualRefillField: 'actRefill',
      );
      final items = <Map<String, dynamic>>[
        {'in': 'Item', 'planDrop': 3, 'planPickup': 2, 'type': 'deliver'},
      ];
      final execMap = <String, ExecutionEntry>{
        '0': ExecutionEntry(
            dropActual: 1, pickupActual: 2, dropPlan: 3, pickupPlan: 2),
      };
      final result = rebuildItWithActuals(items, execMap, customCfg);
      expect(result[0]['actDrop'], 1);
      expect(result[0]['actPickup'], 2);
      expect(result[0].containsKey('ad'), false); // not the default name
    });
  });

  // ── stripTstFromUpdateEventRow ──────────────────────────────────────────
  //
  // The stored DSL form passed to saveSend uses LITERAL ⭘ (U+2B58) / ◼
  // (U+25FC). Confirmed against the live op1screen artifacts for the sibling
  // CUSTODY_EVENT_SUBMIT template (docs/driver_runtime/*-op1screen.md) and the
  // json/admin-runtime/*.json templates -- all store updateEventRow with
  // literal ⭘/◼, never the _2B58_/_25FC_ escapes. saveSend (api.dart:4282)
  // autheniumDecodes the raw component value, which is a no-op on already-
  // literal text, so the form saveSend persists -- and the form the strip
  // must operate on -- is the literal one. Hence these tests use literal
  // \u{2B58}/\u{25FC}, matching what the widget hands to saveSend.

  group('stripTstFromUpdateEventRow', () {
    test('strips tst and tce fields from DSL string', () {
      const dsl =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}'
          '\u{2B58}tst\u{25FC}completed\u{2B58}tce\u{25FC}{now}';
      final result = stripTstFromUpdateEventRow(dsl);
      expect(result.contains('tst\u{25FC}'), false);
      expect(result.contains('tce\u{25FC}'), false);
      // Retains path, tablevid, search
      expect(result.contains('84214220504259//task'), true);
      expect(result.contains('tablevid'), true);
      expect(result.contains('search'), true);
    });

    test('preserves DSL with no tst/tce', () {
      const dsl =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}'
          '\u{2B58}ost\u{25FC}pending';
      final result = stripTstFromUpdateEventRow(dsl);
      expect(result, dsl); // unchanged
    });

    test('empty string returns empty', () {
      expect(stripTstFromUpdateEventRow(''), '');
    });

    test('strips tst only (no tce present)', () {
      const dsl =
          '84214220504259//task\u{2B58}tst\u{25FC}completed'
          '\u{2B58}search\u{25FC}tnm\u{2605}x';
      final result = stripTstFromUpdateEventRow(dsl);
      expect(result.contains('tst\u{25FC}'), false);
      expect(result.contains('search'), true);
    });

    test('handles trailing separator after strip', () {
      const dsl =
          '84214220504259//task\u{2B58}search\u{25FC}x'
          '\u{2B58}tst\u{25FC}completed';
      final result = stripTstFromUpdateEventRow(dsl);
      expect(result.contains('tst'), false);
      // Should not have a trailing separator
      expect(result.endsWith('\u{2B58}'), false);
    });

    // W2: the LIVE P11 updateEventRow is exactly tst◼completed⭘tce◼{now}
    // (plus path/tablevid/search header clauses). After stripping both tst and
    // tce, only the header clauses remain -- there is no body clause left.
    test('live P11 form: strip leaves only header clauses (no body)', () {
      const dsl =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}'
          '\u{2B58}tst\u{25FC}completed\u{2B58}tce\u{25FC}1718000000000';
      final result = stripTstFromUpdateEventRow(dsl);
      // tst + tce gone
      expect(result.contains('tst\u{25FC}'), false);
      expect(result.contains('tce\u{25FC}'), false);
      // header clauses survive
      expect(result.contains('84214220504259//task'), true);
      expect(result.contains('tablevid\u{25FC}20342033315492'), true);
      expect(result.contains('search\u{25FC}tnm\u{2605}{activeTaskVid}'), true);
      // No body clause remains -> updateEventRowHasBody == false
      expect(updateEventRowHasBody(result), false);
    });
  });

  // ── updateEventRowHasBody (W2 empty-body guard) ─────────────────────────
  //
  // Returns true iff the DSL has at least one body key/value clause beyond the
  // header (path / tablevid / search). Used to drop a body-less updateEventRow
  // from the saveSend map so historySync does not issue a no-op merge.

  group('updateEventRowHasBody', () {
    test('header-only DSL has no body', () {
      const dsl =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}';
      expect(updateEventRowHasBody(dsl), false);
    });

    test('DSL with a body clause has body', () {
      const dsl =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}'
          '\u{2B58}ost\u{25FC}pending';
      expect(updateEventRowHasBody(dsl), true);
    });

    test('empty string has no body', () {
      expect(updateEventRowHasBody(''), false);
    });

    test('path-only DSL has no body', () {
      expect(updateEventRowHasBody('84214220504259//task'), false);
    });
  });

  // ── extractItems (pure logic mirror) ──────────────────────────────────

  group('extractItems from task doc', () {
    test('extracts it[] as List<Map>', () {
      final taskDoc = <String, dynamic>{
        'tnm': 'T-001',
        'it': [
          {'in': 'Galon', 'pd': 3, 'pp': 2},
          {'in': 'Aqua', 'pd': 5, 'pp': 0},
        ],
      };
      final items = extractItemsFromDoc(taskDoc, 'it');
      expect(items.length, 2);
      expect(items[0]['in'], 'Galon');
      expect(items[1]['pd'], 5);
    });

    test('null taskDoc returns empty', () {
      expect(extractItemsFromDoc(null, 'it'), isEmpty);
    });

    test('missing items field returns empty', () {
      expect(extractItemsFromDoc({'tnm': 'T-001'}, 'it'), isEmpty);
    });

    test('items field is not a List returns empty', () {
      expect(extractItemsFromDoc({'it': 'not-a-list'}, 'it'), isEmpty);
    });

    test('non-Map entries in items are skipped', () {
      final taskDoc = {
        'it': [
          {'in': 'Valid'},
          'invalid-string',
          42,
          {'in': 'Also Valid'},
        ],
      };
      final items = extractItemsFromDoc(taskDoc, 'it');
      expect(items.length, 2);
      expect(items[0]['in'], 'Valid');
      expect(items[1]['in'], 'Also Valid');
    });

    test('custom items field name works', () {
      final taskDoc = {
        'items': [
          {'in': 'Custom'},
        ],
      };
      expect(extractItemsFromDoc(taskDoc, 'items').length, 1);
    });
  });

  // ── saveSend hook: registration, no-op, config parse ────────────────────
  //
  // Pure-fn and static-map tests for the hook wiring. The end-to-end flow
  // (writeNativeFields, getRealTime, filterDriverHomeDocs) depends on
  // Firebase globals and is verified by manual device testing.

  group('submitComponentByScr registration and cleanup', () {
    test('register stores component, clearExecutionStore removes it', () {
      const String scr = '__test_hook_reg__';
      final component = <String, dynamic>{
        'table': '84214220504259//task',
        'search': 'tnm\u{25FC}T-001',
        'itemsField': 'it',
      };

      // Register
      ItemExecutionList.submitComponentByScr[scr] = component;
      expect(ItemExecutionList.submitComponentByScr[scr], same(component));

      // clearExecutionStore removes it (alongside executionStore, capStore)
      ItemExecutionList.clearExecutionStore(scr);
      expect(
          ItemExecutionList.submitComponentByScr.containsKey(scr), isFalse);
      // Also verify executionStore and capStore are gone
      expect(ItemExecutionList.executionStore.containsKey(scr), isFalse);
      expect(ItemExecutionList.capStore.containsKey(scr), isFalse);
    });

    test('register overwrites on repeated initState (same scrName)', () {
      const String scr = '__test_hook_overwrite__';
      final first = <String, dynamic>{'table': 'first'};
      final second = <String, dynamic>{'table': 'second'};
      ItemExecutionList.submitComponentByScr[scr] = first;
      ItemExecutionList.submitComponentByScr[scr] = second;
      expect(ItemExecutionList.submitComponentByScr[scr], same(second));
      // Cleanup
      ItemExecutionList.clearExecutionStore(scr);
    });

    test('re-register after clearExecutionStore restores hook gate', () {
      // Simulates the build-re-register cycle: after clearExecutionStore wipes
      // the entry (as saveSend does on submit), a plain re-assignment in build
      // must restore it so the next submit's hook guard passes.
      const String scr = '__test_hook_reregister__';
      final component = <String, dynamic>{
        'table': '84214220504259//task',
        'search': 'tnm\u{25FC}T-REREG',
        'itemsField': 'it',
      };

      // 1. Register (simulates initState)
      ItemExecutionList.submitComponentByScr[scr] = component;
      expect(ItemExecutionList.submitComponentByScr.containsKey(scr), isTrue);

      // 2. Clear (simulates saveSend -> clearData -> clearExecutionStore)
      ItemExecutionList.clearExecutionStore(scr);
      expect(ItemExecutionList.submitComponentByScr.containsKey(scr), isFalse);

      // 3. Re-register (simulates the new build() re-registration)
      ItemExecutionList.submitComponentByScr[scr] = component;
      expect(ItemExecutionList.submitComponentByScr.containsKey(scr), isTrue);
      expect(ItemExecutionList.submitComponentByScr[scr], same(component));

      // Cleanup
      ItemExecutionList.clearExecutionStore(scr);
    });
  });

  group('runActualWrite no-op', () {
    test('returns true when no LIST registered for scrName', () async {
      const String scr = '__test_hook_noop__';
      // Ensure the scrName is NOT in the map
      ItemExecutionList.submitComponentByScr.remove(scr);

      final bool result = await ItemExecutionSubmit.runActualWrite(scr);
      expect(result, isTrue);
    });
  });

  group('parseConfigFromComponent', () {
    test('returns defaults for empty component', () {
      final cfg = parseConfigFromComponent(<String, dynamic>{});
      expect(cfg.itemsField, 'it');
      expect(cfg.txField, 'tx');
      expect(cfg.planDropField, 'pd');
      expect(cfg.planPickupField, 'pp');
      expect(cfg.saleField, 'ps');
      expect(cfg.buyField, 'pb');
      expect(cfg.refillField, 'pr');
      expect(cfg.actualDropField, 'ad');
      expect(cfg.actualPickupField, 'ap');
      expect(cfg.actualSaleField, 'as');
      expect(cfg.actualBuyField, 'ab');
      expect(cfg.actualRefillField, 'ar');
    });

    test('reads overrides from component', () {
      final cfg = parseConfigFromComponent(<String, dynamic>{
        'itemsField': 'items',
        'txField': 'type',
        'planDropField': 'drop_plan',
        'actualDropField': 'drop_actual',
      });
      expect(cfg.itemsField, 'items');
      expect(cfg.txField, 'type');
      expect(cfg.planDropField, 'drop_plan');
      expect(cfg.actualDropField, 'drop_actual');
      // Non-overridden fields use defaults
      expect(cfg.planPickupField, 'pp');
      expect(cfg.actualPickupField, 'ap');
    });

    test('trims whitespace from component values', () {
      final cfg = parseConfigFromComponent(<String, dynamic>{
        'itemsField': '  it  ',
        'txField': ' tx ',
      });
      expect(cfg.itemsField, 'it');
      expect(cfg.txField, 'tx');
    });

    test('handles null component values gracefully', () {
      final cfg = parseConfigFromComponent(<String, dynamic>{
        'itemsField': null,
        'txField': null,
      });
      // null falls through to default via ?? operator
      expect(cfg.itemsField, 'it');
      expect(cfg.txField, 'tx');
    });
  });

  group('RBT updateEventRow strip for hook', () {
    // Verifies the strip+body-guard pattern used in ftz_row_of_button_2
    // doSaveProcedure: strip tst/tce from the RBT's component copy,
    // then check if any body remains. For the live P11 form, the body
    // is ONLY tst+tce, so after strip the body is empty.

    test('live P11 RBT form: strip removes all body, key is dropped', () {
      // This is the EXACT updateEventRow value on the P11 "Kirim" RBT:
      // path⭘tablevid◼vid⭘search◼tnm★{activeTaskVid}⭘tst◼completed⭘tce◼◀2▶
      // (◀2▶ is a placeholder that saveSend resolves to the timestamp)
      const String liveForm =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}'
          '\u{2B58}tst\u{25FC}completed\u{2B58}tce\u{25FC}\u{25C0}2\u{25B6}';
      final String stripped = stripTstFromUpdateEventRow(liveForm);
      // tst and tce are gone
      expect(stripped.contains('tst\u{25FC}'), isFalse);
      expect(stripped.contains('tce\u{25FC}'), isFalse);
      // Header survives
      expect(stripped.contains('84214220504259//task'), isTrue);
      expect(stripped.contains('tablevid\u{25FC}20342033315492'), isTrue);
      // No body clause remains -> drop the key entirely
      expect(updateEventRowHasBody(stripped), isFalse);
    });

    test('form with extra body clause: strip keeps the extra clause', () {
      // Hypothetical: updateEventRow carries ost◼pending alongside tst/tce
      const String form =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}{activeTaskVid}'
          '\u{2B58}tst\u{25FC}completed\u{2B58}tce\u{25FC}123'
          '\u{2B58}ost\u{25FC}pending';
      final String stripped = stripTstFromUpdateEventRow(form);
      expect(stripped.contains('tst\u{25FC}'), isFalse);
      expect(stripped.contains('tce\u{25FC}'), isFalse);
      // ost◼pending is a body clause that survives
      expect(stripped.contains('ost\u{25FC}pending'), isTrue);
      expect(updateEventRowHasBody(stripped), isTrue);
    });
  });
}
