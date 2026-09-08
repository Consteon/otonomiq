import '../global.dart'; // screenUIComponent, mapTableContent, autheniumDecode, devPrint
import 'approver_sticky_bar.dart'; // evaluateRbtSearch (positional predicate, unchanged)
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs
import 'item_card_detail.dart'; // ItemCardDetail.currentRow
import 'panel_card_support.dart'; // TablePath, parseTablePath

/// RBT child `search` = VISIBILITY predicate, evaluated on EVERY RBT (inline,
/// sticky, and nested in DO_DIALOG / DO_BOTTOM_SHEET chains). The outer
/// `RBT.search` is a LAYOUT switch only ("sticky" vs inline) and is parsed
/// separately in build_display_component.dart's `rbt` branch.
///
/// Two clause dialects, dispatched by key type -- forced by live config, not
/// preference: 45 sticky children in op1Screen use an INTEGER key ("2◼MENUNGGU")
/// against the positional row published by ITEM_CARD_DETAIL, and 9 inline
/// children use a FIELD key ("st◼waiting") against the page's keyed context doc.
/// Zero overlap between the two populations.
///
/// Its own file, and the import graph has a deliberate CYCLE:
/// rbt_visibility.dart -> approver_sticky_bar.dart -> ftz_row_of_button_2.dart
/// -> rbt_visibility.dart, because approver_sticky_bar.dart:8 imports the
/// button row. That is legal Dart, it compiles and runs -- do NOT restructure
/// it away. The file exists for three reasons that hold regardless:
///   1. list_card_support.dart is a pure parser module (it imports only
///      global.dart + admin_home_support.dart); this predicate needs GetX,
///      mapTableContent and ItemCardDetail, which would pollute it.
///   2. driver_home_support.dart is imported BY detail_card.dart and
///      approver_sticky_bar.dart, so hosting the predicate there would add a
///      back-edge from a leaf support module to a widget.
///   3. Unit-testable: everything here is pure over plain globals, so
///      test/rbt_child_visibility_test.dart needs no widget pump, no GetX
///      controller and no Firebase.

const String _kAndSep = '\u{2B58}'; // ⭘  clause AND separator
const String _kEqSep = '\u{25FC}'; // ◼  key/value separator

/// Keys to the page's context doc: the mapTableContent subscription code and
/// the raw (undecoded) search of the page's first usable DETAIL_CARD.
///
/// The KEYS are resolved, never a doc snapshot: the reader looks the docs up
/// inside its own Obx, so a Firestore snapshot repaints it (mapTableContent is
/// an RxMap and the listener assigns whole lists -- table_repository.dart
/// `mapTableContent[code] = docs`).
class RbtDocSource {
  final String code;
  final String rawSearch;
  const RbtDocSource(this.code, this.rawSearch);
  bool get isEmpty => code.isEmpty;
}

const RbtDocSource kNoRbtDocSource = RbtDocSource('', '');

/// Resolve the page's context-doc keys from the page JSON both the DETAIL_CARD
/// and the RBT were built from. Same lookup shape as
/// ApproverStickyBar.hasCommentInput.
///
/// Derived, not published: a published registry would be wiped by the
/// post-frame `clearData` that `reloadPage` schedules on every gotoRoute
/// (global.dart `reloadPage` -> addPostFrameCallback -> api.dart `clearData`
/// -> ScreenSession.navReset) with nothing left to re-publish it, because
/// AnyPage re-renders the SAME cached widget instances from linkElement.
///
/// Tie-break when a screen carries several DETAIL_CARDs: the FIRST usable one
/// in page-JSON order wins. Page order, not build order -- deterministic.
/// A DETAIL_CARD with a missing/malformed `table` is skipped, matching
/// DetailCard._subscribe, which returns early and never subscribes in that case.
RbtDocSource resolveRbtDocSource(String scrName) {
  try {
    final dynamic page = screenUIComponent is Map
        ? screenUIComponent[scrName]
        : null;
    final dynamic children = page is Map ? page['children'] : null;
    if (children is! List) return kNoRbtDocSource;
    for (final dynamic c in children) {
      if (c is! Map) continue;
      if ((c['type'] ?? '').toString().trim().toLowerCase() != 'detail_card') {
        continue;
      }
      final String rawTable = (c['table'] ?? '').toString().trim();
      if (rawTable.isEmpty) continue;
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isEmpty) continue;
      final String appVid = resolveAppVid(c);
      // Same key formula as DetailCard._subscribe -- keep them identical.
      return RbtDocSource(
        '$appVid/${tp.tableDocId}/${tp.subColl}',
        // RAW: filterDriverHomeDocs decodes + resolves tokens internally.
        (c['search'] ?? '').toString().trim(),
      );
    }
  } catch (e) {
    devPrint('resolveRbtDocSource("$scrName") error: $e');
  }
  return kNoRbtDocSource;
}

