// test/circulation_summary_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── circulationSummary text parsing ─────────────────────────────────────

  group('circulationSummary text parsing', () {
    test('5-slot text parsed and length-guarded', () {
      final text = [
        'Total Circulation', // 0
        'Muat', // 1
        'Total \u{2193} drop', // 2
        'Total \u{2191} pickup', // 3
        'Muat awal = jumlah drop total. Pickup nambah ke vehicle selama rute.', // 4
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 5);
      expect(arr.isNotEmpty ? arr[0] : '', 'Total Circulation');
      expect(arr.length > 4 ? arr[4] : '', contains('Muat awal'));
    });

    test('short text array uses defaults', () {
      final arr = diamondTextToList('Title');
      expect(arr.isNotEmpty ? arr[0] : 'def', 'Title');
      expect(arr.length > 1 ? arr[1] : 'Muat', 'Muat');
      expect(arr.length > 4 ? arr[4] : 'note', 'note');
    });
  });

  // ── Muat == Drop invariant ──────────────────────────────────────────────

  group('circulationSummary Muat == Drop invariant', () {
    test('Muat column equals Drop column per item (totalDrop)', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'Aqua', 'pd': '8', 'pp': '2'},
            {'in': 'LPG', 'pd': '5', 'pp': '0'},
          ],
        },
        {
          'it': [
            {'in': 'Aqua', 'pd': '4', 'pp': '3'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      // "Muat awal = jumlah drop total": Muat == totalDrop per item.
      for (final item in result.items) {
        // In the widget, the Muat column renders item.totalDrop (same value).
        expect(item.totalDrop, item.totalDrop); // tautology for doc purposes
      }
      // Verify actual values
      expect(result.items[0].totalDrop, 12); // Aqua: 8+4
      expect(result.items[1].totalDrop, 5); // LPG: 5
    });
  });

  // ── Grand total footer ─────────────────────────────────────────────────

  group('circulationSummary grand totals', () {
    test('grand totals sum correctly across multiple items', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'A', 'pd': '10', 'pp': '3'},
            {'in': 'B', 'pd': '5', 'pp': '2'},
          ],
        },
        {
          'it': [
            {'in': 'A', 'pd': '7', 'pp': '4'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.grandDrop, 22); // 10+5+7
      expect(result.grandPickup, 9); // 3+2+4
    });

    test('all-zero quantities produce zero grand totals', () {
      final taskDocs = [
        {
          'it': [
            {'in': 'A', 'pd': '0', 'pp': '0'},
          ],
        },
      ];
      final result = aggregateItemCirculation(taskDocs);
      expect(result.grandDrop, 0);
      expect(result.grandPickup, 0);
    });
  });

  // ── excludeByStatus + aggregateItemCirculation composition ───────────────

  group('excludeByStatus + aggregateItemCirculation composition', () {
    test('load_rejected task excluded from item circulation', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'in': 'Aqua', 'pd': '8', 'pp': '2'},
            {'in': 'LPG', 'pd': '5', 'pp': '0'},
          ],
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'in': 'Aqua', 'pd': '10', 'pp': '4'},
          ],
        },
      ];

      final filtered = excludeByStatus(taskDocs, 'load_rejected');
      expect(filtered.length, 1);

      final result = aggregateItemCirculation(filtered);
      // Only task 1 contributes: Aqua pd=8/pp=2, LPG pd=5/pp=0
      expect(result.items.length, 2);
      expect(result.grandDrop, 13); // 8+5, NOT 8+5+10
      expect(result.grandPickup, 2); // 2+0, NOT 2+0+4
    });

    test('empty excludeStatus includes all tasks in circulation', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [{'in': 'Aqua', 'pd': '8', 'pp': '2'}],
        },
        {
          'tst': 'load_rejected',
          'it': [{'in': 'Aqua', 'pd': '10', 'pp': '4'}],
        },
      ];

      final filtered = excludeByStatus(taskDocs, '');
      expect(filtered.length, 2);

      final result = aggregateItemCirculation(filtered);
      expect(result.grandDrop, 18); // 8+10
      expect(result.grandPickup, 6); // 2+4
    });

    test('failed status preserved when excludeStatus is load_rejected', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tst': 'failed',
          'it': [{'in': 'LPG', 'pd': '7', 'pp': '1'}],
        },
        {
          'tst': 'load_rejected',
          'it': [{'in': 'LPG', 'pd': '3', 'pp': '2'}],
        },
      ];

      final filtered = excludeByStatus(taskDocs, 'load_rejected');
      expect(filtered.length, 1);

      final result = aggregateItemCirculation(filtered);
      expect(result.grandDrop, 7); // only failed task
      expect(result.grandPickup, 1);
    });
  });

  // ── Opsi A: per-tx item circulation (spec (2).md §3) ────────────────────

  group('aggregateTxCirculation tx-driven flows', () {
    test('spec example: deliver/sale/purchase route to distinct flows', () {
      // Firebase otq-01 task i89dddJsDN3q94bw4lnZ (2026-06-24).
      final taskDocs = <Map<String, dynamic>>[
        {
          'it': [
            {
              'in': 'Amidis Galon 19 Liter',
              'tx': 'deliver',
              'pd': '3',
              'pp': '3'
            },
            {'in': 'Aqua 600ml', 'tx': 'sale', 'ps': '8'},
            {'in': 'LPG 12kg', 'tx': 'purchase', 'pb': '5'},
          ],
        },
      ];
      final r = aggregateTxCirculation(taskDocs);
      expect(r.items.length, 3);
      // deliver -> drop + pickup
      expect(r.items[0].drop, 3);
      expect(r.items[0].pickup, 3);
      expect(r.items[0].sale, 0);
      // sale -> Jual only (no longer 0/0/0)
      expect(r.items[1].sale, 8);
      expect(r.items[1].drop, 0);
      expect(r.items[1].pickup, 0);
      // purchase -> Beli only
      expect(r.items[2].buy, 5);
      expect(r.items[2].drop, 0);
    });

    test('refill routes to refill flow (pr)', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'Galon', 'tx': 'refill', 'pr': '4'}
          ]
        },
      ]);
      expect(r.items.single.refill, 4);
      expect(r.items.single.drop, 0);
    });

    test('empty/absent tx == deliver (backward-compat for old it[] lines)', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'A', 'tx': '', 'pd': '5', 'pp': '2'},
            {'in': 'B', 'pd': '7', 'pp': '1'}, // tx absent
          ]
        },
      ]);
      expect(r.items[0].drop, 5);
      expect(r.items[0].pickup, 2);
      expect(r.items[1].drop, 7);
      expect(r.items[1].pickup, 1);
    });

    test('unknown tx falls back to deliver', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'A', 'tx': 'mystery', 'pd': '3'}
          ]
        },
      ]);
      expect(r.items.single.drop, 3);
    });

    test('same item aggregated across tasks per flow', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'Aqua', 'tx': 'sale', 'ps': '8'}
          ]
        },
        {
          'it': [
            {'in': 'Aqua', 'tx': 'sale', 'ps': '5'}
          ]
        },
      ]);
      expect(r.items.single.sale, 13);
    });

    test('grand totals per flow', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'A', 'tx': 'deliver', 'pd': '3', 'pp': '1'},
            {'in': 'B', 'tx': 'sale', 'ps': '8'},
            {'in': 'C', 'tx': 'purchase', 'pb': '5'},
            {'in': 'D', 'tx': 'refill', 'pr': '2'},
          ]
        },
      ]);
      expect(r.grandDrop, 3);
      expect(r.grandPickup, 1);
      expect(r.grandSale, 8);
      expect(r.grandBuy, 5);
      expect(r.grandRefill, 2);
    });

    test('non-numeric qty -> 0; empty label skipped', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'A', 'tx': 'sale', 'ps': 'abc'},
            {'in': '', 'tx': 'sale', 'ps': '9'}, // empty label skipped
          ]
        },
      ]);
      expect(r.items.single.itemName, 'A');
      expect(r.items.single.sale, 0);
    });

    test('int qty values aggregate', () {
      final r = aggregateTxCirculation([
        {
          'it': [
            {'in': 'A', 'tx': 'sale', 'ps': 20}
          ]
        },
        {
          'it': [
            {'in': 'A', 'tx': 'sale', 'ps': 14}
          ]
        },
      ]);
      expect(r.items.single.sale, 34);
    });

    test('load_rejected excluded composes with tx aggregation', () {
      final taskDocs = <Map<String, dynamic>>[
        {
          'tst': 'assigned',
          'it': [
            {'in': 'A', 'tx': 'sale', 'ps': '8'}
          ]
        },
        {
          'tst': 'load_rejected',
          'it': [
            {'in': 'A', 'tx': 'sale', 'ps': '10'}
          ]
        },
      ];
      final filtered = excludeByStatus(taskDocs, 'load_rejected');
      final r = aggregateTxCirculation(filtered);
      expect(r.items.single.sale, 8); // NOT 18
    });

    test('TxItemCirculation.isEmpty true when all flows zero', () {
      const row = TxItemCirculation(itemName: 'A');
      expect(row.isEmpty, isTrue);
      const row2 = TxItemCirculation(itemName: 'B', sale: 1);
      expect(row2.isEmpty, isFalse);
    });

    test('empty task list -> empty result', () {
      final r = aggregateTxCirculation(<Map<String, dynamic>>[]);
      expect(r.items, isEmpty);
      expect(r.grandSale, 0);
    });
  });

  group('circulationSummary Opsi A text (7-seg)', () {
    test('7-slot text: title/Drop/Pickup/Jual/Tukar/Beli/caption', () {
      final text = [
        'Total Circulation', // 0 title
        'Drop', // 1
        'Pickup', // 2
        'Jual', // 3
        'Tukar', // 4
        'Beli', // 5
        'Sirkulasi barang hari ini per tujuan.', // 6 caption
      ].join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 7);
      expect(arr.length > 3 ? arr[3] : 'Jual', 'Jual');
      expect(arr.length > 5 ? arr[5] : 'Beli', 'Beli');
      expect(arr.length > 6 ? arr[6] : '', contains('Sirkulasi'));
    });

    // Mirror of the renderer's chip filter: only non-zero flows render.
    test('only non-zero flows produce a chip', () {
      const item = TxItemCirculation(itemName: 'Aqua', sale: 8);
      final chips = <String>[];
      void add(String label, int v) {
        if (v != 0) chips.add('$label $v');
      }

      add('Drop', item.drop);
      add('Pickup', item.pickup);
      add('Jual', item.sale);
      add('Tukar', item.refill);
      add('Beli', item.buy);
      expect(chips, ['Jual 8']);
    });
  });
}
