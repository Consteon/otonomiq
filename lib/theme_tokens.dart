import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'global.dart';

/// Vertika v4 design-token access.
///
/// Two kinds of colour live here and they are NOT interchangeable:
///
///  - [otqColor] reads a **brand** colour out of the server-driven theme map
///    (`systemUIComponent[theme]`, filled per tenant from the Sheets-backed
///    `Proxy/{lif}/System` doc). Absent key -> the caller's fallback, so a
///    tenant that never edits its sheet keeps exactly the colours it has now.
///  - [OtqPalette] holds **accessibility** colours as constants. Those are not
///    per-brand choices, they are the values that pass WCAG, so keying them
///    would only let a tenant opt back in to unreadable text. Promoting one to
///    a sheet key later is a two-line change if a brand ever really needs it.
///
/// Nothing here imports Firebase or bloc; it is safe to pull into any widget.

/// Reads a colour out of the server-driven theme map, degrading to [fallback]
/// instead of throwing.
///
/// Mirrors `themeColor` in `lib/page/vertriz_app.dart`, which now delegates
/// here. Three real states reach this function and all three must degrade:
///   - `systemUIComponent` is null      (global.dart declares it bare `dynamic`)
///   - `systemUIComponent` is `{}`      (the init/reset routine)
///   - the tenant sheet omits the key
///
/// `v is num` also covers the sheet value arriving as `double` rather than
/// `int`, which `Color(x)` would otherwise throw a TypeError on.
Color otqColor(String key, Color fallback) {
  try {
    final dynamic v = systemUIComponent?[theme]?[key];
    if (v is num) return Color(v.toInt());
  } catch (_) {
    // systemUIComponent is not a Map at all.
  }
  return fallback;
}

/// v4 semantic colours. Constants on purpose -- see the file header.
abstract class OtqPalette {
  /// Primary text on a light surface. 15.01:1 on white.
  static const Color foreground = Color(0xFF0F2A33);

  /// Secondary text on a light surface. 6.73:1 on white; replaces the
  /// `#9CA3AF` (2.54:1) and `Colors.grey.shade400` (1.88:1) this app shipped.
  static const Color mutedFg = Color(0xFF4A5F66);

  /// Rules, dividers, input borders.
  static const Color border = Color(0xFFE2E8EA);

  /// Status colours for text/marks on a LIGHT surface.
  static const Color successText = Color(0xFF047857); // 5.48:1 on white
  static const Color warningText = Color(0xFF854D0E); // 6.85:1 on white
  static const Color dangerText = Color(0xFFB91C1C); // 6.47:1 on white

  // ── v6 ────────────────────────────────────────────────────────────────
  // The v6 system keeps navy as primary (which is already this app's
  // `primaryColor`) and gives the ORANGE family a second job: the identity of
  // the "Absen Pulang" block. That family is a design-system constant, not a
  // tenant colour, so it lives here. Ratios are v6's own `cek-kontras.py`.

  /// Tile background for the pulang block. Pairs with [v6AccentText] 5.6:1.
  static const Color v6AccentSoft = Color(0xFFFEF0E3);
  static const Color v6AccentSoftPressed = Color(0xFFFAE0C4);

  /// Icons only — 3.6:1 on white clears the non-text bar, not the text one.
  static const Color v6AccentStrong = Color(0xFFD9640A);

  /// Labels in the pulang block. 6.3:1 on white, 5.6:1 on [v6AccentSoft].
  static const Color v6AccentText = Color(0xFF9A4A05);

  /// A FILLED accent CTA — the one strong action on an otherwise empty screen
  /// (v6 `--color-accent` / `--color-on-accent`). The pair measures 6.94:1, so
  /// unlike [v6AccentStrong] it carries a label, not just an icon. White on
  /// this orange is 2.67:1 and must never be used.
  static const Color v6Accent = Color(0xFFF08118);
  static const Color v6OnAccent = Color(0xFF1A1206);

  /// Section rule. v6 calls `--color-border` a decorative separator only
  /// (1.25:1) -- never the boundary of a control, which owes 3:1.
  static const Color v6Border = Color(0xFFE2E6EE);

  /// v6 neutrals are navy-toned where the v4 set above is teal-toned. Only the
  /// attendance block uses these so far; the two sets deliberately coexist
  /// until the rest of the app moves over.
  static const Color v6Muted = Color(0xFFEEF0F4);
  static const Color v6MutedFg = Color(0xFF475569); // 7.58:1 on white
  static const Color v6DisabledFg = Color(0xFF949DB3); // 2.72:1 — v6 calls
  // this "sengaja rendah"; used ONLY for a disabled tile, never live text.

  /// v6 status MARKS on a LIGHT surface -- the 12 dp dot beside a status word,
  /// and the map's own geometry. Non-text, so the bar is 3:1, and these
  /// measure 3.77 / 4.83 / 3.65 on white. The label beside each dot stays
  /// [successText] / [dangerText] / [v6MutedFg], which clear the 4.5:1 text
  /// bar. Same rule as the on-dark set below: colour the mark, not the label.
  static const Color v6SuccessMark = Color(0xFF059669);
  static const Color v6DangerMark = Color(0xFFDC2626);
  static const Color v6BorderStrong = Color(0xFF7B869F);

  /// Ground for a warning callout. [warningText] on it measures 6.48:1.
  static const Color v6WarningSoft = Color(0xFFFEF9E3);

