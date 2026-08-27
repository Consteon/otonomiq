import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart' show mapTableContent;
import 'package:otonomiq/widget/driver_home_support.dart'
    show clearDriverHomeState, kMapsLabelDefault;
import 'package:otonomiq/widget/driver_stop_card.dart';

/// DRIVER_STOP_CARD `mapsUrl` — slot contract + backward compatibility.
///
/// The `mapsUrl` feature APPENDS a maps label at `text` slot 20. The reject
/// footnote stays at slot 19, where every deployed config already has it
/// (`docs/driver_runtime/custody-mode-toggle-op1screen.md` records a resolved
/// 20-segment `text` for tenant 20342033315492 with the footnote at 19), so
/// migration is append-only — no existing segment is ever rewritten.
///
/// Two cases, because one alone cannot prove the contract:
///   1. a LEAN 19-segment tenant with no `mapsUrl`: no button anywhere, and
///      the footnote still renders from its hardcoded default;
///   2. a 21-segment config with DISTINCT strings at slots 19 and 20 — the
///      only fixture that can tell the two slots apart. A renderer that read
///      them the other way round produces the mirror-image widget counts and
///      fails.
///
/// Harness notes (why this pumps with no Firebase):
///   * `table` is OMITTED, so `_subscribe()`'s `tp.tableDocId` is empty and
///     `subscribeToMapCollection` is never reached.
///   * `vidtable` IS set. `_subscribe()` calls `resolveAppVid` BEFORE that
///     guard, and `resolveAppVid` falls through to `getTableVid`, which reads
///     the `late` global `appCodeController` and throws
///     LateInitializationError outside `globalInit`. A non-empty `vidtable`
///     short-circuits it. It changes nothing else: with no `table` there is
///     no subscription code to scope.
///   * `_dataCode` therefore stays `''`, so `_getFilteredStops()` reads
///     `mapTableContent['']` — seeded directly below.
///   * `gateTable` is OMITTED, so `evaluateGateSearch('', '', …)` returns
///     false and the card renders in LOCKED mode (`_buildPending`), which is
///     where the reject footnote lives.
void main() {
  // A lean tenant: 19 segments, slots 0..18, ending at "Tolak". Slots 19
  // (reject footnote) and 20 (maps label) are BOTH absent, so both `_t` reads
  // fall through to their hardcoded defaults.
  const List<String> kShipped19Segments = <String>[
    'Stop Berikutnya',
    'Dilaporkan Gagal',
    'Sudah Selesai',
    'Pilih sesuai kondisi lapangan',
    'Mulai Eksekusi',
    'Selesai',
    'Customer confirmed',
    'Dilaporkan gagal — menunggu admin reschedule',
    'kirim',
    'ambil',
    'Pickup Only',
    'Rute Hari Ini',
    '{closed} dari {total} stop',
    'lanjut:',
    'semua kelar',
    '{total} tujuan',
    'Konfirmasi muatan dulu buat mulai — ini tujuan lo hari ini:',
    'Buka Tasklist (eksekusi)',
    'Tolak',
  ];

  const String kScrName = 'dsc_maps_compat_01';
  const String kScrName2 = 'dsc_maps_slots_01';
  const String kScrName3 = 'dsc_maps_label_01';
  const String kScrName4 = 'dsc_maps_layout_01';

  // Deliberately unlike anything the widget hardcodes: if either of these
  // renders, it came out of the `text` config at that exact slot.
  const String kFootnoteSlot19 = 'FOOTNOTE-SLOT-19';
  const String kLabelSlot20 = 'LABEL-SLOT-20';

  const String kFootnoteDefault =
      'Ada stop nggak searah? Tolak sebelum berangkat, dikembalikan ke Admin.';

  tearDown(() {
    // Do not leak the seeded rows or the per-screen GetX state into the rest
    // of the suite.
    mapTableContent.remove('');
    clearDriverHomeState(kScrName);
    clearDriverHomeState(kScrName2);
    clearDriverHomeState(kScrName3);
    clearDriverHomeState(kScrName4);
  });

  testWidgets(
      'mapsUrl absent: no maps button anywhere, reject footnote still renders',
      (WidgetTester tester) async {
    // Two pending stops. `tst` must not be the default-excluded
    // `load_rejected`, or `_getFilteredStops()` drops them and the footnote
    // (gated on stops.isNotEmpty) never renders.
    mapTableContent[''] = <Map<String, dynamic>>[
      {'tnm': 'T001', 'kn': 'Toko A', 'al': 'Jl. X', 'tst': 'assigned'},
      {'tnm': 'T002', 'kn': 'Toko B', 'al': 'Jl. Y', 'tst': 'assigned'},
    ];

    final Map<String, dynamic> component = <String, dynamic>{
      'type': 'DRIVER_STOP_CARD',
      'vidtable': '20342033315492',
      // 'table' omitted on purpose — see the harness note above.
      // 'gateTable' omitted — locked mode.
      // 'mapsUrl' ABSENT — this is the guarantee under test.
      'rejectRoute': 'rejectTask', // hasReject, so the footnote block runs
      'text': kShipped19Segments.join('\u{25C6}'),
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverStopCard(
            component: component,
            scrName: kScrName,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Fixture sanity FIRST: without this, the two assertions below could both
    // be green on a card that rendered nothing at all.
    //
    // Slot 16 is the one shipped segment whose text differs from the code's
    // hardcoded default ('Konfirmasi muatan dulu buat mulai', no suffix), so
    // finding the LONGER string proves `_textArray` is genuinely populated and
    // being indexed — not empty with every `_t` falling through to a default.
    expect(find.text(kShipped19Segments[16]), findsOneWidget);
    // And both seeded stops reached the locked-mode render, so the footnote's
    // `stops.isNotEmpty` gate is genuinely open.
    expect(find.text('Tolak'), findsNWidgets(2));

    // (1) mapsUrl absent -> the maps button is not rendered anywhere.
    expect(find.text(kMapsLabelDefault), findsNothing);

    // (2) the reject footnote still renders. Slot 19 is untouched by this
    // feature and falls through to its hardcoded default on a 19-segment
    // config, so the lean tenant sees no change. This assertion cannot tell
    // slot 19 from slot 20 — the 21-segment test below is the one that can.
    expect(find.text(kFootnoteDefault), findsOneWidget);
  });

  testWidgets(
      '21-segment config: slot 20 is the maps label, slot 19 stays the footnote',
      (WidgetTester tester) async {
    // The migrated shape: the lean 19 segments with the footnote APPENDED at
    // 19 and the maps label APPENDED at 20 — append-only, nothing rewritten.
    const List<String> kSegments21 = <String>[
      ...kShipped19Segments,
      kFootnoteSlot19,
      kLabelSlot20,
    ];

    // Same two stops, now carrying the denormalised coordinate, so every
    // `<token>` in the `url` template fills and the ENABLED path runs.
    mapTableContent[''] = <Map<String, dynamic>>[
      {
        'tnm': 'T001',
        'kn': 'Toko A',
        'al': 'Jl. X',
        'tst': 'assigned',
        'la': '-6.302154',
        'lo': '106.653428',
      },
      {
        'tnm': 'T002',
        'kn': 'Toko B',
        'al': 'Jl. Y',
        'tst': 'assigned',
        'la': '-6.175392',
        'lo': '106.827153',
      },
    ];

    final Map<String, dynamic> component = <String, dynamic>{
      'type': 'DRIVER_STOP_CARD',
      'vidtable': '20342033315492',
      // 'table' / 'gateTable' omitted — see the harness note above.
      'rejectRoute': 'rejectTask',
      // keyed DSL, one pair: `url` + \u25FC + template. Both tokens resolve
      // off the rows above, so the button renders enabled.
      'mapsUrl': 'url\u{25FC}https://www.google.com/maps/search/'
          '?api=1&query=<la>,<lo>',
      'text': kSegments21.join('\u{25C6}'),
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverStopCard(
            component: component,
            scrName: kScrName2,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Anti-vacuity, same two guards as above: the text array is genuinely
    // populated and indexed, and both stop rows reached the locked render.
    expect(find.text(kShipped19Segments[16]), findsOneWidget);
    expect(find.text('Tolak'), findsNWidgets(2));
    // Neither hardcoded default is on screen, so every string asserted below
    // came out of the config rather than out of a `_t` fallthrough.
    expect(find.text(kFootnoteDefault), findsNothing);
    expect(find.text(kMapsLabelDefault), findsNothing);

    // The discrimination. The label is per ROW (2 stops -> 2 widgets); the
    // footnote is once per CARD. A renderer that swapped the two `_t` reads
    // produces exactly the mirror image of these counts and fails here.
    expect(find.text(kLabelSlot20), findsNWidgets(2));
    expect(find.text(kFootnoteSlot19), findsOneWidget);
  });

  testWidgets('mapsUrl label key OVERRIDES the legacy text slot 20',
      (WidgetTester tester) async {
    // Bagian C, D1: the label moved into the keyed DSL so a tenant never has to
    // count ◆ again. The legacy slot stays as the middle fallback, so this
    // fixture carries BOTH and proves which one wins.
    const List<String> kSegments21 = <String>[
      ...kShipped19Segments,
      kFootnoteSlot19,
      kLabelSlot20, // legacy slot -- must LOSE to the DSL key
    ];
    const String kLabelFromDsl = 'LABEL-FROM-DSL';

    mapTableContent[''] = <Map<String, dynamic>>[
      {
        'tnm': 'T001',
        'kn': 'Toko A',
        'al': 'Jl. X',
        'tst': 'assigned',
        'la': '-6.302154',
        'lo': '106.653428',
      },
    ];

    final Map<String, dynamic> component = <String, dynamic>{
      'type': 'DRIVER_STOP_CARD',
      'vidtable': '20342033315492',
      'rejectRoute': 'rejectTask',
      'mapsUrl': 'url\u{25FC}https://www.google.com/maps/search/'
          '?api=1&query=<la>,<lo>'
          '\u{2B58}label\u{25FC}$kLabelFromDsl',
      'text': kSegments21.join('\u{25C6}'),
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverStopCard(
            component: component,
            scrName: kScrName3,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Fixture sanity FIRST: the text array really parsed and the stop really
    // rendered, so the assertions below cannot be green on an empty card.
    expect(find.text(kShipped19Segments[16]), findsOneWidget);
    expect(find.text('Tolak'), findsOneWidget);
    // And the footnote still comes from slot 19 -- nothing was renumbered.
    expect(find.text(kFootnoteSlot19), findsOneWidget);

    // The discrimination: the DSL label renders, the legacy slot does NOT.
    expect(find.text(kLabelFromDsl), findsOneWidget);
    expect(find.text(kLabelSlot20), findsNothing);
    expect(find.text(kMapsLabelDefault), findsNothing);
  });

  testWidgets(
      'spec 13.5.1: pending row pairs maps+Tolak on one line, done row keeps the chip',
      (WidgetTester tester) async {
    // Row 0 pending, row 1 done. Short addresses on purpose: a wrapping address
    // would move the button and make the geometry assertions ambiguous.
    mapTableContent[''] = <Map<String, dynamic>>[
      {
        'tnm': 'T001',
        'kn': 'Toko A',
        'al': 'Jl. X',
        'tst': 'assigned',
        'la': '-6.302154',
        'lo': '106.653428',
      },
      {
        'tnm': 'T002',
        'kn': 'Toko B',
        'al': 'Jl. Y',
        'tst': 'completed', // stopStatusOf -> 'done'
        'la': '-6.175392',
        'lo': '106.827153',
      },
    ];

    final Map<String, dynamic> component = <String, dynamic>{
      'type': 'DRIVER_STOP_CARD',
      'vidtable': '20342033315492',
      'rejectRoute': 'rejectTask',
      'mapsUrl': 'url\u{25FC}https://www.google.com/maps/search/'
          '?api=1&query=<la>,<lo>',
      'text': kShipped19Segments.join('\u{25C6}'),
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverStopCard(
            component: component,
            scrName: kScrName4,
            lPad: 0,
            tPad: 0,
            rPad: 0,
            bPad: 0,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Fixture sanity: both rows rendered and the maps feature is genuinely on.
    expect(find.text(kShipped19Segments[16]), findsOneWidget);
    expect(find.text(kMapsLabelDefault), findsNWidgets(2));
    // Uniform rule (spec 6.4): the `done` row gets a button too.
    // Exactly ONE Tolak -- the done row has none.
    expect(find.text('Tolak'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);

    final Offset mapsRow0 = tester.getCenter(find.text(kMapsLabelDefault).at(0));
    final Offset mapsRow1 = tester.getCenter(find.text(kMapsLabelDefault).at(1));
    final Offset tolak = tester.getCenter(find.text('Tolak'));
    final Offset selesai = tester.getCenter(find.text('Selesai'));

    // PENDING row: Tolak is on the SAME line as the maps button (their inner
    // paddings differ by 1px, hence the 4px tolerance) and to its RIGHT.
    // In the pre-13.5.1 layout Tolak sat at the top of the row, ~38px above the
    // maps button -- that is what this assertion kills.
    expect((tolak.dy - mapsRow0.dy).abs(), lessThan(4.0),
        reason: 'Tolak must share a line with the maps button on a pending stop');
    expect(tolak.dx, greaterThan(mapsRow0.dx),
        reason: 'maps left, Tolak right');

    // DONE row: the Selesai chip stays in the TRAILING position (top of the
    // row) and the maps button sits alone below the address.
    expect(selesai.dy, lessThan(mapsRow1.dy - 10.0),
        reason: 'Selesai chip stays trailing; maps button sits below it');
  });
}
