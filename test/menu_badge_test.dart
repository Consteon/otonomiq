import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/widget/menu_icon_card.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Search-DSL separators, written as escapes so the file stays ASCII-safe.
/// sq = ◼ U+25FC (field/value), ci = ⭘ U+2B58 (AND between clauses).
const String sq = '\u{25FC}';
const String ci = '\u{2B58}';

/// Site VID from the live config: op1Screen!D695 `search:"7◼83674161979544"`.
const String siteVid = '83674161979544';

/// Doc fixtures are ALWAYS written as `<String, dynamic>{...}` inside an
/// explicitly typed `<Map<String, dynamic>>[...]`. A bare `[{'t': 1}]` assigned
/// to a local infers `List<Map<String, int>>` and will not pass to a
/// `List<Map<String, dynamic>>` parameter.
List<Map<String, dynamic>> docs(List<Map<String, dynamic>> d) => d;

void main() {
  // MenuBadge.countFor -> filterDriverHomeDocs -> transactionStore.state.screenTx
  // (driver_home_support.dart:975). The global `transactionStore` is null in a
  // bare flutter_test process, so seed the Redux store ONCE. Mirrors
  // test/driver_home_support_test.dart and test/precondition_gate_card_test.dart.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  group('MenuBadge.countFor - hard gate', () {
    test('empty badgeTable -> 0 (feature off for that item)', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'t': 9999},
          ]),
          rawSearch: '',
          tsField: '',
          seen: 0,
          scrName: 'home',
        ),
        0,
      );
    });

    test('whitespace-only badgeTable -> 0', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '   ',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'t': 9999},
          ]),
          rawSearch: '',
          tsField: '',
          seen: 0,
          scrName: 'home',
        ),
        0,
      );
    });

    test('empty doc list -> 0', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[]),
          rawSearch: '',
          tsField: '',
          seen: 0,
          scrName: 'home',
        ),
        0,
      );
    });
  });

  group('MenuBadge.countFor - timestamp field', () {
    test('blank badgeTs defaults to "t" (D4)', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'t': 2000},
            <String, dynamic>{'t': 3000},
          ]),
          rawSearch: '',
          tsField: '',
          seen: 1000,
          scrName: 'home',
        ),
        2,
      );
    });

    test('blank badgeTs does NOT read a row-slot field such as "12"', () {
      // The spec's `badgeTs:"12"` names a slot that is not promoted by
      // `index◼1★S◼2★S◼5★N◼7★N◼9★N` (op1Screen!N665), so it is absent from the
      // document. Only `t` exists. This is the regression this test locks.
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'12': 5000},
          ]),
          rawSearch: '',
          tsField: '',
          seen: 1000,
          scrName: 'home',
        ),
        0,
      );
    });

    test('timestamp field missing from every doc -> 0', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': siteVid},
            <String, dynamic>{'7': siteVid},
          ]),
          rawSearch: '',
          tsField: 't',
          seen: 0,
          scrName: 'home',
        ),
        0,
      );
    });

    test('String and num timestamps are BOTH counted', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'t': 2000},
            <String, dynamic>{'t': '3000'},
          ]),
          rawSearch: '',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        2,
      );
    });

    test('doc exactly == seen is NOT counted (strictly greater)', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'t': 1000},
            <String, dynamic>{'t': 1001},
          ]),
          rawSearch: '',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        1,
      );
    });

    test('unparseable timestamp coerces to 0 and is not counted', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'t': 'not-a-number'},
            <String, dynamic>{'t': ''},
            <String, dynamic>{'t': null},
          ]),
          rawSearch: '',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        0,
      );
    });

    test('explicit badgeTs reads that field, not "t"', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//event',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'ts': 5000, 't': 0},
          ]),
          rawSearch: '',
          tsField: 'ts',
          seen: 1000,
          scrName: 'home',
        ),
        1,
      );
    });
  });

  group('MenuBadge.countFor - badgeSearch scoping', () {
    test('other-site docs are excluded by 7-clause', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': siteVid, 't': 2000},
            <String, dynamic>{'7': '11111111111111', 't': 2000},
            <String, dynamic>{'7': siteVid, 't': 3000},
          ]),
          rawSearch: '7$sq$siteVid',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        2,
      );
    });

    test('num-typed doc field matches String search value (dsl_eq)', () {
      // `7★N` in op1Screen!N665 promotes slot 7 as a NUMBER; the sheet search
      // value is a String. dsl_eq.eq bridges that (14 chars <= the 15-char
      // safe-integer guard).
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': 83674161979544, 't': 2000},
          ]),
          rawSearch: '7$sq$siteVid',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        1,
      );
    });

    test('multi-clause AND narrows the count', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': siteVid, '2': 'MENUNGGU', 't': 2000},
            <String, dynamic>{'7': siteVid, '2': 'SELESAI', 't': 2000},
          ]),
          rawSearch: '7$sq$siteVid${ci}2${sq}MENUNGGU',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        1,
      );
    });

    test('empty badgeSearch counts every doc', () {
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': siteVid, 't': 2000},
            <String, dynamic>{'7': '11111111111111', 't': 2000},
          ]),
          rawSearch: '',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        2,
      );
    });

    test('search key absent from every doc counts 0 (D5 limitation)', () {
      // Documents the accepted limitation: a badgeSearch key that is not a
      // promoted `index◼` field matches nothing, silently.
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': siteVid, 't': 2000},
          ]),
          rawSearch: '23$sq$siteVid',
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        ),
        0,
      );
    });
  });

  group('MenuBadge - large counts and label', () {
    test('150 fresh docs count 150', () {
      final List<Map<String, dynamic>> many =
          List<Map<String, dynamic>>.generate(
        150,
        (int i) => <String, dynamic>{'t': 2000 + i},
      );
      expect(
        MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: many,
          rawSearch: '',
          tsField: '',
          seen: 1000,
          scrName: 'home',
        ),
        150,
      );
    });

    test('badgeLabel mirrors otq_bottom_nav_bar: 99 -> "99", 100 -> "99+"', () {
      expect(MenuBadge.badgeLabel(1), '1');
      expect(MenuBadge.badgeLabel(99), '99');
      expect(MenuBadge.badgeLabel(100), '99+');
      expect(MenuBadge.badgeLabel(150), '99+');
    });
  });

  // W2 (r2): the D5 diagnostic used `.split('\u{25FC}').first`, which returns
  // the WHOLE clause when there is no separator. filterByMultiClause instead
  // SKIPS such a clause (driver_home_support.dart:942). These tests pin the
  // evaluator behaviour the diagnostic has to mirror.
  group('MenuBadge.countFor - clause shapes the evaluator skips', () {
    final List<Map<String, dynamic>> fixture = docs(<Map<String, dynamic>>[
      <String, dynamic>{'7': siteVid, 't': 2000},
      <String, dynamic>{'7': '11111111111111', 't': 2000},
      <String, dynamic>{'7': siteVid, 't': 3000},
    ]);

    int countWith(String rawSearch) => MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: fixture,
          rawSearch: rawSearch,
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        );

    test('a separator-less trailing fragment does NOT change the count', () {
      // `7<sq><vid><ci>garbage` counts exactly as `7<sq><vid>` does: the
      // `garbage` clause has no <sq>, so filterByMultiClause skips it. The
      // pre-fix diagnostic read `garbage` as a search key, found it on no
      // document, and printed "Badge will stay 0" over a config returning 2.
      expect(countWith('7$sq$siteVid'), 2);
      expect(countWith('7$sq$siteVid${ci}garbage'), 2);
    });

    test('a clause with an EMPTY value fail-closes to 0 (undiagnosed cause)',
        () {
      // filterByMultiClause returns [] on an empty resolved value
      // (driver_home_support.dart:949-953). Nothing warns about this — it is
      // not detectable from the raw badgeSearch string — which is why the
      // doc's trap 3 exists.
      expect(countWith('7$sq'), 0);
    });
  });

  // W2 (r2), second half: the diagnostic's ONLY output is a devPrint, so pin
  // it by capturing debugPrint. Pair matters — (a) alone would also pass if the
  // fix had simply neutered the diagnostic, (b) proves it still fires.
  group('MenuBadge D5 diagnostic', () {
    late List<String> printed;
    late DebugPrintCallback original;

    setUp(() {
      printed = <String>[];
      original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
    });

    tearDown(() {
      debugPrint = original;
    });

    void count(String rawSearch) => MenuBadge.countFor(
          badgeTable: '84214220504259//report',
          docs: docs(<Map<String, dynamic>>[
            <String, dynamic>{'7': siteVid, 't': 2000},
          ]),
          rawSearch: rawSearch,
          tsField: 't',
          seen: 1000,
          scrName: 'home',
        );

    test('(a) a separator-less fragment raises NO false alarm', () {
      count('7$sq$siteVid${ci}garbage');
      expect(
        printed.where((String l) => l.contains('badgeSearch key(s)')),
        isEmpty,
      );
    });

    test('(b) a key absent from every document still warns', () {
      count('23$sq$siteVid');
      expect(
        printed.where((String l) => l.contains('badgeSearch key(s) [23]')),
        isNotEmpty,
      );
    });
  });

  // W3 (r2): codeFor needs NO Firebase. `firestoreDb` is a plain `dynamic`
  // (global.dart:507) and is null in a test process, so
  // `subscribeToMapCollection` throws NoSuchMethodError internally and swallows
  // it (table_repository.dart:2181-2184); codeFor still returns its code.
  //
  // Every fixture pins the tenant explicitly (`badgeVidtable`, or `vidtable`
  // when the fallback chain is what is under test) so nothing reaches
  // `getTableVid` -> `appCodeController` (GetX, not initialized here), and every
  // fixture carries a `route`, because a child with none can never be cleared.
  group('MenuBadge.codeFor', () {
    const String reportTable = '84214220504259//report';
    const String otqVid = '60936087747650';
    const String conVid = '20342033315492';

    test('blank badgeTable -> "" (hard gate)', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'route': 'reportList',
          'vidtable': otqVid,
        }),
        '',
      );
    });

    test('whitespace-only badgeTable -> ""', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': '   ',
          'route': 'reportList',
          'vidtable': otqVid,
        }),
        '',
      );
    });

    test('explicit vidtable -> "<vidtable>/<tableDocId>/<subColl>"', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'route': 'reportList',
          'vidtable': otqVid,
        }),
        '$otqVid/84214220504259/report',
      );
    });

    test('the SAME badgeTable under two tenants yields two DIFFERENT codes',
        () {
      // Table doc 84214220504259 exists under BOTH 60936087747650 (otq) and
      // 20342033315492 (con) with different content (api.dart:80-98), and
      // mapTableContent / _mapSubscribed are keyed by `code` ALONE. Drop the
      // vid from the code and the two tenants collapse onto one stream: one
      // tenant's menu badge would count the other tenant's documents.
      final String a = MenuBadge.codeFor(<String, dynamic>{
        'badgeTable': reportTable,
        'route': 'reportList',
        'vidtable': otqVid,
      });
      final String b = MenuBadge.codeFor(<String, dynamic>{
        'badgeTable': reportTable,
        'route': 'reportList',
        'vidtable': conVid,
      });
      expect(a, '$otqVid/84214220504259/report');
      expect(b, '$conVid/84214220504259/report');
      expect(a, isNot(b));
    });

    // D6 (r3): the field name the SPEC fixes at grid-child level is
    // `badgeVidtable` (§3, §4, §7.2, §8, §11). Round 1 read `vidtable` through
    // `resolveAppVid`, so deployed config carrying `badgeVidtable` was
    // invisible: the vid fell through to `applicationTableVid`, the badge
    // counted another tenant's collection and sat at 0 forever, no error, no
    // log. Same silent class as the `badgeTs:"12"` slot-vs-field bug.
    test('badgeVidtable pins the tenant (the spec field name)', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'route': 'reportList',
          'badgeVidtable': conVid,
        }),
        '$conVid/84214220504259/report',
      );
    });

    test('badgeVidtable WINS over vidtable on the same item', () {
      // Both keys present: only `badgeVidtable` may decide. The round-1
      // precedence resolves `$otqVid` here and fails this expectation.
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'route': 'reportList',
          'badgeVidtable': conVid,
          'vidtable': otqVid,
        }),
        '$conVid/84214220504259/report',
      );
    });

    test('blank badgeVidtable falls back to the resolveAppVid chain', () {
      // Spec §3: an empty `badgeVidtable` "jatuh ke default aplikasi".
      // `vidtable` is the first link of that chain
      // (driver_home_support.dart:249), so it must still resolve. Whitespace
      // must behave as empty, not as a tenant id.
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'route': 'reportList',
          'badgeVidtable': '',
          'vidtable': otqVid,
        }),
        '$otqVid/84214220504259/report',
      );
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'route': 'reportList',
          'badgeVidtable': '   ',
          'vidtable': otqVid,
        }),
        '$otqVid/84214220504259/report',
      );
    });

    test('two items differing ONLY in badgeVidtable get DIFFERENT codes', () {
      // Cross-tenant assertion for the spec's field name — mirrors the
      // `vidtable` case above. `mapTableContent` / `_mapSubscribed` are keyed
      // by `code` ALONE, so an ignored `badgeVidtable` collapses both items
      // onto ONE stream and one tenant's menu counts the other's documents.
      final String a = MenuBadge.codeFor(<String, dynamic>{
        'badgeTable': reportTable,
        'route': 'reportList',
        'badgeVidtable': otqVid,
      });
      final String b = MenuBadge.codeFor(<String, dynamic>{
        'badgeTable': reportTable,
        'route': 'reportList',
        'badgeVidtable': conVid,
      });
      expect(a, '$otqVid/84214220504259/report');
      expect(b, '$conVid/84214220504259/report');
      expect(a, isNot(b));
    });

    test('badgeTable with no "//" -> subColl defaults to "content"', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': '84214220504259',
          'route': 'reportList',
          'vidtable': otqVid,
        }),
        '$otqVid/84214220504259/content',
      );
    });

    test('badgeTable with an empty "//" tail -> "content"', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': '84214220504259//',
          'route': 'reportList',
          'vidtable': otqVid,
        }),
        '$otqVid/84214220504259/content',
      );
    });

    test('non-Map item -> "" and does not throw', () {
      // buildGridList's per-item try/catch would otherwise swap the whole tile
      // for the `--GRID--` error card.
      expect(MenuBadge.codeFor('not-a-map'), '');
      expect(MenuBadge.codeFor(null), '');
      expect(MenuBadge.codeFor(<dynamic>['badgeTable']), '');
    });

    // I2 (r2): the seen-store is keyed by route and only the navigate guard
    // stamps it, so a badge with no route could never be cleared once lit.
    test('badgeTable but NO route -> "" (an unclearable badge must not lit)',
        () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'vidtable': otqVid,
        }),
        '',
      );
    });

    test('whitespace-only route -> ""', () {
      expect(
        MenuBadge.codeFor(<String, dynamic>{
          'badgeTable': reportTable,
          'route': '   ',
          'vidtable': otqVid,
        }),
        '',
      );
    });
  });

  // W1 (r2): markSeen trimmed the route before building the prefs key and
  // seenEpoch did not, so a sheet route carrying whitespace wrote
  // `badgeSeen_x` and read `badgeSeen_ x ` -> the badge never cleared, on that
  // tenant only, with no error. `routeExist` (global.dart:1522) is an exact
  // `linkElement` lookup with no trim, so such a route navigates normally.
  group('MenuBadge seen-key derivation', () {
    setUp(() async {
      // The plugin's own test hook, not a mock package.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('markSeen then seenEpoch round-trips a route carrying whitespace',
        () {
      const String padded = '  reportList  ';
      expect(MenuBadge.seenEpoch(padded), 0);
      MenuBadge.markSeen(padded);
      expect(MenuBadge.seenEpoch(padded), greaterThan(0));
    });

    test('trimmed and untrimmed spellings address ONE prefs key', () {
      MenuBadge.markSeen('  reportList  ');
      final int bare = MenuBadge.seenEpoch('reportList');
      expect(bare, greaterThan(0));
      expect(MenuBadge.seenEpoch('  reportList  '), bare);
      expect(MenuBadge.seenEpoch('reportList '), bare);
      expect(prefs.getInt('${MenuBadge.seenKeyPrefix}reportList'), bare);
    });

    test('an unvisited route reads 0', () {
      MenuBadge.markSeen('reportList');
      expect(MenuBadge.seenEpoch('formList'), 0);
    });

    test('a blank route writes nothing and reads 0', () {
      MenuBadge.markSeen('   ');
      MenuBadge.markSeen('');
      expect(MenuBadge.seenEpoch('   '), 0);
      expect(MenuBadge.seenEpoch(''), 0);
      expect(
        prefs
            .getKeys()
            .where((String k) => k.startsWith(MenuBadge.seenKeyPrefix)),
        isEmpty,
      );
    });
  });
}
