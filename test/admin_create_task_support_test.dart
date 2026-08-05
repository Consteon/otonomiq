import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';

void main() {
  // ── DraftItem.toItMap ───────────────────────────────────────────────
  group('DraftItem.toItMap', () {
    test('deliver line sets pd/pp, zeros others', () {
      final item = DraftItem(
        ii: 'galon', itemName: 'Galon 19L', tx: 'deliver',
        pd: 5, pp: 3, cdo: 'full', cdi: 'empty',
      );
      final m = item.toItMap();
      expect(m['ii'], 'galon');
      expect(m['in'], 'Galon 19L');
      expect(m['tx'], 'deliver');
      expect(m['pd'], 5);
      expect(m['pp'], 3);
      expect(m['ps'], 0);
      expect(m['pb'], 0);
      expect(m['pr'], 0);
      expect(m['cdo'], 'full');
      expect(m['cdi'], 'empty');
      expect(m['wt'], '');
    });

    test('sale line sets ps, zeros pd/pp/pb/pr', () {
      final item = DraftItem(
        ii: 'aqua600', itemName: 'Aqua 600mL', tx: 'sale',
        ps: 10, cdo: 'full',
      );
      final m = item.toItMap();
      expect(m['tx'], 'sale');
      expect(m['ps'], 10);
      expect(m['pd'], 0);
      expect(m['pp'], 0);
      expect(m['pb'], 0);
      expect(m['pr'], 0);
      expect(m['cdo'], 'full');
      expect(m['cdi'], '');
      expect(m['wt'], '');
    });

    test('purchase line sets pb, zeros others', () {
      final item = DraftItem(
        ii: 'lpg3', itemName: 'LPG 3kg', tx: 'purchase',
        pb: 7, cdi: 'empty',
      );
      final m = item.toItMap();
      expect(m['tx'], 'purchase');
      expect(m['pb'], 7);
      expect(m['pd'], 0);
      expect(m['pp'], 0);
      expect(m['ps'], 0);
      expect(m['pr'], 0);
      expect(m['cdo'], '');
      expect(m['cdi'], 'empty');
      expect(m['wt'], '');
    });

    test('refill line sets pr and wt, zeros others', () {
      final item = DraftItem(
        ii: 'galon', itemName: 'Galon 19L', tx: 'refill',
        pr: 3, wt: 'ro',
      );
      final m = item.toItMap();
      expect(m['tx'], 'refill');
      expect(m['pr'], 3);
      expect(m['pd'], 0);
      expect(m['pp'], 0);
      expect(m['ps'], 0);
      expect(m['pb'], 0);
      expect(m['cdo'], '');
      expect(m['cdi'], '');
      expect(m['wt'], 'ro');
    });
  });

  // ── DraftItem.primaryQty ───────────────────────────────────────────
  group('DraftItem.primaryQty', () {
    test('deliver returns pd', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'deliver', pd: 5);
      expect(item.primaryQty, 5);
    });

    test('sale returns ps', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'sale', ps: 3);
      expect(item.primaryQty, 3);
    });

    test('purchase returns pb', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'purchase', pb: 7);
      expect(item.primaryQty, 7);
    });

    test('refill returns pr', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'refill', pr: 2);
      expect(item.primaryQty, 2);
    });

    test('unknown tx returns 0', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'unknown', pd: 99);
      expect(item.primaryQty, 0);
    });
  });

  // ── draftToItArray ──────────────────────────────────────────────────
  group('draftToItArray', () {
    test('empty draft returns empty list', () {
      expect(AdminCreateTaskSupport.draftToItArray([]), isEmpty);
    });

    test('multiple items serialize in order', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 1),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2),
      ];
      final arr = AdminCreateTaskSupport.draftToItArray(items);
      expect(arr.length, 2);
      expect(arr[0]['ii'], 'a');
      expect(arr[1]['ii'], 'b');
    });

    test('every element carries ad+ap present with null value (mixed tx types)', () {
      // Regression: ad/ap must survive the array-build path (draftToItArray),
      // not just single toItMap(). CF custody/confirm falls back to plan when
      // the field is ABSENT -- containsKey is the load-bearing assertion.
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 45000),
        DraftItem(ii: 'c', itemName: 'C', tx: 'purchase', pb: 4),
        DraftItem(ii: 'd', itemName: 'D', tx: 'refill', pr: 3),
      ];
      final arr = AdminCreateTaskSupport.draftToItArray(items);
      expect(arr.length, 4);
      for (int i = 0; i < arr.length; i++) {
        final m = arr[i];
        expect(m.containsKey('ad'), isTrue,
            reason: 'ad must be present at index $i (${m['tx']})');
        expect(m.containsKey('ap'), isTrue,
            reason: 'ap must be present at index $i (${m['tx']})');
        expect(m['ad'], isNull,
            reason: 'ad must be null at index $i (${m['tx']})');
        expect(m['ap'], isNull,
            reason: 'ap must be null at index $i (${m['tx']})');
      }
    });
  });

  // ── computeTotals ──────────────────────────────────────────────────
  group('computeTotals', () {
    test('empty list returns all zeros', () {
      final t = AdminCreateTaskSupport.computeTotals([]);
      expect(t.totalDrop, 0);
      expect(t.totalPickup, 0);
      expect(t.totalSale, 0);
      expect(t.totalPurchase, 0);
      expect(t.totalRefill, 0);
      expect(t.lineCount, 0);
    });

    test('mixed tx types sum correctly', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'deliver', pd: 2, pp: 1),
        DraftItem(ii: 'c', itemName: 'C', tx: 'sale', ps: 10),
        DraftItem(ii: 'd', itemName: 'D', tx: 'purchase', pb: 4),
        DraftItem(ii: 'e', itemName: 'E', tx: 'refill', pr: 6),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalDrop, 7);
      expect(t.totalPickup, 4);
      expect(t.totalSale, 10);
      expect(t.totalPurchase, 4);
      expect(t.totalRefill, 6);
      expect(t.lineCount, 5);
    });

    test('unknown tx type is ignored in totals', () {
      final items = [
        DraftItem(ii: 'x', itemName: 'X', tx: 'unknown', pd: 99),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalDrop, 0);
      expect(t.lineCount, 1);
    });
  });

  // ── generateTnm ────────────────────────────────────────────────────
  group('generateTnm', () {
    test('format is TASK-{kl7}-{yyyyMMdd}-{HHmmss}', () {
      // 2026-06-24 10:30:45 WIB = 2026-06-24 03:30:45 UTC
      // UTC epoch ms: 1782286245000
      final int epochMs = 1782286245000;
      final tnm = AdminCreateTaskSupport.generateTnm('CUST-LONG-ID',
          nowMs: epochMs);
      expect(tnm, startsWith('TASK-CUST-LO-')); // 7 chars of kl
      expect(tnm, contains('20260624'));
    });

    test('short kl is not padded', () {
      final tnm = AdminCreateTaskSupport.generateTnm('ABC', nowMs: 1782286245000);
      expect(tnm, startsWith('TASK-ABC-'));
    });

    test('empty kl produces TASK--date-time', () {
      final tnm = AdminCreateTaskSupport.generateTnm('', nowMs: 1782286245000);
      expect(tnm, startsWith('TASK--'));
    });
  });

  // ── lookupOutstanding ──────────────────────────────────────────────
  group('lookupOutstanding', () {
    final docs = <Map<String, dynamic>>[
      {'lv': 'C1', 'ii': 'galon', 'cd': 'full', 'qt': 5},
      {'lv': 'C1', 'ii': 'galon', 'cd': 'empty', 'qt': 2},
      {'lv': 'C2', 'ii': 'galon', 'cd': 'full', 'qt': 10},
    ];

    test('returns qt when match found', () {
      expect(
        AdminCreateTaskSupport.lookupOutstanding(docs,
            clientLv: 'C1', itemIi: 'galon', condition: 'full'),
        5,
      );
    });

    test('returns 0 when no match (different client)', () {
      expect(
        AdminCreateTaskSupport.lookupOutstanding(docs,
            clientLv: 'C99', itemIi: 'galon', condition: 'full'),
        0,
      );
    });

    test('returns 0 when empty docs (genesis pending)', () {
      expect(
        AdminCreateTaskSupport.lookupOutstanding([],
            clientLv: 'C1', itemIi: 'galon', condition: 'full'),
        0,
      );
    });

    test('handles null/dynamic qt gracefully', () {
      final badDocs = <Map<String, dynamic>>[
        {'lv': 'C1', 'ii': 'galon', 'cd': 'full', 'qt': null},
      ];
      expect(
        AdminCreateTaskSupport.lookupOutstanding(badDocs,
            clientLv: 'C1', itemIi: 'galon', condition: 'full'),
        0,
      );
    });

    test('handles string qt', () {
      final stringDocs = <Map<String, dynamic>>[
        {'lv': 'C1', 'ii': 'galon', 'cd': 'full', 'qt': '7'},
      ];
      expect(
        AdminCreateTaskSupport.lookupOutstanding(stringDocs,
            clientLv: 'C1', itemIi: 'galon', condition: 'full'),
        7,
      );
    });
  });

  // ── hasOutstandingData ─────────────────────────────────────────────
  group('hasOutstandingData', () {
    test('returns true when client has any row', () {
      final docs = <Map<String, dynamic>>[
        {'lv': 'C1', 'ii': 'galon', 'cd': 'full', 'qt': 5},
      ];
      expect(AdminCreateTaskSupport.hasOutstandingData(docs, 'C1'), true);
    });

    test('returns false when no rows for client', () {
      final docs = <Map<String, dynamic>>[
        {'lv': 'C2', 'ii': 'galon', 'cd': 'full', 'qt': 5},
      ];
      expect(AdminCreateTaskSupport.hasOutstandingData(docs, 'C1'), false);
    });

    test('returns false when docs empty', () {
      expect(AdminCreateTaskSupport.hasOutstandingData([], 'C1'), false);
    });
  });

  // ── suggestPickup ──────────────────────────────────────────────────
  group('suggestPickup', () {
    final docs = <Map<String, dynamic>>[
      {'lv': 'C1', 'ii': 'galon', 'cd': 'full', 'qt': 3},
    ];

    test('returns pd + outstanding when data exists', () {
      expect(
        AdminCreateTaskSupport.suggestPickup(
          pd: 5,
          assetCacheDocs: docs,
          clientLv: 'C1',
          itemIi: 'galon',
          condition: 'full',
        ),
        8, // 5 + 3
      );
    });

    test('returns null when no asset_cache data for client', () {
      expect(
        AdminCreateTaskSupport.suggestPickup(
          pd: 5,
          assetCacheDocs: docs,
          clientLv: 'C99',
          itemIi: 'galon',
          condition: 'full',
        ),
        isNull,
      );
    });

    test('returns null when docs empty (CF undeployed)', () {
      expect(
        AdminCreateTaskSupport.suggestPickup(
          pd: 5,
          assetCacheDocs: [],
          clientLv: 'C1',
          itemIi: 'galon',
          condition: 'full',
        ),
        isNull,
      );
    });

    test('floors at 0 when pd + outstanding would be negative', () {
      final negDocs = <Map<String, dynamic>>[
        {'lv': 'C1', 'ii': 'galon', 'cd': 'full', 'qt': -10},
      ];
      expect(
        AdminCreateTaskSupport.suggestPickup(
          pd: 2,
          assetCacheDocs: negDocs,
          clientLv: 'C1',
          itemIi: 'galon',
          condition: 'full',
        ),
        0,
      );
    });
  });

  // ── assembleTaskDoc ────────────────────────────────────────────────
  group('assembleTaskDoc', () {
    test('contains all required fields', () {
      final doc = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'TASK-ABC-20260624-103045',
        kl: 'C1',
        kn: 'Honda',
        al: 'Jl. Sudirman 54',
        vv: 'VEH-123',
        gl: 'WH-001',
        cv: '12345',
        cn: 'Admin A',
        tdt: 1782244800000,
        t: 1782286245000,
        itArray: [{'ii': 'galon', 'in': 'Galon', 'tx': 'deliver', 'pd': 5, 'pp': 3, 'ps': 0, 'pb': 0, 'pr': 0, 'cdo': 'full', 'cdi': 'empty', 'wt': ''}],
        tableVid: '20342033315492',
      );
      expect(doc['tnm'], 'TASK-ABC-20260624-103045');
      expect(doc['tty'], 'delivery');
      expect(doc['tst'], 'assigned');
      expect(doc['kl'], 'C1');
      expect(doc['kn'], 'Honda');
      expect(doc['al'], 'Jl. Sudirman 54');
      expect(doc['vv'], 'VEH-123');
      expect(doc['gl'], 'WH-001');
      expect(doc['cv'], '12345');
      expect(doc['cn'], 'Admin A');
      expect(doc['t'], 1782286245000);
      expect(doc['tdt'], 1782244800000);
      expect(doc['it'], isA<List>());
      expect((doc['it'] as List).length, 1);
      expect(doc['tablevid'], '20342033315492');
      expect(doc['search'], contains('TASK-ABC'));
    });

    test('empty scalars: vv/tdt omitted when empty/null, others preserved', () {
      final doc = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'TASK--20260624-000000',
        kl: '', kn: '', al: '', vv: '', gl: '',
        cv: '', cn: '',
        tdt: null, t: 0,
        itArray: [],
        tableVid: '',
      );
      // vv passed as '' -> omitted (D4: absent, not empty)
      expect(doc.containsKey('vv'), isFalse,
          reason: 'vv must be absent when empty');
      // tdt passed as null -> omitted
      expect(doc.containsKey('tdt'), isFalse,
          reason: 'tdt must be absent when null');
      // ln defaults to '' -> omitted
      expect(doc.containsKey('ln'), isFalse,
          reason: 'ln must be absent when empty');
      // Other scalars are still present (even when empty)
      expect(doc['kl'], '');
      expect(doc['tst'], 'assigned');
      expect(doc['it'], isEmpty);
    });

    test('it[] in assembled doc carries ad+ap present+null on every line', () {
      // Regression end-to-end: the field must reach the real Firestore payload.
      // Build itArray via draftToItArray (the production path), then assemble
      // the doc and verify each it[] element still has ad/ap present+null.
      final items = [
        DraftItem(ii: 'galon', itemName: 'Galon 19L', tx: 'deliver',
            pd: 5, pp: 3),
        DraftItem(ii: 'aqua', itemName: 'Aqua 600mL', tx: 'sale',
            ps: 2, hg: 45000),
      ];
      final itArray = AdminCreateTaskSupport.draftToItArray(items);
      final doc = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'TASK-C1-20260701-100000',
        kl: 'C1',
        kn: 'Toko Maju',
        al: 'Jl. Sudirman',
        vv: 'VEH-001',
        gl: 'WH-001',
        cv: '12345',
        cn: 'Admin A',
        tdt: 1782244800000,
        t: 1782286245000,
        itArray: itArray,
        tableVid: '20342033315492',
      );
      final it = doc['it'] as List;
      expect(it.length, 2);
      for (int i = 0; i < it.length; i++) {
        final m = it[i] as Map<String, dynamic>;
        expect(m.containsKey('ad'), isTrue,
            reason: 'ad must be present in doc.it[$i] (${m['tx']})');
        expect(m.containsKey('ap'), isTrue,
            reason: 'ap must be present in doc.it[$i] (${m['tx']})');
        expect(m['ad'], isNull,
            reason: 'ad must be null in doc.it[$i] (${m['tx']})');
        expect(m['ap'], isNull,
            reason: 'ap must be null in doc.it[$i] (${m['tx']})');
      }
    });

    test('tst override: unassigned status written to doc', () {
      final doc = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'TASK-C1-20260803-100000',
        kl: 'C1', kn: 'Toko A', al: 'Jl. Raya',
        vv: '', gl: 'WH-001', cv: '12345', cn: 'Admin',
        tdt: null, t: 1000, itArray: [], tableVid: 'VID',
        tst: 'unassigned',
      );
      expect(doc['tst'], 'unassigned');
      expect(doc.containsKey('vv'), isFalse);
      expect(doc.containsKey('tdt'), isFalse);
    });

    test('vv present when non-empty, absent when empty', () {
      final withVv = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T1', kl: '', kn: '', al: '', vv: 'VEH-123',
        gl: '', cv: '', cn: '',
        tdt: null, t: 0, itArray: [], tableVid: '',
      );
      expect(withVv['vv'], 'VEH-123');

      final withoutVv = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T2', kl: '', kn: '', al: '', vv: '',
        gl: '', cv: '', cn: '',
        tdt: null, t: 0, itArray: [], tableVid: '',
      );
      expect(withoutVv.containsKey('vv'), isFalse);
    });

    test('ln present when non-empty, absent when empty', () {
      final withLn = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T1', kl: '', kn: '', al: '', vv: '',
        gl: '', cv: '', cn: '',
        tdt: null, t: 0, itArray: [], tableVid: '',
        ln: 'B 1234 XY',
      );
      expect(withLn['ln'], 'B 1234 XY');

      final withoutLn = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T2', kl: '', kn: '', al: '', vv: '',
        gl: '', cv: '', cn: '',
        tdt: null, t: 0, itArray: [], tableVid: '',
      );
      expect(withoutLn.containsKey('ln'), isFalse);
    });

    test('tdt present when non-null, absent when null', () {
      final withTdt = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T1', kl: '', kn: '', al: '', vv: '',
        gl: '', cv: '', cn: '',
        tdt: 1782244800000, t: 0, itArray: [], tableVid: '',
      );
      expect(withTdt['tdt'], 1782244800000);

      final withoutTdt = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T2', kl: '', kn: '', al: '', vv: '',
        gl: '', cv: '', cn: '',
        tdt: null, t: 0, itArray: [], tableVid: '',
      );
      expect(withoutTdt.containsKey('tdt'), isFalse);
    });
  });

  // ── Draft holder lifecycle ─────────────────────────────────────────
  group('draft holder', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
    });

    test('getDraft creates empty list on first access', () {
      final draft = AdminCreateTaskSupport.getDraft('wiz1');
      expect(draft, isEmpty);
    });

    test('getDraft returns same list on repeated access', () {
      final d1 = AdminCreateTaskSupport.getDraft('wiz1');
      d1.add(DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'));
      final d2 = AdminCreateTaskSupport.getDraft('wiz1');
      expect(d2.length, 1);
      expect(identical(d1, d2), true);
    });

    test('clearDraft removes wizard key', () {
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      AdminCreateTaskSupport.clearDraft('wiz1');
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
    });

    test('clearAllDrafts removes everything', () {
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      AdminCreateTaskSupport.getDraft('wiz2').add(
        DraftItem(ii: 'y', itemName: 'Y', tx: 'sale'),
      );
      AdminCreateTaskSupport.clearAllDrafts();
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getDraft('wiz2'), isEmpty);
    });
  });

  // ── Draft customer holder ─────────────────────────────────────────
  group('draft customer', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
    });

    test('getCustomer returns null when not set', () {
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
    });

    test('setCustomer + getCustomer round-trip', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Toko Maju', al: 'Jl. Sudirman 54');
      final c = AdminCreateTaskSupport.getCustomer('wiz1');
      expect(c, isNotNull);
      expect(c!['kl'], 'C1');
      expect(c['kn'], 'Toko Maju');
      expect(c['al'], 'Jl. Sudirman 54');
    });

    test('setCustomer overwrites prior value', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Old', al: 'Old Addr');
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C2', kn: 'New', al: 'New Addr');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kl'], 'C2');
      expect(c['kn'], 'New');
    });

    test('clearDraft removes customer for that wizard key', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Name', al: 'Addr');
      AdminCreateTaskSupport.setCustomer('wiz2',
          kl: 'C2', kn: 'Name2', al: 'Addr2');
      AdminCreateTaskSupport.clearDraft('wiz1');
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getCustomer('wiz2'), isNotNull);
    });

    test('clearAllDrafts removes all customers', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'N1', al: 'A1');
      AdminCreateTaskSupport.setCustomer('wiz2',
          kl: 'C2', kn: 'N2', al: 'A2');
      AdminCreateTaskSupport.clearAllDrafts();
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getCustomer('wiz2'), isNull);
    });

    test('setCustomer with empty fields is valid', () {
      AdminCreateTaskSupport.setCustomer('wiz1', kl: '', kn: '', al: '');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kl'], '');
      expect(c['kn'], '');
      expect(c['al'], '');
    });

    test('customer is independent of items', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Name', al: 'Addr');
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNotNull);
      expect(AdminCreateTaskSupport.getDraft('wiz1').length, 1);
    });

    test('setCustomer + getCustomer round-trips pic', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Toko Maju', al: 'Jl. Sudirman 54',
          pic: 'Pak Budi \u{00B7} 081234567890');
      final c = AdminCreateTaskSupport.getCustomer('wiz1');
      expect(c, isNotNull);
      expect(c!['kl'], 'C1');
      expect(c['kn'], 'Toko Maju');
      expect(c['al'], 'Jl. Sudirman 54');
      expect(c['pic'], 'Pak Budi \u{00B7} 081234567890');
    });

    test('setCustomer pic defaults to empty string when omitted', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Name', al: 'Addr');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['pic'], '');
    });

    test('setCustomer overwrites pic on re-pick', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Old', al: 'Old Addr',
          pic: 'Old PIC');
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C2', kn: 'New', al: 'New Addr',
          pic: 'New PIC');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['pic'], 'New PIC');
    });

    test('clearDraft removes pic along with other customer fields', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Name', al: 'Addr', pic: 'PIC');
      AdminCreateTaskSupport.clearDraft('wiz1');
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
    });

    test('clearAllDrafts removes pic along with all customer fields', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'N1', al: 'A1', pic: 'P1');
      AdminCreateTaskSupport.setCustomer('wiz2',
          kl: 'C2', kn: 'N2', al: 'A2', pic: 'P2');
      AdminCreateTaskSupport.clearAllDrafts();
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getCustomer('wiz2'), isNull);
    });

    test('pic is independent of items and vehicle', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Name', al: 'Addr', pic: 'Contact');
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'Plate');
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['pic'], 'Contact');
      expect(AdminCreateTaskSupport.getVehicle('wiz1')!['vv'], 'V1');
      expect(AdminCreateTaskSupport.getDraft('wiz1').length, 1);
    });
  });

  // ── Draft vehicle holder ──────────────────────────────────────────
  group('draft vehicle', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
    });

    test('getVehicle returns null when not set', () {
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
    });

    test('setVehicle + getVehicle round-trip', () {
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'B 1234 XY');
      final v = AdminCreateTaskSupport.getVehicle('wiz1');
      expect(v, isNotNull);
      expect(v!['vv'], 'V1');
      expect(v['vn'], 'B 1234 XY');
    });

    test('setVehicle overwrites prior value', () {
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'Old Plate');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V2', vn: 'New Plate');
      final v = AdminCreateTaskSupport.getVehicle('wiz1')!;
      expect(v['vv'], 'V2');
      expect(v['vn'], 'New Plate');
    });

    test('clearDraft removes vehicle for that wizard key', () {
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'P1');
      AdminCreateTaskSupport.setVehicle('wiz2', vv: 'V2', vn: 'P2');
      AdminCreateTaskSupport.clearDraft('wiz1');
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz2'), isNotNull);
    });

    test('clearAllDrafts removes all vehicles', () {
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'P1');
      AdminCreateTaskSupport.setVehicle('wiz2', vv: 'V2', vn: 'P2');
      AdminCreateTaskSupport.clearAllDrafts();
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz2'), isNull);
    });

    test('clearDraft clears items + customer + vehicle together', () {
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'N', al: 'A');
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'Plate');
      AdminCreateTaskSupport.clearDraft('wiz1');
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
    });

    test('clearAllDrafts clears all items + customers + vehicles', () {
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver'),
      );
      AdminCreateTaskSupport.getDraft('wiz2').add(
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale'),
      );
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'N1', al: 'A1');
      AdminCreateTaskSupport.setCustomer('wiz2',
          kl: 'C2', kn: 'N2', al: 'A2');
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'P1');
      AdminCreateTaskSupport.setVehicle('wiz2', vv: 'V2', vn: 'P2');
      AdminCreateTaskSupport.clearAllDrafts();
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getDraft('wiz2'), isEmpty);
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getCustomer('wiz2'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz2'), isNull);
    });
  });

  // ── DraftItem.hg price field ──────────────────────────────────────────
  group('DraftItem.hg', () {
    test('defaults to 0', () {
      final item = DraftItem(ii: 'x', itemName: 'X', tx: 'sale');
      expect(item.hg, 0);
    });

    test('constructor accepts hg', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'sale', ps: 2, hg: 45000,
      );
      expect(item.hg, 45000);
    });

    test('toItMap includes hg for sale rows', () {
      final item = DraftItem(
        ii: 'aqua', itemName: 'Aqua 600mL', tx: 'sale',
        ps: 2, cdo: 'full', hg: 45000,
      );
      final m = item.toItMap();
      expect(m.containsKey('hg'), true);
      expect(m['hg'], 45000);
    });

    test('toItMap includes hg=0 for sale rows with no price', () {
      final item = DraftItem(
        ii: 'aqua', itemName: 'Aqua', tx: 'sale', ps: 1,
      );
      final m = item.toItMap();
      expect(m.containsKey('hg'), true);
      expect(m['hg'], 0);
    });

    test('toItMap excludes hg for deliver rows', () {
      final item = DraftItem(
        ii: 'galon', itemName: 'Galon', tx: 'deliver',
        pd: 5, pp: 3, hg: 99999,
      );
      final m = item.toItMap();
      expect(m.containsKey('hg'), false);
    });

    test('toItMap excludes hg for purchase rows', () {
      final item = DraftItem(
        ii: 'lpg', itemName: 'LPG', tx: 'purchase',
        pb: 7, hg: 10000,
      );
      final m = item.toItMap();
      expect(m.containsKey('hg'), false);
    });

    test('toItMap excludes hg for refill rows', () {
      final item = DraftItem(
        ii: 'galon', itemName: 'Galon', tx: 'refill',
        pr: 3, hg: 5000,
      );
      final m = item.toItMap();
      expect(m.containsKey('hg'), false);
    });

    test('hg is mutable (inline edit)', () {
      final item = DraftItem(
        ii: 'x', itemName: 'X', tx: 'sale', ps: 1, hg: 10000,
      );
      item.hg = 25000;
      expect(item.hg, 25000);
      expect(item.toItMap()['hg'], 25000);
    });

    test('sale row: ad+ap present+null alongside hg (coexistence)', () {
      // Guards against a future refactor that drops ad/ap inside the sale
      // branch when adding hg. The hg conditional block is AFTER the base map
      // that sets ad/ap -- both must appear together.
      final item = DraftItem(
        ii: 'aqua', itemName: 'Aqua 600mL', tx: 'sale',
        ps: 3, cdo: 'full', hg: 45000,
      );
      final m = item.toItMap();
      // hg must be present with the specified price
      expect(m.containsKey('hg'), isTrue);
      expect(m['hg'], 45000);
      // ad/ap must be present with null despite the hg conditional
      expect(m.containsKey('ad'), isTrue);
      expect(m.containsKey('ap'), isTrue);
      expect(m['ad'], isNull);
      expect(m['ap'], isNull);
    });
  });

  // ── formatRupiah ──────────────────────────────────────────────────────
  group('formatRupiah', () {
    test('zero', () {
      expect(AdminCreateTaskSupport.formatRupiah(0), 'Rp 0');
    });

    test('small amount (no dots)', () {
      expect(AdminCreateTaskSupport.formatRupiah(500), 'Rp 500');
    });

    test('thousands', () {
      expect(AdminCreateTaskSupport.formatRupiah(5000), 'Rp 5.000');
    });

    test('tens of thousands', () {
      expect(AdminCreateTaskSupport.formatRupiah(45000), 'Rp 45.000');
    });

    test('hundreds of thousands', () {
      expect(AdminCreateTaskSupport.formatRupiah(250000), 'Rp 250.000');
    });

    test('millions', () {
      expect(AdminCreateTaskSupport.formatRupiah(1250000), 'Rp 1.250.000');
    });

    test('negative amount', () {
      expect(AdminCreateTaskSupport.formatRupiah(-5000), 'Rp -5.000');
    });

    test('single digit', () {
      expect(AdminCreateTaskSupport.formatRupiah(7), 'Rp 7');
    });

    test('exact thousand', () {
      expect(AdminCreateTaskSupport.formatRupiah(1000), 'Rp 1.000');
    });

    test('large amount', () {
      expect(AdminCreateTaskSupport.formatRupiah(99999999), 'Rp 99.999.999');
    });
  });

  // ── computeTotals.totalSalePrice ──────────────────────────────────────
  group('computeTotals.totalSalePrice', () {
    test('zero when no sale lines', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'refill', pr: 2),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 0);
    });

    test('single sale line', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 90000); // 2 * 45000
      expect(t.totalSale, 2);
    });

    test('multiple sale lines sum correctly', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 3, hg: 10000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 120000); // (2*45000) + (3*10000)
      expect(t.totalSale, 5);
    });

    test('mixed tx types -- only sale contributes to price', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 10, pp: 5),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 1, hg: 50000),
        DraftItem(ii: 'c', itemName: 'C', tx: 'purchase', pb: 3),
        DraftItem(ii: 'd', itemName: 'D', tx: 'refill', pr: 2),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 50000);
      expect(t.totalDrop, 10);
      expect(t.totalPickup, 5);
      expect(t.totalPurchase, 3);
      expect(t.totalRefill, 2);
    });

    test('sale line with hg=0 contributes 0 to price', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 5, hg: 0),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 0);
      expect(t.totalSale, 5);
    });

    test('sale line with ps=0 contributes 0 to price', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 0, hg: 45000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 0);
      expect(t.totalSale, 0);
    });
  });

  // ── draftToItArray with hg ────────────────────────────────────────────
  group('draftToItArray with hg', () {
    test('sale item includes hg in serialized map', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 2, hg: 45000),
      ];
      final arr = AdminCreateTaskSupport.draftToItArray(items);
      expect(arr.length, 1);
      expect(arr[0]['hg'], 45000);
      expect(arr[0]['tx'], 'sale');
    });

    test('deliver item does not include hg in serialized map', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5),
      ];
      final arr = AdminCreateTaskSupport.draftToItArray(items);
      expect(arr[0].containsKey('hg'), false);
    });

    test('mixed items -- only sale has hg', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 10, pp: 5),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 45000),
        DraftItem(ii: 'c', itemName: 'C', tx: 'refill', pr: 3),
      ];
      final arr = AdminCreateTaskSupport.draftToItArray(items);
      expect(arr[0].containsKey('hg'), false);
      expect(arr[1]['hg'], 45000);
      expect(arr[2].containsKey('hg'), false);
    });
  });

  // ── lastCreated holder ──────────────────────────────────────────────────
  group('lastCreated holder', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
      AdminCreateTaskSupport.lastCreated.clear(); // reset for test isolation
    });

    test('getLastCreated returns null when not set', () {
      expect(AdminCreateTaskSupport.getLastCreated('wiz1'), isNull);
    });

    test('setLastCreated + getLastCreated round-trip', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'TASK-ABC-20260630-100000',
          kn: 'Toko Maju',
          vn: 'B 1234 XY',
          totalDrop: 7,
          totalPickup: 4);
      final m = AdminCreateTaskSupport.getLastCreated('wiz1');
      expect(m, isNotNull);
      expect(m!['tnm'], 'TASK-ABC-20260630-100000');
      expect(m['kn'], 'Toko Maju');
      expect(m['vn'], 'B 1234 XY');
      expect(m['totalDrop'], 7);
      expect(m['totalPickup'], 4);
    });

    test('lastCreated survives clearDraft', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T1', kn: 'K', vn: 'V', totalDrop: 1, totalPickup: 2);
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      AdminCreateTaskSupport.clearDraft('wiz1');
      // Draft is gone but lastCreated is still there
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getLastCreated('wiz1'), isNotNull);
      expect(AdminCreateTaskSupport.getLastCreated('wiz1')!['tnm'], 'T1');
    });

    test('lastCreated survives clearAllDrafts', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T1', kn: 'K', vn: 'V', totalDrop: 1, totalPickup: 2);
      AdminCreateTaskSupport.setLastCreated('wiz2',
          tnm: 'T2', kn: 'K2', vn: 'V2', totalDrop: 3, totalPickup: 4);
      AdminCreateTaskSupport.clearAllDrafts();
      expect(AdminCreateTaskSupport.getLastCreated('wiz1'), isNotNull);
      expect(AdminCreateTaskSupport.getLastCreated('wiz2'), isNotNull);
    });

    test('overwrite on re-create', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'OLD', kn: 'OldK', vn: 'OldV', totalDrop: 1, totalPickup: 2);
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'NEW', kn: 'NewK', vn: 'NewV', totalDrop: 10, totalPickup: 5);
      final m = AdminCreateTaskSupport.getLastCreated('wiz1')!;
      expect(m['tnm'], 'NEW');
      expect(m['kn'], 'NewK');
      expect(m['totalDrop'], 10);
    });

    test('wizard keys are independent', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T1', kn: 'K1', vn: 'V1', totalDrop: 1, totalPickup: 1);
      AdminCreateTaskSupport.setLastCreated('wiz2',
          tnm: 'T2', kn: 'K2', vn: 'V2', totalDrop: 2, totalPickup: 2);
      expect(AdminCreateTaskSupport.getLastCreated('wiz1')!['tnm'], 'T1');
      expect(AdminCreateTaskSupport.getLastCreated('wiz2')!['tnm'], 'T2');
    });

    test('empty strings are valid', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: '', kn: '', vn: '', totalDrop: 0, totalPickup: 0);
      final m = AdminCreateTaskSupport.getLastCreated('wiz1')!;
      expect(m['tnm'], '');
      expect(m['totalDrop'], 0);
    });
  });

  // ── Draft reset on customer change (bug fix) ──────────────────────────
  group('draft reset on customer change', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
    });

    test('switch customer: clearDraft wipes items + vehicle, setCustomer sets new', () {
      // Setup: customer A with items and vehicle
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'Indomaret', al: 'Jl. Sudirman');
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'galon', itemName: 'Galon 19L', tx: 'deliver', pd: 5),
        DraftItem(ii: 'aqua', itemName: 'Aqua 600mL', tx: 'sale', ps: 10),
      ]);
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'B 1234 XY');

      // Simulate the fix: detect kl change -> clearDraft -> setCustomer
      final String priorKl =
          (AdminCreateTaskSupport.getCustomer('wiz1')?['kl'] ?? '')
              .toString()
              .trim();
      const String newKl = 'CUST-B';
      expect(priorKl, 'CUST-A');
      expect(priorKl != newKl, isTrue);

      // Clear stale draft
      AdminCreateTaskSupport.clearDraft('wiz1');
      // Set new customer
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-B', kn: 'Alfamart', al: 'Jl. Merdeka');

      // Verify: items wiped, vehicle wiped, customer is B
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kl'], 'CUST-B');
      expect(c['kn'], 'Alfamart');
      expect(c['al'], 'Jl. Merdeka');
    });

    test('same customer re-tap: no clearDraft, items preserved', () {
      // Setup: customer A with items
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'Indomaret', al: 'Jl. Sudirman');
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'galon', itemName: 'Galon 19L', tx: 'deliver', pd: 5),
      ]);
      AdminCreateTaskSupport.setVehicle('wiz1', vv: 'V1', vn: 'B 1234 XY');

      // Simulate: same kl -> no clear
      final String priorKl =
          (AdminCreateTaskSupport.getCustomer('wiz1')?['kl'] ?? '')
              .toString()
              .trim();
      const String newKl = 'CUST-A';
      expect(priorKl, 'CUST-A');
      expect(priorKl == newKl, isTrue);

      // No clearDraft call -- items preserved
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'Indomaret', al: 'Jl. Sudirman');

      // Verify: items and vehicle still present
      expect(AdminCreateTaskSupport.getDraft('wiz1').length, 1);
      expect(AdminCreateTaskSupport.getDraft('wiz1')[0].ii, 'galon');
      expect(AdminCreateTaskSupport.getVehicle('wiz1')!['vv'], 'V1');
    });

    test('first pick (no prior customer): clearDraft on empty draft is safe', () {
      // No prior customer set
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);

      // Simulate: priorKl is '' (null customer), newKl is non-empty
      final String priorKl =
          (AdminCreateTaskSupport.getCustomer('wiz1')?['kl'] ?? '')
              .toString()
              .trim();
      expect(priorKl, '');
      const String newKl = 'CUST-A';
      expect(priorKl != newKl, isTrue);

      // clearDraft on empty draft: no throw
      AdminCreateTaskSupport.clearDraft('wiz1');
      // setCustomer sets fresh
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'Indomaret', al: 'Jl. Sudirman');

      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kl'], 'CUST-A');
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
    });

    test('switch customer: lastCreated survives clearDraft', () {
      // lastCreated from a prior successful submit must survive the clear
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'TASK-OLD', kn: 'Old', vn: 'V', totalDrop: 1, totalPickup: 1);
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'Indomaret', al: 'Jl. Sudirman');
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'galon', itemName: 'Galon', tx: 'deliver', pd: 3),
      );

      // Switch customer
      AdminCreateTaskSupport.clearDraft('wiz1');
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-B', kn: 'Alfamart', al: 'Jl. Merdeka');

      // Items wiped, but lastCreated intact
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getLastCreated('wiz1'), isNotNull);
      expect(AdminCreateTaskSupport.getLastCreated('wiz1')!['tnm'], 'TASK-OLD');
    });

    test('switch customer: pic field carried on new customer', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'Old', al: 'Old Addr', pic: 'Old PIC');
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );

      AdminCreateTaskSupport.clearDraft('wiz1');
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-B', kn: 'New', al: 'New Addr', pic: 'New PIC');

      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kl'], 'CUST-B');
      expect(c['pic'], 'New PIC');
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
    });

    test('multiple wizard keys: switch on one does not affect the other', () {
      // wiz1: customer A with items
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-A', kn: 'A', al: 'Addr A');
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'g', itemName: 'G', tx: 'deliver', pd: 2),
      );
      // wiz2: customer X with items
      AdminCreateTaskSupport.setCustomer('wiz2',
          kl: 'CUST-X', kn: 'X', al: 'Addr X');
      AdminCreateTaskSupport.getDraft('wiz2').add(
        DraftItem(ii: 'h', itemName: 'H', tx: 'sale', ps: 3),
      );

      // Switch wiz1 to customer B
      AdminCreateTaskSupport.clearDraft('wiz1');
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'CUST-B', kn: 'B', al: 'Addr B');

      // wiz1: items wiped, customer B
      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getCustomer('wiz1')!['kl'], 'CUST-B');

      // wiz2: UNTOUCHED
      expect(AdminCreateTaskSupport.getDraft('wiz2').length, 1);
      expect(AdminCreateTaskSupport.getDraft('wiz2')[0].ii, 'h');
      expect(AdminCreateTaskSupport.getCustomer('wiz2')!['kl'], 'CUST-X');
    });
  });

  // ── isSavesendMode ──────────────────────────────────────────────────
  group('isSavesendMode', () {
    test('returns true for "savesend"', () {
      expect(AdminCreateTaskSupport.isSavesendMode('savesend'), true);
    });

    test('returns true case-insensitive', () {
      expect(AdminCreateTaskSupport.isSavesendMode('SaveSend'), true);
      expect(AdminCreateTaskSupport.isSavesendMode('SAVESEND'), true);
    });

    test('returns true with whitespace', () {
      expect(AdminCreateTaskSupport.isSavesendMode('  savesend  '), true);
    });

    test('returns false for null', () {
      expect(AdminCreateTaskSupport.isSavesendMode(null), false);
    });

    test('returns false for empty string', () {
      expect(AdminCreateTaskSupport.isSavesendMode(''), false);
    });

    test('returns false for other action values', () {
      expect(AdminCreateTaskSupport.isSavesendMode('submit'), false);
      expect(AdminCreateTaskSupport.isSavesendMode('save'), false);
      expect(AdminCreateTaskSupport.isSavesendMode('send'), false);
    });

    test('returns false for numeric input', () {
      expect(AdminCreateTaskSupport.isSavesendMode(42), false);
    });
  });

  // ── parseNumberPos ─────────────────────────────────────────────────
  group('parseNumberPos', () {
    test('parses valid integer string', () {
      expect(AdminCreateTaskSupport.parseNumberPos('17'), 17);
    });

    test('parses integer value', () {
      expect(AdminCreateTaskSupport.parseNumberPos(17), 17);
    });

    test('returns 0 for null', () {
      expect(AdminCreateTaskSupport.parseNumberPos(null), 0);
    });

    test('returns 0 for empty string', () {
      expect(AdminCreateTaskSupport.parseNumberPos(''), 0);
    });

    test('returns 0 for non-numeric string', () {
      expect(AdminCreateTaskSupport.parseNumberPos('abc'), 0);
    });

    test('trims whitespace before parsing', () {
      expect(AdminCreateTaskSupport.parseNumberPos('  17  '), 17);
    });

    test('returns 0 for zero string', () {
      expect(AdminCreateTaskSupport.parseNumberPos('0'), 0);
    });
  });

  // ── isGeneratedTnmValid ────────────────────────────────────────────
  group('isGeneratedTnmValid', () {
    test('returns true for well-formed tnm', () {
      expect(
          AdminCreateTaskSupport.isGeneratedTnmValid('TASK-2026-000123'), true);
    });

    test('returns true for any non-empty non-sentinel string', () {
      expect(AdminCreateTaskSupport.isGeneratedTnmValid('TASK-2026-1'), true);
      expect(AdminCreateTaskSupport.isGeneratedTnmValid('ABC'), true);
    });

    test('returns false for empty string', () {
      expect(AdminCreateTaskSupport.isGeneratedTnmValid(''), false);
    });

    test('returns false for the app empty-marker "--"', () {
      // A freshly-created / unpopulated txfController slot seeds finalData
      // with emptyString ('--'), NOT '' -- so a read from the wrong or
      // undeployed numberPos returns '--'. Must be rejected (spec section 7).
      expect(AdminCreateTaskSupport.isGeneratedTnmValid('--'), false);
    });

    test('returns false for the string "null"', () {
      expect(AdminCreateTaskSupport.isGeneratedTnmValid('null'), false);
    });

    test('returns false when contains COUNTER_ERR', () {
      expect(
          AdminCreateTaskSupport.isGeneratedTnmValid('TASK-COUNTER_ERR'),
          false);
      expect(AdminCreateTaskSupport.isGeneratedTnmValid('COUNTER_ERR'), false);
    });

    test('returns false when contains POS_ERR', () {
      expect(
          AdminCreateTaskSupport.isGeneratedTnmValid('TASK-POS_ERR-2026'),
          false);
    });

    test('returns false when contains POS_NODATA', () {
      expect(
          AdminCreateTaskSupport.isGeneratedTnmValid('TASK-POS_NODATA'),
          false);
    });

    test('returns false when contains unresolved template token', () {
      expect(
          AdminCreateTaskSupport.isGeneratedTnmValid('TASK-{{YYYY}}-000001'),
          false);
      expect(
          AdminCreateTaskSupport.isGeneratedTnmValid('{{COUNTER(vtl,6)}}'),
          false);
    });

    test('returns true when string contains "ERR" but not a sentinel', () {
      // "ERR" alone is not a sentinel -- only the full sentinel substrings
      expect(AdminCreateTaskSupport.isGeneratedTnmValid('TASK-ERR-2026'), true);
    });
  });

  // ── DraftItem.toItMap ad/ap presence ──────────────────────────────
  test('toItMap always includes ad+ap present with null value (all tx types)', () {
    for (final tx in ['deliver', 'sale', 'purchase', 'refill']) {
      final item = DraftItem(ii: 'galon', itemName: 'Galon 19L', tx: tx);
      final m = item.toItMap();
      expect(m.containsKey('ad'), isTrue, reason: 'ad must be present for $tx');
      expect(m.containsKey('ap'), isTrue, reason: 'ap must be present for $tx');
      expect(m['ad'], isNull, reason: 'ad must be null for $tx');
      expect(m['ap'], isNull, reason: 'ap must be null for $tx');
    }
  });
}
