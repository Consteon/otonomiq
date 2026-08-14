// test/custody_confirmed_list_test.dart
//
// SCOPE -- read this before trusting a green run.
//
// COVERED (real production code, lib/widget/driver_home_support.dart):
//   * buildConfirmedRows -- ip[] -> display rows, the item-JOIN fallbacks, and
//     D1's first-row-only badge attachment. Reverting that function turns this
//     file red (plan Task 2, probe A).
//   * aggregateItemCirculation + excludeByStatus, composed below in
//     flowMapFrom() -- the sums themselves, the actual-only semantics, and the
//     load_rejected exclusion (probe B).
//
// NOT COVERED -- and not honestly coverable here:
//   * CustodyConfirmedList._buildFlowMap()'s ARGUMENT WIRING. flowMapFrom()
//     below is a local re-implementation of that wiring. It composes the real
//     helpers, which is the right pattern, but it is NOT the widget's call
//     site: if the widget passed actualDropField: 'pd' (breaking D2) or
//     dropped the excludeByStatus call (breaking D3), every test in this file
//     would still pass. Probe C in the plan demonstrates exactly that.
//   * D4's fail-closed guards (_flowCode.isEmpty / flowSearch.isEmpty). They
//     live in the widget, and the repo's SDUI pump harness must OMIT the
//     component's `table` key to avoid Firebase init -- so a pump test cannot
//     reach the subscribe path either.
//
// Both gaps are verified ONLY by the manual device flow: plan section 6.4,
// steps 3, 4 and 9. Do not "fix" them with a pump test.
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

/// Build the flowMap exactly as the widget does: filter out load_rejected,
/// aggregate actual-only (same field name as both plan and actual), fold to a
/// map keyed by the aggregated label.
Map<String, ItemCirculation> flowMapFrom(
  List<Map<String, dynamic>> taskDocs, {
  String itemsField = 'it',
  String labelField = 'ii',
  String dropField = 'ad',
  String pickupField = 'ap',
}) {
  final List<Map<String, dynamic>> live =
      excludeByStatus(taskDocs, kDefaultExcludeStatus, statusField: 'tst');
  final CirculationResult r = aggregateItemCirculation(
    live,
    itemsField: itemsField,
    labelField: labelField,
    dropField: dropField,
    actualDropField: dropField,
    pickupField: pickupField,
    actualPickupField: pickupField,
  );
  final Map<String, ItemCirculation> map = <String, ItemCirculation>{};
  for (final ItemCirculation ic in r.items) {
    map[ic.itemName] = ic;
  }
  return map;
}

