import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../screen_session.dart';
import 'admin_home_support.dart';
import 'customer_outstanding_list.dart'; // ChipAccent
import 'driver_home_support.dart';
import 'panel_card_support.dart';

// ---- Public aggregation result (testable) ---------------------------------

/// Result of [groupAssetStock]: sorted entity list + summary scope totals.
class AssetStockResult {
  final List<AssetEntity> entities;

  /// Keyed by scope: `all`, `<pivotVal>`, `<pivotVal>.<condVal>`.
  final Map<String, int> summaryValues;
  const AssetStockResult({required this.entities, required this.summaryValues});
}

/// One entity (item) in the stock distribution. Public for test assertions.
class AssetEntity {
  final String id;
  final String name;
  final String category;
  final int total;

  /// Keyed by pivotValue string (e.g. 'warehouse', 'vehicle').
  final Map<String, PivotCell> pivots;
  const AssetEntity({
    required this.id,
    required this.name,
    required this.category,
    required this.total,
    required this.pivots,
  });
}

/// One pivot dimension for an entity. Public for test assertions.
class PivotCell {
  final String value;
  final int total;

  /// Keyed by condValue string (e.g. 'full', 'empty').
  final Map<String, int> condTotals;

  /// Per-detail breakdown (e.g. per vehicle/customer). Empty when detailField
  /// is unset. Sorted total desc, id asc.
  final List<DetailRow> details;
  const PivotCell({
    required this.value,
    required this.total,
    required this.condTotals,
    this.details = const <DetailRow>[],
  });
}

/// One detail row within a pivot cell (e.g. a specific vehicle or customer).
/// Public for test assertions.
class DetailRow {
  final String id;
  final String name;
  final String sub;
  final int total;

  /// Keyed by condValue string (e.g. 'full', 'empty').
  final Map<String, int> condTotals;
  const DetailRow({
    required this.id,
    required this.name,
    this.sub = '',
    required this.total,
    required this.condTotals,
  });
}

// ---- Pure aggregation function --------------------------------------------

