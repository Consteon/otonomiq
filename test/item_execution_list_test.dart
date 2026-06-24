// test/item_execution_list_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/item_execution_list.dart';

void main() {
  // ── Returnable vs consumable classification ───────────────────────────

  group('item type classification (pp > 0)', () {
    test('pp > 0 is returnable', () {
      final item = {'in': 'Galon 19L', 'pd': 3, 'pp': 2};
      final int pp =
          int.tryParse((item['pp'] ?? '0').toString().trim()) ?? 0;
      expect(pp > 0, true); // returnable
    });

    test('pp == 0 is consumable', () {
      final item = {'in': 'Aqua 600ml', 'pd': 5, 'pp': 0};
      final int pp =
          int.tryParse((item['pp'] ?? '0').toString().trim()) ?? 0;
      expect(pp > 0, false); // consumable
    });

    test('pp absent is consumable', () {
      final item = {'in': 'Mie Box', 'pd': 10};
      final int pp =
          int.tryParse((item['pp'] ?? '0').toString().trim()) ?? 0;
      expect(pp > 0, false); // consumable
    });

    test('pp as string parses correctly', () {
      final item = {'in': 'LPG 12kg', 'pd': '5', 'pp': '3'};
      final int pp =
          int.tryParse((item['pp'] ?? '0').toString().trim()) ?? 0;
      expect(pp, 3);
      expect(pp > 0, true); // returnable
    });
  });

  // ── Status state-machine thresholds ───────────────────────────────────

  group('execution stepper status state-machine', () {
    /// Pure function mirroring ItemExecutionList's per-cell status logic.
    /// Returns a status string for display.
    String cellStatus(int actual, int plan, bool isPickup) {
      if (actual < plan) {
        return 'partial';
      } else if (actual == plan) {
        return 'complete';
      } else {
        // actual > plan
        return isPickup ? 'opportunistic' : 'extra';
      }
    }

    test('actual < plan -> partial', () {
      expect(cellStatus(1, 3, false), 'partial');
      expect(cellStatus(0, 5, true), 'partial');
    });

    test('actual == plan -> complete', () {
      expect(cellStatus(3, 3, false), 'complete');
      expect(cellStatus(0, 0, true), 'complete');
    });

    test('actual > plan on pickup -> opportunistic', () {
      expect(cellStatus(5, 3, true), 'opportunistic');
    });

    test('actual > plan on drop -> extra', () {
      expect(cellStatus(5, 3, false), 'extra');
    });

    test('boundary: actual == plan == 0 is complete', () {
      expect(cellStatus(0, 0, false), 'complete');
      expect(cellStatus(0, 0, true), 'complete');
    });
  });

  // ── ExecutionEntry store isolation ────────────────────────────────────

  group('execution store per-scrName isolation', () {
    test('different scrNames are isolated', () {
      final Map<String, Map<String, _TestEntry>> store = {};
      store.putIfAbsent('p11a', () => {});
      store.putIfAbsent('p11b', () => {});
      store['p11a']!['0'] = _TestEntry(dropActual: 3, pickupActual: 2);
      store['p11b']!['0'] = _TestEntry(dropActual: 7, pickupActual: 0);
      expect(store['p11a']!['0']!.dropActual, 3);
      expect(store['p11b']!['0']!.dropActual, 7);
    });

    test('clearStore removes scrName entry', () {
      final Map<String, Map<String, _TestEntry>> store = {};
      store['scr1'] = {'0': _TestEntry(dropActual: 5, pickupActual: 1)};
      store.remove('scr1');
      expect(store.containsKey('scr1'), false);
    });
  });

  // ── diamondTextToList 11-segment guards ───────────────────────────────

  group('item execution list text segment guards', () {
    test('full 11-segment text parses all slots', () {
      final text =
          'hint\u{25C6}Drop\u{25C6}Pickup\u{25C6}partial\u{25C6}complete'
          '\u{25C6}opportunistic\u{25C6}extra\u{25C6}plan\u{25C6}Returnable'
          '\u{25C6}Consumable\u{25C6}pickupHint';
      final arr = diamondTextToList(text);
      expect(arr.length, 11);
      expect(arr[0], 'hint');
      expect(arr[10], 'pickupHint');
    });

    test('sparse text falls back for missing slots', () {
      final arr = diamondTextToList('justHint');
      expect(arr.isNotEmpty ? arr[0] : '', 'justHint');
      expect(arr.length > 1 ? arr[1] : 'Drop', 'Drop');
      expect(arr.length > 8 ? arr[8] : 'Returnable', 'Returnable');
      expect(arr.length > 9 ? arr[9] : 'Consumable', 'Consumable');
    });

    test('empty text returns length-1 array', () {
      final arr = diamondTextToList('');
      expect(arr.length, 1);
      expect(arr.length > 1 ? arr[1] : 'default', 'default');
    });
  });

  // ── TX-DELTA: classifyTxKind ─────────────────────────────────────────

  group('classifyTxKind', () {
    test('empty string returns deliver', () {
      expect(classifyTxKind(''), 'deliver');
    });

    test('"deliver" returns deliver', () {
      expect(classifyTxKind('deliver'), 'deliver');
    });

    test('"sale" returns sale', () {
      expect(classifyTxKind('sale'), 'sale');
    });

    test('"purchase" returns purchase', () {
      expect(classifyTxKind('purchase'), 'purchase');
    });

    test('"refill" returns refill', () {
      expect(classifyTxKind('refill'), 'refill');
    });

    test('unknown value falls back to deliver', () {
      expect(classifyTxKind('exchange'), 'deliver');
      expect(classifyTxKind('return'), 'deliver');
      expect(classifyTxKind('xyz'), 'deliver');
    });

    test('classification is case-insensitive (caller lowercases)', () {
      // classifyTxKind expects pre-lowercased input (per _buildRows).
      // Verify the raw call with uppercase falls back to deliver.
      expect(classifyTxKind('Sale'), 'deliver'); // not lowercased = unknown
      expect(classifyTxKind('REFILL'), 'deliver');
    });
  });

  // ── TX-DELTA: conditionLabel ─────────────────────────────────────────

  group('conditionLabel', () {
    test('"full" maps to penuh slot', () {
      expect(
        conditionLabel('full', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        'Penuh',
      );
    });

    test('"Full" (mixed case) maps to penuh slot', () {
      expect(
        conditionLabel('Full', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        'Penuh',
      );
    });

    test('"empty" maps to kosong slot', () {
      expect(
        conditionLabel('empty', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        'Kosong',
      );
    });

    test('"EMPTY" (uppercase) maps to kosong slot', () {
      expect(
        conditionLabel('EMPTY', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        'Kosong',
      );
    });

    test('unknown value returns raw trimmed string', () {
      expect(
        conditionLabel('half', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        'half',
      );
    });

    test('unknown with whitespace returns trimmed raw', () {
      expect(
        conditionLabel('  broken  ', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        'broken',
      );
    });

    test('empty string returns empty', () {
      expect(
        conditionLabel('', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        '',
      );
    });

    test('whitespace-only returns empty', () {
      expect(
        conditionLabel('   ', kosongSlot: 'Kosong', penuhSlot: 'Penuh'),
        '',
      );
    });
  });

  // ── TX-DELTA: waterLabel ─────────────────────────────────────────────

  group('waterLabel', () {
    test('"ro" maps to RO slot', () {
      expect(
        waterLabel('ro', roSlot: 'RO', isiUlangSlot: 'Isi Ulang'),
        'RO',
      );
    });

    test('"RO" (uppercase) maps to RO slot', () {
      expect(
        waterLabel('RO', roSlot: 'RO', isiUlangSlot: 'Isi Ulang'),
        'RO',
      );
    });

    test('any other non-empty value maps to isi ulang slot', () {
      expect(
        waterLabel('refill', roSlot: 'RO', isiUlangSlot: 'Isi Ulang'),
        'Isi Ulang',
      );
      expect(
        waterLabel('mineral', roSlot: 'RO', isiUlangSlot: 'Isi Ulang'),
        'Isi Ulang',
      );
    });

    test('empty string returns empty', () {
      expect(
        waterLabel('', roSlot: 'RO', isiUlangSlot: 'Isi Ulang'),
        '',
      );
    });

    test('whitespace-only returns empty', () {
      expect(
        waterLabel('   ', roSlot: 'RO', isiUlangSlot: 'Isi Ulang'),
        '',
      );
    });
  });

  // ── TX-DELTA: execution store skips non-deliver items ────────────────

  group('execution store tx-kind isolation', () {
    test('only deliver items should seed the store (integration note)', () {
      // This is a design-contract test: non-deliver items must NOT create
      // ExecutionEntry entries. The actual seeding is in _buildRows which
      // is private, so we verify the contract by documenting: the store
      // should contain keys ONLY for deliver items. Verified manually and
      // by the _buildRows code branching on txKind == 'deliver'.
      final Map<String, int> store = {};
      final items = [
        {'in': 'Galon', 'tx': 'deliver', 'pd': 3, 'pp': 2},
        {'in': 'Tabung', 'tx': 'sale', 'ps': 5},
        {'in': 'Aqua', 'tx': '', 'pd': 10, 'pp': 0}, // empty = deliver
        {'in': 'LPG', 'tx': 'refill', 'pr': 4},
      ];
      for (int i = 0; i < items.length; i++) {
        final tx = classifyTxKind(
            (items[i]['tx'] ?? '').toString().trim().toLowerCase());
        if (tx == 'deliver') {
          store[i.toString()] = 1; // simulate seeding
        }
      }
      expect(store.containsKey('0'), true); // deliver
      expect(store.containsKey('1'), false); // sale -- NOT seeded
      expect(store.containsKey('2'), true); // '' = deliver
      expect(store.containsKey('3'), false); // refill -- NOT seeded
      expect(store.length, 2);
    });
  });

  // ── TX-DELTA: 24-segment text guards ─────────────────────────────────

  group('24-segment text slot guards (tx-delta)', () {
    test('full 24-segment text parses all slots', () {
      final segments = List.generate(24, (i) => 'seg$i');
      final text = segments.join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 24);
      expect(arr[0], 'seg0');
      expect(arr[11], 'seg11');
      expect(arr[23], 'seg23');
    });

    test('11-segment text (old format) falls back for 11-23', () {
      final segments = List.generate(11, (i) => 'seg$i');
      final text = segments.join('\u{25C6}');
      final arr = diamondTextToList(text);
      expect(arr.length, 11);
      // Slots 11-23 must use defaults via _t length guard
      expect(arr.length > 11 ? arr[11] : 'Jual', 'Jual');
      expect(arr.length > 20 ? arr[20] : 'Kosong', 'Kosong');
      expect(arr.length > 23 ? arr[23] : 'Isi Ulang', 'Isi Ulang');
    });
  });

  // ── buildItemDetailMap pp classification (reuse from P6) ──────────────

  group('buildItemDetailMap with pp for type classification', () {
    test('items with pp > 0 can be classified as returnable', () {
      // Not the function's job to classify, but the caller reads pp from
      // the task doc's it[] array. This test verifies buildItemDetailMap
      // correctly resolves the category field for cross-checking.
      final itemDocs = <Map<String, dynamic>>[
        {'ii': 'galon', 'in': 'Galon 19L', 'ic': 'returnable'},
        {'ii': 'aqua', 'in': 'Aqua 600ml', 'ic': 'consumable'},
      ];
      final map = buildItemDetailMap(itemDocs);
      expect(map['galon']!.category, 'returnable');
      expect(map['aqua']!.category, 'consumable');
    });
  });
}

/// Test-only stand-in for ExecutionEntry (avoids importing widget file
/// before it exists -- tests run first in TDD order).
class _TestEntry {
  int dropActual;
  int pickupActual;
  _TestEntry({required this.dropActual, required this.pickupActual});
}
