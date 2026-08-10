import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'item_card_detail.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

/// WORKER_CARD_DETAIL · variant:"keyed" — read-only fact card for ONE worker.
/// Reads the keyed `workforce` doc whose `vid` matches `` `<vid>` `` from screenTx
/// (set by the worker-list tap). `text` layout (diamond-separated):
///   [0]=`<n>`  [1]=`<is>`  [2]=`<os>`  [3]=role label  [4]=Masuk label  [5]=Keluar label
class WorkerCardDetailKeyed extends StatefulWidget {
  const WorkerCardDetailKeyed({
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
  State<WorkerCardDetailKeyed> createState() => _WorkerCardDetailKeyedState();
}

class _WorkerCardDetailKeyedState extends State<WorkerCardDetailKeyed> {
  String _code = '';
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    // Register ItemCardDetail's ScreenSession entries: this widget publishes
    // ItemCardDetail.currentRow (in build), so a screen that renders only this
    // card — never ItemCardDetail itself — must still register so navReset
    // clears currentRow on route change (the old approver_sticky_bar reach-in
    // did this unconditionally before Phase 2).
    ItemCardDetail.registerScreenSession();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '')
        .toString()
        .trim();
    debugPrint(
      '[WorkerCardDetailKeyed._subscribe] rawTable="$rawTable" '
      'vidtable="$appVid" tableDocId="${tp.tableDocId}" subColl="${tp.subColl}"',
    );
    // `table` is mandatory — it determines the mapTableContent code we read.
    if (tp.tableDocId.isEmpty) return;
    // vid-scoped: without vid, another tenant's same tableDocId/subColl dedups
    // our stream away (mapTableContent/_mapSubscribed key omits vid).
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    // `vidtable` only needed to open our OWN subscription. If absent, fall back
    // to whatever a sibling (e.g. the worker list) already loaded under _code.
    if (appVid.isEmpty) return;
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  /// Resolve `<key>` markers from screenTx so `vid◼<vid>` becomes `vid◼<value>`
  /// before the char-code equality filter runs.
  String _resolveNamedMarkers(String text) {
    return text.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
      final v = _screenTx[m.group(1)!];
      return v == null ? m.group(0)! : v.toString();
    });
  }

  String _at(int i, Map<String, dynamic> doc) => _textArray.length > i
      ? resolveMapTokens(_textArray[i], doc, const {})
      : '';

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _factTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A93A6)),
            ),
            const SizedBox(height: 4),
            Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2233),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_code] ?? const [],
      );
      final String condRaw =
          (widget.component['conditions'] ?? widget.component['search'] ?? '')
              .toString();
      String cond = autheniumDecode(condRaw) ?? condRaw;
      cond = _resolveNamedMarkers(cond);
      final List<Map<String, dynamic>> matched = filterByCharCodeEquality(
        docs,
        cond,
        _screenTx,
      );
      debugPrint(
        '[WorkerCardDetailKeyed] code=$_code docs=${docs.length} '
        'firstDocKeys=${docs.isNotEmpty ? docs.first.keys.toList() : const []} '
        'screenTxVid="${_screenTx['vid']}" rawCond="$condRaw" '
        'resolvedCond="$cond" matched=${matched.length}',
      );
      if (matched.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ItemCardDetail.currentRow.value = const [],
        );
        return const SizedBox.shrink();
      }
      final Map<String, dynamic> doc = matched.first;

      final String name = _at(0, doc);
      final String isVal = _at(1, doc);
      final String osVal = _at(2, doc);
      // Publish a positional row so the incident sticky bar renders:
      // _buildIncident (approver_sticky_bar.dart) returns SizedBox.shrink() while
      // ItemCardDetail.currentRow is empty. Layout: [0]=<n> [1]=<is> [2]=<os>
      // [3]=vid [4]=sv. Post-frame to avoid setState-during-build (mirrors
      // ItemCardDetail's own pattern).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ItemCardDetail.currentRow.value = <dynamic>[
          name,
          isVal,
          osVal,
          (doc['vid'] ?? '').toString(),
          (doc['sv'] ?? '').toString(),
        ];
      });
      final String roleLabel = _textArray.length > 3 ? _textArray[3] : '';
      final String masukLabel = _textArray.length > 4 ? _textArray[4] : 'Masuk';
      final String keluarLabel = _textArray.length > 5
          ? _textArray[5]
          : 'Keluar';

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE0E7FF),
                    child: Text(
                      _getInitials(name),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        if (roleLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            roleLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _factTile(masukLabel, isVal),
                    const SizedBox(width: 12),
                    _factTile(keluarLabel, osVal),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