/// Group asset_cache docs into entity x pivot x cond cube. Join item names.
///
/// Pure -- no Flutter/Obx deps, directly testable. The widget calls this;
/// it does not re-implement the logic.
///
/// Convention #7: all inputs originate from firestoreDb (dynamic); field reads
/// use `.toString().trim()` and `_safeInt`. Returns explicitly typed
/// collections (never `.map().toList()` into a typed store).
AssetStockResult groupAssetStock({
  required List<Map<String, dynamic>> cacheDocs,
  List<Map<String, dynamic>> itemDocs = const [],
  bool hideZero = true,
  String groupField = 'ii',
  String valueField = 'qt',
  String pivotField = 'lt',
  String condField = 'cd',
  String itemKey = 'ii',
  String nameField = 'in',
  String catField = 'ic',
  required List<String> pivotOrder,
  required List<String> condOrder,
  String detailField = '',
  String detailNameField = '',
  String detailSubField = '',
}) {
  // -- Build item join maps -------------------------------------------------

  final Map<String, String> itemNameMap = <String, String>{};
  final Map<String, String> itemCatMap = <String, String>{};
  for (final Map<String, dynamic> doc in itemDocs) {
    final String key = (doc[itemKey] ?? '').toString().trim();
    if (key.isEmpty) continue;
    itemNameMap[key] = (doc[nameField] ?? '').toString().trim();
    itemCatMap[key] = (doc[catField] ?? '').toString().trim();
  }

  // -- Accumulate: entity -> pivot -> cond -> sum(qty) ----------------------

  // grouped[entityId][pivotVal][condVal] = sumQty
  final Map<String, Map<String, Map<String, int>>> grouped =
      <String, Map<String, Map<String, int>>>{};

  // Summary scopes: 'all', '<pivot>', '<pivot>.<cond>'
  final Map<String, int> summary = <String, int>{};
  summary['all'] = 0;

  // Detail grouping: [entityId][pivotVal][detailVal][condVal] = sumQty
  final Map<String, Map<String, Map<String, Map<String, int>>>> detailGrouped =
      <String, Map<String, Map<String, Map<String, int>>>>{};
  final Map<String, String> detailNames = <String, String>{};
  final Map<String, String> detailSubs = <String, String>{};

  for (final Map<String, dynamic> doc in cacheDocs) {
    final String entityId = (doc[groupField] ?? '').toString().trim();
    if (entityId.isEmpty) continue;

    final String pivotVal = (doc[pivotField] ?? '').toString().trim();
    final String condVal = (doc[condField] ?? '').toString().trim();
    final int qty = _safeInt(doc[valueField]);

    // Entity -> pivot -> cond bucket
    final Map<String, Map<String, int>> entityBucket = grouped.putIfAbsent(
      entityId,
      () => <String, Map<String, int>>{},
    );
    final Map<String, int> pivotBucket = entityBucket.putIfAbsent(
      pivotVal,
      () => <String, int>{},
    );
    pivotBucket[condVal] = (pivotBucket[condVal] ?? 0) + qty;

    // Summary accumulators (gross -- not affected by hideZero)
    summary['all'] = (summary['all'] ?? 0) + qty;
    if (pivotVal.isNotEmpty) {
      summary[pivotVal] = (summary[pivotVal] ?? 0) + qty;
      if (condVal.isNotEmpty) {
        final String scopeKey = '$pivotVal.$condVal';
        summary[scopeKey] = (summary[scopeKey] ?? 0) + qty;
      }
    }

    // Detail accumulation (per detailField value)
    if (detailField.isNotEmpty) {
      final String detailVal = (doc[detailField] ?? '').toString().trim();
      if (detailVal.isNotEmpty) {
        final Map<String, Map<String, Map<String, int>>> entityDetail =
            detailGrouped.putIfAbsent(
              entityId,
              () => <String, Map<String, Map<String, int>>>{},
            );
        final Map<String, Map<String, int>> pivotDetail = entityDetail
            .putIfAbsent(pivotVal, () => <String, Map<String, int>>{});
        final Map<String, int> detailBucket = pivotDetail.putIfAbsent(
          detailVal,
          () => <String, int>{},
        );
        detailBucket[condVal] = (detailBucket[condVal] ?? 0) + qty;

        // Name resolution: first non-empty wins
        if (detailNameField.isNotEmpty && !detailNames.containsKey(detailVal)) {
          final String dName = (doc[detailNameField] ?? '').toString().trim();
          if (dName.isNotEmpty) {
            detailNames[detailVal] = dName;
          }
        }

        // Sub resolution: first non-empty wins (same pattern as name)
        if (detailSubField.isNotEmpty && !detailSubs.containsKey(detailVal)) {
          final String dSub = (doc[detailSubField] ?? '').toString().trim();
          if (dSub.isNotEmpty) {
            detailSubs[detailVal] = dSub;
          }
        }
      }
    }
  }

  // -- Build AssetEntity list -----------------------------------------------

  final List<AssetEntity> entities = <AssetEntity>[];

  for (final MapEntry<String, Map<String, Map<String, int>>> entry
      in grouped.entries) {
    final String entityId = entry.key;
    final Map<String, Map<String, int>> pivotMap = entry.value;

    final Map<String, PivotCell> pivotCells = <String, PivotCell>{};
    int entityTotal = 0;

    for (final String pv in pivotOrder) {
      final Map<String, int> condMap = pivotMap[pv] ?? const <String, int>{};

      // Build condTotals for known condOrder values
      final Map<String, int> condTotals = <String, int>{};
      int pivotTotal = 0;
      for (final String cv in condOrder) {
        final int val = condMap[cv] ?? 0;
        condTotals[cv] = val;
        pivotTotal += val;
      }
      // Also sum any cond values NOT in condOrder (e.g. empty condField '')
      for (final MapEntry<String, int> ce in condMap.entries) {
        if (!condOrder.contains(ce.key)) {
          pivotTotal += ce.value;
        }
      }

      if (hideZero && pivotTotal == 0) continue;

      // Build detail rows (per detailField) when set
      List<DetailRow> details = const <DetailRow>[];
      if (detailField.isNotEmpty) {
        final Map<String, Map<String, int>>? pivotDetailMap =
            detailGrouped[entityId]?[pv];
        if (pivotDetailMap != null && pivotDetailMap.isNotEmpty) {
          final List<DetailRow> detailList = <DetailRow>[];
          for (final MapEntry<String, Map<String, int>> de
              in pivotDetailMap.entries) {
            final String detailId = de.key;
            final Map<String, int> dCondMap = de.value;
            final Map<String, int> dCondTotals = <String, int>{};
            int dTotal = 0;
            for (final String cv in condOrder) {
              final int val = dCondMap[cv] ?? 0;
              dCondTotals[cv] = val;
              dTotal += val;
            }
            // Sum cond values not in condOrder (e.g. empty condField '')
            for (final MapEntry<String, int> ce in dCondMap.entries) {
              if (!condOrder.contains(ce.key)) dTotal += ce.value;
            }
            if (hideZero && dTotal == 0) continue;
            final String resolvedName =
                detailNames[detailId]?.isNotEmpty == true
                ? detailNames[detailId]!
                : detailId;
            detailList.add(
              DetailRow(
                id: detailId,
                name: resolvedName,
                sub: detailSubs[detailId] ?? '',
                total: dTotal,
                condTotals: dCondTotals,
              ),
            );
          }
          // Sort: total desc, tie-break id asc (match entity sort)
          detailList.sort((DetailRow a, DetailRow b) {
            final int cmp = b.total.compareTo(a.total);
            return cmp != 0 ? cmp : a.id.compareTo(b.id);
          });
          details = detailList;
        }
      }

      pivotCells[pv] = PivotCell(
        value: pv,
        total: pivotTotal,
        condTotals: condTotals,
        details: details,
      );
      entityTotal += pivotTotal;
    }

    // Also include docs whose pivotVal is not in pivotOrder (sum into entity
    // total but don't create a PivotCell -- matches hideZero spirit).
    for (final MapEntry<String, Map<String, int>> pe in pivotMap.entries) {
      if (!pivotOrder.contains(pe.key)) {
        int extraTotal = 0;
        for (final int v in pe.value.values) {
          extraTotal += v;
        }
        entityTotal += extraTotal;
      }
    }

    if (hideZero && entityTotal == 0) continue;

    final String resolvedName = itemNameMap[entityId]?.isNotEmpty == true
        ? itemNameMap[entityId]!
        : entityId;
    final String resolvedCat = itemCatMap[entityId] ?? '';

    entities.add(
      AssetEntity(
        id: entityId,
        name: resolvedName,
        category: resolvedCat,
        total: entityTotal,
        pivots: pivotCells,
      ),
    );
  }

  // Sort by total desc, tie-break by id asc (stable)
  entities.sort((AssetEntity a, AssetEntity b) {
    final int cmp = b.total.compareTo(a.total);
    return cmp != 0 ? cmp : a.id.compareTo(b.id);
  });

  return AssetStockResult(entities: entities, summaryValues: summary);
}

