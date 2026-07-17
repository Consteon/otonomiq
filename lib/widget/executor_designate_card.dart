import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'custody_count_list.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// EXECUTOR_DESIGNATE_CARD -- O1 driver picker card (SDUI component).
///
/// Two visual states:
/// - UNSET: amber card, "?" avatar, "Belum ditentukan" + "Tentukan" button.
/// - SET: teal card, initial avatar, driver name + "Ganti" button.
///
/// Tapping the button opens a bottom-sheet workforce picker. Pick writes
/// #CHOSEN_DRIVER_VID + #CHOSEN_DRIVER_NAME to screenTx and bumps [chosenRev].
/// CustodyCountSubmit O1 variant Obx-reads chosenRev for the enable gate.
///
/// Workforce subscription: reuses getTableVid(component['com']) routing (via
/// [resolveAppVid]) + subscribeToMapCollection (same pattern as scanner.dart /
/// otq_txf_2.dart searchtable variant).
///
/// Read-only for Firestore: no txfController, no saveSend, no history.
class ExecutorDesignateCard extends StatefulWidget {
  const ExecutorDesignateCard({
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

  // ── Cross-widget reactivity ───────────────────────────────────────────────

  /// Revision signal bumped on pick/clear. CustodyCountSubmit Obx-reads this
  /// to gate the enable state. Plain RxInt -- NOT an RxMap (no mutate-in-build).
  static final RxInt chosenRev = 0.obs;

  /// Clear ALL O1 state for a screen. Called from clearData (api.dart)
  /// on route change. Covers: #CHOSEN_DRIVER_VID, #CHOSEN_DRIVER_NAME,
  /// #ACTIVE_WAREHOUSE, plus the warehouse-published flag on count-list.
  static void clearO1State(String scrName) {
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#CHOSEN_DRIVER_VID': '',
          '#CHOSEN_DRIVER_NAME': '',
          '#ACTIVE_WAREHOUSE': '',
        }),
      ),
    );
    chosenRev.value++;
    // Reset the warehouse-published flag so reopen re-reads gl
    CustodyCountList.resetWarehousePublished(scrName);
  }

  /// Filter workforce docs: apply an optional server search (via
  /// filterDriverHomeDocs) then drop any doc whose resolved VID is empty.
  ///
  /// Pure function (no Flutter/Obx deps), directly testable. This is the
  /// SINGLE source of truth for the picker list filtering -- `_getWorkforceDocs`
  /// delegates to it.
  ///
  /// [docs] -- raw workforce docs from mapTableContent.
  /// [rawWorkforceSearch] -- raw `component['workforceSearch']` value. Empty
  ///   string = no server filter (filterDriverHomeDocs returns docs unchanged).
  ///   Server-encoded (_25FC_/_2B58_) values are decoded internally by
  ///   filterDriverHomeDocs -- the caller does NOT need to autheniumDecode.
  /// [scrName] -- screen name for curly-token resolution in filterDriverHomeDocs.
  /// [vidField] -- workforce doc field for the driver VID (default 'VID').
  ///
  /// Returns a new list containing only docs that (a) match the server search
  /// AND (b) have a non-empty VID. Order is preserved.
  static List<Map<String, dynamic>> filterWorkforceDocs(
    List<Map<String, dynamic>> docs,
    String rawWorkforceSearch,
    String scrName, {
    String vidField = 'VID',
  }) {
    // Layer 1: server search filter (empty search = pass-through)
    final List<Map<String, dynamic>> searched = filterDriverHomeDocs(
      docs,
      rawWorkforceSearch,
      scrName,
    );
    // Layer 2: drop docs with empty VID (meta/tenant rows)
    return searched
        .where((doc) => (doc[vidField] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  /// Build a busy-set from a collection of docs (e.g. stock_location).
  ///
  /// For each row where [busyField] is non-empty (trimmed), map
  /// `row[busyField] -> row[busyLabelField]`. The key is the bound entity's
  /// vid (a driver's vid in the O1 case); the value is the display label
  /// (vehicle plate).
  ///
  /// Pure function (no Flutter deps), directly testable. Mirrors the
  /// [filterWorkforceDocs] pattern.
  static Map<String, String> buildBusySet(
    List<Map<String, dynamic>> docs,
    String busyField,
    String busyLabelField,
  ) {
    final Map<String, String> result = <String, String>{};
    for (final Map<String, dynamic> doc in docs) {
      final String key = (doc[busyField] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final String label = (doc[busyLabelField] ?? '').toString().trim();
      result[key] = label;
    }
    return result;
  }

  @override
  State<ExecutorDesignateCard> createState() => _ExecutorDesignateCardState();
}

class _ExecutorDesignateCardState extends State<ExecutorDesignateCard> {
  String _workforceCode = '';
  String _busyCode = '';
  List<String> _textArray = [];

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

  /// text slot accessors:
  ///  [0] section label    (e.g. "PENGEMUDI")
  ///  [1] unset message    (e.g. "Belum ditentukan -- pilih sebelum berangkat")
  ///  [2] unset button     (e.g. "Tentukan")
  ///  [3] set button       (e.g. "Ganti")
  ///  [4] picker title     (e.g. "TENTUKAN PENGEMUDI")
  ///  [5] picker subtitle  (e.g. "Siapa yang ngantar?")
  ///  [6] picker helper    (e.g. "Pilih dari daftar pegawai")
  ///  [7] picker empty     (e.g. "Tidak ada pegawai tersedia")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Workforce subscription (existing).
    // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
    final String rawTable = (widget.component['workforceTable'] ?? '')
        .toString()
        .trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        _workforceCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
          appVid,
          tp.tableDocId,
          tp.subColl,
          _workforceCode,
        );
      }
    }

    // Busy-table subscription (cross-table busy guard).
    final String rawBusyTable = (widget.component['busyTable'] ?? '')
        .toString()
        .trim();
    if (rawBusyTable.isNotEmpty) {
      final TablePath bp = parseTablePath(rawBusyTable);
      if (bp.tableDocId.isNotEmpty) {
        _busyCode = '$appVid/${bp.tableDocId}/${bp.subColl}';
        subscribeToMapCollection(appVid, bp.tableDocId, bp.subColl, _busyCode);
      }
    }
  }

  List<Map<String, dynamic>> _getWorkforceDocs() {
    if (_workforceCode.isEmpty) return const [];
    final List<Map<String, dynamic>> raw = List<Map<String, dynamic>>.from(
      mapTableContent[_workforceCode] ?? const [],
    );
    final String rawSearch = (widget.component['workforceSearch'] ?? '')
        .toString()
        .trim();
    final String vidField = (widget.component['vidField'] ?? 'VID').toString();
    return ExecutorDesignateCard.filterWorkforceDocs(
      raw,
      rawSearch,
      widget.scrName,
      vidField: vidField,
    );
  }

  void _onPick(String vid, String name) {
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#CHOSEN_DRIVER_VID': vid,
          '#CHOSEN_DRIVER_NAME': name,
        }),
      ),
    );
    ExecutorDesignateCard.chosenRev.value++;
  }

  void _showPicker(BuildContext context) {
    final List<Map<String, dynamic>> docs = _getWorkforceDocs();
    final String nameField = (widget.component['nameField'] ?? 'n').toString();
    final String vidField = (widget.component['vidField'] ?? 'VID').toString();
    final String siteField = (widget.component['siteField'] ?? '').toString();

    // Build busy-set from cross-table subscription (S1 busy guard).
    final String busyField = (widget.component['busyField'] ?? '')
        .toString()
        .trim();
    final String busyLabelField = (widget.component['busyLabelField'] ?? '')
        .toString()
        .trim();
    final Map<String, String> busySet;
    if (_busyCode.isNotEmpty && busyField.isNotEmpty) {
      final List<Map<String, dynamic>> busyDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_busyCode] ?? const [],
          );
      busySet = ExecutorDesignateCard.buildBusySet(
        busyDocs,
        busyField,
        busyLabelField,
      );
    } else {
      busySet = const <String, String>{};
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExecutorPickerSheet(
        docs: docs,
        nameField: nameField,
        vidField: vidField,
        siteField: siteField,
        title: _t(4, 'TENTUKAN PENGEMUDI'),
        subtitle: _t(5, 'Siapa yang ngantar?'),
        helper: _t(6, 'Pilih dari daftar pegawai'),
        emptyMessage: _t(7, 'Tidak ada pegawai tersedia'),
        busySet: busySet,
        busyPrefix: _t(8),
        onSelect: (String vid, String name) {
          _onPick(vid, name);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      ExecutorDesignateCard.chosenRev.value;

      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
      final String chosenVid = (screenTx['#CHOSEN_DRIVER_VID'] ?? '')
          .toString()
          .trim();
      final String chosenName = (screenTx['#CHOSEN_DRIVER_NAME'] ?? '')
          .toString()
          .trim();
      final bool isSet = chosenVid.isNotEmpty;

      final String sectionLabel = _t(0, 'PENGEMUDI');

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: isSet
            ? _buildSetCard(context, sectionLabel, chosenName)
            : _buildUnsetCard(context, sectionLabel),
      );
    });
  }

  Widget _buildUnsetCard(BuildContext context, String label) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFFBBF24),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text(
              '?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _t(1, 'Belum ditentukan \u{2014} pilih sebelum berangkat'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => _showPicker(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  _t(2, 'Tentukan'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetCard(BuildContext context, String label, String name) {
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFF14B8A6),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              height: 44,
              child: TextButton(
                onPressed: () => _showPicker(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  _t(3, 'Ganti'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom-sheet picker ────────────────────────────────────────────────────

/// Workforce picker bottom sheet. Lists workforce docs (each: circular initial
/// avatar + name + optional site). Tap a row -> [onSelect](vid, name).
class _ExecutorPickerSheet extends StatelessWidget {
  const _ExecutorPickerSheet({
    required this.docs,
    required this.nameField,
    required this.vidField,
    required this.siteField,
    required this.title,
    required this.subtitle,
    required this.helper,
    required this.emptyMessage,
    required this.onSelect,
    this.busySet = const <String, String>{},
    this.busyPrefix = '',
  });

  final List<Map<String, dynamic>> docs;
  final String nameField;
  final String vidField;
  final String siteField;
  final String title;
  final String subtitle;
  final String helper;
  final String emptyMessage;
  final void Function(String vid, String name) onSelect;

  /// Map of driver-vid -> vehicle label for busy drivers. Empty = no guard.
  final Map<String, String> busySet;

  /// Prefix for the busy subtitle (from text segment, e.g. "Sedang jalan · ").
  final String busyPrefix;

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.7;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (helper.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      helper,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            // List or empty state
            Flexible(
              child: docs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 40,
                      ),
                      child: Center(
                        child: Text(
                          emptyMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: docs.length,
                      separatorBuilder: (ctx, i) => const Divider(
                        height: 1,
                        indent: 68,
                        color: Color(0xFFF3F4F6),
                      ),
                      itemBuilder: (ctx, i) => _buildRow(docs[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> doc) {
    final String name = (doc[nameField] ?? '').toString().trim();
    final String vid = (doc[vidField] ?? '').toString().trim();
    final String site = siteField.isNotEmpty
        ? (doc[siteField] ?? '').toString().trim()
        : '';
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    // Busy guard: driver vid is in the busy-set AND vid is non-empty.
    final bool isBusy = vid.isNotEmpty && busySet.containsKey(vid);
    final String busyLabel = isBusy ? '$busyPrefix${busySet[vid] ?? ''}' : '';

    return InkWell(
      // Combine existing vid-empty guard with busy guard.
      onTap: (vid.isEmpty || isBusy) ? null : () => onSelect(vid, name),
      child: Opacity(
        opacity: isBusy ? 0.45 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isBusy
                      ? const Color(0xFFF3F4F6) // gray-100
                      : const Color(0xFFE0F2F1),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isBusy
                        ? const Color(0xFF9CA3AF) // gray-400
                        : const Color(0xFF0F766E),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isNotEmpty ? name : vid,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isBusy
                            ? const Color(0xFF9CA3AF) // gray-400
                            : const Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Busy subtitle takes priority over site subtitle.
                    if (isBusy && busyLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        busyLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFEF4444), // red-500
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (site.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        site,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!isBusy)
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFFD1D5DB),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
