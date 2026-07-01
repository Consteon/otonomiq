import 'package:flutter/material.dart';

import '../global.dart';
import 'admin_home_support.dart';
import 'panel_card_support.dart';

/// A notification strip/callout rendered from server JSON.
///
/// Displays an optional left accent bar (when [label] or [title] present),
/// an optional left icon gutter, and up to 3 text tiers: eyebrow label
/// (UPPERCASE), bold title (dark neutral), and body text (variant color,
/// supports inline **bold** and *italic*).
///
/// Colors are determined by [variant] via [statusColor]/[statusBgColor].
/// Pure display except for an optional trailing CTA: when both `actionText`
/// and `actionRoute` are set, a compact violet [TextButton] renders to the
/// right of the text and navigates via `routeStack.push` + `gotoRoute`
/// (dead-route guarded). No txfController, no Redux.
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  Widget build(BuildContext context) {
    final String variant = (component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final String iconKey = (component['icon'] ?? '').toString().trim();
    final String iconAlign = (component['iconAlign'] ?? 'center')
        .toString()
        .trim()
        .toLowerCase();
    final String label = (component['label'] ?? '').toString().trim();
    final String title = (component['title'] ?? '').toString().trim();
    final String text = (component['text'] ?? '').toString().trim();
    final String actionText = (component['actionText'] ?? '').toString().trim();
    final String actionRoute = (component['actionRoute'] ?? '')
        .toString()
        .trim();
    final bool hasAction = actionText.isNotEmpty && actionRoute.isNotEmpty;

    // If all display content is empty, render nothing.
    if (label.isEmpty && title.isEmpty && text.isEmpty) {
      return const SizedBox.shrink();
    }

    final Color fgColor = statusColor(variant);
    final Color bgColor = statusBgColor(variant);
    final bool hasBar = label.isNotEmpty || title.isNotEmpty;
    final bool hasIcon = iconKey.isNotEmpty;

    // -- Build text tiers --------------------------------------------------
    final List<Widget> tiers = [];

    if (label.isNotEmpty) {
      tiers.add(
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: fgColor,
          ),
        ),
      );
    }

    if (title.isNotEmpty) {
      if (tiers.isNotEmpty) tiers.add(const SizedBox(height: 6));
      tiers.add(
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: Color(0xFF1F2937),
          ),
        ),
      );
    }

    if (text.isNotEmpty) {
      if (tiers.isNotEmpty) tiers.add(const SizedBox(height: 6));
      final TextStyle bodyBase = TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: fgColor,
      );
      final List<InlineSpan> spans = parseInlineEmphasis(text, bodyBase);
      tiers.add(
        Text.rich(TextSpan(children: spans), textAlign: TextAlign.left),
      );
    }

    final Widget textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: tiers,
    );

    // -- Build trailing CTA (if configured) --------------------------------
    Widget? ctaButton;
    if (hasAction) {
      ctaButton = TextButton(
        onPressed: () {
          if (!routeExist(actionRoute)) return;
          routeStack.push(actionRoute);
          gotoRoute(actionRoute);
        },
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: Text(
          actionText,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AdminTierColors.warnBadgeText, // violet 0xFF7C3AED
          ),
        ),
      );
    }

    // -- Build icon + text row (if icon present) + trailing CTA -----------
    final Widget content;
    if (hasIcon) {
      content = Row(
        crossAxisAlignment: iconAlign == 'top'
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(panelIcon(iconKey), size: 24, color: fgColor),
          ),
          Expanded(child: textColumn),
          if (ctaButton != null) ...[const SizedBox(width: 8), ctaButton],
        ],
      );
    } else {
      content = hasAction
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: textColumn),
                const SizedBox(width: 8),
                ctaButton!,
              ],
            )
          : textColumn;
    }

    // -- Build accent bar + content row (if bar present) -------------------
    final Widget body;
    if (hasBar) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 4.0, minWidth: 4.0),
              color: fgColor,
            ),
            Expanded(
              child: Padding(padding: const EdgeInsets.all(18), child: content),
            ),
          ],
        ),
      );
    } else {
      body = Padding(padding: const EdgeInsets.all(18), child: content);
    }

    // -- Outer container with bg color, margins, paddings ------------------
    final List<double> margin = marginArray(
      (component['margin'] ?? '').toString().isEmpty
          ? null
          : component['margin'].toString(),
    );

    return Container(
      margin: EdgeInsets.only(
        top: (component['beforeSpacing'] ?? 0.0).toDouble() + margin[0],
        bottom: (component['afterSpacing'] ?? 0.0).toDouble() + margin[1],
      ),
      padding: EdgeInsets.fromLTRB(
        lPad + margin[2],
        tPad,
        rPad + margin[3],
        bPad,
      ),
      child: Container(
        key: const ValueKey('noticeBarBox'),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: hasBar ? IntrinsicHeight(child: body) : body,
      ),
    );
  }
}

// ── Inline emphasis parser ──────────────────────────────────────────────────

/// Matches `**bold**` first, then `*italic*`.
/// `.+?` ensures non-greedy (shortest match).
final RegExp _emphasisRe = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');

/// Parse inline `**bold**` and `*italic*` markers in [src] into a list of
/// [TextSpan]s styled relative to [base].
///
/// Grammar:
/// - `**text**` -> FontWeight.w700
/// - `*text*`   -> FontStyle.italic
/// - Unmatched/lone markers are rendered as literal text.
/// - Non-nested: markers are not recursive.
///
/// Returns an empty list for an empty [src].
List<InlineSpan> parseInlineEmphasis(String src, TextStyle base) {
  if (src.isEmpty) return const [];

  final List<InlineSpan> spans = [];
  int pos = 0;

  for (final Match m in _emphasisRe.allMatches(src)) {
    // Literal text before this match
    if (m.start > pos) {
      spans.add(TextSpan(text: src.substring(pos, m.start), style: base));
    }

    if (m.group(1) != null) {
      // **bold**
      spans.add(
        TextSpan(
          text: m.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      // *italic*
      spans.add(
        TextSpan(
          text: m.group(2),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    pos = m.end;
  }

  // Trailing literal text
  if (pos < src.length) {
    spans.add(TextSpan(text: src.substring(pos), style: base));
  }

  // If no matches at all, return a single literal span
  if (spans.isEmpty) {
    return [TextSpan(text: src, style: base)];
  }

  return spans;
}
