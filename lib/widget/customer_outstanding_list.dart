import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // getNowMillisecondFromEpoch
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'admin_home_support.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

// ─── Chip accent palette (W3: category-colored chips) ──────────────────────

/// Named accent slots for per-item chips. Seven accents tuned to the design
/// mockups. Config supplies a slot NAME (not hex); this class resolves it to
/// a (bg, fg) pair. Centralized here (co-located with the widget that uses
/// it) rather than AdminTierColors because these are chip-specific, not
/// tier-specific.
///
/// When the server theme eventually adds chip-color slots, only this class
/// needs updating (mirrors the AdminTierColors upgrade-path comment).
class ChipAccent {
  final Color bg;
  final Color fg;
  const ChipAccent(this.bg, this.fg);

  // ── Named accents ────────────────────────────────────────────────────

  static const ChipAccent blue = ChipAccent(
    Color(0xFFDBEAFE),
    Color(0xFF1D4ED8),
  );
  static const ChipAccent red = ChipAccent(
    Color(0xFFFEE2E2),
    Color(0xFFDC2626),
  );
  static const ChipAccent amber = ChipAccent(
    Color(0xFFFEF3C7),
    Color(0xFFB45309),
  );
  static const ChipAccent green = ChipAccent(
    Color(0xFFDCFCE7),
    Color(0xFF16A34A),
  );
  static const ChipAccent violet = ChipAccent(
    Color(0xFFEDE9FE),
    Color(0xFF7C3AED),
  );
  static const ChipAccent teal = ChipAccent(
    Color(0xFFCCFBF1),
    Color(0xFF0D9488),
  );
  static const ChipAccent slate = ChipAccent(
    Color(0xFFF1F5F9),
    Color(0xFF475569),
  );

  /// Ordered palette for deterministic category assignment.
  static const List<ChipAccent> _palette = [
    blue,
    red,
    amber,
    green,
    violet,
    teal,
    slate,
  ];

  /// Slot-name lookup. Returns [slate] for unknown/empty names.
  static const Map<String, ChipAccent> _byName = {
    'blue': blue,
    'red': red,
    'amber': amber,
    'green': green,
    'violet': violet,
    'teal': teal,
    'slate': slate,
  };

  /// Resolve a named slot to an accent. Unknown/empty -> [slate].
  static ChipAccent forSlot(String slot) {
    if (slot.isEmpty) return slate;
    return _byName[slot.toLowerCase().trim()] ?? slate;
  }

  /// Deterministic accent for a category string (when no explicit slot is
  /// configured). Stable: same category always gets the same accent.
  /// Uses hashCode mod palette length.
  static ChipAccent forCategory(String category) {
    if (category.isEmpty) return slate;
    final int idx = category.hashCode.abs() % _palette.length;
    return _palette[idx];
  }
}

// ─── Public aggregation result (testable) ──────────────────────────────────

/// Result of [groupCustomerOutstanding]: sorted customer groups + grand total.
class CustomerOutstandingResult {
  final List<CustomerGroup> groups;
  final int grandTotal;
  const CustomerOutstandingResult({
    required this.groups,
    required this.grandTotal,
  });
}

/// One customer's outstanding summary. Public for test assertions.
class CustomerGroup {
  final String customerId;
  final String customerName;
  final String customerType;
  final int totalQty;
  final int oldestAgingDays;
  final String tier; // 'kritis', 'perhatian', 'normal'
  final List<CustomerItemSummary> items;
  const CustomerGroup({
    required this.customerId,
    required this.customerName,
    required this.customerType,
    required this.totalQty,
    required this.oldestAgingDays,
    required this.tier,
    required this.items,
  });
}

/// One item within a customer's outstanding. Public for test assertions.
class CustomerItemSummary {
  final String itemId;
  final String itemName;
  final String itemCategory;
  final int qty;
  final int agingDays;
  const CustomerItemSummary({
    required this.itemId,
    required this.itemName,
    required this.itemCategory,
    required this.qty,
    required this.agingDays,
  });
}

// ─── Pure aggregation function (the SINGLE source of truth) ────────────────

