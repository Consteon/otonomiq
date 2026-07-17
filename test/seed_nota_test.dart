import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';

void main() {
  // ── DraftItem.toSeedLiMap ─────────────────────────────────────────────
  group('DraftItem.toSeedLiMap', () {
    test('serializes {ii, in, qt, cd:"full"}', () {
      final item = DraftItem(
        ii: '8886008101138',
        itemName: 'Aqua Galon 19 Liter',
        tx: 'seed',
        ps: 3,
      );
      final m = item.toSeedLiMap();
      expect(m, {
        'ii': '8886008101138',
        'in': 'Aqua Galon 19 Liter',
        'qt': 3,
        'cd': 'full',
      });
      expect(m.length, 4); // exactly 4 keys
    });

    test('cd is always "full" regardless of cdo/cdi fields', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'seed', ps: 1,
        cdo: 'empty', cdi: 'empty',
      );
      final m = item.toSeedLiMap();
      expect(m['cd'], 'full');
    });

    test('qt uses ps field as qty holder', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'seed', ps: 7,
      );
      expect(item.toSeedLiMap()['qt'], 7);
    });

    test('zero qty serializes as 0', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'seed', ps: 0,
      );
      expect(item.toSeedLiMap()['qt'], 0);
    });

    test('does NOT include tx, hg, hrg, qo, qi, sub fields', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'seed', ps: 3,
        hg: 45000, qo: 99, qi: 88,
      );
      final m = item.toSeedLiMap();
      expect(m.containsKey('tx'), false);
      expect(m.containsKey('hg'), false);
      expect(m.containsKey('hrg'), false);
      expect(m.containsKey('qo'), false);
      expect(m.containsKey('qi'), false);
      expect(m.containsKey('sub'), false);
    });
  });

  // ── draftToSeedLiArray ────────────────────────────────────────────────
  group('draftToSeedLiArray', () {
    test('empty draft returns empty list', () {
      expect(AdminCreateTaskSupport.draftToSeedLiArray([]), isEmpty);
    });

    test('multiple items serialize in order', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'seed', ps: 5),
      ];
      final arr = AdminCreateTaskSupport.draftToSeedLiArray(items);
      expect(arr.length, 2);
      expect(arr[0]['ii'], 'a');
      expect(arr[0]['qt'], 3);
      expect(arr[0]['cd'], 'full');
      expect(arr[1]['ii'], 'b');
      expect(arr[1]['qt'], 5);
      expect(arr[1]['cd'], 'full');
    });

    test('element shape matches CF contract', () {
      final items = [
        DraftItem(
          ii: '8886008101138', itemName: 'Aqua Galon 19 Liter',
          tx: 'seed', ps: 3,
        ),
      ];
      final arr = AdminCreateTaskSupport.draftToSeedLiArray(items);
      expect(arr[0], {
        'ii': '8886008101138',
        'in': 'Aqua Galon 19 Liter',
        'qt': 3,
        'cd': 'full',
      });
    });
  });

  // ── computeSeedTotalQty ───────────────────────────────────────────────
  group('computeSeedTotalQty', () {
    test('empty list returns 0', () {
      expect(AdminCreateTaskSupport.computeSeedTotalQty([]), 0);
    });

    test('single item returns its ps', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 3),
      ];
      expect(AdminCreateTaskSupport.computeSeedTotalQty(items), 3);
    });

    test('multiple items sum ps', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'seed', ps: 5),
        DraftItem(ii: 'c', itemName: 'C', tx: 'seed', ps: 2),
      ];
      expect(AdminCreateTaskSupport.computeSeedTotalQty(items), 10);
    });

    test('zero-qty items contribute 0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 0),
        DraftItem(ii: 'b', itemName: 'B', tx: 'seed', ps: 3),
      ];
      expect(AdminCreateTaskSupport.computeSeedTotalQty(items), 3);
    });
  });

  // ── allSeedLinesValid ─────────────────────────────────────────────────
  group('allSeedLinesValid', () {
    test('empty list returns true (vacuously)', () {
      expect(AdminCreateTaskSupport.allSeedLinesValid([]), true);
    });

    test('all lines ps >= 1 returns true', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 1),
        DraftItem(ii: 'b', itemName: 'B', tx: 'seed', ps: 5),
      ];
      expect(AdminCreateTaskSupport.allSeedLinesValid(items), true);
    });

    test('any line ps == 0 returns false', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'seed', ps: 0),
      ];
      expect(AdminCreateTaskSupport.allSeedLinesValid(items), false);
    });

    test('single line ps == 1 returns true', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 1),
      ];
      expect(AdminCreateTaskSupport.allSeedLinesValid(items), true);
    });
  });

  // ── assembleNotaDoc seed params ───────────────────────────────────────
  group('assembleNotaDoc seed', () {
    test('seed call includes kl, kn, days when set', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'SEED-2026-000001',
        src: 'seed',
        by: 'Admin A',
        bym: '',
        gl: 'F621558e33b612',
        tot: 0,
        liArray: [
          {'ii': '8886008101138', 'in': 'Aqua Galon 19L', 'qt': 3, 'cd': 'full'},
        ],
        cv: '12345',
        cn: 'Admin A',
        t: 1752624000000,
        ts: '2026-07-16 10:30',
        tableVid: '20342033315492',
        kl: 'CUST-0001',
        kn: 'Toko Contoh Jaya',
        days: 30,
      );
      expect(doc['src'], 'seed');
      expect(doc['kl'], 'CUST-0001');
      expect(doc['kn'], 'Toko Contoh Jaya');
      expect(doc['days'], 30);
      expect(doc['days'] is int, true);
      expect(doc['tot'], 0);
      expect(doc['li'], hasLength(1));
      expect(doc['li'][0]['cd'], 'full');
    });

    test('days omitted when null', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'SEED-2026-000002',
        src: 'seed',
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
        kl: 'CUST-0001',
        kn: 'Toko',
      );
      expect(doc.containsKey('days'), false);
      expect(doc['kl'], 'CUST-0001');
      expect(doc['kn'], 'Toko');
    });

    test('kn omitted when empty', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'SEED-2026-000003',
        src: 'seed',
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
        kl: 'CUST-0001',
        kn: '',
        days: 30,
      );
      expect(doc.containsKey('kn'), false);
      expect(doc['days'], 30);
    });

    test('days=0 is written (not omitted)', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'SEED-2026-000004',
        src: 'seed',
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
        kl: 'C',
        days: 0,
      );
      expect(doc.containsKey('days'), true);
      expect(doc['days'], 0);
    });
  });

  // ── assembleNotaDoc walkin regression ──────────────────────────────────
  group('assembleNotaDoc walkin regression', () {
    test('walkin call (no kl/kn/days) produces identical shape', () {
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
      // kl defaults to '' (same as before)
      expect(doc['kl'], '');
      // Must NOT contain kn or days
      expect(doc.containsKey('kn'), false);
      expect(doc.containsKey('days'), false);
      // Must NOT contain sv/sn/d (default empty)
      expect(doc.containsKey('sv'), false);
      expect(doc.containsKey('sn'), false);
      expect(doc.containsKey('d'), false);
      // Standard fields present
      expect(doc['nno'], 'WLK-2026-000001');
      expect(doc['src'], 'walkin');
      expect(doc['tot'], 90000);
    });
  });

  // ── assembleNotaDoc supplier regression ────────────────────────────────
  group('assembleNotaDoc supplier regression', () {
    test('supplier call (no kl/kn/days) produces identical shape', () {
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
      // kl defaults to '' (same as before)
      expect(doc['kl'], '');
      // Must NOT contain kn or days
      expect(doc.containsKey('kn'), false);
      expect(doc.containsKey('days'), false);
      // Supplier fields present
      expect(doc['sv'], 'SUP-01');
      expect(doc['sn'], 'Tirta Jaya Abadi');
      expect(doc['d'], '5 galon Cleo rusak');
      expect(doc['src'], 'supplier');
    });
  });

  // ── Walkin li[] regression ────────────────────────────────────────────
  group('walkin li[] regression', () {
    test('toLiMap unchanged (qt/hg/sub, no cd)', () {
      final item = DraftItem(
        ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000,
      );
      final m = item.toLiMap();
      expect(m, {
        'ii': 'a',
        'in': 'A',
        'qt': 2,
        'hg': 45000,
        'sub': 90000,
      });
      expect(m.containsKey('cd'), false);
      expect(m.containsKey('tx'), false);
    });

    test('toSeedLiMap does NOT affect toLiMap', () {
      final item = DraftItem(
        ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000,
      );
      // Call toSeedLiMap then toLiMap -- both are independent reads
      item.toSeedLiMap();
      final m = item.toLiMap();
      expect(m['qt'], 2);
      expect(m['hg'], 45000);
      expect(m['sub'], 90000);
    });
  });

  // ── Supplier li[] regression ──────────────────────────────────────────
  group('supplier li[] regression', () {
    test('toSupplierLiMap unchanged', () {
      final item = DraftItem(
        ii: 'a', itemName: 'A', tx: 'buy', qi: 5, hg: 6000,
      );
      final m = item.toSupplierLiMap();
      expect(m, {
        'ii': 'a',
        'in': 'A',
        'tx': 'buy',
        'qo': 0,
        'qi': 5,
        'hrg': 6000,
      });
      expect(m.containsKey('cd'), false);
    });
  });

  // ── Edge: sparse/short text array ─────────────────────────────────────
  group('seed edge cases', () {
    test('seed item with ps=0 fails allSeedLinesValid', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 0),
      ];
      expect(AdminCreateTaskSupport.allSeedLinesValid(items), false);
    });

    test('computeSeedTotalQty with all-zero items returns 0', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'seed', ps: 0),
        DraftItem(ii: 'b', itemName: 'B', tx: 'seed', ps: 0),
      ];
      expect(AdminCreateTaskSupport.computeSeedTotalQty(items), 0);
    });

    test('toSeedLiMap on non-seed tx still produces cd:"full"', () {
      // Edge: calling toSeedLiMap on a DraftItem with tx='deliver'
      // (should never happen in practice but must not crash)
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'deliver', pd: 5, ps: 0,
      );
      final m = item.toSeedLiMap();
      expect(m['cd'], 'full');
      expect(m['qt'], 0); // ps is 0 for deliver items
    });
  });
}
