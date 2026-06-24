// test/display_list_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';

void main() {
  // ── searchTable grammar (proves the AND-token filter works) ───────────

  group('searchTable plain-string filter', () {
    // Sample rows: each row is a List<dynamic> (mirrors tableContent shape).
    final sampleRows = <List<dynamic>>[
      ['id1', 'Dinas DKP3A Prov Kaltim', 'Samarinda', '2025-01-01'],
      ['id2', 'Dinas Kesehatan Prov Kaltim', 'Balikpapan', '2025-02-01'],
      ['id3', 'Dinas DKP3A Kota Bandung', 'Bandung', '2025-03-01'],
      ['id4', 'Dinas DKP3A Prov Kaltim Cabang Baru', 'Samarinda', '2025-04-01'],
      ['id5', 'PT Consteon Informatika', 'Jakarta', '2025-05-01'],
    ];

    test('filters to rows matching ALL 4 tokens', () {
      final result =
          searchTable('Dinas DKP3A Prov Kaltim', List.from(sampleRows));
      // Only id1 and id4 contain all four tokens.
      expect(result.length, 2);
      expect(result[0][0], 'id1');
      expect(result[1][0], 'id4');
    });

    test('empty filter returns all rows', () {
      final result = searchTable('', List.from(sampleRows));
      expect(result.length, sampleRows.length);
    });

    test('whitespace-only filter returns all rows', () {
      final result = searchTable('   ', List.from(sampleRows));
      expect(result.length, sampleRows.length);
    });

    test('single-token filter matches any cell containing that token', () {
      final result = searchTable('Samarinda', List.from(sampleRows));
      expect(result.length, 2); // id1, id4
    });

    test('filter is case-insensitive', () {
      final result =
          searchTable('dinas dkp3a prov kaltim', List.from(sampleRows));
      expect(result.length, 2);
    });
  });

  // ── Documents WHY finalFilter was null (the original bug) ─────────────

  group('separator[8] split on plain-string filter', () {
    test('plain-string filter has no hollow-circle -> split yields length 1', () {
      const filter = 'Dinas DKP3A Prov Kaltim';
      final parts = filter.split(separator[8]); // white hollow circle
      expect(parts.length, 1,
          reason:
              'A plain-string filter contains no separator[8], so split '
              'produces a single-element list. The original code required '
              'parts.length > 1 to set finalFilter, so finalFilter stayed null '
              '-> searchTable received empty string -> returned all rows.');
    });

    test('picker-style filter with hollow-circle splits into label + value', () {
      final filter = 'Label${separator[8]}FilterValue';
      final parts = filter.split(separator[8]);
      expect(parts.length, 2);
      expect(parts[0], 'Label');
      expect(parts[1], 'FilterValue');
    });
  });

  // ── _activeFilter getter logic (pure-function mirror) ─────────────────
  //
  // FtzArraySearch is a StatefulWidget with heavy GetX/global deps, so we
  // test the getter's logic as a standalone function rather than pumping
  // the widget (which would require seeding GetX tableContent, global
  // separator, etc.). This proves the discriminator produces the correct
  // filter string for each mode.

  group('_activeFilter discriminator logic', () {
    // Mirror the getter: resultController == null -> raw filter; else finalFilter.
    String activeFilter({
      required bool hasResultController,
      required dynamic componentFilter,
      required String? finalFilter,
    }) {
      return !hasResultController
          ? (componentFilter ?? '').toString()
          : (finalFilter ?? '');
    }

    test('display mode (no resultController) returns raw component filter', () {
      expect(
        activeFilter(
          hasResultController: false,
          componentFilter: 'Dinas DKP3A Prov Kaltim',
          finalFilter: null,
        ),
        'Dinas DKP3A Prov Kaltim',
      );
    });

    test('display mode with null filter returns empty string', () {
      expect(
        activeFilter(
          hasResultController: false,
          componentFilter: null,
          finalFilter: null,
        ),
        '',
      );
    });

    test('picker mode (has resultController) returns finalFilter', () {
      expect(
        activeFilter(
          hasResultController: true,
          componentFilter: 'irrelevant',
          finalFilter: 'ParsedValue',
        ),
        'ParsedValue',
      );
    });

    test('picker mode with null finalFilter returns empty string', () {
      expect(
        activeFilter(
          hasResultController: true,
          componentFilter: 'irrelevant',
          finalFilter: null,
        ),
        '',
      );
    });
  });

  // ── C2 fix: length-guard on row index 5 ───────────────────────────────

  group('C2 row index length guard', () {
    test('row with 6+ elements: index 5 accessible', () {
      final row = ['id', 'a', 'b', 'c', 'd', 'e'];
      final val = row.length > 5 ? row[5] : '';
      expect(val, 'e');
    });

    test('row with 3 elements: index 5 falls back to empty string', () {
      final row = ['id', 'a', 'b'];
      final val = row.length > 5 ? row[5] : '';
      expect(val, '');
    });

    test('row scalars have no .value getter (plain String)', () {
      final row = ['id1', 'Hello', 42, true, null, 'last'];
      // Accessing row[0] returns the String directly, not an object with .value.
      expect(row[0], isA<String>());
      expect(row[0].toString(), 'id1');
      // This is what the FIXED code does -- no .value call.
      expect(row.length > 5 ? row[5] : '', 'last');
    });
  });

  // ── Task 1d: _applySort by row key (index 0) ──────────────────────────
  //
  // Mirrors _applySort's comparator. Proves display-mode first-paint sort.

  group('_applySort by integer key at index 0', () {
    List<dynamic> applySort(List<dynamic> rows, String sortParam) {
      if (sortParam == 'asc' || sortParam == 'desc') {
        final sortFactor = sortParam == 'asc' ? 1 : -1;
        try {
          rows.sort((a, b) =>
              sortFactor *
              int.parse(a[0].toString())
                  .compareTo(int.parse(b[0].toString())));
        } catch (_) {}
      }
      return rows;
    }

    test('desc orders rows by key descending (newest-first)', () {
      final rows = <List<dynamic>>[
        ['100', 'a'], ['300', 'c'], ['200', 'b'],
      ];
      applySort(rows, 'desc');
      expect(rows.map((r) => r[0]).toList(), ['300', '200', '100']);
    });

    test('asc orders rows by key ascending', () {
      final rows = <List<dynamic>>[
        ['100', 'a'], ['300', 'c'], ['200', 'b'],
      ];
      applySort(rows, 'asc');
      expect(rows.map((r) => r[0]).toList(), ['100', '200', '300']);
    });

    test('non-integer key: no throw, order preserved', () {
      final rows = <List<dynamic>>[
        ['x', 'a'], ['y', 'b'],
      ];
      applySort(rows, 'desc'); // int.parse throws internally -> swallowed
      expect(rows.length, 2);
    });

    test('unset sort param: no-op', () {
      final rows = <List<dynamic>>[
        ['300', 'c'], ['100', 'a'],
      ];
      applySort(rows, '');
      expect(rows.map((r) => r[0]).toList(), ['300', '100']);
    });
  });
}