/// Safely coerce a dynamic value to int. Returns 0 on null, empty, or
/// non-parseable input. Copied from customer_outstanding_list.dart (private
/// there); Convention #7 -- firestoreDb fields are dynamic.
int _safeInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

// ---- Widget ---------------------------------------------------------------

/// ASSET_STOCK_LIST -- generic pivot-cube stock distribution widget.
///
/// Summary strip + filter tabs + per-entity cards with proportion bar and
/// pivot breakdown. Display-only: no txfController, no saveSend, no history.
class AssetStockList extends StatefulWidget {
  const AssetStockList({
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

  /// Per-screen active filter tab index, keyed by scrName (convention:
  /// screen-specific shared state as static Map, not global.dart).
  static final Map<String, int> _activeTab = <String, int>{};

  static void registerScreenSession() {
    ScreenSession.ensure(
      'AssetStockList.activeTab',
      AssetStockList.clearState,
      nav: NavPolicy.none,
    );
  }

  /// Called from buildPage in ui_component.dart on route change to release
  /// per-screen state. Mirrors CustomerOutstandingList.clearState.
  static void clearState(String scrName) {
    _activeTab.remove(scrName);
  }

  @override
  State<AssetStockList> createState() => _AssetStockListState();
}

class _AssetStockListState extends State<AssetStockList> {
  List<String> _textArray = [];
  String _acCode = ''; // asset_cache subscription
  String _itemCode = ''; // item join subscription

  // Config fields (parsed once in initState)
  String _groupField = 'ii';
  String _valueField = 'qt';
  String _pivotField = 'lt';
  String _condField = 'cd';
  String _joinKey = 'ii';
  String _nameField = 'in';
  String _catField = 'ic';
  bool _showCondition = false;
  bool _filterTabs = true;
  String _title = '';
  String _subtitle = '';
  String _emptyText = '';
  String _condNote = '';
  String _detailField = '';
  String _detailNameField = '';
  String _detailSubField = '';

  /// Parsed pivotValues: list of (value, label, icon).
  List<_PivotDef> _pivotDefs = const [];

  /// Parsed condValues: list of (value, label).
  List<_CondDef> _condDefs = const [];

  /// Parsed summary scopes: list of (scope, label).
  List<_SummaryDef> _summaryDefs = const [];

  /// Parsed from itemIconMap (copy of sibling pattern).
  Map<String, _IconEntry> _iconMap = const <String, _IconEntry>{};

  @override
  void initState() {
    super.initState();
    AssetStockList.registerScreenSession();
    _parseText();
    _parseConfig();
    _subscribe();
  }

  @override
  void dispose() {
    // Do NOT clear _activeTab here. clearState(scrName) is called from
    // buildPage in ui_component.dart -- the correct teardown path given
    // linkElement caching (dispose may not fire on route changes).
    super.dispose();
  }

  // -- Parse helpers --------------------------------------------------------

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessor (length-guarded: arr.length > i ? arr[i] : def).
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _parseConfig() {
    String cfg(String key, String def) {
      final String v = (widget.component[key] ?? '').toString().trim();
      return v.isNotEmpty ? v : def;
    }

    _groupField = cfg('groupField', 'ii');
    _valueField = cfg('valueField', 'qt');
    _pivotField = cfg('pivotField', 'lt');
    _condField = cfg('condField', 'cd');
    _joinKey = cfg('joinKey', 'ii');
    _nameField = cfg('nameField', 'in');
    _catField = cfg('catField', 'ic');
    _showCondition = cfg('showCondition', 'FALSE').toUpperCase() == 'TRUE';
    _filterTabs = cfg('filterTabs', 'TRUE').toUpperCase() != 'FALSE';
    _title = cfg('title', '');
    _subtitle = cfg('subtitle', '');
    _emptyText = cfg('emptyText', '');
    _condNote = cfg('condNote', '');
    _detailField = cfg('detailField', '');
    _detailNameField = cfg('detailNameField', '');
    _detailSubField = cfg('detailSubField', '');

    // pivotValues: value◼label◼icon★... (autheniumDecode first)
    final String rawPivot = (widget.component['pivotValues'] ?? '')
        .toString()
        .trim();
    if (rawPivot.isNotEmpty) {
      final String decoded = autheniumDecode(rawPivot) ?? rawPivot;
      final List<_PivotDef> defs = <_PivotDef>[];
      for (final String entry in decoded.split('\u{2605}')) {
        final List<String> segs = entry.split('\u{25FC}');
        if (segs.isEmpty) continue;
        final String value = segs[0].trim();
        final String label = segs.length > 1 ? segs[1].trim() : value;
        final String icon = segs.length > 2 ? segs[2].trim() : '';
        if (value.isNotEmpty) {
          defs.add(_PivotDef(value: value, label: label, icon: icon));
        }
      }
      _pivotDefs = defs;
    }

    // condValues: value◼label★...
    final String rawCond = (widget.component['condValues'] ?? '')
        .toString()
        .trim();
    if (rawCond.isNotEmpty) {
      final String decoded = autheniumDecode(rawCond) ?? rawCond;
      final List<_CondDef> defs = <_CondDef>[];
      for (final String entry in decoded.split('\u{2605}')) {
        final List<String> segs = entry.split('\u{25FC}');
        if (segs.isEmpty) continue;
        final String value = segs[0].trim();
        final String label = segs.length > 1 ? segs[1].trim() : value;
        if (value.isNotEmpty) {
          defs.add(_CondDef(value: value, label: label));
        }
      }
      _condDefs = defs;
    }

    // summary: scope◼label★...
    final String rawSummary = (widget.component['summary'] ?? '')
        .toString()
        .trim();
    if (rawSummary.isNotEmpty) {
      final String decoded = autheniumDecode(rawSummary) ?? rawSummary;
      final List<_SummaryDef> defs = <_SummaryDef>[];
      for (final String entry in decoded.split('\u{2605}')) {
        final List<String> segs = entry.split('\u{25FC}');
        if (segs.isEmpty) continue;
        final String scope = segs[0].trim();
        final String label = segs.length > 1 ? segs[1].trim() : scope;
        if (scope.isNotEmpty) {
          defs.add(_SummaryDef(scope: scope, label: label));
        }
      }
      _summaryDefs = defs;
    }

    // itemIconMap: key◼emoji◼slot★... (copy of sibling pattern)
    final String rawIconMap = (widget.component['itemIconMap'] ?? '')
        .toString()
        .trim();
    if (rawIconMap.isNotEmpty) {
      final String decoded = autheniumDecode(rawIconMap) ?? rawIconMap;
      final Map<String, _IconEntry> map = <String, _IconEntry>{};
      for (final String entry in decoded.split('\u{2605}')) {
        final List<String> segs = entry.split('\u{25FC}');
        if (segs.length < 2) continue;
        final String k = segs[0].trim();
        final String emoji = segs[1].trim();
        final String slot = segs.length > 2 ? segs[2].trim() : '';
        if (k.isNotEmpty && emoji.isNotEmpty) {
          map[k] = _IconEntry(emoji: emoji, slot: slot);
        }
      }
      _iconMap = map;
    }
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // asset_cache
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty) {
        _acCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _acCode);
      }
    }