/// Group asset_cache docs by customer, aggregate per-item qty + aging, join
/// name/type from stock_location and item collections.
///
/// Pure -- no Flutter/Obx deps, directly testable. The widget calls this; it
/// does not re-implement the logic.
///
/// Convention #7: all inputs originate from firestoreDb (dynamic); field reads
/// use `.toString().trim()` and `int.tryParse(...) ?? 0`. Returns explicitly
/// typed collections (never `.map().toList()` into a typed store).
CustomerOutstandingResult groupCustomerOutstanding({
  required List<Map<String, dynamic>> cacheDocs,
  required List<Map<String, dynamic>> customerDocs,
  required List<Map<String, dynamic>> itemDocs,
  int? nowMs,
  bool hideZero = true,
  String groupField = 'lv',
  String itemField = 'ii',
  String qtyField = 'qt',
  String ageField = 't',
  String customerKey = 'lv',
  String nameField = 'ln',
  String typeField = 'ty',
  String itemKey = 'ii',
  String itemNameField = 'in',
  String itemCatField = 'ic',
  int? dangerAge,
  int? warnAge,
}) {
  final int now = nowMs ?? getNowMillisecondFromEpoch();
  const int msPerDay = 86400000;

  // ── Build join maps ──────────────────────────────────────────────────

  // customer lv -> (name, type)
  final Map<String, String> custNameMap = <String, String>{};
  final Map<String, String> custTypeMap = <String, String>{};
  for (final Map<String, dynamic> doc in customerDocs) {
    final String key = (doc[customerKey] ?? '').toString().trim();
    if (key.isEmpty) continue;
    custNameMap[key] = (doc[nameField] ?? '').toString().trim();
    custTypeMap[key] = (doc[typeField] ?? '').toString().trim();
  }

  // item ii -> (name, category)
  final Map<String, String> itemNameMap = <String, String>{};
  final Map<String, String> itemCatMap = <String, String>{};
  for (final Map<String, dynamic> doc in itemDocs) {
    final String key = (doc[itemKey] ?? '').toString().trim();
    if (key.isEmpty) continue;
    itemNameMap[key] = (doc[itemNameField] ?? '').toString().trim();
    itemCatMap[key] = (doc[itemCatField] ?? '').toString().trim();
  }

  // ── Group asset_cache by customer -> item -> sum qty + oldest t ──────

  // grouped[customerId][itemId] = (sumQty, oldestT)
  final Map<String, Map<String, _Accum>> grouped =
      <String, Map<String, _Accum>>{};

  for (final Map<String, dynamic> doc in cacheDocs) {
    final String custId = (doc[groupField] ?? '').toString().trim();
    if (custId.isEmpty) continue;
    final String iid = (doc[itemField] ?? '').toString().trim();
    if (iid.isEmpty) continue;
    final int qty = _safeInt(doc[qtyField]);
    final int t = _safeInt(doc[ageField]);

    final Map<String, _Accum> custBucket = grouped.putIfAbsent(
      custId,
      () => <String, _Accum>{},
    );
    final _Accum acc = custBucket.putIfAbsent(iid, () => _Accum());
    acc.totalQty += qty;
    if (t > 0 && (acc.oldestT == 0 || t < acc.oldestT)) {
      acc.oldestT = t;
    }
  }

  // ── Build CustomerGroup list ─────────────────────────────────────────

  final List<CustomerGroup> result = <CustomerGroup>[];
  int grandTotal = 0;

  for (final MapEntry<String, Map<String, _Accum>> custEntry
      in grouped.entries) {
    final String custId = custEntry.key;
    final Map<String, _Accum> itemMap = custEntry.value;

    final List<CustomerItemSummary> items = <CustomerItemSummary>[];
    int custTotal = 0;
    int custOldestAgingDays = 0;

    for (final MapEntry<String, _Accum> itemEntry in itemMap.entries) {
      final String iid = itemEntry.key;
      final _Accum acc = itemEntry.value;

      if (hideZero && acc.totalQty == 0) continue;

      final int ageDays = acc.oldestT > 0
          ? ((now - acc.oldestT) ~/ msPerDay)
          : 0;
      final int safeAgeDays = ageDays < 0 ? 0 : ageDays;

      final String resolvedName = itemNameMap[iid]?.isNotEmpty == true
          ? itemNameMap[iid]!
          : iid;
      final String resolvedCat = itemCatMap[iid] ?? '';

      items.add(
        CustomerItemSummary(
          itemId: iid,
          itemName: resolvedName,
          itemCategory: resolvedCat,
          qty: acc.totalQty,
          agingDays: safeAgeDays,
        ),
      );

      custTotal += acc.totalQty;
      if (safeAgeDays > custOldestAgingDays) {
        custOldestAgingDays = safeAgeDays;
      }
    }

    if (hideZero && custTotal == 0) continue;
    if (items.isEmpty && hideZero) continue;

    final String resolvedCustName = custNameMap[custId]?.isNotEmpty == true
        ? custNameMap[custId]!
        : custId;
    final String resolvedCustType = custTypeMap[custId] ?? '';

    // Sort items by qty desc within this customer
    items.sort((a, b) => b.qty.compareTo(a.qty));

    result.add(
      CustomerGroup(
        customerId: custId,
        customerName: resolvedCustName,
        customerType: resolvedCustType,
        totalQty: custTotal,
        oldestAgingDays: custOldestAgingDays,
        tier: agingTierDays(
          custOldestAgingDays,
          dangerDays: dangerAge,
          warnDays: warnAge,
        ),
        items: items,
      ),
    );

    grandTotal += custTotal;
  }

  // Sort customers by total desc (spec §1.7)
  result.sort((a, b) => b.totalQty.compareTo(a.totalQty));

  return CustomerOutstandingResult(groups: result, grandTotal: grandTotal);
}

