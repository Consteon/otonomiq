import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';

void main() {
  // ── P1: subtotal calculation ──────────────────────────────────────────

  group('walkin subtotal calculation', () {
    test('subtotal = qty * price', () {
      final item = DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 3, hg: 15000);
      // sub is computed inline in renderer as ps * hg
      expect(item.ps * item.hg, 45000);
    });

    test('subtotal zero when price zero', () {
      final item = DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 2, hg: 0);
      expect(item.ps * item.hg, 0);
    });

    test('subtotal zero when qty zero', () {
      final item = DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 0, hg: 15000);
      expect(item.ps * item.hg, 0);
    });
  });

  // ── P2: TOTAL sum ─────────────────────────────────────────────────────

  group('walkin TOTAL sum via computeTotals', () {
    test('sum of multiple sale lines', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 3, hg: 15000),
        DraftItem(ii: 'b', itemName: 'LPG', tx: 'sale', ps: 1, hg: 30000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      // 3*15000 + 1*30000 = 45000 + 30000 = 75000
      expect(t.totalSalePrice, 75000);
    });

    test('single line total', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 5, hg: 20000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 100000);
    });

    test('empty draft -> zero total', () {
      final t = AdminCreateTaskSupport.computeTotals([]);
      expect(t.totalSalePrice, 0);
    });

    test('line with hg=0 contributes zero', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'Galon', tx: 'sale', ps: 3, hg: 0),
        DraftItem(ii: 'b', itemName: 'LPG', tx: 'sale', ps: 2, hg: 10000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 20000);
    });
  });

  // ── P2: li[] assembly + Number canon ──────────────────────────────────

  group('walkin li[] assembly (toLiMap + draftToLiArray)', () {
    test('toLiMap produces correct shape with all fields present', () {
      final item = DraftItem(ii: 'ABC', itemName: 'Galon 19L', tx: 'sale', ps: 3, hg: 15000);
      final m = item.toLiMap();
      expect(m['ii'], 'ABC');
      expect(m['in'], 'Galon 19L');
      expect(m['qt'], 3);
      expect(m['hg'], 15000);
      expect(m['sub'], 45000);
      // All fields present
      expect(m.containsKey('ii'), true);
      expect(m.containsKey('in'), true);
      expect(m.containsKey('qt'), true);
      expect(m.containsKey('hg'), true);
      expect(m.containsKey('sub'), true);
    });

    test('toLiMap Number canon: qt, hg, sub are int', () {
      final item = DraftItem(ii: 'a', itemName: 'X', tx: 'sale', ps: 2, hg: 5000);
      final m = item.toLiMap();
      expect(m['qt'], isA<int>());
      expect(m['hg'], isA<int>());
      expect(m['sub'], isA<int>());
    });

    test('toLiMap String canon: ii and in are String', () {
      final item = DraftItem(ii: 'a', itemName: 'X', tx: 'sale', ps: 1, hg: 1000);
      final m = item.toLiMap();
      expect(m['ii'], isA<String>());
      expect(m['in'], isA<String>());
    });

    test('toLiMap with hg=0 produces sub=0', () {
      final item = DraftItem(ii: 'a', itemName: 'X', tx: 'sale', ps: 5, hg: 0);
      final m = item.toLiMap();
      expect(m['hg'], 0);
      expect(m['sub'], 0);
    });

    test('draftToLiArray converts multiple items', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 1, hg: 1000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 2000),
      ];
      final arr = AdminCreateTaskSupport.draftToLiArray(items);
      expect(arr.length, 2);
      expect(arr[0]['ii'], 'a');
      expect(arr[0]['sub'], 1000);
      expect(arr[1]['ii'], 'b');
      expect(arr[1]['sub'], 4000);
    });

    test('draftToLiArray empty list returns empty', () {
      final arr = AdminCreateTaskSupport.draftToLiArray([]);
      expect(arr, isEmpty);
    });
  });

  // ── P2: assembleNotaDoc ───────────────────────────────────────────────

  group('walkin assembleNotaDoc', () {
    test('produces correct shape with all fields', () {
      final liArray = [
        {'ii': 'a', 'in': 'Galon', 'qt': 3, 'hg': 15000, 'sub': 45000},
      ];
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'NOTA-2026-000001',
        src: 'walkin',
        by: 'John',
        bym: 'tunai',
        gl: 'F621558e33b612',
        tot: 45000,
        liArray: liArray,
        cv: 'VID123',
        cn: 'Admin Name',
        t: 1720000000000,
        ts: '2026-07-08 14:30',
        tableVid: '20342033315492',
      );
      expect(doc['nno'], 'NOTA-2026-000001');
      expect(doc['src'], 'walkin');
      expect(doc['ref'], '');
      expect(doc['kl'], '');
      expect(doc['by'], 'John');
      expect(doc['bym'], 'tunai');
      expect(doc['st'], 'LUNAS');
      expect(doc['gl'], 'F621558e33b612');
      expect(doc['tot'], 45000);
      expect(doc['li'], liArray);
      expect(doc['cv'], 'VID123');
      expect(doc['cn'], 'Admin Name');
      expect(doc['t'], 1720000000000);
      expect(doc['ts'], '2026-07-08 14:30');
      expect(doc['tablevid'], '20342033315492');
      expect(doc['search'], 'nno\u{2605}NOTA-2026-000001');
    });

    test('Number canon: tot and t are int', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'N1',
        src: 'walkin',
        by: '',
        bym: 'tunai',
        gl: 'G1',
        tot: 99000,
        liArray: [],
        cv: 'V1',
        cn: 'C1',
        t: 1720000000000,
        ts: '2026-07-08 14:30',
        tableVid: 'TV1',
      );
      expect(doc['tot'], isA<int>());
      expect(doc['t'], isA<int>());
    });

    test('String canon: nno, src, by, bym, st, gl, ts, search are String', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'N1',
        src: 'walkin',
        by: 'X',
        bym: 'transfer',
        gl: 'G1',
        tot: 0,
        liArray: [],
        cv: 'V1',
        cn: 'C1',
        t: 0,
        ts: '2026-01-01 00:00',
        tableVid: 'TV1',
      );
      expect(doc['nno'], isA<String>());
      expect(doc['src'], isA<String>());
      expect(doc['by'], isA<String>());
      expect(doc['bym'], isA<String>());
      expect(doc['st'], isA<String>());
      expect(doc['gl'], isA<String>());
      expect(doc['ts'], isA<String>());
      expect(doc['search'], isA<String>());
    });

    test('st is always LUNAS (uppercase)', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'N1', src: 'w', by: '', bym: 'tunai', gl: 'G',
        tot: 0, liArray: [], cv: '', cn: '', t: 0, ts: '', tableVid: '',
      );
      expect(doc['st'], 'LUNAS');
    });

    test('search uses star separator U+2605', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'NOTA-2026-000007', src: 'w', by: '', bym: 'tunai', gl: 'G',
        tot: 0, liArray: [], cv: '', cn: '', t: 0, ts: '', tableVid: '',
      );
      expect(doc['search'], contains('\u{2605}'));
      expect(doc['search'], 'nno\u{2605}NOTA-2026-000007');
    });
  });

  // ── P2: bym mapping ───────────────────────────────────────────────────

  group('walkin bym mapping', () {
    // These test the mapping logic that lives in nota_create_submit.dart
    // _onSubmit. We test the pure mapping here directly.
    String mapBym(String raw) {
      final String clean = (raw == '--' || raw == 'null') ? '' : raw.trim();
      if (clean == 'Tunai' || clean == 'tunai') return 'tunai';
      if (clean == 'Transfer' || clean == 'transfer') return 'transfer';
      return clean.toLowerCase();
    }

    test('Tunai -> tunai', () {
      expect(mapBym('Tunai'), 'tunai');
    });

    test('Transfer -> transfer', () {
      expect(mapBym('Transfer'), 'transfer');
    });

    test('already lowercase tunai -> tunai', () {
      expect(mapBym('tunai'), 'tunai');
    });

    test('already lowercase transfer -> transfer', () {
      expect(mapBym('transfer'), 'transfer');
    });

    test('unknown method lowercased', () {
      expect(mapBym('QRIS'), 'qris');
    });

    test('emptyString marker (--) -> empty', () {
      expect(mapBym('--'), '');
    });

    test('null string -> empty', () {
      expect(mapBym('null'), '');
    });

    test('empty -> empty', () {
      expect(mapBym(''), '');
    });
  });

  // ── P2: empty buyer fallback ──────────────────────────────────────────

  group('walkin empty buyer fallback', () {
    test('empty buyer produces by=""', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'N1', src: 'walkin', by: '', bym: 'tunai', gl: 'G1',
        tot: 10000, liArray: [{'ii': 'a', 'in': 'X', 'qt': 1, 'hg': 10000, 'sub': 10000}],
        cv: 'V', cn: 'C', t: 1720000000000, ts: '2026-07-08 14:30', tableVid: 'TV',
      );
      expect(doc['by'], '');
    });

    test('non-empty buyer preserved', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'N1', src: 'walkin', by: 'Budi', bym: 'tunai', gl: 'G1',
        tot: 10000, liArray: [{'ii': 'a', 'in': 'X', 'qt': 1, 'hg': 10000, 'sub': 10000}],
        cv: 'V', cn: 'C', t: 1720000000000, ts: '2026-07-08 14:30', tableVid: 'TV',
      );
      expect(doc['by'], 'Budi');
    });
  });

  // ── P2: formatWibTimestamp ─────────────────────────────────────────────

  group('formatWibTimestamp', () {
    test('formats epoch-ms to yyyy-MM-dd HH:mm WIB', () {
      // 2026-07-08 14:30 WIB = 2026-07-08 07:30 UTC
      final int epochMs = DateTime.utc(2026, 7, 8, 7, 30).millisecondsSinceEpoch;
      final String ts = AdminCreateTaskSupport.formatWibTimestamp(epochMs);
      expect(ts, '2026-07-08 14:30');
    });

    test('midnight WIB', () {
      // 2026-01-01 00:00 WIB = 2025-12-31 17:00 UTC
      final int epochMs = DateTime.utc(2025, 12, 31, 17, 0).millisecondsSinceEpoch;
      final String ts = AdminCreateTaskSupport.formatWibTimestamp(epochMs);
      expect(ts, '2026-01-01 00:00');
    });

    test('pads single-digit month and day', () {
      // 2026-03-05 09:05 WIB = 2026-03-05 02:05 UTC
      final int epochMs = DateTime.utc(2026, 3, 5, 2, 5).millisecondsSinceEpoch;
      final String ts = AdminCreateTaskSupport.formatWibTimestamp(epochMs);
      expect(ts, '2026-03-05 09:05');
    });
  });

  // ── FIX-2: price guard (no zero-priced line may be committed) ──────────

  group('walkin price guard (spec section 1)', () {
    // Mirror of _NotaCreateSubmitState._allLinesPriced: submit is blocked
    // when ANY sale line has hg <= 0.
    bool allLinesPriced(List<DraftItem> draft) =>
        draft.every((item) => item.hg > 0);

    test('all lines priced -> allowed', () {
      final draft = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 1, hg: 1000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 2000),
      ];
      expect(allLinesPriced(draft), true);
    });

    test('one zero-priced line -> blocked', () {
      final draft = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 1, hg: 1000),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 2, hg: 0),
      ];
      expect(allLinesPriced(draft), false);
    });

    test('all zero-priced -> blocked', () {
      final draft = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'sale', ps: 1, hg: 0),
      ];
      expect(allLinesPriced(draft), false);
    });

    test('empty draft vacuously priced (empty-items gate handles it)', () {
      expect(allLinesPriced([]), true);
    });
  });

  // ── P3: PRN keyed doc-scalar resolver ─────────────────────────────────

  group('PRN keyed doc-scalar resolver (_interpolate path traversal)', () {
    // These tests verify that TemplatePrinter._interpolate resolves
    // {{field}} from a Map context. Since _interpolate is private, we test
    // the LOGIC pattern: Map path-traversal with dot/bracket access.

    String resolve(String key, Map<String, dynamic> ctx) {
      var parts = key.split(RegExp(r'[.\[\]]+'))..removeWhere((p) => p.isEmpty);
      dynamic currentValue = ctx;
      for (final part in parts) {
        if (currentValue == null) break;
        if (currentValue is Map) {
          currentValue = currentValue[part];
        } else {
          currentValue = null;
          break;
        }
      }
      return currentValue?.toString() ?? '';
    }

    test('scalar fields resolve from flat map', () {
      final Map<String, dynamic> context = {
        'nno': 'NOTA-2026-000001',
        'by': 'John',
        'tot': 45000,
        'st': 'LUNAS',
        'ts': '2026-07-08 14:30',
        'bym': 'tunai',
      };
      expect(resolve('nno', context), 'NOTA-2026-000001');
      expect(resolve('by', context), 'John');
      expect(resolve('tot', context), '45000');
      expect(resolve('st', context), 'LUNAS');
      expect(resolve('bym', context), 'tunai');
    });

    test('array item fields resolve via item.field', () {
      final Map<String, dynamic> itemContext = {
        'item': {'ii': 'ABC', 'in': 'Galon 19L', 'qt': 3, 'hg': 15000, 'sub': 45000},
      };
      expect(resolve('item.in', itemContext), 'Galon 19L');
      expect(resolve('item.qt', itemContext), '3');
      expect(resolve('item.hg', itemContext), '15000');
      expect(resolve('item.sub', itemContext), '45000');
    });

    test('missing field resolves to empty string', () {
      final Map<String, dynamic> context = {'nno': 'N1'};
      expect(resolve('nonexistent', context), '');
    });
  });

  // ── FIX-3: default pipe (white-label empty-value fallback) ────────────

  group('template default pipe (FIX-3)', () {
    // Mirror of the _interpolate formatter branch:
    //   {{field|default:SomeText}} -> SomeText only when value is empty.
    String applyDefault(String value, String formatter) {
      final m = RegExp(r'^default:(.*)$').firstMatch(formatter);
      if (m != null) {
        return value.isEmpty ? m.group(1)! : value;
      }
      return value;
    }

    test('fires on empty value', () {
      expect(applyDefault('', 'default:Umum'), 'Umum');
    });

    test('inert on non-empty value', () {
      expect(applyDefault('Budi', 'default:Umum'), 'Budi');
    });

    test('fallback text may contain spaces', () {
      expect(applyDefault('', 'default:Pelanggan Umum'), 'Pelanggan Umum');
    });

    test('non-default formatter is not treated as default', () {
      expect(applyDefault('', 'idr'), '');
    });
  });

  // ── P3: PRN LOOP Map-tolerance ────────────────────────────────────────

  group('PRN LOOP Map-tolerance', () {
    test('Map items pass through unchanged (keyed variant)', () {
      final List<dynamic> source = [
        {'ii': 'a', 'in': 'Galon', 'qt': 3, 'hg': 15000, 'sub': 45000},
        {'ii': 'b', 'in': 'LPG', 'qt': 1, 'hg': 30000, 'sub': 30000},
      ];

      // Mirror of the fixed loop coercion logic
      final List<dynamic> coerced = source.map((row) {
        if (row is Map) return row;
        return (row as List).map((cell) => cell.toString()).toList();
      }).toList();

      expect(coerced.length, 2);
      expect(coerced[0], isA<Map>());
      expect((coerced[0] as Map)['in'], 'Galon');
      expect((coerced[0] as Map)['qt'], 3);
    });

    test('List items coerced to List<String> (positional variant, no regression)', () {
      final List<dynamic> source = [
        ['DO-001', 'Customer A', '10', '5'],
        ['DO-002', 'Customer B', '8', '3'],
      ];

      final List<dynamic> coerced = source.map((row) {
        if (row is Map) return row;
        return (row as List).map((cell) => cell.toString()).toList();
      }).toList();

      expect(coerced.length, 2);
      expect(coerced[0], isA<List>());
      expect((coerced[0] as List)[0], 'DO-001');
      expect((coerced[0] as List)[1], 'Customer A');
    });

    test('mixed source (should not happen but handled)', () {
      final List<dynamic> source = [
        {'ii': 'a', 'in': 'Galon'},
        ['DO-001', 'Customer A'],
      ];

      final List<dynamic> coerced = source.map((row) {
        if (row is Map) return row;
        return (row as List).map((cell) => cell.toString()).toList();
      }).toList();

      expect(coerced[0], isA<Map>());
      expect(coerced[1], isA<List>());
    });

    test('empty source -> empty result', () {
      final List<dynamic> source = [];
      final List<dynamic> coerced = source.map((row) {
        if (row is Map) return row;
        return (row as List).map((cell) => cell.toString()).toList();
      }).toList();
      expect(coerced, isEmpty);
    });
  });

  // ── P3: PRN positional variant non-regression ─────────────────────────

  group('PRN positional variant non-regression', () {
    test('positional table access pattern still works', () {
      final Map<String, dynamic> context = {
        'master1_do': [
          ['DO-001', 'Customer A', '10', '5', '2026-07-01'],
          ['DO-002', 'Customer B', '8', '3', '2026-07-02'],
        ],
      };

      // {{master1_do[1][3]}} -> row 1 (0-indexed: 0), col 3 -> '5'
      final table = context['master1_do'] as List;
      final int rowIndex = 1 - 1; // 1-based -> 0-based
      final int colIndex = 3;
      expect(table[rowIndex][colIndex], '5');

      // {{master1_do[2][0]}} -> row 2 (idx 1), col 0 -> 'DO-002'
      expect(table[2 - 1][0], 'DO-002');
    });

    test('positional List<List<String>> coercion untouched', () {
      final dynamic rawSourceData = [
        ['DO-001', 'A', '10', '5'],
        ['DO-002', 'B', '8', '3'],
      ];

      final List<List<String>> groupByData = (rawSourceData as List)
          .map((row) => (row as List).map((cell) => cell.toString()).toList())
          .toList();
      expect(groupByData.length, 2);
      expect(groupByData[0][0], 'DO-001');
    });
  });

  // ── P2: sparse/edge cases ─────────────────────────────────────────────

  group('walkin edge cases', () {
    test('hrg empty/0 -> hg=0, sub=0, user must override manually', () {
      final item = DraftItem(ii: 'a', itemName: 'X', tx: 'sale', ps: 1, hg: 0);
      expect(item.hg, 0);
      expect(item.ps * item.hg, 0);
    });

    test('single item with qty=1 (minimum)', () {
      final items = [
        DraftItem(ii: 'a', itemName: 'X', tx: 'sale', ps: 1, hg: 25000),
      ];
      final t = AdminCreateTaskSupport.computeTotals(items);
      expect(t.totalSalePrice, 25000);

      final li = AdminCreateTaskSupport.draftToLiArray(items);
      expect(li[0]['qt'], 1);
      expect(li[0]['sub'], 25000);
    });

    test('large qty and price', () {
      final item = DraftItem(ii: 'a', itemName: 'X', tx: 'sale', ps: 100, hg: 999999);
      final m = item.toLiMap();
      expect(m['sub'], 99999900);
    });
  });
}
