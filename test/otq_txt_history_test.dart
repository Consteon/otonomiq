// Parser check for the TXT `variant:"history"` timeline rail.
//
// The rail only ever renders what parseHistoryLine() returns, so this covers
// the whole risk surface: real server strings, empty server fields (the "@ -"
// artifacts), and unknown formats degrading to plain text instead of vanishing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/otq_txt.dart';

void main() {
  group('OtqTxt.parseHistoryLine', () {
    test('attendance line splits into stamp / head / tail', () {
      final (stamp, head, tail) = OtqTxt.parseHistoryLine(
          '15-Jul 15:42 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora 15345 Indonesia');
      expect(stamp, '15-Jul · 15:42');
      expect(head, 'Sekuriti - absen masuk');
      expect(tail, 'BSD Tech Center #26 - Sampora 15345 Indonesia');
    });

    test('empty server fields leave no dangling dashes', () {
      final (stamp, head, tail) = OtqTxt.parseHistoryLine(
          '06-Jul 11:04 - Pengarahan @ - QA-shared-path-regression-check - Jalan Horizon Broadway Banten 15345');
      expect(stamp, '06-Jul · 11:04');
      expect(head, 'Pengarahan');
      expect(tail, 'QA-shared-path-regression-check - Jalan Horizon Broadway Banten 15345');
    });

    test('missing location keeps head, empty tail', () {
      final (stamp, head, tail) =
          OtqTxt.parseHistoryLine('11-Jun 14:41 - Laporan patroli');
      expect(stamp, '11-Jun · 14:41');
      expect(head, 'Laporan patroli');
      expect(tail, '');
    });

    test('unknown format degrades to plain text, never dropped', () {
      final (stamp, head, tail) =
          OtqTxt.parseHistoryLine('catatan bebas tanpa tanggal');
      expect(stamp, '');
      expect(head, 'catatan bebas tanpa tanggal');
      expect(tail, '');
    });

    test('empty and dash-only input do not hang or throw', () {
      expect(OtqTxt.parseHistoryLine(''), ('', '', ''));
      expect(OtqTxt.parseHistoryLine('  -  -  '), ('', '', ''));
    });

    test('single-digit day and dotted time still parse', () {
      final (stamp, head, _) =
          OtqTxt.parseHistoryLine('6-Jul 9.04 Pengarahan @ Sampora');
      expect(stamp, '6-Jul · 9.04');
      expect(head, 'Pengarahan');
    });
  });

  // The rail nests Expanded inside IntrinsicHeight — the one layout shape that
  // can throw "unbounded height" at runtime and take the whole home page down.
  group('OtqTxt variant rendering', () {
    testWidgets('history rail lays out and splits every line', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OtqTxt(
              component: const <String, dynamic>{
                'type': 'txt',
                'variant': 'history',
                'data':
                    '15-Jul 15:42 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora\n'
                        '14-Jul 13:31 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora\n'
                        '14-Jul 13:20 Sekuriti - absen masuk @ BSD Tech Center #26 - Sampora',
              },
              scrName: 'home',
              lPad: 16,
              tPad: 0,
              rPad: 16,
              bPad: 0,
            ),
          ),
        ),
      ));
      expect(find.text('15-Jul · 15:42'), findsOneWidget);
      expect(find.text('Sekuriti - absen masuk'), findsNWidgets(3));
    });

    testWidgets('section header renders mixed-case title as-is', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: OtqTxt(
            component: <String, dynamic>{
              'type': 'txt',
              'variant': 'section',
              'data': 'Riwayat Absensi',
            },
            scrName: 'home',
            lPad: 16,
            tPad: 0,
            rPad: 16,
            bPad: 0,
          ),
        ),
      ));
      expect(find.text('Riwayat Absensi'), findsOneWidget);
    });

    testWidgets('section header splits " -- " meta to its own right-side text',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: OtqTxt(
            component: <String, dynamic>{
              'type': 'txt',
              'variant': 'section',
              'data': 'ABSEN MASUK -- 18-Aug 8:34',
            },
            scrName: 'home',
            lPad: 16,
            tPad: 0,
            rPad: 16,
            bPad: 0,
          ),
        ),
      ));
      expect(find.text('ABSEN MASUK'), findsOneWidget);
      expect(find.text('18 Aug · 8:34'), findsOneWidget);
    });
  });
}