/// Safely coerce a dynamic value to int. Returns 0 on null, empty, or
/// non-parseable input. Mirrors admin_home_support._toInt (private there).
int _safeInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

/// Mutable accumulator for per-item aggregation within a customer.
class _Accum {
  int totalQty = 0;
  int oldestT = 0; // epoch-ms of oldest doc (smallest positive t)
}

// ─── Widget ────────────────────────────────────────────────────────────────

/// CUSTOMER_OUTSTANDING_LIST -- full-page customer outstanding lookup.
///
/// Header (title + subtitle + grand-total pill) · search box · count line ·
/// customer cards. Tap card -> modal bottom sheet (per-item breakdown +
/// doctrine + Tutup).
///
/// Read-only: no txfController, no saveSend, no history.
class CustomerOutstandingList extends StatefulWidget {
  const CustomerOutstandingList({
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

  /// Per-screen search text, keyed by scrName (convention: screen-specific
  /// shared state as static Map, not global.dart).
  static final Map<String, String> _searchText = <String, String>{};

  /// Called from buildPage in ui_component.dart on route change to release
  /// per-screen state. Mirrors CustodyEventSubmit.clearState,
  /// ItemExecutionSubmit.clearState, TaskFeedList.clearFlatSearch, etc.
  static void clearState(String scrName) {
    _searchText.remove(scrName);
  }

  @override
  State<CustomerOutstandingList> createState() =>
      _CustomerOutstandingListState();
}

class _CustomerOutstandingListState extends State<CustomerOutstandingList> {
  List<String> _textArray = [];
  List<String> _detailTextArray = [];
  String _acCode = ''; // asset_cache subscription
  String _slCode = ''; // stock_location (customer) subscription
  String _itemCode = ''; // item collection subscription

  // Config fields (parsed once in initState)
  String _groupField = 'lv';
  String _itemField = 'ii';
  String _qtyField = 'qt';
  String _ageField = 't';
  String _customerKey = 'lv';
  String _nameField = 'ln';
  String _typeField = 'ty';
  String _itemKey = 'ii';
  String _itemNameField = 'in';
  String _itemCatField = 'ic';
  int? _dangerAge;
  int? _warnAge;
  String _searchHint = 'Cari customer';
  String _title = 'Outstanding Customer';
  String _subtitle = '';
  String _emptyText = 'Belum ada customer dengan outstanding';
  String _doctrineText = '';
  String _closeText = 'Tutup';

  /// Parsed from itemIconMap: itemId/category -> (emoji, accentSlot).
  /// 3-segment: key◼emoji◼slot; 2-segment: key◼emoji (slot='').
  Map<String, _IconEntry> _iconMap = const <String, _IconEntry>{};

  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _parseText();
    _parseConfig();
    _subscribe();
    _searchController = TextEditingController(
      text: CustomerOutstandingList._searchText[widget.scrName] ?? '',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    // W4: do NOT clear _searchText here. clearState(scrName) is called from
    // buildPage in ui_component.dart -- the correct teardown path given
    // linkElement caching (dispose may not fire on route changes).
    super.dispose();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    try {
      _detailTextArray = diamondTextToList(
        widget.component['detailText'] ?? '',
      );
    } catch (_) {
      _detailTextArray = [];
    }
  }

  /// text slot accessor (length-guarded: arr.length > i ? arr[i] : def).
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  /// detailText slot accessor (length-guarded).
  String _dt(int i, [String def = '']) =>
      _detailTextArray.length > i ? _detailTextArray[i] : def;

  void _parseConfig() {
    String cfg(String key, String def) {
      final String v = (widget.component[key] ?? '').toString().trim();
      return v.isNotEmpty ? v : def;
    }

    _groupField = cfg('groupField', 'lv');
    _itemField = cfg('itemField', 'ii');
    _qtyField = cfg('qtyField', 'qt');
    _ageField = cfg('ageField', 't');
    _customerKey = cfg('customerKey', 'lv');
    _nameField = cfg('nameField', 'ln');
    _typeField = cfg('typeField', 'ty');
    _itemKey = cfg('itemKey', 'ii');
    _itemNameField = cfg('itemNameField', 'in');
    _itemCatField = cfg('itemCatField', 'ic');
    _searchHint = cfg('searchHint', 'Cari customer');
    _title = cfg('title', 'Outstanding Customer');
    _subtitle = cfg('subtitle', '');
    _emptyText = cfg('emptyText', 'Belum ada customer dengan outstanding');
    _doctrineText = cfg('doctrineText', '');
    _closeText = cfg('closeText', 'Tutup');

    final dynamic rawDanger = widget.component['dangerAge'];
    if (rawDanger != null) {
      final int d = int.tryParse(rawDanger.toString().trim()) ?? 0;
      if (d > 0) _dangerAge = d;
    }
    final dynamic rawWarn = widget.component['warnAge'];
    if (rawWarn != null) {
      final int w = int.tryParse(rawWarn.toString().trim()) ?? 0;
      if (w > 0) _warnAge = w;
    }

    // itemIconMap: key◼emoji◼slot★key◼emoji★... (autheniumDecode first)
    // 3-segment (key◼emoji◼slot) = explicit accent slot.
    // 2-segment (key◼emoji) = slot '' → deterministic category assignment.
    final String rawIconMap = (widget.component['itemIconMap'] ?? '')
        .toString()
        .trim();
    if (rawIconMap.isNotEmpty) {
      final String decoded = autheniumDecode(rawIconMap) ?? rawIconMap;
      final Map<String, _IconEntry> map = <String, _IconEntry>{};
      for (final String entry in decoded.split('\u{2605}')) {
        // ★ separator between entries
        final List<String> segs = entry.split('\u{25FC}'); // ◼ separator
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

    // stock_location (customer name + type)
    final String rawCustTable = (widget.component['customerTable'] ?? '')
        .toString()
        .trim();
    if (rawCustTable.isNotEmpty) {
      final TablePath cp = parseTablePath(rawCustTable);
      if (cp.tableDocId.isNotEmpty) {
        _slCode = '$appVid/${cp.tableDocId}/${cp.subColl}';
        subscribeToMapCollection(appVid, cp.tableDocId, cp.subColl, _slCode);
      }
    }

    // item collection (item name + category)
    final String rawItemTable = (widget.component['itemTable'] ?? '')
        .toString()
        .trim();
    if (rawItemTable.isNotEmpty) {
      if (!rawItemTable.contains('//') && _acCode.isNotEmpty) {
        // Bare name: subscribe as subcollection under the asset_cache table's docId
        final String mainTableDocId = parseTablePath(
          (widget.component['table'] ?? '').toString().trim(),
        ).tableDocId;
        if (mainTableDocId.isNotEmpty) {
          _itemCode = '$appVid/$mainTableDocId/$rawItemTable';
          subscribeToMapCollection(
            appVid,
            mainTableDocId,
            rawItemTable,
            _itemCode,
          );
        }
      } else {
        final TablePath itp = parseTablePath(rawItemTable);
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

  /// Get filtered asset_cache docs. Uses filterDriverHomeDocs which handles
  /// autheniumDecode, token resolution, and filterByMultiClause with eq().
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

  /// Resolve icon emoji and accent for an item. Checks itemId first, then
  /// category. Falls back to neutral dot + slate accent.
  (_IconEntry icon, ChipAccent accent) _resolveChip(
    String itemId,
    String itemCategory,
  ) {
    // Check itemId first, then category
    _IconEntry? entry = _iconMap[itemId] ?? _iconMap[itemCategory];
    if (entry != null) {
      final ChipAccent accent = entry.slot.isNotEmpty
          ? ChipAccent.forSlot(entry.slot)
          : (itemCategory.isNotEmpty
                ? ChipAccent.forCategory(itemCategory)
                : ChipAccent.slate);
      return (entry, accent);
    }
    // No icon map entry: deterministic accent by category, neutral dot emoji
    final _IconEntry fallbackIcon = const _IconEntry(
      emoji: '\u{25CF}',
      slot: '',
    ); // ● neutral dot
    final ChipAccent accent = itemCategory.isNotEmpty
        ? ChipAccent.forCategory(itemCategory)
        : ChipAccent.slate;
    return (fallbackIcon, accent);
  }

  void _onSearchChanged(String value) {
    CustomerOutstandingList._searchText[widget.scrName] = value;
    setState(() {});
  }

  void _showDetailSheet(BuildContext context, CustomerGroup group) {
    final String rincianHeader = _dt(0, 'Rincian per jenis');
    final String agingSuffix = _dt(1, 'nyangkut');
    final String totalLabel = _dt(2, 'total pinjam');
    final String qtyUnit = _dt(3, 'pcs');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final double maxSheetHeight =
            MediaQuery.of(sheetCtx).size.height * 0.85;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AdminTierColors.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Customer name + total
                  Text(
                    group.customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AdminTierColors.titleText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalLabel: ${group.totalQty} $qtyUnit',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminTierColors.subText,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // "RINCIAN PER JENIS" header
                  Text(
                    rincianHeader.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AdminTierColors.sectionCaps,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Per-item rows (shrink-wrapped; scrolls only if tall)
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: group.items.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: AdminTierColors.cardBorder),
                      itemBuilder: (_, i) {
                        final CustomerItemSummary item = group.items[i];
                        final (icon, chipAccent) = _resolveChip(
                          item.itemId,
                          item.itemCategory,
                        );
                        final (
                          Color _,
                          Color tierFg,
                        ) = AdminTierColors.outstandingBadge(
                          agingTierDays(
                            item.agingDays,
                            dangerDays: _dangerAge,
                            warnDays: _warnAge,
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              // Icon with category-accent background
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: chipAccent.bg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  icon.emoji,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Name + aging
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.itemName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AdminTierColors.titleText,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.agingDays} ${_t(4, 'hari')} $agingSuffix',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: tierFg,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Qty
                              Text(
                                '${item.qty}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: AdminTierColors.titleText,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                qtyUnit,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AdminTierColors.subText,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Doctrine note
                  if (_doctrineText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminTierColors.normalBadgeBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AdminTierColors.cardBorder),
                      ),
                      child: Text(
                        _doctrineText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AdminTierColors.neutralPillText,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],

                  // Tutup button
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: AdminTierColors.cardBorder),
                        ),
                      ),
                      child: Text(
                        _closeText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AdminTierColors.titleText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // ── Reactive reads (register Obx dependencies) ─────────────────
      mapTableContent[_acCode];
      mapTableContent[_slCode];
      mapTableContent[_itemCode];

      // ── Data ───────────────────────────────────────────────────────
      final List<Map<String, dynamic>> filteredDocs = _getFilteredDocs();

      final List<Map<String, dynamic>> customerDocs =
          List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);
      final List<Map<String, dynamic>> itemDocsList =
          List<Map<String, dynamic>>.from(
            mapTableContent[_itemCode] ?? const [],
          );

      final bool hideZero = hideZeroEnabled(widget.component);

      final CustomerOutstandingResult data = groupCustomerOutstanding(
        cacheDocs: filteredDocs,
        customerDocs: customerDocs,
        itemDocs: itemDocsList,
        hideZero: hideZero,
        groupField: _groupField,
        itemField: _itemField,
        qtyField: _qtyField,
        ageField: _ageField,
        customerKey: _customerKey,
        nameField: _nameField,
        typeField: _typeField,
        itemKey: _itemKey,
        itemNameField: _itemNameField,
        itemCatField: _itemCatField,
        dangerAge: _dangerAge,
        warnAge: _warnAge,
      );

      // ── Client-side search filter ──────────────────────────────────
      final String query =
          (CustomerOutstandingList._searchText[widget.scrName] ?? '')
              .toLowerCase()
              .trim();
      final List<CustomerGroup> displayGroups = query.isEmpty
          ? data.groups
          : data.groups
                .where((g) => g.customerName.toLowerCase().contains(query))
                .toList();

      // ── Text slots ─────────────────────────────────────────────────
      final String grandTotalLabel = _t(0, 'total di luar');
      final String perCustUnit = _t(1, 'pcs pinjam');
      final String countLineLabel = _t(2, 'customer punya outstanding');
      final String agingPrefix = _t(3, 'tertua');
      final String agingUnit = _t(4, 'hari');

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
            // ── Header: title + subtitle + grand-total pill ──────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                    ],
                  ),
                ),
                // Grand total pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AdminTierColors.normalBadgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${data.grandTotal} $grandTotalLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminTierColors.normalBadgeText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Search box ──────────────────────────────────────────
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: _searchHint,
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AdminTierColors.mutedText,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AdminTierColors.mutedText,
                ),
                filled: true,
                fillColor: AdminTierColors.normalBadgeBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AdminTierColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AdminTierColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AdminTierColors.okAction),
                ),
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AdminTierColors.titleText,
              ),
            ),
            const SizedBox(height: 12),

            // ── Count line ──────────────────────────────────────────
            Text(
              '${displayGroups.length} $countLineLabel',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AdminTierColors.subText,
              ),
            ),
            const SizedBox(height: 12),

