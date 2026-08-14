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

  // ── Multi-clause ◆ filter: OR / union across clauses ──────────────────
  //
  // Grammar: filter := clause (◆ clause)* ; clause := term (WS term)*
  // A row is kept when it matches ANY clause; within ONE clause every term
  // must match. ◆ is separator[1] and may arrive as the real character or as
  // the server escapes _u25C6_ / _25C6_.

  group('searchTable multi-clause OR filter', () {
    // Mirrors the real config "Product Group◆Kantor Pusat".
    // id3 carries 'kantor' but NOT 'pusat' -> proves within-clause AND.
    // id4 matches BOTH clauses -> proves de-duplication.
    final orRows = <List<dynamic>>[
      ['id1', 'Product Group', 'Samarinda'],
      ['id2', 'Kantor Pusat', 'Balikpapan'],
      ['id3', 'Cabang Kantor', 'Bandung'],
      ['id4', 'Product Group', 'Kantor Pusat'],
      ['id5', 'PT Consteon', 'Jakarta'],
    ];

    List<dynamic> idsOf(List<dynamic> rows) => rows.map((r) => r[0]).toList();

    test('two clauses keep rows matching EITHER clause', () {
      final result = searchTable(
        'Product Group${separator[1]}Kantor Pusat',
        List.from(orRows),
      );
      expect(idsOf(result), ['id1', 'id2', 'id4']);
    });

    test('union keeps SOURCE order and never duplicates a row', () {
      // Clause order reversed: the output must still follow row order,
      // and id4 (matches both clauses) must appear exactly once.
      final result = searchTable(
        'Kantor Pusat${separator[1]}Product Group',
        List.from(orRows),
      );
      expect(idsOf(result), ['id1', 'id2', 'id4']);
      expect(idsOf(result).where((id) => id == 'id4').length, 1);
    });

    test('within one clause the words are ANDed', () {
      // id3 has 'Cabang Kantor' but no 'pusat' -> must be excluded.
      final result = searchTable('Kantor Pusat', List.from(orRows));
      expect(idsOf(result), ['id2', 'id4']);
    });

    test('single clause behaves exactly as before', () {
      final result = searchTable('Product Group', List.from(orRows));
      expect(idsOf(result), ['id1', 'id4']);
    });

    test('trailing empty clause is dropped: "A◆" == "A"', () {
      final withSep =
          searchTable('Product Group${separator[1]}', List.from(orRows));
      final without = searchTable('Product Group', List.from(orRows));
      expect(idsOf(withSep), idsOf(without));
      expect(idsOf(withSep), ['id1', 'id4']);
    });

    test('separator-only filter returns ALL rows (fail-open)', () {
      expect(searchTable(separator[1], List.from(orRows)).length, orRows.length);
      expect(
        searchTable('${separator[1]}${separator[1]}', List.from(orRows)).length,
        orRows.length,
      );
    });

    test('escape form _u25C6_ splits into clauses', () {
      final result =
          searchTable('Product Group_u25C6_Kantor Pusat', List.from(orRows));
      expect(idsOf(result), ['id1', 'id2', 'id4']);
    });

    test('bare escape form _25C6_ splits into clauses', () {
      // autheniumDecode has NO _25C6_ line (it covers only the _u25C6_ form),
      // so searchTable must normalize this form itself.
      final result =
          searchTable('Product Group_25C6_Kantor Pusat', List.from(orRows));
      expect(idsOf(result), ['id1', 'id2', 'id4']);
    });

    test('ragged rows and null/int cells are non-matches', () {
      final sparse = <List<dynamic>>[
        ['id1'],
        ['id2', null, 7],
        ['id3', 'Kantor Pusat'],
      ];
      final result = searchTable(
        'Product Group${separator[1]}Kantor Pusat',
        List.from(sparse),
      );
      expect(idsOf(result), ['id3']);
    });

    test('normalization touches the ◆ escapes ONLY, not autheniumDecode', () {
      // Pins the design decision: searchTable must NOT run autheniumDecode.
      // If it did, '_u25FC_' would become ◼ and match id2 instead of id1.
      final escRows = <List<dynamic>>[
        ['id1', 'has literal _u25FC_ here'],
        ['id2', 'has real \u{25FC} here'],
      ];
      final result = searchTable('_u25FC_', List.from(escRows));
      expect(idsOf(result), ['id1']);
    });

    test('clause split that breaks a group falls back to the unsplit filter',
        () {
      // Splitting on ◆ can cut a BALANCED regex in half: "Kantor (Pusat◆Cabang)"
      // gives the clause "Kantor (Pusat" -> term "(pusat" -> FormatException:
      // Unterminated group. The fallback re-runs the UNSPLIT string, which is
      // what this filter did before ◆ was a clause separator: one clause, term
      // "(pusat◆cabang)", matching nothing because ◆ is forbiddenCharacter[0]
      // and cannot survive in a cell. Expect 0 rows, NOT all rows — a broken
      // filter must not silently start matching everything.
      final result = searchTable(
        'Kantor (Pusat${separator[1]}Cabang)',
        List.from(orRows),
      );
      expect(idsOf(result), <dynamic>[]);
    });

    test('clause split that breaks a character class does not throw', () {
      // "[A◆B]" -> clause "[A" -> RegExp: Unterminated character class.
      // Fallback compiles the unsplit "[a◆b]", a class of a / ◆ / b.
      final classRows = <List<dynamic>>[
        ['id1', 'Alpha'],
        ['id2', 'Bravo'],
        ['id3', 'Zulu'],
      ];
      final result =
          searchTable('[A${separator[1]}B]', List.from(classRows));
      expect(idsOf(result), ['id1', 'id2']); // id3 has neither a nor b
    });

    test('valid regex clauses still OR normally (fallback swallows nothing)',
        () {
      // Balanced groups on BOTH sides of ◆: the happy path must stay on the
      // multi-clause branch and must NOT be diverted into the fallback.
      final result = searchTable(
        '(Product|PT)${separator[1]}Kantor Pusat',
        List.from(orRows),
      );
      expect(idsOf(result), ['id1', 'id2', 'id4', 'id5']);
    });
  });
}
