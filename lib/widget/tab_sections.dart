import 'package:flutter/material.dart';

import '../global.dart';
import '../theme_tokens.dart';

/// `TAB` — one component that owns several page sections and decides how they
/// are laid out: stacked on the page, collapsed behind a "Lainnya" link, or
/// switched by an underline tab bar.
///
/// The three modes exist so that ONE field in the screen JSON moves the
/// Formulir / Log / Terbaru sections between the home page and a separate menu
/// page. Nothing about the sections themselves changes — they are ordinary
/// components (`HGR`, `TXT`, …) built by `buildDisplayComponent` before they
/// ever reach this widget, and each one keeps its own `variant`.
///
///   `inline`  every section stacked, each under its own heading. No tab bar,
///             no link. This is what the home page renders today.
///   `link`    the first section only, plus a link that pushes `route`.
///   `tab`     an underline tab bar, one section visible at a time.
///
/// [v6] gates the LOOK, never the structure: a `TAB` with no `variant:"v6"`
/// draws plain headings and a `primaryColor` underline, so a screen that has
/// not moved to v6 can still use the component.

/// One labelled group of already-built page components.
class TabSection {
  const TabSection(this.label, this.children);

  final String label;
  final List<Widget> children;
}

/// Groups built children by the `tab` index each declared, ascending, pairing
/// each group with its label.
///
/// Takes ONE list of (index, widget) pairs rather than two parallel lists:
/// parallel arrays are how a grid ends up showing the wrong label under the
/// wrong tile. Indexes may be sparse (0, 2) — the order is by index, and a
/// group whose index is past the end of [labels] simply gets no heading.
List<TabSection> groupTabSections(
  List<MapEntry<int, Widget>> built,
  List<String> labels,
) {
  final Map<int, List<Widget>> byTab = <int, List<Widget>>{};
  for (final MapEntry<int, Widget> e in built) {
    byTab.putIfAbsent(e.key, () => <Widget>[]).add(e.value);
  }
  final List<int> keys = byTab.keys.toList()..sort();
  return <TabSection>[
    for (final int k in keys)
      TabSection(k >= 0 && k < labels.length ? labels[k] : '', byTab[k]!),
  ];
}

/// The `TAB` component of [scrName], or null when that screen has none.
///
/// Lets a menu screen borrow the sections that already live on home
/// (`"source":"<screen>"`) instead of duplicating a 23-item grid into a second
/// cell, where the two copies would drift apart with nothing to catch it.
dynamic findTabComponent(String scrName) {
  try {
    final dynamic kids = screenUIComponent?[scrName]?['children'];
    if (kids is List) {
      for (final dynamic c in kids) {
        if (c is Map &&
            (c['type'] ?? '').toString().trim().toLowerCase() == 'tab') {
          return c;
        }
      }
    }
  } catch (_) {
    // screenUIComponent is null, empty, or not a Map — no source, no borrow.
  }
  return null;
}

/// The children a `TAB` builds: the borrowed ones first, then its own.
///
/// `source` ADDS to a borrowed menu rather than replacing it, so a screen can
/// append one block — a log preview, say — without duplicating every grid it
/// borrowed. Replacing would drop the local children silently, and a block that
/// simply never appears is the worst kind of config bug.
///
/// [host] is [component] itself when there is no `source`; the identity check
/// is what stops the children being counted twice in that case.
List<dynamic> tabChildren(dynamic component, dynamic host) {
  final dynamic borrowed = host is Map ? host['children'] : null;
  final dynamic own = component is Map ? component['children'] : null;
  return <dynamic>[
    if (borrowed is List) ...borrowed,
    if (!identical(host, component) && own is List) ...own,
  ];
}

class TabSections extends StatefulWidget {
  const TabSections({
    super.key,
    required this.scrName,
    required this.sections,
    this.mode = '',
    this.v6 = false,
    this.link = '',
    this.route = '',
  });

  final String scrName;
  final List<TabSection> sections;

  /// `inline` | `link` | `tab`. Anything else — absent, misspelt — renders
  /// `inline`, which shows every section. An unreadable flag must not be able
  /// to hide content.
  final String mode;
  final bool v6;

  /// Link label for `link` mode, e.g. "Lainnya". Blank falls back to `Lainnya`.
  final String link;
  final String route;

