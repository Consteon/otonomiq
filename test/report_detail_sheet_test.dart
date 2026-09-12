import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/ftz_array_search_support.dart';
import 'package:otonomiq/widget/report_detail_sheet.dart';

/// Pump the sheet with NO images: that branch draws the "Tanpa foto" strip and
/// never touches `displayImage`, so the whole layout is testable off-device.
/// The photo gallery is not — it reaches for the network.
Future<void> _open(
  WidgetTester tester,
  String note, {
  Size screen = const Size(390, _kScreenHeight),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showReportDetailSheet(
              context: context,
              lines: parseContentLines(
                'Tanggal: 11 Sep 2026 11:47\n'
                'Nama: Agenia Demo-7\n'
                'Lokasi: BSD Tech Center #26\n'
                'Kondisi: Aman kondusif\n'
                'Keterangan: $note',
              ),
              images: const <String>[],
              chipLabel: '',
              epochMs: DateTime(2026, 9, 11, 11, 47).millisecondsSinceEpoch,
            ),
            child: const Text('buka'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
}

/// Screen height used by every test here, and the 88 % ceiling that follows.
const double _kScreenHeight = 844;
const double _kCeiling = _kScreenHeight * 0.88; // 742.72

/// Height of the sheet itself.
///
/// `BottomSheet`, not an ancestor lookup from the title: the first
/// `ConstrainedBox` above that text belongs to the close `IconButton`, and
/// measuring it made the assertion pass against a deliberately broken layout.
double _sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(BottomSheet)).height;

void main() {
  testWidgets('a short report makes a short sheet, not 88 % of white', (
    WidgetTester tester,
  ) async {
    await _open(tester, 'ok3');
    expect(find.text('Tanpa foto'), findsOneWidget);
    expect(find.text('ok3'), findsOneWidget);
    final double h = _sheetHeight(tester);
    // A whole 100 dp clear of the ceiling, not merely under it: the broken
    // layout (Expanded + mainAxisSize.max) measures 742.72 against a ceiling
    // of 742.72, so `lessThan(_kCeiling)` passes it and certifies nothing.
    expect(h, lessThan(_kCeiling - 100));
    expect(h, greaterThan(200), reason: 'still a real sheet, not a sliver');
  });

  testWidgets('a long report stops at the 88 % ceiling and scrolls', (
    WidgetTester tester,
  ) async {
    await _open(tester, List<String>.filled(400, 'temuan').join(' '));
    expect(_sheetHeight(tester), closeTo(_kCeiling, 1));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('the head is sticky: it survives scrolling the body', (
    WidgetTester tester,
  ) async {
    await _open(tester, List<String>.filled(400, 'temuan').join(' '));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pump();
    expect(find.text('Detail laporan'), findsOneWidget);
  });

  testWidgets('an empty note says so instead of leaving a gap', (
    WidgetTester tester,
  ) async {
    await _open(tester, '');
    expect(find.text('Tanpa catatan'), findsOneWidget);
  });

  testWidgets('fields land where splitDetailRoles says they do', (
    WidgetTester tester,
  ) async {
    await _open(tester, 'ok3');
    // Chip in the head.
    expect(find.text('Aman kondusif'), findsOneWidget);
    // Clock from the epoch, long date + place on the sub line.
    expect(find.text('11:47'), findsOneWidget);
    expect(
      find.text('Jumat, 11 Sep 2026 · BSD Tech Center #26'),
      findsOneWidget,
    );
    // Non-place, non-chip fields in the metadata table, plus Dibuat.
    expect(find.text('Nama'), findsOneWidget);
    expect(find.text('Agenia Demo-7'), findsOneWidget);
    expect(find.text('Dibuat'), findsOneWidget);
  });
}
