import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // diamondTextToList, mapTableContent, emptyString
import '../global2.dart'; // txfController, txfControllerCheck, getPosition
import 'driver_home_support.dart'; // resolveAppVid
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'picker_list.dart'; // PickerList.filterRows (static reuse, no coupling)

/// TABLE_PICKER -- generic single/multi-select picker bound to form positions.
///
/// Picks records from a keyed Firestore table collection, writes value(s) into
/// `txfController[scrName][position].finalData` and label(s) into
/// `txfController[scrName][labelPosition].finalData`.
///
/// Single mode: bare string value/label.
/// Multi mode: JSON-array string `["v1","v2"]` / `["l1","l2"]`.
///
/// SDUI type: `table_picker`.
class TablePicker extends StatefulWidget {
  const TablePicker({
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

  // ── Per-screen state store ──────────────────────────────────────────────

  /// Working set for multi-select: `{ scrName -> { position -> Set<vid> } }`.
  /// ponytail: keyed by scrName+position so two pickers on one screen don't collide.
  static final Map<String, Map<int, Set<String>>> _selectionStore = {};

  /// Companion label store: `{ scrName -> { position -> { vid -> label } } }`.
  static final Map<String, Map<int, Map<String, String>>> _labelStore = {};

  /// Clear per-screen state. Called from buildPage clearData path.
  static void clearState(String scrName) {
    _selectionStore.remove(scrName);
    _labelStore.remove(scrName);
  }

  // ── Pure static helpers (testable without SDUI globals) ─────────────────

  /// Resolve the value to capture from a doc row.
  /// Empty [valueField] -> doc id (`__docId`). Otherwise -> doc[valueField].
  static String resolveValueFromDoc(
    Map<String, dynamic> doc,
    String valueField,
  ) {
    if (valueField.isEmpty) {
      return (doc['__docId'] ?? '').toString().trim();
    }
    return (doc[valueField] ?? '').toString().trim();
  }

  /// Encode a list of selected values for form output.
  ///
  /// Single mode: bare string (first element or empty) — unaffected by the note
  /// below.
  ///
  /// Multi mode: a JSON-array string, e.g. `["V1","V2"]`. IMPORTANT: on submit
  /// the app runs this through `stringCleanUp` -> `quoteCleanUp`
  /// (`global.dart`), which escapes `"` -> two backticks and `'` -> one
  /// backtick. So the value PERSISTS BACKTICK-ESCAPED, e.g.
  /// `` [``V1``,``V2``] ``, which is NOT valid JSON. The consumer — the
  /// `Consteon/asset_cache` Cloud Function `onFateProjectCreated` — MUST reverse
  /// it before `JSON.parse`, in this order (two-backticks first):
  ///   `s.replaceAll('``', '"').replaceAll('`', "'")`.
  static String encodeSelection(List<String> values, {required bool isSingle}) {
    if (isSingle) {
      return values.isNotEmpty ? values.first : '';
    }
    return jsonEncode(values);
  }

  /// Decode a stored form value back to a list (for re-open / chip display).
  static List<String> decodeSelection(String stored, {required bool isSingle}) {
    if (stored.isEmpty || stored == emptyString) return [];
    if (isSingle) {
      return [stored];
    }
    try {
      final List<dynamic> parsed = jsonDecode(stored);
      return parsed.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Length-guarded text segment accessor.
  static String textSegment(List<String> arr, int index, String def) {
    return arr.length > index ? arr[index] : def;
  }

  /// Whether more items can be added given the max constraint.
  /// max 0 = unlimited.
  static bool canAddMore({required int currentCount, required int max}) {
    if (max <= 0) return true;
    return currentCount < max;
  }

  /// Client-side text search: filter rows by labelField/subField contains query.
  static List<Map<String, dynamic>> clientSearch(
    List<Map<String, dynamic>> rows,
    String query,
    String labelField,
    String subField,
  ) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((r) {
      final String label = (r[labelField] ?? '').toString().toLowerCase();
      final String sub = (r[subField] ?? '').toString().toLowerCase();
      return label.contains(q) || sub.contains(q);
    }).toList();
  }

  @override
  State<TablePicker> createState() => _TablePickerState();
}

class _TablePickerState extends State<TablePicker> {
  String _code = ''; // subscription code for mapTableContent
  List<String> _textArray = [];

  // ── Config accessors ────────────────────────────────────────────────────

  bool get _isSingle =>
      (widget.component['mode'] ?? 'single').toString().trim().toLowerCase() ==
      'single';

  int get _position => getPosition(widget.component['position']);

  int get _labelPosition => getPosition(widget.component['labelPosition']);

  String get _labelField =>
      (widget.component['labelField'] ?? 'n').toString().trim();

  String get _subField =>
      (widget.component['subField'] ?? '').toString().trim();

  String get _valueField =>
      (widget.component['valueField'] ?? '').toString().trim();

  int get _max {
    if (_isSingle) return 1;
    final dynamic raw = widget.component['max'];
    if (raw == null) return 0;
    return int.tryParse(raw.toString()) ?? 0;
  }

  String get _title => (widget.component['title'] ?? '').toString().trim();

  String get _hint => (widget.component['hint'] ?? '').toString().trim();

  /// Text segment helper with defaults.
  String _t(int i, String def) => TablePicker.textSegment(_textArray, i, def);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
    _seedFromController();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's
    // same tableDocId/subColl would dedup our stream away. Mirrors PickerList.
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  /// Seed the working set from any existing txfController value (re-open case).
  void _seedFromController() {
    final String scrName = widget.scrName;
    final int pos = _position;
    // Only seed if the store is empty for this scrName+position
    final existing = TablePicker._selectionStore[scrName]?[pos];
    if (existing != null && existing.isNotEmpty) return;

    if (txfController[scrName]?[pos] != null) {
      final String stored = txfController[scrName]![pos]!.finalData;
      if (stored.isNotEmpty && stored != emptyString) {
        final List<String> values = TablePicker.decodeSelection(
          stored,
          isSingle: _isSingle,
        );
        if (values.isNotEmpty) {
          TablePicker._selectionStore
              .putIfAbsent(scrName, () => {})
              .putIfAbsent(pos, () => {})
              .addAll(values);
        }
      }
    }
    // Seed labels from labelPosition controller
    if (txfController[scrName]?[_labelPosition] != null) {
      final String storedLabels =
          txfController[scrName]![_labelPosition]!.finalData;
      if (storedLabels.isNotEmpty && storedLabels != emptyString) {
        final List<String> labels = TablePicker.decodeSelection(
          storedLabels,
          isSingle: _isSingle,
        );
        final Set<String> vids =
            TablePicker._selectionStore[scrName]?[pos] ?? {};
        if (labels.length == vids.length) {
          final Map<String, String> labelMap = {};
          final List<String> vidList = vids.toList();
          for (int i = 0; i < vidList.length; i++) {
            labelMap[vidList[i]] = labels[i];
          }
          TablePicker._labelStore.putIfAbsent(scrName, () => {})[pos] =
              labelMap;
        }
      }
    }
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _allRows() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    return PickerList.filterRows(docs, rawSearch);
  }

  /// Current selected vids for this picker instance.
  Set<String> get _selectedVids {
    return TablePicker._selectionStore[widget.scrName]?[_position] ?? {};
  }

  /// Current label map for this picker instance.
  Map<String, String> get _labelMap {
    return TablePicker._labelStore[widget.scrName]?[_position] ?? {};
  }

  // ── Write to txfController ──────────────────────────────────────────────

  void _writeToController() {
    final String scrName = widget.scrName;
    final int pos = _position;
    final int lPos = _labelPosition;
    final Set<String> vids = _selectedVids;
    final Map<String, String> labels = _labelMap;

    txfControllerCheck(scrName, pos);
    txfControllerCheck(scrName, lPos);

    final List<String> valueList = vids.toList();
    final List<String> labelList = valueList
        .map((v) => labels[v] ?? '')
        .toList();

    txfController[scrName]![pos]!.finalData = TablePicker.encodeSelection(
      valueList,
      isSingle: _isSingle,
    );
    txfController[scrName]![lPos]!.finalData = TablePicker.encodeSelection(
      labelList,
      isSingle: _isSingle,
    );
  }

  // ── Sheet ───────────────────────────────────────────────────────────────

  void _openSheet() {
    // Snapshot current selection into a temporary working set for the sheet.
    // If user cancels, we discard changes. If confirms, we commit.
    final Set<String> workingSet = Set<String>.from(_selectedVids);
    final Map<String, String> workingLabels = Map<String, String>.from(
      _labelMap,
    );

    showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _TablePickerSheet(
          rows: _allRows(),
          initialSelection: workingSet,
          initialLabels: workingLabels,
          isSingle: _isSingle,
          max: _max,
          labelField: _labelField,
          subField: _subField,
          valueField: _valueField,
          sheetTitle: _t(0, _title),
          searchHint: _t(1, ''),
          emptyText: _t(2, 'Tidak ada data'),
          confirmLabel: _t(3, 'Pilih'),
          cancelLabel: _t(4, 'Batal'),
          countTemplate: _t(5, '{n} dipilih'),
        );
      },
    ).then((result) {
      if (result == null) return; // dismissed / cancelled
      if (!mounted) return;

      // Commit the sheet result into the per-screen store
      final String scrName = widget.scrName;
      final int pos = _position;
      TablePicker._selectionStore.putIfAbsent(scrName, () => {})[pos] =
          result.vids;
      TablePicker._labelStore.putIfAbsent(scrName, () => {})[pos] =
          result.labels;

      _writeToController();
      setState(() {}); // rebuild chips
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch mapTableContent to register the reactive dependency so the field
      // rebuilds when the subscription emits (Obx requires >=1 observable read).
      final _ = mapTableContent[_code];

      final Color primary = Theme.of(context).primaryColor;
      final Set<String> selected = _selectedVids;
      final Map<String, String> labels = _labelMap;

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
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151), // gray-700
                  ),
                ),
              ),
            // Tap target
            GestureDetector(
              onTap: _openSheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD1D5DB),
                  ), // gray-300
                ),
                child: selected.isEmpty
                    ? Text(
                        _hint.isNotEmpty ? _hint : _t(0, 'Pilih...'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF), // gray-400
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: selected.map((vid) {
                          final String label = labels[vid] ?? vid;
                          return _chip(label, primary, () {
                            setState(() {
                              _selectedVids.remove(vid);
                              _labelMap.remove(vid);
                              _writeToController();
                            });
                          });
                        }).toList(),
                      ),
              ),
            ),
            // Count label for multi
            if (!_isSingle && selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _t(
                    5,
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

  /// Selected-value chip. Colors derive from the theme accent so branded
  /// (white-label) apps don't clash (W3).
  Widget _chip(String label, Color primary, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 14, color: primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: primary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheet result ──────────────────────────────────────────────────────────────

class _SheetResult {
  final Set<String> vids;
  final Map<String, String> labels; // vid -> label
  const _SheetResult(this.vids, this.labels);
}

// ── Picker sheet (stateful, lives inside showModalBottomSheet) ────────────────

class _TablePickerSheet extends StatefulWidget {
  const _TablePickerSheet({
    required this.rows,
    required this.initialSelection,
    required this.initialLabels,
    required this.isSingle,
    required this.max,
    required this.labelField,
    required this.subField,
    required this.valueField,
    required this.sheetTitle,
    required this.searchHint,
    required this.emptyText,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.countTemplate,
  });

  final List<Map<String, dynamic>> rows;
  final Set<String> initialSelection;
  final Map<String, String> initialLabels;
  final bool isSingle;
  final int max;
  final String labelField;
  final String subField;
  final String valueField;
  final String sheetTitle;
  final String searchHint;
  final String emptyText;
  final String confirmLabel;
  final String cancelLabel;
  final String countTemplate;

  @override
  State<_TablePickerSheet> createState() => _TablePickerSheetState();
}

class _TablePickerSheetState extends State<_TablePickerSheet> {
  late Set<String> _selected;
  late Map<String, String> _labels;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelection);
    _labels = Map<String, String>.from(widget.initialLabels);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(Map<String, dynamic> doc) {
    final String vid = TablePicker.resolveValueFromDoc(doc, widget.valueField);
    final String label = (doc[widget.labelField] ?? '').toString().trim();

    if (vid.isEmpty) return;

    setState(() {
      if (_selected.contains(vid)) {
        _selected.remove(vid);
        _labels.remove(vid);
      } else {
        if (!TablePicker.canAddMore(
          currentCount: _selected.length,
          max: widget.max,
        )) {
          return;
        }
        _selected.add(vid);
        _labels[vid] = label;
      }
    });

    // Single mode: auto-confirm on selection
    if (widget.isSingle && _selected.isNotEmpty) {
      Navigator.pop(context, _SheetResult(_selected, _labels));
    }
  }

  void _confirm() {
    Navigator.pop(context, _SheetResult(_selected, _labels));
  }

  void _cancel() {
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> filtered = TablePicker.clientSearch(
      widget.rows,
      _query,
      widget.labelField,
      widget.subField,
    );

    final double screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              widget.sheetTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          // Search box
          if (widget.searchHint.isNotEmpty || widget.rows.length > 5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: widget.searchHint.isNotEmpty
                      ? widget.searchHint
                      : 'Cari...',
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
          const SizedBox(height: 8),
          const Divider(height: 1),
          // List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.emptyText,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final Map<String, dynamic> doc = filtered[index];
                      final String vid = TablePicker.resolveValueFromDoc(
                        doc,
                        widget.valueField,
                      );
                      final String label = (doc[widget.labelField] ?? '')
                          .toString()
                          .trim();
                      final String sub = widget.subField.isEmpty
                          ? ''
                          : (doc[widget.subField] ?? '').toString().trim();
                      final bool isSelected = _selected.contains(vid);
                      final bool canAdd = TablePicker.canAddMore(
                        currentCount: _selected.length,
                        max: widget.max,
                      );

                      return ListTile(
                        title: Text(
                          label.isNotEmpty ? label : vid,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: sub.isNotEmpty
                            ? Text(
                                sub,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).primaryColor,
                                size: 22,
                              )
                            : (canAdd
                                  ? Icon(
                                      Icons.radio_button_unchecked,
                                      color: Colors.grey.shade400,
                                      size: 22,
                                    )
                                  : Icon(
                                      Icons.block,
                                      color: Colors.grey.shade300,
                                      size: 22,
                                    )),
                        onTap: (isSelected || canAdd)
                            ? () => _toggle(doc)
                            : null,
                      );
                    },
                  ),
          ),
          // Bottom bar (multi mode only)
          if (!widget.isSingle) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Count
                  Expanded(
                    child: Text(
                      widget.countTemplate.replaceAll(
                        '{n}',
                        _selected.length.toString(),
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                  // Cancel
                  TextButton(
                    onPressed: _cancel,
                    child: Text(
                      widget.cancelLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Confirm
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      widget.confirmLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
