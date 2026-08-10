// test/screen_session_matrix_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/screen_session.dart';
import 'package:otonomiq/screen_session_entries.dart';

void main() {
  setUp(() {
    ScreenSession.resetForTest();
    registerAllScreenSessionEntries();
  });

  test('Phase 1 matrix: every entry has the expected policy', () {
    final snap = ScreenSession.registrySnapshot;

    // ── Both lists (nav:screen, rebuild:screen) ──────────────────────────
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

    // ── nav:all (GroupPicker) ────────────────────────────────────────────
    _expectEntry(snap, 'GroupPicker.stores',
        nav: NavPolicy.all, rebuild: RebuildPolicy.screen);

    // ── clearData-only (nav:screen, rebuild:none) ────────────────────────
    _expectEntry(snap, 'ExecutorDesignateCard.o1State',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    _expectEntry(snap, 'NfcReader.collectorState',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);
    _expectEntry(snap, 'SignaturePad.writeState',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.none);

    // ── buildPage-only (nav:none, rebuild:screen) ────────────────────────
    _expectEntry(snap, 'ApproverStickyBar.configs',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'DriverHomeState',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskManifestList.expandState',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'CustodyEventSubmit.writing',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskItemBuilder.lastPublishedKl',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskCreateSubmit.writing',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'NotaCreateSubmit.writing',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TaskFeedList.flatSearch',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'CustomerOutstandingList.searchText',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'AssetStockList.activeTab',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);
    _expectEntry(snap, 'TablePicker.selectionStore',
        nav: NavPolicy.none, rebuild: RebuildPolicy.screen);

    // ── Persistent ───────────────────────────────────────────────────────
    // persistent:true with default nav/rebuild (screen/screen). The values
    // are inert (persistent entries are skipped by both navReset and
    // pageBuild) but the matrix pins what is actually stored.
    _expectEntry(snap, 'AdminCreateTaskSupport.drafts',
        nav: NavPolicy.screen, rebuild: RebuildPolicy.screen,
        persistent: true);

    // ── Completeness check ───────────────────────────────────────────────
    // If a new entry is added to production but not to this test, this fails.
    expect(snap.length, 23,
        reason: 'expected 23 registered entries (22 non-persistent + 1 persistent)');
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
