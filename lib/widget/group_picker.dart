import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // diamondTextToList, mapTableContent, emptyString
import '../global2.dart'; // txfController, txfControllerCheck, getPosition
import '../screen_session.dart';
import 'driver_home_support.dart'; // resolveAppVid
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'picker_list.dart'; // PickerList.filterRows (static reuse, no coupling)
import 'table_picker.dart'; // TablePicker.resolveValueFromDoc, .clientSearch

/// GROUP_PICKER -- multi-group single/multi-select picker with internal toggle.
///
/// Self-contained: user picks a group (level), then picks target(s) within that
/// group. Emits 2-3 form-position values: active group key, selected value(s),
/// optional label(s). Reuses [PickerList.filterRows] for table-src search gate
/// and [TablePicker.resolveValueFromDoc] for doc value extraction.
///
/// Output: pairSep-join for multi (NOT jsonEncode -- dodges quoteCleanUp mangle,
/// see table_picker C1 note). Bare string for single.
///
/// SDUI type: `group_picker`.
class GroupPicker extends StatefulWidget {
  const GroupPicker({
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

  // -- Per-screen state stores ------------------------------------------------
  // ponytail: keyed by scrName+valuePosition so two GroupPickers on one screen
  // don't collide. Nested Map<groupKey, Set<id>> isolates selection per group
  // (R4: the tab you leave is cleared on switch -- only the active tab holds).

  /// Active group index: { scrName -> { valuePosition -> activeIndex } }.
  static final Map<String, Map<int, int>> _activeGroupStore = {};

  /// Selection per group:
  /// { scrName -> { valuePosition -> { groupKey -> `Set<id>` } } }.
  static final Map<String, Map<int, Map<String, Set<String>>>> _selectionStore =
      {};

  /// Labels per group:
  /// { scrName -> { valuePosition -> { groupKey -> { id -> label } } } }.
  static final Map<String, Map<int, Map<String, Map<String, String>>>>
  _labelStore = {};

  /// Repaint signal for [clearState]. The stores above stay PLAIN Maps (mutated
  /// during build via putIfAbsent); only this counter is reactive, so a reset
  /// can never notify mid-build. Mirrors the countStore/editStore shape.
  static final RxInt resetRev = 0.obs;

  /// Clear every picker on a screen.
  ///
  /// Must be called from clearData (the per-NAV reset) as well as
  /// buildPage(clear:true) -- buildPage runs at page CONSTRUCTION/refresh only.
  /// Navigation is gotoRoute -> reloadPage, which returns the CACHED
  /// linkElement[scrName] and never re-runs buildPage, so a buildPage-only
  /// reset leaks the last visit's tab + ticks into the next visit.
  ///
  /// clearData fires POST-frame, after the cached widget already painted once,
  /// and GroupPicker has no GetBuilder subscription -- so clearing the stores
  /// alone would not repaint. Bumping [resetRev] (read by build's Obx) is what
  /// makes the reset visible.
  static void registerScreenSession() {
    ScreenSession.ensure(
      'GroupPicker.stores',
      GroupPicker.clearState,
      nav: NavPolicy.all,
      clearAllFn: GroupPicker.clearAll,
    );
  }

  static void clearState(String scrName) {
    _activeGroupStore.remove(scrName);
    _selectionStore.remove(scrName);
    _labelStore.remove(scrName);
    resetRev.value++;
  }

  /// Wipe EVERY screen's picker state. This is what clearData calls.
  ///
  /// Clearing only the entering screen is correct but VISIBLY GLITCHY: clearData
  /// runs post-frame, so a revisited page paints the previous visit's tab+ticks
  /// for a frame and then snaps to empty. Wiping every screen instead means the
  /// page is cleared on the nav AWAY from it (while it is off-screen and there
  /// is nothing to see), so the next visit is already empty at its FIRST paint.
  /// The entering screen is included so a same-page clearData -- saveSend after
  /// a submit, or a reset button -- still resets the picker you are looking at.
  ///
  /// ponytail: blunt on purpose. Per-visit reset is this widget's semantics
  /// everywhere (R4/R7), no screen wants its picker state preserved while a
  /// different screen is on top, and blunt keeps the "was it cleared yet?"
  /// bookkeeping at zero. Narrow it only if a picker ever has to survive nav.
  static void clearAll() {
    _activeGroupStore.clear();
    _selectionStore.clear();
    _labelStore.clear();
    resetRev.value++;
  }

  // -- Pure static helpers (testable without SDUI globals) --------------------

  /// Length-guarded text segment accessor.
  static String textSegment(List<String> arr, int index, String def) {
    return arr.length > index ? arr[index] : def;
  }

  /// Decode the server escapes for ◆/⭘ that [autheniumDecode] alone misses.
  /// The server ships ◆/⭘ as `_u25C6_`/`_u2B58_` (autheniumDecode handles those)
  /// OR as the bare `_25C6_`/`_2B58_` (global.dart:1153 leaves `_2B58_`
  /// commented out and has no `_25C6_` line at all). Covering both here is what
  /// lets a server-escaped config separator meet a `src:"doc"` field's REAL
  /// ◆/⭘ on the same character. Idempotent on already-real input.
  static String _decodeSep(String s) => (autheniumDecode(s) ?? s)
      .replaceAll('_25C6_', '\u{25C6}')
      .replaceAll('_2B58_', '\u{2B58}');

  /// Parse static options: "Product Group◆83674161979544⭘Kantor Pusat◆32639062303108"
  /// Separators AND the string are normalized ([_decodeSep]) first: the
  /// top-level `pairSep`/`itemSep` config arrives server-escaped, but a
  /// `src:"doc"` field carries REAL ◆/⭘ -- without normalizing, the escaped
  /// separator never matches and the whole field collapses to ONE option
  /// (the reported bug). Empty/blank [options] returns empty list.
  static List<Map<String, String>> parseStaticOptions(
    String options,
    String pairSep,
    String itemSep,
  ) {
    final String pair = _decodeSep(pairSep);
    final String item = _decodeSep(itemSep);
    final String trimmed = _decodeSep(options).trim();
    if (trimmed.isEmpty) return [];
    final List<String> items = trimmed.split(item);
    final List<Map<String, String>> result = [];
    for (final entry in items) {
      final String t = entry.trim();
      if (t.isEmpty) continue;
      final int sepIdx = t.indexOf(pair);
      if (sepIdx < 0) {
        // No separator: use whole string as both name and id
        result.add({'name': t, 'id': t});
      } else {
        final String name = t.substring(0, sepIdx).trim();
        final String id = t.substring(sepIdx + pair.length).trim();
        result.add({
          'name': name.isNotEmpty ? name : id,
          'id': id.isNotEmpty ? id : name,
        });
      }
    }
    return result;
  }

  /// Encode selection for form output.
  /// Single: bare string. Multi: [sep]-join (NOT jsonEncode).
  static String encodeSelection(
    List<String> values,
    String sep, {
    required bool isSingle,
  }) {
    if (isSingle) return values.isNotEmpty ? values.first : '';
    return values.join(sep);
  }

  /// Client-side text search on static options by name.
  static List<Map<String, String>> clientSearchStatic(
    List<Map<String, String>> options,
    String query,
  ) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return options;
    return options
        .where((o) => (o['name'] ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  State<GroupPicker> createState() => _GroupPickerState();
}

// -- Parsed group config (internal) -------------------------------------------

class _GroupConfig {
  final String key;
  final String label;
  final bool isTable;
  // Static source
  final List<Map<String, String>> staticOptions;
  // Table source
  final String subscriptionCode;
  final String labelField;
  final String subField;
  final String valueField;
  final String rawSearch;
  // Doc source: set by `src:"doc"` ONLY. isTable is also true (a doc group owns
  // a subscription), but rows are static-shaped Map<String, String> parsed out
  // of ONE field of the first matching doc.
  final bool isDoc;

  /// Field name read off the matched doc. Empty on a misconfigured `src:"doc"`
  /// group -> [isDoc] still discriminates, so it degrades to an EMPTY list
  /// instead of silently rendering raw grant docs (and leaking `__docId` ids).
  final String docField;

  const _GroupConfig({
    required this.key,
    required this.label,
    required this.isTable,
    this.staticOptions = const [],
    this.subscriptionCode = '',
    this.labelField = 'n',
    this.subField = '',
    this.valueField = '',
    this.rawSearch = '',
    this.isDoc = false,
    this.docField = '',
  });
}

// -- State --------------------------------------------------------------------

class _GroupPickerState extends State<GroupPicker> {
  List<String> _textArray = [];
  final List<_GroupConfig> _groups = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // -- Config accessors -------------------------------------------------------

  bool get _isSingle =>
      (widget.component['mode'] ?? 'single').toString().trim().toLowerCase() ==
      'single';

  /// Opt-in select-all affordance. Multi-only: never active in single mode.
  /// Default OFF (absent/false/any-non-true => disabled).
  bool get _selectAllEnabled =>
      (widget.component['selectAll'] == true) && !_isSingle;

  int get _valuePosition => getPosition(widget.component['valuePosition']);

  int? get _keyPosition {
    final dynamic raw = widget.component['keyPosition'];
    return raw != null ? getPosition(raw) : null;
  }

  int? get _labelPosition {
    final dynamic raw = widget.component['labelPosition'];
    return raw != null ? getPosition(raw) : null;
  }

  String get _pairSep => (widget.component['pairSep'] ?? '\u{25C6}').toString();

  /// Output-only multi-join separator. Falls back to [_pairSep] when absent/empty
  /// so pickers without `joinSep` are byte-identical (backward-compat). Lets JSON
  /// pick a `stringCleanUp`-surviving char (e.g. `,`/`|`/`;`) for the emitted `bcc`
  /// join while `pairSep` stays `◆` for parsing the static `options`.
  String get _joinSep {
    final dynamic raw = widget.component['joinSep'];
    return (raw != null && raw.toString().isNotEmpty)
        ? raw.toString()
        : _pairSep;
  }

  String get _itemSep => (widget.component['itemSep'] ?? '\u{2B58}').toString();

  String get _title => (widget.component['title'] ?? '').toString().trim();

  String get _hint => (widget.component['hint'] ?? '').toString().trim();

  bool get _showSelector {
    final String raw = (widget.component['selector'] ?? 'segmented')
        .toString()
        .trim()
        .toLowerCase();
    // none -> hide toggle; dropdown -> degrade to segmented (deferred)
    if (raw == 'none') return false;
    return _groups.length > 1;
  }

  String _t(int i, String def) => GroupPicker.textSegment(_textArray, i, def);

  // -- Lifecycle --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    GroupPicker.registerScreenSession();
    _parseText();
    _parseGroups();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Decode server escapes + resolve session/screenTx `{token}`s before the
  /// gate DSL sees the search string. PickerList.filterRows re-decodes
  /// (idempotent) but never resolves tokens; this helper closes that gap for
  /// both src:table and src:doc branches.
  String _resolveSearch(String raw) =>
      resolveDriverCurlyTokens(autheniumDecode(raw) ?? raw, widget.scrName);

  /// Build the vid-scoped subscription code for [g] and subscribe to it.
  /// Returns '' when the group has no usable `table` (nothing subscribed).
  /// ONE derivation shared by src:table and src:doc -- a divergent second copy
  /// is how the vid-scope collision bug spread before.
  String _subscribeForGroup(Map<dynamic, dynamic> g) {
    final String rawTable = (g['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return '';
    final String appVid = resolveAppVid(g);
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return '';
    final String code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, code);
    return code;
  }

  void _parseGroups() {
    final dynamic rawGroups = widget.component['groups'];
    if (rawGroups is! List || rawGroups.isEmpty) return;

    final String pairSep = _pairSep;
    final String itemSep = _itemSep;

    for (final dynamic g in rawGroups) {
      if (g is! Map) continue;
      final String key = (g['key'] ?? '').toString().trim();
      final String label = (g['label'] ?? '').toString().trim();
      final String src = (g['src'] ?? 'static').toString().trim().toLowerCase();

      if (src == 'table') {
        _groups.add(
          _GroupConfig(
            key: key,
            label: label,
            isTable: true,
            subscriptionCode: _subscribeForGroup(g),
            labelField: (g['labelField'] ?? 'n').toString().trim(),
            subField: (g['subField'] ?? '').toString().trim(),
            valueField: (g['valueField'] ?? '').toString().trim(),
            rawSearch: (g['search'] ?? '').toString().trim(),
          ),
        );
      } else if (src == 'doc') {
        // src:doc -- subscribe like table (same engine), but at read time take
        // the FIRST matching doc, read one string field, and split like static.
        _groups.add(
          _GroupConfig(
            key: key,
            label: label,
            isTable: true,
            isDoc: true,
            subscriptionCode: _subscribeForGroup(g),
            docField: (g['field'] ?? '').toString().trim(),
            rawSearch: (g['search'] ?? '').toString().trim(),
          ),
        );
      } else {
        _groups.add(
          _GroupConfig(
            key: key,
            label: label,
            isTable: false,
            staticOptions: GroupPicker.parseStaticOptions(
              (g['options'] ?? '').toString(),
              pairSep,
              itemSep,
            ),
          ),
        );
      }
    }
  }

  // -- Active group -----------------------------------------------------------

  int get _activeIndex {
    return GroupPicker._activeGroupStore[widget.scrName]?[_valuePosition] ?? 0;
  }

  void _setActiveIndex(int idx) {
    // R4 (reset-on-tab-switch): leaving a tab RESETS it. Capture the group being
    // LEFT and clear its selection + labels BEFORE switching, so only the active
    // tab ever holds a selection (output is active-group-only, so non-active tab
    // state is dead/confusing -- see docs). REVERSES the prior per-group keep.
    final int oldIdx = _activeIndex.clamp(0, _groups.length - 1);
    if (oldIdx != idx && oldIdx >= 0 && oldIdx < _groups.length) {
      final String oldKey = _groups[oldIdx].key;
      GroupPicker._selectionStore[widget.scrName]?[_valuePosition]?[oldKey]
          ?.clear();
      GroupPicker._labelStore[widget.scrName]?[_valuePosition]?[oldKey]
          ?.clear();
    }
    GroupPicker._activeGroupStore.putIfAbsent(
      widget.scrName,
      () => {},
    )[_valuePosition] = idx;
    _searchCtrl.clear();
    _query = '';
    _writeToController();
  }

  _GroupConfig get _activeGroup =>
      _groups[_activeIndex.clamp(0, _groups.length - 1)];

  // -- Selection accessors ----------------------------------------------------

  Set<String> _selectedIds(String groupKey) {
    return GroupPicker._selectionStore[widget
            .scrName]?[_valuePosition]?[groupKey] ??
        {};
  }

  Map<String, String> _selectedLabels(String groupKey) {
    return GroupPicker._labelStore[widget
            .scrName]?[_valuePosition]?[groupKey] ??
        {};
  }

  void _toggleItem(String id, String label, String groupKey) {
    final String scrName = widget.scrName;
    final int pos = _valuePosition;

    GroupPicker._selectionStore
        .putIfAbsent(scrName, () => {})
        .putIfAbsent(pos, () => {})
        .putIfAbsent(groupKey, () => {});
    GroupPicker._labelStore
        .putIfAbsent(scrName, () => {})
        .putIfAbsent(pos, () => {})
        .putIfAbsent(groupKey, () => {});

    final Set<String> ids =
        GroupPicker._selectionStore[scrName]![pos]![groupKey]!;
    final Map<String, String> labels =
        GroupPicker._labelStore[scrName]![pos]![groupKey]!;

    setState(() {
      if (_isSingle) {
        ids.clear();
        labels.clear();
        ids.add(id);
        labels[id] = label;
      } else {
        if (ids.contains(id)) {
          ids.remove(id);
          labels.remove(id);
        } else {
          ids.add(id);
          labels[id] = label;
        }
      }
    });

    _writeToController();
  }

  /// Select-all-VISIBLE for the ACTIVE group (multi mode only). [rows] is the
  /// already-filtered `_activeRows()` list from build (respects search + gate).
  /// If every visible row id is already selected -> deselect them all; else ->
  /// add every visible row's id+label. Acts on [group] (the active group) only
  /// (other tabs are reset on switch, R4). Same write path as [_toggleItem].
  void _toggleSelectAll(List<dynamic> rows, _GroupConfig group) {
    final String scrName = widget.scrName;
    final int pos = _valuePosition;
    final String groupKey = group.key;

    GroupPicker._selectionStore
        .putIfAbsent(scrName, () => {})
        .putIfAbsent(pos, () => {})
        .putIfAbsent(groupKey, () => {});
    GroupPicker._labelStore
        .putIfAbsent(scrName, () => {})
        .putIfAbsent(pos, () => {})
        .putIfAbsent(groupKey, () => {});

    final Set<String> ids =
        GroupPicker._selectionStore[scrName]![pos]![groupKey]!;
    final Map<String, String> labels =
        GroupPicker._labelStore[scrName]![pos]![groupKey]!;

    final List<String> visibleIds = rows
        .map((r) => _rowId(r, group))
        .where((id) => id.isNotEmpty)
        .toList();

    setState(() {
      if (visibleIds.isNotEmpty && visibleIds.every((id) => ids.contains(id))) {
        // Deselect-all-visible.
        for (final String id in visibleIds) {
          ids.remove(id);
          labels.remove(id);
        }
      } else {
        // Select-all-visible.
        for (final dynamic row in rows) {
          final String id = _rowId(row, group);
          if (id.isEmpty) continue;
          ids.add(id);
          labels[id] = _rowLabel(row, group);
        }
      }
    });

    _writeToController();
  }

  // -- Write to txfController -------------------------------------------------

  void _writeToController() {
    final String scrName = widget.scrName;
    final int vPos = _valuePosition;
    final _GroupConfig group = _activeGroup;
    final String groupKey = group.key;
    final Set<String> ids = _selectedIds(groupKey);
    final Map<String, String> labels = _selectedLabels(groupKey);
    // R3: OUTPUT join uses _joinSep (defaults to _pairSep); pairSep still parses
    // static options, joinSep lets the multi bcc use a stringCleanUp-surviving char.
    final String joinSep = _joinSep;

    // Value
    txfControllerCheck(scrName, vPos);
    final List<String> idList = ids.toList();
    txfController[scrName]![vPos]!.finalData = GroupPicker.encodeSelection(
      idList,
      joinSep,
      isSingle: _isSingle,
    );

    // Key (optional)
    final int? kPos = _keyPosition;
    if (kPos != null) {
      txfControllerCheck(scrName, kPos);
      txfController[scrName]![kPos]!.finalData = groupKey;
    }

    // Label (optional)
    final int? lPos = _labelPosition;
    if (lPos != null) {
      txfControllerCheck(scrName, lPos);
      final List<String> labelList = idList
          .map((v) => labels[v] ?? '')
          .toList();
      txfController[scrName]![lPos]!.finalData = GroupPicker.encodeSelection(
        labelList,
        joinSep,
        isSingle: _isSingle,
      );
    }
  }

  // -- Data rows for active group ---------------------------------------------

  /// Returns a heterogeneous list: `List<Map<String,String>>` for static and
  /// doc groups, `List<Map<String,dynamic>>` for table groups. Row accessors
  /// below handle both.
  List<dynamic> _activeRows() {
    final _GroupConfig group = _activeGroup;
    if (group.isDoc) {
      // Misconfigured src:doc (no `field`) -> EMPTY, never fall through to the
      // table rendering (which would emit raw doc ids into the broadcast).
      if (group.docField.isEmpty) return [];
      // src:doc -- query subscription (like table), first match, read field,
      // split (like static). Rows are static-shaped Map<String, String>.
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[group.subscriptionCode] ?? const [],
      );
      final String resolvedSearch = _resolveSearch(group.rawSearch);
      final List<Map<String, dynamic>> filtered = PickerList.filterRows(
        docs,
        resolvedSearch,
      );
      if (filtered.isEmpty) return [];
      // Contract: ONE grant doc per user (gk = "broadcast_{userVid}"). If the
      // search matches several, "first" is Firestore snapshot order.
      final Map<String, dynamic> doc = filtered.first;
      final String fieldValue = (doc[group.docField] ?? '').toString();
      final List<Map<String, String>> options = GroupPicker.parseStaticOptions(
        fieldValue,
        _pairSep,
        _itemSep,
      );
      if (_query.isNotEmpty) {
        return GroupPicker.clientSearchStatic(options, _query);
      }
      return options;
    } else if (group.isTable) {
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[group.subscriptionCode] ?? const [],
      );
      final String resolvedSearch = _resolveSearch(group.rawSearch);
      final List<Map<String, dynamic>> filtered = PickerList.filterRows(
        docs,
        resolvedSearch,
      );
      if (_query.isNotEmpty) {
        return TablePicker.clientSearch(
          filtered,
          _query,
          group.labelField,
          group.subField,
        );
      }
      return filtered;
    } else {
      if (_query.isNotEmpty) {
        return GroupPicker.clientSearchStatic(group.staticOptions, _query);
      }
      return group.staticOptions;
    }
  }

  String _rowId(dynamic row, _GroupConfig group) {
    if (group.isTable && !group.isDoc) {
      return TablePicker.resolveValueFromDoc(
        row as Map<String, dynamic>,
        group.valueField,
      );
    }
    // Static and doc rows are both Map<String, String> from parseStaticOptions.
    return ((row as Map<String, String>)['id'] ?? '').trim();
  }

  String _rowLabel(dynamic row, _GroupConfig group) {
    if (group.isTable && !group.isDoc) {
      return ((row as Map<String, dynamic>)[group.labelField] ?? '')
          .toString()
          .trim();
    }
    // Static and doc rows are both Map<String, String> from parseStaticOptions.
    return ((row as Map<String, String>)['name'] ?? '').trim();
  }

  String _rowSub(dynamic row, _GroupConfig group) {
    if (!group.isTable || group.subField.isEmpty) return '';
    return ((row as Map<String, dynamic>)[group.subField] ?? '')
        .toString()
        .trim();
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // FIRST statement, unconditional: clearState (per-nav reset from
      // clearData) bumps this, and reading it here is what repaints the picker
      // back to group 0 with nothing ticked. Hoisted to the top so no ternary
      // or early return can short-circuit the observable read.
      // ignore: unused_local_variable
      final int rev = GroupPicker.resetRev.value;
      // Obx requires >=1 observable read on EVERY build path. An all-static
      // picker (no table group) would otherwise register ZERO observables and
      // get 4.7.3 throws "improper use of a GetX has been detected" -- the
      // dispatch try/catch has already returned, so it can't catch it and the
      // subtree becomes an ErrorWidget. Read the ACTIVE group's subscription
      // code UNCONDITIONALLY: '' for a static/absent group still registers the
      // dependency on the observable map and returns null harmlessly, and it
      // tracks the active table collection for reactivity. Mirrors
      // table_picker.dart build() (`final _ = mapTableContent[_code];`).
      final String activeCode = _groups.isEmpty
          ? ''
          : _groups[_activeIndex.clamp(0, _groups.length - 1)].subscriptionCode;
      // ignore: unused_local_variable
      final _ = mapTableContent[activeCode];

      if (_groups.isEmpty) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: const Text('--group_picker-- no groups'),
        );
      }

      final Color primary = Theme.of(context).primaryColor;
      final int activeIdx = _activeIndex.clamp(0, _groups.length - 1);
      final _GroupConfig activeGroup = _groups[activeIdx];
      final Set<String> selected = _selectedIds(activeGroup.key);
      final List<dynamic> rows = _activeRows();
      final bool showSelector = _showSelector;

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            if (_title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151), // gray-700
                  ),
                ),
              ),
            // Hint (shown only when nothing is selected)
            if (_hint.isNotEmpty && selected.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ), // gray-400
                ),
              ),
            // Segmented selector
            if (showSelector) _buildSelector(activeIdx, primary),
            // Search field
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: _t(0, 'Cari...'),
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: Color(0xFF9CA3AF),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6), // gray-100
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            // Item list
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    _t(1, 'Data tidak ditemukan'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              // Select-all header (multi + selectAll:true), above the tiles.
              // Stays FIXED (outside the R5 scroll box), directly above the list.
              if (_selectAllEnabled) ...[
                _selectAllTile(rows, activeGroup, selected, primary),
                const SizedBox(height: 4),
              ],
              // R5: bound the item-tile list to a capped, internally-scrollable
              // box so a long list doesn't push the page's send button far down.
              // SingleChildScrollView + Column(min) shrink-wraps for a few items
              // (no empty gap) and caps + scrolls for many -- a bare ListView
              // would greedily fill maxHeight even for 3 tiles.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _maxListHeight(context)),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final dynamic row in rows) ...[
                        _itemTile(
                          id: _rowId(row, activeGroup),
                          label: _rowLabel(row, activeGroup),
                          sub: _rowSub(row, activeGroup),
                          isSelected: selected.contains(
                            _rowId(row, activeGroup),
                          ),
                          groupKey: activeGroup.key,
                          primary: primary,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            // Count label (multi mode only)
            if (!_isSingle && selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _t(
                    4,
                    '{n} dipilih',
                  ).replaceAll('{n}', selected.length.toString()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280), // gray-500
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  // -- Bounded list height (R5) -----------------------------------------------

  /// Max height for the internally-scrollable item-tile list. Config
  /// `maxListHeight` (px, positive number) wins; else a responsive
  /// `screenHeight * 0.4` default. Bounds only the person-tile list so the rest
  /// of the page (send button/CTA) stays reachable instead of being pushed down.
  double _maxListHeight(BuildContext context) {
    final dynamic raw = widget.component['maxListHeight'];
    if (raw is num && raw > 0) return raw.toDouble();
    return MediaQuery.of(context).size.height * 0.4;
  }

  // -- Segmented selector -----------------------------------------------------

  Widget _buildSelector(int activeIdx, Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6), // gray-100
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: List.generate(_groups.length, (i) {
            final bool active = i == activeIdx;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (i != activeIdx) {
                    setState(() => _setActiveIndex(i));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _groups[i].label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? primary
                          : const Color(0xFF6B7280), // gray-500
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // -- Select-all header row (multi mode, opt-in) -----------------------------

  /// Control row rendered above the item tiles when `selectAll:true` (multi).
  /// 3-state leading icon reflects the ACTIVE group's selection vs the visible
  /// [rows]: all visible selected -> checked; some -> indeterminate; none ->
  /// blank. Styled distinctly (subtle primary fill + bold label) so it reads as
  /// a control, not a person/item. Tap -> [_toggleSelectAll].
  Widget _selectAllTile(
    List<dynamic> rows,
    _GroupConfig group,
    Set<String> selected,
    Color primary,
  ) {
    final List<String> visibleIds = rows
        .map((r) => _rowId(r, group))
        .where((id) => id.isNotEmpty)
        .toList();
    final int selectedCount = visibleIds
        .where((id) => selected.contains(id))
        .length;
    final bool allSelected =
        visibleIds.isNotEmpty && selectedCount == visibleIds.length;
    final bool someSelected = selectedCount > 0 && !allSelected;
    final IconData icon = allSelected
        ? Icons.check_box
        : (someSelected
              ? Icons.indeterminate_check_box
              : Icons.check_box_outline_blank);

    return GestureDetector(
      onTap: () => _toggleSelectAll(rows, group),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // Persistent subtle tint so the row reads as a control, not an item.
          color: primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFCBD5E1), // slate-300
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: (allSelected || someSelected)
                  ? primary
                  : const Color(0xFF94A3B8), // slate-400
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _t(5, 'Pilih semua'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155), // slate-700
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Item tile (checkbox/radio row) -----------------------------------------

  Widget _itemTile({
    required String id,
    required String label,
    required String sub,
    required bool isSelected,
    required String groupKey,
    required Color primary,
  }) {
    return GestureDetector(
      onTap: id.isEmpty ? null : () => _toggleItem(id, label, groupKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? primary : const Color(0xFFE2E8F0), // slate-200
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _isSingle
                  ? (isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked)
                  : (isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank),
              size: 20,
              color: isSelected
                  ? primary
                  : const Color(0xFF94A3B8), // slate-400
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.isNotEmpty ? label : id,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: const Color(0xFF1E293B), // slate-800
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ), // slate-500
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
