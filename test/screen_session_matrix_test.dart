// test/screen_session_matrix_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/screen_session.dart';
import 'package:otonomiq/screen_session_entries.dart';

void main() {
  setUp(() {
    ScreenSession.resetForTest();
    registerAllScreenSessionEntries();
  });

  test('Phase 2 matrix: every entry has the expected policy', () {
    final snap = ScreenSession.registrySnapshot;

    // ── nav:screen, rebuild:screen ───────────────────────────────────────
    _expectEntry(snap, 'CustodyCountList.countStore',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'CustodyReveal.editState',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'ItemExecutionList.executionStore',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'ItemExecutionSubmit.writing',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'WhatsAppSend.sentState',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'PayoutList.selectionStore',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'ListActionCard.inflight',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    // Phase 2 flips (were nav:none in Phase 1):
    _expectEntry(snap, 'TaskItemBuilder.lastPublishedKl',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskCreateSubmit.writing',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'NotaCreateSubmit.writing',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'CustodyEventSubmit.writing',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskFeedList.flatSearch',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'CustomerOutstandingList.searchText',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen);

    // ── nav:all ──────────────────────────────────────────────────────────
    _expectEntry(snap, 'GroupPicker.stores',
        nav: NavPolicy.all, rebuild: RebuildPolicy.screen);
    // Phase 2 flip (was nav:none in Phase 1):
    _expectEntry(snap, 'TablePicker.selectionStore',
        nav: NavPolicy.all, rebuild: RebuildPolicy.screen);

    // ── nav:screen, rebuild:none ─────────────────────────────────────────
    _expectEntry(snap, 'ExecutorDesignateCard.o1State',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    _expectEntry(snap, 'NfcReader.collectorState',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    _expectEntry(snap, 'SignaturePad.writeState',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    // Phase 2 new entries:
    _expectEntry(snap, 'ItemCardDetail.screenStatus',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    _expectEntry(snap, 'ItemCardDetail.currentRow',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    // DIGIT_PAD's verdict-sheet raise latch. rebuild:none for the SignaturePad
    // reason — a background readSettings refresh must not make a dismissed
    // sheet pop back up (§4c rule 3).
    _expectEntry(snap, 'DigitPad.sheetRaised',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    // DIGIT_PAD's serial-verdict memo (the OCR key + its answer). Same pair of
    // policies for the same pair of reasons: a different meter is a different
    // verdict (nav:screen), and a background readSettings refresh must not
    // re-run ML Kit or re-raise the sheet the officer dismissed (rebuild:none).
    _expectEntry(snap, 'DigitPad.serialMemo',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);

    // ── nav:none, rebuild:screen (NOT flipped — documented reasons) ──────
    _expectEntry(snap, 'ApproverStickyBar.configs',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'DriverHomeState',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskManifestList.expandState',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'AssetStockList.activeTab',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);

    // ── Persistent ───────────────────────────────────────────────────────
    _expectEntry(snap, 'AdminCreateTaskSupport.drafts',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen,
        persistent: true);

    // ── Completeness check ───────────────────────────────────────────────
    expect(snap.length, 27,
        reason: 'expected 27 registered entries (Phase 2: +2 ItemCardDetail, '
            '+1 DigitPad.sheetRaised, +1 DigitPad.serialMemo)');
  });
}

void _expectEntry(
  Map<String, ({NavPolicy nav, RebuildPolicy rebuild, bool persistent})> snap,
  String name, {
  required NavPolicy nav,
  required RebuildPolicy rebuild,
  bool persistent = false,
}) {
  expect(snap.containsKey(name), true,
      reason: '$name not found in registry');
  final e = snap[name]!;
  expect(e.nav, nav, reason: '$name nav');
  expect(e.rebuild, rebuild, reason: '$name rebuild');
  expect(e.persistent, persistent, reason: '$name persistent');
}