  /// Selected tab, keyed per screen.
  ///
  /// Static rather than State on purpose: `any_page` re-runs `buildPage` inside
  /// its StoreConnector builder, so an unrelated redux dispatch rebuilds the
  /// whole page and mints a fresh widget tree. A selection held in State would
  /// jump back to the first tab every time that happened.
  static final Map<String, int> activeTab = <String, int>{};

  static void clear(String scrName) => activeTab.remove(scrName);

  @override
  State<TabSections> createState() => _TabSectionsState();
}

class _TabSectionsState extends State<TabSections> {
  /// Resolves [TabSections.mode] against what the config can actually support.
  ///
  /// Both narrowing rules fail OPEN, to `inline`:
  ///   - `link` needs a `route` that some screen actually declares. Gated on
  ///     `screenUIComponent`, NOT on `routeExist`: `routeExist` reads
  ///     `linkElement`, which is filled screen by screen, so gating on it would
  ///     make the rendering depend on which screen was built first.
  ///   - `tab` with a single section is a tab bar with one tab.
  ///
  /// Getting this backwards would hide three quarters of the menu behind a link
  /// that goes nowhere, which is exactly the failure a typo'd route should not
  /// be able to cause.
  String get _mode {
    final String m = widget.mode.trim().toLowerCase();
    if (widget.sections.length < 2) return 'inline';
    if (m == 'tab') return 'tab';
    if (m == 'link') {
      final String r = widget.route.trim();
      bool declared = false;
      try {
        declared = r.isNotEmpty && screenUIComponent?[r] != null;
      } catch (_) {
        declared = false;
      }
      if (declared) return 'link';
    }
    return 'inline';
  }

  int get _index {
    final int i = TabSections.activeTab[widget.scrName] ?? 0;
    return i >= 0 && i < widget.sections.length ? i : 0;
  }

  void _goto() {
    final String r = widget.route.trim();
    // Same guard as buildGridList's card tap: an unbuilt route must not push a
    // stack entry the AppBar back button would later pop into nothing.
    if (r.isEmpty || !routeExist(r)) {
      devPrint('TAB: route "$r" does not exist — link ignored');
      return;
    }
    routeStack.push(r); // BEFORE gotoRoute — back navigation pops this stack
    gotoRoute(r);
  }

  /// Delegates to the shared [otqSectionHead] so this heading and the log
  /// card's heading — which sit on the same screen, one under the other —
  /// cannot drift apart.
  Widget _head(String label, bool withLink) => otqSectionHead(
    context: context,
    label: label,
    v6: widget.v6,
    linkLabel: withLink
        ? (widget.link.trim().isEmpty ? 'Lainnya' : widget.link.trim())
        : '',
    onLink: withLink ? _goto : null,
  );

  Widget _tabBar() {
    final Color primary = Theme.of(context).primaryColor;
    final int active = _index;
    // Expanded tabs cannot overflow, so a fifth or sixth tab ellipsizes instead
    // of throwing a RenderFlex error. v6 only ever specifies four.
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OtqPalette.v6Border)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < widget.sections.length; i++)
            Expanded(
              child: InkWell(
                onTap: () =>
                    setState(() => TabSections.activeTab[widget.scrName] = i),
                child: SizedBox(
                  height: 44,
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Center(
                          child: Text(
                            widget.sections[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: i == active
                                  ? primary
                                  : (widget.v6
                                        ? OtqPalette.v6MutedFg
                                        : OtqPalette.mutedFg),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          // v6 spends its single orange on this underline;
                          // without the variant the indicator stays on brand.
                          color: i == active
                              ? (widget.v6
                                    ? OtqPalette.v6AccentStrong
                                    : primary)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();
    final String mode = _mode;

    if (mode == 'tab') {
      final int i = _index;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(padding: otqContentInset(), child: _tabBar()),
          const SizedBox(height: 16),
          ...widget.sections[i].children,
        ],
      );
    }

    final List<TabSection> shown = mode == 'link'
        ? widget.sections.take(1).toList()
        : widget.sections;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final TabSection s in shown) ...<Widget>[
          if (s.label.isNotEmpty) _head(s.label, mode == 'link'),
          ...s.children,
        ],
      ],
    );
  }
}
