import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart'; // getLocationString
import 'package:otonomiq/global.dart'; // separator, emptyString
import 'package:otonomiq/global2.dart'; // txfController, txfControllerCheck
import 'package:otonomiq/model/otq_state.dart'; // OtqState
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/task_create_submit.dart';

/// renderer-submit-event-gap
///
/// Two things are verifiable here without Firebase:
///   1. the assemblers no longer write `search` / `tablevid` (pure functions);
///   2. `eventComponent` strips exactly the six write-DSL/route keys and
///      nothing else, without mutating its input.
///
/// NOT testable in this harness, and deliberately not faked:
///   - the `emitSubmitEventRow` -> `saveSend` call itself. `saveSend` reads
///     `transactionStore.state.screenTx['#VID'] / ['#INTERFACE_KEY'] /
///     ['#SUBMIT_BLOC'] / ['#TIMER_BLOC']`, and the GPS branch awaits
///     `OtqState().setAllDataAsync()`. A `testWidgets` pump that stubs all of
///     that would assert against its own stub, not against production.
///     Verified on device instead -- see the plan's Verification section.
void main() {
  // Same pattern as ocr_capture_support_test.dart:31. Swaps debugPrint to the
  // synchronous implementation so the debugPrint inside addToTxfController
  // (global2.dart:1033) cannot leave a pending Timer behind a plain test().
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  // ── assembleTaskDoc: junk fields gone, everything else intact ──────────
  group('assembleTaskDoc drops search/tablevid', () {
    Map<String, dynamic> buildFull() =>
        AdminCreateTaskSupport.assembleTaskDoc(
          tnm: 'TASK-2026-000551',
          kl: 'C1',
          kn: 'Toko Maju',
          al: 'Jl. Sudirman 54',
          la: '-6.302154',
          lo: '106.653428',
          vv: 'VEH-123',
          gl: 'WH-001',
          cv: '12345',
          cn: 'Admin A',
          tdt: 1782244800000,
          t: 1782286245000,
          itArray: const [
            {'ii': 'galon', 'in': 'Galon', 'tx': 'deliver', 'sub': 5000},
          ],
          tableVid: '20342033315492',
          tst: 'assigned',
          ln: 'B 1234 XY',
        );

    test('search key is absent', () {
      expect(buildFull().containsKey('search'), isFalse);
    });

    test('tablevid key is absent', () {
      expect(buildFull().containsKey('tablevid'), isFalse);
    });

    test('exact key set -- nothing else was added or lost', () {
      // Explicit expected set, NOT a restatement of the implementation: it is
      // the pre-change key list minus the two removed keys. A future field
      // added to the assembler must fail here on purpose.
      expect(
        buildFull().keys.toSet(),
        <String>{
          'tnm', 'tty', 'tst', 'kl', 'kn', 'al', 'la', 'lo', 'gl',
          'cv', 'cn', 't', 'it', 'tot', 'ts', 'vv', 'ln', 'tdt',
        },
      );
    });

    test('surviving values are unchanged', () {
      final doc = buildFull();
      expect(doc['tnm'], 'TASK-2026-000551');
      expect(doc['tty'], 'delivery');
      expect(doc['tst'], 'assigned');
      expect(doc['kn'], 'Toko Maju');
      expect(doc['la'], '-6.302154');
      expect(doc['vv'], 'VEH-123');
      expect(doc['ln'], 'B 1234 XY');
      expect(doc['tdt'], 1782244800000);
      expect(doc['t'], 1782286245000);
      expect((doc['it'] as List).length, 1);
    });

    test('omit-when-empty idiom still holds for vv/ln/tdt', () {
      final doc = AdminCreateTaskSupport.assembleTaskDoc(
        tnm: 'T1', kl: '', kn: '', al: '', vv: '', gl: '',
        cv: '', cn: '', tdt: null, t: 0, itArray: const [],
        tableVid: '20342033315492',
      );
      expect(doc.containsKey('vv'), isFalse);
      expect(doc.containsKey('ln'), isFalse);
      expect(doc.containsKey('tdt'), isFalse);
      expect(doc.containsKey('search'), isFalse);
      expect(doc.containsKey('tablevid'), isFalse);
    });
  });

  // ── assembleNotaDoc: junk fields gone, everything else intact ──────────
  group('assembleNotaDoc drops search/tablevid', () {
    Map<String, dynamic> buildWalkin() =>
        AdminCreateTaskSupport.assembleNotaDoc(
          nno: 'NOTA-2026-000001',
          src: 'walkin',
          by: 'John',
          bym: 'tunai',
          gl: 'F621558e33b612',
          tot: 45000,
          liArray: const [
            {'ii': 'aqua', 'qt': 1, 'hg': 45000, 'sub': 45000},
          ],
          cv: 'VID123',
          cn: 'Admin Name',
          t: 1720000000000,
          ts: '2026-07-08 14:30',
          tableVid: '20342033315492',
        );

    test('search key is absent', () {
      expect(buildWalkin().containsKey('search'), isFalse);
    });

    test('tablevid key is absent', () {
      expect(buildWalkin().containsKey('tablevid'), isFalse);
    });

    test('exact key set (walkin) -- nothing else was added or lost', () {
      expect(
        buildWalkin().keys.toSet(),
        <String>{
          'nno', 'src', 'ref', 'kl', 'by', 'bym', 'st', 'gl',
          'tot', 'li', 'cv', 'cn', 't', 'ts',
        },
      );
    });

    test('optional supplier/seed keys still appear when supplied', () {
      final doc = AdminCreateTaskSupport.assembleNotaDoc(
        nno: 'NOTA-S-1', src: 'supplier', by: 'Admin', bym: '',
        gl: 'WH-1', tot: 12000, liArray: const [], cv: 'V', cn: 'C',
        t: 1, ts: '2026-07-08 14:30', tableVid: 'TV1',
        sv: 'SUP-1', sn: 'PT Sumber', d: 'catatan',
        kl: 'C9', kn: 'Toko Z', days: 30,
      );
      expect(doc['sv'], 'SUP-1');
      expect(doc['sn'], 'PT Sumber');
      expect(doc['d'], 'catatan');
      expect(doc['kl'], 'C9');
      expect(doc['kn'], 'Toko Z');
      expect(doc['days'], 30);
      expect(doc.containsKey('search'), isFalse);
      expect(doc.containsKey('tablevid'), isFalse);
    });

    test('surviving values are unchanged', () {
      final doc = buildWalkin();
      expect(doc['nno'], 'NOTA-2026-000001');
      expect(doc['src'], 'walkin');
      expect(doc['ref'], '');
      expect(doc['st'], 'LUNAS');
      expect(doc['tot'], 45000);
      expect(doc['tot'], isA<int>());
      expect(doc['t'], isA<int>());
      expect(doc['ts'], '2026-07-08 14:30');
      expect((doc['li'] as List).length, 1);
    });
  });

  // ── eventComponent ────────────────────────────────────────────────────
  group('eventComponent', () {
    // A component carrying every strippable key PLUS the keys saveSend
    // actually reads off it (flag / desc / type / com) PLUS unrelated config.
    Map<String, dynamic> sample() => <String, dynamic>{
          'type': 'TASK_CREATE_SUBMIT',
          'flag': 'admin-create-task',
          'desc': 'buat task',
          'com': 'app',
          'gpsPosition': 0,
          'table': '84214220504259//task',
          'vidtable': '20342033315492',
          'wizardKey': 'admin_create_task',
          'chain': 'someChain',
          'text': 'Buat Task',
          'addToTable': 'A-payload',
          'updateTableRow': 'U-payload',
          'deleteFromTable': 'D-payload',
          'addToEvent': 'E-payload',
          'updateEventRow': 'UE-payload',
          'route': '[ROUTE:taskSuccess]',
        };

    test('strips exactly the six DSL/route keys', () {
      expect(
        eventComponent(sample()).keys.toSet(),
        <String>{
          'type', 'flag', 'desc', 'com', 'gpsPosition', 'table',
          'vidtable', 'wizardKey', 'chain', 'text',
        },
      );
    });

    test('keeps every value saveSend reads off the component', () {
      final out = eventComponent(sample());
      expect(out['flag'], 'admin-create-task');
      expect(out['desc'], 'buat task');
      expect(out['type'], 'TASK_CREATE_SUBMIT');
      expect(out['com'], 'app');
      expect(out['gpsPosition'], 0);
    });

    test('the stripped key list is exactly the six documented keys', () {
      expect(
        kEventComponentStrippedKeys,
        <String>[
          'addToTable',
          'updateTableRow',
          'deleteFromTable',
          'addToEvent',
          'updateEventRow',
          'route',
        ],
      );
    });

    test('does NOT mutate the input map', () {
      final input = sample();
      final int before = input.length;
      eventComponent(input);
      expect(input.length, before);
      expect(input.containsKey('addToEvent'), isTrue);
      expect(input.containsKey('route'), isTrue);
      expect(input['route'], '[ROUTE:taskSuccess]');
    });

    test('returns a new instance, not the same map', () {
      final input = sample();
      expect(identical(eventComponent(input), input), isFalse);
    });

    test('absent keys are a no-op, not a throw', () {
      final lean = <String, dynamic>{'type': 'NOTA_CREATE_SUBMIT'};
      final out = eventComponent(lean);
      expect(out, <String, dynamic>{'type': 'NOTA_CREATE_SUBMIT'});
    });

    test('accepts a dynamic-typed component (server JSON, Convention #7)', () {
      final dynamic asDynamic = sample();
      final out = eventComponent(asDynamic);
      expect(out.containsKey('addToEvent'), isFalse);
      expect(out['type'], 'TASK_CREATE_SUBMIT');
    });
  });

  // ── ROUND 2, gap 1: eventLocString (the geo block) ────────────────────
  //
  // Fully unit-reachable BECAUSE the function takes an OtqState rather than
  // capturing GPS itself: a bare `OtqState()` IS the no-fix state (its field
  // initialisers are the 888/88/"No Gps" dummies, otq_state.dart:16-17/26-27),
  // and a hand-set OtqState is the valid-fix state. Both branches of the
  // `latitude == invalidLocation` condition therefore run under test.
  //
  // NOT covered here, and deliberately not faked: that a real device actually
  // reaches the valid branch. `setAllDataAsync()` needs Geolocator + geocoding
  // + NTP; a stub would assert against itself. Device-verified instead -- see
  // the plan's Verification section.
  group('eventLocString', () {
    /// The valid-fix shape, values taken from the healthy DSL comparator in
    /// spec section 5A-1 (`admin-new-customer`).
    OtqState validFix() => OtqState()
      ..latitude = -6.32288744
      ..longitude = 106.66780365
      ..isoCountryCode = 'ID'
      ..postalCode = '15310'
      ..administrativeArea = 'Banten'
      ..locationStatus = 'true-location';

    test('the raw builder still emits the dummies -- blanking is what removes them',
        () {
      // Guards against a green run that would also pass if eventLocString were
      // a no-op: this asserts the INPUT is genuinely poisoned.
      final List<String> raw =
          getLocationString('', '', '', OtqState()).split(separator[1]);
      expect(raw[4], '888.8888888');
      expect(raw[5], '888.8888888');
      expect(raw[7], '88');
      expect(raw[15], 'No Gps');
    });

    test('no GPS: exactly 17 diamond fields, count unchanged by blanking', () {
      final int rawCount =
          getLocationString('', '', '', OtqState()).split(separator[1]).length;
      final int outCount = eventLocString(OtqState()).split(separator[1]).length;
      expect(rawCount, 17);
      expect(outCount, 17);
    });

    test('no GPS: lat / lng / isoCountryCode slots are EMPTY', () {
      final List<String> parts = eventLocString(OtqState()).split(separator[1]);
      expect(parts[4], '');
      expect(parts[5], '');
      expect(parts[7], '');
      expect(parts[4], isNot(contains('888')));
      expect(parts[7], isNot('88'));
    });

    test('no GPS: the locationStatus slot still says "No Gps"', () {
      final List<String> parts = eventLocString(OtqState()).split(separator[1]);
      expect(parts[15], 'No Gps');
    });

    test('no GPS: the epoch slot is non-empty and numeric', () {
      final List<String> parts = eventLocString(OtqState()).split(separator[1]);
      expect(parts[1], isNotEmpty);
      expect(int.tryParse(parts[1]), isNotNull);
      expect(int.parse(parts[1]), greaterThan(1700000000000));
    });

    test('no GPS: reproduces the FIXED form of the live TASK-2026-000561 block',
        () {
      // Live (broken), spec section 5A-1:
      //   ◆1787886165028◆◆◆888.8888888◆888.8888888◆◆88◆◆◆◆◆◆◆◆No Gps
      // Expected after the fix: geo blanked, status kept, plus the trailing
      // GPS-accuracy slot (index 16, ◀17▶) which is EMPTY for a no-fix sensor —
      // 17 fields total, so the string now ends in a bare ◆.
      final OtqState sensor = OtqState()
        ..nowTime = DateTime.fromMillisecondsSinceEpoch(1787886165028);
      expect(
        eventLocString(sensor),
        '${separator[1]}1787886165028${separator[1] * 14}No Gps${separator[1]}',
      );
    });

    test('valid GPS: lat / lng / iso / status survive unchanged', () {
      final List<String> parts = eventLocString(validFix()).split(separator[1]);
      expect(parts.length, 17);
      expect(parts[4], '-6.32288744');
      expect(parts[5], '106.66780365');
      expect(parts[7], 'ID');
      expect(parts[15], 'true-location');
    });

    test('valid GPS: the string is byte-identical to getLocationString', () {
      // The blanking branch must not fire when the fix is real.
      final OtqState sensor = validFix();
      expect(
        eventLocString(sensor),
        getLocationString('', '', '', sensor),
      );
    });
  });

  // ── ROUND 2, gap 2: TaskCreateSubmit.writeEventSlots (the ★ block) ─────
  //
  // Extracted out of the State method _submit precisely so it IS unit
  // reachable: _submit itself is not (it awaits a native Firestore write).
  // The slot numbers are LITERALS here and LITERALS in production -- no shared
  // constant -- so this is a contract check against spec section 5A-2, not a
  // re-implementation of the production expression.
  group('TaskCreateSubmit.writeEventSlots', () {
    const String scr = 'CreateTaskSummaryR2';

    setUp(() {
      txfController.remove(scr);
    });

    /// Real it[] array built through the production assembler.
    List<Map<String, dynamic>> itArrayOf(int n) =>
        AdminCreateTaskSupport.draftToItArray(<DraftItem>[
          for (int i = 0; i < n; i++)
            DraftItem(ii: 'item-$i', itemName: 'Item $i', tx: 'deliver'),
        ]);

    String? slot(int p) => txfController[scr]?[p]?.finalData;

    void run({String vv = 'GDG-01', int items = 1}) =>
        TaskCreateSubmit.writeEventSlots(
          scrName: scr,
          kl: 'X4Qwc',
          kn: 'Kopi Kenangan',
          vv: vv,
          itArray: itArrayOf(items),
        );

    test('creates txfController[scrName] on a page that declared no positions',
        () {
      expect(txfController[scr], isNull);
      run();
      expect(txfController[scr], isNotNull);
    });

    test('writes kl / kn / vv to slots 11 / 12 / 13', () {
      run();
      expect(slot(11), 'X4Qwc');
      expect(slot(12), 'Kopi Kenangan');
      expect(slot(13), 'GDG-01');
    });

    test('slot 14 is the it[] line count, stringified', () {
      run(items: 3);
      expect(slot(14), '3');
    });

    test('an empty it[] yields "0", never "--" and never null', () {
      // _submit returns early on an empty draft (task_create_submit.dart:463),
      // so '0' cannot ship -- this pins the helper's own behaviour.
      run(items: 0);
      expect(slot(14), '0');
      expect(slot(14), isNot(emptyString));
    });

    test('adhoc "Tugaskan Nanti": slot 13 is PRESENT but empty', () {
      run(vv: '');
      expect(txfController[scr]!.containsKey(13), isTrue);
      expect(slot(13), '');
      expect(slot(13), isNot(emptyString));
    });

    test('controller.text mirrors finalData (saveSend reads either)', () {
      run();
      expect(txfController[scr]![11]!.controller.text, 'X4Qwc');
      expect(txfController[scr]![12]!.controller.text, 'Kopi Kenangan');
      expect(txfController[scr]![14]!.controller.text, '1');
    });

    test('slot 17 is NOT created -- tnm stays numberPos-owned', () {
      run();
      expect(txfController[scr]?[17], isNull);
    });

    test('an already-generated tnm in slot 17 survives untouched', () {
      txfControllerCheck(scr, 17);
      txfController[scr]![17]!.finalData = 'TASK-2026-000561';
      run();
      expect(slot(17), 'TASK-2026-000561');
    });

    test('reserved slots 15 and 16 stay untouched', () {
      run();
      expect(txfController[scr]?[15], isNull);
      expect(txfController[scr]?[16], isNull);
    });

    test('the exact slot set written is {11, 12, 13, 14}', () {
      run();
      // 0 is absent: writeEventSlots does NOT do emitSubmitEventRow's job.
      expect(txfController[scr]!.keys.toSet(), <int>{11, 12, 13, 14});
    });
  });
}
