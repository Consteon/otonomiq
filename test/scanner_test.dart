import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/scanner_validate.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/scanner.dart';

void main() {
  // ── Slot parser tests (real scannerSlot from scanner.dart) ─────────
  //
  // These exercise the REAL exported scannerSlot function.
  // They validate the length-guard pattern that prevents per-tenant crashes.

  group('scannerSlot (diamondTextToList + length guard)', () {
    test('full text: all 9 slots populated', () {
      final input =
          'Title${separator[1]}Subtitle${separator[1]}Scan QR'
          '${separator[1]}Berhasil${separator[1]}OK'
          '${separator[1]}QR salah${separator[1]}QR tidak cocok'
          '${separator[1]}Scan Lagi${separator[1]}Batal';
      final slots = diamondTextToList(input);
      expect(slots.length, 9);
      expect(scannerSlot(slots, 0, 'Scan'), 'Title');
      expect(scannerSlot(slots, 1, ''), 'Subtitle');
      expect(scannerSlot(slots, 2, 'Scan QR'), 'Scan QR');
      expect(scannerSlot(slots, 3, 'Berhasil'), 'Berhasil');
      expect(scannerSlot(slots, 4, 'OK'), 'OK');
      expect(scannerSlot(slots, 5, 'QR salah'), 'QR salah');
      expect(scannerSlot(slots, 6, 'QR tidak cocok'), 'QR tidak cocok');
      expect(scannerSlot(slots, 7, 'Scan Lagi'), 'Scan Lagi');
      expect(scannerSlot(slots, 8, 'Batal'), 'Batal');
    });

    test('sparse text: only 2 slots -- dialog slots fall to defaults', () {
      final input = 'My Title${separator[1]}My Subtitle';
      final slots = diamondTextToList(input);
      expect(slots.length, 2);
      expect(scannerSlot(slots, 0, 'Scan'), 'My Title');
      expect(scannerSlot(slots, 1, ''), 'My Subtitle');
      expect(scannerSlot(slots, 2, 'Scan QR'), 'Scan QR');
      expect(scannerSlot(slots, 3, 'Berhasil'), 'Berhasil');
      expect(scannerSlot(slots, 4, 'OK'), 'OK');
      expect(scannerSlot(slots, 5, 'QR salah'), 'QR salah');
      expect(scannerSlot(slots, 6, 'QR tidak cocok'), 'QR tidak cocok');
      expect(scannerSlot(slots, 7, 'Scan Lagi'), 'Scan Lagi');
      expect(scannerSlot(slots, 8, 'Batal'), 'Batal');
    });

    test('empty text: all slots fall to defaults, no RangeError', () {
      final slots = diamondTextToList('');
      // diamondTextToList('') yields [''] (one empty element), because the
      // codebase 'empty' sentinel is '--' not '', so the JSON splitter runs on
      // '' and produces ['']. scannerSlot must still return defaults: index 0
      // exists but is empty -> fallback; index 8 is out of range -> fallback.
      expect(slots, ['']);
      expect(scannerSlot(slots, 0, 'Scan'), 'Scan');
      expect(scannerSlot(slots, 1, ''), '');
      expect(scannerSlot(slots, 8, 'Batal'), 'Batal');
    });

    test('single slot: only title', () {
      final slots = diamondTextToList('Just Title');
      expect(slots.length, 1);
      expect(scannerSlot(slots, 0, 'Scan'), 'Just Title');
      expect(scannerSlot(slots, 1, ''), '');
    });

    test('trailing empty slots: preserved but guarded', () {
      final input =
          'Title${separator[1]}${separator[1]}Camera Label';
      final slots = diamondTextToList(input);
      expect(slots.length, 3);
      expect(scannerSlot(slots, 0, 'Scan'), 'Title');
      // slot 1 is empty string from diamondTextToList
      expect(scannerSlot(slots, 1, 'fallback'), 'fallback');
      expect(scannerSlot(slots, 2, 'Scan QR'), 'Camera Label');
    });

    test('slot with empty value uses fallback', () {
      // A slot that parses to empty string should return fallback
      final slots = ['Title', '', 'Camera'];
      expect(scannerSlot(slots, 1, 'default-sub'), 'default-sub');
    });
  });

  // ── Search-field parser tests (real scannerSearchField) ────────────
  //
  // NEW in round 4. Exercises the REAL exported scannerSearchField function.
  // Validates single-field extraction and edge cases.

  group('scannerSearchField (search field parser)', () {
    test('single field: returns trimmed field name', () {
      expect(scannerSearchField('VID'), 'VID');
    });

    test('single field with whitespace: trims', () {
      expect(scannerSearchField('  VID  '), 'VID');
    });

    test('multi-field with star separator: returns first field only', () {
      expect(scannerSearchField('VID★status'), 'VID');
    });

    test('multi-field with spaces around star: trims both', () {
      expect(scannerSearchField('  VID ★ status ★ name'), 'VID');
    });

    test('empty string: returns empty', () {
      expect(scannerSearchField(''), '');
    });

    test('whitespace only: returns empty', () {
      expect(scannerSearchField('   '), '');
    });

    test('star only: returns empty (no field before star)', () {
      // '★' split gives ['', 'xxx'] or just [''] -- first.trim() = ''
      expect(scannerSearchField('★status'), '');
    });

    test('field name with no star: returned as-is', () {
      expect(scannerSearchField('employeeCode'), 'employeeCode');
    });
  });

  // ── scannerTableCode tests (NEW round 7) ──────────────────────────
  //
  // Exercises the REAL exported scannerTableCode function from
  // scanner_validate.dart. This is the single source of truth for the
  // #TABLE<code> key derivation. Both the initState subscribe and
  // scannerVidInWorkforce call it, so correctness here guarantees key
  // alignment (the round-7 bug was a missing table load, not a mismatch,
  // but this helper exists to PREVENT a future mismatch).

  group('scannerTableCode (table code derivation)', () {
    test('plain table name: returned as-is', () {
      // 'vtl.workforce' has no encoded chars and no // subcollection.
      // normalizeTableName is a no-op, autheniumDecode is a no-op.
      expect(scannerTableCode('vtl.workforce'), 'vtl.workforce');
    });

    test('empty string: returns empty', () {
      expect(scannerTableCode(''), '');
    });

    test('whitespace only: returns trimmed empty', () {
      // normalizeTableName trims first (global2.dart).
      // autheniumDecode('') returns '' (not null).
      expect(scannerTableCode('   '), '');
    });

    test('table name with encoded chars: decoded', () {
      // _25FC_ = ◼ (black medium square, U+25FC)
      // autheniumDecode replaces _25FC_ with ◼
      expect(scannerTableCode('vtl_25FC_workforce'), 'vtl◼workforce');
    });

    test('subcollection with //: normalized', () {
      // normalizeTableName splits on '//' and calls getDocumentName.
      // For a simple name like 'sub', getDocumentName returns 'sub'.
      expect(scannerTableCode('docId//sub'), contains('docId/'));
    });
  });

  // ── Widget render / scan-flow / decrypt / validation / table-load tests: NOT included ──
  //
  // Round 3 replaced the static decorative viewport with a live
  // MobileScanner widget. Pumping Scanner in flutter_test triggers a
  // MissingPluginException from the mobile_scanner method channel
  // (no camera platform in test). getVidUQR (crypto/secret) is not
  // testable without the gitignored auth_crypto.dart. findData and
  // scannerVidInWorkforce read transactionStore (global singleton).
  // subscribeToTable (round 7) is a Firestore side-effect (not unit-testable).
  // The following are on-device-QA-only:
  //
  //   - Live camera renders inside rounded viewport card
  //   - Corner bracket + scan-line overlays visible on camera feed
  //   - Title/subtitle display below card from slots
  //   - Auto-detect fires _onScanDetected on valid barcode
  //   - QR GATE: component['qr']=='uqr' -> decrypt path; absent/other -> plain path
  //   - DECRYPT (uqr): encrypted URL QR -> getVidUQR -> VID int
  //   - DECRYPT-FAIL (uqr): vid == -1 -> "tidak dikenal" snackbar + rescan
  //   - PLAIN (no qr / other): raw scan string IS vidStr -> continues to store+compare
  //   - PLAIN-EMPTY: raw scan trims to empty -> "tidak dikenal" snackbar + rescan
  //   - STORE: #has_user_login = vidStr dispatched (both paths)
  //   - TABLE PRE-LOAD (round 7): initState fires subscribeToTable with
  //       scannerTableCode(component['table']) -- verify devPrint
  //       "subscribeTable => <code>" appears in debug console on mount;
  //       requires the JSON `table` to be the LOADABLE name (e.g.
  //       "vtl.workforce"), NOT a raw Firestore docId
  //   - COMPARE (local): workforce table loaded (#TABLE<code> non-null)
  //       -> findData finds VID -> success
  //       -> findData returns null -> NOT-FOUND -> clear #has_user_login + snackbar + rescan
  //   - COMPARE (fallback): workforce table NOT loaded (#TABLE<code> null)
  //       -> Firestore query finds VID -> success
  //       -> Firestore query returns false -> NOT-FOUND -> clear #has_user_login + snackbar + rescan
  //   - LOAD RACE (round 7): scan immediately after mount, before
  //       subscribeToTable completes -> #TABLE null -> Firestore fallback ->
  //       re-scan after table loads = success (self-recovering)
  //   - SUCCESS: SCAN_RESULT = vidStr, saveSend, slot-7 snackbar, routeStack+gotoRoute
  //   - #has_user_login stays set on success, cleared on not-found
  //   - saveSend enqueues history + SCAN_RESULT marker resolves
  //   - SnackBar success feedback (slot 7) and wrong-result feedback (slots 9/10)
  //   - routeStack.push + gotoRoute navigation (success only)
  //   - Permission-denied fallback renders retry inside card
  //   - Lean-tenant short/empty text: no crash, defaults render
  //   - Missing table/search fields: validation skipped, direct success
  //   - Offline: Firestore fallback throws -> caught -> not-found snackbar + rescan
}
