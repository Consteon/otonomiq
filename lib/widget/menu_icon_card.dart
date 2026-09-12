import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart'; // DateFormat — device-local by construction

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../theme_tokens.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';
import 'time_presence.dart'; // parseLastAction, composeLedgerSearch, isSameLocalDay

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
  // ── v6 attendance tile ──────────────────────────────────────────────────
  // Only `variant == 'v6'` leaves the classic card. Every one of the eight
  // existing call sites omits these and renders byte for byte as before.
  String variant = '',
  String tone = 'in',
  String subtitle = '',
  String opMode = '',
  bool row = true,
  bool enabled = true,
  // v6 has TWO tile shapes and they are not interchangeable: the attendance
  // method tile (soft-filled block, label + caption) and the shortcut-grid
  // tile (soft icon square, label underneath, no fill behind the text).
  bool quick = false,
}) {
  if (variant.trim().toLowerCase() == 'v6' && quick) {
    return Builder(
      builder: (BuildContext context) => _quickTileV6(
        context: context,
        imageUrl: imageUrl,
        label: label,
        badgeCount: badgeCount,
        onTap: onTap,
      ),
    );
  }
  if (variant.trim().toLowerCase() == 'v6') {
    // Builder, not a context parameter: the tile needs Theme for the tenant
    // primary and the eight classic call sites must not grow an argument.
    return Builder(
      builder: (BuildContext context) => _attendanceTileV6(
        context: context,
        label: label,
        subtitle: attendSubtitle(subtitle, opMode),
        imageUrl: imageUrl,
        tone: tone,
        row: row,
        enabled: enabled,
        onTap: onTap,
      ),
    );
  }
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

// ─── v6 attendance block ────────────────────────────────────────────────────
// The Vertika v6 "Absen Masuk" / "Absen Pulang" blocks: a head, then a method
// grid whose shape follows the number of methods the sheet enabled.

/// Colours for one block. `masuk` follows the TENANT primary — the same source
/// the app bar and the location panel read, so the three can never drift.
/// `pulang` uses the design system's orange family, which is not per-tenant.
class AttendPalette {
  const AttendPalette({
    required this.fill,
    required this.pressed,
    required this.ink,
    required this.subtle,
  });

  final Color fill;
  final Color pressed;
  final Color ink;
  final Color subtle;

  static AttendPalette of(
    BuildContext context,
    String tone, {
    bool enabled = true,
  }) {
    if (!enabled) {
      return const AttendPalette(
        fill: OtqPalette.v6Muted,
        pressed: OtqPalette.v6Muted,
        ink: OtqPalette.v6DisabledFg,
        subtle: OtqPalette.v6DisabledFg,
      );
    }
    if (tone.trim().toLowerCase() == 'out') {
      return const AttendPalette(
        fill: OtqPalette.v6AccentSoft,
        pressed: OtqPalette.v6AccentSoftPressed,
        ink: OtqPalette.v6AccentText,
        subtle: OtqPalette.v6MutedFg,
      );
    }
    final Color primary = Theme.of(context).primaryColor;
    final Color fill = _softTint(primary, 0.93);
    // Measured, not assumed. Navy reads 12.3:1 on its own tint; a light tenant
    // primary would land at 2-3:1, which is the pairing v6 forbids outright.
    final Color ink = otqContrast(primary, fill) >= 4.5
        ? primary
        : OtqPalette.foreground;
    return AttendPalette(
      fill: fill,
      pressed: _softTint(primary, 0.84),
      ink: ink,
      subtle: OtqPalette.v6MutedFg,
    );
  }
}

/// The tenant primary lifted to a soft surface, keeping its hue.
///
/// An alpha blend over white does NOT reproduce v6's `--color-primary-soft`:
/// blending #001A72 at 12 % lands on #E0E4EE, visibly greyer than the #E3E8F8
/// the system specifies. Lifting LIGHTNESS in HSL and capping saturation gives
/// #E3E8F7 / #C0CAED -- v6's soft and soft-pressed to within one step -- while
/// still following whatever primaryColor the tenant's theme doc carries. The
/// saturation cap keeps a vivid brand colour from turning the tile neon.
/// Same idiom as otq_bottom_nav_bar.dart:83.
Color _softTint(Color primary, double lightness) {
  final HSLColor hsl = HSLColor.fromColor(primary);
  return hsl
      .withSaturation(hsl.saturation > 0.55 ? 0.55 : hsl.saturation)
      .withLightness(lightness)
      .toColor();
}

/// The head's right-hand meta, rendered from the event ledger instead of a
/// literal in the sheet.
///
/// Pure so it can be tested without Firestore. [epochMs] is the newest matching
/// event; null means nothing matched and the block says so.
///
/// v6 copy: `Terakhir 11:38` / `Terakhir kemarin 17:04` / `Belum ada` — never a
/// raw timestamp. Anything older than yesterday keeps the date, because "kemarin"
/// would be a lie and a bare clock time would be ambiguous.
String attendMetaLabel({
  required int? epochMs,
  required DateTime now,
  required String prefix,
  required String yesterday,
  required String none,
  required String format,
}) {
  if (epochMs == null) return none;
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final String clock = DateFormat(format).format(t);
  if (isSameLocalDay(epochMs, now)) return '$prefix $clock'.trim();
  // Indonesia has no DST, so subtracting 24h lands on the previous calendar
  // day. Revisit if this app ever ships to a DST timezone.
  if (isSameLocalDay(epochMs, now.subtract(const Duration(days: 1)))) {
    return '$prefix $yesterday $clock'.trim();
  }
  return '$prefix ${DateFormat('d MMM').format(t)} $clock'.trim();
}

/// Live block meta. Subscribes to the tenant event ledger and repaints when a
/// new attendance row lands, so "Terakhir" is never a stale literal.
///
/// Configured with exactly the keys TIME_PRESENCE already uses — `vidtable`,
/// `table`, `search`, `lastAction` — because they name the same things. Scope
/// the block to one event type with position 5 of `lastAction`
/// (`t◆desc◆t◆HH:mm◆ty◼clock-in`), which [composeLedgerSearch] AND-s onto
/// `search`.
///
/// This is the SECOND subscriber in this file, after MenuBadge. It is a
/// separate widget on purpose: [menuIconCard] itself stays free of Firestore
/// for its eight callers.
class AttendMeta extends StatefulWidget {
  const AttendMeta({
    required Key key,
    required this.component,
    required this.scrName,
    required this.prefix,
    required this.yesterday,
    required this.none,
    required this.style,
  }) : super(key: key);

  final dynamic component;
  final String scrName;
  final String prefix;
  final String yesterday;
  final String none;
  final TextStyle style;

  @override
  State<AttendMeta> createState() => _AttendMetaState();
}

class _AttendMetaState extends State<AttendMeta> {
  late final LastActionSpec _cfg;
  String _code = '';
  String _rawSearch = '';

  @override
  void initState() {
    super.initState();
    // Absent `lastAction` still has to work: the block's whole point is one
    // newest row by `t`, which is also this default.
    _cfg =
        parseLastAction((widget.component['lastAction'] ?? '').toString()) ??
        const LastActionSpec(
          sortField: 't',
          descending: true,
          valueField: 't',
          format: 'HH:mm',
          filter: '',
        );
    _rawSearch = (widget.component['search'] ?? '').toString();
    final TablePath tp = parseTablePath(
      (widget.component['table'] ?? '').toString(),
    );
    if (tp.tableDocId.isEmpty) return; // no table -> _code stays '' -> no rows
    final String appVid = resolveAppVid(widget.component);
    // The code MUST carry the appVid: mapTableContent is keyed by it alone and
    // the same tableDocId exists under more than one appVid.
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  @override
  Widget build(BuildContext context) {
    // Fail-closed, and NOT inside the Obx: an empty code would read
    // `mapTableContent['']`, a key any other widget with an unparseable
    // `table` also lands on. Say "nothing recorded" instead of rendering
    // whatever happens to be sitting there.
    //
    // ★ It must return BEFORE the Obx, not inside it: an Obx closure that
    // completes without touching an observable throws ObxError.
    if (_code.isEmpty) {
      return Text(
        widget.none,
        textAlign: TextAlign.right,
        maxLines: 2,
        style: widget.style,
      );
    }
    return Obx(() {
      // ★ Read the observable FIRST and unconditionally: an Obx closure that
      // returns before touching one throws ObxError.
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_code] ?? const [],
      );
      // Position 5 of `lastAction` AND-s onto the component `search`, so a
      // block scopes itself with `ty◼clock-in` without a second search key.
      final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
        docs,
        composeLedgerSearch(_rawSearch, _cfg.filter),
        widget.scrName,
      );
      final Map<String, dynamic>? doc = pickNewestDoc(
        matched,
        field: _cfg.sortField,
        descending: _cfg.descending,
      );
      return Text(
        attendMetaLabel(
          // The DAY comes from the sort field, which is always epoch ms; the
          // value field may legitimately hold text.
          epochMs: doc == null ? null : lastActionEpochMs(doc[_cfg.sortField]),
          now: DateTime.now(),
          prefix: widget.prefix,
          yesterday: widget.yesterday,
          none: widget.none,
          format: _cfg.format,
        ),
        textAlign: TextAlign.right,
        maxLines: 2,
        style: widget.style,
      );
    });
  }
}

