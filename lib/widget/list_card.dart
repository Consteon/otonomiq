import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'list_card_support.dart';
import 'panel_card_support.dart';

/// LIST_CARD -- universal config-driven keyed list renderer.
///
/// Subscribes to a single Firestore map-collection, filters/sorts/groups
/// client-side, renders a card list with optional header, stats strip, search
/// bar, group accordion, badge, and trailing value.
///
/// All display strings come from config (spec rule 2: no hardcoded labels).
/// Empty optional fields = element not rendered (spec rule 6).
///
/// Card tap navigates via routeParams (multi-pair, row-first resolution).
class ListCard extends StatefulWidget {
  const ListCard({
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
  final double lPad, tPad, rPad, bPad;

  @override
  State<ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<ListCard> {
  String _code = '';
  String _gateCode = '';
  String _rawGateSearch = '';
  GateSlotConfig _gateSlotConfig = const GateSlotConfig('', '', '');

  /// True when the config ASKS for gating (`gateTable` authored), regardless of
  /// whether the rest of the gate config resolved. Drives fail-closed: a screen
  /// that requested gating must never fall back to showing every row.
  bool _gateIntended = false;

  // Parsed config (set once in initState)
  List<String> _textSegments = [];
  List<BadgeEntry> _badgeEntries = [];
  List<GroupLabelEntry> _groupLabels = [];
  List<StatsDef> _statsDefs = [];
  List<String> _searchFieldCodes = [];
  String _rawSearch = '';
  String _rawConditions = '';
  String _sortField = '';
  bool _sortDesc = false;
  String _groupByField = '';
  String _leadMode = '';
  String _titleTpl = '';
  String _subtitleTpl = '';
  String _metaTpl = '';
  String _noteTpl = '';
  String _badgeField = '';
  String _trailingTpl = '';
  String _trailingLabelTpl = '';
  String _routeStr = '';
  Map<String, String> _groupRoutes = const {};

  // Local UI state
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, bool> _expanded = {};

  /// Length-guarded text segment accessor. Missing segment -> [def].
  String _txt(int i, [String def = '']) =>
      _textSegments.length > i ? _textSegments[i] : def;

  /// Decode a component config field via autheniumDecode (server may encode
  /// special chars as _u25FC_/_u2B58_/etc).
  String _cfg(String key) {
    final String raw = (widget.component[key] ?? '').toString();
    return autheniumDecode(raw) ?? raw;
  }

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initConfig() {
    // text: decode then split (diamondTextToList returns [''] for '', not [])
    try {
      _textSegments = diamondTextToList(_cfg('text'));
    } catch (_) {
      _textSegments = [];
    }

    _badgeEntries = parseBadgeMap(_cfg('badgeMap'));

    _groupLabels = parseGroupLabels(_cfg('groupLabels'));
    for (final g in _groupLabels) {
      _expanded[g.value] = true;
    }

    _statsDefs = parseStatsDefs(_cfg('stats'));

    // searchFields: decode then diamondTextToList, drop blanks
    try {
      _searchFieldCodes = diamondTextToList(
        _cfg('searchFields'),
      ).where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      _searchFieldCodes = [];
    }

    // search/conditions: stored raw — filterDriverHomeDocs decodes internally
    _rawSearch = (widget.component['search'] ?? '').toString().trim();
    _rawConditions = (widget.component['conditions'] ?? '').toString().trim();

    _sortField = _cfg('sortField').trim();
    _sortDesc = _cfg('sortDir').trim().toLowerCase() == 'desc';
    _groupByField = _cfg('groupBy').trim();
    _leadMode = _cfg('lead').trim().toLowerCase();
    _titleTpl = _cfg('title');
    _subtitleTpl = _cfg('subtitle');
    _metaTpl = _cfg('meta');
    _noteTpl = _cfg('note');
    _badgeField = _cfg('badgeField').trim();
    _trailingTpl = _cfg('trailing');
    _trailingLabelTpl = _cfg('trailingLabel');
    _routeStr = stripRouteWrapper(_cfg('route').trim());
    _groupRoutes = parseGroupRoutes(
      _cfg('groupRoutes'),
    ).map((k, v) => MapEntry(k, stripRouteWrapper(v)));

    // gateSearch: stored raw — filterDriverHomeDocs decodes internally
    _rawGateSearch = (widget.component['gateSearch'] ?? '').toString().trim();

    // gateSlot: autheniumDecode (via _cfg) then parse
    _gateSlotConfig = parseGateSlot(_cfg('gateSlot'));

    // Intent flag: `gateTable` authored = this screen WANTS gating. Parsed here
    // (not in _subscribe) so it is set even when the subscription bails.
    _gateIntended = (widget.component['gateTable'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    // vid-scoped key (prevents cross-tenant subscription collision)
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);

    // Gate table subscription (slot-based approval queue gating).
    // Sits after _subscribe()'s early returns (lines 138,140), so a malformed
    // primary `table` also disables gating — benign, no _code means no primary
    // data to filter.
    // Skip subscription when gateSlot config is incomplete (I3: avoids a live
    // Firestore listener whose docs are never read).
    if (!_gateSlotConfig.isEmpty) {
      final String rawGateTable = (widget.component['gateTable'] ?? '')
          .toString()
          .trim();
      if (rawGateTable.isNotEmpty) {
        if (!rawGateTable.contains('//')) {
          // Bare name: subcollection under the main table's docId
          if (tp.tableDocId.isNotEmpty) {
            _gateCode = '$appVid/${tp.tableDocId}/$rawGateTable';
            subscribeToMapCollection(
              appVid,
              tp.tableDocId,
              rawGateTable,
              _gateCode,
            );
          }
        } else {
          final TablePath gtp = parseTablePath(rawGateTable);
          if (gtp.tableDocId.isNotEmpty) {
            _gateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
            subscribeToMapCollection(
              appVid,
              gtp.tableDocId,
              gtp.subColl,
              _gateCode,
            );
          }
        }
      }
    }
  }

  /// Server-side filters + slot gate + sort. Returns the filtered-and-sorted list.
  List<Map<String, dynamic>> _getServerFiltered() {
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );

    // Gate table observable read — unconditional to prevent Obx zero-obs crash.
    // When _gateCode is '', reads mapTableContent[''] which is null → const [];
    // harmless no-op that still registers the Obx dependency.
    final List<Map<String, dynamic>> rawGateDocs =
        List<Map<String, dynamic>>.from(mapTableContent[_gateCode] ?? const []);

    // 1. search filter (autheniumDecode + token resolve + filterByMultiClause)
    final List<Map<String, dynamic>> searched = _rawSearch.isEmpty
        ? all
        : filterDriverHomeDocs(all, _rawSearch, widget.scrName);

    // 2. conditions filter (same pipeline, separate config field)
    final List<Map<String, dynamic>> conditioned = _rawConditions.isEmpty
        ? searched
        : filterDriverHomeDocs(searched, _rawConditions, widget.scrName);

    // 3. slot gate filter (D9: before stats/grouping/sorting)
    final List<Map<String, dynamic>> gated = _applySlotGate(
      conditioned,
      rawGateDocs,
    );

    // 4. sort by sortField (numeric coerce, asc/desc)
    if (_sortField.isNotEmpty) {
      gated.sort((a, b) {
        final num va = coerceNum(a[_sortField]);
        final num vb = coerceNum(b[_sortField]);
        return _sortDesc ? vb.compareTo(va) : va.compareTo(vb);
      });
    }

    return gated;
  }

  /// Apply slot gate filter.
  ///
  /// Two distinct states, deliberately NOT the same:
  ///   * `gateTable` absent  → gating was never requested → docs pass through
  ///     untouched (back-compat for every screen that predates gating).
  ///   * `gateTable` present → gating WAS requested → any failure from here on
  ///     (unresolved config, dead subscription, no matching grant, unreadable
  ///     slot field, thrown exception) yields an EMPTY list, never the full
  ///     unfiltered set.
  ///
  /// The second rule is the whole point: an approval queue that cannot prove
  /// which slots the viewer holds must show nothing, not everything. Failing
  /// open here leaks every pending request to every approver while still
  /// looking gated.
  List<Map<String, dynamic>> _applySlotGate(
    List<Map<String, dynamic>> docs,
    List<Map<String, dynamic>> rawGateDocs,
  ) {
    // SS7.4: session identity for gate instrumentation. Uses the SAME
    // screenTx['#VID'] that filterDriverHomeDocs resolves {userVid} from
    // (driver_home_support.dart:303-306). Logging only, not a permission input.
    final String vid = sessionVidForLog();

    // Gating never requested → untouched. Log the raw gateTable value so
    // a device log can distinguish "gate never requested" from "gateTable
    // misspelled" from "gateTable present but _gateIntended somehow false."
    // Frequency: fires per Obx rebuild of _getServerFiltered, which re-runs
    // on ANY rebuild of the Obx subtree — including per-keystroke search
    // (the search field's onChanged setState). On non-gated screens: harmless
    // (pass-through is
    // the only branch that fires). On gated screens with a search bar:
    // one log line per keystroke. Accepted for now.
    // ponytail: if log noise bothers QA, suppress when outcome == previous call.
    if (!_gateIntended) {
      devPrint(
        'ListCard slot gate: _gateIntended=false '
        '(gateTable=${widget.component['gateTable']}) — pass-through',
      );
      return docs;
    }

    // Gating requested but the config did not fully resolve → FAIL CLOSED.
    if (_gateSlotConfig.isEmpty ||
        _gateCode.isEmpty ||
        _rawGateSearch.isEmpty) {
      devPrint(
        'ListCard slot gate: gateTable authored but gate incomplete '
        '(gateSlotEmpty=${_gateSlotConfig.isEmpty} '
        'gateCodeEmpty=${_gateCode.isEmpty} '
        'gateSearchEmpty=${_rawGateSearch.isEmpty}) '
        'vid=$vid visibleCount=0 — returning empty (fail-closed)',
      );
      // ponytail: growable (NOT const []) — callers .sort() this result
      return <Map<String, dynamic>>[];
    }

    try {
      // Filter gate docs by gateSearch (finds current user's grant docs)
      final List<Map<String, dynamic>> matchedGrants = filterDriverHomeDocs(
        rawGateDocs,
        _rawGateSearch,
        widget.scrName,
      );

      // Zero matching grants → empty list (fail-closed)
      if (matchedGrants.isEmpty) {
        devPrint(
          'ListCard slot gate: no grant docs match gateSearch '
          '"$_rawGateSearch" over ${rawGateDocs.length} gate docs '
          '(gateCode=$_gateCode) vid=$vid grantFound=false '
          'visibleCount=0 — returning empty (fail-closed)',
        );
        return <Map<String, dynamic>>[];
      }

      // Union slot terms across all matched grant docs
      final Set<String> allConcrete = {};
      final Set<String> allWildcardLevels = {};
      final List<String> rawSlotValues = []; // I1: actual per-grant raw values
      for (final grantDoc in matchedGrants) {
        final String rawSlot = (grantDoc[_gateSlotConfig.slotField] ?? '')
            .toString()
            .trim();
        rawSlotValues.add(rawSlot);
        final SlotTerms terms = parseSlotTerms(rawSlot);
        allConcrete.addAll(terms.concrete);
        allWildcardLevels.addAll(terms.wildcardLevels);
      }

      if (allConcrete.isEmpty && allWildcardLevels.isEmpty) {
        devPrint(
          'ListCard slot gate: ${matchedGrants.length} grant doc(s) '
          'matched but slot field "${_gateSlotConfig.slotField}" yielded no '
          'terms (raw sc=$rawSlotValues) '
          'vid=$vid grantFound=true '
          'visibleCount=0 — returning empty (fail-closed)',
        );
        return <Map<String, dynamic>>[];
      }

      // Filter request docs by slot terms (type-tolerant compare)
      final List<Map<String, dynamic>> kept = filterBySlotGate(
        docs,
        allConcrete,
        allWildcardLevels,
        _gateSlotConfig.pointerField,
        _gateSlotConfig.levelField,
      );
      devPrint(
        'ListCard slot gate: grants=${matchedGrants.length} '
        'concrete=$allConcrete wildcardLevels=$allWildcardLevels '
        'ptr="${_gateSlotConfig.pointerField}" '
        'lvl="${_gateSlotConfig.levelField}" '
        'vid=$vid grantFound=true visibleCount=${kept.length}',
      );
      return kept;
    } catch (e) {
      // Any gate failure is a visibility failure → show nothing, never throw.
      devPrint(
        'ListCard slot gate: ERROR vid=$vid '
        'visibleCount=0 — returning empty (fail-closed): $e',
      );
      return <Map<String, dynamic>>[];
    }
  }

  /// Client-side search bar filter on configured searchFields.
  List<Map<String, dynamic>> _applySearchBar(List<Map<String, dynamic>> docs) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty || _searchFieldCodes.isEmpty) return docs;
    return docs.where((d) {
      for (final field in _searchFieldCodes) {
        final String val = (d[field] ?? '').toString().toLowerCase();
        if (val.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  void _onCardTap(Map<String, dynamic> doc, [String? routeOverride]) {
    final String route = routeOverride ?? _routeStr;
    if (route.isEmpty) return;
    // Dispatch routeParams: row-first resolution, session fallback.
    // writeRouteParamsFromRow handles autheniumDecode + parse + resolve + dispatch.
    writeRouteParamsFromRow(
      widget.component['routeParams']?.toString(),
      doc,
      widget.scrName,
    );
    // routeStack.push BEFORE gotoRoute (back-nav uses routeStack)
    if (routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }

  /// Resolve `<field>` template tokens from a doc. No computed values in v1.
  String _resolve(String template, Map<String, dynamic> doc) =>
      resolveMapTokens(template, doc, const <String, String>{});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> serverFiltered = _getServerFiltered();

      // Stats: count from server-filtered set (before search bar filter)
      final List<int> statsCounts = _statsDefs.isNotEmpty
          ? computeStatsCounts(_statsDefs, serverFiltered)
          : const [];

      // Search bar filter for display
      final List<Map<String, dynamic>> displayed = _applySearchBar(
        serverFiltered,
      );

      final double availableH = MediaQuery.of(context).size.height * 0.79;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (title + subtitle + count) ──
              if (_txt(0).isNotEmpty) ...[
                _buildHeader(serverFiltered.length),
                const SizedBox(height: 10),
              ],
              // ── Stats strip ──
              if (_statsDefs.isNotEmpty && statsCounts.isNotEmpty) ...[
                _buildStatsStrip(statsCounts),
                const SizedBox(height: 10),
              ],
              // ── Search bar (hidden when searchFields empty) ──
              if (_searchFieldCodes.isNotEmpty) ...[
                _buildSearchBar(),
                const SizedBox(height: 14),
              ],
              // ── Card list (flat or grouped) ──
              Expanded(
                child: displayed.isEmpty
                    ? _buildEmpty()
                    : _groupByField.isNotEmpty
                    ? _buildGrouped(displayed)
                    : _buildFlat(displayed),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ── Subwidgets ─────────────────────────────────────────────────────────

  Widget _buildHeader(int totalCount) {
    final String title = _txt(0);
    final String subtitle = _txt(1);
    final String countLabel = _txt(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (countLabel.isNotEmpty)
              Text(
                '$totalCount $countLabel',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
          ],
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsStrip(List<int> counts) {
    return Row(
      children: [
        for (int i = 0; i < _statsDefs.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${counts.length > i ? counts[i] : 0}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statsDefs[i].label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextFormField(
      controller: _searchCtrl,
      keyboardType: TextInputType.text,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
        hintText: _txt(3, 'Cari'),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        _txt(4, 'Tidak ada data'),
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
    );
  }

  ListView _buildFlat(List<Map<String, dynamic>> docs) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final doc in docs) _buildCard(doc),
        const SizedBox(height: 24),
      ],
    );
  }

  ListView _buildGrouped(List<Map<String, dynamic>> docs) {
    final Map<String, List<Map<String, dynamic>>> grouped = groupByField(
      docs,
      _groupByField,
    );

    // Section order: groupLabels config order first, then unlisted values
    final List<String> orderedKeys = [];
    for (final gl in _groupLabels) {
      orderedKeys.add(gl.value);
    }
    for (final key in grouped.keys) {
      if (!orderedKeys.contains(key)) orderedKeys.add(key);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final key in orderedKeys)
          if ((grouped[key] ?? const []).isNotEmpty) ...[
            _buildGroupHeader(key, grouped[key]!.length),
            if (_expanded[key] ?? true)
              for (final doc in grouped[key]!)
                _buildCard(
                  doc,
                  groupRoute: resolveGroupRoute(_groupRoutes, key),
                ),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildGroupHeader(String groupValue, int count) {
    final bool open = _expanded[groupValue] ?? true;
    // Lookup display label from groupLabels config; raw value if not mapped
    String label = groupValue;
    for (final gl in _groupLabels) {
      if (gl.value == groupValue) {
        label = gl.label;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded[groupValue] = !open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: const Color(0xFF374151),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> doc, {String? groupRoute}) {
    final String title = _resolve(_titleTpl, doc);
    final String subtitle = _resolve(_subtitleTpl, doc);
    final String meta = _resolve(_metaTpl, doc);
    final String trailing = _resolve(_trailingTpl, doc);
    final String trailingLabel = _resolve(_trailingLabelTpl, doc);
    final String note = resolveNoteTemplate(_noteTpl, doc);

    // Badge: look up from badgeField value
    final String badgeValue = _badgeField.isNotEmpty
        ? (doc[_badgeField] ?? '').toString().trim()
        : '';
    final BadgeEntry? badge = badgeValue.isNotEmpty
        ? lookupBadge(_badgeEntries, badgeValue)
        : null;

    // Effective route: groupRoute overrides _routeStr when provided.
    // null = flat mode or grouped without groupRoutes -> use _routeStr.
    // '' = read-only group -> onTap: null (kills ripple).
    // non-empty = per-group route.
    final String effectiveRoute = groupRoute ?? _routeStr;
    final bool tappable = effectiveRoute.isNotEmpty;

    // Lead widget
    Widget? lead;
    if (_leadMode == 'initial' && title.isNotEmpty) {
      lead = CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFE0E7FF),
        child: Text(
          title[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4338CA),
          ),
        ),
      );
    } else if (_leadMode.isNotEmpty) {
      lead = CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFE0E7FF),
        child: Icon(
          panelIcon(_leadMode),
          size: 20,
          color: const Color(0xFF4338CA),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tappable ? () => _onCardTap(doc, groupRoute) : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lead (initial letter or icon)
                if (lead != null) ...[lead, const SizedBox(width: 12)],
                // Card content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + badge row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusBgColor(badge.tier),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor(badge.tier),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Subtitle
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      // Note
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          note,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                      // Meta + trailing row
                      if (meta.trim().isNotEmpty ||
                          trailing.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: meta.trim().isNotEmpty
                                  ? Text(
                                      meta,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            if (trailing.trim().isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    trailing,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (trailingLabel.trim().isNotEmpty)
                                    Text(
                                      trailingLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
