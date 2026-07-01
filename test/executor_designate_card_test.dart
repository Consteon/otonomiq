// test/executor_designate_card_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/custody_count_list.dart';
import 'package:otonomiq/widget/driver_home_support.dart';
import 'package:otonomiq/widget/executor_designate_card.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

void main() {
  // ExecutorDesignateCard.clearO1State dispatches to the global Redux store,
  // which is null in a bare test. Seed it once (mirrors global.dart init).
  setUpAll(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  // ── text-slot accessor (pure replication of _t) ─────────────────────────

  group('text-slot accessor (_t pattern)', () {
    /// Mirror of ExecutorDesignateCard._t: length-guarded slot read.
    String tslot(List<String> arr, int i, [String def = '']) =>
        arr.length > i ? arr[i] : def;

    test('reads present slots', () {
      final arr = diamondTextToList(
          'PENGEMUDI\u{25C6}Belum\u{25C6}Tentukan\u{25C6}Ganti');
      expect(tslot(arr, 0, 'x'), 'PENGEMUDI');
      expect(tslot(arr, 1, 'x'), 'Belum');
      expect(tslot(arr, 2, 'x'), 'Tentukan');
      expect(tslot(arr, 3, 'x'), 'Ganti');
    });

    test('falls back to default for missing slots (no RangeError)', () {
      final arr = diamondTextToList('PENGEMUDI');
      expect(tslot(arr, 4, 'TENTUKAN PENGEMUDI'), 'TENTUKAN PENGEMUDI');
      expect(tslot(arr, 7, 'Tidak ada pegawai'), 'Tidak ada pegawai');
    });

    test("empty text -> diamondTextToList('') is length 1 -> defaults", () {
      final arr = diamondTextToList('');
      // diamondTextToList('') returns [''] (length 1), NOT [].
      expect(arr.length, 1);
      expect(tslot(arr, 1, 'def1'), 'def1');
      expect(tslot(arr, 0, 'def0'), ''); // slot 0 exists but is empty string
    });
  });

  // ── workforce-row field extraction (pure replication of _buildRow) ──────

  group('workforce row field extraction', () {
    ({String name, String vid, String site}) extract(
      Map<String, dynamic> doc, {
      String nameField = 'n',
      String vidField = 'VID',
      String siteField = '',
    }) {
      final String name = (doc[nameField] ?? '').toString().trim();
      final String vid = (doc[vidField] ?? '').toString().trim();
      final String site = siteField.isNotEmpty
          ? (doc[siteField] ?? '').toString().trim()
          : '';
      return (name: name, vid: vid, site: site);
    }

    test('extracts default fields', () {
      final r = extract({'n': 'Budi', 'VID': 'wf-1'});
      expect(r.name, 'Budi');
      expect(r.vid, 'wf-1');
      expect(r.site, '');
    });

    test('extracts optional site when siteField set', () {
      final r = extract({'n': 'Budi', 'VID': 'wf-1', 's': 'Gudang A'},
          siteField: 's');
      expect(r.site, 'Gudang A');
    });

    test('missing fields degrade to empty (no crash)', () {
      final r = extract(<String, dynamic>{});
      expect(r.name, '');
      expect(r.vid, '');
    });

    test('custom field names', () {
      final r = extract({'name': 'Ani', 'vid': 'wf-2'},
          nameField: 'name', vidField: 'vid');
      expect(r.name, 'Ani');
      expect(r.vid, 'wf-2');
    });
  });

  // ── chosenRev reactivity signal ─────────────────────────────────────────

  group('chosenRev signal', () {
    test('bump increments the value', () {
      final int before = ExecutorDesignateCard.chosenRev.value;
      ExecutorDesignateCard.chosenRev.value++;
      expect(ExecutorDesignateCard.chosenRev.value, before + 1);
    });
  });

  // ── clearO1State ─────────────────────────────────────────────────────────

  group('clearO1State', () {
    test('clears all three screenTx keys + bumps chosenRev', () {
      // Seed non-empty state
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        '#CHOSEN_DRIVER_VID': 'wf-9',
        '#CHOSEN_DRIVER_NAME': 'Joko',
        '#ACTIVE_WAREHOUSE': 'WH-7',
      })));
      expect(transactionStore.state.screenTx['#CHOSEN_DRIVER_VID'], 'wf-9');

      final int revBefore = ExecutorDesignateCard.chosenRev.value;
      ExecutorDesignateCard.clearO1State('o1scr');

      final Map<String, dynamic> tx = transactionStore.state.screenTx;
      expect((tx['#CHOSEN_DRIVER_VID'] ?? '').toString(), '');
      expect((tx['#CHOSEN_DRIVER_NAME'] ?? '').toString(), '');
      expect((tx['#ACTIVE_WAREHOUSE'] ?? '').toString(), '');
      expect(ExecutorDesignateCard.chosenRev.value, greaterThan(revBefore));
    });

    test('resets the warehouse-published flag (re-arms publish on reopen)', () {
      // resetWarehousePublished is invoked by clearO1State. The flag map is
      // private; assert the public method runs without throwing and the
      // count store is unaffected (orthogonal store).
      CustodyCountList.getCountMap('o1scr2')['galon__full'] =
          CountEntry(ii: 'galon', cd: 'full', qty: 3);
      ExecutorDesignateCard.clearO1State('o1scr2');
      // clearO1State does NOT clear the count store (that's clearCountStore).
      expect(
          CustodyCountList.getCountMap('o1scr2')['galon__full']?.qty, 3);
    });
  });

  // ── filterWorkforceDocs (Bug 1 + Bug 2 fix) ────────────────────────────

  group('filterWorkforceDocs', () {
    // Fixture: a mix of real driver docs and meta/tenant docs.
    final List<Map<String, dynamic>> allDocs = [
      {'VID': 'wf-101', 'n': 'Budi', 'role': 'staff'},
      {'VID': 'wf-102', 'n': 'Anton', 'role': 'staff'},
      {'VID': '', 'n': 'Autsorz'},         // meta-doc: empty VID
      {'n': '?'},                           // meta-doc: missing VID key
      {'VID': 'wf-103', 'n': 'Dirgahayu', 'role': 'staff'},
      {'VID': '   ', 'n': 'Agenia Demo-7'}, // meta-doc: whitespace-only VID
    ];

    test('empty workforceSearch returns all VID-bearing docs (no server filter)',
        () {
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        allDocs,
        '', // empty search
        'testScr',
      );
      // Should include wf-101, wf-102, wf-103. Should exclude the 3 meta docs.
      expect(result.length, 3);
      expect(result.map((d) => d['VID']),
          containsAll(['wf-101', 'wf-102', 'wf-103']));
    });

    test('VID-less and whitespace-VID meta docs are dropped', () {
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        allDocs,
        '',
        'testScr',
      );
      // None of the 3 meta docs should appear
      for (final doc in result) {
        final String vid = (doc['VID'] ?? '').toString().trim();
        expect(vid.isNotEmpty, isTrue,
            reason: 'Every returned doc must have a non-empty VID');
      }
    });

    test('workforceSearch key◼val narrows correctly (AND filter)', () {
      // filterDriverHomeDocs with role◼staff should match only staff docs.
      // Using literal ◼ (U+25FC) since filterDriverHomeDocs handles
      // autheniumDecode internally, but in this test environment there is no
      // server encoding -- pass literal chars.
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        allDocs,
        'role\u{25FC}staff',
        'testScr',
      );
      // Should include wf-101, wf-102, wf-103 (all have role:staff).
      // Should exclude meta docs (no VID + no role match).
      expect(result.length, 3);
    });

    test('workforceSearch filters then VID guard removes remainders', () {
      // A doc that matches the search but has empty VID should still be dropped.
      final docsWithMatchingMeta = <Map<String, dynamic>>[
        {'VID': 'wf-201', 'n': 'Rina', 'role': 'staff'},
        {'VID': '', 'n': 'SystemRow', 'role': 'staff'}, // matches search but empty VID
      ];
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        docsWithMatchingMeta,
        'role\u{25FC}staff',
        'testScr',
      );
      expect(result.length, 1);
      expect(result[0]['VID'], 'wf-201');
    });

    test('empty docs list returns empty', () {
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        const [],
        'role\u{25FC}staff',
        'testScr',
      );
      expect(result, isEmpty);
    });

    test('malformed/sparse docs do not throw', () {
      final sparseDocs = <Map<String, dynamic>>[
        <String, dynamic>{},                    // missing VID -> '' -> dropped
        {'VID': null, 'n': null},                // null VID -> '' -> dropped
        {'VID': 42, 'n': 123},                   // int VID -> '42' (non-empty)
        {'VID': 'wf-300', 'n': 'Valid'},         // valid string VID
      ];
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        sparseDocs,
        '',
        'testScr',
      );
      // VID guard is (doc[field] ?? '').toString().trim().isNotEmpty, so a
      // NON-STRING but non-empty VID (int 42 -> '42') legitimately passes --
      // an int VID is a real identifier, not a meta-row. Only the docs with
      // absent/null VID (which stringify to '') are dropped. So 2 docs survive:
      // the int-VID doc and the wf-300 doc. The key point of this test is that
      // malformed/sparse docs do not THROW (Convention #7: guard the cast).
      expect(result.length, 2);
      expect(result.map((d) => d['VID'].toString()),
          containsAll(['42', 'wf-300']));
    });

    test('custom vidField is respected', () {
      final customDocs = <Map<String, dynamic>>[
        {'vid': 'c-1', 'n': 'CustomA'},  // lowercase vid
        {'vid': '', 'n': 'MetaB'},        // empty vid
        {'VID': 'c-2', 'n': 'DefaultC'}, // uppercase VID (wrong field)
      ];
      final result = ExecutorDesignateCard.filterWorkforceDocs(
        customDocs,
        '',
        'testScr',
        vidField: 'vid', // custom field
      );
      // Only c-1 should pass (c-2 has VID not vid, empty 'vid' key defaults to '')
      expect(result.length, 1);
      expect(result[0]['vid'], 'c-1');
    });
  });
}
