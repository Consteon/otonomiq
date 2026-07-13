import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/customer_outstanding_list.dart';

void main() {
  const int now = 1720000000000; // fixed epoch-ms for determinism
  const int msPerDay = 86400000;

  // ── Empty scenarios ──────────────────────────────────────────────────────

  group('groupCustomerOutstanding empty scenarios', () {
    test('no docs -> empty result, grandTotal 0', () {
      final result = groupCustomerOutstanding(
        cacheDocs: const [],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups, isEmpty);
      expect(result.grandTotal, 0);
    });

    test('all qt == 0 with hideZero -> empty', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'I1', 'qt': 0, 't': now},
          {'lv': 'C1', 'ii': 'I2', 'qt': '0', 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        hideZero: true,
      );
      expect(result.groups, isEmpty);
      expect(result.grandTotal, 0);
    });

    test('all qt == 0 with hideZero false -> includes them', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'I1', 'qt': 0, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        hideZero: false,
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.totalQty, 0);
      expect(result.grandTotal, 0);
    });
  });

  // ── Basic grouping ─────────────────────────────────────────────────────

  group('groupCustomerOutstanding basic grouping', () {
    test('single customer, single item', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 5, 'cd': 'full', 't': now - 3 * msPerDay},
        ],
        customerDocs: [
          {'lv': 'C1', 'ln': 'Toko Ahmad', 'ty': 'retail'},
        ],
        itemDocs: [
          {'ii': 'GAS', 'in': 'Gas 3kg', 'ic': 'returnable'},
        ],
        nowMs: now,
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.customerName, 'Toko Ahmad');
      expect(result.groups.first.customerType, 'retail');
      expect(result.groups.first.totalQty, 5);
      expect(result.groups.first.items.length, 1);
      expect(result.groups.first.items.first.itemName, 'Gas 3kg');
      expect(result.groups.first.items.first.qty, 5);
      expect(result.groups.first.items.first.agingDays, 3);
      expect(result.grandTotal, 5);
    });

    test('conditions combined: full + empty = total pcs', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 3, 'cd': 'full', 't': now - msPerDay},
          {'lv': 'C1', 'ii': 'GAS', 'qt': 2, 'cd': 'empty', 't': now - 5 * msPerDay},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.totalQty, 5);
      expect(result.groups.first.items.length, 1);
      expect(result.groups.first.items.first.qty, 5);
      // oldest aging = 5 days (from the empty doc)
      expect(result.groups.first.items.first.agingDays, 5);
    });

    test('multiple customers sorted by total desc', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 3, 't': now},
          {'lv': 'C2', 'ii': 'GAS', 'qt': 10, 't': now},
          {'lv': 'C3', 'ii': 'GAS', 'qt': 7, 't': now},
        ],
        customerDocs: [
          {'lv': 'C1', 'ln': 'Small'},
          {'lv': 'C2', 'ln': 'Big'},
          {'lv': 'C3', 'ln': 'Medium'},
        ],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups.length, 3);
      expect(result.groups[0].customerName, 'Big');
      expect(result.groups[0].totalQty, 10);
      expect(result.groups[1].customerName, 'Medium');
      expect(result.groups[1].totalQty, 7);
      expect(result.groups[2].customerName, 'Small');
      expect(result.groups[2].totalQty, 3);
      expect(result.grandTotal, 20);
    });

    test('multiple items per customer', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 3, 't': now - 2 * msPerDay},
          {'lv': 'C1', 'ii': 'TAB', 'qt': 7, 't': now - 10 * msPerDay},
        ],
        customerDocs: [
          {'lv': 'C1', 'ln': 'Toko A'},
        ],
        itemDocs: [
          {'ii': 'GAS', 'in': 'Gas 3kg', 'ic': 'gas'},
          {'ii': 'TAB', 'in': 'Tabung 12kg', 'ic': 'tabung'},
        ],
        nowMs: now,
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.totalQty, 10);
      expect(result.groups.first.items.length, 2);
      // oldest aging = 10 days
      expect(result.groups.first.oldestAgingDays, 10);
    });
  });

  // ── Type-tolerant qt parsing ───────────────────────────────────────────

  group('qt as string', () {
    test('qt is a string number', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': '12', 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups.first.totalQty, 12);
    });

    test('qt is non-numeric string -> 0', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 'abc', 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        hideZero: false,
      );
      expect(result.groups.first.totalQty, 0);
    });

    test('qt is null -> 0', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': null, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        hideZero: false,
      );
      expect(result.groups.first.totalQty, 0);
    });
  });

  // ── hideZero pruning ───────────────────────────────────────────────────

  group('hideZero pruning', () {
    test('hideZero drops 0-total customers', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 5, 't': now},
          {'lv': 'C2', 'ii': 'GAS', 'qt': 0, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        hideZero: true,
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.customerId, 'C1');
      expect(result.grandTotal, 5);
    });

    test('hideZero drops 0-qty items within a customer', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 5, 't': now},
          {'lv': 'C1', 'ii': 'TAB', 'qt': 0, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        hideZero: true,
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.items.length, 1);
      expect(result.groups.first.items.first.itemId, 'GAS');
    });
  });

  // ── Aging tiers ────────────────────────────────────────────────────────

  group('aging tier assignment', () {
    test('> dangerAge -> kritis', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 1, 't': now - 31 * msPerDay},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        dangerAge: 30,
        warnAge: 14,
      );
      expect(result.groups.first.tier, 'kritis');
    });

    test('> warnAge but <= dangerAge -> perhatian', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 1, 't': now - 20 * msPerDay},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        dangerAge: 30,
        warnAge: 14,
      );
      expect(result.groups.first.tier, 'perhatian');
    });

    test('<= warnAge -> normal', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 1, 't': now - 5 * msPerDay},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
        dangerAge: 30,
        warnAge: 14,
      );
      expect(result.groups.first.tier, 'normal');
    });

    test('t == 0 -> agingDays 0 -> normal', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 1, 't': 0},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups.first.oldestAgingDays, 0);
      expect(result.groups.first.tier, 'normal');
    });
  });

  // ── Missing join rows ──────────────────────────────────────────────────

  group('missing join rows', () {
    test('unknown lv -> customerName falls back to lv', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'UNKNOWN', 'ii': 'GAS', 'qt': 1, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups.first.customerName, 'UNKNOWN');
      expect(result.groups.first.customerType, '');
    });

    test('unknown ii -> itemName falls back to ii', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'MYSTERY', 'qt': 1, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.groups.first.items.first.itemName, 'MYSTERY');
      expect(result.groups.first.items.first.itemCategory, '');
    });
  });

  // ── Sparse/short diamond text ──────────────────────────────────────────

  group('diamond text length guard', () {
    // Simulates the _t() accessor: arr.length > i ? arr[i] : def
    String t(List<String> arr, int i, [String def = '']) =>
        arr.length > i ? arr[i] : def;

    test('empty text -> all defaults', () {
      final arr = <String>[];
      expect(t(arr, 0, 'default0'), 'default0');
      expect(t(arr, 4, 'default4'), 'default4');
    });

    test('short text -> partial defaults', () {
      final arr = ['total'];
      expect(t(arr, 0), 'total');
      expect(t(arr, 1, 'pcs'), 'pcs');
      expect(t(arr, 4, 'hari'), 'hari');
    });

    test('full text -> all slots available', () {
      final arr = ['a', 'b', 'c', 'd', 'e'];
      expect(t(arr, 0), 'a');
      expect(t(arr, 4), 'e');
    });
  });

  // ── Grand total ────────────────────────────────────────────────────────

  group('grand total', () {
    test('grand total = sum of all customer totals', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'lv': 'C1', 'ii': 'GAS', 'qt': 5, 't': now},
          {'lv': 'C1', 'ii': 'TAB', 'qt': 3, 't': now},
          {'lv': 'C2', 'ii': 'GAS', 'qt': 12, 't': now},
        ],
        customerDocs: const [],
        itemDocs: const [],
        nowMs: now,
      );
      expect(result.grandTotal, 20);
    });
  });

  // ── Config field overrides ─────────────────────────────────────────────

  group('config field overrides', () {
    test('custom groupField + itemField + qtyField + ageField', () {
      final result = groupCustomerOutstanding(
        cacheDocs: [
          {'loc': 'C1', 'prod': 'GAS', 'amount': 7, 'ts': now - 2 * msPerDay},
        ],
        customerDocs: [
          {'loc': 'C1', 'name': 'Custom', 'kind': 'wholesale'},
        ],
        itemDocs: [
          {'prod': 'GAS', 'label': 'Gas 3kg', 'cat': 'gas'},
        ],
        nowMs: now,
        groupField: 'loc',
        itemField: 'prod',
        qtyField: 'amount',
        ageField: 'ts',
        customerKey: 'loc',
        nameField: 'name',
        typeField: 'kind',
        itemKey: 'prod',
        itemNameField: 'label',
        itemCatField: 'cat',
      );
      expect(result.groups.length, 1);
      expect(result.groups.first.customerName, 'Custom');
      expect(result.groups.first.customerType, 'wholesale');
      expect(result.groups.first.totalQty, 7);
      expect(result.groups.first.items.first.itemName, 'Gas 3kg');
      expect(result.groups.first.items.first.itemCategory, 'gas');
      expect(result.grandTotal, 7);
    });
  });

  // ── ChipAccent resolution ─────────────────────────────────────────────

  group('ChipAccent', () {
    test('named slot resolves to known accent', () {
      final accent = ChipAccent.forSlot('blue');
      expect(accent.bg, isNotNull);
      expect(accent.fg, isNotNull);
    });

    test('unknown slot -> fallback slate', () {
      final accent = ChipAccent.forSlot('nonexistent');
      expect(accent, same(ChipAccent.slate));
    });

    test('empty slot -> fallback slate', () {
      final accent = ChipAccent.forSlot('');
      expect(accent, same(ChipAccent.slate));
    });

    test('deterministic assignment is stable', () {
      final a1 = ChipAccent.forCategory('galon');
      final a2 = ChipAccent.forCategory('galon');
      expect(a1, same(a2));
    });

    test('different categories get (potentially) different accents', () {
      // With 7 slots, collisions are possible but different strings should
      // at least hash consistently.
      final a1 = ChipAccent.forCategory('galon');
      final a2 = ChipAccent.forCategory('tabung12');
      // Both are valid ChipAccent instances
      expect(a1.bg, isNotNull);
      expect(a2.bg, isNotNull);
    });
  });
}
