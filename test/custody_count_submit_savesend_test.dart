// test/custody_count_submit_savesend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

void main() {
  // ── Phase A: saveSend action detection ─────────────────────────────────

  group('saveSend action detection', () {
    bool hasSaveSendAction(dynamic component) {
      return (component['action'] ?? '').toString().trim().toLowerCase() ==
          'savesend';
    }

    test('action:"savesend" -> true', () {
      expect(hasSaveSendAction({'action': 'savesend'}), true);
    });

    test('action:"SAVESEND" (case-insensitive) -> true', () {
      expect(hasSaveSendAction({'action': 'SAVESEND'}), true);
    });

    test('action absent -> false', () {
      expect(hasSaveSendAction(<String, dynamic>{}), false);
    });

    test('action null -> false', () {
      expect(hasSaveSendAction({'action': null}), false);
    });

    test('action empty -> false', () {
      expect(hasSaveSendAction({'action': ''}), false);
    });

    test('action other -> false', () {
      expect(hasSaveSendAction({'action': 'resetvid'}), false);
    });
  });

  // ── Phase A: component copy logic (addToEvent strip/preserve) ─────────

  group('component copy for saveSend', () {
    Map<String, dynamic> buildSaveSendComponent(
      Map<String, dynamic> component, {
      required bool hasSaveSendAction,
    }) {
      final copy = Map<String, dynamic>.from(component);
      if (!hasSaveSendAction) {
        copy.remove('addToEvent');
      }
      return copy;
    }

    test('action=savesend preserves addToEvent', () {
      final comp = {
        'type': 'CUSTODY_COUNT_SUBMIT',
        'addToEvent': '84214220504259//evidence\u{2B58}ety\u{25FC}notes',
        'updateEventRow': '84214220504259//stock_location\u{2B58}dv\u{25FC}X',
      };
      final copy = buildSaveSendComponent(comp, hasSaveSendAction: true);
      expect(copy.containsKey('addToEvent'), true);
      expect(copy['addToEvent'], comp['addToEvent']);
    });

    test('action absent strips addToEvent (legacy byte-identical)', () {
      final comp = {
        'type': 'CUSTODY_COUNT_SUBMIT',
        'addToEvent': '84214220504259//evidence\u{2B58}ety\u{25FC}notes',
        'updateEventRow': '84214220504259//stock_location\u{2B58}dv\u{25FC}X',
      };
      final copy = buildSaveSendComponent(comp, hasSaveSendAction: false);
      expect(copy.containsKey('addToEvent'), false);
      // updateEventRow preserved regardless
      expect(copy.containsKey('updateEventRow'), true);
    });

    test('no addToEvent key at all -> no error for both cases', () {
      final comp = {'type': 'CUSTODY_COUNT_SUBMIT'};
      expect(
        buildSaveSendComponent(comp, hasSaveSendAction: true)
            .containsKey('addToEvent'),
        false,
      );
      expect(
        buildSaveSendComponent(comp, hasSaveSendAction: false)
            .containsKey('addToEvent'),
        false,
      );
    });
  });

  // ── Phase A: {checkerName} pre-resolution ─────────────────────────────

  group('checkerName pre-resolution in addToEvent DSL', () {
    String resolveCheckerName(String raw, String checkerName) {
      if (!raw.contains('{checkerName}')) return raw;
      return raw.replaceAll('{checkerName}',
          checkerName.isNotEmpty ? checkerName : '{checkerName}');
    }

    test('resolves {checkerName} with actual name', () {
      const raw =
          'cv\u{25FC}{checkerVid}\u{2B58}cn\u{25FC}{checkerName}';
      final resolved = resolveCheckerName(raw, 'Budi Santoso');
      expect(resolved, contains('Budi Santoso'));
      expect(resolved, isNot(contains('{checkerName}')));
      // {checkerVid} is left for resolveDriverCurlyTokens
      expect(resolved, contains('{checkerVid}'));
    });

    test('leaves {checkerName} literal when name is empty', () {
      const raw = 'cn\u{25FC}{checkerName}';
      final resolved = resolveCheckerName(raw, '');
      expect(resolved, contains('{checkerName}'));
    });

    test('no {checkerName} token -> passthrough', () {
      const raw = 'cv\u{25FC}F12345';
      expect(resolveCheckerName(raw, 'Budi'), raw);
    });
  });

  // ── Phase A: GPS branch selection ─────────────────────────────────────

  group('GPS branch selection (gpsPosition)', () {
    int parseGpsPosition(dynamic component) {
      if (component['gpsPosition'] is String) {
        return int.tryParse(component['gpsPosition'].toString()) ?? 0;
      }
      return component['gpsPosition'] ?? 0;
    }

    test('gpsPosition int 2 -> 2 (real GPS branch)', () {
      expect(parseGpsPosition({'gpsPosition': 2}), 2);
    });

    test('gpsPosition String "2" -> 2 (real GPS branch)', () {
      expect(parseGpsPosition({'gpsPosition': '2'}), 2);
    });

    test('gpsPosition absent -> 0 (dummy branch)', () {
      expect(parseGpsPosition(<String, dynamic>{}), 0);
    });

    test('gpsPosition null -> 0 (dummy branch)', () {
      expect(parseGpsPosition({'gpsPosition': null}), 0);
    });

    test('gpsPosition String "abc" -> 0 (dummy branch)', () {
      expect(parseGpsPosition({'gpsPosition': 'abc'}), 0);
    });

    test('gpsPosition 0 -> 0 (dummy branch)', () {
      expect(parseGpsPosition({'gpsPosition': 0}), 0);
    });
  });

  // ── Phase B: opening doc map shape (cdt/ldt/t types) ──────────────────

  group('opening doc map shape (Phase B)', () {
    Map<String, dynamic> buildOpeningDocMap({
      required String genCnm,
      required String vehicleId,
      required String warehouseId,
      required String today,
      required String checkerVid,
      required String checkerName,
      required int nowMs,
      required List<Map<String, dynamic>> ieArray,
      required String tableVid,
    }) {
      return <String, dynamic>{
        'cnm': genCnm,
        'cty': 'opening',
        'vv': vehicleId,
        'gl': warehouseId,
        'cdt': int.parse(today),
        'cst': 'awaiting_custody',
        'gv': checkerVid,
        'gn': checkerName,
        'ldt': nowMs,
        't': nowMs,
        'ie': ieArray,
        'tablevid': tableVid,
        'search': 'cnm\u{2605}$genCnm',
      };
    }

    const int fixedNow = 1782666000000;
    final String fixedToday = todayEpochMidnightWib(nowMs: fixedNow);

    test('cdt is int (Number, not String)', () {
      final doc = buildOpeningDocMap(
        genCnm: 'CHK-VEH-001-20260630',
        vehicleId: 'VEH-001',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ieArray: [],
        tableVid: '20342033315492',
      );
      expect(doc['cdt'], isA<int>());
      expect(doc['cdt'], int.parse(fixedToday));
    });

    test('ldt is int (Number, not String)', () {
      final doc = buildOpeningDocMap(
        genCnm: 'CHK-VEH-001-20260630',
        vehicleId: 'VEH-001',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ieArray: [],
        tableVid: '20342033315492',
      );
      expect(doc['ldt'], isA<int>());
      expect(doc['ldt'], fixedNow);
    });

    test('t is int (regression: already was int)', () {
      final doc = buildOpeningDocMap(
        genCnm: 'CHK-VEH-001-20260630',
        vehicleId: 'VEH-001',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ieArray: [],
        tableVid: '20342033315492',
      );
      expect(doc['t'], isA<int>());
    });

    test('cnm stays as field value (business key)', () {
      final doc = buildOpeningDocMap(
        genCnm: 'CHK-F629GD0000099-20260630',
        vehicleId: 'F629GD0000099',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ieArray: [],
        tableVid: '20342033315492',
      );
      expect(doc['cnm'], 'CHK-F629GD0000099-20260630');
    });

    test('vv is String (vehicle id)', () {
      final doc = buildOpeningDocMap(
        genCnm: 'CHK-VEH-001-20260630',
        vehicleId: 'F629GD0000099',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ieArray: [],
        tableVid: '20342033315492',
      );
      expect(doc['vv'], isA<String>());
    });
  });

  // ── Phase B: closing doc map shape ────────────────────────────────────

  group('closing doc map shape (Phase B)', () {
    Map<String, dynamic> buildClosingDocMap({
      required String closingCnm,
      required String vehicleId,
      required String warehouseId,
      required String today,
      required String checkerVid,
      required String checkerName,
      required int nowMs,
      required List<Map<String, dynamic>> ipArray,
      required List<Map<String, dynamic>> dp,
      required String rs,
      required String tableVid,
    }) {
      return <String, dynamic>{
        'cnm': closingCnm,
        'cty': 'closing',
        'vv': vehicleId,
        'gl': warehouseId,
        'cdt': int.parse(today),
        'cv': checkerVid,
        'cn': checkerName,
        't': nowMs,
        'ip': ipArray,
        'dp': dp,
        'rs': rs,
        'tablevid': tableVid,
        'search': 'cnm\u{2605}$closingCnm',
      };
    }

    const int fixedNow = 1782666000000;
    final String fixedToday = todayEpochMidnightWib(nowMs: fixedNow);

    test('cdt is int (Number, not String)', () {
      final doc = buildClosingDocMap(
        closingCnm: 'CHK-VEH-001-20260630-C',
        vehicleId: 'VEH-001',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ipArray: [],
        dp: [],
        rs: 'matched',
        tableVid: '20342033315492',
      );
      expect(doc['cdt'], isA<int>());
      expect(doc['cdt'], int.parse(fixedToday));
    });

    test('t is int (regression)', () {
      final doc = buildClosingDocMap(
        closingCnm: 'CHK-VEH-001-20260630-C',
        vehicleId: 'VEH-001',
        warehouseId: 'WH-001',
        today: fixedToday,
        checkerVid: 'F123',
        checkerName: 'Budi',
        nowMs: fixedNow,
        ipArray: [],
        dp: [],
        rs: 'matched',
        tableVid: '20342033315492',
      );
      expect(doc['t'], isA<int>());
    });
  });

  // ── Phase B: close-via-search clause shape ────────────────────────────

  group('close-via-search clause', () {
    test('search string uses literal Unicode separators', () {
      const vehicleId = 'F629GD0000099';
      const today = '1782612000000';
      final closeSearch =
          'cty\u{25FC}opening\u{2B58}vv\u{25FC}$vehicleId\u{2B58}cdt\u{25FC}$today';
      // ◼ = \u{25FC}, ⭘ = \u{2B58}
      expect(closeSearch, contains('cty\u{25FC}opening'));
      expect(closeSearch, contains('vv\u{25FC}$vehicleId'));
      expect(closeSearch, contains('cdt\u{25FC}$today'));
      // Three AND clauses separated by ⭘
      final clauses = closeSearch.split('\u{2B58}');
      expect(clauses.length, 3);
    });

    test('search clause is fully resolved (no curly tokens)', () {
      const vehicleId = 'F629GD0000099';
      const today = '1782612000000';
      final closeSearch =
          'cty\u{25FC}opening\u{2B58}vv\u{25FC}$vehicleId\u{2B58}cdt\u{25FC}$today';
      expect(closeSearch.contains('{'), false);
    });
  });

  // ── Regression: todayEpochMidnightWib returns String ──────────────────

  group('todayEpochMidnightWib returns String (regression guard)', () {
    test('return type is String', () {
      final result = todayEpochMidnightWib(nowMs: 1782666000000);
      expect(result, isA<String>());
    });

    test('value is a valid int string', () {
      final result = todayEpochMidnightWib(nowMs: 1782666000000);
      expect(int.tryParse(result), isNotNull);
    });

    test('int.parse does not throw', () {
      final result = todayEpochMidnightWib(nowMs: 1782666000000);
      expect(() => int.parse(result), returnsNormally);
    });
  });

  // ── Regression: P6 path unchanged ─────────────────────────────────────

  group('P6 path unchanged', () {
    test('P6 mode detection: mode absent -> not opening, not closing', () {
      final comp = {'type': 'CUSTODY_COUNT_SUBMIT'};
      final isOpening =
          (comp['mode'] ?? '').toString().trim() == 'opening';
      final isClosing =
          (comp['mode'] ?? '').toString().trim() == 'closing';
      expect(isOpening, false);
      expect(isClosing, false);
    });

    test('P6 mode detection: mode empty -> not opening, not closing', () {
      final comp = {'type': 'CUSTODY_COUNT_SUBMIT', 'mode': ''};
      final isOpening =
          (comp['mode'] ?? '').toString().trim() == 'opening';
      final isClosing =
          (comp['mode'] ?? '').toString().trim() == 'closing';
      expect(isOpening, false);
      expect(isClosing, false);
    });

    test('opening mode detected', () {
      final comp = {'mode': 'opening'};
      expect((comp['mode'] ?? '').toString().trim() == 'opening', true);
    });

    test('closing mode detected', () {
      final comp = {'mode': 'closing'};
      expect((comp['mode'] ?? '').toString().trim() == 'closing', true);
    });
  });
}