    // item collection (join: name + category)
    final String rawJoinTable = (widget.component['joinTable'] ?? '')
        .toString()
        .trim();
    if (rawJoinTable.isNotEmpty) {
      if (!rawJoinTable.contains('//') && _acCode.isNotEmpty) {
        // Bare name: subscribe as subcollection under the asset_cache table's docId
        final String mainTableDocId = parseTablePath(
          (widget.component['table'] ?? '').toString().trim(),
        ).tableDocId;
        if (mainTableDocId.isNotEmpty) {
          _itemCode = '$appVid/$mainTableDocId/$rawJoinTable';
          subscribeToMapCollection(
            appVid,
            mainTableDocId,
            rawJoinTable,
            _itemCode,
          );
        }
      } else {
        final TablePath itp = parseTablePath(rawJoinTable);
        if (itp.tableDocId.isNotEmpty) {
          _itemCode = '$appVid/${itp.tableDocId}/${itp.subColl}';
          subscribeToMapCollection(
            appVid,
            itp.tableDocId,
            itp.subColl,
            _itemCode,
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredDocs() {
    if (_acCode.isEmpty) return const [];
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_acCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return docs;
    return filterDriverHomeDocs(docs, rawSearch, widget.scrName);
  }

  /// Resolve icon emoji and accent for an entity. Checks entityId first,
  /// then category. Falls back to neutral dot + slate accent.
  /// Mirrors sibling _resolveChip pattern.
  (_IconEntry icon, ChipAccent accent) _resolveChip(
    String entityId,
    String entityCategory,
  ) {
    _IconEntry? entry = _iconMap[entityId] ?? _iconMap[entityCategory];
    if (entry != null) {
      final ChipAccent accent = entry.slot.isNotEmpty
          ? ChipAccent.forSlot(entry.slot)
          : (entityCategory.isNotEmpty
                ? ChipAccent.forCategory(entityCategory)
                : ChipAccent.slate);
      return (entry, accent);
    }
    final _IconEntry fallbackIcon = const _IconEntry(
      emoji: '\u{25CF}',
      slot: '',
    ); // bullet dot
    final ChipAccent accent = entityCategory.isNotEmpty
        ? ChipAccent.forCategory(entityCategory)
        : ChipAccent.slate;
    return (fallbackIcon, accent);
  }

  /// Whether the given pivot index is the "outstanding-style" pivot.
  /// Condition: last pivotValue AND text seg-3 is non-empty.
  bool _isOutstandingPivot(int pivotIndex) {
    return pivotIndex == _pivotDefs.length - 1 && _t(3).isNotEmpty;
  }

  /// Accent for a pivot by its position index. Outstanding -> violet,
  /// others -> positional from ChipAccent palette.
  ChipAccent _pivotAccent(int pivotIndex) {
    if (_isOutstandingPivot(pivotIndex)) return ChipAccent.violet;
    const List<ChipAccent> palette = [
      ChipAccent.slate,
      ChipAccent.blue,
      ChipAccent.teal,
      ChipAccent.green,
      ChipAccent.amber,
      ChipAccent.red,
    ];
    return palette[pivotIndex % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // -- Reactive reads (register Obx dependencies) -----------------------
      mapTableContent[_acCode];
      mapTableContent[_itemCode];

      // -- Data -------------------------------------------------------------
      final List<Map<String, dynamic>> filteredDocs = _getFilteredDocs();
      final List<Map<String, dynamic>> itemDocsList =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );

      final bool hideZero = hideZeroEnabled(widget.component);

      final List<String> pivotOrder = _pivotDefs
          .map((_PivotDef d) => d.value)
          .toList();
      final List<String> condOrder = _condDefs
          .map((_CondDef d) => d.value)
          .toList();

      final AssetStockResult data = groupAssetStock(
        cacheDocs: filteredDocs,
        itemDocs: itemDocsList,
        hideZero: hideZero,
        groupField: _groupField,
        valueField: _valueField,
        pivotField: _pivotField,
        condField: _condField,
        itemKey: _joinKey,
        nameField: _nameField,
        catField: _catField,
        pivotOrder: pivotOrder,
        condOrder: condOrder,
        detailField: _detailField,
        detailNameField: _detailNameField,
        detailSubField: _detailSubField,
      );

      final int activeTab = AssetStockList._activeTab[widget.scrName] ?? 0;

      // -- Text slots -------------------------------------------------------
      final String totalLabel = _t(0, 'total');
      final String semuaLabel = _t(1, 'Semua');
      // _t(2) = unit (e.g. 'pcs') -- rendered next to totals in card builders
      final String outstandingSublabel = _t(3); // may be empty

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
            // -- Header (title + subtitle) ----------------------------------
            if (_title.isNotEmpty) ...[
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AdminTierColors.titleText,
                ),
              ),
              if (_subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminTierColors.subText,
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // -- Summary strip ----------------------------------------------
            if (_summaryDefs.isNotEmpty) ...[
              _buildSummaryStrip(data.summaryValues),
              const SizedBox(height: 16),
            ],

            // -- Filter tabs ------------------------------------------------
            if (_filterTabs && _pivotDefs.isNotEmpty) ...[
              _buildFilterTabs(activeTab, semuaLabel),
              const SizedBox(height: 16),
            ],

            // -- Entity cards (or empty state) ------------------------------
            if (data.entities.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _emptyText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminTierColors.mutedText,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              for (int i = 0; i < data.entities.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _buildEntityCard(
                  data.entities[i],
                  activeTab,
                  totalLabel,
                  outstandingSublabel,
                ),
              ],

            // -- condNote (only when showCondition == TRUE) -----------------
            if (_showCondition && _condNote.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminTierColors.normalBadgeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminTierColors.cardBorder),
                ),
                child: Text(
                  _condNote,
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AdminTierColors.neutralPillText,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  /// Map a summary scope to its filter-tab index.
  /// Returns null if the scope does not match any pivot (tap is a no-op).
  int? _summaryTabIndex(String scope) {
    if (scope == 'all') return 0;
    final String prefix = scope.contains('.')
        ? scope.substring(0, scope.indexOf('.'))
        : scope;
    for (int i = 0; i < _pivotDefs.length; i++) {
      if (_pivotDefs[i].value == prefix) return i + 1;
    }
    return null;
  }

  Widget _buildSummaryStrip(Map<String, int> summaryValues) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _summaryDefs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: () {
                final _SummaryDef def = _summaryDefs[i];
                final int value = summaryValues[def.scope] ?? 0;

                // Detect warn/amber scope: any scope containing a condValue
                // at index 1 (the "empty"/"danger" position).
                final bool isWarnScope =
                    _condDefs.length > 1 &&
                    def.scope.endsWith('.${_condDefs[1].value}');

                final Color bg = isWarnScope
                    ? AdminTierColors.dangerBadgeBg
                    : AdminTierColors.normalBadgeBg;
                final Color numColor = isWarnScope
                    ? AdminTierColors.dangerBadgeText
                    : AdminTierColors.titleText;
                final Color labelColor = isWarnScope
                    ? AdminTierColors.dangerBadgeText
                    : AdminTierColors.subText;

                final int? tabIdx = _summaryTabIndex(def.scope);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: tabIdx != null
                      ? () {
                          AssetStockList._activeTab[widget.scrName] = tabIdx;
                          setState(() {});
                        }
                      : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$value',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: numColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          def.label,
                          style: TextStyle(fontSize: 10, color: labelColor),
                        ),
                      ],
                    ),
                  ),
                );
              }(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterTabs(int activeTab, String semuaLabel) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Tab 0: "Semua"
          _buildTabPill(
            label: semuaLabel,
            icon: '',
            isActive: activeTab == 0,
            onTap: () {
              AssetStockList._activeTab[widget.scrName] = 0;
              setState(() {});
            },
          ),
          // Tabs 1..N: per pivotValue
          for (int i = 0; i < _pivotDefs.length; i++) ...[
            const SizedBox(width: 8),
            _buildTabPill(
              label: _pivotDefs[i].label,
              icon: _pivotDefs[i].icon,
              isActive: activeTab == i + 1,
              onTap: () {
                AssetStockList._activeTab[widget.scrName] = i + 1;
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required String icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AdminTierColors.titleText : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: isActive
              ? null
              : Border.all(color: AdminTierColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon.isNotEmpty) ...[
              Text(icon, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AdminTierColors.titleText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityCard(
    AssetEntity entity,
    int activeTab,
    String totalLabel,
    String outstandingSublabel,
  ) {
    final (icon, chipAccent) = _resolveChip(entity.id, entity.category);
    final String unit = _t(2); // W2: unit label (e.g. 'pcs'), '' => hidden

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTierColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // -- Header row: icon + name + sublabel + total ------------------
          Row(
            children: [
              // Icon tile
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: chipAccent.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(icon.emoji, style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entity.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTierColors.titleText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      totalLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminTierColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entity.total}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: AdminTierColors.titleText,
                ),
              ),
              // W2: unit next to the big total ("245 pcs"). Absent => hidden.
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminTierColors.subText,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // -- Body: depends on active tab --------------------------------
          if (activeTab == 0)
            _buildSemuaBody(entity, outstandingSublabel)
          else
            _buildSinglePivotBody(entity, activeTab - 1, outstandingSublabel),
        ],
      ),
    );
  }

  /// Semua tab: proportion bar + row of per-pivot breakdown boxes.
  Widget _buildSemuaBody(AssetEntity entity, String outstandingSublabel) {
    // Collect non-zero pivots in order for the bar
    final List<(int index, PivotCell cell)> nonZeroPivots = [];
    for (int i = 0; i < _pivotDefs.length; i++) {
      final PivotCell? cell = entity.pivots[_pivotDefs[i].value];
      if (cell != null && cell.total > 0) {
        nonZeroPivots.add((i, cell));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Proportion bar
        if (nonZeroPivots.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final (int idx, PivotCell cell) in nonZeroPivots)
                    Expanded(
                      flex: cell.total,
                      child: Container(
                        color: _pivotAccent(idx).fg.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Per-pivot breakdown boxes (horizontal wrap)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < _pivotDefs.length; i++) ...[
              () {
                final _PivotDef pDef = _pivotDefs[i];
                final PivotCell? cell = entity.pivots[pDef.value];
                // Always render every configured pivot in the Semua breakdown,
                // even when its balance is 0 or absent (cell pruned by hideZero).
                final int pivotTotal = cell?.total ?? 0;
                final ChipAccent accent = _pivotAccent(i);
                final bool isOutstanding = _isOutstandingPivot(i);

                final Widget box = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accent.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (pDef.icon.isNotEmpty) ...[
                            Text(
                              pDef.icon,
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            pDef.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: accent.fg,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$pivotTotal',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: accent.fg,
                            ),
                          ),
                        ],
                      ),
                      // Isi/Kosong sub-row (non-outstanding + showCondition)
                      if (!isOutstanding &&
                          _showCondition &&
                          _condDefs.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int ci = 0; ci < _condDefs.length; ci++) ...[
                              if (ci > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    '\u{00B7}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: accent.fg,
                                    ),
                                  ),
                                ),
                              Text(
                                '${_condDefs[ci].label} ${cell?.condTotals[_condDefs[ci].value] ?? 0}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: accent.fg.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      // Outstanding sublabel
                      if (isOutstanding && outstandingSublabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          outstandingSublabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: accent.fg.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    AssetStockList._activeTab[widget.scrName] = i + 1;
                    setState(() {});
                  },
                  child: pivotTotal == 0
                      ? Opacity(opacity: 0.5, child: box)
                      : box,
                );
              }(),
            ],
          ],
        ),
      ],
    );
  }