/// Height every shortcut cell is laid out to: icon square + gap + two lines of
/// label + the tile's own vertical padding. Fixed so `childAspectRatio` can be
/// derived from the real cell width instead of guessed — a guessed ratio is
/// how a grid ends up overflowing on a narrow phone.
const double kQuickTileHeight = 92;

/// v6 `.quick` tile — a soft icon square with the label under it, no card.
///
/// One step below the mockup's 52 dp square / 24 dp icon / 13 px label, for the
/// same reason every other v6 surface here is: those sizes read oversized on a
/// real handset. The icon itself stays the tenant's PNG from the sheet.
Widget _quickTileV6({
  required BuildContext context,
  required String imageUrl,
  required String label,
  int badgeCount = 0,
  VoidCallback? onTap,
}) {
  final AttendPalette pal = AttendPalette.of(context, 'in');
  final Widget square = Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: pal.fill,
      borderRadius: BorderRadius.circular(14),
    ),
    child: SizedBox(
      width: 24,
      height: 24,
      child: displayImage(
        imageUrl: imageUrl.isEmpty ? defaultImage : imageUrl,
        cached: true,
        fit: BoxFit.contain,
      ),
    ),
  );
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The badge hangs off the SQUARE, not the cell, so it lands in the
            // same place whatever the label wraps to.
            if (badgeCount <= 0)
              square
            else
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  square,
                  Positioned(
                    right: -6,
                    top: -6,
                    child: _menuBadgeBubble(badgeCount),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            // Flexible: a long two-line label shrinks rather than overflowing
            // the fixed grid cell.
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: OtqPalette.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Type for the head's right-hand meta, shared by the literal and live paths.
const TextStyle attendMetaStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.25,
  color: OtqPalette.v6MutedFg,
);