  /// Grounds for the other two chip tones. Measured against the matching
  /// `*Text` colour: [successText] on [v6SuccessSoft] is 4.91:1, [dangerText]
  /// on [v6DangerSoft] is 5.91:1, so a chip label clears the 4.5:1 text bar on
  /// all three tones -- the indigo chip they replace was one colour for every
  /// meaning.
  static const Color v6SuccessSoft = Color(0xFFE6F6EF);
  static const Color v6DangerSoft = Color(0xFFFEF2F2);

  /// The teal that marks "you" on a map (v6 `--color-secondary`). 3.35:1 on
  /// white: a mark, never a label. Deliberately NOT the navy the geofence uses
  /// -- the whole point of the v6 map is that the two objects cannot be
  /// confused for each other.
  static const Color v6Secondary = Color(0xFF0F9AB0);

  /// Status colours for marks on a DARK surface. Non-text only: measured on
  /// `#0B6E80` these are 3.87 / 5.07 / 3.11, so they clear the 3:1 bar for a
  /// dot or icon but NOT the 4.5:1 bar for a label. Colour the dot, keep the
  /// label in the foreground colour.
  static const Color successOnDark = Color(0xFF6EE7B7);
  static const Color warningOnDark = Color(0xFFFEF08A);
  static const Color dangerOnDark = Color(0xFFFCA5A5);
}

/// WCAG 2.1 contrast ratio between two opaque colours, 1.0 .. 21.0.
///
/// `dart:math` is imported prefixed: an unprefixed import pulls in `e`, which
/// silently shadows a `catch (e)` variable elsewhere in a file.
double otqContrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Extra horizontal padding so a redesigned widget sits on the design
/// system's content edge, whatever the page's own padding happens to be.
///
/// `main_page.dart:223` pads the whole body with
/// `systemUIComponent['Mobile']['leftPad']`, which this workbook sets to **8**.
/// Both v4 and v6 specify a 16 dp content edge (`--space-md`, "tepi konten"),
/// so a widget that wants to honour the system has to make up the difference.
///
/// Topping UP rather than hardcoding 8 matters: if the sheet's `leftPad` is
/// ever raised to 16, this returns zero and nothing double-pads. It never
/// returns a negative inset, so a page padded wider than [target] is left
/// alone rather than pulled back out.
EdgeInsets otqContentInset({double target = 16}) {
  double read(String key) {
    try {
      final dynamic v = systemUIComponent?['Mobile']?[key];
      if (v is num) return v.toDouble();
    } catch (_) {
      // systemUIComponent is null, empty, or not a Map — page padding is 0.
    }
    return 0;
  }

  final double left = target - read('leftPad');
  final double right = target - read('rightPad');
  return EdgeInsets.only(
    left: left > 0 ? left : 0,
    right: right > 0 ? right : 0,
  );
}

/// The readable foreground for [background]: whichever of white and
/// [OtqPalette.foreground] actually measures higher against it.
///
/// Deliberately NOT a luminance threshold. A `computeLuminance() < 0.5` test
/// picks white on `#F08118` (2.67:1), `#1CACC4` (2.71:1) and `#059669`
/// (3.77:1) -- three failures, and exactly the white-on-brand pairing the v4
/// system forbids. Mid-luminance colours land on the wrong side of any fixed
/// threshold; comparing the two candidates is correct by construction.
Color otqOn(Color background) =>
    otqContrast(Colors.white, background) >=
        otqContrast(OtqPalette.foreground, background)
    ? Colors.white
    : OtqPalette.foreground;

/// The section heading shared by every v6 block on a page: an optional 1 dp
/// rule, the label, and an optional right-hand link.
///
/// A widget rather than a token, and here rather than in one of the two callers,
/// because the tabbed sections and the log card sit on the SAME screen one under
/// the other — two copies of this would drift and the drift would be visible.
///
/// [v6] gates the look only: without it the heading is the app's plain 18 pt
/// text with no rule, so a pre-v6 screen keeps what it has.
///
/// The heading is 16, not v6's own 18: on the home page it sits directly under
/// the 16/600 "Absen Pulang" head, and matching the screen beats matching the
/// mockup in isolation.
Widget otqSectionHead({
  required BuildContext context,
  required String label,
  bool v6 = false,
  String linkLabel = '',
  VoidCallback? onLink,
}) {
  final Color primary = Theme.of(context).primaryColor;
  final String link = linkLabel.trim();
  final bool withLink = link.isNotEmpty && onLink != null;
  return Padding(
    // The page pads the body by the sheet's `leftPad`; v6 wants a 16 dp content
    // edge. Block CONTENT pads itself, so only the heading is topped up here.
    padding: otqContentInset(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (v6) ...<Widget>[
          const SizedBox(height: 4),
          Container(height: 1, color: OtqPalette.v6Border),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: v6 ? 16 : 18,
                  fontWeight: v6 ? FontWeight.w600 : FontWeight.normal,
                  height: 1.2,
                  color: v6 ? OtqPalette.foreground : null,
                ),
              ),
            ),
            // ★ INFLEXIBLE. An Expanded heading beside a Flexible link splits
            // the free space 50/50 before either is measured, which strands the
            // link mid-row instead of pinning it right.
            if (withLink)
              InkWell(
                onTap: onLink,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  // 44 dp minimum touch target; the label alone is ~18 dp.
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          link,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: primary),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    ),
  );
}
