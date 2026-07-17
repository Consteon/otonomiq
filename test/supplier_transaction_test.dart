import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/task_item_builder.dart';

void main() {
  // ── DraftItem.toSupplierLiMap ──────────────────────────────────────────
  group('DraftItem.toSupplierLiMap', () {
    test('buy line serializes {ii, in, tx, qo:0, qi, hrg}', () {
      final item = DraftItem(
        ii: 'galon19', itemName: 'Aqua Galon 19L', tx: 'buy',
        qi: 5, hg: 6000,
      );
      final m = item.toSupplierLiMap();
      expect(m['ii'], 'galon19');
      expect(m['in'], 'Aqua Galon 19L');
      expect(m['tx'], 'buy');
      expect(m['qo'], 0);
      expect(m['qi'], 5);
      expect(m['hrg'], 6000);
      expect(m.length, 6); // exactly 6 keys
    });

    test('refill line serializes both qo and qi', () {
      final item = DraftItem(
        ii: 'galon19', itemName: 'Aqua Galon 19L', tx: 'refill',
        qo: 5, qi: 5, hg: 6000,
      );
      final m = item.toSupplierLiMap();
      expect(m['tx'], 'refill');
      expect(m['qo'], 5);
      expect(m['qi'], 5);
      expect(m['hrg'], 6000);
    });

    test('sale line serializes qo with qi=0', () {
      final item = DraftItem(
        ii: 'cleo19', itemName: 'Cleo Galon 19L', tx: 'sale',
        qo: 5, hg: 5000,
      );
      final m = item.toSupplierLiMap();
      expect(m['tx'], 'sale');
      expect(m['qo'], 5);
      expect(m['qi'], 0);
      expect(m['hrg'], 5000);
    });

    test('refill with hrg=0 is valid in output', () {
      final item = DraftItem(
        ii: 'galon19', itemName: 'Galon', tx: 'refill',
        qo: 3, qi: 3, hg: 0,
      );
      final m = item.toSupplierLiMap();
      expect(m['hrg'], 0);
    });
  });

  // ── DraftItem qo/qi backward compatibility ──────────────────────────────
  group('DraftItem qo/qi backward compat', () {
    test('qo/qi default to 0', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'deliver');
      expect(item.qo, 0);
      expect(item.qi, 0);
    });

    test('toItMap does NOT include qo/qi (order path unchanged)', () {
      final item = DraftItem(
        ii: 'galon', itemName: 'Galon', tx: 'deliver',
        pd: 5, pp: 3, qo: 99, qi: 88,
      );
      final m = item.toItMap();
      expect(m.containsKey('qo'), false);
      expect(m.containsKey('qi'), false);
      // Existing fields still present
      expect(m['pd'], 5);
      expect(m['pp'], 3);
    });

    test('toLiMap does NOT include qo/qi (walkin path unchanged)', () {
      final item = DraftItem(
        ii: 'aqua', itemName: 'Aqua', tx: 'sale',
        ps: 2, hg: 45000, qo: 77, qi: 66,
      );
      final m = item.toLiMap();
      expect(m.containsKey('qo'), false);
      expect(m.containsKey('qi'), false);
      // Walkin shape unchanged
      expect(m['qt'], 2);
      expect(m['hg'], 45000);
      expect(m['sub'], 90000);
    });

    test('toItMap on buy tx produces zeroed order fields (no crash)', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'buy', qi: 3, hg: 5000,
      );
      final m = item.toItMap();
      expect(m['pd'], 0);
      expect(m['pp'], 0);
      expect(m['ps'], 0);
      expect(m['pb'], 0);
      expect(m['pr'], 0);
      expect(m.containsKey('hg'), false); // buy != sale
    });
  });

  // ── draftToSupplierLiArray ─────────────────────────────────────────────
  group('draftToSupplierLiArray', () {
    test('empty draft returns empty list', () {
      expect(AdminCreateTaskSupport.draftToSupplierLiArray([]), isEmpty);
    });

    test('multiple items serialize in order', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 3, hg: 6000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', qo: 5, hg: 5000),
      ];
      final arr = AdminCreateTaskSupport.draftToSupplierLiArray(items);
      expect(arr.length, 2);
      expect(arr[0]['ii'], 'a');
      expect(arr[0]['tx'], 'buy');
      expect(arr[1]['ii'], 'b');
      expect(arr[1]['tx'], 'sale');
    });

    test('element shape matches CF contract', () {
      final items = [
        DraftItem(
          ii: '8886008101138', itemName: 'Aqua Galon 19 Liter',
          tx: 'refill', qo: 5, qi: 5, hg: 6000,
        ),
      ];
      final arr = AdminCreateTaskSupport.draftToSupplierLiArray(items);
      final m = arr[0];
      expect(m, {
        'ii': '8886008101138',
        'in': 'Aqua Galon 19 Liter',
        'tx': 'refill',
        'qo': 5,
        'qi': 5,
        'hrg': 6000,
      });
    });
  });

  // ── computeSupplierTotal ──────────────────────────────────────────────
  group('computeSupplierTotal', () {
    test('empty list returns 0', () {
      expect(AdminCreateTaskSupport.computeSupplierTotal([]), 0);
    });

    test('buy line: hrg * qi (qi > qo)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 5, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.computeSupplierTotal(items), 30000);
    });

    test('sale line: hrg * qo (qo > qi)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', qo: 5, hg: 5000),
      ];
      expect(AdminCreateTaskSupport.computeSupplierTotal(items), 25000);
    });

    test('refill line: hrg * max(qo, qi)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 5, qi: 5, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.computeSupplierTotal(items), 30000);
    });

    test('refill with hrg=0 contributes 0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 3, qi: 3, hg: 0),
      ];
      expect(AdminCreateTaskSupport.computeSupplierTotal(items), 0);
    });

    test('mixed lines sum correctly', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 5, hg: 6000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', qo: 5, hg: 5000),
      ];
      // 5*6000 + 5*5000 = 55000
      expect(AdminCreateTaskSupport.computeSupplierTotal(items), 55000);
    });

    test('refill with asymmetric qo/qi uses max', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 3, qi: 7, hg: 1000),
      ];
      // max(3,7) * 1000 = 7000
      expect(AdminCreateTaskSupport.computeSupplierTotal(items), 7000);
    });
  });

  // ── allSupplierLinesValid ─────────────────────────────────────────────
  group('allSupplierLinesValid', () {
    test('empty list returns true (vacuously)', () {
      expect(AdminCreateTaskSupport.allSupplierLinesValid([]), true);
    });

    test('buy valid: qi>=1 and hg>0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 1, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), true);
    });

    test('buy invalid: qi=0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 0, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('buy invalid: hg=0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 3, hg: 0),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('sale valid: qo>=1 and hg>0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', qo: 1, hg: 5000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), true);
    });

    test('sale invalid: qo=0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', qo: 0, hg: 5000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('sale invalid: hg=0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', qo: 3, hg: 0),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('refill valid: qo>=1 and qi>=1 (hrg=0 allowed)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 1, qi: 1, hg: 0),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), true);
    });

    test('refill valid: qo>=1 and qi>=1 with hrg>0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 3, qi: 3, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), true);
    });

    test('refill invalid: qo=0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 0, qi: 3, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('refill invalid: qi=0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'refill',
            qo: 3, qi: 0, hg: 6000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('unknown tx returns false', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });

    test('mixed valid lines all pass', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 5, hg: 6000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', qo: 5, hg: 5000),
        DraftItem(ii: 'c', itemName: 'C', tx: 'refill',
            qo: 3, qi: 3, hg: 0),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), true);
    });

    test('one invalid line fails the whole draft', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'buy', qi: 5, hg: 6000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', qo: 0, hg: 5000),
      ];
      expect(AdminCreateTaskSupport.allSupplierLinesValid(items), false);
    });
  });

  // ── assembleNotaDoc supplier vs walkin ─────────────────────────────────
  group('assembleNotaDoc', () {
    test('walkin call (no sv/sn/d) produces identical shape', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'WLK-2026-000001',
        src: 'walkin',
        by: 'Buyer',
        bym: 'tunai',
        gl: 'GL001',
        tot: 90000,
        liArray: [
          {'ii': 'a', 'in': 'A', 'qt': 2, 'hg': 45000, 'sub': 90000},
        ],
        cv: '12345',
        cn: 'Admin',
        t: 1782286245000,
        ts: '2026-06-24 10:30',
        tableVid: '20342033315492',
      );
      // Must NOT contain sv/sn/d
      expect(doc.containsKey('sv'), false);
      expect(doc.containsKey('sn'), false);
      expect(doc.containsKey('d'), false);
      // Standard fields present
      expect(doc['nno'], 'WLK-2026-000001');
      expect(doc['src'], 'walkin');
      expect(doc['ref'], '');
      expect(doc['kl'], '');
      expect(doc['st'], 'LUNAS');
    });

    test('supplier call includes sv/sn/d when non-empty', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'SUP-2026-000001',
        src: 'supplier',
        by: 'Admin A',
        bym: '',
        gl: 'F621558e33b612',
        tot: 55000,
        liArray: [
          {'ii': 'a', 'in': 'A', 'tx': 'refill',
           'qo': 5, 'qi': 5, 'hrg': 6000},
        ],
        cv: '12345',
        cn: 'Admin A',
        t: 1782286245000,
        ts: '2026-06-24 10:30',
        tableVid: '20342033315492',
        sv: 'SUP-01',
        sn: 'Tirta Jaya Abadi',
        d: '5 galon Cleo rusak',
      );
      expect(doc['sv'], 'SUP-01');
      expect(doc['sn'], 'Tirta Jaya Abadi');
      expect(doc['d'], '5 galon Cleo rusak');
      expect(doc['src'], 'supplier');
      expect(doc['by'], 'Admin A');
      expect(doc['tot'], 55000);
    });

    test('supplier call with empty sv/sn/d omits them', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'SUP-2026-000002',
        src: 'supplier',
        by: 'Admin',
        bym: '',
        gl: 'GL',
        tot: 0,
        liArray: [],
        cv: 'vid',
        cn: 'Admin',
        t: 0,
        ts: '',
        tableVid: 'tv',
        sv: '',
        sn: '',
        d: '',
      );
      expect(doc.containsKey('sv'), false);
      expect(doc.containsKey('sn'), false);
      expect(doc.containsKey('d'), false);
    });
  });

  // ── parseTxOptions ────────────────────────────────────────────────────
  group('TaskItemBuilder.parseTxOptions', () {
    test('parses buy◼Beli★refill◼Tukar★sale◼Jual', () {
      // Use literal Unicode chars (pre-decoded)
      final result = TaskItemBuilder.parseTxOptions(
          'buy\u{25FC}Beli\u{2605}refill\u{25FC}Tukar\u{2605}sale\u{25FC}Jual');
      expect(result.length, 3);
      expect(result[0].key, 'buy');
      expect(result[0].value, 'Beli');
      expect(result[1].key, 'refill');
      expect(result[1].value, 'Tukar');
      expect(result[2].key, 'sale');
      expect(result[2].value, 'Jual');
    });

    test('empty input returns empty list', () {
      expect(TaskItemBuilder.parseTxOptions(''), isEmpty);
      expect(TaskItemBuilder.parseTxOptions(null), isEmpty);
    });

    test('single pair without ★ separator', () {
      final result = TaskItemBuilder.parseTxOptions('buy\u{25FC}Beli');
      expect(result.length, 1);
      expect(result[0].key, 'buy');
      expect(result[0].value, 'Beli');
    });

    test('missing label uses value as label', () {
      final result = TaskItemBuilder.parseTxOptions('buy');
      expect(result.length, 1);
      expect(result[0].key, 'buy');
      expect(result[0].value, 'buy'); // value used as label
    });

    test('encoded _u25FC_ and _u2605_ are decoded', () {
      final result = TaskItemBuilder.parseTxOptions(
          'buy_u25FC_Beli_u2605_sale_u25FC_Jual');
      expect(result.length, 2);
      expect(result[0].key, 'buy');
      expect(result[0].value, 'Beli');
      expect(result[1].key, 'sale');
      expect(result[1].value, 'Jual');
    });

    test('trims whitespace in values and labels', () {
      final result = TaskItemBuilder.parseTxOptions(
          ' buy \u{25FC} Beli \u{2605} sale \u{25FC} Jual ');
      expect(result[0].key, 'buy');
      expect(result[0].value, 'Beli');
      expect(result[1].key, 'sale');
      expect(result[1].value, 'Jual');
    });

    test('skips pairs with empty value', () {
      final result = TaskItemBuilder.parseTxOptions(
          '\u{25FC}EmptyVal\u{2605}sale\u{25FC}Jual');
      expect(result.length, 1);
      expect(result[0].key, 'sale');
    });
  });

  // ── Walkin regression: draftToLiArray + computeTotals unchanged ────────
  group('walkin regression', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
    });

    test('draftToLiArray walkin shape unchanged (qt/hg/sub, no qo/qi)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000),
      ];
      final arr = AdminCreateTaskSupport.draftToLiArray(items);
      expect(arr.length, 1);
      expect(arr[0], {
        'ii': 'a',
        'in': 'A',
        'qt': 2,
        'hg': 45000,
        'sub': 90000,
      });
      expect(arr[0].containsKey('qo'), false);
      expect(arr[0].containsKey('qi'), false);
      expect(arr[0].containsKey('tx'), false);
    });

    test('computeTotals walkin unchanged (sale price = hg*ps)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 3, hg: 10000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 120000); // (2*45000) + (3*10000)
    });

    test('DraftItem with qo/qi set does not affect toLiMap output', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'sale',
        ps: 5, hg: 10000, qo: 99, qi: 88,
      );
      final m = item.toLiMap();
      expect(m['qt'], 5); // uses ps, not qo/qi
      expect(m['sub'], 50000); // ps * hg
      expect(m.containsKey('qo'), false);
      expect(m.containsKey('qi'), false);
    });
  });
}
