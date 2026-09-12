// test/time_presence_last_action_test.dart
//
// Tests for TIME_PRESENCE v2 `lastAction` (slug: time-presence-last-action).
//
// Two layers, because they prove different things.
//
//   1. PURE unit tests (no pump, no binding, no Firebase) for the five
//      top-level helpers in time_presence.dart plus the two new named
//      parameters on driver_home_support.dart's pickNewestDoc. Every config
//      shape and every resolve rule of dev-spec §3.2 is exercised directly.
//
//   2. WIDGET-PUMP tests for the widget's own wiring — WHICH branch renders
//      WHAT. That is the half a pure test structurally cannot reach: the
//      search-empty fail-closed guard and the "no Obx when lastAction is
//      absent" contract live in build(), not in a helper, and a pure test
//      asserts a composition it wrote itself.
//
// Harness (no Firebase, no globalInit):
//   * The first five pump fixtures OMIT `table` deliberately, to stay focused
//     on the resolve rules: _subscribe() returns at its tableDocId guard, _code
//     stays '' and the Obx reads mapTableContent[''] -- seeded per test,
//     removed in tearDown so rows do not leak into the suite. Production never
//     writes mapTableContent['']: subscribeToMapCollection returns early on an
//     empty tableDocId and every caller builds a non-empty
//     '$appVid/$docId/$subColl'.
//   * Those two fixtures also swap `debugPrint` (a seam, not a mock -- see
//     menu_badge_test.dart:376) to observe the subscription itself: devPrint
//     routes to debugPrint (global.dart:2096) and subscribeToMapCollection's
//     catch logs the full path. Rendered output alone cannot see whether a
//     subscription was opened on the v1 path, so "zero query" needs the probe.
//   * The last two fixtures DO set `table`, because omitting it is not
//     necessary and leaves _subscribe's body (resolveAppVid, the _code
//     construction, the subscribeToMapCollection call) executed by no test in
//     the repo. It stays Firebase-free: `dynamic firestoreDb;`
//     (global.dart:523) is plain null in a test, NOT `late`, and mobileTable /
//     mobileTableCollection are const (global.dart:542-543), so the one
//     statement outside the try cannot throw. firestoreDb.collection(path)
//     therefore raises NoSuchMethodError INSIDE subscribeToMapCollection's own
//     try, whose catch swallows it and un-registers the code
//     (table_repository.dart:2183-2186) -- so a later test may re-subscribe the
//     same code.
//   * `vidtable` IS set: resolveAppVid otherwise falls through to getTableVid,
//     which reads the `late` global appCodeController.
//   * transactionStore is null in a bare test and filterDriverHomeDocs reads
//     it on every build, so it is built in setUpAll.
//   * ★ TIMERS. _LiveCounter starts a Timer.periodic(1s) whenever a check-in
//     time is present, so pumpAndSettle NEVER settles and the test dies at
//     teardown with "A Timer is still pending".
//     - The round-1 group below keeps text slot 5 EMPTY and never configures
//       `checkIn`, so no timer runs and pumpAndSettle is safe there.
//     - The round-2 `checkIn` group DOES produce a check-in (that is R2-1:
//       the ledger time feeds the Durasi counter), so it uses a single
//       `tester.pumpWidget(...)` and then disposeTree() -- never
//       pumpAndSettle. Same recipe the v4 variant tests use, and it also
//       stops _V4Track's repeating pulse controller.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart'; // mapTableContent
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/driver_home_support.dart'; // pickNewestDoc
import 'package:otonomiq/widget/time_presence.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart'; // DevToolsStore

const String kDiamond = '\u{25C6}'; // ◆
const String kBlackSquare = '\u{25FC}'; // ◼
const String kBigCircle = '\u{2B58}'; // ⭘ — the AND separator filterByMultiClause splits on
const String kOwnCv = '87544551624342';
const String kOtherCv = '11111111111111';

/// A local DateTime on TODAY's calendar day. Local by construction, so a
/// millisecondsSinceEpoch round-trip renders the same clock string in every
/// timezone -- which is why the assertions below can use literals.
DateTime todayAt(int h, int m) {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m);
}

DateTime yesterdayAt(int h, int m) {
  final DateTime n = DateTime.now().subtract(const Duration(days: 1));
  return DateTime(n.year, n.month, n.day, h, m);
}

/// Epoch ms as a String -- the production shape of `t` (a Firestore
/// stringValue, verified against MobileTable/20342033315492/.../event).
String msStr(DateTime d) => d.millisecondsSinceEpoch.toString();

