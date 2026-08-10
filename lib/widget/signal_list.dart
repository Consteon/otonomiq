import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // autheniumDecode, diamondTextToList, mapTableContent, routeStack, gotoRoute, routeExist, devPrint
import 'admin_home_support.dart'; // AdminTierColors
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs, coerceNum, writeRouteParamsFromRow, stripRouteWrapper
import 'panel_card_support.dart'; // parseTablePath, resolveMapTokens, groupByField
import 'signal_list_support.dart';

/// SIGNAL_LIST — generic "obligation-at-risk" signal card list.
///
/// Server type `SIGNAL_LIST`; dispatch literal `signal_list` (the chain in
/// build_display_component.dart lowercases `component['type']`).
///
/// One Firestore map-collection in, one card per surviving row out. Every
/// visible string comes from the single `text` config field, ◆-split and read
/// by DEV-SPEC segment number 1..8 via [signalTextSegment] — there is not one
/// hardcoded label in this file.
///
/// ## Doctrine (Reorder_Signal_Doctrine, dev spec §10)
///
///  * **Amber, never red.** tone `danger` is forced to `warn` inside
///    [resolveSignalTone]. This widget must never render a red signal.
///  * **Silence is the success state.** Rows that do not match `search` simply
///    do not appear, and an empty list renders a green REASSURANCE
///    (`text` segment 6), not an error or a grey "no results".
///  * **The card NAVIGATES and nothing else.** No inline write, no bottom
///    sheet, no cadence editor, no chart. Real actions live on the `route`
///    detail screen.
///
/// ## Search state
///
/// The search box is plain local `State` (`_searchQuery` + `_searchCtrl`), NOT
/// a static per-`scrName` store and NOT registered in `clearData`. Navigating
/// away unmounts the page subtree, which disposes this State; the next visit
/// builds a fresh one with an empty query. That is exactly the required
/// reset-on-leave behaviour, for free. Same shape as list_card.dart, which is
/// live and likewise absent from clearData's clear list.
class SignalList extends StatefulWidget {
  const SignalList({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  /// Server JSON. `dynamic` BY DESIGN — do not type it.
  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  @override
  State<SignalList> createState() => _SignalListState();
}

class _SignalListState extends State<SignalList> {
  /// vid-scoped subscription code. This is ALSO the `mapTableContent` read key
  /// — never rebuild it unscoped anywhere else in this file.
  String _code = '';

  // Parsed config, set once in initState.
  List<String> _textSegments = <String>[];
  List<SignalStatusEntry> _statusEntries = const <SignalStatusEntry>[];
  SignalSortSpec _sort = const SignalSortSpec('', false);
  String _rawSearch = '';
  String _groupField = '';
  String _statusField = '';
  String _gapsField = '';
  String _markerField = '';
  String _route = '';

  // ── Aging config (REV2) ─────────────────────────────────────────────────
  // Empty _agingTimeField = display-only mode (v1 backward compat, no change).
  String _agingTimeField = '';
  String _cadenceField = '';
  String _cadenceUnit = 'hari';
  double _attentionFraction = 0.8;
  double _dormantMultiplier = 3.0;

  // Local UI state — see the class doc "Search state".
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

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

  // ── Config ──────────────────────────────────────────────────────────────

  /// Read + `autheniumDecode` a config field. The server encodes `◼` as
  /// `_25FC_` and `⭘` as `_2B58_`, so anything we split on those must be
  /// decoded first.
  String _cfg(String key) {
    final String raw = (widget.component[key] ?? '').toString();
    return autheniumDecode(raw) ?? raw;
  }

  /// `text` segment by DEV-SPEC number 1..8 (see [signalTextSegment]).
  String _txt(int specSegment) => signalTextSegment(_textSegments, specSegment);

  /// Regex matching curly `{word}` tokens in text segments.
  static final RegExp _curlyToken = RegExp(r'\{(\w+)\}');

  /// Strip curly braces from config keys that may reference computed fields.
  /// `{ds}` becomes `ds`, `{st}` becomes `st`, bare `fieldName` unchanged.
  static String _stripBraces(String s) =>
      s.replaceAll('{', '').replaceAll('}', '');

  void _initConfig() {
    try {
      _textSegments = diamondTextToList(_cfg('text'));
    } catch (_) {
      _textSegments = <String>[];
    }
    _statusEntries = parseSignalStatusMap(_cfg('statusMap'));
    _sort = parseSignalSort(_stripBraces(_cfg('sort')));
    // `search` is stored RAW: filterDriverHomeDocs autheniumDecodes and
    // resolves {token}s internally. Pre-decoding here would double-decode.
    _rawSearch = (widget.component['search'] ?? '').toString().trim();
    _groupField = _stripBraces(_cfg('groupField').trim());
    _statusField = _stripBraces(_cfg('statusField').trim());
    _gapsField = _cfg('gapsField').trim();
    _markerField = _cfg('markerField').trim();
    _route = stripRouteWrapper(_cfg('route').trim());

    // ── Aging config (REV2) ──────────────────────────────────────────────
    // ORDER CONSTRAINT: aging fields must be parsed before statusField
    // defaulting (which depends on _agingTimeField) and before text
    // normalisation (which depends on _agingTimeField and _textSegments).
    _agingTimeField = _cfg('agingTimeField').trim();
    _cadenceField = _cfg('cadenceField').trim();
    final String rawUnit = _cfg('cadenceUnit').trim();
    // ponytail: 'hari'/'bulan' are cadenceUnit enum keywords, not rendered
    // strings — they never reach a Text widget.
    _cadenceUnit = rawUnit.isEmpty ? 'hari' : rawUnit;
    _attentionFraction =
        double.tryParse(_cfg('attentionFraction').trim()) ?? 0.8;
    _dormantMultiplier =
        double.tryParse(_cfg('dormantMultiplier').trim()) ?? 3.0;

    // W3: config-time guard — aging ON but cadenceField empty is almost
    // certainly a config error; emit one devPrint naming the missing key
    // before any row is processed (the per-row loop silently skips).
    if (_agingTimeField.isNotEmpty && _cadenceField.isEmpty) {
      devPrint(
        '[signalList] AGING MODE with an EMPTY cadenceField — every '
        'card will be skipped because cadence cannot be computed. '
        'Set cadenceField to the doc field holding the cadence value '
        '(e.g. "cad").',
      );
    }

    // REV2: when aging mode is ON and statusField is empty (after
    // brace-stripping in 5b), default to 'st' (the computed tier).
    // Spec section 4 examples omit statusField; statusMap keys off the
    // computed {st} value.
    if (_agingTimeField.isNotEmpty && _statusField.isEmpty) {
      _statusField = 'st';
    }

    // REV2: normalise {word} -> <word> in text segments 1-5 ONLY (indices
    // 0-4) when aging mode is ON, so resolveMapTokens handles computed
    // values (ds, st) through the augmented doc map, exactly like real doc
    // fields. Segments 6-8 are list-level literals that never pass through
    // _resolve; a literal {X} there would be rewritten into a visible <X>.
    // When aging is OFF, curly tokens stay literal (v1 backward compat).
    // routeParams reads from component['routeParams'] directly, not
    // _textSegments — safe.
    if (_agingTimeField.isNotEmpty) {
      for (int i = 0; i < _textSegments.length && i < 5; i++) {
        _textSegments[i] = _textSegments[i].replaceAllMapped(
          _curlyToken,
          (Match m) => '<${m.group(1)}>',
        );
      }
    }

    // W2: aging-aware devPrint. In display-only mode, empty statusMap means
    // every card renders pill-less and neutral (harmless). In aging mode,
    // statusMap is the VISIBILITY FILTER — empty statusMap hides EVERY card
    // and the list renders the green reassurance, which is the worst failure
    // mode for a risk-surfacing widget (a misconfiguration looks like
    // "everything is fine").
    if (_statusEntries.isEmpty && _statusField.isNotEmpty) {
      devPrint(
        _agingTimeField.isEmpty
            ? '[signalList] statusField "$_statusField" set but statusMap is '
                  'empty — every card will render pill-less and neutral'
            : '[signalList] AGING MODE with an EMPTY statusMap — statusMap is '
                  'the visibility filter, so EVERY card will be hidden and the '
                  'list will render the empty-state reassurance. Map at least '
                  'one tier.',
      );
    }
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    // ★ vid-scoped code. subscribeToMapCollection's dedup set and
    // mapTableContent's storage key both omit vid by default, so two tenants
    // sharing a tableDocId/subColl would collide and the first subscriber
    // would silently win. This exact string is the read key too.
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  // ── Data pipeline ───────────────────────────────────────────────────────

  /// Server filter + sort. Returns a fresh growable list (safe to `.sort()`;
  /// never mutates the Rx-stored list).
  List<Map<String, dynamic>> _serverFiltered() {
    // ★ FIRST unconditional observable read. An Obx closure that returns
    // without touching an observable throws ("zero observable" fatal), so
    // never hoist a guard clause above this line.
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const <Map<String, dynamic>>[],
    );

    // filterDriverHomeDocs = autheniumDecode + driver-token + screenTx-token +
    // filterByMultiClause, in that order. Pass the RAW config string.
    //
    // FAIL-CLOSED BY DESIGN: an unresolved {token} or a literal-empty clause
    // yields [] , NOT "show all". That is scope-leak defence — do not "fix"
    // it. Consequence for the config author: a screen whose `search` uses a
    // {token} must have that token populated in screenTx before this widget
    // renders, or the list is empty.
    final List<Map<String, dynamic>> filtered = _rawSearch.isEmpty
        ? all
        : filterDriverHomeDocs(all, _rawSearch, widget.scrName);

    // ★ Aging: augment each doc with computed ds/st, skip empty-lo /
    // broken-cad / unmapped-tier. No-op when aging mode is OFF.
    final List<Map<String, dynamic>> augmented = _augmentAndFilter(filtered);

    if (_sort.isEmpty) return augmented;
    final List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(
      augmented,
    );
    sorted.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final num va = coerceNum(a[_sort.field]);
      final num vb = coerceNum(b[_sort.field]);
      return _sort.desc ? vb.compareTo(va) : va.compareTo(vb);
    });
    return sorted;
  }