/// Tile shape for a block of [methodCount] methods.
///
/// Horizontal (`.method.row`) for every count except three: three tiles only
/// fit one row as the taller vertical shape, which is what v6's grid table
/// says. Kept separate from the dispatch branch so the rule is testable.
bool attendRowShape(int methodCount) => methodCount != 3;

/// The caption to draw: the sheet's own `subtitle` when it carries one, else
/// the [attendSubtitleFor] default for this `opMode`.
///
/// Blank, whitespace-only and the global `--` sentinel all count as "not set".
/// Without that, a tenant who clears the cell — or types the sentinel the rest
/// of the sheet uses for an empty value — ships a tile with a blank second
/// line or a literal "--" under the label.
String attendSubtitle(String fromJson, String opMode) {
  final String s = fromJson.trim();
  if (s.isNotEmpty && s != empty) return s;
  return attendSubtitleFor(opMode);
}

/// v6 copy rule: the caption says what happens NEXT, it does not repeat the
/// label. A `subtitle` in the JSON always wins over this default.
String attendSubtitleFor(String opMode) {
  switch (opMode.trim().toLowerCase()) {
    case 'qr-single':
    case 'qr-checker-single':
    case 'qr-checker-continuous':
      return 'Pindai di pos';
    case 'qr-selfie':
      return 'Pindai, lalu foto';
    case 'selfie':
      return 'Foto wajah';
    case 'gps-single':
      return 'Pakai lokasi';
    default:
      return '';
  }
}

/// One method tile. Two shapes, one family: [row] is the mockup's
/// `.method.row` (64 dp, icon left) and otherwise `.method.col` (92 dp, icon
/// above). Both clear the 48 dp touch minimum on their own.
Widget _attendanceTileV6({
  required BuildContext context,
  required String label,
  required String subtitle,
  required String imageUrl,
  required String tone,
  required bool row,
  required bool enabled,
  VoidCallback? onTap,
}) {
  final AttendPalette pal = AttendPalette.of(context, tone, enabled: enabled);
  // The icon is the tenant's own PNG from the sheet, exactly as every other
  // menu tile in this app. It carries its own colours, so `pal.ink` styles the
  // text only.
  final Widget glyph = SizedBox(
    width: 22,
    height: 22,
    child: displayImage(
      imageUrl: imageUrl.isEmpty ? defaultImage : imageUrl,
      cached: true,
      fit: BoxFit.contain,
    ),
  );
  final Widget labelText = Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: row ? TextAlign.left : TextAlign.center,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: pal.ink,
    ),
  );
  final Widget? subText = subtitle.isEmpty
      ? null
      : Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: row ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: pal.subtle,
          ),
        );

  return Material(
    color: pal.fill,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      // v6: press feedback is a background change only, never a transform.
      onTap: enabled ? onTap : null,
      highlightColor: pal.pressed,
      child: SizedBox(
        // Still clear of the 48 dp touch minimum on its own, in both shapes.
        height: row ? 56 : 80,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: row ? 10 : 6),
          child: row
              ? Row(
                  children: <Widget>[
                    glyph,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          labelText,
                          if (subText != null) ...<Widget>[
                            const SizedBox(height: 2),
                            subText,
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    glyph,
                    const SizedBox(height: 4),
                    labelText,
                    if (subText != null) ...<Widget>[
                      const SizedBox(height: 2),
                      subText,
                    ],
                  ],
                ),
        ),
      ),
    ),
  );
}