void main() {
  // ── parseLastAction ──────────────────────────────────────────────────

  group('parseLastAction', () {
    test('absent / blank / -- / [TOKEN] means v1: null, zero query', () {
      // Catches: the back-compat path breaking. Every already-deployed
      // TIME_PRESENCE has no `lastAction` and must keep rendering slot 6.
      // '--' is the global `empty` sentinel (global.dart:364); '[LASTACTION]'
      // is the unreplaced sheet template placeholder from dev-spec §3.
      expect(parseLastAction(''), isNull);
      expect(parseLastAction('   '), isNull);
      expect(parseLastAction('--'), isNull);
      expect(parseLastAction('[LASTACTION]'), isNull);
    });

    test('the Home lastAction config parses to five positions, filter empty', () {
      final LastActionSpec? c = parseLastAction('t${kDiamond}desc${kDiamond}t${kDiamond}HH:mm');
      expect(c, isNotNull);
      expect(c!.sortField, 't');
      expect(c.descending, isTrue);
      expect(c.valueField, 't');
      expect(c.format, 'HH:mm');
      expect(c.filter, isEmpty); // position 5 absent = no extra WHERE clause
    });

    test('the Home checkIn config: asc plus a position-5 filter', () {
      // Dev spec (1) §3.1 example, and the config the builder still owes:
      // `checkIn:"t◆asc◆t◆HH:mm◆ty◼clock-in"`.
      final LastActionSpec? c = parseLastAction(
          't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm${kDiamond}ty${kBlackSquare}clock-in');
      expect(c, isNotNull);
      expect(c!.sortField, 't');
      expect(c.descending, isFalse); // asc = FIRST event of today
      expect(c.valueField, 't');
      expect(c.format, 'HH:mm');
      expect(c.filter, 'ty${kBlackSquare}clock-in');
    });

    test('position 5 absent, empty or blank all mean "no extra filter"', () {
      // Catches: an unguarded p[4] (RangeError on every 4-position config that
      // is already deployed today -- a per-tenant crash), and a filter default
      // of anything other than ''.
      expect(parseLastAction('t${kDiamond}desc${kDiamond}t${kDiamond}HH:mm')!.filter, '');
      expect(parseLastAction('t${kDiamond}desc${kDiamond}t${kDiamond}HH:mm$kDiamond')!.filter, '');
      expect(parseLastAction('t${kDiamond}desc${kDiamond}t${kDiamond}HH:mm$kDiamond   ')!.filter, '');
      expect(parseLastAction('t${kDiamond}desc')!.filter, '');
      expect(parseLastAction('ts')!.filter, '');
    });

    test('position 5 keeps a multi-clause chain intact', () {
      // The ⭘ chain is handed to filterByMultiClause verbatim; splitting it
      // here would need a second evaluator.
      final LastActionSpec? c = parseLastAction(
          't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm'
          '${kDiamond}ty${kBlackSquare}clock-in${kBigCircle}p${kBlackSquare}home');
      expect(c!.filter, 'ty${kBlackSquare}clock-in${kBigCircle}p${kBlackSquare}home');
    });

    test('the r2 sheet placeholders also mean v1, zero query', () {
      // Dev spec (1) §3 renamed the sheet placeholders. They are SHEET names --
      // the JSON keys stay `lastAction` / `checkIn` -- but an unreplaced one
      // must still parse to null.
      expect(parseLastAction('[LASTACTIONCFG]'), isNull);
      expect(parseLastAction('[CHECKINCFG]'), isNull);
      expect(parseLastAction('[LASTACTION]'), isNull); // the r1 name, still gated
    });

    test('2 of 4 positions: valueField falls back to sortField, format to HH:mm', () {
      // Catches: an unguarded p[2]/p[3] (RangeError -- a per-tenant crash on a
      // lean sheet) and a valueField default of '' (which would blank the slot).
      final LastActionSpec? c = parseLastAction('t${kDiamond}desc');
      expect(c, isNotNull);
      expect(c!.sortField, 't');
      expect(c.descending, isTrue);
      expect(c.valueField, 't'); // NOT ''
      expect(c.format, 'HH:mm');
    });

    test('1 of 4 positions', () {
      final LastActionSpec? c = parseLastAction('ts');
      expect(c, isNotNull);
      expect(c!.sortField, 'ts');
      expect(c.descending, isTrue);
      expect(c.valueField, 'ts');
      expect(c.format, 'HH:mm');
    });

    test('blank positions take the documented defaults, not empty strings', () {
      final LastActionSpec? c =
          parseLastAction('$kDiamond$kDiamond$kDiamond HH:mm:ss ');
      expect(c, isNotNull);
      expect(c!.sortField, 't');
      expect(c.descending, isTrue);
      expect(c.valueField, 't');
      expect(c.format, 'HH:mm:ss');
    });

    test('sortDir: only a case-insensitive asc flips direction', () {
      // Catches: `descending = dir == 'desc'`, which would silently flip the
      // whole feature to ascending on 'DESC' or any typo.
      expect(parseLastAction('t${kDiamond}asc')!.descending, isFalse);
      expect(parseLastAction('t${kDiamond}ASC')!.descending, isFalse);
      expect(parseLastAction('t$kDiamond Asc ')!.descending, isFalse);
      expect(parseLastAction('t${kDiamond}desc')!.descending, isTrue);
      expect(parseLastAction('t${kDiamond}DESC')!.descending, isTrue);
      expect(parseLastAction('t${kDiamond}descending')!.descending, isTrue);
      expect(parseLastAction('t${kDiamond}xyz')!.descending, isTrue);
      expect(parseLastAction('t$kDiamond')!.descending, isTrue);
    });

    test('valueField may differ from sortField (sort by t, show ts)', () {
      final LastActionSpec? c =
          parseLastAction('t${kDiamond}desc${kDiamond}ts${kDiamond}HH:mm');
      expect(c!.sortField, 't');
      expect(c.valueField, 'ts');
    });
  });

  // ── pickNewestDoc: the two NEW named parameters ──────────────────────

  group('pickNewestDoc field/descending parameters', () {
    final Map<String, dynamic> a = {'id': 'a', 't': '100', 'u': '9'};
    final Map<String, dynamic> b = {'id': 'b', 't': '300', 'u': '5'};
    final Map<String, dynamic> c = {'id': 'c', 't': '200', 'u': '7'};

    test('defaults are unchanged: field t, descending', () {
      // Catches: a botched extension breaking the two existing call sites
      // (custody_discrepancy_list.dart:123, custody_confirmed_list.dart:216)
      // that still call pickNewestDoc(matched) with no named arguments.
      expect(pickNewestDoc([a, b, c]), same(b));
      expect(pickNewestDoc([]), isNull);
    });

    test('field selects a different sort column', () {
      expect(pickNewestDoc([a, b, c], field: 'u'), same(a));
    });

    test('descending: false picks the smallest', () {
      expect(pickNewestDoc([a, b, c], descending: false), same(a));
      expect(pickNewestDoc([a, b, c], field: 'u', descending: false), same(b));
    });

    test('ties keep the FIRST doc in list order, in both directions', () {
      // Catches: a `>=` / `<=` comparison, and any switch to List.sort --
      // Dart's sort is unstable and the live ledger already holds 86 docs.
      final Map<String, dynamic> t1 = {'id': 't1', 't': '500'};
      final Map<String, dynamic> t2 = {'id': 't2', 't': '500'};
      expect(pickNewestDoc([t1, t2]), same(t1));
      expect(pickNewestDoc([t2, t1]), same(t2));
      expect(pickNewestDoc([t1, t2], descending: false), same(t1));
    });

    test('all docs unparseable on the sort field: first doc, never null', () {
      // pickNewestDoc is UNCHANGED this round -- this pins the shared helper's
      // own contract, which two other widgets depend on.
      // (The r1 comment justified this with decision D5's fail-open day-guard.
      // D5 is REVOKED in r2: such a doc is now dropped by the day-SCOPE before
      // pickNewestDoc ever sees it -- see the pickLedgerDoc group below.)
      final Map<String, dynamic> x = {'id': 'x'};
      final Map<String, dynamic> y = {'id': 'y'};
      expect(pickNewestDoc([x, y], field: 'nope'), same(x));
    });
  });

  // ── composeLedgerSearch (dev spec (1) §3.1 position 5) ───────────────

  group('composeLedgerSearch', () {
    const String search = 'cv${kBlackSquare}87544551624342';
    const String filter = 'ty${kBlackSquare}clock-in';

    test('no filter -> the search is passed through unchanged', () {
      // The already-deployed 4-position config MUST keep behaving exactly as
      // it does today.
      expect(composeLedgerSearch(search, ''), search);
      expect(composeLedgerSearch(search, '   '), search);
    });

    test('a filter is AND-ed onto the search with ⭘', () {
      // ⭘ is what filterByMultiClause splits on (driver_home_support.dart:954),
      // so composing here means there is exactly ONE search evaluator.
      expect(composeLedgerSearch(search, filter), '$search$kBigCircle$filter');
    });

    test('a multi-clause filter is appended whole', () {
      expect(composeLedgerSearch(search, 'ty${kBlackSquare}clock-in${kBigCircle}p${kBlackSquare}home'),
          '$search${kBigCircle}ty${kBlackSquare}clock-in${kBigCircle}p${kBlackSquare}home');
    });

    test('empty search never grows a leading ⭘', () {
      // Unreachable in production (_searchBlocked gates first) but the helper
      // must be total: a leading ⭘ would be a silently unscoped query shape.
      expect(composeLedgerSearch('', filter), filter);
      expect(composeLedgerSearch('', ''), '');
    });

    test('both sides are trimmed', () {
      expect(composeLedgerSearch('  $search  ', '  $filter  '),
          '$search$kBigCircle$filter');
    });

    test('the LEGACY _2B58_ dialect is decoded to ⭘, on both inputs', () {
      // ★ W1. autheniumDecode (global.dart) handles `_u2B58_` and the legacy
      // `_25FC_`, but its `_2B58_` line is COMMENTED OUT at :1197. Position 5
      // is this widget's first field whose documented shape is a ⭘ chain, so a
      // server emitting the no-`u` dialect would hand filterByMultiClause ONE
      // clause valued `clock-in_2B58_p◼home`, match zero docs, and blank the
      // slot silently forever. Same local pass parseKeyedDsl already carries
      // (driver_home_support.dart:518-536).
      expect(
        composeLedgerSearch(search, 'ty${kBlackSquare}clock-in_2B58_p${kBlackSquare}home'),
        '$search${kBigCircle}ty${kBlackSquare}clock-in${kBigCircle}p${kBlackSquare}home',
      );
      // The pass covers `search` too, not just the new field.
      expect(
        composeLedgerSearch('cv${kBlackSquare}1_2B58_ty${kBlackSquare}x', ''),
        'cv${kBlackSquare}1${kBigCircle}ty${kBlackSquare}x',
      );
    });

    test('running the pass after autheniumDecode is safe: _u2B58_ is untouched',
        () {
      // The safety argument the fix rests on, executed rather than asserted in
      // prose: `_u2B58_` never CONTAINS `_2B58_` as a substring, so pass 2
      // cannot corrupt what pass 1 already decoded. Here pass 1 has already
      // turned `_u2B58_` into ⭘; a second pass must leave that ⭘ alone.
      expect(composeLedgerSearch(search, 'ty${kBlackSquare}a${kBigCircle}p${kBlackSquare}b'),
          '$search${kBigCircle}ty${kBlackSquare}a${kBigCircle}p${kBlackSquare}b');
      // And the literal escape text `_u2B58_` is not mangled into `_u⭘`.
      expect(composeLedgerSearch('a${kBlackSquare}_u2B58_', ''),
          'a${kBlackSquare}_u2B58_');
    });
  });

  // ── lastActionEpochMs ────────────────────────────────────────────────

  group('lastActionEpochMs', () {
    test('13-char epoch-ms String (the production shape of t)', () {
      final int ms = todayAt(9, 37).millisecondsSinceEpoch;
      expect(lastActionEpochMs(ms.toString()), ms);
      expect(lastActionEpochMs(' $ms '), ms);
    });

    test('int and double both read', () {
      final int ms = todayAt(9, 37).millisecondsSinceEpoch;
      expect(lastActionEpochMs(ms), ms);
      expect(lastActionEpochMs(ms.toDouble()), ms);
    });

    test('10-digit seconds epoch is upgraded to ms', () {
      // Dev-spec §12 risk: mixed detik/ms. notifNormalizeMs is the repo's
      // single answer; this pins the reuse.
      final int ms = todayAt(9, 37).millisecondsSinceEpoch;
      final int seconds = ms ~/ 1000;
      expect(lastActionEpochMs(seconds.toString()), seconds * 1000);
    });

    test('non-numeric and null are not timestamps', () {
      expect(lastActionEpochMs(null), isNull);
      expect(lastActionEpochMs(''), isNull);
      expect(lastActionEpochMs('07 Sep 2026 09:37:34'), isNull); // the `ts` shape
      expect(lastActionEpochMs('clock-in'), isNull); // the `ty` shape
    });

    test('small numbers are rejected, not printed as 1970', () {
      // Catches: dropping the plausibility band. valueField:"qt" with value 5
      // would otherwise render a clock time near 07:00.
      expect(lastActionEpochMs(5), isNull);
      expect(lastActionEpochMs('5'), isNull);
      expect(lastActionEpochMs(0), isNull);
      expect(lastActionEpochMs(-1), isNull);
    });

    test('absurd future values are rejected', () {
      expect(lastActionEpochMs('4102444800000'), isNull); // 2100-01-01
      expect(lastActionEpochMs('99999999999999'), isNull);
    });
  });

  // ── isSameLocalDay ───────────────────────────────────────────────────

  group('isSameLocalDay', () {
    test('today matches, yesterday does not', () {
      final DateTime now = DateTime(2026, 9, 8, 15, 0);
      expect(isSameLocalDay(DateTime(2026, 9, 8, 0, 0).millisecondsSinceEpoch, now), isTrue);
      expect(isSameLocalDay(DateTime(2026, 9, 8, 23, 59).millisecondsSinceEpoch, now), isTrue);
      expect(isSameLocalDay(DateTime(2026, 9, 7, 23, 59).millisecondsSinceEpoch, now), isFalse);
      expect(isSameLocalDay(DateTime(2026, 9, 9, 0, 0).millisecondsSinceEpoch, now), isFalse);
    });

    test('same day-of-month in another month or year does not match', () {
      // Catches: comparing `.day` only.
      final DateTime now = DateTime(2026, 9, 8, 15, 0);
      expect(isSameLocalDay(DateTime(2026, 8, 8, 15, 0).millisecondsSinceEpoch, now), isFalse);
      expect(isSameLocalDay(DateTime(2025, 9, 8, 15, 0).millisecondsSinceEpoch, now), isFalse);
    });
  });

  // ── formatLastActionValue ────────────────────────────────────────────

  group('formatLastActionValue', () {
    test('epoch renders in the device timezone with the given pattern', () {
      // Catches: a manual +7 offset (dev-spec §7.4) -- that would render 21:05.
      expect(formatLastActionValue(msStr(todayAt(14, 5)), 'HH:mm'), '14:05');
      expect(formatLastActionValue(todayAt(14, 5).millisecondsSinceEpoch, 'HH:mm'), '14:05');
    });

    test('a non-HH:mm pattern is honoured', () {
      expect(formatLastActionValue(msStr(todayAt(14, 5)), 'HH.mm'), '14.05');
    });

    test('non-epoch value is shown as-is and format is ignored', () {
      // Dev-spec §3.1 position 4: valueField:"ts" holds "07 Sep 2026 09:37:34".
      expect(formatLastActionValue('07 Sep 2026 09:37:34', 'HH:mm'),
          '07 Sep 2026 09:37:34');
      expect(formatLastActionValue('report-patrol', 'HH:mm'), 'report-patrol');
    });

    test('absent / blank / -- yields the empty string (caller shows placeholder)', () {
      expect(formatLastActionValue(null, 'HH:mm'), '');
      expect(formatLastActionValue('', 'HH:mm'), '');
      expect(formatLastActionValue('   ', 'HH:mm'), '');
      expect(formatLastActionValue('--', 'HH:mm'), '');
    });
  });

  // ── pickLedgerDoc: SCOPE to today, THEN pick (dev spec (1) §3.2.2) ────

  group('pickLedgerDoc', () {
    final LastActionSpec asc = parseLastAction(
        't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm')!;
    final LastActionSpec desc = parseLastAction(
        't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm')!;

    test('★ asc scopes to today BEFORE picking -- the r1 order was wrong', () {
      // THE regression test for dev spec (1) change C. Round 1 picked first and
      // day-guarded the winner: pickNewestDoc(descending: false) returned
      // YESTERDAY's 06:00 doc, the guard rejected it, and the Check-in slot was
      // `--:--` forever. Scope-then-pick returns today's FIRST event.
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(yesterdayAt(6, 0))},
        {'t': msStr(todayAt(9, 37))},
        {'t': msStr(todayAt(14, 5))},
      ];
      expect(pickLedgerDoc(docs, asc, DateTime.now())!['t'],
          msStr(todayAt(9, 37)));
    });

    test('a doc MISSING the sortField cannot win asc', () {
      // pickNewestDoc scores a missing field as 0 via `?? 0`, which beats every
      // real epoch under `descending: false` -- its own doc-comment records the
      // ceiling. The day-scope drops such a doc before the pick, which is the
      // whole reason driver_home_support.dart needs no change this round.
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(todayAt(9, 37))},
        {'id': 'no-t'},
      ];
      expect(pickLedgerDoc(docs, asc, DateTime.now())!['t'],
          msStr(todayAt(9, 37)));
    });

    test('desc: a future-dated doc is out of scope, not a poison pill', () {
      // The ONLY case where scope-then-pick differs from r1 under `desc`.
      // r1 blanked the whole slot; r2 ignores the bogus doc.
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(todayAt(9, 37))},
        {'t': msStr(DateTime.now().add(const Duration(days: 1)))},
      ];
      expect(pickLedgerDoc(docs, desc, DateTime.now())!['t'],
          msStr(todayAt(9, 37)));
    });

    test('nothing today -> null, in both directions', () {
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(yesterdayAt(6, 0))},
        {'t': msStr(yesterdayAt(18, 45))},
      ];
      expect(pickLedgerDoc(docs, asc, DateTime.now()), isNull);
      expect(pickLedgerDoc(docs, desc, DateTime.now()), isNull);
      expect(pickLedgerDoc(const [], desc, DateTime.now()), isNull);
    });

    test('an unreadable sortField is OUT OF SCOPE (r1 decision D5 revoked)', () {
      // D5 let a config typo fall through the guard and still print a value.
      // Under a day-SCOPE such a doc cannot be placed in "today" at all, and
      // keeping the escape would let `asc` return the oldest event of all time.
      final LastActionSpec typo = parseLastAction(
          'tt${kDiamond}desc${kDiamond}ts${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(todayAt(9, 37)), 'ts': '07 Sep 2026 09:37:34'},
      ];
      expect(pickLedgerDoc(docs, typo, DateTime.now()), isNull);
    });

    test('the scope reads sortField, not valueField', () {
      final LastActionSpec split = parseLastAction(
          't${kDiamond}desc${kDiamond}ts${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(todayAt(14, 5)), 'ts': '08 Sep 2026 14:05:00'},
      ];
      expect(pickLedgerDoc(docs, split, DateTime.now()), isNotNull);
    });

    test('a num-typed sortField is OUT of scope -- the two parsers are crossed',
        () {
      // ★ W2. The scope parses with lastActionEpochMs, which accepts a `num`
      // via `raw is num -> toInt()`. pickNewestDoc parses the SAME value with
      // `int.tryParse(d[field].toString().trim()) ?? 0`, and a Firestore
      // double stringifies with a `.0` tail that tryParse REJECTS -- so on the
      // epoch check alone the doc passes the scope and still scores 0, which
      // beats every real epoch under `asc`. Exactly the landmine
      // pickLedgerDoc's doc-comment claims is closed; the scope has to require
      // BOTH parses for that claim to be true.
      final List<Map<String, dynamic>> docs = [
        {'t': todayAt(9, 37).millisecondsSinceEpoch.toDouble()},
        {'t': msStr(todayAt(14, 5))},
      ];
      // Fixture sanity: the double really is a plausible epoch for the SCOPE's
      // reader and really is unparseable for the PICK's. If either of these
      // flips, the test above stops testing what it says it tests.
      expect(lastActionEpochMs(docs.first['t']), isNotNull);
      expect(int.tryParse(docs.first['t'].toString().trim()), isNull);

      expect(pickLedgerDoc(docs, asc, DateTime.now())!['t'],
          msStr(todayAt(14, 5)));
      // Alone it leaves NOTHING in scope, rather than winning by default.
      expect(pickLedgerDoc([docs.first], asc, DateTime.now()), isNull);
      // `desc` must not be weakened by the extra condition: the string doc won
      // before this round and still wins. (Not a mutant killer -- a
      // no-regression pin, because the double scored 0 under `desc` too.)
      expect(pickLedgerDoc(docs, desc, DateTime.now())!['t'],
          msStr(todayAt(14, 5)));
    });
  });

  // ── ledgerDocTime (R2-1: the Durasi counter's origin) ────────────────

  group('ledgerDocTime', () {
    final LastActionSpec cfg = parseLastAction(
        't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm')!;

    test('the winning doc sortField epoch, as a device-local DateTime', () {
      // Read from sortField, NOT from the formatted display string: `format`
      // may be `HH.mm`, or valueField may be the human-text `ts`.
      final DateTime ci = todayAt(7, 2);
      expect(ledgerDocTime({'t': msStr(ci)}, cfg), ci);
    });

    test('null doc or unreadable sortField -> null (no counter)', () {
      expect(ledgerDocTime(null, cfg), isNull);
      expect(ledgerDocTime({'id': 'no-t'}, cfg), isNull);
      expect(ledgerDocTime({'t': 'clock-in'}, cfg), isNull);
    });
  });

  // ── resolveLastActionText (dev spec (1) §3.2: SCOPE, then pick) ──────

  group('resolveLastActionText', () {
    final LastActionSpec cfg = parseLastAction(
        't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm')!;

    test('newest doc wins, not the first in the list', () {
      final List<Map<String, dynamic>> docs = [
        {'cv': kOwnCv, 't': msStr(todayAt(9, 37))},
        {'cv': kOwnCv, 't': msStr(todayAt(14, 5))},
        {'cv': kOwnCv, 't': msStr(todayAt(11, 20))},
      ];
      expect(resolveLastActionText(docs, cfg, DateTime.now()), '14:05');
    });

    test('rule 3: zero docs -> null (caller shows the placeholder)', () {
      expect(resolveLastActionText(const [], cfg, DateTime.now()), isNull);
    });

    test('rule 4: every doc is from yesterday -> null', () {
      // Dev-spec §11 acceptance: "Event kemarin doang -> slot tetap --:--".
      final List<Map<String, dynamic>> docs = [
        {'cv': kOwnCv, 't': msStr(yesterdayAt(9, 37))},
        {'cv': kOwnCv, 't': msStr(yesterdayAt(18, 45))},
      ];
      expect(resolveLastActionText(docs, cfg, DateTime.now()), isNull);
    });

    test('a future-dated doc is scoped OUT, so today\'s newest still wins', () {
      // ★ DELIBERATE INVERSION of the r1 test "rule 4 uses the newest doc".
      // r1 picked the (future) newest and let the guard blank the slot -> null.
      // r2 scopes first, so the bogus doc never enters the pick and the card
      // shows the real newest event of today. This is the ONLY behaviour
      // difference change C makes under `desc`, and it is an improvement:
      // a clock-skewed write must not blank a worker's card.
      final List<Map<String, dynamic>> docs = [
        {'cv': kOwnCv, 't': msStr(todayAt(9, 37))},
        {'cv': kOwnCv, 't': msStr(DateTime.now().add(const Duration(days: 1)))},
      ];
      expect(resolveLastActionText(docs, cfg, DateTime.now()), '09:37');
    });

    test('an unreadable sortField blanks the slot (r1 D5 fail-open REVOKED)', () {
      // ★ DELIBERATE INVERSION of the r1 test "D5: ... FAILS OPEN". Decision
      // R2-2: under a day-SCOPE a doc whose sortField is not a readable epoch
      // cannot be placed in "today", so it is simply out of scope. A blank is
      // a legitimate "no event today", not a data leak -- whereas keeping the
      // escape would let `asc` return the oldest event of all time.
      final LastActionSpec typo = parseLastAction(
          'tt${kDiamond}desc${kDiamond}ts${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> docs = [
        {'cv': kOwnCv, 't': msStr(todayAt(9, 37)), 'ts': '07 Sep 2026 09:37:34'},
      ];
      expect(resolveLastActionText(docs, typo, DateTime.now()), isNull);
    });

    test('day-SCOPE reads sortField, value comes from valueField', () {
      final LastActionSpec split = parseLastAction(
          't${kDiamond}desc${kDiamond}ts${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> today = [
        {'t': msStr(todayAt(14, 5)), 'ts': '08 Sep 2026 14:05:00'},
      ];
      final List<Map<String, dynamic>> old = [
        {'t': msStr(yesterdayAt(14, 5)), 'ts': '07 Sep 2026 14:05:00'},
      ];
      expect(resolveLastActionText(today, split, DateTime.now()),
          '08 Sep 2026 14:05:00');
      expect(resolveLastActionText(old, split, DateTime.now()), isNull);
    });

    test('winning doc has no valueField -> null', () {
      final LastActionSpec split = parseLastAction(
          't${kDiamond}desc${kDiamond}ts${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(todayAt(9, 37)), 'ts': '07 Sep 2026 09:37:34'},
        {'t': msStr(todayAt(14, 5))}, // newest, but no `ts`
      ];
      expect(resolveLastActionText(docs, split, DateTime.now()), isNull);
    });

    test('asc scopes to today, so yesterday can never win', () {
      // The same regression as the pickLedgerDoc group, one layer up: this is
      // the function the widget's lastAction path actually calls.
      final LastActionSpec ascCfg = parseLastAction(
          't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(yesterdayAt(6, 0))},
        {'t': msStr(todayAt(9, 37))},
        {'t': msStr(todayAt(14, 5))},
      ];
      expect(resolveLastActionText(docs, ascCfg, DateTime.now()), '09:37');
    });

    test('asc config picks the OLDEST doc of today', () {
      final LastActionSpec asc = parseLastAction(
          't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm')!;
      final List<Map<String, dynamic>> docs = [
        {'t': msStr(todayAt(14, 5))},
        {'t': msStr(todayAt(9, 37))},
      ];
      expect(resolveLastActionText(docs, asc, DateTime.now()), '09:37');
    });
  });

  // ── Widget wiring (pump) ─────────────────────────────────────────────

  group('TimePresence lastAction wiring (pump)', () {
    setUpAll(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    /// The subscription code the last two fixtures make the widget build:
    /// resolveAppVid -> 'V' (the literal `vidtable`), parseTablePath('D//event')
    /// -> ('D', 'event'), so _code == '$appVid/$tableDocId/$subColl'.
    const String kLiveCode = 'V/D/event';

    // mapTableContent is a GLOBAL RxMap: a leaked row poisons later tests in
    // the suite, not just this file. Both keys must go.
    tearDown(() {
      mapTableContent.remove('');
      mapTableContent.remove(kLiveCode);
    });

    // 8 ◆-segments, dev-spec §3 order. Slot 5 (check-in) is EMPTY on purpose:
    // a value there starts _LiveCounter's Timer.periodic and pumpAndSettle
    // would never settle. Slot 6 carries the v1 literal 11:38, slot 7 the
    // checkout (empty unless a test overrides it).
    String cardText({String lastActionLiteral = '11:38', String checkOut = ''}) =>
        <String>[
          'Absensi hari ini',
          'Absen Masuk',
          'Durasi',
          'Aksi terakhir',
          '--:--',
          '', // slot 5 check-in: EMPTY (no timer)
          lastActionLiteral, // slot 6
          checkOut, // slot 7
        ].join(kDiamond);

    Widget wrap(Map<String, dynamic> component, String scrName) => MaterialApp(
          home: Scaffold(
            body: TimePresence(
              key: UniqueKey(),
              component: component,
              scrName: scrName,
              single: true,
            ),
          ),
        );

    /// Ledger rows: own user at 09:37 and 14:05 today, another user at 18:45
    /// today. The OTHER user is deliberately the newest row overall, so a
    /// broken `cv` filter renders 18:45 and the test fails loudly.
    void seedLedger() => mapTableContent[''] = <Map<String, dynamic>>[
          {'cv': kOwnCv, 't': msStr(todayAt(9, 37)), '__docId': 'own-old'},
          {'cv': kOtherCv, 't': msStr(todayAt(18, 45)), '__docId': 'other'},
          {'cv': kOwnCv, 't': msStr(todayAt(14, 5)), '__docId': 'own-new'},
        ];

    testWidgets('no lastAction: v1 literal renders and the ledger is ignored',
        (WidgetTester tester) async {
      // Dev-spec §11: "lastAction kosong -> tampilan identik v1, nol query."
      // Catches: querying unconditionally -- that mutant renders 14:05.
      seedLedger();
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': '20342033315492',
        'search': 'cv$kBlackSquare$kOwnCv',
        'text': cardText(),
      }, 'tp_v1'));
      await tester.pumpAndSettle();

      expect(find.text('Aksi terakhir'), findsOneWidget); // fixture sanity
      expect(find.text('11:38'), findsOneWidget); // slot 6 literal
      expect(find.text('14:05'), findsNothing);
      expect(find.text('18:45'), findsNothing);
    });

    testWidgets(
        'lastAction set but search blank: placeholder, NOT the ledger and NOT '
        'the v1 literal', (WidgetTester tester) async {
      // The highest-value test in this file. filterDriverHomeDocs and
      // filterByMultiClause both RETURN EVERY DOC for an empty condition
      // (driver_home_support.dart:980, :931, :956), so without the widget-level
      // guard this renders another tenant user's 18:45 on this worker's card.
      // The second assertion kills the other tempting mistake -- falling back
      // to the v1 literal, which is the frozen number the config replaces.
      seedLedger();
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': '20342033315492',
        'lastAction': 't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm',
        'text': cardText(),
      }, 'tp_blocked'));
      await tester.pumpAndSettle();

      expect(find.text('Aksi terakhir'), findsOneWidget); // fixture sanity
      expect(find.text('18:45'), findsNothing); // no scope leak
      expect(find.text('14:05'), findsNothing); // no query at all
      expect(find.text('11:38'), findsNothing); // NOT the v1 literal
    });

    testWidgets('lastAction + search: newest OWN doc wins',
        (WidgetTester tester) async {
      seedLedger();
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': '20342033315492',
        'search': 'cv$kBlackSquare$kOwnCv',
        'lastAction': 't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm',
        'text': cardText(),
      }, 'tp_query'));
      await tester.pumpAndSettle();

      expect(find.text('14:05'), findsOneWidget); // own newest
      expect(find.text('09:37'), findsNothing); // own older
      expect(find.text('18:45'), findsNothing); // another user (newest overall)
      expect(find.text('11:38'), findsNothing); // v1 literal overridden
    });

    testWidgets('checkout wins over the ledger', (WidgetTester tester) async {
      // D3: slot 7 filled -> last action shows the no-data label, same as v1.
      seedLedger();
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': '20342033315492',
        'search': 'cv$kBlackSquare$kOwnCv',
        'lastAction': 't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm',
        'text': cardText(checkOut: '17:00'),
      }, 'tp_checkout'));
      await tester.pumpAndSettle();

      expect(find.text('Aksi terakhir'), findsOneWidget); // fixture sanity
      expect(find.text('14:05'), findsNothing);
      expect(find.text('18:45'), findsNothing);
    });

    testWidgets('a new ledger row repaints the slot without a rebuild',
        (WidgetTester tester) async {
      // Dev-spec §3.2.2 / §11: "slot berubah tanpa reload". Proves the Obx
      // dependency on the mapTableContent RxMap is actually registered --
      // the ONLY thing standing in for a Firestore snapshot listener under D1.
      // Two pumps in ONE testWidgets is deliberate here: Element reuse is
      // exactly what is under test, and only the DATA changes between pumps.
      seedLedger();
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': '20342033315492',
        'search': 'cv$kBlackSquare$kOwnCv',
        'lastAction': 't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm',
        'text': cardText(),
      }, 'tp_live'));
      await tester.pumpAndSettle();
      expect(find.text('14:05'), findsOneWidget); // fixture sanity

      mapTableContent[''] = <Map<String, dynamic>>[
        ...mapTableContent['']!,
        {'cv': kOwnCv, 't': msStr(todayAt(16, 20)), '__docId': 'own-newest'},
      ];
      await tester.pumpAndSettle();

      expect(find.text('16:20'), findsOneWidget);
      expect(find.text('14:05'), findsNothing);
    });

    testWidgets('table set: the ledger is read under the vid-scoped code',
        (WidgetTester tester) async {
      // Covers _subscribe's body, which the five fixtures above skip at the
      // `tp.tableDocId.isEmpty` guard. The vid prefix is the sole defence
      // against the live two-appVid `84214220504259/event` collision, and it is
      // only observable through the key the widget reads: drop `$appVid/` from
      // _code and the widget reads an absent key -> zero docs -> placeholder ->
      // RED. The decoy row under '' (the key the table-less fixtures use) makes
      // the test fail just as loudly if _code collapses to '' for any reason.
      mapTableContent[kLiveCode] = <Map<String, dynamic>>[
        {'cv': kOwnCv, 't': msStr(todayAt(14, 5)), '__docId': 'own-new'},
      ];
      mapTableContent[''] = <Map<String, dynamic>>[
        {'cv': kOwnCv, 't': msStr(todayAt(18, 45)), '__docId': 'decoy'},
      ];
      // ★ debugPrint probe -- a seam, not a mock (same idiom as
      // menu_badge_test.dart:376 and stat_card_row_test.dart:78). devPrint
      // (global.dart:2096) routes to debugPrint, and subscribeToMapCollection's
      // catch logs the full path it was asked for, so this observes BOTH that a
      // subscription was attempted and with WHICH argument order:
      // 'MobileTable/$appVid/tables/$tableDocId/$subColl'. Its catch also
      // removes the code from the module-level _mapSubscribed Set, so the next
      // test with the same code re-enters the body and the probe stays live.
      final List<String> printed = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      // Restored INLINE below, not via addTearDown: testWidgets asserts the
      // foundation debug variables are back to their originals by the end of
      // the test BODY, and addTearDown runs after that check.
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': 'V',
        'table': 'D//event',
        'search': 'cv$kBlackSquare$kOwnCv',
        'lastAction': 't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm',
        'text': cardText(),
      }, 'tp_code'));
      await tester.pumpAndSettle();
      debugPrint = originalDebugPrint;

      expect(find.text('14:05'), findsOneWidget); // read under 'V/D/event'
      expect(find.text('18:45'), findsNothing); // NOT the bare '' key
      expect(find.text('11:38'), findsNothing); // v1 literal overridden
      expect(
        printed.where((String m) => m
            .contains('subscribeToMapCollection MobileTable/V/tables/D/event')),
        isNotEmpty,
        reason: 'the subscription must fire, with appVid/tableDocId/subColl in '
            'that order -- this is also what keeps the next test honest',
      );
    });

    testWidgets('no lastAction, table set: the v1 literal stands',
        (WidgetTester tester) async {
      // The v1 half of the same fixture: the ledger is seeded under the REAL
      // code this component would subscribe to, so any path that reads it on
      // the v1 branch renders 14:05 where 11:38 belongs. Dev-spec §11:
      // "lastAction kosong -> tampilan identik v1, nol query."
      mapTableContent[kLiveCode] = <Map<String, dynamic>>[
        {'cv': kOwnCv, 't': msStr(todayAt(14, 5)), '__docId': 'own-new'},
      ];
      // ★ debugPrint probe -- a seam, not a mock (same idiom as
      // menu_badge_test.dart:376 and stat_card_row_test.dart:78). devPrint
      // (global.dart:2096) routes to debugPrint, and subscribeToMapCollection's
      // catch logs the full path it was asked for, so this observes BOTH that a
      // subscription was attempted and with WHICH argument order:
      // 'MobileTable/$appVid/tables/$tableDocId/$subColl'. Its catch also
      // removes the code from the module-level _mapSubscribed Set, so the next
      // test with the same code re-enters the body and the probe stays live.
      final List<String> printed = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      // Restored INLINE below, not via addTearDown: testWidgets asserts the
      // foundation debug variables are back to their originals by the end of
      // the test BODY, and addTearDown runs after that check.
      await tester.pumpWidget(wrap(<String, dynamic>{
        'type': 'TIME_PRESENCE',
        'vidtable': 'V',
        'table': 'D//event',
        'search': 'cv$kBlackSquare$kOwnCv',
        'text': cardText(),
      }, 'tp_v1_table'));
      await tester.pumpAndSettle();
      debugPrint = originalDebugPrint;

      expect(find.text('11:38'), findsOneWidget); // slot 6 literal
      expect(find.text('14:05'), findsNothing); // ledger never rendered
      // ★ "zero query" as an assertion. Rendered output CANNOT see this: with
      // _subscribe hoisted out of the `if (_lastAction != null)` guard the card
      // still prints 11:38, because build() takes the cfg == null branch and
      // never constructs the Obx. Measured -- that mutant survives every
      // find.text assertion in this file; only the probe kills it.
      expect(
        printed.where((String m) => m.contains('subscribeToMapCollection')),
        isEmpty,
        reason: 'the v1 path must open no subscription at all',
      );
    });
  });

  // ── round 2: the `checkIn` ledger slot (pump) ────────────────────────
  //
  // Assertions read a COLUMN, never a global find.text count: `valueUnder`
  // returns the Text rendered directly under a label, because _TimeColumn --
  // used by every column on BOTH render paths, including through
  // _LiveCounter -- lays out label-Text then value-Text. That makes each
  // assertion exact AND immune to the one real collision hazard here: the
  // Durasi column shows an ELAPSED HH:MM that can coincide with a wall-clock
  // value in another column (07:02 elapsed happens at 14:04 if check-in was
  // 07:02).
  group('TimePresence checkIn slot (pump)', () {
    setUpAll(() {
      transactionStore = DevToolsStore<ScreenTransaction>(
        transactionReducer,
        initialState: ScreenTransaction(initTransactionStore()),
      );
    });

    const String kCode = 'V/D/event'; // resolveAppVid('V') / parseTablePath('D//event')

    // mapTableContent is a GLOBAL RxMap, so a leaked row poisons later tests in
    // the whole suite. '' is the code a widget reads when it never subscribed
    // (no `table`, or the blank-search guard fired before _subscribe) -- the
    // single-slot blank-search test below seeds it deliberately.
    tearDown(() {
      mapTableContent.remove('');
      mapTableContent.remove(kCode);
    });

    /// Every Text in tree order: header, then label/value per column.
    List<String> allTexts(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((Text w) => w.data ?? '')
        .toList();

    /// The value rendered directly under [label].
    String valueUnder(WidgetTester tester, String label) {
      final List<String> all = allTexts(tester);
      final int i = all.indexOf(label);
      return i >= 0 && i + 1 < all.length ? all[i + 1] : '<missing:$label>';
    }

    /// How many of the two v4 connectors are still the dashed "belum" track.
    /// 2 = nothing reached, 1 = check-in and live reached, 0 = all three.
    int dashCount(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((CustomPaint p) => p.painter is DashConnectorPainter)
        .length;

    /// Disposes the tree so the 1s Timer and the v4 pulse do not outlive the
    /// test. pumpAndSettle can never be used in this group.
    Future<void> disposeTree(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox.shrink());

    /// 8 ◆-segments, dev spec (1) §3 order, with the live config's literals:
    /// text[4] = '--:--', text[5] = '16:02' (check-in), text[6] = '11:38'
    /// (last action), text[7] = checkout.
    /// [checkInLiteral] is `text[5]`. It defaults to the live config's `16:02`,
    /// but a test that means to observe the LEDGER check-in must pass `''`:
    /// with a valid literal there, `literalCheckInAt` is non-null and stands in
    /// for the ledger value, so the R2-1 revert stays invisible (review W4).
    String cardText({String checkInLiteral = '16:02', String checkOut = ''}) =>
        <String>[
          'Absensi hari ini',
          'Absen Masuk',
          'Durasi',
          'Aksi terakhir',
          '--:--',
          checkInLiteral,
          '11:38',
          checkOut,
        ].join(kDiamond);

    Map<String, dynamic> component({
      String? checkIn,
      String? lastAction,
      String? search = 'cv$kBlackSquare$kOwnCv',
      String? variant,
      String checkOut = '',
      String checkInLiteral = '16:02',
    }) =>
        <String, dynamic>{
          'type': 'TIME_PRESENCE',
          'vidtable': 'V',
          'table': 'D//event',
          if (search != null) 'search': search,
          if (checkIn != null) 'checkIn': checkIn,
          if (lastAction != null) 'lastAction': lastAction,
          if (variant != null) 'variant': variant,
          'text': cardText(checkInLiteral: checkInLiteral, checkOut: checkOut),
        };

    Widget wrap(Map<String, dynamic> c, String scrName) => MaterialApp(
          home: Scaffold(
            body: TimePresence(
              key: UniqueKey(),
              component: c,
              scrName: scrName,
              single: true,
            ),
          ),
        );

    void seed(List<Map<String, dynamic>> docs) => mapTableContent[kCode] = docs;

    Map<String, dynamic> ev(String ty, DateTime at, {String cv = kOwnCv}) =>
        <String, dynamic>{'cv': cv, 'ty': ty, 't': msStr(at)};

    const String kCheckInCfg =
        't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm${kDiamond}ty${kBlackSquare}clock-in';
    const String kLastActionCfg =
        't${kDiamond}desc${kDiamond}t${kDiamond}HH:mm';

    testWidgets('CONTROL: no checkIn key -> the v1 text[5] literal still drives '
        'the column and the counter', (WidgetTester tester) async {
      // Mutation-INSENSITIVE by construction: it asserts the behaviour that
      // already ships. Its job is back-compat -- every deployed
      // TIME_PRESENCE has no `checkIn` -- not mutant-killing.
      seed(<Map<String, dynamic>>[ev('clock-in', todayAt(7, 2))]);
      await tester.pumpWidget(wrap(component(), 'tp_ci_absent'));

      expect(valueUnder(tester, 'Absen Masuk'), '16:02');
      expect(valueUnder(tester, 'Durasi'), isNot('--:--'),
          reason: 'the literal check-in still arms the counter');
      await disposeTree(tester);
    });

    testWidgets('checkIn asc picks the FIRST clock-in of today',
        (WidgetTester tester) async {
      // ★ Each row earns its place; with only the last two the name
      // over-claimed and the test could not fail (review G1). After the
      // `ty◼clock-in` filter the r1 fixture reduced to a SINGLE doc, so
      // neither `asc` nor the day-scope was observable.
      //   yesterday 06:00 clock-in -> the DAY-SCOPE. Under the r1 order
      //     (pick, then day-guard the winner) pickNewestDoc(asc) returns this
      //     doc, the guard rejects it and the slot reads '--:--'. It is the
      //     mutant M1 killer this test's name always implied.
      //   today 09:15 clock-in     -> makes `asc` observable: a `desc` default
      //     renders 09:15 instead of 07:02.
      //   today 11:20 report-patrol -> the position-5 filter still bites.
      seed(<Map<String, dynamic>>[
        ev('clock-in', yesterdayAt(6, 0)),
        ev('clock-in', todayAt(7, 2)),
        ev('clock-in', todayAt(9, 15)),
        ev('report-patrol', todayAt(11, 20)),
      ]);
      await tester.pumpWidget(
          wrap(component(checkIn: kCheckInCfg), 'tp_ci_first'));

      expect(valueUnder(tester, 'Absen Masuk'), '07:02');
      await disposeTree(tester);
    });

    testWidgets('a SECOND clock-in the same day does not move it',
        (WidgetTester tester) async {
      // Dev spec (1) §11: "clock-in kedua di hari sama -> slot TETAP jam
      // pertama (`asc` = paling awal)". Catches a `desc` default.
      seed(<Map<String, dynamic>>[
        ev('clock-in', todayAt(7, 2)),
        ev('clock-in', todayAt(8, 30)),
      ]);
      await tester.pumpWidget(
          wrap(component(checkIn: kCheckInCfg), 'tp_ci_second'));

      expect(valueUnder(tester, 'Absen Masuk'), '07:02');
      await disposeTree(tester);
    });

    testWidgets('an EARLIER event of another ty does not move it',
        (WidgetTester tester) async {
      // The position-5 filter. Without it the 06:10 patrol wins under `asc`.
      seed(<Map<String, dynamic>>[
        ev('report-patrol', todayAt(6, 10)),
        ev('clock-in', todayAt(7, 2)),
      ]);
      await tester.pumpWidget(
          wrap(component(checkIn: kCheckInCfg), 'tp_ci_ty'));

      expect(valueUnder(tester, 'Absen Masuk'), '07:02');
      await disposeTree(tester);
    });

    testWidgets('yesterday only -> placeholder, and NOT the v1 literal',
        (WidgetTester tester) async {
      // ★ The day-SCOPE regression at widget level. Under the r1 order
      // (pick-then-guard) `asc` returns yesterday's doc, the guard rejects it,
      // and the slot is `--:--` -- the same visible result. What this pins is
      // the OTHER half: a configured slot must never fall back to `16:02`.
      seed(<Map<String, dynamic>>[ev('clock-in', yesterdayAt(6, 0))]);
      await tester.pumpWidget(
          wrap(component(checkIn: kCheckInCfg), 'tp_ci_yesterday'));

      expect(valueUnder(tester, 'Absen Masuk'), '--:--');
      expect(valueUnder(tester, 'Durasi'), '--:--');
      await disposeTree(tester);
    });

    testWidgets('position 5 absent: the earliest event of ANY ty wins',
        (WidgetTester tester) async {
      seed(<Map<String, dynamic>>[
        ev('report-patrol', todayAt(6, 10)),
        ev('clock-in', todayAt(7, 2)),
      ]);
      await tester.pumpWidget(wrap(
          component(checkIn: 't${kDiamond}asc${kDiamond}t${kDiamond}HH:mm'),
          'tp_ci_nofilter'));

      expect(valueUnder(tester, 'Absen Masuk'), '06:10');
      await disposeTree(tester);
    });

    testWidgets('a blank search blocks BOTH slots, on either render path',
        (WidgetTester tester) async {
      // The highest-value test in this group. filterDriverHomeDocs (:995) and
      // filterByMultiClause (:951, :976) all RETURN EVERY DOC for an empty
      // condition, so without the widget-level guard this card prints another
      // tenant user's event in BOTH columns. The second pair of assertions
      // kills the other tempting mistake -- falling back to the v1 literals,
      // which are the frozen numbers the config replaces.
      for (final String? v in <String?>[null, 'v4']) {
        seed(<Map<String, dynamic>>[
          ev('clock-in', todayAt(7, 2), cv: kOtherCv),
          ev('report-patrol', todayAt(18, 45), cv: kOtherCv),
        ]);
        await tester.pumpWidget(wrap(
            component(
                checkIn: kCheckInCfg,
                lastAction: kLastActionCfg,
                search: null,
                variant: v),
            'tp_ci_blocked_$v'));

        expect(valueUnder(tester, 'Absen Masuk'), '--:--', reason: 'v=$v');
        expect(valueUnder(tester, 'Aksi terakhir'), '--:--', reason: 'v=$v');
        expect(valueUnder(tester, 'Durasi'), '--:--', reason: 'v=$v');
        expect(allTexts(tester), isNot(contains('16:02')), reason: 'v=$v');
        expect(allTexts(tester), isNot(contains('11:38')), reason: 'v=$v');
        // ★ The only assertion in this file that tells the two render paths
        // apart (review G3). Blocked means all three nodes are todo, and a
        // connector is solid only when NEITHER end is todo -- so v4 paints two
        // dashed connectors, while v1 has no DashConnectorPainter at all and
        // therefore scores 0. Everything else here reads _TimeColumn, which
        // both paths share, so it cannot see which one built the tree.
        expect(dashCount(tester), v == 'v4' ? 2 : 0, reason: 'v=$v');
        await disposeTree(tester);
      }
    });

    testWidgets('checkIn ALONE + blank search is blocked too (single slot)',
        (WidgetTester tester) async {
      // ★ The mirror of round 1's `lastAction set but search blank`, which is
      // the only test that killed mutant M2 (`_lastAction != null || _checkIn
      // != null` -> `&&`). The two-slot test above cannot: with BOTH slots
      // configured `||` and `&&` agree (review G2).
      //
      // Why seeding '' is what makes it bite: under `&&` a checkIn-only card
      // leaves _searchBlocked false AND never calls _subscribe, so _code stays
      // '' and build() takes the Obx branch reading mapTableContent['']. A
      // blank search then fails OPEN in filterDriverHomeDocs, the position-5
      // filter still matches the other user's clock-in, and this worker's card
      // renders 18:45 -- a cross-user leak. The real code short-circuits to the
      // placeholder before any of that.
      mapTableContent[''] = <Map<String, dynamic>>[
        ev('clock-in', todayAt(18, 45), cv: kOtherCv),
      ];
      await tester.pumpWidget(wrap(
          component(checkIn: kCheckInCfg, search: null), 'tp_ci_blocked_solo'));

      expect(valueUnder(tester, 'Absen Masuk'), '--:--');
      expect(valueUnder(tester, 'Durasi'), '--:--');
      expect(allTexts(tester), isNot(contains('18:45')),
          reason: 'no cross-user leak');
      expect(allTexts(tester), isNot(contains('16:02')),
          reason: 'a configured slot never falls back to its text[5] literal');
      // The UNconfigured slot is untouched by the guard -- this is what makes
      // it a single-slot test rather than a second copy of the both-slots one.
      expect(valueUnder(tester, 'Aksi terakhir'), '11:38');
      await disposeTree(tester);
    });

    testWidgets('R2-1: the Durasi counter runs from the LEDGER check-in',
        (WidgetTester tester) async {
      // Without the rewiring, `liveCheckIn` still comes from the sheet literal
      // and the card shows a ledger check-in in one column while Durasi counts
      // from another number -- or, with an empty text[5], shows `--:--`.
      // v1 observes it through the Durasi column; v4 additionally through the
      // timeline, whose live node exists only when liveCheckIn != null.
      //
      // ★ checkInLiteral: '' is load-bearing (review W4). With the group's
      // default text[5] = '16:02' this test was GREEN under the very mutant it
      // is named for: `checkInAt = literalCheckInAt` still yields a non-null
      // 16:02, so the counter ran, Durasi was != '--:--' and both connectors
      // stayed solid. Emptying text[5] makes literalCheckInAt null, so the
      // ONLY source left for the counter is the ledger.
      for (final String? v in <String?>[null, 'v4']) {
        seed(<Map<String, dynamic>>[ev('clock-in', todayAt(7, 2))]);
        await tester.pumpWidget(wrap(
            component(
                checkIn: kCheckInCfg, variant: v, checkInLiteral: ''),
            'tp_ci_live_$v'));

        expect(valueUnder(tester, 'Absen Masuk'), '07:02', reason: 'v=$v');
        expect(valueUnder(tester, 'Durasi'), isNot('--:--'), reason: 'v=$v');
        expect(valueUnder(tester, 'Durasi'), matches(RegExp(r'^\d{2}:\d{2}$')),
            reason: 'v=$v');
        if (v == 'v4') {
          // ★ PLAN CORRECTION, measured -- not tuned until green. The plan
          // predicted 1 dashed connector, reasoning "the last-action node is
          // still todo". It is not: this fixture configures `checkIn` ONLY,
          // so the Aksi-terakhir column keeps cardText()'s v1 literal 11:38,
          // which is != noDataLabel and therefore renders a DONE node. Probed
          // on this exact fixture: 2 check icons, 0 dashed connectors -- both
          // connectors solid. The metric still moves, which is what makes the
          // assertion worth keeping: forcing checkInAt = null (the R2-1 break)
          // drops the live node to todo and dashes BOTH connectors -> 2.
          expect(dashCount(tester), 0);
        }
        await disposeTree(tester);
      }
    });

    testWidgets('both slots live at once, from ONE subscription',
        (WidgetTester tester) async {
      // Dev spec (1) §3.2.5: two slots, one listener. Different filters, same
      // `search`, same mapTableContent[_code], one Obx.
      for (final String? v in <String?>[null, 'v4']) {
        seed(<Map<String, dynamic>>[
          ev('clock-in', todayAt(7, 2)),
          ev('report-patrol', todayAt(14, 5)),
          ev('clock-in', todayAt(18, 45), cv: kOtherCv), // another user, newest
        ]);
        await tester.pumpWidget(wrap(
            component(
                checkIn: kCheckInCfg, lastAction: kLastActionCfg, variant: v),
            'tp_ci_both_$v'));

        expect(valueUnder(tester, 'Absen Masuk'), '07:02', reason: 'v=$v');
        expect(valueUnder(tester, 'Aksi terakhir'), '14:05', reason: 'v=$v');
        expect(valueUnder(tester, 'Durasi'), isNot('--:--'), reason: 'v=$v');
        expect(allTexts(tester), isNot(contains('18:45')),
            reason: 'cross-user leak, v=$v');
        await disposeTree(tester);
      }
    });

    testWidgets('a new ledger row moves the desc slot and NOT the asc slot',
        (WidgetTester tester) async {
      // Proves the single Obx registers its dependency on the mapTableContent
      // RxMap for BOTH slots -- the only thing standing in for a Firestore
      // snapshot listener under D1. Two pumps in one testWidgets is deliberate:
      // Element reuse is exactly what is under test and only the DATA changes.
      seed(<Map<String, dynamic>>[
        ev('clock-in', todayAt(7, 2)),
        ev('report-patrol', todayAt(14, 5)),
      ]);
      await tester.pumpWidget(wrap(
          component(checkIn: kCheckInCfg, lastAction: kLastActionCfg),
          'tp_ci_realtime'));
      expect(valueUnder(tester, 'Aksi terakhir'), '14:05'); // fixture sanity

      seed(<Map<String, dynamic>>[
        ...mapTableContent[kCode]!,
        ev('report-complain', todayAt(16, 20)),
        ev('clock-in', todayAt(17, 0)), // a later clock-in must NOT move `asc`
      ]);
      await tester.pump();

      expect(valueUnder(tester, 'Aksi terakhir'), '17:00');
      expect(valueUnder(tester, 'Absen Masuk'), '07:02');
      await disposeTree(tester);
    });

    testWidgets('checkout wins over both ledger slots (R2-3)',
        (WidgetTester tester) async {
      seed(<Map<String, dynamic>>[
        ev('clock-in', todayAt(7, 2)),
        ev('report-patrol', todayAt(14, 5)),
      ]);
      await tester.pumpWidget(wrap(
          component(
              checkIn: kCheckInCfg,
              lastAction: kLastActionCfg,
              checkOut: '17:00'),
          'tp_ci_checkout'));

      expect(valueUnder(tester, 'Absen Masuk'), '--:--');
      expect(valueUnder(tester, 'Durasi'), '--:--');
      expect(valueUnder(tester, 'Aksi terakhir'), '--:--');
      await disposeTree(tester);
    });
  });
}