  /// Search-bar filter over the RESOLVED title + subtitle (design spec §4.3):
  /// an operator searching "Bu Sari" is searching what they can SEE, not the
  /// raw doc keys.
  ///
  /// No debounce: this is a synchronous scan over an already-in-memory list.
  /// Aging mode: augment each doc with computed `ds`/`st`, skip empty-`lo` /
  /// broken-cadence / unmapped-tier docs. Returns docs unchanged when aging
  /// mode is OFF (`_agingTimeField` empty) -- zero v1 behavioral change.
  ///
  /// No per-row devPrint for broken cadence (W3 policy): the config-time
  /// guard in `_initConfig` already logged the likely cause. A CF-wide
  /// cadence bug would emit N identical lines here with no doc id, which
  /// adds noise without information.
  List<Map<String, dynamic>> _augmentAndFilter(
    List<Map<String, dynamic>> docs,
  ) {
    if (_agingTimeField.isEmpty) return docs;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> doc in docs) {
      final int ds = computeSignalDaysSince(doc[_agingTimeField], nowMs);
      if (ds < 0) continue; // lo empty/non-numeric/future -> skip
      final num cadDays = computeSignalCadenceDays(
        doc[_cadenceField],
        _cadenceUnit,
      );
      if (cadDays < 0) continue; // broken cadence -> skip (config-time log)
      final String st = computeSignalTier(
        ds,
        cadDays,
        _attentionFraction,
        _dormantMultiplier,
      );
      // Interview Q1: unmapped tier -> card HIDDEN (statusMap = visibility
      // filter). Only when aging is ON -- display-only mode returns above.
      if (lookupSignalStatus(_statusEntries, st) == null) continue;
      // Augmented map: computed values shadow any pre-existing ds/st in doc.
      out.add(<String, dynamic>{...doc, 'ds': ds, 'st': st});
    }
    return out;
  }

  List<Map<String, dynamic>> _applySearchBar(List<Map<String, dynamic>> docs) {
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return docs;
    return docs.where((Map<String, dynamic> d) {
      final String hay = '${_resolve(_txt(1), d)} ${_resolve(_txt(2), d)}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Resolve `<field>` angle tokens from the row doc (which, in aging mode,
  /// is the augmented map carrying computed `ds` and `st`).
  ///
  /// **Doc fields** use angle brackets: `<cn>`, `<cad>`. Never `{cn}`.
  /// **Computed values** use curly brackets in the config: `{ds}`, `{st}`.
  /// `_initConfig` normalises `{word}` to `<word>` in text segments 1-5 when
  /// aging mode is ON, so by the time this method runs, both syntaxes have
  /// been unified into angle tokens and `resolveMapTokens` handles them
  /// identically from the augmented doc map. Curly `{field}` in `search` and
  /// `routeParams` is a different mechanism (screenTx / row resolve) and is
  /// NOT normalised.
  ///
  /// ★ DOCUMENTED DEVIATION from dev spec §3.1, which claims an unresolvable
  /// `<field>` is "dibiarkan literal". It is not: `resolveMapTokens` replaces
  /// a missing key with an EMPTY STRING (panel_card_support.dart:341-346,
  /// `val == null ? '' : val.toString()`). We follow the helper, not the spec
  /// sentence — it is the repo-wide contract that every other `<field>`
  /// consumer already uses, and forking it for one widget would be new code
  /// to reinstate a behaviour nothing else in the app has. Consequence for
  /// config authors, also stated in docs/widgets/signal_list.md: a misspelled
  /// or unstamped token renders as nothing, so check the spelling first.
  /// Do not "restore" literal-token behaviour here.
  String _resolve(String template, Map<String, dynamic> doc) =>
      resolveMapTokens(template, doc, const <String, String>{});

  /// Section order: `statusMap` order first (design spec §4.2), then any group
  /// value present in the data but absent from `statusMap`, appended last.
  List<String> _orderedGroupKeys(
    Map<String, List<Map<String, dynamic>>> grouped,
  ) {
    final List<String> keys = <String>[];
    for (final SignalStatusEntry e in _statusEntries) {
      if (grouped.containsKey(e.value) && !keys.contains(e.value)) {
        keys.add(e.value);
      }
    }
    for (final String k in grouped.keys) {
      if (!keys.contains(k)) keys.add(k);
    }
    return keys;
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  void _onCardTap(Map<String, dynamic> doc) {
    if (_route.isEmpty) return;
    // routeParams: row-first {token} resolution then session fallback,
    // dispatched as bare screenTx keys. autheniumDecode happens inside — pass
    // the RAW config value.
    writeRouteParamsFromRow(
      widget.component['routeParams']?.toString(),
      doc,
      widget.scrName,
    );
    // Dead-route silent skip.
    if (!routeExist(_route)) {
      devPrint(
        '[signalList] route "$_route" is not in the page set — '
        'tap ignored',
      );
      return;
    }
    // ★ routeStack.push BEFORE gotoRoute — the AppBar back button pops
    // routeStack, NOT the Flutter Navigator. Reversing these breaks back-nav.
    routeStack.push(_route);
    gotoRoute(_route);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // _serverFiltered()'s first statement is the observable read — keep this
      // call first so the Obx always registers a dependency.
      final List<Map<String, dynamic>> serverFiltered = _serverFiltered();
      final List<Map<String, dynamic>> displayed = _applySearchBar(
        serverFiltered,
      );

      final String listTitle = _txt(8);
      final String searchHint = _txt(7);

      // House convention (same as LIST_CARD): a fixed viewport with the list
      // scrolling internally. This screen is a dedicated list; a shrink-wrapped
      // Column inside the page scroller would double-scroll.
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
            children: <Widget>[
              if (listTitle.isNotEmpty) ...<Widget>[
                Text(
                  listTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminTierColors.titleText,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (searchHint.isNotEmpty) ...<Widget>[
                _buildSearchBar(searchHint),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: displayed.isEmpty
                    ? _buildEmpty()
                    : (_groupField.isEmpty
                          ? _buildFlat(displayed)
                          : _buildGrouped(displayed)),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ── List chrome ─────────────────────────────────────────────────────────

  Widget _buildSearchBar(String hint) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (String v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 13, color: AdminTierColors.titleText),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AdminTierColors.mutedText,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AdminTierColors.mutedText,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTierColors.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AdminTierColors.cardBorder),
          ),
        ),
      ),
    );
  }

  /// Empty state. **Silence is the success state** (doctrine §5, design spec
  /// §4.4): this is a REASSURANCE, not an error — no warning icon, no amber,
  /// no grey "no results found". Also fires when the search box filters
  /// everything out.
  ///
  /// `text` segment 6 empty → render nothing at all. A blank calm screen is
  /// still a correct answer.
  Widget _buildEmpty() {
    final String emptyText = _txt(6);
    if (emptyText.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: AdminTierColors.okBadgeBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: AdminTierColors.okActionGreen,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                emptyText,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AdminTierColors.okActionGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ListView _buildFlat(List<Map<String, dynamic>> docs) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final Map<String, dynamic> doc in docs) _buildCard(doc),
        const SizedBox(height: 24),
      ],
    );
  }

  ListView _buildGrouped(List<Map<String, dynamic>> docs) {
    final Map<String, List<Map<String, dynamic>>> grouped = groupByField(
      docs,
      _groupField,
    );
    final List<String> keys = _orderedGroupKeys(grouped);

    // ★ groupByField SILENTLY DROPS rows whose group value is empty
    // (panel_card_support.dart: `if (k.isEmpty) continue;`). For a signal list
    // a dropped row is a MISSED SIGNAL — exactly the failure this widget
    // exists to prevent — so recover them and render them last, under no
    // section header.
    //
    // The predicate MIRRORS groupByField's exactly (`.toString().isEmpty`,
    // NOT `.trim().isEmpty`): groupByField does not trim, so a whitespace-only
    // value forms its own real group there, and trimming here would render
    // that row a second time.
    final List<Map<String, dynamic>> ungrouped = docs
        .where(
          (Map<String, dynamic> d) => (d[_groupField] ?? '').toString().isEmpty,
        )
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final String key in keys)
          if ((grouped[key] ?? const <Map<String, dynamic>>[])
              .isNotEmpty) ...<Widget>[
            _buildGroupHeader(key),
            for (final Map<String, dynamic> doc in grouped[key]!)
              _buildCard(doc),
          ],
        for (final Map<String, dynamic> doc in ungrouped) _buildCard(doc),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Group section header. Label = the `statusMap` label for that value;
  /// an unmapped value renders raw in `sectionCaps` (design spec §4.2).
  Widget _buildGroupHeader(String groupValue) {
    final SignalStatusEntry? e = lookupSignalStatus(_statusEntries, groupValue);
    final String label = e?.label ?? groupValue;
    final Color color = e == null
        ? AdminTierColors.sectionCaps
        : signalToneColors(e.tone).pillText;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  // ── Card ────────────────────────────────────────────────────────────────

  Widget _buildCard(Map<String, dynamic> doc) {
    final String statusValue = _statusField.isEmpty
        ? ''
        : (doc[_statusField] ?? '').toString().trim();
    final SignalStatusEntry? status = lookupSignalStatus(
      _statusEntries,
      statusValue,
    );
    // Missing or unmapped status → pill hidden entirely AND neutral tone
    // (design spec §3.3).
    final SignalToneColors c = signalToneColors(status?.tone ?? '');

    // text segments 1..5 are per-card and may carry <field> tokens.
    final String title = _resolve(_txt(1), doc);
    final String subtitle = _resolve(_txt(2), doc);
    final String metric = _resolve(_txt(3), doc);
    final String meta = _resolve(_txt(4), doc);
    final String actionLabel = _resolve(_txt(5), doc);

    // Mini-timeline needs BOTH config keys AND both resolved row values.
    final List<num> gaps = _gapsField.isEmpty
        ? const <num>[]
        : parseSignalGaps(doc[_gapsField]);
    final String rawMarker = _markerField.isEmpty
        ? ''
        : (doc[_markerField] ?? '').toString().trim();
    final bool showTimeline = gaps.isNotEmpty && rawMarker.isNotEmpty;

    final bool tappable = _route.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.cardTint,
          borderRadius: BorderRadius.circular(16),
          // ★ UNIFORM border only. A Border with a thicker left side PLUS a
          // borderRadius trips Flutter's assert "A borderRadius can only be
          // given on borders with uniform colors and styles" — a debug crash
          // on every card. That is why the 4px tone accent bar is a Stack
          // child below and NOT Border(left: BorderSide(width: 4)).
          border: Border.all(color: AdminTierColors.cardBorder, width: 1),
        ),
        // No shadow: the accent bar carries the emphasis, and shadows on a
        // scrolling list cost raster time for nothing.
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            // Whole card is tappable → same destination as the button. The
            // button is not a second destination, it is an affordance for the
            // same one, so a stray tap anywhere still works.
            onTap: tappable ? () => _onCardTap(doc) : null,
            child: Stack(
              children: <Widget>[
                Padding(
                  // left 18 = the 4px accent bar + the 14px card padding
                  padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Title + status pill
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              // One line: a name that wraps shifts every card
                              // below it and destroys the scan rhythm.
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AdminTierColors.titleText,
                              ),
                            ),
                          ),
                          if (status != null) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: c.pillBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                status.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: c.pillText,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AdminTierColors.subText,
                          ),
                        ),
                      ],
                      if (showTimeline) ...<Widget>[
                        const SizedBox(height: 10),
                        _buildTimeline(
                          gaps,
                          rawMarker,
                          c,
                          metric.isNotEmpty ? metric : title,
                        ),
                      ],
                      if (metric.isNotEmpty) ...<Widget>[
                        SizedBox(height: showTimeline ? 8 : 10),
                        Text(
                          metric,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            // ★ PILL TEXT, never the accent. The accent
                            // (#F59E0B) is 2.1:1 on white and fails AA; this
                            // is the card's primary read at 16/w800.
                            color: c.pillText,
                          ),
                        ),
                      ],
                      if (meta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AdminTierColors.subText,
                          ),
                        ),
                      ],
                      if (actionLabel.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: AdminTierColors.cardBorder,
                        ),
                        const SizedBox(height: 11),
                        SizedBox(
                          width: double.infinity,
                          // 44 is the touch-target floor, not the target.
                          height: 44,
                          child: ElevatedButton(
                            onPressed: tappable ? () => _onCardTap(doc) : null,
                            style: ElevatedButton.styleFrom(
                              // Blue, not amber: amber marks the PROBLEM,
                              // blue marks the ACTION. One primary CTA.
                              backgroundColor: AdminTierColors.okAction,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 4px tone accent bar, full card height.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: ColoredBox(color: c.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Mini-timeline ───────────────────────────────────────────────────────

  /// `●  7h  ●  6h  ●  8h  ●┈┈┈ 24h ┈┈┈ ○` — the customer's rhythm plus the
  /// current gap (dev spec §3.2, design spec §3.5).
  ///
  /// `Wrap`, not `Row`: a customer with 6+ gaps must fold to a second line,
  /// never overflow or clip. Past 6 gaps only the LAST 6 render, prefixed
  /// with `…`.
  ///
  /// One [Semantics] node with `excludeSemantics: true` for the whole strip —
  /// otherwise a screen reader reads "7h 6h 8h" as meaningless fragments.
  ///
  /// ★ The marker suffix is the language-neutral `h`, NOT " hari". The design
  /// spec's mockup writes `${marker} hari`, but hardcoded Indonesian in lib/
  /// violates the same document's own pre-delivery checklist and would leak
  /// Indonesian into a non-Indonesian tenant. The metric line directly below
  /// spells out the unit in the tenant's own language via `text` segment 3
  /// (`<ds> hari belum order`). If a tenant ever needs a configurable suffix,
  /// the sanctioned extension is `text` segment 9 (dev spec §12: appending by
  /// index is safe) — never a new top-level config field.
  Widget _buildTimeline(
    List<num> gaps,
    String marker,
    SignalToneColors c,
    String semanticsLabel,
  ) {
    final bool folded = gaps.length > 6;
    final List<num> shown = folded ? gaps.sublist(gaps.length - 6) : gaps;
    final num? markerNum = num.tryParse(marker);
    // Non-numeric marker renders verbatim rather than lying with "0h".
    final String markerLabel = markerNum == null
        ? marker
        : '${formatSignalGapValue(markerNum)}h';

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: <Widget>[
          if (folded)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text(
                '…',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AdminTierColors.mutedText,
                ),
              ),
            ),
          for (final num g in shown) ...<Widget>[
            _gapDot(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${formatSignalGapValue(g)}h',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AdminTierColors.mutedText,
                ),
              ),
            ),
          ],
          // Last-event dot: solid "you are here" anchor.
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: AdminTierColors.subText,
              shape: BoxShape.circle,
            ),
          ),
          _dashSegment(c.accent),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              markerLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c.pillText,
              ),
            ),
          ),
          _dashSegment(c.accent),
          // Marker dot: hollow = has not happened yet.
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: c.accent, width: 2),
            ),
          ),
        ],
      ),
    );
  }

  /// 8x8 gap dot: line-coloured fill, 1.5px muted border.
  Widget _gapDot() => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: AdminTierColors.cardBorder,
      shape: BoxShape.circle,
      border: Border.all(color: AdminTierColors.mutedText, width: 1.5),
    ),
  );

  /// Dashed segment. Flutter has no dashed-border primitive; a Row of 3x2
  /// boxes costs one layout pass and zero packages. A CustomPainter would add
  /// a paint callback per card in a scrolling list for ~33px of dashes.
  Widget _dashSegment(Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 6; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 3),
          Container(width: 3, height: 2, color: color),
        ],
      ],
    ),
  );
}
