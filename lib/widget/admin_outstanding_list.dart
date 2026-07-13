import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'admin_home_support.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ADMIN_OUTSTANDING_LIST -- "PRIORITAS PENGAMBILAN" collapsible card for Admin H1.
///
/// Shows client-grouped outstanding items (asset_cache lt=client) with aging-tier
/// badges and a "Jadwalkan" button (DEFERRED: shows snackbar).
///
/// Collapsible (default expanded). Each row: tier badge + client name + item/qty
/// summary + aging + outline-blue "Jadwalkan".
///
/// Read-only. Empty -> renders panel chrome + config-driven emptyText (spec
/// section 5.3). CF-gated (emptyText shows until asset_cache seeded).
class AdminOutstandingList extends StatefulWidget {
  const AdminOutstandingList({
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
  State<AdminOutstandingList> createState() => _AdminOutstandingListState();
}

class _AdminOutstandingListState extends State<AdminOutstandingList>
    with SingleTickerProviderStateMixin {
  List<String> _textArray = [];
  String _acCode = '';
  String _slCode = '';
  bool _expanded = true;
  String _titleField = 'lv';
  String _itemField = 'ii';
  String _qtyField = 'qt';
  String _ageAnchorField = 't';
  String _locationNameField = 'ln';
  int? _dangerDays;
  int? _warnDays;
  late AnimationController _chevronController;
  late Animation<double> _chevronTurns;
  // Config-driven empty-state text (spec section 5.3: panel always visible)
  String _emptyText = 'Tidak ada outstanding \u{00B7} semua sudah tertagih';

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _chevronTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _chevronController, curve: Curves.easeInOut),
    );
    _parseText();
    _parseConfig();
    _subscribe();
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _parseConfig() {
    final String tf = (widget.component['titleField'] ?? '').toString().trim();
    if (tf.isNotEmpty) _titleField = tf;
    final String itf = (widget.component['itemField'] ?? '').toString().trim();
    if (itf.isNotEmpty) _itemField = itf;
    final String qf = (widget.component['qtyField'] ?? '').toString().trim();
    if (qf.isNotEmpty) _qtyField = qf;
    final String af = (widget.component['ageAnchorField'] ?? '')
        .toString()
        .trim();
    if (af.isNotEmpty) _ageAnchorField = af;
    final String lnf = (widget.component['locationNameField'] ?? '')
        .toString()
        .trim();
    if (lnf.isNotEmpty) _locationNameField = lnf;
    final dynamic rawDanger = widget.component['dangerAge'];
    if (rawDanger != null) {
      final int d = int.tryParse(rawDanger.toString().trim()) ?? 0;
      if (d > 0) _dangerDays = d;
    }
    final dynamic rawWarn = widget.component['warnAge'];
    if (rawWarn != null) {
      final int w = int.tryParse(rawWarn.toString().trim()) ?? 0;
      if (w > 0) _warnDays = w;
    }
    final String et = (widget.component['emptyText'] ?? '').toString().trim();
    if (et.isNotEmpty) _emptyText = et;
  }

  /// Text slot accessors:
  ///  [0] section header (default "PRIORITAS PENGAMBILAN")
  ///  [1] schedule button label (default "Jadwalkan")
  ///  [2] kritis badge label (default "KRITIS")
  ///  [3] perhatian badge label (default "PERHATIAN")
  ///  [4] normal badge label (default "NORMAL")
  ///  [5] deferred snackbar message (default "Fitur ini sedang dikembangkan")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Asset_cache
    final String rawAcTable = (widget.component['assetTable'] ?? '')
        .toString()
        .trim();
    if (rawAcTable.isNotEmpty) {
      final TablePath acp = parseTablePath(rawAcTable);
      if (acp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _acCode = '$appVid/${acp.tableDocId}/${acp.subColl}';
        subscribeToMapCollection(appVid, acp.tableDocId, acp.subColl, _acCode);
      }
    }

    // Stock_location (client name lookup)
    final String rawSlTable = (widget.component['clientTable'] ?? '')
        .toString()
        .trim();
    if (rawSlTable.isNotEmpty) {
      final TablePath slp = parseTablePath(rawSlTable);
      if (slp.tableDocId.isNotEmpty) {
        _slCode = '$appVid/${slp.tableDocId}/${slp.subColl}';
        subscribeToMapCollection(appVid, slp.tableDocId, slp.subColl, _slCode);
      }
    }
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _chevronController.reverse();
      } else {
        _chevronController.forward();
      }
    });
  }

  void _onScheduleTap() {
    // DEFERRED: "Jadwalkan" shows a snackbar until the schedule wizard ships.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(5, 'Fitur ini sedang dikembangkan')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> assetCacheDocs =
          List<Map<String, dynamic>>.from(mapTableContent[_acCode] ?? const []);
      final List<Map<String, dynamic>> stockLocations =
          List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);

      final List<OutstandingGroup> groups = groupOutstanding(
        assetCacheDocs: assetCacheDocs,
        stockLocations: stockLocations,
        lvField: _titleField,
        iiField: _itemField,
        qtField: _qtyField,
        tField: _ageAnchorField,
        lnField: _locationNameField,
        dangerDays: _dangerDays,
        warnDays: _warnDays,
      );

      // Labels (sectionHeader always needed for panel chrome)
      final String sectionHeader = _t(0, 'PRIORITAS PENGAMBILAN');
      final String scheduleLabel = _t(1, 'Jadwalkan');

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminTierColors.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: title + chevron (always visible -- spec section 5.3)
              GestureDetector(
                onTap: _toggleExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sectionHeader.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AdminTierColors.sectionCaps,
                          ),
                        ),
                      ),
                      RotationTransition(
                        turns: _chevronTurns,
                        child: const Icon(
                          Icons.expand_more,
                          size: 20,
                          color: AdminTierColors.subText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Body (expanded)
              if (_expanded) ...[
                if (groups.isEmpty)
                  // Empty state (spec section 5.3: panel still visible, never hide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _emptyText,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AdminTierColors.subText,
                        ),
                      ),
                    ),
                  )
                else ...[
                  for (int i = 0; i < groups.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 14, endIndent: 14),
                    _buildRow(context, groups[i], scheduleLabel),
                  ],
                ],
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildRow(
    BuildContext context,
    OutstandingGroup group,
    String scheduleLabel,
  ) {
    // Tier badge colors
    final (Color badgeBg, Color badgeFg) = AdminTierColors.outstandingBadge(
      group.tier,
    );
    String badgeLabel;
    switch (group.tier) {
      case 'kritis':
        badgeLabel = _t(2, 'KRITIS');
        break;
      case 'perhatian':
        badgeLabel = _t(3, 'PERHATIAN');
        break;
      default:
        badgeLabel = _t(4, 'NORMAL');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeFg,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Content: client name + summary
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.clientName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminTierColors.titleText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  group.itemSummary,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AdminTierColors.subText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Jadwalkan button
          GestureDetector(
            onTap: _onScheduleTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: AdminTierColors.okAction),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                scheduleLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AdminTierColors.okAction,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
