// test/log_checklist_keyed_table_test.dart
//
// Repro for the empty `vertikaTeknoLokaciptaLogChecklist` screen.
//
// The page config is
//   {"type":"displayList","variant":"tableCardInteractive",
//    "table":"84214220504259//report-checklist", ...}
// and the rows DO exist in Firestore under
//   MobileTable/60936087747650/tables/84214220504259/report-checklist.
//
// These tests isolate which half of the chain drops them: the `#TABLE<code>`
// key DisplayList looks up, or FtzArraySearch's own tableContent read.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/widget/ftz_array_search.dart';

/// One `report-checklist` row as `createInternalTableDynamic` builds it:
/// `[t, ...jsonDecode(c)]`.
List<dynamic> _row(String t, String jenis, String tanggal, String lokasi) => [
      t,
      jenis,
      tanggal,
      '60181816889090',
      'Surya Widjaja',
      'Kantor Pusat',
      lokasi,
      '0l114807f17536338c20fd13c3896308df116b295d',
      'hoh9',
      'https://example.invalid/x.jpg',
      'Bersihkan kloset dan urinal|Selesai',
      'Pel lantai|Selesai',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ];

const String _rawTable = '84214220504259//report-checklist';

dynamic _component() => {
      'type': 'displayList',
      'variant': 'tableCardInteractive',
      'table': _rawTable,
      'text': 'Checklist◆Cari di checklist◆Tulis yang anda ingin lihat',
      'content': 'Tanggal: <2>\nJenis: <1>\nLokasi: <7>',
      'filter': '',
      'icon': 'search',
      'sort': 'desc',
      'indexStart': 1,
    };

void main() {
  // ── 1. The key the subscriber writes vs. the key DisplayList reads ──────
  group('keyed table name normalization', () {
    test('normalizeTableName collapses // to a single slash', () {
      expect(normalizeTableName(_rawTable), '84214220504259/report-checklist');
    });

    test('DisplayList reads #TABLE<raw>, subscribeToTable writes #TABLE<norm>',
        () {
      // display_list.dart:100 uses the RAW component value for the screenTx
      // lookup; subscribeToTable (table_repository.dart:2199) normalizes first.
      expect('#TABLE$_rawTable',
          isNot('#TABLE${normalizeTableName(_rawTable)}'),
          reason: 'A keyed // table therefore never resolves for DisplayList: '
              'tableToArray gets null and pickTable stays empty. A plain name '
              'normalizes to itself, which is why the other report screens '
              'were never affected.');
    });
  });

  // ── 2. FtzArraySearch's own read path (the would-be rescue) ─────────────
  group('FtzArraySearch keyed tableContent read', () {
    tearDown(tableContent.clear);

    testWidgets('renders rows already present in tableContent at initState',
        (tester) async {
      tableContent[normalizeTableName(_rawTable)] = [
        _row('1787293172413', 'checklist-restroom', '21 Aug 2026 13:19',
            'Kantor Pusat'),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: FtzArraySearch(localTable: const [], component: _component()),
          ),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('checklist-restroom'), findsOneWidget);
    });

    testWidgets('a component filter the rows cannot satisfy empties the list',
        (tester) async {
      // What the device actually received for vertikaTeknoLokaciptaLogChecklist
      // (Proxy/<ssid>/Page, 2026-08-21): "filter":"Product Group". searchTable
      // ANDs the tokens across every cell; no report-checklist row carries
      // either word, so every row is filtered out and the card shows the
      // empty state even though tableContent is full.
      tableContent[normalizeTableName(_rawTable)] = [
        _row('1787293172413', 'checklist-restroom', '21 Aug 2026 13:19',
            'Kantor Pusat'),
      ];
      final dynamic component = _component();
      component['filter'] = 'Product Group';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: FtzArraySearch(localTable: const [], component: component),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Tidak ada data'), findsOneWidget);
      expect(find.textContaining('checklist-restroom'), findsNothing);
    });

    testWidgets('repaints when tableContent is filled AFTER the first build',
        (tester) async {
      // This is the real runtime order: the widget builds first, the Firestore
      // listener fills tableContent milliseconds later.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: FtzArraySearch(localTable: const [], component: _component()),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Tidak ada data'), findsOneWidget);

      tableContent[normalizeTableName(_rawTable)] = [
        _row('1787293172413', 'checklist-restroom', '21 Aug 2026 13:19',
            'Kantor Pusat'),
      ];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('checklist-restroom'), findsOneWidget,
          reason: 'ever(tableContent) should repaint the list.');
    });
  });
}
