import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // diamondTextToList, mapTableContent, autheniumDecode
import '../global2.dart'; // txfController, txfControllerCheck, getPosition
import '../screen_session.dart';
import 'admin_create_task_support.dart'; // AdminCreateTaskSupport.formatRupiah
import 'driver_home_support.dart'; // resolveAppVid, resolveDriverCurlyTokens, coerceNum
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'picker_list.dart'; // PickerList.filterRows
import 'table_picker.dart'; // TablePicker.resolveValueFromDoc
import 'task_item_builder.dart'; // TaskItemBuilder.sortPickerItems

/// PAYOUT_LIST -- multi-select list with per-item nominal (count x rate),
/// select-all, summary totals, emitting values/labels/total to form positions.
///
/// SDUI type: `payout_list`.
class PayoutList extends StatefulWidget {
  const PayoutList({
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

  // -- Per-screen state store --------------------------------------------------
  // Keyed by scrName+position so two PayoutLists on one screen don't collide.
  //
  // _selectionStore is intentionally allowed to hold stale ids (from rows that
  // departed the live Firestore subscription after CF reset). Emission always
  // intersects with the live row set via _writeToController, so departed ids
  // are silently excluded from all three outputs. Do NOT add a pruning pass --
  // the intersection approach is simpler and correct by construction.

  /// Selection: `{ scrName -> { position -> Set<id> } }`.
  static final Map<String, Map<int, Set<String>>> _selectionStore = {};

  /// Clear per-screen state. Called from clearData (api.dart) and buildPage
  /// (ui_component.dart) on route change.
  static void registerScreenSession() {
    ScreenSession.ensure('PayoutList.selectionStore', PayoutList.clearState);
  }

  static void clearState(String scrName) {
    _selectionStore.remove(scrName);
  }

  // -- Pure static helpers (testable without SDUI globals) --------------------

  /// Length-guarded text segment accessor.
  static String textSegment(List<String> arr, int index, String def) {
    return arr.length > index ? arr[index] : def;
  }

  /// Replace [token] with [value] in [template]. When [value] is non-empty this
  /// is a plain substitution. When [value] is empty, the token is removed along
  /// with ONE adjacent separator run so no orphan separator or doubled space is
  /// left behind, wherever the token sits (start, middle, or end).
  ///
  /// A "separator" is a run of optional whitespace + a single non-alphanumeric
  /// punctuation character + optional whitespace (e.g. ` · `, ` — `, ` | `,
  /// ` - `). Removal prefers the TRAILING separator (`… {total} · {n} worker`
  /// -> `… {n} worker`), then the LEADING separator (`{n} dipilih · {total}`
  /// -> `{n} dipilih`), then falls back to a plain token strip. Generalised so
  /// tenants can author any separator character without hardcoding `·`.
  static String collapseTemplate(String template, String token, String value) {
    if (value.isNotEmpty) return template.replaceAll(token, value);
    final String esc = RegExp.escape(token);
    const String sep = r'\s*[^\w\s]\s*';
    // token + following separator  ("… {total} · {n} worker" -> "… {n} worker")
    if (RegExp('$esc$sep').hasMatch(template)) {
      return template.replaceAll(RegExp('$esc$sep'), '').trim();
    }
    // preceding separator + token  ("{n} dipilih · {total}" -> "{n} dipilih")
    if (RegExp('$sep$esc').hasMatch(template)) {
      return template.replaceAll(RegExp('$sep$esc'), '').trim();
    }
    return template.replaceAll(token, '').trim();
  }

  @override
  State<PayoutList> createState() => _PayoutListState();
}

class _PayoutListState extends State<PayoutList> {
  List<String> _textArray = [];
  String _code = ''; // mapTableContent subscription code
  int _parsedRate = 0; // rate per unit (0 = non-money mode)

  // -- Config accessors -------------------------------------------------------

  int get _position => getPosition(widget.component['position']);

  int? get _labelPosition {
    final dynamic raw = widget.component['labelPosition'];
    return raw != null ? getPosition(raw) : null;
  }

  int? get _totalPosition {
    final dynamic raw = widget.component['totalPosition'];
    return raw != null ? getPosition(raw) : null;
  }

  String get _labelField =>
      (widget.component['labelField'] ?? 'n').toString().trim();

  String get _subField =>
      (widget.component['subField'] ?? '').toString().trim();

  String get _countField =>
      (widget.component['countField'] ?? '').toString().trim();

  String get _valueField =>
      (widget.component['valueField'] ?? '').toString().trim();

  String get _sortField =>
      (widget.component['sortField'] ?? '').toString().trim();

  String get _sortDir =>
      (widget.component['sortDir'] ?? 'asc').toString().trim().toLowerCase();

  bool get _selectAllEnabled => widget.component['selectAll'] == true;

  String get _joinSep {
    final dynamic raw = widget.component['joinSep'];
    return (raw != null && raw.toString().isNotEmpty) ? raw.toString() : '|';
  }

  bool get _moneyMode => _parsedRate > 0;

  String _t(int i, String def) => PayoutList.textSegment(_textArray, i, def);

  // -- Lifecycle --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    PayoutList.registerScreenSession();
    _parseText();
    _parseRate();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _parseRate() {
    final dynamic raw = widget.component['rate'];
    if (raw == null) {
      _parsedRate = 0;
      return;
    }
    final num parsed = num.tryParse(raw.toString().trim()) ?? 0;
    // ponytail: .round() is intentional -- fractional rates like "1000.5"
    // become 1001. Correct for whole-rupiah; upgrade to double math if
    // sub-rupiah precision ever matters.
    _parsedRate = parsed > 0 ? parsed.round() : 0;
  }

  /// Decode server escapes + resolve session/screenTx `{token}`s before the
  /// gate DSL sees the search string. PickerList.filterRows re-decodes
  /// (idempotent) but never resolves tokens.
  String _resolveSearch(String raw) =>
      resolveDriverCurlyTokens(autheniumDecode(raw) ?? raw, widget.scrName);

  /// Build the vid-scoped subscription code and subscribe. Returns '' when the
  /// component has no usable `table`. ONE derivation -- no duplicate copy risk.
  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final String appVid = resolveAppVid(widget.component);
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  // -- Selection helpers ------------------------------------------------------

  Set<String> get _selectedIds {
    return PayoutList._selectionStore[widget.scrName]?[_position] ??
        const <String>{};
  }

  void _ensureStore() {
    PayoutList._selectionStore
        .putIfAbsent(widget.scrName, () => {})
        .putIfAbsent(_position, () => <String>{});
  }

  // -- Data rows --------------------------------------------------------------

  /// Get filtered + sorted rows from the subscription.
  List<Map<String, dynamic>> _getRows() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final String resolvedSearch = rawSearch.isNotEmpty
        ? _resolveSearch(rawSearch)
        : '';
    final List<Map<String, dynamic>> filtered = resolvedSearch.isNotEmpty
        ? PickerList.filterRows(docs, resolvedSearch)
        : docs;

    // Sort in-place (TaskItemBuilder.sortPickerItems mutates the list).
    if (_sortField.isNotEmpty) {
      TaskItemBuilder.sortPickerItems(
        filtered,
        sortField: _sortField,
        sortDir: _sortDir,
        nameField: _labelField,
      );
    }
    return filtered;
  }

  /// Resolve the emitted value for a doc row.
  String _rowValue(Map<String, dynamic> row) =>
      TablePicker.resolveValueFromDoc(row, _valueField);

  /// Resolve the display label for a doc row.
  String _rowLabel(Map<String, dynamic> row) =>
      (row[_labelField] ?? '').toString().trim();

  /// Resolve the sub-label for a doc row.
  String _rowSub(Map<String, dynamic> row) {
    if (_subField.isEmpty) return '';
    return (row[_subField] ?? '').toString().trim();
  }

  /// Resolve the count field as a num.
  num _rowCount(Map<String, dynamic> row) {
    if (_countField.isEmpty) return 0;
    return coerceNum(row[_countField]);
  }

  /// Compute nominal for a single row: count * rate.
  int _rowNominal(Map<String, dynamic> row) {
    if (!_moneyMode) return 0;
    return (_rowCount(row) * _parsedRate).round();
  }

  // -- Toggle -----------------------------------------------------------------

  void _toggleItem(String id, List<Map<String, dynamic>> rows) {
    if (id.isEmpty) return;
    _ensureStore();
    final Set<String> ids =
        PayoutList._selectionStore[widget.scrName]![_position]!;
    setState(() {
      if (ids.contains(id)) {
        ids.remove(id);
      } else {
        ids.add(id);
      }
    });
    _writeToController(rows);
  }

  void _toggleSelectAll(List<Map<String, dynamic>> rows) {
    _ensureStore();
    final Set<String> ids =
        PayoutList._selectionStore[widget.scrName]![_position]!;
    final List<String> visibleIds = rows
        .map((r) => _rowValue(r))
        .where((id) => id.isNotEmpty)
        .toList();

    setState(() {
      if (visibleIds.isNotEmpty && visibleIds.every((id) => ids.contains(id))) {
        // Deselect all.
        for (final String id in visibleIds) {
          ids.remove(id);
        }
      } else {
        // Select all.
        for (final String id in visibleIds) {
          ids.add(id);
        }
      }
    });
    _writeToController(rows);
  }

  // -- Emit to txfController --------------------------------------------------

  /// Write all three form positions from ONE ordered pass over [rows].
  ///
  /// This guarantees that position (values) and labelPosition (labels) are
  /// index-aligned parallel arrays in sorted display order, regardless of the
  /// order the admin tapped the checkboxes. It also means stale ids in
  /// _selectionStore (from rows that departed the live Firestore set) are
  /// automatically excluded from all three outputs.
  void _writeToController(List<Map<String, dynamic>> rows) {
    final String scrName = widget.scrName;
    final int pos = _position;
    final Set<String> ids = _selectedIds;
    final String joinSep = _joinSep;

    // Single ordered pass: collect values, labels, and total together.
    final List<String> vals = <String>[];
    final List<String> labels = <String>[];
    int total = 0;
    for (final Map<String, dynamic> row in rows) {
      final String id = _rowValue(row);
      if (id.isEmpty || !ids.contains(id)) continue;
      vals.add(id);
      labels.add(_rowLabel(row));
      total += _rowNominal(row);
    }

    // Value position (required).
    txfControllerCheck(scrName, pos);
    txfController[scrName]![pos]!.finalData = vals.isEmpty
        ? ''
        : vals.join(joinSep);

    // Label position (optional).
    final int? lPos = _labelPosition;
    if (lPos != null) {
      txfControllerCheck(scrName, lPos);
      txfController[scrName]![lPos]!.finalData = vals.isEmpty
          ? ''
          : labels.join(joinSep);
    }

    // Total position (optional).
    final int? tPos = _totalPosition;
    if (tPos != null) {
      txfControllerCheck(scrName, tPos);
      txfController[scrName]![tPos]!.finalData = (vals.isEmpty || !_moneyMode)
          ? '0'
          : total.toString();
    }
  }

  // -- Bounded list height ----------------------------------------------------

  double _maxListHeight(BuildContext context) {
    final dynamic raw = widget.component['maxListHeight'];
    if (raw is num && raw > 0) return raw.toDouble();
    return MediaQuery.sizeOf(context).height * 0.4;
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // UNCONDITIONAL observable read -- Prior Correction #4.
      // Prevents GetX 4.7.3 "improper use" crash when mapTableContent[_code]
      // is behind a conditional early-return.
      // ignore: unused_local_variable
      final _ = mapTableContent[_code];

      final List<Map<String, dynamic>> rows = _getRows();
      final Set<String> selected = _selectedIds;
      final Color primary = Theme.of(context).primaryColor;

      // Compute grand total (all rows) and selected total.
      int grandTotal = 0;
      int selectedTotal = 0;
      for (final Map<String, dynamic> row in rows) {
        final int nom = _rowNominal(row);
        grandTotal += nom;
        if (selected.contains(_rowValue(row))) {
          selectedTotal += nom;
        }
      }

      // Count live-selected (intersection of stored ids with current rows).
      final int liveSelectedCount = rows
          .where((r) => selected.contains(_rowValue(r)))
          .length;

      final String summaryText = _buildSummary(rows.length, grandTotal);

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
            // Title (text[0]).
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _t(0, ''),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B), // slate-800
                ),
              ),
            ),

            // Summary line (text[5]) -- grand total + worker count.
            // Only render when text[5] produced a non-empty result (I4 fix).
            if (rows.isNotEmpty && summaryText.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  summaryText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569), // slate-600
                  ),
                ),
              ),
            ],

            // Select-all row (FIXED, above scroll region).
            if (rows.isNotEmpty && _selectAllEnabled) ...[
              _selectAllTile(rows, selected, primary),
              const SizedBox(height: 4),
            ],

            // Selected counter (text[3]).
            // Note (I1): the mockup places this on the same row as select-all
            // (right-aligned). This renders it as a separate line below --
            // acceptable divergence, revisit if the designer requests inline.
            if (rows.isNotEmpty && liveSelectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _buildSelectedCounter(liveSelectedCount, selectedTotal),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ),

            // Empty state (text[1]).
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    _t(1, 'Tidak ada data'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            // Item list (bounded scroll).
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _maxListHeight(context)),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final Map<String, dynamic> row in rows) ...[
                        _itemTile(
                          row: row,
                          rows: rows,
                          isSelected: selected.contains(_rowValue(row)),
                          primary: primary,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  // -- Template builders ------------------------------------------------------

  /// Build the summary line from text[5]. Replaces {total} and {n}.
  String _buildSummary(int workerCount, int grandTotal) {
    String tpl = _t(5, '');
    if (tpl.isEmpty) return '';
    tpl = tpl.replaceAll('{n}', workerCount.toString());
    if (_moneyMode) {
      tpl = tpl.replaceAll(
        '{total}',
        AdminCreateTaskSupport.formatRupiah(grandTotal),
      );
    } else {
      tpl = PayoutList.collapseTemplate(tpl, '{total}', '');
    }
    return tpl;
  }

  /// Build the selected counter from text[3]. Replaces {n} and {total}.
  String _buildSelectedCounter(int count, int selectedTotal) {
    String tpl = _t(3, '{n} dipilih');
    tpl = tpl.replaceAll('{n}', count.toString());
    if (_moneyMode) {
      tpl = tpl.replaceAll(
        '{total}',
        AdminCreateTaskSupport.formatRupiah(selectedTotal),
      );
    } else {
      tpl = PayoutList.collapseTemplate(tpl, '{total}', '');
    }
    return tpl;
  }

  /// Build the per-item nominal line from text[4]. Replaces {c} and {nom}.
  /// Uses .toInt() on count to avoid displaying "3.0" when Firestore sends
  /// a Number as a double.
  String _buildItemNominal(Map<String, dynamic> row) {
    if (!_moneyMode) return '';
    String tpl = _t(4, '{c} · {nom}');
    tpl = tpl.replaceAll('{c}', _rowCount(row).toInt().toString());
    tpl = tpl.replaceAll(
      '{nom}',
      AdminCreateTaskSupport.formatRupiah(_rowNominal(row)),
    );
    return tpl;
  }

  // -- Select-all tile --------------------------------------------------------

  Widget _selectAllTile(
    List<Map<String, dynamic>> rows,
    Set<String> selected,
    Color primary,
  ) {
    final List<String> visibleIds = rows
        .map((r) => _rowValue(r))
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

    // text[2] with {n} = total row count.
    final String label = _t(
      2,
      'Pilih semua ({n})',
    ).replaceAll('{n}', rows.length.toString());

    return GestureDetector(
      onTap: () => _toggleSelectAll(rows),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
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
                label,
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

  // -- Item tile --------------------------------------------------------------

  Widget _itemTile({
    required Map<String, dynamic> row,
    required List<Map<String, dynamic>> rows,
    required bool isSelected,
    required Color primary,
  }) {
    final String id = _rowValue(row);
    final String label = _rowLabel(row);
    final String sub = _rowSub(row);
    final String nominal = _buildItemNominal(row);

    return GestureDetector(
      onTap: id.isEmpty ? null : () => _toggleItem(id, rows),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? primary.withValues(alpha: 0.3)
                : const Color(0xFFE2E8F0), // slate-200
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: isSelected ? primary : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label (name).
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B), // slate-800
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Sub-label (handle).
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B), // slate-500
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Nominal line (count x rate).
                  if (nominal.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        nominal,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF475569), // slate-600
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
