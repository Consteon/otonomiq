// test/timeline_periodic_widget_test.dart
//
// The ONLY test that pumps TimelinePeriodic. It exists to pin the _buildEntry
// call site: the pure tests in timeline_periodic_support_test.dart all pass
// even when the renderer never calls resolveHidingEmptySegments.
//
// The component carries `table`/`vidtable` so _subscribe() runs; firestoreDb is
// null under flutter_test, subscribeToMapCollection swallows the resulting
// NoSuchMethodError in its own try/catch and prints one line, and the widget
// then reads the rows this test seeds directly into mapTableContent. Expect
// that "subscribeToMapCollection ... failed" line in the output; it is not a
// failure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show mapTableContent, transactionStore;
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/timeline_periodic.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // build() reads transactionStore.state.screenTx; the global is `dynamic`
    // and stays null outside globalInit, so this would NoSuchMethod without it.
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  // A plain global RxMap -- a seeded row leaks into the next test otherwise.
  setUp(mapTableContent.clear);
  tearDown(mapTableContent.clear);

  // vidtable/tableDocId/subColl, the key _subscribe() builds.
  const String code = 'V/D/event';
  const String tpl = '<ts>◆<pvo> → <sd> (+<du> m³)◆oleh <cn>◆<d>';

  Map<String, dynamic> component() => <String, dynamic>{
        'type': 'TIMELINE',
        'variant': 'periodic',
        'position': 3,
        'vidtable': 'V',
        'table': 'D//event',
        'period': 'Minggu ini◼604800000',
        'text': tpl,
        'badge': '-',
      };

  Widget subject() => MaterialApp(
        home: Scaffold(
          body: TimelinePeriodic(
            component: component(),
            scrName: 'kokpit',
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      );

  // ★ RED if _buildEntry still calls resolveMapTokens: segment 1 renders the
  // literal " →  (+ m³)" -- the exact string the field report photographed.
  // `t` is the epoch eventEpoch() reads; `ts` is OVERWRITTEN by _buildEntry
  // with relativeTimestamp(), so no fixture can pin slot 0 without a clock.
  testWidgets('a recheck event renders without the empty " →  (+ m³)"',
      (WidgetTester t) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    mapTableContent[code] = <Map<String, dynamic>>[
      <String, dynamic>{
        't': '$now',
        'cn': 'Dewi (kantor)',
        'd': 'Angka meragukan',
      },
    ];
    await t.pumpWidget(subject());
    await t.pump();
    expect(find.textContaining('oleh Dewi (kantor)'), findsOneWidget);
    expect(find.textContaining('m³'), findsNothing);
    // D1: the note stayed in slot 3 instead of shifting up into the
    // maxLines-1 slot 2. _buildEntry wraps at(3) in quotes.
    expect(find.text('"Angka meragukan"'), findsOneWidget);
  });

  // The CONTROL. Measured GREEN under the same mutation that reds the test
  // above, which is what makes that one a detector rather than a coincidence.
  testWidgets('a full reading row still renders every segment',
      (WidgetTester t) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    mapTableContent[code] = <Map<String, dynamic>>[
      <String, dynamic>{
        't': '$now',
        'pvo': '4581',
        'sd': '4615',
        'du': '34',
        'cn': 'Surya',
        'd': 'lancar',
      },
    ];
    await t.pumpWidget(subject());
    await t.pump();
    expect(find.text('4581 → 4615 (+34 m³)'), findsOneWidget);
    expect(find.textContaining('oleh Surya'), findsOneWidget);
  });
}
