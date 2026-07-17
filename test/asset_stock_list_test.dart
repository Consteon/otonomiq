import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/asset_stock_list.dart';

void main() {
  const List<String> pivots = ['warehouse', 'vehicle', 'client'];
  const List<String> conds = ['full', 'empty'];

  // -- Empty scenarios ------------------------------------------------------

  group('groupAssetStock empty scenarios', () {
    test('no docs -> empty result, summary all=0', () {
      final result = groupAssetStock(
        cacheDocs: const [],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities, isEmpty);
      expect(result.summaryValues['all'], 0);
    });

    test('all qt==0 with hideZero -> empty entities', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 0},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: true,
      );
      expect(result.entities, isEmpty);
      // Summary still counts (gross)
      expect(result.summaryValues['all'], 0);
    });

    test('all qt==0 with hideZero false -> includes entity', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 0},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: false,
      );
      expect(result.entities.length, 1);
      expect(result.entities.first.total, 0);
    });
  });

  // -- Basic pivot cube -----------------------------------------------------

  group('groupAssetStock basic pivot cube', () {
    test('single entity, single pivot+cond', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 10},
        ],
        itemDocs: [
          {'ii': 'GAS', 'in': 'Gas 3kg', 'ic': 'gas'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.length, 1);
      final e = result.entities.first;
      expect(e.id, 'GAS');
      expect(e.name, 'Gas 3kg');
      expect(e.category, 'gas');
      expect(e.total, 10);
      expect(e.pivots['warehouse']!.total, 10);
      expect(e.pivots['warehouse']!.condTotals['full'], 10);
      expect(e.pivots['warehouse']!.condTotals['empty'], 0);
      // vehicle/client pivots not present (zero + hideZero)
      expect(e.pivots.containsKey('vehicle'), false);
    });

    test('entity across multiple pivots and conds', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 100},
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'empty', 'qt': 50},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 20},
          {'ii': 'GAS', 'lt': 'client', 'cd': 'full', 'qt': 30},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.length, 1);
      final e = result.entities.first;
      expect(e.total, 200);
      expect(e.pivots['warehouse']!.total, 150);
      expect(e.pivots['warehouse']!.condTotals['full'], 100);
      expect(e.pivots['warehouse']!.condTotals['empty'], 50);
      expect(e.pivots['vehicle']!.total, 20);
      expect(e.pivots['client']!.total, 30);
    });
  });

  // -- Multi-entity sort ----------------------------------------------------

  group('multi-entity sort', () {
    test('sorted by total desc', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'A', 'lt': 'warehouse', 'cd': 'full', 'qt': 5},
          {'ii': 'B', 'lt': 'warehouse', 'cd': 'full', 'qt': 20},
          {'ii': 'C', 'lt': 'warehouse', 'cd': 'full', 'qt': 10},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.length, 3);
      expect(result.entities[0].id, 'B');
      expect(result.entities[1].id, 'C');
      expect(result.entities[2].id, 'A');
    });

    test('tie-break by id asc', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'ZZZ', 'lt': 'warehouse', 'cd': 'full', 'qt': 10},
          {'ii': 'AAA', 'lt': 'warehouse', 'cd': 'full', 'qt': 10},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.length, 2);
      expect(result.entities[0].id, 'AAA');
      expect(result.entities[1].id, 'ZZZ');
    });
  });

  // -- Summary scope keys ---------------------------------------------------

  group('summary scope keys', () {
    test('all + pivot + pivot.cond scopes computed', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 100},
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'empty', 'qt': 50},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 20},
          {'ii': 'TAB', 'lt': 'warehouse', 'cd': 'full', 'qt': 30},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.summaryValues['all'], 200);
      expect(result.summaryValues['warehouse'], 180);
      expect(result.summaryValues['vehicle'], 20);
      expect(result.summaryValues['warehouse.full'], 130);
      expect(result.summaryValues['warehouse.empty'], 50);
      expect(result.summaryValues['vehicle.full'], 20);
    });

    test('summary is gross (unaffected by hideZero)', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 10},
          {'ii': 'ZERO', 'lt': 'warehouse', 'cd': 'full', 'qt': 0},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: true,
      );
      // Entity ZERO pruned from entities list
      expect(result.entities.length, 1);
      // Summary still counts everything (10 + 0 = 10)
      expect(result.summaryValues['all'], 10);
    });
  });

  // -- hideZero pruning -----------------------------------------------------

  group('hideZero pruning', () {
    test('prunes zero-total entity', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 5},
          {'ii': 'ZERO', 'lt': 'warehouse', 'cd': 'full', 'qt': 0},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: true,
      );
      expect(result.entities.length, 1);
      expect(result.entities.first.id, 'GAS');
    });

    test('prunes zero-total pivot cell from entity', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 10},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 0},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: true,
      );
      expect(result.entities.length, 1);
      expect(result.entities.first.pivots.containsKey('warehouse'), true);
      expect(result.entities.first.pivots.containsKey('vehicle'), false);
    });
  });

  // -- Type-tolerant qty parsing --------------------------------------------

  group('_safeInt via valueField', () {
    test('qt as string number', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': '15'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.first.total, 15);
    });

    test('qt as non-numeric string -> 0', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 'abc'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: false,
      );
      expect(result.entities.first.total, 0);
    });

    test('qt null -> 0', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': null},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: false,
      );
      expect(result.entities.first.total, 0);
    });
  });

  // -- Missing join rows ---------------------------------------------------

  group('missing join rows', () {
    test('unknown ii -> name falls back to id', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'MYSTERY', 'lt': 'warehouse', 'cd': 'full', 'qt': 1},
        ],
        itemDocs: const [],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.first.name, 'MYSTERY');
      expect(result.entities.first.category, '');
    });
  });

  // -- Sparse/short config rows (diamond text) ------------------------------

  group('diamond text length guard', () {
    String t(List<String> arr, int i, [String def = '']) =>
        arr.length > i ? arr[i] : def;

    test('empty text -> all defaults', () {
      final arr = <String>[];
      expect(t(arr, 0, 'total'), 'total');
      expect(t(arr, 1, 'Semua'), 'Semua');
      expect(t(arr, 3, ''), '');
    });

    test('short text -> partial defaults', () {
      final arr = ['label0'];
      expect(t(arr, 0), 'label0');
      expect(t(arr, 1, 'Semua'), 'Semua');
      expect(t(arr, 3, ''), '');
    });
  });

  // -- Positional cond mapping ----------------------------------------------

  group('positional cond mapping', () {
    test('condTotals keyed by condOrder values', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 60},
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'empty', 'qt': 40},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      final pivot = result.entities.first.pivots['warehouse']!;
      expect(pivot.condTotals['full'], 60);
      expect(pivot.condTotals['empty'], 40);
      expect(pivot.total, 100);
    });

    test('missing cd field -> qty counted in pivot total, not in condTotals', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'qt': 10}, // no cd
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      final pivot = result.entities.first.pivots['warehouse']!;
      // cd '' is not in condOrder, so counted in pivotTotal but not in condTotals
      expect(pivot.total, 10);
      expect(pivot.condTotals['full'], 0);
      expect(pivot.condTotals['empty'], 0);
    });
  });

  // -- Outstanding-pivot detection ------------------------------------------

  group('outstanding-pivot detection', () {
    // The widget uses: last pivotValue AND text seg-3 non-empty.
    // We test the logic pattern here (not the widget method directly).

    test('last pivot with non-empty seg-3 is outstanding', () {
      // Simulates _isOutstandingPivot logic
      const int pivotCount = 3;
      const String seg3 = 'dipinjam (lagi dipakai)';
      bool isOutstanding(int idx) =>
          idx == pivotCount - 1 && seg3.isNotEmpty;

      expect(isOutstanding(0), false);
      expect(isOutstanding(1), false);
      expect(isOutstanding(2), true);
    });

    test('last pivot with empty seg-3 is NOT outstanding', () {
      const int pivotCount = 3;
      const String seg3 = '';
      bool isOutstanding(int idx) =>
          idx == pivotCount - 1 && seg3.isNotEmpty;

      expect(isOutstanding(2), false);
    });
  });

  // -- Config parse: pivotValues/condValues split ---------------------------

  group('pivotValues/condValues parse', () {
    // Simulates the parse pattern in _parseConfig

    List<(String value, String label, String icon)> parsePivots(String raw) {
      final List<(String, String, String)> result = [];
      for (final entry in raw.split('\u{2605}')) {
        final segs = entry.split('\u{25FC}');
        if (segs.isEmpty) continue;
        final v = segs[0].trim();
        final l = segs.length > 1 ? segs[1].trim() : v;
        final ic = segs.length > 2 ? segs[2].trim() : '';
        if (v.isNotEmpty) result.add((v, l, ic));
      }
      return result;
    }

    test('full 3-segment pivotValues', () {
      const raw = 'warehouse\u{25FC}Gudang\u{25FC}\u{1F3E0}'
          '\u{2605}vehicle\u{25FC}Mobil\u{25FC}\u{1F69A}'
          '\u{2605}client\u{25FC}Customer\u{25FC}\u{1F464}';
      final parsed = parsePivots(raw);
      expect(parsed.length, 3);
      expect(parsed[0], ('warehouse', 'Gudang', '\u{1F3E0}'));
      expect(parsed[1], ('vehicle', 'Mobil', '\u{1F69A}'));
      expect(parsed[2], ('client', 'Customer', '\u{1F464}'));
    });

    test('2-segment pivotValues (no icon)', () {
      const raw = 'warehouse\u{25FC}Gudang\u{2605}vehicle\u{25FC}Mobil';
      final parsed = parsePivots(raw);
      expect(parsed.length, 2);
      expect(parsed[0].$3, ''); // no icon
    });

    test('1-segment pivotValues (value only, label=value)', () {
      const raw = 'warehouse\u{2605}vehicle';
      final parsed = parsePivots(raw);
      expect(parsed.length, 2);
      expect(parsed[0].$2, 'warehouse'); // label falls back to value
    });

    List<(String value, String label)> parseConds(String raw) {
      final List<(String, String)> result = [];
      for (final entry in raw.split('\u{2605}')) {
        final segs = entry.split('\u{25FC}');
        if (segs.isEmpty) continue;
        final v = segs[0].trim();
        final l = segs.length > 1 ? segs[1].trim() : v;
        if (v.isNotEmpty) result.add((v, l));
      }
      return result;
    }

    test('condValues parse', () {
      const raw = 'full\u{25FC}Isi\u{2605}empty\u{25FC}Kosong';
      final parsed = parseConds(raw);
      expect(parsed.length, 2);
      expect(parsed[0], ('full', 'Isi'));
      expect(parsed[1], ('empty', 'Kosong'));
    });
  });

  // -- Config field overrides -----------------------------------------------

  group('config field overrides', () {
    test('custom groupField + valueField + pivotField + condField', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'prod': 'GAS', 'loc': 'wh', 'status': 'ok', 'amount': 7},
        ],
        itemDocs: [
          {'prod': 'GAS', 'label': 'Gas 3kg', 'cat': 'gas'},
        ],
        groupField: 'prod',
        valueField: 'amount',
        pivotField: 'loc',
        condField: 'status',
        itemKey: 'prod',
        nameField: 'label',
        catField: 'cat',
        pivotOrder: ['wh'],
        condOrder: ['ok'],
      );
      expect(result.entities.length, 1);
      expect(result.entities.first.name, 'Gas 3kg');
      expect(result.entities.first.total, 7);
      expect(result.entities.first.pivots['wh']!.total, 7);
      expect(result.entities.first.pivots['wh']!.condTotals['ok'], 7);
    });
  });

  // -- Empty payload --------------------------------------------------------

  group('empty payload', () {
    test('empty cacheDocs + empty itemDocs -> empty result', () {
      final result = groupAssetStock(
        cacheDocs: const [],
        itemDocs: const [],
        pivotOrder: const [],
        condOrder: const [],
      );
      expect(result.entities, isEmpty);
      expect(result.summaryValues['all'], 0);
    });
  });

  // -- DetailRow aggregation (detailField / detailNameField) -----------------

  group('detailField empty -> no details (zero regression)', () {
    test('detailField empty -> all PivotCell.details empty', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 10, 'lv': 'WH1', 'ln': 'Gudang Utama'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: '',
      );
      expect(result.entities.length, 1);
      expect(result.entities.first.pivots['warehouse']!.details, isEmpty);
    });

    test('detailField omitted (default empty) -> no details', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'warehouse', 'cd': 'full', 'qt': 10, 'lv': 'WH1'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
      );
      expect(result.entities.first.pivots['warehouse']!.details, isEmpty);
    });
  });

  group('detailField per-lv grouping', () {
    test('groups by detailField within pivot', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1', 'ln': 'B 1234 XY'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'empty', 'qt': 5, 'lv': 'V1', 'ln': 'B 1234 XY'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 3, 'lv': 'V2', 'ln': 'B 5678 CD'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: 'ln',
      );
      final pivot = result.entities.first.pivots['vehicle']!;
      expect(pivot.details.length, 2);
      // Sorted by total desc: V1=15, V2=3
      expect(pivot.details[0].id, 'V1');
      expect(pivot.details[0].name, 'B 1234 XY');
      expect(pivot.details[0].total, 15);
      expect(pivot.details[0].condTotals['full'], 10);
      expect(pivot.details[0].condTotals['empty'], 5);
      expect(pivot.details[1].id, 'V2');
      expect(pivot.details[1].name, 'B 5678 CD');
      expect(pivot.details[1].total, 3);
    });

    test('detail does not affect entity-level pivot totals', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 3, 'lv': 'V2'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
      );
      // Entity-level pivot total unchanged
      expect(result.entities.first.pivots['vehicle']!.total, 13);
      expect(result.entities.first.total, 13);
    });

    test('empty lv value on doc -> excluded from detail rows', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': ''},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
      );
      final pivot = result.entities.first.pivots['vehicle']!;
      // Only V1 in detail; empty-lv doc still counts in pivot total
      expect(pivot.details.length, 1);
      expect(pivot.details.first.id, 'V1');
      expect(pivot.total, 15);
    });
  });

  group('detailNameField name resolution', () {
    test('first non-empty ln wins for a given lv', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'V1', 'ln': 'First Name'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'empty', 'qt': 3, 'lv': 'V1', 'ln': 'Second Name'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: 'ln',
      );
      expect(result.entities.first.pivots['vehicle']!.details.first.name, 'First Name');
    });

    test('all ln empty -> falls back to lv id', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'V1', 'ln': ''},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 3, 'lv': 'V1'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: 'ln',
      );
      expect(result.entities.first.pivots['vehicle']!.details.first.name, 'V1');
    });

    test('detailNameField empty -> name falls back to id', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'V1', 'ln': 'Some Name'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: '',
      );
      expect(result.entities.first.pivots['vehicle']!.details.first.name, 'V1');
    });
  });

  group('hideZero per detail row', () {
    test('zero-total detail row pruned when hideZero true', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 0, 'lv': 'V2'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: true,
        detailField: 'lv',
      );
      final pivot = result.entities.first.pivots['vehicle']!;
      expect(pivot.details.length, 1);
      expect(pivot.details.first.id, 'V1');
    });

    test('zero-total detail row kept when hideZero false', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 0, 'lv': 'V2'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        hideZero: false,
        detailField: 'lv',
      );
      final pivot = result.entities.first.pivots['vehicle']!;
      expect(pivot.details.length, 2);
    });
  });

  group('detail row sort order', () {
    test('sorted total desc, tie-break id asc', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'ZZZ'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'AAA'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 20, 'lv': 'MID'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
      );
      final details = result.entities.first.pivots['vehicle']!.details;
      expect(details.length, 3);
      expect(details[0].id, 'MID'); // 20
      expect(details[1].id, 'AAA'); // 5, tie-break asc
      expect(details[2].id, 'ZZZ'); // 5, tie-break asc
    });
  });

  group('detail row condTotals', () {
    test('condTotals populated per detail row', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'empty', 'qt': 3, 'lv': 'V1'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
      );
      final dr = result.entities.first.pivots['vehicle']!.details.first;
      expect(dr.condTotals['full'], 10);
      expect(dr.condTotals['empty'], 3);
      expect(dr.total, 13);
    });

    test('missing cd on detail doc -> counted in total not condTotals', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'qt': 7, 'lv': 'V1'}, // no cd
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
      );
      final dr = result.entities.first.pivots['vehicle']!.details.first;
      expect(dr.total, 7);
      expect(dr.condTotals['full'], 0);
      expect(dr.condTotals['empty'], 0);
    });
  });

  group('detail across multiple entities', () {
    test('detail rows scoped per entity', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1'},
          {'ii': 'TAB', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'V2'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
      );
      // GAS has V1, TAB has V2 -- details are per-entity
      final gas = result.entities.firstWhere((e) => e.id == 'GAS');
      final tab = result.entities.firstWhere((e) => e.id == 'TAB');
      expect(gas.pivots['vehicle']!.details.length, 1);
      expect(gas.pivots['vehicle']!.details.first.id, 'V1');
      expect(tab.pivots['vehicle']!.details.length, 1);
      expect(tab.pivots['vehicle']!.details.first.id, 'V2');
    });
  });

  // -- detailSubField (R4) ----------------------------------------------------

  group('detailSubField captures sub into DetailRow.sub', () {
    test('sub captured from detailSubField (first non-empty wins)', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1', 'ln': 'B 1234 XY', 'ty': 'Pickup'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'empty', 'qt': 5, 'lv': 'V1', 'ln': 'B 1234 XY', 'ty': 'Truck'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 3, 'lv': 'V2', 'ln': 'B 5678 CD', 'ty': 'Motor'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: 'ln',
        detailSubField: 'ty',
      );
      final details = result.entities.first.pivots['vehicle']!.details;
      expect(details.length, 2);
      // V1 total=15, V2 total=3 -> sorted desc
      expect(details[0].id, 'V1');
      expect(details[0].name, 'B 1234 XY');
      expect(details[0].sub, 'Pickup'); // first non-empty wins
      expect(details[1].id, 'V2');
      expect(details[1].sub, 'Motor');
    });

    test('detailSubField empty (omitted) -> DetailRow.sub is empty string (zero regression)', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1', 'ln': 'B 1234 XY', 'ty': 'Pickup'},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: 'ln',
        // detailSubField omitted -> default ''
      );
      final dr = result.entities.first.pivots['vehicle']!.details.first;
      expect(dr.name, 'B 1234 XY');
      expect(dr.sub, '');
    });

    test('doc missing ty field -> sub is empty string, no error', () {
      final result = groupAssetStock(
        cacheDocs: [
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 10, 'lv': 'V1', 'ln': 'B 1234 XY'},
          {'ii': 'GAS', 'lt': 'vehicle', 'cd': 'full', 'qt': 5, 'lv': 'V2', 'ln': 'B 5678 CD', 'ty': ''},
        ],
        pivotOrder: pivots,
        condOrder: conds,
        detailField: 'lv',
        detailNameField: 'ln',
        detailSubField: 'ty',
      );
      final details = result.entities.first.pivots['vehicle']!.details;
      // Both docs have empty/missing ty -> sub stays ''
      expect(details[0].sub, '');
      expect(details[1].sub, '');
      // Names still resolve correctly
      expect(details[0].name, 'B 1234 XY');
      expect(details[1].name, 'B 5678 CD');
    });
  });
}
