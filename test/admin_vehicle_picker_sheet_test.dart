import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_vehicle_picker_sheet.dart';

void main() {
  // ── busyPoolCode ─────────────────────────────────────────────────────────

  group('VehiclePickerSheet.busyPoolCode', () {
    const String search = 'vv\u{25FC}{lv}\u{2B58}cst\u{25FC}custody_confirmed';

    test('empty assignBusySearch -> no pool (guard off)', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: '',
          assignBusyTable: '84214220504259//vehicle_check',
          appVid: '20342033315492',
        ),
        '',
      );
    });

    test('whitespace-only assignBusySearch -> no pool', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: '   ',
          assignBusyTable: '84214220504259//vehicle_check',
          appVid: '20342033315492',
        ),
        '',
      );
    });

    test('empty assignBusyTable -> no pool (caller uses own docs)', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: search,
          assignBusyTable: '',
          appVid: '20342033315492',
        ),
        '',
      );
    });

    test('vehicle_check table -> vid-scoped pool code', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: search,
          assignBusyTable: '84214220504259//vehicle_check',
          appVid: '20342033315492',
        ),
        '20342033315492/84214220504259/vehicle_check',
      );
    });

    test('bare docId -> defaults to the content subcollection', () {
      // parseTablePath("84214220504259") -> (docId, subColl: "content")
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: search,
          assignBusyTable: '84214220504259',
          appVid: '20342033315492',
        ),
        '20342033315492/84214220504259/content',
      );
    });

    test('pool code is vid-scoped -- same table, two tenants, two codes', () {
      // 84214220504259 lives under BOTH tenant vids in production; an
      // unscoped code would let one tenant read the other's stream.
      final String a = VehiclePickerSheet.busyPoolCode(
        assignBusySearch: search,
        assignBusyTable: '84214220504259//vehicle_check',
        appVid: '20342033315492',
      );
      final String b = VehiclePickerSheet.busyPoolCode(
        assignBusySearch: search,
        assignBusyTable: '84214220504259//vehicle_check',
        appVid: '60936087747650',
      );
      expect(a, isNot(b));
    });

    test('table with no docId -> no pool', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: search,
          assignBusyTable: '//vehicle_check',
          appVid: '20342033315492',
        ),
        '',
      );
    });

    test('whitespace around the table string is tolerated', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: search,
          assignBusyTable: '  84214220504259//vehicle_check  ',
          appVid: '20342033315492',
        ),
        '20342033315492/84214220504259/vehicle_check',
      );
    });
  });

  // ── isVehicleBusy over vehicle_check (the real "lagi jalan" source) ──────

  group('VehiclePickerSheet.isVehicleBusy -- vehicle_check pool', () {
    // Mirrors production shape: one opening doc per departure, cst walks
    // awaiting_custody -> custody_confirmed -> closed. Only custody_confirmed
    // means the vehicle is out on the road.
    final List<Map<String, dynamic>> checks = [
      {'vv': 'MBL-02', 'cty': 'opening', 'cst': 'custody_confirmed'},
      {'vv': 'MBL-02', 'cty': 'opening', 'cst': 'closed'},
      {'vv': 'MBL-02', 'cty': 'closing'},
      {'vv': 'MBL-01', 'cty': 'opening', 'cst': 'awaiting_custody'},
      {'vv': 'MBL-03', 'cty': 'opening', 'cst': 'closed'},
      {'vv': 'MBL-04', 'cty': 'opening', 'cst': 'cancelled'},
    ];

    const String busySearch = 'vv\u{25FC}{lv}\u{2B58}cty\u{25FC}opening'
        '\u{2B58}cst\u{25FC}custody_confirmed';

    test('custody_confirmed -> busy (on the road)', () {
      expect(
          VehiclePickerSheet.isVehicleBusy(checks, busySearch, 'MBL-02'), true);
    });

    test('awaiting_custody -> NOT busy (still at the warehouse)', () {
      expect(VehiclePickerSheet.isVehicleBusy(checks, busySearch, 'MBL-01'),
          false);
    });

    test('closed opening doc only -> NOT busy (trip finished)', () {
      expect(VehiclePickerSheet.isVehicleBusy(checks, busySearch, 'MBL-03'),
          false);
    });

    test('cancelled opening doc -> NOT busy', () {
      expect(VehiclePickerSheet.isVehicleBusy(checks, busySearch, 'MBL-04'),
          false);
    });

    test('vehicle with no check docs -> NOT busy', () {
      expect(VehiclePickerSheet.isVehicleBusy(checks, busySearch, 'MBL-99'),
          false);
    });

    test('server-encoded search (_25FC_ / _u2B58_) decodes and matches', () {
      expect(
        VehiclePickerSheet.isVehicleBusy(checks,
            'vv_25FC_{lv}_u2B58_cty_25FC_opening_u2B58_cst_25FC_custody_confirmed',
            'MBL-02'),
        true,
      );
    });

    test('empty pool -> NOT busy (fail-open, never blocks the whole fleet)', () {
      expect(VehiclePickerSheet.isVehicleBusy([], busySearch, 'MBL-02'), false);
    });
  });

  // ── The bug this fix closes ──────────────────────────────────────────────

  group('Regression: tst=on_delivery never matches real task data', () {
    // Production task docs for tenant 20342033315492 (read 2026-08-11): the
    // only live statuses are unassigned / assigned / completed / failed.
    // A vehicle out on the road keeps tst=assigned -- so a task-table guard
    // on on_delivery matches nothing while the vehicle IS driving.
    final List<Map<String, dynamic>> tasks = [
      {'vv': 'MBL-02', 'tst': 'assigned'}, // D 2134 FA -- shown as IN ROUTE
      {'vv': 'MBL-01', 'tst': 'assigned'},
      {'vv': 'MBL-01', 'tst': 'assigned'},
      {'vv': 'MBL-02', 'tst': 'completed'},
    ];

    const String oldSearch =
        'vv\u{25FC}{lv}\u{2B58}tst\u{25FC}on_delivery';

    test('old task-table search blocks nobody -- the reported bug', () {
      expect(VehiclePickerSheet.isVehicleBusy(tasks, oldSearch, 'MBL-02'),
          false);
      expect(VehiclePickerSheet.isVehicleBusy(tasks, oldSearch, 'MBL-01'),
          false);
    });

    test('assigned vehicles stay selectable under the new search too', () {
      // Spec section 3: loaded-but-not-departed must remain assignable. The
      // vehicle_check search never looks at tst, so this holds by construction.
      const String newSearch = 'vv\u{25FC}{lv}\u{2B58}cty\u{25FC}opening'
          '\u{2B58}cst\u{25FC}custody_confirmed';
      final List<Map<String, dynamic>> checks = [
        {'vv': 'MBL-01', 'cty': 'opening', 'cst': 'awaiting_custody'},
      ];
      expect(
          VehiclePickerSheet.isVehicleBusy(checks, newSearch, 'MBL-01'), false);
    });
  });

  // ── busySelfField (row's own field, mirrors PICKER_LIST) ────────────────

  group('VehiclePickerSheet.isVehicleSelfBusy', () {
    final Map<String, dynamic> held = {
      'lv': 'MBL-01',
      'ln': 'B 1234 XY',
      'dv': '80883888051110',
      'dn': 'Budi',
    };
    final Map<String, dynamic> free = {'lv': 'MBL-05', 'ln': 'F 5 GH'};

    test('field non-empty -> busy', () {
      expect(VehiclePickerSheet.isVehicleSelfBusy(held, 'dv'), true);
    });

    test('field absent on the row -> NOT busy', () {
      expect(VehiclePickerSheet.isVehicleSelfBusy(free, 'dv'), false);
    });

    test('field present but blank/whitespace -> NOT busy', () {
      expect(
          VehiclePickerSheet.isVehicleSelfBusy({'dv': '   '}, 'dv'), false);
    });

    test('empty field name -> guard off', () {
      expect(VehiclePickerSheet.isVehicleSelfBusy(held, ''), false);
    });

    test('non-string value counts as non-empty', () {
      expect(VehiclePickerSheet.isVehicleSelfBusy({'dv': 12345}, 'dv'), true);
    });

    test('★ dv is WIDER than "lagi jalan" -- documents the semantic gap', () {
      // MBL-01 has a driver (dv set) but its opening check is still
      // awaiting_custody: the app shows it as CUSTODY PENDING, not IN ROUTE.
      // The self-guard blocks it; the search guard does not. Config decides.
      const String search = 'vv\u{25FC}{lv}\u{2B58}cty\u{25FC}opening'
          '\u{2B58}cst\u{25FC}custody_confirmed';
      final checks = [
        {'vv': 'MBL-01', 'cty': 'opening', 'cst': 'awaiting_custody'},
      ];
      expect(VehiclePickerSheet.isVehicleBusy(checks, search, 'MBL-01'), false);
      expect(VehiclePickerSheet.isVehicleSelfBusy(held, 'dv'), true);
    });
  });

  group('VehiclePickerSheet.busyBadgeText', () {
    test('both parts -> joined with a middot', () {
      expect(
        VehiclePickerSheet.busyBadgeText(
            busyLabel: 'Lagi Jalan', selfLabel: 'Budi'),
        'Lagi Jalan \u{00B7} Budi',
      );
    });

    test('label only', () {
      expect(
        VehiclePickerSheet.busyBadgeText(busyLabel: 'Lagi Jalan', selfLabel: ''),
        'Lagi Jalan',
      );
    });

    test('self label only', () {
      expect(
        VehiclePickerSheet.busyBadgeText(busyLabel: '', selfLabel: 'Budi'),
        'Budi',
      );
    });

    test('neither -> empty (row disabled, no badge text)', () {
      expect(
        VehiclePickerSheet.busyBadgeText(busyLabel: '   ', selfLabel: ''),
        '',
      );
    });
  });

  // ── Backward compatibility ─────────────────────────────────────────────

  group('Backward compat (all config absent)', () {
    test('no search, no table -> no pool code', () {
      expect(
        VehiclePickerSheet.busyPoolCode(
          assignBusySearch: '',
          assignBusyTable: '',
          appVid: '20342033315492',
        ),
        '',
      );
    });

    test('no busySelfField -> self-guard off, vehicle with dv stays free', () {
      expect(
        VehiclePickerSheet.isVehicleSelfBusy(
            {'lv': 'MBL-01', 'dv': '80883888051110'}, ''),
        false,
      );
    });

    test('isVehicleBusy with empty search -> all vehicles free', () {
      final docs = [
        {'vv': 'MBL-02', 'cty': 'opening', 'cst': 'custody_confirmed'},
      ];
      expect(VehiclePickerSheet.isVehicleBusy(docs, '', 'MBL-02'), false);
    });

    test('unresolved row token -> NOT busy (guard degrades open, not shut)', () {
      // A typo'd token ({vv} instead of {lv}) leaves "{" unresolved;
      // countForRow bails to 0. Never fail-closed here -- that would block
      // every vehicle and stop dispatch entirely.
      final docs = [
        {'vv': 'MBL-02', 'cty': 'opening', 'cst': 'custody_confirmed'},
      ];
      expect(
        VehiclePickerSheet.isVehicleBusy(docs,
            'vv\u{25FC}{vv}\u{2B58}cst\u{25FC}custody_confirmed', 'MBL-02'),
        false,
      );
    });
  });
}
