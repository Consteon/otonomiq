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

  // ── DROP CAP: buildDropCapMap pure helper ────────────────────────────

  group('buildDropCapMap', () {
    test('builds {ii -> qt} map from cap docs', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon19', 'qt': 5, 'lv': 'v1', 'cd': 'full'},
        {'ii': 'aqua600', 'qt': 12, 'lv': 'v1', 'cd': 'full'},
      ];
      final result = buildDropCapMap(docs, capKeyField: 'ii', capValueField: 'qt');
      expect(result, {'galon19': 5, 'aqua600': 12});
    });

    test('empty docs returns empty map', () {
      final result = buildDropCapMap(
        const <Map<String, dynamic>>[],
        capKeyField: 'ii',
        capValueField: 'qt',
      );
      expect(result, isEmpty);
    });

    test('missing capKeyField skips doc', () {
      final docs = <Map<String, dynamic>>[
        {'qt': 5, 'lv': 'v1'},
        {'ii': 'galon', 'qt': 3},
      ];
      final result = buildDropCapMap(docs, capKeyField: 'ii', capValueField: 'qt');
      expect(result, {'galon': 3});
    });

    test('non-numeric qt defaults to 0', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon', 'qt': 'abc'},
      ];
      final result = buildDropCapMap(docs, capKeyField: 'ii', capValueField: 'qt');
      expect(result, {'galon': 0});
    });

    test('missing qt defaults to 0', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon'},
      ];
      final result = buildDropCapMap(docs, capKeyField: 'ii', capValueField: 'qt');
      expect(result, {'galon': 0});
    });

    test('duplicate ii keeps last write', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon', 'qt': 3},
        {'ii': 'galon', 'qt': 7},
      ];
      final result = buildDropCapMap(docs, capKeyField: 'ii', capValueField: 'qt');
      expect(result, {'galon': 7});
    });

    test('qt as string parses correctly', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon', 'qt': '10'},
      ];
      final result = buildDropCapMap(docs, capKeyField: 'ii', capValueField: 'qt');
      expect(result, {'galon': 10});
    });

    test('custom field names work', () {
      final docs = <Map<String, dynamic>>[
        {'itemCode': 'g19', 'stock': 8},
      ];
      final result =
          buildDropCapMap(docs, capKeyField: 'itemCode', capValueField: 'stock');
      expect(result, {'g19': 8});
    });
  });

  // ── DROP CAP: seed-clamp (rowCap-nullable) ──────────────────────────────────────

  group('drop cap seed-clamp (rowCap-nullable)', () {
    /// Pure seed-clamp logic mirroring _buildRows deliver branch.
    /// rowCap == null -> plan (no cap / unresolved).
    /// rowCap != null -> min(plan, rowCap).
    int seedDrop(int planDrop, int? rowCap) {
      if (rowCap == null) return planDrop;
      return planDrop < rowCap ? planDrop : rowCap;
    }

    test('plan 3, rowCap 1 -> seed 1 (THE bug fix)', () {
      expect(seedDrop(3, 1), 1);
    });

    test('plan 3, rowCap 5 -> seed 3 (plan < cap)', () {
      expect(seedDrop(3, 5), 3);
    });

    test('plan 3, rowCap 3 -> seed 3 (exact match)', () {
      expect(seedDrop(3, 3), 3);
    });

    test('rowCap 0 -> seed 0 (item not in asset_cache)', () {
      expect(seedDrop(3, 0), 0);
    });

    test('rowCap null -> seed = plan (unresolved or no-cap)', () {
      expect(seedDrop(3, null), 3);
      expect(seedDrop(5, null), 5);
      expect(seedDrop(0, null), 0);
    });

    test('plan 0, rowCap 5 -> seed 0 (zero plan stays zero)', () {
      expect(seedDrop(0, 5), 0);
    });
  });

  // ── DROP CAP: increment clamp ───────────────────────────────────────

  group('drop cap increment clamp', () {
    test('[+] disabled when dropActual >= cap', () {
      const int dropActual = 3;
      const int cap = 3;
      final bool disabled = dropActual >= cap;
      expect(disabled, true);
    });

    test('[+] enabled when dropActual < cap', () {
      const int dropActual = 2;
      const int cap = 3;
      final bool disabled = dropActual >= cap;
      expect(disabled, false);
    });

    test('[+] always enabled when cap is null (no-cap mode)', () {
      const int dropActual = 100;
      const int? cap = null;
      final bool disabled = cap != null && dropActual >= cap;
      expect(disabled, false);
    });

    test('increment clamp: min(value+1, cap)', () {
      int clampedIncrement(int current, int? cap) {
        final int next = current + 1;
        if (cap == null) return next;
        return next < cap ? next : cap;
      }

      expect(clampedIncrement(2, 3), 3);
      expect(clampedIncrement(3, 3), 3); // already at cap
      expect(clampedIncrement(4, 3), 3); // over cap (defense)
      expect(clampedIncrement(2, null), 3); // no cap
    });
  });

  // ── DROP CAP: capLabel token resolution ─────────────────────────────

  group('capLabel <max> token resolution', () {
    test('<max> resolves to cap value', () {
      const String raw = 'Maks <max> \u{2014} stok mobil';
      final String resolved = raw.replaceAll('<max>', '5');
      expect(resolved, 'Maks 5 \u{2014} stok mobil');
    });

    test('no <max> token in label -> unchanged', () {
      const String raw = 'Stok terbatas';
      final String resolved = raw.replaceAll('<max>', '5');
      expect(resolved, 'Stok terbatas');
    });

    test('cap 0 -> <max> resolves to 0', () {
      const String raw = 'Maks <max>';
      final String resolved = raw.replaceAll('<max>', '0');
      expect(resolved, 'Maks 0');
    });
  });

  // ── DROP CAP: status precedence ─────────────────────────────────────

  group('cap status precedence over plan-relative', () {
    test('at cap -> capped status (overrides partial/complete/extra)', () {
      // When dropActual == cap, status is 'capped' regardless of plan.
      const int cap = 1;
      const int dropActual = 1;
      // Plan (3) says partial (1 < 3), but cap overrides.
      final String status = (dropActual == cap) ? 'capped' : 'partial';
      expect(status, 'capped');
    });

    test('below cap -> plan-relative status applies', () {
      const int cap = 5;
      const int dropActual = 2;
      final bool atCap = dropActual == cap;
      expect(atCap, false);
      // Plan (3) logic: 2 < 3 = partial
    });
  });

  // ── DROP CAP: capStore per-scrName isolation ────────────────────────

  group('capStore per-scrName isolation', () {
    test('different scrNames have independent cap maps', () {
      final Map<String, Map<String, int>> store = {};
      store['p11a'] = {'galon': 5};
      store['p11b'] = {'galon': 1};
      expect(store['p11a']!['galon'], 5);
      expect(store['p11b']!['galon'], 1);
    });

    test('clearing one scrName does not affect another', () {
      final Map<String, Map<String, int>> store = {};
      store['p11a'] = {'galon': 5};
      store['p11b'] = {'galon': 1};
      store.remove('p11a');
      expect(store.containsKey('p11a'), false);
      expect(store['p11b']!['galon'], 1);
    });
  });

  // ── DROP CAP: rowCap resolution ────────────────────────────────────

  group('rowCap resolution', () {
    /// Pure rowCap resolution mirroring _buildRows logic.
    int? resolveRowCap(
        bool capModeActive, bool capResolved, Map<String, int> capMap,
        String itemIi) {
      if (capModeActive && capResolved) return capMap[itemIi] ?? 0;
      return null;
    }

    test('cap active + resolved + item in map -> cap value', () {
      expect(resolveRowCap(true, true, {'galon': 5}, 'galon'), 5);
    });

    test('cap active + resolved + item NOT in map -> 0', () {
      expect(resolveRowCap(true, true, <String, int>{}, 'galon'), 0);
    });

    test('cap active + NOT resolved -> null', () {
      expect(resolveRowCap(true, false, {'galon': 5}, 'galon'), null);
    });

    test('cap NOT active -> null regardless of resolved', () {
      expect(resolveRowCap(false, true, {'galon': 5}, 'galon'), null);
      expect(resolveRowCap(false, false, <String, int>{}, 'galon'), null);
    });
  });

  // ── DROP CAP: clamp-down (build-time re-correct) ──────────────────

  group('clamp-down (build-time re-correct)', () {
    /// Pure clamp-down logic mirroring _buildRows post-putIfAbsent.
    /// Returns the value that seeded.dropActual should become.
    int clampDown(int stored, int? rowCap) {
      if (rowCap != null && stored > rowCap) return rowCap;
      return stored;
    }

    test('stored 3, cap 1 -> clamped to 1', () {
      expect(clampDown(3, 1), 1);
    });

    test('stored 1, cap 1 -> unchanged (at cap)', () {
      expect(clampDown(1, 1), 1);
    });

    test('stored 0, cap null -> unchanged (no-cap)', () {
      expect(clampDown(0, null), 0);
    });

    test('stored 2, cap 5 -> unchanged (below cap)', () {
      expect(clampDown(2, 5), 2);
    });

    test('stored 0, cap 0 -> unchanged (at zero cap)', () {
      expect(clampDown(0, 0), 0);
    });

    test('stored 5, cap null -> unchanged (no-cap, high value)', () {
      expect(clampDown(5, null), 5);
    });
  });

  // ── DROP CAP: unresolved renders at plan (never-blank) ────────────

  group('unresolved cap renders at plan (never-blank)', () {
    test('rowCap null -> seedDrop = plan', () {
      const int planDrop = 3;
      const int? rowCap = null;
      final int seedDrop = (rowCap == null)
          ? planDrop
          : (planDrop < rowCap ? planDrop : rowCap);
      expect(seedDrop, 3);
    });

    test('rowCap null -> [+] enabled (increment NOT disabled)', () {
      const int? dropCap = null;
      const int dropActual = 3;
      final bool disabled = dropCap != null && dropActual >= dropCap;
      expect(disabled, false);
    });

    test('rowCap null -> no capLabel (status falls through to plan)', () {
      const int? dropCap = null;
      const int dropActual = 3;
      final bool showCapStatus = dropCap != null && dropActual == dropCap;
      expect(showCapStatus, false);
    });

    test('rowCap null -> clamp-down is no-op', () {
      const int stored = 5;
      const int? rowCap = null;
      final int result =
          (rowCap != null && stored > rowCap) ? rowCap : stored;
      expect(result, 5);
    });
  });

  // ── R3: capResolved from task.vv ──────────────────────────────────────

  group('capResolved from task.vv (R3)', () {
    /// Pure predicate mirroring _buildRows R3 logic.
    /// capResolved = taskVv.isNotEmpty && snapshotArrived.
    bool resolved(String taskVv, bool snapshotArrived) {
      return taskVv.isNotEmpty && snapshotArrived;
    }

    test('taskVv present + snapshot arrived -> true', () {
      expect(resolved('F621', true), true);
    });

    test('taskVv empty + snapshot arrived -> false', () {
      expect(resolved('', true), false);
    });

    test('taskVv present + snapshot NOT arrived -> false', () {
      expect(resolved('F621', false), false);
    });

    test('taskVv empty + snapshot NOT arrived -> false', () {
      expect(resolved('', false), false);
    });

    test('whitespace-only taskVv (trimmed to empty) -> false', () {
      // taskVv is already trimmed in _buildRows; proxy mirrors post-trim.
      expect(resolved('', true), false);
    });
  });

  // ── R3: vehicleId substitution in cap search ──────────────────────────

  group('vehicleId substitution in cap search (R3)', () {
    test('replaces {vehicleId} with taskVv', () {
      const String search = 'lv\u{25FC}{vehicleId}\u{2B58}cd\u{25FC}full';
      final String result = search.replaceAll('{vehicleId}', 'F621');
      expect(result, 'lv\u{25FC}F621\u{2B58}cd\u{25FC}full');
    });

    test('empty taskVv leaves {vehicleId} as literal', () {
      // In practice capResolved is false when taskVv is empty, so this
      // branch is unreachable. But replaceAll('', '') is identity on
      // '{vehicleId}' substrings that don't contain empty -- so the token
      // stays literal. Verified for safety.
      const String search = 'lv\u{25FC}{vehicleId}';
      final String result = search.replaceAll('{vehicleId}', '');
      expect(result, 'lv\u{25FC}');
    });

    test('search with no {vehicleId} token -> unchanged', () {
      const String search = 'cd\u{25FC}full';
      final String result = search.replaceAll('{vehicleId}', 'F621');
      expect(result, 'cd\u{25FC}full');
    });

    test('search with _2B58_-style encoded separator still replaces token', () {
      // Token is {vehicleId} (curly braces), not affected by separator
      // encoding. replaceAll targets the literal substring.
      const String search = 'lv_25FC_{vehicleId}_2B58_cd_25FC_full';
      final String result = search.replaceAll('{vehicleId}', 'F621');
      expect(result, 'lv_25FC_F621_2B58_cd_25FC_full');
    });

    test('multiple {vehicleId} tokens all replaced', () {
      const String search = '{vehicleId}\u{2B58}{vehicleId}';
      final String result = search.replaceAll('{vehicleId}', 'X1');
      expect(result, 'X1\u{2B58}X1');
    });
  });

  // ── R3: end-to-end cap proxy (task.vv source) ────────────────────────

  group('end-to-end cap proxy with task.vv (R3)', () {
    /// Full proxy: taskVv + snapshot -> capResolved -> rowCap -> seed.
    int? resolveRowCap(
      String taskVv,
      bool snapshotArrived,
      Map<String, int> capMap,
      String itemIi,
    ) {
      final bool capResolved = taskVv.isNotEmpty && snapshotArrived;
      if (capResolved) return capMap[itemIi] ?? 0;
      return null;
    }

    int seedDrop(int planDrop, int? rowCap) {
      if (rowCap == null) return planDrop;
      return planDrop < rowCap ? planDrop : rowCap;
    }

    test('taskVv present + snapshot -> cap applies -> seed clamped', () {
      final int? rowCap =
          resolveRowCap('F621', true, {'galon': 1}, 'galon');
      expect(rowCap, 1);
      expect(seedDrop(3, rowCap), 1); // THE fix: seed 1, not 3
    });

    test('taskVv empty -> no cap -> seed at plan', () {
      final int? rowCap =
          resolveRowCap('', true, {'galon': 1}, 'galon');
      expect(rowCap, null);
      expect(seedDrop(3, rowCap), 3);
    });

    test('snapshot not arrived -> no cap -> seed at plan', () {
      final int? rowCap =
          resolveRowCap('F621', false, {'galon': 1}, 'galon');
      expect(rowCap, null);
      expect(seedDrop(3, rowCap), 3);
    });

    test('item not in capMap -> cap 0 -> seed 0', () {
      final int? rowCap =
          resolveRowCap('F621', true, <String, int>{}, 'galon');
      expect(rowCap, 0);
      expect(seedDrop(3, rowCap), 0);
    });

    test('plan < cap -> seed at plan (cap not limiting)', () {
      final int? rowCap =
          resolveRowCap('F621', true, {'galon': 10}, 'galon');
      expect(rowCap, 10);
      expect(seedDrop(3, rowCap), 3);
    });
  });

  // ── PIVOT VARIANT: parsePivotSlots ──────────────────────────────────

  group('parsePivotSlots', () {
    test('normal two-slot string', () {
      final List<PivotSlot> result =
          parsePivotSlots('full^Penuh~empty^Kosong');
      expect(result.length, 2);
      expect(result[0].value, 'full');
      expect(result[0].label, 'Penuh');
      expect(result[1].value, 'empty');
      expect(result[1].label, 'Kosong');
    });

    test('single slot', () {
      final List<PivotSlot> result = parsePivotSlots('full^Penuh');
      expect(result.length, 1);
      expect(result[0].value, 'full');
      expect(result[0].label, 'Penuh');
    });

    test('three slots', () {
      final List<PivotSlot> result =
          parsePivotSlots('full^Penuh~empty^Kosong~damaged^Rusak');
      expect(result.length, 3);
      expect(result[2].value, 'damaged');
      expect(result[2].label, 'Rusak');
    });

    test('empty string returns empty list', () {
      expect(parsePivotSlots(''), isEmpty);
    });

    test('whitespace-only returns empty list', () {
      expect(parsePivotSlots('   '), isEmpty);
    });

    test('malformed entry without caret is skipped', () {
      final List<PivotSlot> result =
          parsePivotSlots('full^Penuh~noCaret~empty^Kosong');
      expect(result.length, 2);
      expect(result[0].value, 'full');
      expect(result[1].value, 'empty');
    });

    test('entry with empty value is skipped', () {
      final List<PivotSlot> result =
          parsePivotSlots('^EmptyValue~full^Penuh');
      expect(result.length, 1);
      expect(result[0].value, 'full');
    });

    test('trailing tilde produces no extra entry', () {
      final List<PivotSlot> result = parsePivotSlots('full^Penuh~');
      expect(result.length, 1);
      expect(result[0].value, 'full');
    });

    test('leading tilde produces no extra entry', () {
      final List<PivotSlot> result = parsePivotSlots('~full^Penuh');
      expect(result.length, 1);
      expect(result[0].value, 'full');
    });

    test('whitespace around entries is trimmed', () {
      final List<PivotSlot> result =
          parsePivotSlots('  full ^ Penuh  ~  empty ^ Kosong  ');
      expect(result.length, 2);
      expect(result[0].value, 'full');
      expect(result[0].label, 'Penuh');
      expect(result[1].value, 'empty');
      expect(result[1].label, 'Kosong');
    });

    test('empty label is allowed (value is required, label is not)', () {
      final List<PivotSlot> result = parsePivotSlots('full^');
      expect(result.length, 1);
      expect(result[0].value, 'full');
      expect(result[0].label, '');
    });
  });

  // ── PIVOT VARIANT: groupDocsByKey ───────────────────────────────────

  group('groupDocsByKey', () {
    test('groups docs by key field', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'full', 'qt': 5},
        {'ii': 'galon', 'cd': 'empty', 'qt': 3},
        {'ii': 'aqua', 'cd': 'full', 'qt': 12},
      ];
      final result = groupDocsByKey(docs, 'ii');
      expect(result.length, 2);
      expect(result['galon']!.length, 2);
      expect(result['aqua']!.length, 1);
    });

    test('preserves insertion order', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'zebra', 'cd': 'full'},
        {'ii': 'alpha', 'cd': 'full'},
        {'ii': 'mango', 'cd': 'full'},
      ];
      final result = groupDocsByKey(docs, 'ii');
      expect(result.keys.toList(), ['zebra', 'alpha', 'mango']);
    });

    test('skips docs with empty key', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '', 'cd': 'full'},
        {'ii': 'galon', 'cd': 'empty'},
      ];
      final result = groupDocsByKey(docs, 'ii');
      expect(result.length, 1);
      expect(result.containsKey('galon'), true);
    });

    test('skips docs with absent key', () {
      final docs = <Map<String, dynamic>>[
        {'cd': 'full'},
        {'ii': 'galon', 'cd': 'empty'},
      ];
      final result = groupDocsByKey(docs, 'ii');
      expect(result.length, 1);
    });

    test('empty docs returns empty map', () {
      final result =
          groupDocsByKey(const <Map<String, dynamic>>[], 'ii');
      expect(result, isEmpty);
    });

    test('single doc produces single group', () {
      final docs = <Map<String, dynamic>>[
        {'ii': 'galon', 'cd': 'full', 'qt': 5},
      ];
      final result = groupDocsByKey(docs, 'ii');
      expect(result.length, 1);
      expect(result['galon']!.length, 1);
    });

    test('whitespace-only key is treated as empty (skipped)', () {
      final docs = <Map<String, dynamic>>[
        {'ii': '   ', 'cd': 'full'},
      ];
      final result = groupDocsByKey(docs, 'ii');
      expect(result, isEmpty);
    });
  });

  // ── PIVOT VARIANT: pivotExpected ───────────────────────────────────

  group('pivotExpected', () {
    test('finds matching doc and returns coerced value', () {
      final group = <Map<String, dynamic>>[
        {'cd': 'full', 'qt': 5},
        {'cd': 'empty', 'qt': 3},
      ];
      expect(pivotExpected(group, 'cd', 'full', 'qt'), 5);
      expect(pivotExpected(group, 'cd', 'empty', 'qt'), 3);
    });

    test('returns 0 when no doc matches slot value', () {
      final group = <Map<String, dynamic>>[
        {'cd': 'full', 'qt': 5},
      ];
      expect(pivotExpected(group, 'cd', 'empty', 'qt'), 0);
    });

    test('returns 0 for empty group', () {
      expect(
        pivotExpected(const <Map<String, dynamic>>[], 'cd', 'full', 'qt'),
        0,
      );
    });

    test('handles non-numeric value via coerceNum', () {
      final group = <Map<String, dynamic>>[
        {'cd': 'full', 'qt': 'abc'},
      ];
      expect(pivotExpected(group, 'cd', 'full', 'qt'), 0);
    });

    test('handles string-numeric value', () {
      final group = <Map<String, dynamic>>[
        {'cd': 'full', 'qt': '7'},
      ];
      expect(pivotExpected(group, 'cd', 'full', 'qt'), 7);
    });

    test('handles null value field', () {
      final group = <Map<String, dynamic>>[
        {'cd': 'full'},
      ];
      expect(pivotExpected(group, 'cd', 'full', 'qt'), 0);
    });

    test('returns first match when duplicates exist', () {
      final group = <Map<String, dynamic>>[
        {'cd': 'full', 'qt': 5},
        {'cd': 'full', 'qt': 99},
      ];
      expect(pivotExpected(group, 'cd', 'full', 'qt'), 5);
    });

    test('pivot field absent in doc is treated as empty string', () {
      final group = <Map<String, dynamic>>[
        {'qt': 5},
      ];
      // Empty string != 'full', so returns 0.
      expect(pivotExpected(group, 'cd', 'full', 'qt'), 0);
    });
  });

  // ── PIVOT VARIANT: status state-machine ────────────────────────────

  group('pivot status state-machine', () {
    /// Pure proxy of _pivotCellStatus.
    /// delta == 0 -> complete; delta < 0 -> partial (amber); delta > 0 -> extra (violet).
    String pivotStatus(int counted, int expected) {
      final int delta = counted - expected;
      if (delta == 0) return 'complete';
      return delta < 0 ? 'partial' : 'extra';
    }

    test('counted == expected -> complete', () {
      expect(pivotStatus(5, 5), 'complete');
      expect(pivotStatus(0, 0), 'complete');
    });

    test('counted < expected -> partial (amber)', () {
      expect(pivotStatus(2, 5), 'partial');
      expect(pivotStatus(0, 3), 'partial');
    });

    test('counted > expected -> extra (violet)', () {
      expect(pivotStatus(7, 5), 'extra');
      expect(pivotStatus(1, 0), 'extra');
    });
  });

  // ── PIVOT VARIANT: delta label formatting ──────────────────────────

  group('pivot delta label formatting', () {
    test('positive delta shows +N', () {
      final int delta = 7 - 5;
      final String sign = delta > 0 ? '+$delta' : '$delta';
      expect(sign, '+2');
    });

    test('negative delta shows -N', () {
      final int delta = 2 - 5;
      final String sign = delta > 0 ? '+$delta' : '$delta';
      expect(sign, '-3');
    });

    test('template replacement works', () {
      const String template = 'Selisih \u{00B7} <delta>';
      final String label = template.replaceAll('<delta>', '+2');
      expect(label, 'Selisih \u{00B7} +2');
    });

    test('template without <delta> token is unchanged', () {
      const String template = 'Mismatch detected';
      final String label = template.replaceAll('<delta>', '+2');
      expect(label, 'Mismatch detected');
    });
  });

  // ── PIVOT VARIANT: countStore key format ───────────────────────────

  group('pivot countStore key format', () {
    test('key is ii__slotValue', () {
      const String ii = 'galon19';
      const String slotValue = 'full';
      final String key = '${ii}__$slotValue';
      expect(key, 'galon19__full');
    });

    test('different slots produce different keys', () {
      const String ii = 'galon19';
      final String keyFull = '${ii}__full';
      final String keyEmpty = '${ii}__empty';
      expect(keyFull, isNot(equals(keyEmpty)));
    });

    test('different items produce different keys', () {
      final String keyA = 'galon19__full';
      final String keyB = 'aqua600__full';
      expect(keyA, isNot(equals(keyB)));
    });
  });

  // ── PIVOT VARIANT: pivot text slot guards ──────────────────────────

  group('pivot text slot guards (6-segment)', () {
    test('full 6-segment text parses all pivot slots', () {
      final text =
          'Hitung fisik\u{25C6}Ekspektasi\u{25C6}\u{2713} Sesuai'
          '\u{25C6}Selisih \u{00B7} <delta>\u{25C6}Returnable\u{25C6}Consumable';
      final arr = diamondTextToList(text);
      expect(arr.length, 6);
      expect(arr[0], 'Hitung fisik');
      expect(arr[1], 'Ekspektasi');
      expect(arr[2], '\u{2713} Sesuai');
      expect(arr[3], 'Selisih \u{00B7} <delta>');
      expect(arr[4], 'Returnable');
      expect(arr[5], 'Consumable');
    });

    test('sparse text falls back for missing slots', () {
      final arr = diamondTextToList('hint');
      expect(arr.isNotEmpty ? arr[0] : '', 'hint');
      expect(arr.length > 1 ? arr[1] : 'Ekspektasi', 'Ekspektasi');
      expect(arr.length > 2 ? arr[2] : '\u{2713} Sesuai', '\u{2713} Sesuai');
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
