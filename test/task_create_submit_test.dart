import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/task_create_submit.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  group('resolveWizardVehicle', () {
    test('draft vv non-empty -> returns draft vv (highest priority)', () {
      expect(
        TaskCreateSubmit.resolveWizardVehicle(
          draftVeh: {'vv': 'VEH-1', 'vn': 'B 1234 XY'},
          wizardKey: 'admin_create_task',
          screenTx: {'vv': 'STALE-VEH'},
          vvKey: 'vv',
        ),
        'VEH-1',
      );
    });

    test('draft null + wizardKey set -> empty (never screenTx fallback)', () {
      expect(
        TaskCreateSubmit.resolveWizardVehicle(
          draftVeh: null,
          wizardKey: 'admin_create_task',
          screenTx: {'vv': 'STALE-VEH'},
          vvKey: 'vv',
        ),
        '',
      );
    });

    test('draft vv empty + wizardKey set -> empty (adhoc path)', () {
      expect(
        TaskCreateSubmit.resolveWizardVehicle(
          draftVeh: {'vv': '', 'vn': ''},
          wizardKey: 'admin_create_task',
          screenTx: {'vv': 'STALE-VEH'},
          vvKey: 'vv',
        ),
        '',
      );
    });

    test('draft null + wizardKey empty -> screenTx fallback (legacy path)', () {
      expect(
        TaskCreateSubmit.resolveWizardVehicle(
          draftVeh: null,
          wizardKey: '',
          screenTx: {'vv': 'LEGACY-VEH'},
          vvKey: 'vv',
        ),
        'LEGACY-VEH',
      );
    });

    test('draft null + wizardKey empty + screenTx missing key -> empty', () {
      expect(
        TaskCreateSubmit.resolveWizardVehicle(
          draftVeh: null,
          wizardKey: '',
          screenTx: <String, dynamic>{},
          vvKey: 'vv',
        ),
        '',
      );
    });
  });

  group('resolveCustomerKl', () {
    test('draft kl non-empty wins over screenTx', () {
      expect(
        TaskCreateSubmit.resolveCustomerKl(
          draftCust: {'kl': 'CUST-1', 'kn': 'Toko Contoh Jaya'},
          screenTx: {'kl': 'STALE-CUST'},
          klKey: 'kl',
        ),
        'CUST-1',
      );
    });

    test('draft null -> screenTx fallback (NOT wizardKey-gated, unlike vv)',
        () {
      expect(
        TaskCreateSubmit.resolveCustomerKl(
          draftCust: null,
          screenTx: {'kl': 'TX-CUST'},
          klKey: 'kl',
        ),
        'TX-CUST',
      );
    });

    test('draft present but kl empty -> screenTx fallback', () {
      expect(
        TaskCreateSubmit.resolveCustomerKl(
          draftCust: {'kl': '', 'kn': ''},
          screenTx: {'kl': 'TX-CUST'},
          klKey: 'kl',
        ),
        'TX-CUST',
      );
    });

    test('draft null + screenTx missing key -> empty (gate stays closed)', () {
      expect(
        TaskCreateSubmit.resolveCustomerKl(
          draftCust: null,
          screenTx: <String, dynamic>{},
          klKey: 'kl',
        ),
        '',
      );
    });

    // Load-bearing: without trim, a whitespace-only screenTx kl is isNotEmpty,
    // the gate opens, and the write lands kl=' ' -> generateTnm(' ').
    test('whitespace-only screenTx kl trims to empty', () {
      expect(
        TaskCreateSubmit.resolveCustomerKl(
          draftCust: null,
          screenTx: {'kl': '   '},
          klKey: 'kl',
        ),
        '',
      );
    });

    test('honors a remapped klKey', () {
      expect(
        TaskCreateSubmit.resolveCustomerKl(
          draftCust: null,
          screenTx: {'kl': 'WRONG', 'clientId': 'RIGHT'},
          klKey: 'clientId',
        ),
        'RIGHT',
      );
    });
  });

  // ── adhocSkipTdt (spec (6) §3.2b REVISI) ──────────────────────────────
  //
  // The load-bearing case is the FIRST one: param absent must be FALSE, i.e.
  // adhoc still writes `tdt`. Flipping that default silently reintroduces the
  // live 2026-08-04 warehouse-blind bug (opening manifest matches on
  // `(vv, tdt)`), and it is not backfillable from the app. `_onSubmit` cannot
  // be pumped (internetConnected + Firestore), so this static is the only
  // reachable pin on the decision.
  group('resolveAdhocSkipTdt', () {
    test('param absent -> false (default: adhoc still writes tdt)', () {
      expect(TaskCreateSubmit.resolveAdhocSkipTdt(<String, dynamic>{}), isFalse);
    });

    test('empty / whitespace-only -> false', () {
      expect(
          TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': ''}), isFalse);
      expect(
          TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': '   '}), isFalse);
    });

    test("'true' -> true, any case, padded", () {
      expect(TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': 'true'}),
          isTrue);
      expect(TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': 'TRUE'}),
          isTrue);
      expect(TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': ' True '}),
          isTrue);
    });

    test("'1' -> true (spreadsheet checkbox shape)", () {
      expect(
          TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': '1'}), isTrue);
    });

    test('real bool true -> true (JSON may not be a string)', () {
      expect(
          TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': true}), isTrue);
    });

    test('anything else -> false (fail-safe: unknown value keeps tdt)', () {
      for (final dynamic v in <dynamic>['false', 'yes', 'ya', '0', 'null', 2]) {
        expect(TaskCreateSubmit.resolveAdhocSkipTdt({'adhocSkipTdt': v}),
            isFalse,
            reason: 'unrecognized "$v" must not skip tdt');
      }
    });
  });

  // Full 2x2 of the decision that actually reaches the doc. Both conjuncts get
  // their own failing case: without the adhocSkipTdt one the param is dead,
  // without the adhocNoVehicle one every NORMAL task silently loses its date.
  group('resolveTaskTdt', () {
    const int today = 1782244800000;

    test('adhoc + skip enabled -> null (field omitted)', () {
      expect(
        TaskCreateSubmit.resolveTaskTdt(
            adhocNoVehicle: true, adhocSkipTdt: true, tdt: today),
        isNull,
      );
    });

    test('adhoc + skip disabled -> tdt written (the default path)', () {
      expect(
        TaskCreateSubmit.resolveTaskTdt(
            adhocNoVehicle: true, adhocSkipTdt: false, tdt: today),
        today,
      );
    });

    test('normal task + skip enabled -> tdt STILL written', () {
      expect(
        TaskCreateSubmit.resolveTaskTdt(
            adhocNoVehicle: false, adhocSkipTdt: true, tdt: today),
        today,
        reason: 'adhocSkipTdt must never touch a task that has a vehicle',
      );
    });

    test('normal task + skip disabled -> tdt written', () {
      expect(
        TaskCreateSubmit.resolveTaskTdt(
            adhocNoVehicle: false, adhocSkipTdt: false, tdt: today),
        today,
      );
    });
  });

  // ── build() enabled-gate + label (widget pump) ────────────────────────
  //
  // Closes review I1: the `enabled` gate and `enabledLabel` have no automated
  // coverage. Deleting `hasCustomer &&` or the vehicleOptional ternary both
  // pass CI green without these tests.
  //
  // Harness: transactionStore + appCodeController seeded once in setUpAll
  // (mirrors driver_home_support_test.dart). Component carries no
  // `table`/`warehouseTable` -> _subscribeStockLocation tp stays null ->
  // subscribeToMapCollection never called -> no Firebase initialization.
  group('build() enabled gate + label', () {
    final diamond = separator[1]; // ◆ Black diamond — separator for diamondTextToList
    const wk = 'pump_wk';
    const scr = 'pump_scr';

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
      // getTableVid(null) reads appCodeController.applicationTableVid (a late
      // global — assigned only in globalInit, not in flutter_test). Assign
      // directly to avoid LateInitializationError in resolveAppVid/initState.
      // Mirrors driver_home_support_test.dart W1 setup.
      appCodeController = AppCodeController()..applicationTableVid = 99999;
    });

    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
      TaskCreateSubmit.resetWriting(scr);
    });

    // ── Wizard-state seed helpers ──
    void seedCustomer() => AdminCreateTaskSupport.setCustomer(wk,
        kl: 'CUST-1', kn: 'Toko Test', al: '');
    void seedVehicle() =>
        AdminCreateTaskSupport.setVehicle(wk, vv: 'VEH-1', vn: 'B 1234 XY');
    void seedItem() => AdminCreateTaskSupport.getDraft(wk)
        .add(DraftItem(ii: 'ITM-1', itemName: 'Barang Test', tx: 'drop'));

    // 5-segment text: all slots populated including slot[4]
    String fiveSlots() =>
        'Buat Task & Assign${diamond}Lengkapi data dulu${diamond}Gagal membuat task${diamond}Data item kosong${diamond}Simpan Tanpa Kendaraan';

    Widget buildSut({String? unassignedStatus, String? textOverride}) =>
        MaterialApp(
          home: Scaffold(
            body: TaskCreateSubmit(
              component: <String, dynamic>{
                'wizardKey': wk,
                if (unassignedStatus != null)
                  'unassignedStatus': unassignedStatus,
                'text': textOverride ?? fiveSlots(),
                // No 'table'/'warehouseTable': parseTablePath('') returns docId=''
                // -> tp stays null -> subscribeToMapCollection never called
              },
              scrName: scr,
              lPad: 0,
              tPad: 0,
              rPad: 0,
              bPad: 0,
            ),
          ),
        );

    // Reads the rendered Text label from inside the ElevatedButton.
    // isWriting=false (reset in setUp) so the child is Text, not a spinner.
    String labelText(WidgetTester tester) {
      final text = tester.widget<Text>(find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byType(Text),
      ));
      return text.data ?? '';
    }

    // (a) LOAD-BEARING: vehicleOptional + no vehicle + customer + items
    // -> enabled, slot[4] label. Reverting the vehicleOptional ternary to
    // unconditional unassignedStatus.isNotEmpty breaks this.
    testWidgets(
      '(a) vehicleOptional + no vehicle + customer + items -> enabled, slot[4]',
      (tester) async {
        seedCustomer();
        seedItem();
        await tester.pumpWidget(buildSut(unassignedStatus: 'assigned'));
        await tester.pump();
        expect(labelText(tester), 'Simpan Tanpa Kendaraan');
        final btn =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(btn.onPressed, isNotNull); // enabled
        expect(
          btn.style?.backgroundColor?.resolve(const <WidgetState>{}),
          const Color(0xFF2563EB), // AdminTierColors.okAction
        );
      },
    );

    // (b) LOAD-BEARING: deleting `hasCustomer &&` from the gate flips this
    // from disabled to enabled. This is the exact regression I1 warns about.
    testWidgets(
      '(b) vehicleOptional + no vehicle + NO customer -> disabled [validates hasCustomer &&]',
      (tester) async {
        // Customer deliberately NOT seeded -> resolveCustomerKl returns ''
        // -> hasCustomer = false -> enabled must be false regardless of items
        seedItem();
        await tester.pumpWidget(buildSut(unassignedStatus: 'assigned'));
        await tester.pump();
        expect(labelText(tester), 'Lengkapi data dulu');
        final btn =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(btn.onPressed, isNull); // disabled
      },
    );

    // (c) unassignedStatus absent -> vehicleOptional = false -> vehicle required
    // even with customer + items. Existing configs are unaffected by round 3/4.
    testWidgets(
      '(c) unassignedStatus unset + no vehicle + customer + items -> disabled',
      (tester) async {
        seedCustomer();
        seedItem();
        // unassignedStatus NOT passed -> key absent -> vehicleOptional = false
        await tester.pumpWidget(buildSut());
        await tester.pump();
        expect(labelText(tester), 'Lengkapi data dulu');
        final btn =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(btn.onPressed, isNull); // disabled: no vehicle and not optional
      },
    );

    // (d) 4-segment text -> slot[4] absent -> _t(4, _t(0,...)) degrades to
    // slot[0]. Byte-identical behaviour vs today on existing 4-segment configs.
    testWidgets(
      '(d) 4-segment text + vehicleOptional + no vehicle -> slot[4] degrades to slot[0]',
      (tester) async {
        seedCustomer();
        seedItem();
        final fourSeg =
            'Buat Task & Assign${diamond}Lengkapi data dulu${diamond}Gagal${diamond}Kosong';
        await tester.pumpWidget(
            buildSut(unassignedStatus: 'assigned', textOverride: fourSeg));
        await tester.pump();
        // vehicleOptional && !hasVehicle -> _t(4, _t(0, 'Buat Task & Assign'))
        // _textArray.length = 4, 4 > 4 is false -> returns default _t(0,...) = 'Buat Task & Assign'
        expect(labelText(tester), 'Buat Task & Assign');
        final btn =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(btn.onPressed, isNotNull); // still enabled
      },
    );

    // (e) Trailing-empty 5th segment -> _t(4,...) returns '' -> BLANK label.
    // Review Info I2: known pre-existing weakness of the shared _t() idiom.
    // This test pins CURRENT behaviour; fixing _t() to treat empty-as-absent
    // would turn this red and signal the intentional semantic change.
    testWidgets(
      '(e) trailing-empty 5th segment -> blank label [I2 known behavior]',
      (tester) async {
        seedCustomer();
        seedItem();
        // Trailing ◆ with no content: diamondTextToList yields 5th element = ''
        final trailingEmpty =
            'Buat Task & Assign${diamond}Lengkapi data dulu${diamond}Gagal${diamond}Kosong$diamond';
        await tester.pumpWidget(buildSut(
            unassignedStatus: 'assigned', textOverride: trailingEmpty));
        await tester.pump();
        // _textArray[4] = '' -> _t(4, _t(0,...)) returns '' -> enabledLabel = ''
        // Button IS enabled; the blank label is the I2 defect.
        expect(labelText(tester), '');
        final btn =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(btn.onPressed, isNotNull); // enabled despite blank label
      },
    );

    // (f) vehicleOptional + vehicle present -> hasVehicle=true ->
    // (vehicleOptional && !hasVehicle) = false -> slot[0] assigned-path label.
    testWidgets(
      '(f) vehicleOptional + vehicle present + customer + items -> enabled, slot[0]',
      (tester) async {
        seedCustomer();
        seedVehicle();
        seedItem();
        await tester.pumpWidget(buildSut(unassignedStatus: 'assigned'));
        await tester.pump();
        expect(labelText(tester), 'Buat Task & Assign');
        final btn =
            tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        expect(btn.onPressed, isNotNull);
        expect(
          btn.style?.backgroundColor?.resolve(const <WidgetState>{}),
          const Color(0xFF2563EB), // AdminTierColors.okAction
        );
      },
    );
  });
}
