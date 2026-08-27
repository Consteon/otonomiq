// test/workspace_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart'
    show clearDriverHomeState, kMapsLabelDefault, MapsButton;
import 'package:otonomiq/widget/workspace_header.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // ── stopNumber derivation (pure function) ─────────────────────────────

  group('stopNumber derivation', () {
    /// Pure function mirroring WorkspaceHeader's stopNumber logic:
    /// iterate filtered task docs in doc-order, return the 1-based index
    /// of the doc whose [idField] matches [activeTaskVid].
    /// Returns 0 if not found.
    int deriveStopNumber(
      List<Map<String, dynamic>> tasks,
      String activeTaskVid,
      String idField,
    ) {
      for (int i = 0; i < tasks.length; i++) {
        final String docId = (tasks[i][idField] ?? '').toString().trim();
        if (docId == activeTaskVid) return i + 1;
      }
      return 0;
    }

    test('finds correct 1-based index for second task', () {
      final tasks = [
        {'tnm': 'T001', 'kn': 'Customer A'},
        {'tnm': 'T002', 'kn': 'Customer B'},
        {'tnm': 'T003', 'kn': 'Customer C'},
      ];
      expect(deriveStopNumber(tasks, 'T002', 'tnm'), 2);
    });

    test('returns 0 when activeTaskVid not found', () {
      final tasks = [
        {'tnm': 'T001'},
        {'tnm': 'T002'},
      ];
      expect(deriveStopNumber(tasks, 'T999', 'tnm'), 0);
    });

    test('returns 0 for empty task list', () {
      expect(deriveStopNumber([], 'T001', 'tnm'), 0);
    });

    test('first task returns 1', () {
      final tasks = [
        {'tnm': 'T001'},
      ];
      expect(deriveStopNumber(tasks, 'T001', 'tnm'), 1);
    });
  });

  // ── diamondTextToList length guards (workspace header 2 segments) ─────

  group('workspace header text segment guards', () {
    test('2-segment text parses correctly', () {
      final arr = diamondTextToList('Stop\u{25C6}Berjalan');
      expect(arr.isNotEmpty ? arr[0] : '', 'Stop');
      expect(arr.length > 1 ? arr[1] : '', 'Berjalan');
    });

    test('empty text falls back to defaults', () {
      final arr = diamondTextToList('');
      // diamondTextToList('') returns [''] (length 1, arr[0] == '').
      // The index-0 read therefore yields the empty parse value (NOT the
      // 'Stop' default, since length>0). The length-guard default only kicks
      // in at index >= 1.
      expect(arr.length, 1);
      expect(arr.isNotEmpty ? arr[0] : 'Stop', ''); // '' from parse
      expect(arr.length > 1 ? arr[1] : 'Berjalan', 'Berjalan'); // default
    });

    test('single segment falls back for index 1', () {
      final arr = diamondTextToList('OnlyOne');
      expect(arr.isNotEmpty ? arr[0] : '', 'OnlyOne');
      expect(arr.length > 1 ? arr[1] : 'fallback', 'fallback');
    });
  });

  // ── no-data diagnostic title uses slot [0], chip uses slot [1] ────────────
  // Regression: the fallback title rendered chipLabel (slot [1]), so a header
  // with no task doc printed the SAME string on the left and in the chip.
  // No `table` key -> no Firestore subscription, so this pumps offline.

  testWidgets('empty-data header renders slot[0] left, slot[1] in chip',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkspaceHeader(
          component: const <String, dynamic>{
            'type': 'WORKSPACE_HEADER',
            'table': '',
            'text': 'Slip Gaji\u{25C6}Dokumen dari perusahaan Anda',
          },
          scrName: 'wh_test',
          lPad: 0,
          tPad: 0,
          rPad: 0,
          bPad: 0,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('SLIP GAJI'), findsOneWidget);
    expect(find.text('DOKUMEN DARI PERUSAHAAN ANDA'), findsOneWidget);
  });

  // ── maps button in the address band (Bagian C, spec 13.3) ───────────────
  //
  // Harness (no Firebase): `table` is OMITTED, so `_subscribe()` never calls
  // `resolveAppVid` (it sits INSIDE the `rawTable.isNotEmpty` branch in this
  // widget) and `_taskCode` stays `''`. `_findActiveTask()` returns null the
  // moment `_taskCode.isEmpty`, which is exactly the "no task doc" case D6
  // cares about. For the with-doc cases `table` IS set and `mapTableContent`
  // is seeded under the resulting code.
  group('WORKSPACE_HEADER maps button', () {
    const String kScrName = 'wh_maps_01';
    const String kVid = '20342033315492';
    const String kTable = '84214220504259//task';
    const String kCode = '$kVid/84214220504259/task';
    const String kMapsDsl = 'url\u{25FC}https://www.google.com/maps/search/'
        '?api=1&query=<la>,<lo>'
        '\u{2B58}fallback\u{25FC}https://www.google.com/maps/search/'
        '?api=1&query=<al>'
        '\u{2B58}empty\u{25FC}Alamat belum lengkap';

    // `transactionStore` is null in a bare test. Any pump that resolves a task
    // doc reaches `_deriveStopNumber` -> `filterDriverHomeDocs` ->
    // `resolveDriverCurlyTokens`, which reads `transactionStore.state` while
    // resolving `{vehicleId}`/`{today}` in the default `listSearch`. Without
    // this the widget throws during build and every assertion below would fail
    // on an empty screen. Same shape as the GROUPED maps group in
    // test/task_feed_list_test.dart.
    setUpAll(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    tearDown(() {
      mapTableContent.remove(kCode);
      clearDriverHomeState(kScrName);
    });

    Future<void> pumpHeader(
      WidgetTester tester,
      Map<String, dynamic> component,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceHeader(
            component: component,
            scrName: kScrName,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no task doc -> no button AND no address band (D6)',
        (WidgetTester tester) async {
      await pumpHeader(tester, const <String, dynamic>{
        'type': 'WORKSPACE_HEADER',
        'table': '', // -> _taskCode stays '', _findActiveTask() -> null
        'mapsUrl': kMapsDsl,
        'text': 'Tujuan\u{25C6}Lagi Antar',
      });

      // Fixture sanity: the header itself DID render (its no-data diagnostic
      // prints slot 0 uppercased), so "findsNothing" below is about the band,
      // not about an empty screen.
      expect(find.text('TUJUAN'), findsOneWidget);

      expect(find.text(kMapsLabelDefault), findsNothing);
      expect(find.byIcon(Icons.location_on_rounded), findsNothing);
    });

    testWidgets('task doc with coordinates -> enabled button inside the band',
        (WidgetTester tester) async {
      mapTableContent[kCode] = <Map<String, dynamic>>[
        {
          'tnm': 'T001',
          'kn': 'Toko A',
          'al': 'Jl. Merdeka No. 5',
          'la': '-6.302154',
          'lo': '106.653428',
        },
      ];

      await pumpHeader(tester, const <String, dynamic>{
        'type': 'WORKSPACE_HEADER',
        'vidtable': kVid,
        'table': kTable,
        // search omitted -> _findActiveTask() takes docs.first
        'mapsUrl': kMapsDsl,
        'text': 'Tujuan\u{25C6}Lagi Antar',
      });

      // Fixture sanity: the doc really resolved and the band really rendered.
      expect(find.text('Toko A'), findsOneWidget);
      expect(find.text('Jl. Merdeka No. 5'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);

      expect(find.text(kMapsLabelDefault), findsOneWidget);
      // Enabled, so the disabled `empty` message must NOT be printed.
      expect(find.text('Alamat belum lengkap'), findsNothing);

      // Spec 13.5.3, INVERTED host: this band is already indigo-50, so the
      // button here is an OUTLINE (`filled: false`) -- a tint of the same
      // colour would be invisible on it. `filled` is otherwise unobservable
      // to find.text(), and flipping it to `true` used to leave this file
      // green (code-review-r1 I-1). Same binding as the TASK_FEED_LIST
      // witness in test/task_feed_list_test.dart: MapsButton's tree is
      // Column -> GestureDetector -> Container and neither of those two
      // inserts a Container, so `.first` is the author's, not a framework
      // one. This assertion only discriminates on the ENABLED button --
      // a disabled one is outlined whatever `filled` says.
      final BoxDecoration deco = tester
          .widget<Container>(find
              .descendant(
                of: find.byType(MapsButton).first,
                matching: find.byType(Container),
              )
              .first)
          .decoration! as BoxDecoration;
      expect(deco.color, Colors.transparent); // NOT the indigo-50 tint
      expect(deco.border, isNotNull); // outlined
    });

    testWidgets('task doc with NO address and NO coordinates -> disabled button '
        'with its reason', (WidgetTester tester) async {
      mapTableContent[kCode] = <Map<String, dynamic>>[
        {'tnm': 'T001', 'kn': 'Toko A', 'al': '', 'la': '', 'lo': ''},
      ];

      await pumpHeader(tester, const <String, dynamic>{
        'type': 'WORKSPACE_HEADER',
        'vidtable': kVid,
        'table': kTable,
        'mapsUrl': kMapsDsl,
        'text': 'Tujuan\u{25C6}Lagi Antar',
      });

      // Fixture sanity: the doc resolved (the customer name proves it) even
      // though it has no address at all.
      expect(find.text('Toko A'), findsOneWidget);

      // Spec 6.6: the button is greyed WITH a reason, never hidden. The band
      // renders even with an empty address, because the button lives in it.
      expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
      expect(find.text(kMapsLabelDefault), findsOneWidget);
      expect(find.text('Alamat belum lengkap'), findsOneWidget);
    });

    testWidgets('mapsUrl absent -> band renders exactly as before, no button',
        (WidgetTester tester) async {
      mapTableContent[kCode] = <Map<String, dynamic>>[
        {
          'tnm': 'T001',
          'kn': 'Toko A',
          'al': 'Jl. Merdeka No. 5',
          'la': '-6.302154',
          'lo': '106.653428',
        },
      ];

      await pumpHeader(tester, const <String, dynamic>{
        'type': 'WORKSPACE_HEADER',
        'vidtable': kVid,
        'table': kTable,
        // 'mapsUrl' ABSENT -- this is the backward-compat guarantee.
        'text': 'Tujuan\u{25C6}Lagi Antar',
      });

      expect(find.text('Toko A'), findsOneWidget);
      expect(find.text('Jl. Merdeka No. 5'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
      expect(find.text(kMapsLabelDefault), findsNothing);
    });

    // ── W-1: rendering the button must cost the address NOTHING ──────────
    //
    // The band used to be one Row holding `Expanded(address)` (tight, flex 1)
    // and `Flexible(button)` (loose, flex 1). RenderFlex divides the free
    // space between flex children BEFORE laying either of them out, and a
    // loose child never hands its unused share back -- so the address was cut
    // to half the band on EVERY viewport whenever the button rendered, and
    // nothing overflowed to make it visible. That is why the suite stayed
    // green through it. These two tests MEASURE; a test that only asserts the
    // button rendered is exactly what let this ship.

    // A real post-spec-4.1 reverse-geocode address. Long enough that the Text
    // wraps at both viewports below, so its laid-out width IS the width the
    // Row gave it.
    const String kLongAddress =
        'Jl. Raya Serpong No. 88 Blok C RT 05 RW 09, Kelapa Dua, '
        'Kabupaten Tangerang, Banten, 15321, Indonesia';

    testWidgets('spec 13.5.2: the maps button does NOT narrow the address',
        (WidgetTester tester) async {
      mapTableContent[kCode] = <Map<String, dynamic>>[
        {
          'tnm': 'T001',
          'kn': 'Toko A',
          'al': kLongAddress,
          'la': '-6.302154',
          'lo': '106.653428',
        },
      ];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<double> addressWidth(bool withMaps, double viewport) async {
        tester.view.physicalSize = Size(viewport, 800);
        tester.view.devicePixelRatio = 1.0;
        // Unmount first. pumpWidget REUSES the State when widget type and
        // position match, and `_hasMaps` is parsed once in initState -- the
        // second pump would otherwise still be running the first pump's
        // feature gate and both measurements would be the same case.
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpHeader(tester, <String, dynamic>{
          'type': 'WORKSPACE_HEADER',
          'vidtable': kVid,
          'table': kTable,
          if (withMaps) 'mapsUrl': kMapsDsl,
          'text': 'Tujuan\u{25C6}Lagi Antar',
        });
        // Fixture sanity: the band really rendered AND the button really is
        // present/absent as asked. Without this, "the widths match" would be
        // trivially true on a screen that never drew a button.
        expect(find.text(kLongAddress), findsOneWidget);
        expect(find.text(kMapsLabelDefault),
            withMaps ? findsOneWidget : findsNothing);
        return tester.getSize(find.text(kLongAddress)).width;
      }

      for (final double viewport in <double>[800, 360]) {
        final double without = await addressWidth(false, viewport);
        final double withButton = await addressWidth(true, viewport);

        // Sanity on the ceiling itself: the address fills the band, so
        // `without` is a real measurement of the space available.
        expect(without, greaterThan(viewport * 0.7),
            reason: 'viewport $viewport: address did not fill the band '
                '(measured $without)');

        // Round C exists to give the address MORE room (spec 13.5.2). The
        // 50/50 split scored ~0.49 of this at every width.
        expect(withButton, greaterThanOrEqualTo(without - 1.0),
            reason: 'viewport $viewport: the maps button took '
                '${(without - withButton).toStringAsFixed(1)}px from the '
                'address ($without -> $withButton)');
      }
    });

    testWidgets('a long tenant `empty` message wraps, it does not overflow',
        (WidgetTester tester) async {
      // The OTHER half of W-1. The button must stay BOUNDED: simply deleting
      // `Flexible` from the old Row gave it an unbounded main-axis
      // constraint, and this message -- the widest thing MapsButton can draw
      // -- then overflowed the band. As a Column child it is bounded by the
      // band width and wraps (maxLines: 2 + ellipsis).
      const String kLongEmpty =
          'Alamat dan koordinat pelanggan ini belum lengkap. Hubungi admin '
          'untuk melengkapi datanya sebelum berangkat.';
      const String kLongEmptyDsl =
          'url\u{25FC}https://www.google.com/maps/search/?api=1&query=<la>,<lo>'
          '\u{2B58}empty\u{25FC}$kLongEmpty';

      mapTableContent[kCode] = <Map<String, dynamic>>[
        {'tnm': 'T001', 'kn': 'Toko A', 'al': '', 'la': '', 'lo': ''},
      ];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800); // smallest real phone
      tester.view.devicePixelRatio = 1.0;

      await pumpHeader(tester, const <String, dynamic>{
        'type': 'WORKSPACE_HEADER',
        'vidtable': kVid,
        'table': kTable,
        'mapsUrl': kLongEmptyDsl,
        'text': 'Tujuan\u{25C6}Lagi Antar',
      });

      // Fixture sanity: the disabled button AND its long reason really drew.
      expect(find.text(kMapsLabelDefault), findsOneWidget);
      expect(find.text(kLongEmpty), findsOneWidget);
      // A RenderFlex overflow is reported through FlutterError while
      // painting, which the test binding turns into a pending exception.
      expect(tester.takeException(), isNull);
    });
  });
}
