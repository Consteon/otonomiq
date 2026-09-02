import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// Home-menu icon buttons: the shared card shell AND the menu-badge feature.
///
/// [menuIconCard] is the presentational shell for `horizontal_icon` children
/// (Goto, GpsSend, AttendQrGpsSelfie, FtzChecker, disabledIcon), their single
/// modes, and `buildGridList` (`vgr`/`hgr`). One place owns the card look;
/// callers keep their own onTap.
///
/// Grid cells are screen-derived (4 fixed columns, see the `horizontal_icon`
/// and `hgr` branches), so the card fills its tight cell and centers its
/// content; in single mode (unbounded height) the column hugs content.
///
/// [MenuBadge] is NOT presentational and is used by `buildGridList` only. It
/// owns a Firestore subscription (`subscribeToMapCollection` — that is why
/// this file imports `table_repository.dart`), the `badgeSeen_<route>`
/// SharedPreferences store, and the pure count. Keep unrelated subscriptions
/// out of this file: the shell half must stay cheap for its seven other
/// callers, which never touch [MenuBadge] at all.
Widget menuIconCard({
  required String imageUrl,
  required String label,
  required double fontSize,
  void Function()? onTap,
  // MENU BADGE: optional and defaulted, so the seven other call sites
  // (goto.dart x2, gps_send.dart x2, attendance_qr_selfie_gps_verify.dart x2,
  // ftz_checker.dart, ui_component.dart disabledIcon) compile untouched.
  // 0 (or less) renders NOTHING — not an empty circle, not "0".
  int badgeCount = 0,
}) {
  final BorderRadius radius = BorderRadius.circular(16);
  // Sheet-config fontSize varies per section (14–16); a menu-card label is a
  // caption, so normalize into the 11–12 band for a uniform type scale
  // across ABSEN / Laporan / Formulir.
  final double labelSize = fontSize.clamp(11.0, 12.0);
  return Container(
    margin: const EdgeInsets.all(5),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        // same hairline as the time_presence stat chips
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // MENU BADGE: badgeCount <= 0 keeps the ORIGINAL subtree byte for
              // byte (no Stack, no extra constraint) so every non-badged caller
              // renders exactly as before.
              if (badgeCount <= 0)
                SizedBox(
                  height: 36,
                  child: displayImage(
                    imageUrl: imageUrl.isEmpty ? defaultImage : imageUrl,
                    cached: true,
                    fit: BoxFit.contain,
                  ),
                )
              else
                // ponytail: the badged icon box is pinned to 36x36. Without a
                // width, the box is full-card-width while CachedNetworkImage
                // shows its `width: double.infinity` placeholder and ~36 wide
                // once loaded — the badge anchor would jump, and at full width
                // `right: -6` would push the bubble past the card padding into
                // the `Clip.antiAlias` boundary. Live menu icons are square
                // (90x90 PNGs); a non-square badged icon would letterbox.
                // Widen this if a badged menu ever ships a non-square icon.
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Non-positioned child FIRST: the Stack sizes to it and
                      // the image receives the same constraints it had before.
                      displayImage(
                        imageUrl: imageUrl.isEmpty ? defaultImage : imageUrl,
                        cached: true,
                        fit: BoxFit.contain,
                      ),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: _menuBadgeBubble(badgeCount),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              // Flexible: on very narrow screens the 2-line label shrinks
              // instead of overflowing the fixed grid cell
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: labelSize,
                    height: 1.15,
                    letterSpacing: 0.1,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2A3240),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Count bubble drawn at the top-right of the icon area (never over the label).
///
/// Structure mirrors the inbox badge in `lib/widget/otq_bottom_nav_bar.dart`
/// `_buildIcon`: `Stack(clipBehavior: Clip.none)` + `Positioned` +
/// `BoxConstraints(minWidth: 18, minHeight: 18)` + white ring +
/// `count > 99 ? '99+' : '$count'` (one rule, via [MenuBadge.badgeLabel]).
///
/// DELIBERATE DEVIATION from that mirror — fill colour. The bottom bar uses a
/// `red.shade400 -> red.shade600` gradient. Against white 11sp bold text that
/// is 3.49:1 (shade400) to 4.23:1 (shade600); 11sp bold is NOT WCAG "large
/// text", so the floor is 4.5:1 and both ends FAIL AA. Solid Material red 700
/// (`0xFFD32F2F`) is 4.98:1 and passes. Everything else is copied.
Widget _menuBadgeBubble(int count) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    decoration: BoxDecoration(
      color: const Color(0xFFD32F2F),
      borderRadius: BorderRadius.circular(10),
      // 2dp ring in the CARD colour — this is what separates the bubble from
      // the icon artwork behind it.
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Center(
      child: Text(
        MenuBadge.badgeLabel(count),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
          // tabular figures: 1 -> 2 digits must not shift the glyph baseline
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// Numeric "new since I last visited" badge for `HGR` / `VGR` grid children.
///
/// Entirely device-side: the server never sends a count. A grid child carries
/// the SAME collection address as the page it navigates to (`badgeTable` /
/// `badgeSearch` / `badgeVidtable` are copied verbatim from the destination
/// `LIST_ITEM_CARD`), so the badge can never disagree with the list the user
/// then opens.
///
/// Namespace class, all members static — same shape as `ScreenSession`
/// (`lib/screen_session.dart:21`). Feature state lives here, NOT in
/// `global.dart`.
class MenuBadge {
  MenuBadge._();

  /// SharedPreferences key prefix. Full key: `badgeSeen_<route>`, int, epoch ms.
  /// Documented in `documentation.md` -> "# Shared Persistence Keys:".
  /// Not reused for anything else.
  static const String seenKeyPrefix = 'badgeSeen_';

  /// Default timestamp field when `badgeTs` is blank.
  ///
  /// `MobileTableController.addContent` stamps `newData['t'] =
  /// getNowMillisecondFromEpoch()` on EVERY content document
  /// (`lib/states/mobile_table_controller.dart:137`), and keyed `//event` rows
  /// carry `t` too (live DSL `...⭘t◼◀2▶...`, op1Screen!D684). So `t` is the one
  /// universal per-row stamp.
  ///
  /// DO NOT configure `badgeTs` with a row-slot number. `<N>` in an
  /// `addToTable` DSL is a SLOT, not a field name: only the slots listed in
  /// `index◼...` are promoted to top-level document fields. The spec's
  /// `badgeTs:"12"` names a non-promoted slot -> `coerceNum(null)` -> a
  /// permanently-zero badge with no error.
  static const String defaultTsField = 't';

  /// Reactive SIGNAL only. The DATA lives in `prefs` (synchronous, not
  /// reactive). `build` reads this so the tile repaints after [markSeen];
  /// [markSeen] bumps it from the tap handler, OFF build.
  ///
  /// Deliberately NOT an `RxMap` seen-store: mutating an `RxMap` during build
  /// calls `refresh()` during build -> `setState() called during build`.
  /// Same pattern as `ExecutorDesignateCard.chosenRev`
  /// (`lib/widget/executor_designate_card.dart:46`).
  static final RxInt seenRev = 0.obs;

  /// Resolve the vid-scoped subscription code for a grid child and start the
  /// stream. Returns `''` when the item cannot carry a badge (no `badgeTable`,
  /// or no `route` to clear it with) -> the caller must then take the
  /// pre-badge render path (no `Obx`, no badge).
  ///
  /// Call this at PAGE-BUILD time (from `buildGridList`), not per frame.
  /// `subscribeToMapCollection` is idempotent per `code`, so repeated page
  /// construction does not multiply streams.
  static String codeFor(dynamic item) {
    try {
      final String rawTable = (item['badgeTable'] ?? '').toString().trim();
      // Hard gate: no badgeTable -> feature completely off for this item.
      if (rawTable.isEmpty) return '';
      // Second hard gate: the seen-store is keyed by `route` ([seenEpoch] /
      // [markSeen]), and [markSeen] only runs inside buildGridList's navigate
      // guard, which requires a route. A child with a badgeTable but NO route
      // would therefore read `seenEpoch('') == 0` forever with no way to ever
      // stamp it: the bubble lights on the first matching doc and NOTHING can
      // clear it. Refuse to render rather than ship a permanently-lit badge.
      if ((item['route'] ?? '').toString().trim().isEmpty) return '';
      // badgeVidtable > vidtable > getTableVid(com) > applicationTableVid.
      // `badgeVidtable` is the field name the SPEC fixes at grid-child level
      // (§3, §4, §7.2, §8, §11) — reading `vidtable` instead made deployed
      // config invisible: resolveAppVid fell through to applicationTableVid,
      // the badge counted another tenant's collection and sat at 0 forever
      // with no error and no log. Blank `badgeVidtable` keeps the shared
      // resolveAppVid chain, which IS the spec's "kosong = jatuh ke default
      // aplikasi" (and that default is "hampir selalu salah", spec §3.1).
      final String explicitVid = (item['badgeVidtable'] ?? '').toString().trim();
      final String appVid =
          explicitVid.isNotEmpty ? explicitVid : resolveAppVid(item);
      final TablePath tp = parseTablePath(rawTable);
      if (appVid.isEmpty || tp.tableDocId.isEmpty) return '';
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another
      // tenant's same tableDocId/subColl would dedup our stream away.
      // Table doc 84214220504259 exists under BOTH 60936087747650 (otq) and
      // 20342033315492 (con) with different content (api.dart:80-98).
      final String code = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, code);
      return code;
    } catch (e) {
      // buildGridList's per-item try/catch would otherwise swap the whole tile
      // for the `--GRID--` error card. Degrade to "no badge" instead.
      devPrint('MenuBadge.codeFor error: $e');
      return '';
    }
  }

  /// Last-visit epoch for [route], or 0 when never visited.
  ///
  /// Callers inside an `Obx` MUST also read [seenRev] — `prefs` is not
  /// reactive, so this value alone will not trigger a repaint.
  static int seenEpoch(String route) {
    // TRIM EXACTLY AS [markSeen] DOES — both must derive the same prefs key.
    // `routeExist` (global.dart:1522) is an exact `linkElement[page]` lookup
    // with no trim, so a sheet route carrying whitespace navigates fine while
    // an untrimmed read here would look up `badgeSeen_<space>x<space>` against
    // a `badgeSeen_x` written by [markSeen]: the badge would never clear, on
    // that tenant only, with no error.
    final String r = route.trim();
    if (r.isEmpty) return 0;
    try {
      return prefs.getInt('$seenKeyPrefix$r') ?? 0;
    } catch (e) {
      // `prefs` is `late` (global.dart:548, assigned in globalInit). A read
      // before that would be a LateInitializationError inside a build.
      devPrint('MenuBadge.seenEpoch error: $e');
      return 0;
    }
  }

  /// Stamp "visited now" for [route] and repaint any badge bound to it.
  ///
  /// Call ONLY from a tap handler (off build). `seenRev.value++` during build
  /// would be `setState() called during build`.
  ///
  /// Uses `getNowMillisecondFromEpoch()` (api.dart:1428) — the SAME NTP-
  /// corrected clock that stamps `t` on the documents being compared
  /// (mobile_table_controller.dart:137). A raw
  /// `DateTime.now().millisecondsSinceEpoch` would compare two different
  /// clocks and could leave the badge non-zero right after a visit. The
  /// function degrades to the raw device clock when the NTP reference keys are
  /// absent, so there is no new failure mode.
  static void markSeen(String route) {
    final String r = route.trim();
    if (r.isEmpty) return;
    try {
      prefs.setInt('$seenKeyPrefix$r', getNowMillisecondFromEpoch());
    } catch (e) {
      devPrint('MenuBadge.markSeen error: $e');
      return;
    }
    seenRev.value++;
  }

  /// Badge text. Same rule as the inbox badge in
  /// `lib/widget/otq_bottom_nav_bar.dart:191` — one rule for the whole app.
  static String badgeLabel(int count) => count > 99 ? '99+' : '$count';

  /// PURE count: how many docs are newer than [seen].
  ///
  /// No Firebase, no `prefs`, no widget — directly unit-testable
  /// (`test/menu_badge_test.dart`). The only global it reads is
  /// `transactionStore` (via `filterDriverHomeDocs` token resolution), which
  /// tests seed in `setUpAll`.
  ///
  /// [badgeTable] — raw `child['badgeTable']`. Blank = feature off -> 0.
  /// [docs] — raw docs from `mapTableContent[code]`.
  /// [rawSearch] — raw `child['badgeSearch']`. Pass RAW: `filterDriverHomeDocs`
  ///   runs `autheniumDecode` -> `resolveDriverCurlyTokens` ->
  ///   `resolveScreenTxTokens` -> `filterByMultiClause` internally
  ///   (driver_home_support.dart:975). Do NOT decode here.
  /// [tsField] — raw `child['badgeTs']`. Blank -> [defaultTsField] (`t`).
  /// [seen] — epoch ms from [seenEpoch].
  /// [scrName] — screen name for curly-token resolution.
  static int countFor({
    required String badgeTable,
    required List<Map<String, dynamic>> docs,
    required String rawSearch,
    required String tsField,
    required int seen,
    required String scrName,
  }) {
    if (badgeTable.trim().isEmpty) return 0;
    final String ts =
        tsField.trim().isEmpty ? defaultTsField : tsField.trim();

    final List<Map<String, dynamic>> matched =
        filterDriverHomeDocs(docs, rawSearch, scrName);

    _warnMissingSearchKey(badgeTable, docs, rawSearch);

    int count = 0;
    for (final Map<String, dynamic> d in matched) {
      // coerceNum: null/unparseable -> 0, so a doc with no (or a broken)
      // timestamp can never beat a non-negative `seen`. STRICTLY greater:
      // a doc stamped exactly at the visit instant is "already seen".
      if (coerceNum(d[ts]) > seen) count++;
    }
    return count;
  }

  /// Debug-only signal for ONE cause of a stuck-at-zero badge (D5): a
  /// `badgeSearch` key that is not a promoted `index◼` field is absent from
  /// the documents, so it reads as `''` in `filterByMultiClause` and matches
  /// nothing, SILENTLY.
  ///
  /// It detects NOTHING ELSE — in particular not the other silent zero:
  /// `filterByMultiClause` FAIL-CLOSES to an empty result when a clause's
  /// value is empty (`7◼`) or still holds an unresolved `{token}`
  /// (`7◼{driverVid}` on a screen with no driver context;
  /// driver_home_support.dart:949-953). Neither is detectable from the RAW
  /// `badgeSearch` string this function receives — `{driverVid}` looks
  /// identical before resolution whether or not it will resolve. A stuck badge
  /// with NO warning printed means "check the clause VALUES", not "the keys
  /// are fine".
  ///
  /// The WHOLE body is `kDebugMode`-gated, not just the `devPrint`
  /// (global.dart:2080): the decode, the split and the `docs.any(...)` scan
  /// would otherwise run in release on every `Obx` rebuild.
  static void _warnMissingSearchKey(
    String badgeTable,
    List<Map<String, dynamic>> docs,
    String rawSearch,
  ) {
    if (!kDebugMode) return;
    if (docs.isEmpty || rawSearch.trim().isEmpty) return;
    // Mirror filterByMultiClause's clause rules EXACTLY
    // (driver_home_support.dart:936-948): a blank clause, a clause with no
    // ◼, and a clause whose field part is empty are all `continue`d there,
    // so none of them is a search key. The previous `.split('◼').first`
    // returned the WHOLE clause instead, so a ◼-less fragment — the tail
    // of `7◼<vid>⭘garbage` — became a phantom key `garbage` that no
    // document carries, and the warning below fired "Badge will stay 0" on a
    // config that in fact counts correctly.
    final List<String> keys = <String>[];
    for (final String clause
        in (autheniumDecode(rawSearch) ?? rawSearch).split('\u{2B58}')) {
      final String trimmed = clause.trim();
      if (trimmed.isEmpty) continue;
      final int sep = trimmed.indexOf('\u{25FC}');
      if (sep < 0) continue;
      final String field = trimmed.substring(0, sep).trim();
      if (field.isEmpty) continue;
      keys.add(field);
    }
    if (keys.isEmpty) return;
    if (docs.any((Map<String, dynamic> d) => keys.every(d.containsKey))) return;
    devPrint(
      'MenuBadge: no doc in "$badgeTable" carries badgeSearch key(s) $keys — '
      'the key must be a field promoted by the writer\'s index◼ list, or a '
      'real keyed-collection field. Badge will stay 0.',
    );
  }
}