/// Head + adaptive grid.
///
/// The grid shape is derived from how many methods the sheet enabled, per the
/// v6 table: 1-2 stay horizontal tiles on one row, 3 become vertical tiles so
/// three still fit one row, 4 go 2x2, and anything beyond 4 keeps wrapping in
/// pairs rather than shrinking a tile below its label.
Widget attendanceBlockV6({
  required BuildContext context,
  required String title,
  required String meta,
  required String tone,
  required String emptyText,
  required List<Widget> tiles,
  bool rule = true,
  Widget? metaWidget,
}) {
  final AttendPalette pal = AttendPalette.of(context, tone);
  final bool out = tone.trim().toLowerCase() == 'out';
  const double gap = 8;

  Widget pair(List<Widget> two) => Row(
    children: <Widget>[
      Expanded(child: two[0]),
      if (two.length > 1) ...<Widget>[
        const SizedBox(width: gap),
        Expanded(child: two[1]),
      ],
    ],
  );

  Widget grid;
  if (tiles.isEmpty) {
    // Misconfiguration is visible, not silent: the block still appears and
    // says who to ask.
    grid = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: OtqPalette.v6Muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Color(0xFFA16207),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              emptyText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: OtqPalette.v6MutedFg,
              ),
            ),
          ),
        ],
      ),
    );
  } else if (tiles.length == 1) {
    grid = tiles.first;
  } else if (tiles.length == 3) {
    grid = Row(
      children: <Widget>[
        Expanded(child: tiles[0]),
        const SizedBox(width: gap),
        Expanded(child: tiles[1]),
        const SizedBox(width: gap),
        Expanded(child: tiles[2]),
      ],
    );
  } else {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(
        pair(tiles.sublist(i, i + 2 > tiles.length ? tiles.length : i + 2)),
      );
    }
    grid = Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  return Padding(
    // The page pads the body by the sheet's `leftPad` (8 in this workbook);
    // v6 specifies a 16 dp content edge (`.content{padding:0 16px}`), so top up
    // the difference. The rule sits INSIDE it, as in the mockup, where
    // `.rule` carries no negative side margin.
    padding: otqContentInset(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // v6 separates the flat home sections with a 1 dp rule instead of
        // boxing each one in a card. Drawn by the block itself so no divider
        // component has to be threaded into the screen JSON.
        if (rule) ...<Widget>[
          const SizedBox(height: 4),
          Container(height: 1, color: OtqPalette.v6Border),
          const SizedBox(height: 16),
        ],
        if (title.isNotEmpty) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(out ? Icons.logout : Icons.login, size: 20, color: pal.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Matches the "Absensi hari ini" strip above it; v6's own
                  // 18/600 read a step too loud next to 12 dp captions.
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: OtqPalette.foreground,
                  ),
                ),
              ),
              // A live meta wins over the sheet literal; v6 pins either to the
              // FAR right of the head row.
              //
              // ★ The meta must be INFLEXIBLE. An Expanded title beside a
              // Flexible meta splits the free space 50/50 before either child is
              // measured, so the meta shrink-wraps inside its half and stops
              // mid-row with a gap after it. Inflexible + Expanded title is what
              // actually pins it right: the meta takes its intrinsic width and
              // the title absorbs everything left over.
              //
              // The cap keeps a long meta from starving the title — a
              // non-flexible child is measured with UNBOUNDED width, so without
              // it "Terakhir kemarin 17:04" would never wrap and a longer string
              // could push the title to nothing. 180 fits every string v6
              // specifies at 13/500 and still leaves ~200 for the title at 390dp.
              if (metaWidget != null || meta.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child:
                      metaWidget ??
                      Text(
                        meta,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        style: attendMetaStyle,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        grid,
      ],
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
      final String explicitVid = (item['badgeVidtable'] ?? '')
          .toString()
          .trim();
      final String appVid = explicitVid.isNotEmpty
          ? explicitVid
          : resolveAppVid(item);
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
    final String ts = tsField.trim().isEmpty ? defaultTsField : tsField.trim();

    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      docs,
      rawSearch,
      scrName,
    );

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
    for (final String clause in (autheniumDecode(rawSearch) ?? rawSearch).split(
      '\u{2B58}',
    )) {
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
