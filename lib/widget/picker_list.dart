import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // transactionStore, mapTableContent, diamondTextToList, autheniumDecode, routeStack, gotoRoute, routeExist
import '../redux/screen_transaction.dart'; // UpdateScreenTxAction, ScreenTransaction
import 'admin_create_task_support.dart'; // AdminCreateTaskSupport.setVehicle
import 'admin_home_support.dart'; // evaluateGate
import 'driver_home_support.dart'; // resolveAppVid, stripRouteWrapper
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'task_item_builder.dart'; // TaskItemBuilder.draftRev

/// PICKER_LIST -- generic single-select picker.
///
/// Pick one record from ANY collection, capture its id into a token. Optional
/// per-row count badge + an "ad-hoc / lainnya" row. ZERO entity baked into the
/// renderer -- vehicle / warehouse / slot / category / approver / customer are
/// all just config (table/search/field/token/route).
///
/// Modes:
///   capture  (default) -- bind `captureToken` = selected id into screenTx.
///                         No navigate, no Firestore write. Caller/page consumes.
///   navigate           -- capture + push `route` (carrying the id via screenTx).
///
/// The picker NEVER writes Firestore itself. The write is the caller's job
/// (e.g. H1 updateEventRow) or the page submit (e.g. create-task P3 -> P4 draft).
///
/// SDUI type: `picker_list` (aliases `pickerlist`, legacy `vehicle_picker`).
class PickerList extends StatefulWidget {
  const PickerList({
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

  /// screenTx bare key the selection is bound to. Default `vv` (the create-task
  /// P3 case). Override per context (`vehicleId`, `kl`, ...).
  static String resolveCaptureToken(dynamic component) {
    final String raw = (component['captureToken'] ?? '').toString().trim();
    return raw.isNotEmpty ? raw : 'vv';
  }

  /// Doc field whose value is (a) captured into captureToken and (b) substituted
  /// for `{idField}` in countSearch. Default `lv`.
  static String resolveIdField(dynamic component) {
    final String raw = (component['idField'] ?? '').toString().trim();
    return raw.isNotEmpty ? raw : 'lv';
  }

  /// Filter source docs to selectable rows using the `search` gate-DSL.
  /// [rawSearch] is the un-decoded `component['search']`; autheniumDecode'd then
  /// AND-matched via [evaluateGate]. Empty/absent search -> ALL docs (no entity
  /// fallback -- the renderer is collection-agnostic).
  static List<Map<String, dynamic>> filterRows(
    List<Map<String, dynamic>> docs,
    String rawSearch,
  ) {
    final String trimmed = rawSearch.trim();
    if (trimmed.isEmpty) return docs;
    final String gate = autheniumDecode(trimmed) ?? trimmed;
    if (gate.isEmpty) return docs;
    return docs.where((d) => evaluateGate(d, gate)).toList();
  }

  /// DSLs already logged for unresolved-token bail. Prevents per-row-per-build
  /// flood: countForRow runs N-rows x every Obx repaint (W1).
  static final Set<String> _loggedUnresolved = <String>{};

  /// Resolve time tokens in a gate DSL: `{today}` -> WIB epoch-midnight ms.
  ///
  /// Deliberately NOT [resolveDriverCurlyTokens]: that resolver's `default:`
  /// branch substitutes ANY unknown `{name}` from screen-tx bare keys, which
  /// would eat a per-row token like `{lv}` the moment some route published a
  /// bare `lv`. This one touches the time tokens and nothing else.
  ///
  /// Called per evaluation, not at config-parse: a screen left open past
  /// midnight must roll over to the new day.
  static String resolveTimeTokens(String dsl) {
    if (!dsl.contains('{today}')) return dsl;
    return dsl.replaceAll('{today}', todayEpochMidnightWib());
  }

  /// Count docs in [countDocs] matching [rawCountSearch] after substituting the
  /// per-row token `{idField}` -> [rowId]. Empty count config -> 0 (no badge).
  ///
  /// `{today}` is resolved first — without that, a dated search silently
  /// counts 0 (the `contains('{')` bail below), which reads as "nothing is
  /// busy" rather than as a misconfiguration.
  static int countForRow(
    List<Map<String, dynamic>> countDocs,
    String rawCountSearch,
    String idField,
    String rowId,
  ) {
    final String trimmed = rawCountSearch.trim();
    if (trimmed.isEmpty) return 0;
    final String decoded = autheniumDecode(trimmed) ?? trimmed;
    final String resolved = resolveTimeTokens(
      decoded,
    ).replaceAll('{$idField}', rowId);
    // Unresolved row token (or empty rowId) -> a meaningless count; bail to 0.
    if (resolved.contains('{') || rowId.isEmpty) {
      if (resolved.contains('{') && _loggedUnresolved.add(resolved)) {
        devPrint(
          '[pickerList] countForRow: unresolved token in DSL '
          '"$resolved" (idField=$idField, rowId=$rowId) -- bailing to 0',
        );
      }
      return 0;
    }
    return countDocs.where((d) => evaluateGate(d, resolved)).length;
  }

  /// Derive the combined lock state from two independent guards (D3):
  ///   1. busySelf  -- row's own field is non-empty (driver assigned)
  ///   2. statusLock -- statusSearch matched AND disableWhenStatusOn
  ///
  /// Either guard firing -> row locked (isBusy, onTap:null).
  /// Both firing -> labels joined with ' · ' (D7).
  ///
  /// The row-field extraction (null, missing key, whitespace) is owned by
  /// this static so callers and tests exercise the same code path (C1).
  static ({bool isBusy, String busyLabel}) deriveRowLock({
    required Map<String, dynamic> row,
    required String busySelfField,
    required String busySelfLabelField,
    required String busyPrefix,
    required bool statusOn,
    required String statusOnLabel,
    required bool disableWhenStatusOn,
  }) {
    final String busyVal = busySelfField.isEmpty
        ? ''
        : (row[busySelfField] ?? '').toString().trim();
    final bool busySelfBusy = busyVal.isNotEmpty;
    final bool statusLocked = statusOn && disableWhenStatusOn;
    if (!busySelfBusy && !statusLocked) return (isBusy: false, busyLabel: '');
    final String busySelfLabel = busySelfBusy
        ? '$busyPrefix${(row[busySelfLabelField] ?? '').toString().trim()}'
        : '';
    final List<String> parts = [
      if (busySelfLabel.isNotEmpty) busySelfLabel,
      if (statusLocked && statusOnLabel.isNotEmpty) statusOnLabel,
    ];
    return (isBusy: true, busyLabel: parts.join(' \u{00B7} '));
  }

  /// Parse a hex color string from component config.
  ///
  /// Handles formats:
  ///   "0xFF2563EB", "FF2563EB", "2563EB", "#2563EB", "#ff2563eb"
  /// Returns null on invalid/empty/null input (caller falls back to
  /// Theme.primaryColor for backward-compat).
  static Color? parseHexColor(String? raw) {
    if (raw == null) return null;
    String hex = raw.trim();
    if (hex.isEmpty) return null;
    // Strip "0x" / "0X" prefix
    if (hex.length > 2 && (hex.startsWith('0x') || hex.startsWith('0X'))) {
      hex = hex.substring(2);
    }
    // Strip "#" prefix
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    // 6-char RGB -> prepend FF alpha
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    // Must be exactly 8 hex digits for a valid ARGB color
    if (hex.length != 8) return null;
    final int? value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  /// Derive the current highlight selection from a screenTx token value.
  /// Non-empty trimmed value -> that value; empty / whitespace / null -> null.
  /// Pure; testable without SDUI globals.
  static String? selectionFromToken(dynamic rawTokenVal) {
    final String trimmed = (rawTokenVal ?? '').toString().trim();
    return trimmed.isNotEmpty ? trimmed : null;
  }

  /// Whether the adhoc row should render as selected.
  ///
  /// When [adhocValue] is empty (config sets no explicit value), the ad-hoc
  /// state IS "no vehicle captured" ([selected] == null). When [adhocValue]
  /// is non-empty, exact match. Pure; testable without SDUI globals.
  static bool isAdhocSelected({
    required String adhocValue,
    required String? selected,
  }) {
    if (adhocValue.isEmpty) return selected == null;
    return selected == adhocValue;
  }

  @override
  State<PickerList> createState() => _PickerListState();
}

class _PickerListState extends State<PickerList> {
  String _code = ''; // source-collection subscription code
  String _countCode = ''; // count-collection subscription code
  String _statusCode =
      ''; // status-table subscription code (separate from count)
  List<String> _textArray = [];

  /// Locally-tracked selection (the captured id). Re-derived from
  /// screenTx[captureToken] on every build so the highlight always reflects the
  /// current token -- cleared externally (customer switch) or set by tap.
  String? _selected;

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// `text` segments:
  ///  [0] list title        (reserved; the page usually has its own header)
  ///  [1] per-row select label ("Pilih")
  ///  [2] count badge suffix ("task aktif")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _titleField =>
      (widget.component['titleField'] ?? 'ln').toString().trim();
  String get _subField =>
      (widget.component['subField'] ?? '').toString().trim();
  String get _metaField =>
      (widget.component['metaField'] ?? '').toString().trim();
  String get _idField => PickerList.resolveIdField(widget.component);
  String get _captureToken => PickerList.resolveCaptureToken(widget.component);
  String get _mode =>
      (widget.component['mode'] ?? 'capture').toString().trim().toLowerCase();
  String get _adhocLabel =>
      (widget.component['adhocLabel'] ?? '').toString().trim();
  String get _adhocValue =>
      (widget.component['adhocValue'] ?? '').toString().trim();
  String get _emptyText {
    final String raw = (widget.component['emptyText'] ?? '').toString().trim();
    return raw.isNotEmpty ? raw : 'Tidak ada data';
  }

  String get _statusSearch =>
      (widget.component['statusSearch'] ?? '').toString().trim();
  String get _statusOnLabel =>
      (widget.component['statusOnLabel'] ?? '').toString().trim();
  String get _statusOffLabel =>
      (widget.component['statusOffLabel'] ?? '').toString().trim();
  String get _busySelfField =>
      (widget.component['busySelfField'] ?? '').toString().trim();
  String get _busySelfLabelField =>
      (widget.component['busySelfLabelField'] ?? '').toString().trim();
  bool get _disableWhenStatusOn {
    final String raw = (widget.component['disableWhenStatusOn'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return raw == 'true' || raw == '1';
  }

  String get _rowIcon => (widget.component['rowIcon'] ?? '').toString().trim();
  bool get _titleMono {
    final String raw = (widget.component['titleMono'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return raw == 'true' || raw == '1';
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
      }
    }

    final String rawCountTable = (widget.component['countTable'] ?? '')
        .toString()
        .trim();
    if (rawCountTable.isNotEmpty) {
      final TablePath cp = parseTablePath(rawCountTable);
      if (cp.tableDocId.isNotEmpty) {
        _countCode = '$appVid/${cp.tableDocId}/${cp.subColl}';
        subscribeToMapCollection(appVid, cp.tableDocId, cp.subColl, _countCode);
      }
    }

    // Status table subscription (optional, separate from countTable).
    // Gated on BOTH statusSearch (the intent switch) AND statusTable being
    // authored -- mirrors list_card.dart:223-238 (W2). No listener opened
    // when there is no consumer.
    // When absent: status counts against countTable pool (D4, no regression).
    if (_statusSearch.isNotEmpty) {
      final String rawStatusTable = (widget.component['statusTable'] ?? '')
          .toString()
          .trim();
      if (rawStatusTable.isNotEmpty) {
        final TablePath stp = parseTablePath(rawStatusTable);
        if (stp.tableDocId.isNotEmpty) {
          _statusCode = '$appVid/${stp.tableDocId}/${stp.subColl}';
          subscribeToMapCollection(
            appVid,
            stp.tableDocId,
            stp.subColl,
            _statusCode,
          );
        } else {
          devPrint(
            '[pickerList] statusTable "$rawStatusTable" unparseable '
            '-- status counts against countTable pool',
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> _rows() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    return PickerList.filterRows(docs, rawSearch);
  }

  /// Bind selection into screenTx; in navigate mode also push the route.
  /// Tap is a user gesture (not during build) so a direct dispatch is safe.
  ///
  /// [row] is the full doc map for collection rows. Null for adhoc rows.
  /// When [wizardKey] is configured, captures the selection into the wizard
  /// draft on EVERY pick -- including the adhoc row (no doc, so [vn] is empty).
  /// Overwriting unconditionally prevents a prior collection pick from
  /// lingering in the draft and being submitted in place of the latest
  /// selection (vehicle-side mirror of review C-1).
  void _select(String value, [Map<String, dynamic>? row]) {
    // LOAD-BEARING setState: build() re-derives _selected from
    // screenTx[captureToken], but the Obx observes mapTableContent (not
    // screenTx/redux) -- so this setState is the only thing that rebuilds the
    // row on tap. Do NOT drop it as "redundant"; the dispatch below is
    // synchronous so the rebuild reads the just-set token.
    setState(() => _selected = value);
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({_captureToken: value})),
    );

    // Draft-carry: capture display fields into wizard draft.
    final String wizardKey = (widget.component['wizardKey'] ?? '')
        .toString()
        .trim();
    if (wizardKey.isNotEmpty) {
      final String vn = row != null
          ? (row[_titleField] ?? '').toString().trim()
          : '';
      AdminCreateTaskSupport.setVehicle(wizardKey, vv: value, vn: vn);
      TaskItemBuilder.draftRev.value++;
    }

    if (_mode == 'navigate') {
      // routeParams: resolve from tapped row context + dispatch before nav.
      writeRouteParamsFromRow(
        widget.component['routeParams']?.toString(),
        row,
        widget.scrName,
      );
      final String route = stripRouteWrapper(
        (widget.component['route'] ?? '').toString().trim(),
      );
      if (route.isNotEmpty && routeExist(route)) {
        routeStack.push(route);
        gotoRoute(route);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Register dependencies on the subscribed collections.
      final List<Map<String, dynamic>> rows = _rows();
      final List<Map<String, dynamic>> countDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_countCode] ?? const [],
          );
      // Status pool: unconditional read so the observable is registered even
      // when the row list is empty and _rowTile never runs (D6 zero-obs).
      // During subscription warm-up this is empty -> count 0 -> row tappable
      // (fail-open by design, same as count badge warm-up; W4).
      final List<Map<String, dynamic>> statusDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_statusCode] ?? const [],
          );

      // Re-derive selection from screenTx on every build -- the token is the
      // single source of truth. Cached State + one-shot seed caused stale
      // highlights on page revisit when the token was cleared externally
      // (e.g. customer switch clearing vv on P1 while P3 State is cached).
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
      _selected = PickerList.selectionFromToken(screenTx[_captureToken]);

      final String adhocLabel = _adhocLabel;
      final bool showAdhoc = adhocLabel.isNotEmpty;

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty && !showAdhoc)
              _emptyState()
            else ...[
              for (final Map<String, dynamic> r in rows) ...[
                _rowTile(context, r, countDocs, statusDocs),
                const SizedBox(height: 8),
              ],
              if (showAdhoc) _adhocTile(context, adhocLabel),
            ],
          ],
        ),
      );
    });
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Text(
        _emptyText,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _rowTile(
    BuildContext context,
    Map<String, dynamic> r,
    List<Map<String, dynamic>> countDocs,
    List<Map<String, dynamic>> statusDocs,
  ) {
    final String id = (r[_idField] ?? '').toString().trim();
    final String title = (r[_titleField] ?? '').toString().trim();
    final String sub = _subField.isEmpty
        ? ''
        : (r[_subField] ?? '').toString().trim();
    // metaField configured -> always render a 3rd line; empty value -> placeholder.
    final String? meta = _metaField.isEmpty
        ? null
        : ((r[_metaField] ?? '').toString().trim().isEmpty
              ? '—'
              : (r[_metaField] ?? '').toString().trim());

    // Per-row count badge.
    String? badge;
    if (_countCode.isNotEmpty) {
      final String rawCountSearch = (widget.component['countSearch'] ?? '')
          .toString()
          .trim();
      final int n = PickerList.countForRow(
        countDocs,
        rawCountSearch,
        _idField,
        id,
      );
      final String suffix = _t(2);
      badge = suffix.isEmpty ? '$n' : '$n $suffix';
    }

    // Per-row status pill (only when statusSearch configured).
    String? statusLabel;
    bool statusIsOn = false;
    if (_statusSearch.isNotEmpty &&
        (_statusCode.isNotEmpty || _countCode.isNotEmpty)) {
      // statusTable configured -> its own pool; absent -> countTable pool (D4).
      final List<Map<String, dynamic>> pool = _statusCode.isNotEmpty
          ? statusDocs
          : countDocs;
      final int sn = PickerList.countForRow(pool, _statusSearch, _idField, id);
      statusIsOn = sn > 0;
      final String label = statusIsOn ? _statusOnLabel : _statusOffLabel;
      statusLabel = label.isNotEmpty ? label : null;
    }

    // Combined lock: busySelf OR status-lock (D3). The static owns the
    // row-field extraction so tests exercise the same code path (C1).
    final ({bool isBusy, String busyLabel}) lock = PickerList.deriveRowLock(
      row: r,
      busySelfField: _busySelfField,
      busySelfLabelField: _busySelfLabelField,
      busyPrefix: _t(3),
      statusOn: statusIsOn,
      statusOnLabel: _statusOnLabel,
      disableWhenStatusOn: _disableWhenStatusOn,
    );
    final bool isBusy = lock.isBusy;
    final String busyLabel = lock.busyLabel;

    return _selectableRow(
      title: title.isNotEmpty ? title : id,
      sub: sub,
      meta: meta,
      badge: badge,
      selected: _selected == id && id.isNotEmpty,
      onTap: (id.isEmpty || isBusy) ? null : () => _select(id, r),
      statusLabel: statusLabel,
      statusIsOn: statusIsOn,
      iconName: _rowIcon,
      mono: _titleMono,
      isBusy: isBusy,
      busyLabel: busyLabel,
    );
  }

  Widget _adhocTile(BuildContext context, String label) {
    return _selectableRow(
      title: label,
      sub: '',
      meta: null,
      badge: null,
      selected: PickerList.isAdhocSelected(
        adhocValue: _adhocValue,
        selected: _selected,
      ),
      onTap: () => _select(_adhocValue),
      leadingAdd: true,
      iconName: _rowIcon,
    );
  }

  Widget _selectableRow({
    required String title,
    required String sub,
    required String? meta,
    required String? badge,
    required bool selected,
    required VoidCallback? onTap,
    bool leadingAdd = false,
    String? statusLabel,
    bool statusIsOn = false,
    String iconName = '',
    bool mono = false,
    bool isBusy = false,
    String busyLabel = '',
  }) {
    final Color primary =
        PickerList.parseHexColor(
          (widget.component['accentColor'] ?? '').toString(),
        ) ??
        Theme.of(context).primaryColor;

    final bool isEntity = iconName.isNotEmpty;

    if (isEntity) {
      return _entityRow(
        title: title,
        sub: sub,
        badge: badge,
        selected: selected,
        onTap: onTap,
        leadingAdd: leadingAdd,
        statusLabel: statusLabel,
        statusIsOn: statusIsOn,
        iconName: iconName,
        mono: mono,
        primary: primary,
        isBusy: isBusy,
        busyLabel: busyLabel,
      );
    }

    // ── Non-entity (radio) layout -- byte-identical to pre-entity code ──
    final String rowBtnLabel = _t(1, 'Pilih');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : const Color(0xFFE2E8F0), // slate-200
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Generic leading affordance (no entity icon).
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                leadingAdd
                    ? Icons.add_circle_outline
                    : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                size: 20,
                color: selected
                    ? primary
                    : const Color(0xFF94A3B8), // slate-400
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: isBusy
                          ? const Color(0xFF9CA3AF) // gray-400
                          : const Color(0xFF1E293B), // slate-800
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: isBusy
                            ? const Color(0xFFD1D5DB) // gray-300
                            : const Color(0xFF64748B), // slate-500
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (meta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 11,
                        color: isBusy
                            ? const Color(0xFFD1D5DB)
                            : const Color(0xFF94A3B8), // slate-400
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isBusy && busyLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      busyLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444), // red-500
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (!isBusy &&
                      statusLabel != null &&
                      statusLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusIsOn
                            ? const Color(0xFFFEF3C7) // amber-100
                            : const Color(0xFFD1FAE5), // emerald-100
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusIsOn
                              ? const Color(0xFFB45309) // amber-700
                              : const Color(0xFF047857), // emerald-700
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Busy rows present no trailing affordance (mirror of entity layout
            // Task 7d): hide the count badge AND the "Pilih" label / check icon
            // so an inert (onTap:null) row never shows a "Pilih" cue.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isBusy && badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ),
                if (!isBusy && badge != null) const SizedBox(height: 4),
                if (!isBusy)
                  selected
                      ? Icon(Icons.check_circle, size: 18, color: primary)
                      : Text(
                          rowBtnLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8), // slate-400
                          ),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Entity-card layout: icon-avatar + mono title + sub + [pill + count] row.
  /// Extracted from [_selectableRow] for readability; only called when
  /// [iconName] is non-empty.
  Widget _entityRow({
    required String title,
    required String sub,
    required String? badge,
    required bool selected,
    required VoidCallback? onTap,
    required bool leadingAdd,
    required String? statusLabel,
    required bool statusIsOn,
    required String iconName,
    required bool mono,
    required Color primary,
    bool isBusy = false,
    String busyLabel = '',
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isBusy ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isBusy
                ? const Color(0xFFF9FAFB) // gray-50
                : (selected
                      ? const Color(0xFFEFF6FF) // adminAccentBg
                      : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isBusy
                  ? const Color(0xFFE5E7EB) // gray-200
                  : (selected ? primary : const Color(0xFFE2E8F0)),
              width: selected && !isBusy ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon avatar: 40x40, radius 10.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isBusy
                      ? const Color(0xFFF3F4F6) // gray-100
                      : (selected
                            ? primary
                            : const Color(0xFFF1F5F9)), // slate-100
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  leadingAdd ? Icons.add : panelIcon(iconName),
                  size: 20,
                  color: isBusy
                      ? const Color(0xFF9CA3AF) // gray-400
                      : (selected
                            ? Colors.white
                            : const Color(0xFF64748B)), // slate-500
                ),
              ),
              const SizedBox(width: 12),
              // Middle column: title, sub, [busy label OR pill + count].
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isBusy
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF1E293B), // slate-800
                        fontFamily: mono ? 'monospace' : null,
                        fontFamilyFallback: mono
                            ? const ['Menlo', 'Courier']
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 11,
                          color: isBusy
                              ? const Color(0xFFD1D5DB)
                              : const Color(0xFF64748B), // slate-500
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Busy label (distinct from status pill; takes priority).
                    if (isBusy && busyLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        busyLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444), // red-500
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Status pill + count (only when NOT busy).
                    if (!isBusy && hasStatusOrBadge(statusLabel, badge)) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (statusLabel != null && statusLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusIsOn
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusIsOn
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFF047857),
                                ),
                              ),
                            ),
                          if (statusLabel != null &&
                              statusLabel.isNotEmpty &&
                              badge != null)
                            const SizedBox(width: 8),
                          if (badge != null)
                            Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Trailing: check icon only when selected AND not busy.
              if (selected && !isBusy) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, size: 20, color: primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether the status-pill + count-meta row should render in entity mode.
/// Package-visible for testing; no widget dependency.
bool hasStatusOrBadge(String? statusLabel, String? badge) {
  if (badge != null) return true;
  if (statusLabel != null && statusLabel.isNotEmpty) return true;
  return false;
}