void main() {
  // ── ip[] -> display rows (acceptance §1: unchanged behaviour) ───────────

  group('buildConfirmedRows -- recount rows (flow absent)', () {
    test('joins item names from detail map', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'returnable', 'qt': 25},
        {'ii': 'lpg12', 'cd': 'returnable', 'qt': 17},
      ];
      final details = {
        'galon': const ItemDetail(name: 'Galon 19L', category: 'returnable'),
        'lpg12': const ItemDetail(name: 'LPG 12kg', category: 'returnable'),
      };
      final rows = buildConfirmedRows(ip, details);
      expect(rows.length, 2);
      expect(rows[0].name, 'Galon 19L');
      expect(rows[0].qty, 25);
      expect(rows[1].name, 'LPG 12kg');
      expect(rows[1].qty, 17);
    });

    test('falls back to ii/cd when detail map has no entry', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'unknown', 'cd': 'misc', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows[0].name, 'unknown');
      expect(rows[0].category, 'misc');
      expect(rows[0].itemId, 'unknown');
    });

    test('skips entries with empty ii', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '', 'cd': 'returnable', 'qt': 10},
        {'ii': 'galon', 'cd': 'returnable', 'qt': 25},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows.length, 1);
      expect(rows[0].itemId, 'galon');
    });

    test('empty ip[] -> empty rows', () {
      expect(buildConfirmedRows([], {}), isEmpty);
    });

    test('qt parses from string', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'r', 'qt': '25'},
      ];
      expect(buildConfirmedRows(ip, {})[0].qty, 25);
    });

    test('non-numeric qt defaults to 0', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'r', 'qt': 'abc'},
      ];
      expect(buildConfirmedRows(ip, {})[0].qty, 0);
    });

    test('acceptance §1: omitted flowMap leaves every badge at zero', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
        {'ii': 'galon', 'cd': 'kosong', 'qt': 5},
        {'ii': 'lpg12', 'cd': 'isi', 'qt': 3},
      ];
      final rows = buildConfirmedRows(ip, {});
      expect(rows.length, 3);
      for (final r in rows) {
        expect(r.drop, 0, reason: 'flow absent must not produce a drop badge');
        expect(r.pickup, 0,
            reason: 'flow absent must not produce a pickup badge');
      }
    });

    test('acceptance §1: an EMPTY flowMap is identical to an omitted one', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
      ];
      final a = buildConfirmedRows(ip, {});
      final b = buildConfirmedRows(ip, {},
          flowMap: const <String, ItemCirculation>{});
      expect(b.length, a.length);
      expect(b[0].name, a[0].name);
      expect(b[0].category, a[0].category);
      expect(b[0].qty, a[0].qty);
      expect(b[0].drop, a[0].drop);
      expect(b[0].pickup, a[0].pickup);
    });
  });

  // ── badge attachment (spec §7.2 / §7.3, decision D1) ───────────────────

  group('buildConfirmedRows -- badge attachment', () {
    final flow = <String, ItemCirculation>{
      'galon': const ItemCirculation(
          itemName: 'galon', totalDrop: 12, totalPickup: 7),
      'dropOnly': const ItemCirculation(
          itemName: 'dropOnly', totalDrop: 4, totalPickup: 0),
      'pickOnly': const ItemCirculation(
          itemName: 'pickOnly', totalDrop: 0, totalPickup: 9),
      'idle': const ItemCirculation(
          itemName: 'idle', totalDrop: 0, totalPickup: 0),
    };

    test('attaches drop + pickup for a matching item id', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows[0].drop, 12);
      expect(rows[0].pickup, 7);
    });

    test('drop-only item leaves pickup at 0 (badge suppressed)', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'dropOnly', 'cd': 'isi', 'qt': 1},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows[0].drop, 4);
      expect(rows[0].pickup, 0);
    });

    test('pickup-only item leaves drop at 0 (badge suppressed)', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'pickOnly', 'cd': 'kosong', 'qt': 1},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows[0].drop, 0);
      expect(rows[0].pickup, 9);
    });

    test('both zero -> no badges', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'idle', 'cd': 'isi', 'qt': 6},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows[0].drop, 0);
      expect(rows[0].pickup, 0);
    });

    test('item absent from flowMap -> no badges', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'ghost', 'cd': 'isi', 'qt': 2},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows[0].drop, 0);
      expect(rows[0].pickup, 0);
    });

    test('D1: duplicate ii (isi + kosong) badges the FIRST row only', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
        {'ii': 'galon', 'cd': 'kosong', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows.length, 2);
      expect(rows[0].drop, 12);
      expect(rows[0].pickup, 7);
      expect(rows[1].drop, 0,
          reason: 'second row of the same ii must not repeat the sum');
      expect(rows[1].pickup, 0,
          reason: 'second row of the same ii must not repeat the sum');
    });

    test('D1: first-seen order wins even when kosong comes first', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'kosong', 'qt': 5},
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
      ];
      final rows = buildConfirmedRows(ip, {}, flowMap: flow);
      expect(rows[0].category, 'kosong');
      expect(rows[0].drop, 12);
      expect(rows[1].drop, 0);
    });

    test('flowKeyField = in: falls back to the JOIN-resolved name', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'g19', 'cd': 'isi', 'qt': 25},
      ];
      final details = {
        'g19': const ItemDetail(name: 'Galon 19L', category: 'returnable'),
      };
      final byName = <String, ItemCirculation>{
        'Galon 19L': const ItemCirculation(
            itemName: 'Galon 19L', totalDrop: 3, totalPickup: 2),
      };
      final rows = buildConfirmedRows(ip, details, flowMap: byName);
      expect(rows[0].name, 'Galon 19L');
      expect(rows[0].drop, 3);
      expect(rows[0].pickup, 2);
    });
  });

  // ── the aggregate that feeds flowMap (spec §7.4) ────────────────────────
  //
  // HONESTY NOTE: this group certifies the aggregation HELPERS
  // (aggregateItemCirculation + excludeByStatus) as composed by flowMapFrom()
  // above. It does NOT certify the widget's _buildFlowMap() call site -- the
  // widget could wire these same helpers wrongly and every test below would
  // stay green. That call site is verified only by the manual flow in plan
  // section 6.4 (steps 3, 4, 9), and probe C proves the blind spot on purpose.

  group('flowMap aggregate -- actual-only + load_rejected exclusion', () {
    test('sums ad/ap across multiple task docs for one item key', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'in': 'Galon 19L', 'pd': 99, 'pp': 99,
             'ad': 5, 'ap': 2},
          ],
        },
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'in': 'Galon 19L', 'pd': 99, 'pp': 99,
             'ad': 7, 'ap': 3},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 12);
      expect(map['galon']!.totalPickup, 5);
    });

    test('D2: pd/pp are NEVER a fallback -- actual-only', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'pd': 40, 'pp': 30, 'ad': 6, 'ap': 1},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 6, reason: 'must not read pd=40');
      expect(map['galon']!.totalPickup, 1, reason: 'must not read pp=30');
    });

    test('landmine: PRESENT-BUT-NULL ad/ap (toItMap shape) yields 0', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'unassigned',
          'it': [
            // Exactly what admin_create_task_support.toItMap() writes at
            // task creation: the keys exist, the values are literal null.
            {'ii': 'galon', 'in': 'Galon 19L', 'pd': 20, 'pp': 10,
             'ad': null, 'ap': null},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 0);
      expect(map['galon']!.totalPickup, 0);
    });

    test('legacy shape: ad/ap keys absent entirely yields 0', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'pd': 20, 'pp': 10},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 0);
      expect(map['galon']!.totalPickup, 0);
    });

    test('blank-string ad/ap yields 0', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'pd': 20, 'pp': 10, 'ad': '', 'ap': ''},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 0);
      expect(map['galon']!.totalPickup, 0);
    });

    test('string ad/ap parse (sheet flips 5 and "5")', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'ad': '5', 'ap': '2'},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 5);
      expect(map['galon']!.totalPickup, 2);
    });

    test('D3: load_rejected task is excluded from the sum', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'ad': 5, 'ap': 2},
          ],
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'ii': 'galon', 'ad': 100, 'ap': 100},
          ],
        },
      ];
      final map = flowMapFrom(tasks);
      expect(map['galon']!.totalDrop, 5);
      expect(map['galon']!.totalPickup, 2);
    });

    test('an item only present on a load_rejected task disappears entirely',
        () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'load_rejected',
          'it': [
            {'ii': 'ghost', 'ad': 9, 'ap': 9},
          ],
        },
      ];
      expect(flowMapFrom(tasks).containsKey('ghost'), isFalse);
    });

    test('end-to-end: aggregate feeds rows, null actuals render no badge', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'unassigned',
          'it': [
            {'ii': 'galon', 'pd': 20, 'pp': 10, 'ad': null, 'ap': null},
          ],
        },
      ];
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
      ];
      final rows =
          buildConfirmedRows(ip, {}, flowMap: flowMapFrom(tasks));
      expect(rows[0].qty, 25);
      expect(rows[0].drop, 0);
      expect(rows[0].pickup, 0);
    });

    test('end-to-end: executed task renders both badge numbers', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'pd': 20, 'pp': 10, 'ad': 18, 'ap': 11},
          ],
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'ii': 'galon', 'pd': 5, 'pp': 5, 'ad': 5, 'ap': 5},
          ],
        },
      ];
      final ip = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'isi', 'qt': 25},
        {'ii': 'galon', 'cd': 'kosong', 'qt': 4},
      ];
      final rows =
          buildConfirmedRows(ip, {}, flowMap: flowMapFrom(tasks));
      expect(rows[0].drop, 18);
      expect(rows[0].pickup, 11);
      expect(rows[1].drop, 0);
      expect(rows[1].pickup, 0);
    });

    test('custom flowItemsField / flowKeyField are honoured', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'items': [
            {'in': 'Galon 19L', 'ad': 4, 'ap': 1},
          ],
        },
      ];
      final map =
          flowMapFrom(tasks, itemsField: 'items', labelField: 'in');
      expect(map['Galon 19L']!.totalDrop, 4);
      expect(map['Galon 19L']!.totalPickup, 1);
    });

    test('custom dropField / pickupField are honoured', () {
      final tasks = <Map<String, dynamic>>[
        {
          'tst': 'done',
          'it': [
            {'ii': 'galon', 'ad': 99, 'ap': 99, 'as': 6, 'ab': 2},
          ],
        },
      ];
      final map =
          flowMapFrom(tasks, dropField: 'as', pickupField: 'ab');
      expect(map['galon']!.totalDrop, 6);
      expect(map['galon']!.totalPickup, 2);
    });

    test('non-list items field is skipped without throwing', () {
      final tasks = <Map<String, dynamic>>[
        {'tst': 'done', 'it': 'not-a-list'},
        {'tst': 'done'},
      ];
      expect(flowMapFrom(tasks), isEmpty);
    });
  });

  // ── sduiBool (D-D truthy whitelist) ───────────────────────────────────────
  //
  // These call the REAL public symbol from driver_home_support.dart.
  // The widget's call site is `sduiBool(_spec.str('groupByItem'))`, so the
  // test below verifies the whitelist directly -- not via a private copy.

  group('sduiBool -- D-D truthy whitelist', () {
    test('TRUE -> true', () => expect(sduiBool('TRUE'), isTrue));
    test('true -> true', () => expect(sduiBool('true'), isTrue));
    test('1 -> true', () => expect(sduiBool('1'), isTrue));
    test('yes -> true', () => expect(sduiBool('yes'), isTrue));
    test('ya -> true', () => expect(sduiBool('ya'), isTrue));
    test('FALSE -> false (the case D-D was written for)', () {
      expect(sduiBool('FALSE'), isFalse);
    });
    test('empty -> false', () => expect(sduiBool(''), isFalse));
    test('0 -> false', () => expect(sduiBool('0'), isFalse));
    test('nope -> false', () => expect(sduiBool('nope'), isFalse));
    test('whitespace-padded true -> true', () {
      expect(sduiBool('  TRUE  '), isTrue);
    });
  });

  // ── parseCondLabels ──────────────────────────────────────────────────────
  //
  // These call the REAL public symbol from driver_home_support.dart.
  // The test strings use literal ⭘ (U+2B58) and ◼ (U+25FC) characters,
  // bypassing autheniumDecode, because autheniumDecode is the caller's
  // responsibility (SduiSpec.str handles it before passing to parseCondLabels).

  group('parseCondLabels -- condition label map', () {
    test('parses full◼Penuh⭘empty◼Kosong', () {
      final map = parseCondLabels('full\u{25FC}Penuh\u{2B58}empty\u{25FC}Kosong');
      expect(map, {'full': 'Penuh', 'empty': 'Kosong'});
    });

    test('empty input -> empty map', () {
      expect(parseCondLabels(''), isEmpty);
    });

    test('malformed entry (no ◼) is skipped', () {
      // 'bad' has no ◼ separator -- parseBuckets skips it
      final map = parseCondLabels('bad\u{2B58}full\u{25FC}Penuh');
      expect(map, {'full': 'Penuh'});
      expect(map.containsKey('bad'), isFalse);
    });

    test('blank second segment is filtered (W2: ok substitution)', () {
      // 'full◼' has an empty label -> parseBuckets substitutes 'ok' ->
      // parseCondLabels filters it out -> condLabels[cd] ?? cd falls back
      // to the raw cd value, which is honest.
      final map = parseCondLabels('full\u{25FC}\u{2B58}empty\u{25FC}Kosong');
      expect(map.containsKey('full'), isFalse,
          reason: 'blank label should be filtered, not mapped to ok');
      expect(map['empty'], 'Kosong');
    });

    test('single entry parses', () {
      final map = parseCondLabels('full\u{25FC}Isi');
      expect(map, {'full': 'Isi'});
    });
  });

  // ── grouped mode (spec section 3b) ────────────────────────────────────────

  group('buildConfirmedRows -- groupByItem', () {
    final details = <String, ItemDetail>{
      '9990019000045': const ItemDetail(
          name: 'Amidis Galon 19 Liter', category: 'returnable'),
      '2000000006001': const ItemDetail(
          name: 'Aqua 1500ml', category: 'consumable'),
      '8800000001002': const ItemDetail(
          name: 'LPG 12kg', category: 'returnable'),
    };
    final condLabels = <String, String>{'full': 'Penuh', 'empty': 'Kosong'};

    test('live fixture: Amidis full+empty merges to 1 row, qty=sum', () {
      // Firestore doc ASvYe5lJw672K5ezigy5
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, condLabels: condLabels);
      expect(rows.length, 1, reason: 'two ip[] entries -> one grouped row');
      expect(rows[0].name, 'Amidis Galon 19 Liter');
      expect(rows[0].qty, 5, reason: 'D-B: qty = 0 + 5');
      expect(rows[0].category, 'returnable');
      expect(rows[0].conditions.length, 2);
      expect(rows[0].conditions[0].label, 'Penuh');
      expect(rows[0].conditions[0].qty, 0);
      expect(rows[0].conditions[1].label, 'Kosong');
      expect(rows[0].conditions[1].qty, 5);
    });

    test('live fixture: 4 ip rows (2 items x 2 conds) -> 2 grouped rows', () {
      // Firestore doc RjDi5jBXL8Sr0OYJSrFi
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
        {'ii': '8800000001002', 'cd': 'full', 'qt': 3},
        {'ii': '8800000001002', 'cd': 'empty', 'qt': 0},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, condLabels: condLabels);
      expect(rows.length, 2, reason: 'pill should say "2 item"');
      expect(rows[0].name, 'Amidis Galon 19 Liter');
      expect(rows[0].qty, 5);
      expect(rows[1].name, 'LPG 12kg');
      expect(rows[1].qty, 3);
    });

    test('D-A: consumable item suppresses condition breakdown', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '2000000006001', 'cd': 'full', 'qt': 1},
        {'ii': '2000000006001', 'cd': 'empty', 'qt': 0},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true,
          condLabels: condLabels,
          consumableCategory: 'consumable');
      expect(rows.length, 1);
      expect(rows[0].name, 'Aqua 1500ml');
      expect(rows[0].qty, 1, reason: 'D-B: qty = 1 + 0');
      expect(rows[0].conditions, isEmpty,
          reason: 'consumable: condition breakdown suppressed');
    });

    test('D-A: case-insensitive consumable match', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '2000000006001', 'cd': 'full', 'qt': 1},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, consumableCategory: 'CONSUMABLE');
      expect(rows[0].conditions, isEmpty);
    });

    test('D-A: empty consumableCategory never suppresses', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '2000000006001', 'cd': 'full', 'qt': 1},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, condLabels: condLabels);
      expect(rows[0].conditions.length, 1,
          reason: 'no consumableCategory -> conditions shown');
    });

    test('D-A: returnable is NOT suppressed', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true,
          condLabels: condLabels,
          consumableCategory: 'consumable');
      expect(rows[0].conditions.length, 2,
          reason: 'returnable: conditions shown');
    });

    test('condLabels absent -> raw cd values as labels', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, details, groupByItem: true);
      expect(rows[0].conditions[0].label, 'full');
      expect(rows[0].conditions[1].label, 'empty');
    });

    test('condLabels partial -> unmapped cd falls back to raw', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
      ];
      final partial = <String, String>{'full': 'Penuh'};
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, condLabels: partial);
      expect(rows[0].conditions[0].label, 'Penuh');
      expect(rows[0].conditions[1].label, 'empty',
          reason: 'unmapped cd value falls back to raw');
    });

    test('custom condField reads the right entry field', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'condition': 'full', 'qt': 3},
      ];
      final labels = <String, String>{'full': 'Isi'};
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, condField: 'condition', condLabels: labels);
      expect(rows[0].conditions[0].label, 'Isi');
    });

    test('grouped row attaches flow badges directly (no badged set)', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
      ];
      final flow = <String, ItemCirculation>{
        '9990019000045': const ItemCirculation(
            itemName: '9990019000045', totalDrop: 5, totalPickup: 5),
      };
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, flowMap: flow);
      expect(rows.length, 1);
      expect(rows[0].drop, 5);
      expect(rows[0].pickup, 5);
    });

    test('grouped row with no flow entry -> badges zero', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
      ];
      final rows = buildConfirmedRows(ip, details, groupByItem: true);
      expect(rows[0].drop, 0);
      expect(rows[0].pickup, 0);
    });

    test('empty ii entries skipped in grouped mode', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '', 'cd': 'full', 'qt': 10},
        {'ii': '9990019000045', 'cd': 'full', 'qt': 3},
      ];
      final rows = buildConfirmedRows(ip, details, groupByItem: true);
      expect(rows.length, 1);
    });

    test('category fallback: no detail -> empty category (W3)', () {
      final ip = <Map<String, dynamic>>[
        {'ii': 'unknown', 'cd': 'full', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, {}, groupByItem: true);
      expect(rows[0].category, '',
          reason: 'grouped mode falls back to empty, not raw cd');
      expect(rows[0].name, 'unknown');
    });

    test('single condition entry -> one-element conditions list', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 3},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: true, condLabels: condLabels);
      expect(rows.length, 1);
      expect(rows[0].qty, 3);
      expect(rows[0].conditions.length, 1);
      expect(rows[0].conditions[0].label, 'Penuh');
    });

    test('preserves first-seen item order', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '8800000001002', 'cd': 'full', 'qt': 3},
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
      ];
      final rows = buildConfirmedRows(ip, details, groupByItem: true);
      expect(rows[0].itemId, '8800000001002', reason: 'LPG first-seen');
      expect(rows[1].itemId, '9990019000045', reason: 'Amidis second-seen');
    });
  });

  // ── non-grouped regression (groupByItem=false) ────────────────────────────

  group('buildConfirmedRows -- non-grouped regression', () {
    final details = <String, ItemDetail>{
      '9990019000045': const ItemDetail(
          name: 'Amidis Galon 19 Liter', category: 'returnable'),
    };
    final condLabels = <String, String>{'full': 'Penuh', 'empty': 'Kosong'};

    test('non-grouped mode is unaffected: conditions always empty', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
        {'ii': '9990019000045', 'cd': 'empty', 'qt': 5},
      ];
      final rows = buildConfirmedRows(ip, details);
      expect(rows.length, 2, reason: 'non-grouped: one row per entry');
      for (final r in rows) {
        expect(r.conditions, isEmpty,
            reason: 'non-grouped rows never have conditions');
      }
    });

    test('groupByItem=false with condLabels/condField -> ignored', () {
      final ip = <Map<String, dynamic>>[
        {'ii': '9990019000045', 'cd': 'full', 'qt': 0},
      ];
      final rows = buildConfirmedRows(ip, details,
          groupByItem: false,
          condLabels: condLabels,
          consumableCategory: 'consumable');
      expect(rows.length, 1);
      expect(rows[0].conditions, isEmpty);
    });
  });
}
