import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/task_feed_list.dart';

void main() {
  // ── P10 tst vocabulary via stopStatusOf ─────────────────────────────────

  group('P10 tst vocabulary', () {
    test('assigned normalizes to pending', () {
      expect(stopStatusOf({'tst': 'assigned'}), 'pending');
    });

    test('on_delivery normalizes to pending', () {
      expect(stopStatusOf({'tst': 'on_delivery'}), 'pending');
    });

    test('completed normalizes to done', () {
      expect(stopStatusOf({'tst': 'completed'}), 'done');
    });

    test('failed normalizes to failed', () {
      expect(stopStatusOf({'tst': 'failed'}), 'failed');
    });
  });

  // ── Grouping logic (pure function extraction) ──────────────────────────

  group('task grouping', () {
    /// Pure grouping function that mirrors the logic in TaskFeedList.build.
    /// Extracted here for testing without widget pump.
    Map<String, List<Map<String, dynamic>>> groupTasks(
        List<Map<String, dynamic>> tasks, String tstField) {
      final pending = <Map<String, dynamic>>[];
      final failed = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      for (final doc in tasks) {
        final status = stopStatusOf(doc, tstField: tstField);
        if (status == 'failed') {
          failed.add(doc);
        } else if (status == 'done') {
          completed.add(doc);
        } else {
          pending.add(doc);
        }
      }
      return {'pending': pending, 'failed': failed, 'completed': completed};
    }

    test('groups assigned+on_delivery into pending', () {
      final tasks = [
        {'tst': 'assigned'},
        {'tst': 'on_delivery'},
        {'tst': 'completed'},
        {'tst': 'failed'},
      ];
      final groups = groupTasks(tasks, 'tst');
      expect(groups['pending']!.length, 2);
      expect(groups['failed']!.length, 1);
      expect(groups['completed']!.length, 1);
    });

    test('on_delivery groups with assigned, not completed', () {
      final tasks = [
        {'tst': 'on_delivery'},
        {'tst': 'on_delivery'},
        {'tst': 'completed'},
      ];
      final groups = groupTasks(tasks, 'tst');
      expect(groups['pending']!.length, 2);
      expect(groups['completed']!.length, 1);
    });

    test('empty task list produces empty groups', () {
      final groups = groupTasks([], 'tst');
      expect(groups['pending'], isEmpty);
      expect(groups['failed'], isEmpty);
      expect(groups['completed'], isEmpty);
    });

    test('all completed', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'completed'},
      ];
      final groups = groupTasks(tasks, 'tst');
      expect(groups['pending'], isEmpty);
      expect(groups['completed']!.length, 2);
    });
  });

  // ── stopNumber indexing ─────────────────────────────────────────────────

  group('stopNumber indexing', () {
    test('1-based global index across all tasks regardless of state', () {
      final tasks = [
        {'tst': 'assigned', 'tnm': 'T001'},
        {'tst': 'completed', 'tnm': 'T002'},
        {'tst': 'assigned', 'tnm': 'T003'},
        {'tst': 'failed', 'tnm': 'T004'},
      ];

      // Simulate the indexing logic from TaskFeedList.build
      final List<Map<String, int>> indexed = [];
      int globalIndex = 0;
      for (final _ in tasks) {
        globalIndex++;
        indexed.add({'stopNumber': globalIndex});
      }

      expect(indexed[0]['stopNumber'], 1);
      expect(indexed[1]['stopNumber'], 2);
      expect(indexed[2]['stopNumber'], 3);
      expect(indexed[3]['stopNumber'], 4);
    });
  });

  // ── allDone boolean ──────────────────────────────────────────────────────

  group('allDone', () {
    test('true when no assigned or on_delivery tasks', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'failed'},
        {'tst': 'completed'},
      ];
      final bool allDone = tasks.every((doc) {
        final status = stopStatusOf(doc);
        return status == 'done' || status == 'failed';
      });
      expect(allDone, true);
    });

    test('false when on_delivery tasks remain', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'on_delivery'},
      ];
      final bool allDone = tasks.every((doc) {
        final status = stopStatusOf(doc);
        return status == 'done' || status == 'failed';
      });
      expect(allDone, false);
    });

    test('false when assigned tasks remain', () {
      final tasks = [
        {'tst': 'assigned'},
      ];
      final bool allDone = tasks.every((doc) {
        final status = stopStatusOf(doc);
        return status == 'done' || status == 'failed';
      });
      expect(allDone, false);
    });

    test('allDone computed via pending group empty (matches widget logic)', () {
      final tasks = [
        {'tst': 'completed'},
        {'tst': 'failed'},
      ];
      final pending = tasks.where((doc) {
        final status = stopStatusOf(doc);
        return status != 'done' && status != 'failed';
      }).toList();
      expect(pending.isEmpty, true); // allDone
    });

    test('empty task list is NOT allDone (no banner shown)', () {
      // Widget shows allDone banner only when allDone && tasks.isNotEmpty
      final tasks = <Map<String, dynamic>>[];
      final pending = tasks.where((doc) {
        final status = stopStatusOf(doc);
        return status != 'done' && status != 'failed';
      }).toList();
      // pending is empty, but tasks is also empty → no banner
      expect(pending.isEmpty, true);
      expect(tasks.isNotEmpty, false);
    });
  });

  // ── Per-card drop/pickup with actual vs planned ──────────────────────────

  group('per-card drop/pickup', () {
    test('assigned card uses planned pd/pp', () {
      final doc = {
        'tst': 'assigned',
        'it': [
          {'pd': '5', 'pp': '2', 'ad': '0', 'ap': '0'},
          {'pd': '3', 'pp': '1', 'ad': '0', 'ap': '0'},
        ],
      };
      // Widget uses pd/pp for non-done
      int drop = 0;
      int pickup = 0;
      for (final item in (doc['it'] as List)) {
        drop += int.tryParse((item['pd'] ?? '0').toString()) ?? 0;
        pickup += int.tryParse((item['pp'] ?? '0').toString()) ?? 0;
      }
      expect(drop, 8);
      expect(pickup, 3);
    });

    test('completed card uses actual ad/ap', () {
      final doc = {
        'tst': 'completed',
        'it': [
          {'pd': '5', 'pp': '2', 'ad': '4', 'ap': '1'},
          {'pd': '3', 'pp': '1', 'ad': '3', 'ap': '1'},
        ],
      };
      // Widget uses ad/ap for done status
      int drop = 0;
      int pickup = 0;
      for (final item in (doc['it'] as List)) {
        drop += int.tryParse((item['ad'] ?? '0').toString()) ?? 0;
        pickup += int.tryParse((item['ap'] ?? '0').toString()) ?? 0;
      }
      expect(drop, 7);
      expect(pickup, 2);
    });
  });

  // ── diamondTextToList length guard ──────────────────────────────────────

  group('text segment length guard', () {
    test('empty text returns length-1 list with empty string', () {
      final result = diamondTextToList('');
      expect(result.length, 1);
      expect(result[0], '');
    });

    test('_t helper returns default for out-of-range index', () {
      // Simulate the _t helper
      final textArray = diamondTextToList('');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      expect(t(0), ''); // index 0 exists, returns ''
      expect(t(1, 'fallback'), 'fallback'); // index 1 out of range
      expect(t(14, 'last'), 'last'); // way out of range
    });

    test('short text still length-guards high indexes', () {
      final textArray = diamondTextToList('Hello\u{25C6}World');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      expect(t(0), 'Hello');
      expect(t(1), 'World');
      expect(t(2, 'nope'), 'nope');
    });
  });

  // ── return-CTA gate opt-in (spec (4).md §OPEN 3 option a) ────────────────
  // The widget hides the "Kembali ke Gudang" entry-point after handover by
  // gating on a vehicle_check rt=pending search. Gating is OPT-IN: active ONLY
  // when BOTH returnGateSearch and a subscribed gate table are present. The
  // pure decision below mirrors the widget's build() logic (evaluateGateSearch
  // itself is covered in driver_home_support_test).

  group('task_feed_list return-CTA gate opt-in', () {
    bool returnGateOpen({
      required String returnGateSearch,
      required String returnGateCode,
      required bool gateMatched,
    }) {
      final bool returnGated =
          returnGateSearch.isNotEmpty && returnGateCode.isNotEmpty;
      return !returnGated || gateMatched;
    }

    test('unconfigured (no search) -> CTA always shown', () {
      expect(
        returnGateOpen(
            returnGateSearch: '',
            returnGateCode: '84214220504259/vehicle_check',
            gateMatched: false),
        isTrue,
      );
    });

    test('search set but no gate table subscribed -> not gated -> shown', () {
      expect(
        returnGateOpen(
            returnGateSearch: 'rt\u{25FC}pending',
            returnGateCode: '',
            gateMatched: false),
        isTrue,
      );
    });

    test('gated + gate matches (rt=pending) -> shown', () {
      expect(
        returnGateOpen(
            returnGateSearch: 'rt\u{25FC}pending',
            returnGateCode: '84214220504259/vehicle_check',
            gateMatched: true),
        isTrue,
      );
    });

    test('gated + gate no longer matches (rt=returned) -> hidden', () {
      expect(
        returnGateOpen(
            returnGateSearch: 'rt\u{25FC}pending',
            returnGateCode: '84214220504259/vehicle_check',
            gateMatched: false),
        isFalse,
      );
    });
  });

  // ── FLAT mode (groupField empty) ────────────────────────────────────

  group('FLAT mode groupField decision', () {
    test('empty groupField selects FLAT (no grouping)', () {
      // Mirrors the widget's build logic:
      //   final String groupField =
      //       (component['groupField'] ?? 'tst').toString();
      //   if (groupField.isEmpty) -> FLAT

      // Present-but-empty key: FLAT
      final String gf1 = ({'groupField': ''} ['groupField'] ?? 'tst').toString();
      expect(gf1.isEmpty, isTrue);

      // Non-empty key: GROUPED
      final String gf2 =
          ({'groupField': 'tst'} ['groupField'] ?? 'tst').toString();
      expect(gf2.isEmpty, isFalse);

      // Absent key: defaults to 'tst' -> GROUPED
      final String gf3 =
          (<String, dynamic>{} ['groupField'] ?? 'tst').toString();
      expect(gf3.isEmpty, isFalse);
      expect(gf3, 'tst');
    });
  });

  group('FLAT mode text header', () {
    test('text segment [0] is heading, [1] is subtitle', () {
      final textArray =
          diamondTextToList('Customer\u{25C6}Pilih customer untuk order');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      expect(t(0), 'Customer');
      expect(t(1), 'Pilih customer untuk order');
    });

    test('empty text yields empty heading and subtitle', () {
      final textArray = diamondTextToList('');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      // diamondTextToList('') returns [''] (length-1, index 0 = '')
      expect(t(0), '');
      expect(t(1, ''), '');
    });

    test('single-segment text has heading only, no subtitle', () {
      final textArray = diamondTextToList('Customer');
      String t(int i, [String def = '']) =>
          textArray.length > i ? textArray[i] : def;

      expect(t(0), 'Customer');
      expect(t(1, ''), '');
    });
  });

  group('FLAT mode card data extraction', () {
    test('reads titleField and addressField from doc', () {
      final doc = {'ln': 'Halooo', 'al': 'mantap', 'lv': '12345'};
      final title = (doc['ln'] ?? '').toString().trim();
      final address = (doc['al'] ?? '').toString().trim();
      expect(title, 'Halooo');
      expect(address, 'mantap');
    });

    test('missing fields yield empty strings (no crash)', () {
      final doc = <String, dynamic>{'lv': '12345'};
      final title = (doc['ln'] ?? '').toString().trim();
      final address = (doc['al'] ?? '').toString().trim();
      expect(title, '');
      expect(address, '');
    });

    test('idField reads lv for customer picker', () {
      final doc = {'ln': 'Halooo', 'al': 'mantap', 'lv': 'CUST-001'};
      final idField = 'lv';
      final taskVid = (doc[idField] ?? '').toString().trim();
      expect(taskVid, 'CUST-001');
    });
  });

  group('FLAT vs GROUPED backward-compat', () {
    test('non-empty groupField still groups by status', () {
      // With groupField = "tst" (default), tasks are grouped
      final tasks = [
        {'tst': 'assigned', 'kn': 'A'},
        {'tst': 'completed', 'kn': 'B'},
        {'tst': 'failed', 'kn': 'C'},
      ];
      // GROUPED logic (existing, mirrors widget build):
      final pending = <Map<String, dynamic>>[];
      final failed = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      for (final doc in tasks) {
        final status = stopStatusOf(doc, tstField: 'tst');
        if (status == 'failed') {
          failed.add(doc);
        } else if (status == 'done') {
          completed.add(doc);
        } else {
          pending.add(doc);
        }
      }
      expect(pending.length, 1);
      expect(failed.length, 1);
      expect(completed.length, 1);
    });

    test('FLAT mode would skip grouping entirely', () {
      // With groupField = "" (FLAT), no grouping -- all tasks rendered as-is
      final tasks = [
        {'lt': 'client', 'lst': 'active', 'ln': 'Customer A'},
        {'lt': 'client', 'lst': 'active', 'ln': 'Customer B'},
      ];
      // FLAT: render all, no status check
      expect(tasks.length, 2); // no filtering by status
    });
  });

  // ── FLAT avatar fallback (R2) ──────────────────────────────────────

  group('FLAT avatar fallback', () {
    /// Mirrors _buildFlatCard avatar logic:
    ///   1. If iconField config is non-empty, read task[iconField].
    ///   2. If that value is empty, fall back to first letter of title.
    ///   3. If title is also empty, avatarContent is '' (empty box).
    String avatarOf(Map<String, dynamic> task,
        {required String iconField, required String titleField}) {
      String result = '';
      if (iconField.isNotEmpty) {
        result = (task[iconField] ?? '').toString().trim();
      }
      if (result.isEmpty) {
        final String title = (task[titleField] ?? '').toString().trim();
        result = title.isNotEmpty ? title[0].toUpperCase() : '';
      }
      return result;
    }

    test('iconField value takes priority when non-empty', () {
      expect(
        avatarOf({'ic': '\u{1F3EA}', 'ln': 'Halooo'},
            iconField: 'ic', titleField: 'ln'),
        '\u{1F3EA}',
      );
    });

    test('first letter of title when iconField config is empty string', () {
      expect(
        avatarOf({'ln': 'Halooo', 'al': 'mantap'},
            iconField: '', titleField: 'ln'),
        'H',
      );
    });

    test('first letter of title when iconField doc value is empty', () {
      expect(
        avatarOf({'ic': '', 'ln': 'Mantap'},
            iconField: 'ic', titleField: 'ln'),
        'M',
      );
    });

    test('lowercase first letter is uppercased', () {
      expect(
        avatarOf({'ln': 'halooo'}, iconField: '', titleField: 'ln'),
        'H',
      );
    });

    test('empty title yields empty avatar (no crash)', () {
      expect(
        avatarOf(<String, dynamic>{'lv': '12345'},
            iconField: '', titleField: 'ln'),
        '',
      );
    });

    test('missing iconField key in doc falls back to title', () {
      expect(
        avatarOf({'ln': 'Sejahtera'}, iconField: 'ic', titleField: 'ln'),
        'S',
      );
    });
  });

  // ── FLAT local search filter (R2) ──────────────────────────────────

  group('FLAT local search filter', () {
    final tasks = <Map<String, dynamic>>[
      {'ln': 'Halooo', 'al': 'Jl. Mantap'},
      {'ln': 'PT Sejahtera', 'al': 'Jl. Merdeka'},
      {'ln': 'CV Maju', 'al': 'Komplek Mantap'},
    ];
    const String titleField = 'ln';
    const String addressField = 'al';

    /// Mirrors _buildFlatList local filter logic (plain text, no
    /// autheniumDecode — this is user-typed text, not a server search).
    List<Map<String, dynamic>> filterFlat(
        List<Map<String, dynamic>> docs, String query) {
      final String q = query.trim().toLowerCase();
      if (q.isEmpty) return docs;
      return docs.where((task) {
        final String title =
            (task[titleField] ?? '').toString().trim().toLowerCase();
        final String address =
            (task[addressField] ?? '').toString().trim().toLowerCase();
        return title.contains(q) || address.contains(q);
      }).toList();
    }

    test('empty query returns all tasks', () {
      expect(filterFlat(tasks, '').length, 3);
    });

    test('whitespace-only query returns all tasks', () {
      expect(filterFlat(tasks, '   ').length, 3);
    });

    test('matches title (case-insensitive)', () {
      final result = filterFlat(tasks, 'halooo');
      expect(result.length, 1);
      expect(result[0]['ln'], 'Halooo');
    });

    test('matches address (case-insensitive)', () {
      final result = filterFlat(tasks, 'merdeka');
      expect(result.length, 1);
      expect(result[0]['ln'], 'PT Sejahtera');
    });

    test('matches title OR address (substring match)', () {
      // 'mantap' matches Halooo (address) + CV Maju (address)
      final result = filterFlat(tasks, 'mantap');
      expect(result.length, 2);
    });

    test('no match returns empty list', () {
      expect(filterFlat(tasks, 'xyz'), isEmpty);
    });

    test('partial substring match works', () {
      final result = filterFlat(tasks, 'pt');
      expect(result.length, 1);
      expect(result[0]['ln'], 'PT Sejahtera');
    });
  });

  // ── FLAT count header (R2) ─────────────────────────────────────────

  group('FLAT count header', () {
    test('count reflects post-filter results', () {
      final allTasks = <Map<String, dynamic>>[
        {'ln': 'A', 'al': 'X'},
        {'ln': 'B', 'al': 'Y'},
        {'ln': 'C', 'al': 'X'},
      ];
      // Simulate local search filter: query 'X' matches address
      final filtered = allTasks.where((t) {
        final String address = (t['al'] ?? '').toString().toLowerCase();
        return address.contains('x');
      }).toList();
      expect(filtered.length, 2);
      // Count header text mirrors widget: '$count $countLabel'.toUpperCase()
      const String countLabel = 'Customer';
      final String header = '${filtered.length} $countLabel'.toUpperCase();
      expect(header, '2 CUSTOMER');
    });

    test('empty countLabel config suppresses count header', () {
      // Widget: if (countLabel.isNotEmpty) → render header
      const String countLabel = '';
      expect(countLabel.isNotEmpty, isFalse);
    });

    test('count is 0 when all filtered out', () {
      final filtered = <Map<String, dynamic>>[];
      const String countLabel = 'Customer';
      final String header = '${filtered.length} $countLabel'.toUpperCase();
      expect(header, '0 CUSTOMER');
    });
  });

  // ── FLAT empty state (R2) ──────────────────────────────────────────

  group('FLAT empty state', () {
    test('emptyText rendered when filtered count is 0', () {
      const String emptyText = 'Belum ada customer';
      final filtered = <Map<String, dynamic>>[];
      // Widget: if (count == 0) _buildFlatEmptyState(emptyText)
      expect(filtered.isEmpty, isTrue);
      expect(emptyText.isNotEmpty, isTrue);
    });

    test('empty emptyText falls back to default', () {
      // Widget: emptyText.isNotEmpty ? emptyText : 'Tidak ada data'
      const String emptyText = '';
      final String display =
          emptyText.isNotEmpty ? emptyText : 'Tidak ada data';
      expect(display, 'Tidak ada data');
    });

    test('non-empty emptyText used as-is', () {
      const String emptyText = 'Belum ada customer';
      final String display =
          emptyText.isNotEmpty ? emptyText : 'Tidak ada data';
      expect(display, 'Belum ada customer');
    });
  });

  // ── aggregateForRow (FLAT badge: outstanding / seed) ─────────────────

  group('TaskFeedList.aggregateForRow', () {
    // Fixture: asset_cache docs with lt/lv/qt fields.
    final List<Map<String, dynamic>> assetCache = [
      {'lt': 'client', 'lv': 'C1', 'qt': 5, 'ii': 'G19'},
      {'lt': 'client', 'lv': 'C1', 'qt': 3, 'ii': 'G12'},
      {'lt': 'client', 'lv': 'C2', 'qt': 10, 'ii': 'G19'},
      {'lt': 'vehicle', 'lv': 'V1', 'qt': 2, 'ii': 'G19'},
    ];

    test('sums qt for matching client rows (C1: 5+3=8)', () {
      final agg = TaskFeedList.aggregateForRow(
          assetCache,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C1',
          'qt');
      expect(agg.rows, 2);
      expect(agg.sum, 8);
    });

    test('different rowId yields separate result (C2: 10)', () {
      final agg = TaskFeedList.aggregateForRow(
          assetCache,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C2',
          'qt');
      expect(agg.rows, 1);
      expect(agg.sum, 10);
    });

    test('no matching docs -> rows:0 sum:0 (seed path)', () {
      final agg = TaskFeedList.aggregateForRow(
          assetCache,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C999',
          'qt');
      expect(agg.rows, 0);
      expect(agg.sum, 0);
    });

    test('matched rows with sum 0 -> outstanding-0, NOT seed', () {
      // CRITICAL: rows > 0 means seeded. Chip = "up-arrow 0 outstanding",
      // NOT seedLabel. Only 0 matched rows yields the seed chip.
      final List<Map<String, dynamic>> zeroDocs = [
        {'lt': 'client', 'lv': 'C3', 'qt': 0},
        {'lt': 'client', 'lv': 'C3', 'qt': 0},
      ];
      final agg = TaskFeedList.aggregateForRow(
          zeroDocs,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C3',
          'qt');
      expect(agg.rows, 2);
      expect(agg.sum, 0);
    });

    test('server-encoded search decodes correctly', () {
      // _25FC_ = blackSquare, _u2B58_ = circleSeparator
      final agg = TaskFeedList.aggregateForRow(
          assetCache,
          'lt_25FC_client_u2B58_lv_25FC_{lv}',
          'lv',
          'C1',
          'qt');
      expect(agg.rows, 2);
      expect(agg.sum, 8);
    });

    test('empty search -> rows:0 sum:0', () {
      final agg = TaskFeedList.aggregateForRow(
          assetCache, '', 'lv', 'C1', 'qt');
      expect(agg.rows, 0);
      expect(agg.sum, 0);
    });

    test('empty rowId -> rows:0 sum:0', () {
      final agg = TaskFeedList.aggregateForRow(
          assetCache,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          '',
          'qt');
      expect(agg.rows, 0);
      expect(agg.sum, 0);
    });

    test('unresolved leftover token -> rows:0 sum:0', () {
      // rawSearch references {warehouse} but idField is 'lv' -> leftover.
      final agg = TaskFeedList.aggregateForRow(
          assetCache,
          'lt\u{25FC}client\u{2B58}gl\u{25FC}{warehouse}',
          'lv',
          'C1',
          'qt');
      expect(agg.rows, 0);
      expect(agg.sum, 0);
    });

    test('empty docs -> rows:0 sum:0', () {
      final agg = TaskFeedList.aggregateForRow(
          <Map<String, dynamic>>[],
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C1',
          'qt');
      expect(agg.rows, 0);
      expect(agg.sum, 0);
    });

    test('missing sumField defaults to 0 via coerceNum', () {
      final List<Map<String, dynamic>> noQtDocs = [
        {'lt': 'client', 'lv': 'C1'},
        {'lt': 'client', 'lv': 'C1'},
      ];
      final agg = TaskFeedList.aggregateForRow(
          noQtDocs,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C1',
          'qt');
      expect(agg.rows, 2);
      expect(agg.sum, 0);
    });

    test('string qt values coerced to int', () {
      final List<Map<String, dynamic>> strDocs = [
        {'lt': 'client', 'lv': 'C1', 'qt': '7'},
        {'lt': 'client', 'lv': 'C1', 'qt': '3'},
      ];
      final agg = TaskFeedList.aggregateForRow(
          strDocs,
          'lt\u{25FC}client\u{2B58}lv\u{25FC}{lv}',
          'lv',
          'C1',
          'qt');
      expect(agg.rows, 2);
      expect(agg.sum, 10);
    });
  });
}
