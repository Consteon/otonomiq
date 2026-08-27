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

  // ── Location-QR code normalisation (real scannerLqrCode) ───────────
  //
  // The whole point of this helper is one off-by-one character: aecDecrypt
  // returns input[1:], so lqrVerify hands back 'l<sha1>' while location.li
  // stores '0l<sha1>'. Comparing them raw is what produced the "QR salah"
  // toast. The literals below are a REAL row read from
  // MobileTable/20342033315492/tables/84214220504259/location.
  group('scannerLqrCode (version-marker normalisation)', () {
    // Real li value from production, and what lqrVerify returns for it.
    const String storedLi = '0l7213c132e1b85e643db1c7e6713ebdcb33400bf3';
    const String verified = 'l7213c132e1b85e643db1c7e6713ebdcb33400bf3';

    test('re-adds the stripped version marker so it matches location.li', () {
      // MUTATION TARGET: drop the '0' prefix -> this is the shipped bug.
      expect(scannerLqrCode(verified), storedLi);
      expect(scannerLqrCode(verified).length, 42);
    });

    test('a value that already carries the marker is left alone', () {
      // MUTATION TARGET: prefix unconditionally -> yields '00l…', 43 chars.
      expect(scannerLqrCode(storedLi), storedLi);
    });

    test('errorString means the QR did not decrypt', () {
      // aecDecrypt yields this for any version that is not '0' or '2'.
      // MUTATION TARGET: drop the errorString guard -> returns '0Error'.
      expect(scannerLqrCode(errorString), '');
    });

    test('empty sentinel means the QR did not decrypt', () {
      // MUTATION TARGET: drop the `empty` guard -> returns '0--'.
      expect(scannerLqrCode(empty), '');
    });

    test('blank input yields empty, never a bare marker', () {
      // MUTATION TARGET: drop the isEmpty guard -> returns '0', which would
      // then be queried against li and could match a malformed row.
      expect(scannerLqrCode(''), '');
      expect(scannerLqrCode('   '), '');
    });

    test('surrounding whitespace is trimmed before the marker is added', () {
      expect(scannerLqrCode('  $verified  '), storedLi);
    });
  });

  // ── scannerMatchFromRows (>1-match ambiguity gate) ──────────────────
  //
  // The pure decision seam extracted out of scannerValidateQr so the D1 rule
  // is testable without Firestore. `needRow` is true exactly when the scanner
  // component carries a non-empty routeParams.
  group('scannerMatchFromRows (ambiguity gate)', () {
    // Shape taken from the real `location` collection: `li` is NOT unique --
    // five values appear twice across docs with different `sv`, which is the
    // whole reason this gate exists.
    final Map<String, dynamic> rowA = <String, dynamic>{
      'li': '0l7213c132e1b85e643db1c7e6713ebdcb33400bf3',
      'lk': '0l7213c132e1b85e643db1c7e6713ebdcb33400bf3-32639062303108',
      'ln': 'BSD Tech Center #18',
    };
    final Map<String, dynamic> rowB = <String, dynamic>{
      'li': '0l7213c132e1b85e643db1c7e6713ebdcb33400bf3',
      'lk': '0l7213c132e1b85e643db1c7e6713ebdcb33400bf3-84726150937261',
      'ln': 'Menara Palma #7',
    };

    test('no rows is not-found regardless of needRow', () {
      // MUTATION TARGET: flip `rows.isEmpty` to `rows.isNotEmpty` -> RED
      // (an empty result would report found and index rows.first).
      expect(scannerMatchFromRows(const <Map<String, dynamic>>[],
              needRow: false)
          .found,
          isFalse);
      final m = scannerMatchFromRows(const <Map<String, dynamic>>[],
          needRow: true);
      expect(m.found, isFalse);
      expect(m.row, isNull);
    });

    test('one row is found and carries the document', () {
      final m = scannerMatchFromRows(<Map<String, dynamic>>[rowA],
          needRow: true);
      expect(m.found, isTrue);
      // MUTATION TARGET: return `row: null` -> RED. Without the row the
      // routeParams tokens can never resolve and the feature is inert.
      expect(m.row, same(rowA));
      expect(m.row!['lk'], endsWith('-32639062303108'));
    });

    test('two rows FAIL when the caller needs the row (D1 / spec 2.2)', () {
      // Silently taking rowA picks an arbitrary site; for the meter feature
      // that is a reading billed to the wrong tenant.
      // MUTATION TARGET: drop the `rows.length > 1` guard -> RED (found true).
      final m = scannerMatchFromRows(<Map<String, dynamic>>[rowA, rowB],
          needRow: true);
      expect(m.found, isFalse);
      expect(m.row, isNull);
    });

    test('two rows still SUCCEED when the caller does not need the row', () {
      // D1: routeParams empty keeps today's first-match-wins semantics, so
      // DriverScanLogin is unaffected. (In that mode the query is limit(1) and
      // can never actually return two rows, but the gate must not fire.)
      // MUTATION TARGET: drop the `needRow &&` qualifier -> RED, which is what
      // would break every already-live scanner page.
      // MUTATION TARGET: return `rows.last` instead of `rows.first` -> RED.
      final m = scannerMatchFromRows(<Map<String, dynamic>>[rowA, rowB],
          needRow: false);
      expect(m.found, isTrue);
      expect(m.row, same(rowA));
    });

    test('the matched row keeps its __docId stamp', () {
      // _rowsFromDocs stamps `__docId` = d.id on every row it builds (same key
      // and shape as subscribeToMapCollection), so `docId◼{__docId}` copied
      // from a working LIST_CARD config resolves on a scanner too. This pins
      // the PASS-THROUGH half of that contract only -- the stamping itself
      // happens in a private function over live Firestore docs and is
      // observable on a device, not here.
      // MUTATION TARGET: have scannerMatchFromRows rebuild/filter the row
      // (e.g. return a copy stripped of `_`-prefixed keys) -> RED.
      final Map<String, dynamic> stamped = <String, dynamic>{
        ...rowA,
        '__docId': 'wq0kZ3mXlq9dK2ePab7T',
      };
      final m = scannerMatchFromRows(<Map<String, dynamic>>[stamped],
          needRow: true);
      expect(m.found, isTrue);
      expect(m.row!['__docId'], 'wq0kZ3mXlq9dK2ePab7T');
      // The doc's own fields are untouched alongside the stamp.
      expect(m.row!['lk'], endsWith('-32639062303108'));
    });
  });

  // ── scannerBlankRouteParams (stale bare-key guard) ──────────────────
  //
  // screenTx is MERGE-only (UpdateScreenTxAction never removes, and
  // DeleteAllScreenTxRowAction is never dispatched anywhere in lib/), so a
  // bare key from a PREVIOUS scan survives forever. This helper produces the
  // blank-out map dispatched before resolution, so an unresolvable key reads
  // as '' (destination renders EMPTY) instead of stale (destination renders
  // the previous point's data, silently WRONG).
  group('scannerBlankRouteParams (stale bare-key guard)', () {
    test('every declared key is blanked, none carries a value', () {
      // MUTATION TARGET: emit `p.value` instead of '' -> RED; the literal
      // '{lk}' would be dispatched as the key's value.
      expect(
          scannerBlankRouteParams(
              'lk\u{25FC}{lk}\u{2B58}li\u{25FC}{li}\u{2B58}ln\u{25FC}{ln}'),
          <String, dynamic>{'lk': '', 'li': '', 'ln': ''});
    });

    test('server-escaped separators are decoded before parsing', () {
      // The sheet may deliver ◼/⭘ as _25FC_/_u2B58_.
      // MUTATION TARGET: drop the autheniumDecode call -> RED; the whole
      // string becomes one unparsable pair and nothing is ever blanked.
      expect(scannerBlankRouteParams('lk_25FC_{lk}_u2B58_li_25FC_{li}'),
          <String, dynamic>{'lk': '', 'li': ''});
    });

    test('legacy bare _2B58_ is NOT decoded — pins a known landmine', () {
      // autheniumDecode (global.dart) decodes '_u2B58_' but its '_2B58_' line
      // is COMMENTED OUT, while '_25FC_' IS decoded. A sheet emitting the bare
      // legacy form therefore yields ONE pair, swallowing the rest. Config
      // authors must use the literal ⭘ or '_u2B58_'.
      // MUTATION TARGET: someone "fixing" autheniumDecode to decode '_2B58_'
      // -> RED here, which is the signal to re-check every routeParams config.
      expect(scannerBlankRouteParams('lk_25FC_{lk}_2B58_li_25FC_{li}').length,
          1);
    });

    test('empty / malformed input yields nothing to dispatch', () {
      expect(scannerBlankRouteParams(''), isEmpty);
      expect(scannerBlankRouteParams('   '), isEmpty);
      // No ◼ separator -> parseRouteParams skips the pair.
      expect(scannerBlankRouteParams('justakey'), isEmpty);
    });
  });
}