  /// Single-pivot tab: large box for the selected pivot only.
  Widget _buildSinglePivotBody(
    AssetEntity entity,
    int pivotIndex,
    String outstandingSublabel,
  ) {
    if (pivotIndex < 0 || pivotIndex >= _pivotDefs.length) {
      return const SizedBox.shrink();
    }

    final _PivotDef pDef = _pivotDefs[pivotIndex];
    final PivotCell? cell = entity.pivots[pDef.value];
    final int pivotTotal = cell?.total ?? 0;
    final ChipAccent accent = _pivotAccent(pivotIndex);
    final bool isOutstanding = _isOutstandingPivot(pivotIndex);
    final String unit = _t(2); // W2: unit label (e.g. 'pcs'), '' => hidden

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pivot label + total
          Row(
            children: [
              if (pDef.icon.isNotEmpty) ...[
                Text(pDef.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
              ],
              Text(
                pDef.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent.fg,
                ),
              ),
              const Spacer(),
              Text(
                '$pivotTotal',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: accent.fg,
                ),
              ),
              // W2: unit next to the big total ("45 pcs"). Absent => hidden.
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11,
                    color: accent.fg.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),

          // Detail rows (per detailField) when set and details available
          if (_detailField.isNotEmpty &&
              cell != null &&
              cell.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: accent.fg.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            for (final DetailRow dr in cell.details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (pDef.icon.isNotEmpty) ...[
                      Text(pDef.icon, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: dr.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: accent.fg,
                              ),
                            ),
                            if (dr.sub.isNotEmpty)
                              TextSpan(
                                text: ' \u{00B7} ${dr.sub}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: accent.fg.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isOutstanding &&
                        _showCondition &&
                        _condDefs.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int ci = 0; ci < _condDefs.length; ci++) ...[
                            if (ci > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  '\u{00B7}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: accent.fg,
                                  ),
                                ),
                              ),
                            Text(
                              '${_condDefs[ci].label} ${dr.condTotals[_condDefs[ci].value] ?? 0}',
                              style: TextStyle(
                                fontSize: 10,
                                color: accent.fg.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Text(
                        '${dr.total}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: accent.fg,
                        ),
                      ),
                  ],
                ),
              ),
          ]
          // Non-outstanding + showCondition: large ISI | KOSONG split (aggregate fallback)
          else if (!isOutstanding &&
              _showCondition &&
              _condDefs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (int ci = 0; ci < _condDefs.length; ci++) ...[
                  if (ci > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ci == 0
                            ? AdminTierColors.okBadgeBg
                            : AdminTierColors.dangerBadgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _condDefs[ci].label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: ci == 0
                                  ? AdminTierColors.okBadgeText
                                  : AdminTierColors.dangerBadgeText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${cell?.condTotals[_condDefs[ci].value] ?? 0}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: ci == 0
                                  ? AdminTierColors.okBadgeText
                                  : AdminTierColors.dangerBadgeText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Outstanding sublabel
          if (isOutstanding && outstandingSublabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              outstandingSublabel,
              style: TextStyle(
                fontSize: 11,
                color: accent.fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Private config types -------------------------------------------------

class _PivotDef {
  final String value;
  final String label;
  final String icon;
  const _PivotDef({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class _CondDef {
  final String value;
  final String label;
  const _CondDef({required this.value, required this.label});
}

class _SummaryDef {
  final String scope;
  final String label;
  const _SummaryDef({required this.scope, required this.label});
}

/// Internal: parsed itemIconMap entry (mirrors sibling).
class _IconEntry {
  final String emoji;
  final String slot;
  const _IconEntry({required this.emoji, required this.slot});
}