/// True when at least one child declares a non-empty `search`. Lets an RBT with
/// no conditional child keep the original widget tree with no Obx wrapper and
/// no repaint-on-any-snapshot cost -- ~200 of the 209 live RBT occurrences.
bool anyRbtChildConditional(List<dynamic> children) {
  for (final dynamic c in children) {
    if (c is! Map) continue;
    if ((c['search'] ?? '').toString().trim().isNotEmpty) return true;
  }
  return false;
}

/// Evaluate ONE child's `search`.
///
/// Empty `search` -> always visible, in every state.
/// Integer clause key -> positional match via the UNMODIFIED evaluateRbtSearch
///   (case-INsensitive, out-of-range -> false, eq() type-tolerant).
/// Field clause key -> keyed match via filterDriverHomeDocs against
///   [contextDoc] (case-SENSITIVE via eq()'s string fallback, type-tolerant on
///   numbers, fail-closed on an empty value or an unresolved `{token}`).
/// Mixed -> AND of both, each evaluator fed only its own clauses.
///
/// The two dialects differ on case BY DESIGN. Do not harmonize them: the keyed
/// branch must keep agreeing with the DETAIL_CARD above it, which runs the same
/// filterDriverHomeDocs over the same list.
///
/// Fail-closed on every undecidable state (these buttons write; a wrongly shown
/// button is a double-accept, a wrongly hidden one costs a reload).
bool rbtChildVisible(
  String rawSearch,
  String scrName, {
  required List<dynamic> row,
  required Map<String, dynamic>? contextDoc,
}) {
  if (rawSearch.trim().isEmpty) return true;

  final String decoded = autheniumDecode(rawSearch) ?? rawSearch;
  final List<String> positional = <String>[];
  final List<String> keyed = <String>[];
  for (final String clause in decoded.split(_kAndSep)) {
    if (clause.trim().isEmpty) continue;
    final int sep = clause.indexOf(_kEqSep);
    if (sep < 0) continue; // no ◼ -> ignored, same as evaluateRbtSearch
    final String key = clause.substring(0, sep).trim();
    if (key.isEmpty) {
      // Load-bearing guard: filterByMultiClause SKIPS an empty field
      // (`if (field.isEmpty) continue`), so "◼waiting" would end with
      // pairs.isEmpty and return every doc -> fail-OPEN. evaluateRbtSearch
      // fails closed on the same string; keep that, a gate never fails open.
      devPrint(
        'RBT visibility: "$rawSearch" on "$scrName" — '
        'clause with empty key → hidden',
      );
      return false;
    }
    if (int.tryParse(key) != null) {
      positional.add(clause);
    } else {
      keyed.add(clause);
    }
  }

  if (positional.isEmpty && keyed.isEmpty) return true;

  if (positional.isNotEmpty) {
    // Pure-positional: hand evaluateRbtSearch the ORIGINAL string so its own
    // decode/uppercase/eq path runs byte-for-byte as it does today.
    final bool ok = keyed.isEmpty
        ? evaluateRbtSearch(rawSearch, row)
        : evaluateRbtSearch(positional.join(_kAndSep), row);
    if (!ok) return false;
    if (keyed.isEmpty) return true;
  }

  if (contextDoc == null) {
    devPrint(
      'RBT visibility: "$rawSearch" on "$scrName" — '
      'no page context doc → hidden',
    );
    return false;
  }
  final bool ok = filterDriverHomeDocs(
    <Map<String, dynamic>>[contextDoc],
    positional.isEmpty ? rawSearch : keyed.join(_kAndSep),
    scrName,
  ).isNotEmpty;
  if (!ok) {
    devPrint(
      'RBT visibility: "$rawSearch" on "$scrName" — '
      'context doc mismatch → hidden',
    );
  }
  return ok;
}

/// Filter an RBT's children down to the visible ones.
///
/// CALLED FROM INSIDE AN Obx. The two observable reads below MUST stay the
/// first statements of this function, before any guard, `if`, early `return`,
/// `??` or `&&`: a closure that can finish without reading an observable throws
/// GetX's "improper use of a GetX" fatal (six shipped instances in this repo).
/// `mapTableContent[code]` registers the dependency even when `code` is '' or
/// absent -- RxMap.operator[] goes through the `value` getter, which calls
/// `RxInterface.proxy?.addListener`.
List<dynamic> visibleRbtChildren(List<dynamic> children, String scrName) {
  final List<dynamic> row =
      ItemCardDetail.currentRow.value; // obs read #1 — literally first
  final RbtDocSource src = resolveRbtDocSource(scrName);
  final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
    mapTableContent[src.code] ?? const [],
  ); // obs read #2

  // matched.first mirrors DetailCard._findDoc: the predicate is evaluated
  // against the doc the card is actually SHOWING, not any matching doc.
  final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
    docs,
    src.rawSearch,
    scrName,
  );
  final Map<String, dynamic>? contextDoc = matched.isNotEmpty
      ? matched.first
      : null;

  return children.where((dynamic child) {
    final String raw = (child is Map ? (child['search'] ?? '') : '')
        .toString()
        .trim();
    if (raw.isEmpty) return true;
    return rbtChildVisible(raw, scrName, row: row, contextDoc: contextDoc);
  }).toList();
}