            // ── Customer cards (or empty state) ─────────────────────
            if (displayGroups.isEmpty)
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
              for (int i = 0; i < displayGroups.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _buildCustomerCard(
                  context,
                  displayGroups[i],
                  perCustUnit,
                  agingPrefix,
                  agingUnit,
                ),
              ],
          ],
        ),
      );
    });
  }

  Widget _buildCustomerCard(
    BuildContext context,
    CustomerGroup group,
    String perCustUnit,
    String agingPrefix,
    String agingUnit,
  ) {
    final (Color tierBadgeBg, Color tierBadgeFg) =
        AdminTierColors.outstandingBadge(group.tier);

    return GestureDetector(
      onTap: () => _showDetailSheet(context, group),
      behavior: HitTestBehavior.opaque,
      child: Container(
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
            // Row 1: Customer name + total + chevron
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.customerName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AdminTierColors.titleText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (group.customerType.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          group.customerType,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminTierColors.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${group.totalQty}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: AdminTierColors.titleText,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  perCustUnit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminTierColors.subText,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AdminTierColors.mutedText,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Row 2: Per-item chips (category-colored)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in group.items) ...[
                  () {
                    final (icon, chipAccent) = _resolveChip(
                      item.itemId,
                      item.itemCategory,
                    );
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: chipAccent.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            icon.emoji,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${item.itemName} ${item.qty}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: chipAccent.fg,
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Row 3: Oldest aging + tier badge
            Row(
              children: [
                // Tier badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tierBadgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    group.tier.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: tierBadgeFg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Aging text
                Text(
                  '$agingPrefix ${group.oldestAgingDays} $agingUnit',
                  style: TextStyle(fontSize: 11, color: tierBadgeFg),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Internal: parsed itemIconMap entry.
class _IconEntry {
  final String emoji;
  final String slot; // accent slot name, '' = deterministic
  const _IconEntry({required this.emoji, required this.slot});
}
