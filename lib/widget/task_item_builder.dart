import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter, TextInputFormatter
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // transactionStore, mapTableContent, diamondTextToList
import '../redux/screen_transaction.dart'; // UpdateScreenTxAction, ScreenTransaction
import '../screen_session.dart';
import 'admin_create_task_support.dart';
import 'admin_home_support.dart'; // AdminTierColors
import 'custody_stepper.dart'; // CustodyStepper (reusable stepper control)
import 'driver_home_support.dart'; // resolveAppVid
import 'panel_card_support.dart'; // parseTablePath, TablePath

/// TASK_ITEM_BUILDER -- the core item-line builder for P2 (Admin create-task
/// wizard, mode=order).
///
/// Self-contained Flutter UI: renders item cards with steppers, toggles, and
/// picker bottom-sheets. Does NOT dispatch SDUI sub-components.
///
/// Subscribes to:
///   - item collection (product catalog)
///   - stock_location (resolve kl -> kn/al for screenTx republish)
///   - asset_cache (Model B outstanding suggestion)
///
/// Writes to:
///   - AdminCreateTaskSupport.draftItems[wizardKey] (the cross-screen draft)
///   - screenTx bare keys: kl, kn, al (republished on first build/data load)
///
/// Read-only for Firestore: no txfController, no saveSend, no history. The
/// actual native write happens in task_create_submit (P4).
class TaskItemBuilder extends StatefulWidget {
  const TaskItemBuilder({
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

  /// Revision counter: bumped whenever the draft changes and cross-widget
  /// Obx consumers (e.g. a buttonRoute that shows totals) need to rebuild.
  /// Pattern: plain Map + RxInt signal (Prior Correction #3).
  static final RxInt draftRev = 0.obs;

  /// Per-scrName record of the LAST kl that was republished for this screen.
  /// Tracking the kl (not a one-shot bool) lets _republishClient re-fire when
  /// the user re-picks a DIFFERENT customer on back-nav -- the page State is
  /// cached in linkElement, so a bool would latch forever and leak the prior
  /// customer's kn/al into the next task (review C-1). Static so clearData can
  /// reset it.
  static final Map<String, String> _lastPublishedKl = {};

  static void registerScreenSession() {
    // Phase 2: flipped to nav:screen (its own doc comment says "Static so
    // clearData can reset it").
    ScreenSession.ensure(
      'TaskItemBuilder.lastPublishedKl',
      TaskItemBuilder.resetClientPublished,
    );
  }

  /// Reset client-published tracking for a screen.
  static void resetClientPublished(String scrName) {
    _lastPublishedKl.remove(scrName);
  }

  /// Parse the [txTypes] config: comma-separated list of active transaction
  /// button types. Absent or empty -> all 4 (backward-compat for deployments
  /// lacking the key). Order of entries = order of CTA buttons rendered.
  static List<String> parseTxTypes(dynamic component) {
    const List<String> defaultTypes = ['deliver', 'sale', 'purchase', 'refill'];
    final String raw = (component['txTypes'] ?? '').toString().trim();
    if (raw.isEmpty) return defaultTypes;
    final List<String> parsed = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parsed.isEmpty ? defaultTypes : parsed;
  }

  /// Parse the txOptions config field: ★-separated pairs of value◼Label.
  ///
  /// Input: raw string from component['txOptions'], e.g.
  ///   'buy◼Beli★refill◼Tukar★sale◼Jual'
  /// (may be server-encoded: _u25FC_ for ◼, _u2605_ for ★).
  ///
  /// Returns list of entries: key = tx value ('buy'), value = display label ('Beli').
  /// Empty or null input -> empty list.
  /// Length-guarded: each pair is split on ◼; missing label -> uses value.
  ///
  /// Convention #2: autheniumDecode before splitting on ◼/★.
  static List<MapEntry<String, String>> parseTxOptions(dynamic raw) {
    final String decoded = (autheniumDecode((raw ?? '').toString()) ?? '')
        .trim();
    if (decoded.isEmpty) return [];
    final List<String> pairs = decoded.split('\u{2605}'); // ★
    final List<MapEntry<String, String>> result = [];
    for (final String pair in pairs) {
      final List<String> parts = pair.split('\u{25FC}'); // ◼
      final String value = parts.isNotEmpty ? parts[0].trim() : '';
      final String label = parts.length > 1 ? parts[1].trim() : value;
      if (value.isNotEmpty) {
        result.add(MapEntry(value, label));
      }
    }
    return result;
  }

  /// Jual-putus test: any category that is not returnable is sold outright.
  /// Inverts the literal already used by the picker filter -- adds no new
  /// hardcoded string (spec §3). Blank/missing category => sell-outright
  /// (interview decision D2).
  static bool isSellOutright(String cat) => cat != 'returnable';

  /// Compute the "exchange" component of a pickup breakdown.
  /// Exchange = empties returned in exchange for drops = min(pd, pp).
  static int pickupExchange(int pd, int pp) => pd < pp ? pd : pp;

  /// Compute the "clearing" component of a pickup breakdown.
  /// Clearing = additional outstanding being cleared = max(0, pp - pd).
  static int pickupClearing(int pd, int pp) => pp > pd ? pp - pd : 0;

  /// Sort picker items: primary by [sortField] (numeric, via [coerceNum]),
  /// secondary by [nameField] (string, case-insensitive asc).
  /// When [sortField] is empty, sorts by name only (current default).
  /// Dart List.sort is unstable — the name tiebreak is mandatory.
  static void sortPickerItems(
    List<Map<String, dynamic>> items, {
    required String sortField,
    required String sortDir,
    required String nameField,
  }) {
    items.sort((a, b) {
      if (sortField.isNotEmpty) {
        final num va = coerceNum(a[sortField]);
        final num vb = coerceNum(b[sortField]);
        final int primary = sortDir == 'asc'
            ? va.compareTo(vb)
            : vb.compareTo(va);
        if (primary != 0) return primary;
      }
      // Tiebreak / default: name asc, case-insensitive.
      final String na = (a[nameField] ?? '').toString().trim().toLowerCase();
      final String nb = (b[nameField] ?? '').toString().trim().toLowerCase();
      return na.compareTo(nb);
    });
  }

  @override
  State<TaskItemBuilder> createState() => _TaskItemBuilderState();
}

class _TaskItemBuilderState extends State<TaskItemBuilder> {
  String _itemCode = ''; // item subscription code
  String _clientCode = ''; // stock_location subscription code
  String _cacheCode = ''; // asset_cache subscription code
  List<String> _textArray = [];

  /// Per-item price TextEditingControllers, keyed by item id (ii).
  /// Created on first render of each sale card, disposed on item removal
  /// or widget disposal. Keyed by ii (unique within a draft).
  final Map<String, TextEditingController> _priceControllers = {};

  @override
  void initState() {
    super.initState();
    TaskItemBuilder.registerScreenSession();
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

  /// Text slot accessors.
  ///  [0] "Tambah Item"
  ///  [1] (reserved)
  ///  [2] "Refill"
  ///  [3] "Jual"
  ///  [4] "Beli"
  ///  [5] "Kosong"
  ///  [6] "Penuh"
  ///  [7] "Air RO"
  ///  [8] "Isi Ulang"
  ///  [9] "Pilih Produk"
  ///  [10] "Drop"
  ///  [11] "Pickup"
  ///  [12] "Hapus"
  ///  [13] "saran"
  ///  [14] "Harga"      (price input label)
  ///  [15] "Total"      (total Rp footer label)
  ///  [16] "Belum ada item"                      (empty state title)
  ///  [17] "Tambah item yang customer mau pesan"  (empty state subtitle)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'admin_create_task').toString().trim();

  /// Config: field name on the item catalog doc that holds the default price.
  /// Default 'harga' matches the live item collection schema.
  String get _itemPriceField =>
      (widget.component['itemPriceField'] ?? 'harga').toString().trim();

  /// Component mode: 'order' (default, admin create-task), 'walkin' (POS),
  /// 'supplier' (supplier transaction), or 'seed' (seed saldo awal).
  String get _mode =>
      (widget.component['mode'] ?? 'order').toString().trim().toLowerCase();

  /// Config: field name on the item catalog doc that holds the walkin default
  /// price. Default 'hrg' matches the new master item field for POS pricing.
  /// Only read when _mode == 'walkin'; order mode uses _itemPriceField.
  String get _priceSourceField =>
      (widget.component['priceSourceField'] ?? 'hrg').toString().trim();

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // 1. item collection (product catalog)
    final String rawItemTable = (widget.component['itemTable'] ?? '')
        .toString()
        .trim();
    if (rawItemTable.isNotEmpty) {
      final TablePath itp = parseTablePath(rawItemTable);
      if (itp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _itemCode = '$appVid/${itp.tableDocId}/${itp.subColl}';
        subscribeToMapCollection(
          appVid,
          itp.tableDocId,
          itp.subColl,
          _itemCode,
        );
      }
    }

    // 2. stock_location (resolve kl -> kn/al)
    final String rawClientTable = (widget.component['clientTable'] ?? '')
        .toString()
        .trim();
    if (rawClientTable.isNotEmpty) {
      final TablePath ctp = parseTablePath(rawClientTable);
      if (ctp.tableDocId.isNotEmpty) {
        _clientCode = '$appVid/${ctp.tableDocId}/${ctp.subColl}';
        subscribeToMapCollection(
          appVid,
          ctp.tableDocId,
          ctp.subColl,
          _clientCode,
        );
      }
    }

    // 3. asset_cache (Model B outstanding)
    final String rawCacheTable = (widget.component['outstandingTable'] ?? '')
        .toString()
        .trim();
    if (rawCacheTable.isNotEmpty) {
      final TablePath atp = parseTablePath(rawCacheTable);
      if (atp.tableDocId.isNotEmpty) {
        _cacheCode = '$appVid/${atp.tableDocId}/${atp.subColl}';
        subscribeToMapCollection(
          appVid,
          atp.tableDocId,
          atp.subColl,
          _cacheCode,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _priceControllers.values) {
      c.dispose();
    }
    _priceControllers.clear();
    super.dispose();
  }

  /// Resolve {kl} from screenTx, look up stock_location to get kn/al,
  /// republish all three as bare screenTx keys AND mirror the resolved
  /// (authoritative) customer into the wizard draft.
  ///
  /// Re-fires whenever the active kl changes: on back-nav re-pick the page
  /// State is cached in linkElement and buildPage's clear hook does not run,
  /// so a one-shot latch would keep the previously-picked customer's kn/al and
  /// the next task would be written with a stale address (review C-1).
  void _republishClient() {
    if (_clientCode.isEmpty) return;

    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String kl = (screenTx['kl'] ?? '').toString().trim();
    if (kl.isEmpty) return;

    // Already published for THIS customer on this screen -> nothing to do.
    if (TaskItemBuilder._lastPublishedKl[widget.scrName] == kl) return;

    final List<Map<String, dynamic>> clientDocs =
        List<Map<String, dynamic>>.from(
          mapTableContent[_clientCode] ?? const [],
        );

    final String lvField = (widget.component['clientIdField'] ?? 'lv')
        .toString()
        .trim();
    final String nameField = (widget.component['clientNameField'] ?? 'ln')
        .toString()
        .trim();
    final String addrField = (widget.component['clientAddrField'] ?? 'al')
        .toString()
        .trim();
    final String picField = (widget.component['clientPicField'] ?? 'pic')
        .toString()
        .trim();

    String kn = '';
    String al = '';
    String pic = '';
    bool found = false;
    for (final Map<String, dynamic> doc in clientDocs) {
      if ((doc[lvField] ?? '').toString().trim() == kl) {
        kn = (doc[nameField] ?? '').toString().trim();
        al = (doc[addrField] ?? '').toString().trim();
        pic = (doc[picField] ?? '').toString().trim();
        found = true;
        break;
      }
    }

    // Latch only once the client doc is actually loaded; otherwise let a later
    // build (after the collection streams in) resolve the real kn/al instead
    // of latching empty values for this kl.
    if (!found) return;

    TaskItemBuilder._lastPublishedKl[widget.scrName] = kl;

    final String wizardKey = (widget.component['wizardKey'] ?? '')
        .toString()
        .trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'kl': kl, 'kn': kn, 'al': al})),
      );
      // Mirror the resolved customer into the wizard draft so P4 submit +
      // task_draft_info read a complete, current-customer record and never mix
      // a stale screenTx address from a previously-picked customer (C-1).
      if (wizardKey.isNotEmpty) {
        AdminCreateTaskSupport.setCustomer(
          wizardKey,
          kl: kl,
          kn: kn,
          al: al,
          pic: pic,
        );
        TaskItemBuilder.draftRev.value++;
      }
    });
  }

  /// Show the product picker bottom-sheet. Filters item catalog by category,
  /// excludes items already in the draft.
  void _showProductPicker(BuildContext context, String txType) {
    final List<Map<String, dynamic>> itemDocs = List<Map<String, dynamic>>.from(
      mapTableContent[_itemCode] ?? const [],
    );

    final String idField = (widget.component['itemIdField'] ?? 'ii')
        .toString()
        .trim();
    final String nameField = (widget.component['itemNameField'] ?? 'in')
        .toString()
        .trim();
    final String catField = (widget.component['itemCatField'] ?? 'ic')
        .toString()
        .trim();

    final String searchField;
    {
      final String raw = (widget.component['searchField'] ?? '')
          .toString()
          .trim();
      searchField = raw.isNotEmpty ? raw : nameField;
    }
    final String searchHint;
    {
      final String raw = (widget.component['searchHint'] ?? '')
          .toString()
          .trim();
      searchHint = raw.isNotEmpty ? raw : 'Cari...';
    }
    final String emptyText;
    {
      final String raw = (widget.component['emptyText'] ?? '')
          .toString()
          .trim();
      emptyText = raw.isNotEmpty ? raw : 'Semua item sudah ditambahkan';
    }
    final String sortField;
    {
      final String raw = (widget.component['sortField'] ?? '')
          .toString()
          .trim();
      sortField = raw;
    }
    final String sortDir;
    {
      final String raw = (widget.component['sortDir'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      sortDir = raw.isNotEmpty ? raw : 'desc';
    }

    // Filter by category based on tx type.
    // Supplier/seed mode: no category filter (all items available).
    final String targetCat;
    if (_mode == 'supplier' || _mode == 'seed') {
      targetCat = '';
    } else {
      switch (txType) {
        case 'deliver':
          // ponytail: all categories; consumable pick → sale override in onPick
          targetCat = '';
          break;
        case 'purchase':
          targetCat = 'returnable';
          break;
        case 'sale':
          targetCat = ''; // all categories
          break;
        case 'refill':
          targetCat = 'returnable'; // refill = water galon (returnable)
          break;
        default:
          targetCat = '';
      }
    }

    // Exclude items already in draft
    final List<DraftItem> currentDraft = AdminCreateTaskSupport.getDraft(
      _wizardKey,
    );
    final Set<String> inDraft = currentDraft.map((d) => d.ii).toSet();

    final List<Map<String, dynamic>> available = itemDocs.where((doc) {
      final String ii = (doc[idField] ?? '').toString().trim();
      if (ii.isEmpty || inDraft.contains(ii)) return false;
      if (targetCat.isNotEmpty) {
        final String cat = (doc[catField] ?? '').toString().trim();
        if (cat != targetCat) return false;
      }
      return true;
    }).toList();

    // Sort: primary by sortField (numeric) if present, tiebreak name asc.
    TaskItemBuilder.sortPickerItems(
      available,
      sortField: sortField,
      sortDir: sortDir,
      nameField: nameField,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ProductPickerSheet(
        items: available,
        idField: idField,
        nameField: nameField,
        catField: catField,
        title: _t(9, 'Pilih Produk'),
        searchField: searchField,
        searchHint: searchHint,
        emptyText: emptyText,
        onPick: (Map<String, dynamic> item) {
          Navigator.of(context).pop(); // close sheet

          // Determine effective tx: a non-returnable ("sell outright") item
          // picked from the deliver picker becomes a jual-putus sale.
          // Detection via configured catField (never literal 'ic'); blank
          // category => sell-outright (isSellOutright, decision D2).
          final String addTx;
          final bool isConsumable;
          if (_mode == 'supplier') {
            final List<MapEntry<String, String>> opts =
                TaskItemBuilder.parseTxOptions(widget.component['txOptions']);
            addTx = opts.isNotEmpty ? opts[0].key : 'buy';
            isConsumable = false;
          } else {
            final String pickedCat = (item[catField] ?? '').toString().trim();
            // ponytail: only the deliver picker can surface consumables
            // (purchase/refill filter to returnable at the query level).
            isConsumable =
                txType == 'deliver' &&
                TaskItemBuilder.isSellOutright(pickedCat);
            addTx = isConsumable ? 'sale' : txType;
          }

          // Seed price: supplier from priceSourceField, sale from the mode's
          // price field. Keys off the EFFECTIVE tx (addTx) so a consumable
          // override (addTx=='sale') still seeds. Convention #7: coerceNum
          // guards the dynamic field.
          final int seedPrice;
          if (_mode == 'supplier') {
            seedPrice = coerceNum(item[_priceSourceField]).toInt();
          } else if (addTx == 'sale') {
            final String priceField = _mode == 'walkin'
                ? _priceSourceField
                : _itemPriceField;
            seedPrice = coerceNum(item[priceField]).toInt();
          } else {
            seedPrice = 0;
          }

          _addItem(
            ii: (item[idField] ?? '').toString().trim(),
            itemName: (item[nameField] ?? '').toString().trim(),
            tx: addTx,
            hg: seedPrice,
            consumable: isConsumable,
          );
        },
      ),
    );
  }

  void _addItem({
    required String ii,
    required String itemName,
    required String tx,
    int hg = 0,
    bool consumable = false,
  }) {
    final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
    if (_mode == 'seed') {
      // Seed: single qty (ps), fixed cd='full', no price, no conditions.
      // tx='seed' is an internal marker (not serialized to li[] output).
      draft.add(DraftItem(ii: ii, itemName: itemName, tx: 'seed', ps: 1));
    } else if (_mode == 'supplier') {
      // Supplier: all tx types carry price. qo/qi default 0 (user sets via
      // steppers). No condition/water concepts.
      draft.add(DraftItem(ii: ii, itemName: itemName, tx: tx, hg: hg));
    } else {
      // Order / walkin: existing logic unchanged.
      // ponytail: consumable sale -> no condition, floor qty 1 (like walkin).
      final String defaultCdo = consumable
          ? ''
          : ((tx == 'deliver' || tx == 'sale') ? 'full' : '');
      final String defaultCdi = tx == 'deliver'
          ? 'empty'
          : (tx == 'purchase' ? 'full' : '');
      final String defaultWt = tx == 'refill' ? 'refill' : '';
      final int seedPs = (tx == 'sale' && (_mode == 'walkin' || consumable))
          ? 1
          : 0;
      draft.add(
        DraftItem(
          ii: ii,
          itemName: itemName,
          tx: tx,
          ps: seedPs,
          cdo: defaultCdo,
          cdi: defaultCdi,
          wt: defaultWt,
          hg: tx == 'sale' ? hg : 0,
        ),
      );
    }
    TaskItemBuilder.draftRev.value++;
    setState(() {});
  }

  void _removeItem(int index) {
    final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
    if (index >= 0 && index < draft.length) {
      final String ii = draft[index].ii;
      draft.removeAt(index);
      // Clean up price controller if one was created for this item
      _priceControllers[ii]?.dispose();
      _priceControllers.remove(ii);
      TaskItemBuilder.draftRev.value++;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch revision signal (cross-widget reactivity)
      TaskItemBuilder.draftRev.value;

      // Touch subscribed data to register Obx deps
      mapTableContent[_itemCode];
      mapTableContent[_clientCode];
      mapTableContent[_cacheCode];

      // Republish client info (once)
      _republishClient();

      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final TaskTotals totals = AdminCreateTaskSupport.computeTotals(draft);

      // Load asset_cache for Model B
      final List<Map<String, dynamic>> cacheDocs =
          List<Map<String, dynamic>>.from(
            mapTableContent[_cacheCode] ?? const [],
          );
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
      final String kl = (screenTx['kl'] ?? '').toString().trim();

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
            if (draft.isEmpty)
              _buildEmptyState(context)
            else ...[
              // Item cards
              for (int i = 0; i < draft.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildItemCard(context, draft[i], i, cacheDocs, kl),
              ],
              // CTA buttons
              const SizedBox(height: 16),
              _buildCtaRow(context),
              // Footer summary
              const SizedBox(height: 16),
              _buildFooterSummary(totals),
            ],
          ],
        ),
      );
    });
  }

  /// Centered empty-state card: icon + text + CTA buttons.
  /// CTA set gated by the same txTypes config as _buildCtaRow.
  Widget _buildEmptyState(BuildContext context) {
    // Supplier/seed: single CTA, no per-tx buttons.
    if (_mode == 'supplier' || _mode == 'seed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD4D7DC)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('\u{1F4E6}', style: TextStyle(fontSize: 32)), // box
            const SizedBox(height: 8),
            Text(
              _t(0, 'Barang'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _showProductPicker(context, ''),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  _t(1, '+ Barang'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTierColors.okAction,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // ponytail: walkin mode forces sale-only regardless of txTypes config.
    final List<String> types = _mode == 'walkin'
        ? const ['sale']
        : TaskItemBuilder.parseTxTypes(widget.component);
    final bool hasDeliver = types.contains('deliver');
    final List<String> secondaryTypes = types
        .where((t) => t != 'deliver')
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD4D7DC)), // borderStrong
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          const Text('\u{1F4E6}', style: TextStyle(fontSize: 32)), // 📦
          const SizedBox(height: 8),
          // Title
          Text(
            _t(16, 'Belum ada item'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A), // text-primary
            ),
          ),
          const SizedBox(height: 4),
          // Subtitle
          Text(
            _t(17, 'Tambah item yang customer mau pesan'),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8), // slate-400 (textDim)
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Primary CTA: deliver (filled blue button)
          if (hasDeliver)
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _showProductPicker(context, 'deliver'),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  _t(0, 'Tambah Item'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTierColors.okAction,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          // Secondary CTAs: other types (outline, per-type color)
          if (secondaryTypes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final String tx in secondaryTypes)
                  if (_ctaLabel(tx) != null)
                    _ctaButton(context, _ctaLabel(tx)!, tx),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    DraftItem item,
    int index,
    List<Map<String, dynamic>> cacheDocs,
    String kl,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)), // slate-200
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: name + tx chip + delete
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName.isNotEmpty ? item.itemName : item.ii,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B), // slate-800
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _txChip(item.tx),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ), // slate-400
                  onPressed: () => _removeItem(index),
                  tooltip: _t(12, 'Hapus'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Body: steppers + toggles per tx type
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildItemBody(context, item, index, cacheDocs, kl),
          ),
        ],
      ),
    );
  }

  Widget _buildItemBody(
    BuildContext context,
    DraftItem item,
    int index,
    List<Map<String, dynamic>> cacheDocs,
    String kl,
  ) {
    if (_mode == 'seed') {
      return _buildSeedBody(item, index);
    }
    if (_mode == 'supplier') {
      return _buildSupplierBody(item, index);
    }
    switch (item.tx) {
      case 'deliver':
        return _buildDeliverBody(item, index, cacheDocs, kl);
      case 'sale':
        return _buildSaleBody(item, index);
      case 'purchase':
        return _buildPurchaseBody(item, index);
      case 'refill':
        return _buildRefillBody(item, index);
      default:
        return _buildDeliverBody(item, index, cacheDocs, kl);
    }
  }

  Widget _buildDeliverBody(
    DraftItem item,
    int index,
    List<Map<String, dynamic>> cacheDocs,
    String kl,
  ) {
    // Model B suggested pickup -- DISPLAY ONLY (hint + breakdown). Drop and
    // Pickup are fully independent; this never auto-sets item.pp.
    final int? suggested = AdminCreateTaskSupport.suggestPickup(
      pd: item.pd,
      assetCacheDocs: cacheDocs,
      clientLv: kl,
      itemIi: item.ii,
      condition: item.cdo.isNotEmpty ? item.cdo : 'full',
    );
    final bool suggestionActive = suggested != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Condition toggles (cdo / cdi)
        _conditionToggle(
          label: _t(10, 'Drop'),
          value: item.cdo,
          onChanged: (v) {
            setState(() {
              item.cdo = v;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
        const SizedBox(height: 8),
        // Drop stepper
        _labeledStepper(
          label: _t(10, 'Drop'),
          value: item.pd,
          onDecrement: item.pd > 0
              ? () {
                  setState(() {
                    item.pd--;
                  });
                  TaskItemBuilder.draftRev.value++;
                }
              : null,
          onIncrement: () {
            setState(() {
              item.pd++;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
        const SizedBox(height: 8),
        _conditionToggle(
          label: _t(11, 'Pickup'),
          value: item.cdi,
          onChanged: (v) {
            setState(() {
              item.cdi = v;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
        const SizedBox(height: 8),
        // Pickup stepper
        _labeledStepper(
          label: _t(11, 'Pickup'),
          value: item.pp,
          onDecrement: item.pp > 0
              ? () {
                  setState(() {
                    item.pp--;
                  });
                  TaskItemBuilder.draftRev.value++;
                }
              : null,
          onIncrement: () {
            setState(() {
              item.pp++;
            });
            TaskItemBuilder.draftRev.value++;
          },
          hint: suggestionActive ? '${_t(13, 'saran')}: $suggested' : null,
        ),
        // Pickup breakdown box (display only, when pp > 0)
        if (item.pp > 0) ...[
          const SizedBox(height: 8),
          _pickupBreakdownBox(item.pd, item.pp),
        ],
      ],
    );
  }

  /// Violet info box showing the pickup breakdown: exchange + clearing = pp.
  /// Shown in deliver cards when pp > 0.
  Widget _pickupBreakdownBox(int pd, int pp) {
    final int exchange = TaskItemBuilder.pickupExchange(pd, pp);
    final int clearing = TaskItemBuilder.pickupClearing(pd, pp);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: const Color(0xFFF5F3FF), // violet-50
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(
                width: 3,
                color: const Color(0xFFA78BFA), // violet-400
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      const Row(
                        children: [
                          Text(
                            '\u{2191} ', // ↑
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6D28D9), // violet-700
                            ),
                          ),
                          Text(
                            'Pickup breakdown:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6D28D9),
                            ),
                          ),
                        ],
                      ),
                      // Exchange line
                      if (exchange > 0) ...[
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '\u{2022} ', // •
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6D28D9),
                              ),
                            ),
                            Text(
                              '$exchange exchange ',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6D28D9),
                              ),
                            ),
                            const Text(
                              '(kosong dari order)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569), // textMid
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Clearing line
                      if (clearing > 0) ...[
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '\u{2022} ', // •
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6D28D9),
                              ),
                            ),
                            Text(
                              '$clearing clearing ',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6D28D9),
                              ),
                            ),
                            const Text(
                              '(outstanding lama)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Total line
                      const SizedBox(height: 2),
                      Text(
                        '= $pp total pickup',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6D28D9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaleBody(DraftItem item, int index) {
    final bool isWalkin = _mode == 'walkin';
    // Consumable-sale (order mode) carries no condition (cdo==''); a
    // returnable-sale always has cdo=='full'|'empty' (the toggle offers only
    // those). The !isWalkin term is defensive redundancy (W1): walkin sale
    // already seeds cdo=='full', so cdo.isEmpty is already false for walkin.
    final bool isConsumable = !isWalkin && item.cdo.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Condition toggle (full/empty) -- order-mode returnable sale only.
        // Walkin POS + consumable have no returnable condition concept.
        if (!isWalkin && !isConsumable) ...[
          _conditionToggle(
            label: _t(3, 'Jual'),
            value: item.cdo,
            onChanged: (v) {
              setState(() {
                item.cdo = v;
              });
              TaskItemBuilder.draftRev.value++;
            },
          ),
          const SizedBox(height: 8),
        ],
        _labeledStepper(
          label: isWalkin ? _t(2, 'Qty') : _t(3, 'Jual'),
          value: item.ps,
          onDecrement: item.ps > ((isWalkin || isConsumable) ? 1 : 0)
              ? () {
                  setState(() {
                    item.ps--;
                  });
                  TaskItemBuilder.draftRev.value++;
                }
              : null,
          onIncrement: () {
            setState(() {
              item.ps++;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
        // Price + subtotal: skip for consumable (price silently carried in hg;
        // CF DeliveryInvoice prices from item.hrg regardless).
        if (!isConsumable) ...[
          const SizedBox(height: 8),
          // Inline price input (sale only)
          _priceInput(item),
          // Per-line subtotal
          if (item.ps > 0 && item.hg > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${item.ps} x ${AdminCreateTaskSupport.formatRupiah(item.hg)} = ${AdminCreateTaskSupport.formatRupiah(item.hg * item.ps)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B), // slate-500
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPurchaseBody(DraftItem item, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _conditionToggle(
          label: _t(4, 'Beli'),
          value: item.cdi,
          onChanged: (v) {
            setState(() {
              item.cdi = v;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
        const SizedBox(height: 8),
        _labeledStepper(
          label: _t(4, 'Beli'),
          value: item.pb,
          onDecrement: item.pb > 0
              ? () {
                  setState(() {
                    item.pb--;
                  });
                  TaskItemBuilder.draftRev.value++;
                }
              : null,
          onIncrement: () {
            setState(() {
              item.pb++;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
      ],
    );
  }

  Widget _buildRefillBody(DraftItem item, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _waterToggle(
          value: item.wt,
          onChanged: (v) {
            setState(() {
              item.wt = v;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
        const SizedBox(height: 8),
        _labeledStepper(
          label: _t(2, 'Refill'),
          value: item.pr,
          onDecrement: item.pr > 0
              ? () {
                  setState(() {
                    item.pr--;
                  });
                  TaskItemBuilder.draftRev.value++;
                }
              : null,
          onIncrement: () {
            setState(() {
              item.pr++;
            });
            TaskItemBuilder.draftRev.value++;
          },
        ),
      ],
    );
  }

  // ── Supplier body (per-line tx selector + qty steppers + price) ─────
  Widget _buildSupplierBody(DraftItem item, int index) {
    final List<MapEntry<String, String>> txOpts =
        TaskItemBuilder.parseTxOptions(widget.component['txOptions']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // TX selector (segmented chips) -- only when >1 option
        if (txOpts.length > 1) ...[
          _txOptionSelector(item, txOpts),
          const SizedBox(height: 8),
        ],
        // Qty steppers based on selected tx
        if (item.tx == 'buy') ...[
          // Buy: qi (masuk) only
          _labeledStepper(
            label: _t(3, 'Masuk'),
            value: item.qi,
            onDecrement: item.qi > 0
                ? () {
                    setState(() {
                      item.qi--;
                    });
                    TaskItemBuilder.draftRev.value++;
                  }
                : null,
            onIncrement: () {
              setState(() {
                item.qi++;
              });
              TaskItemBuilder.draftRev.value++;
            },
          ),
        ] else if (item.tx == 'refill') ...[
          // Refill: qo (keluar) + qi (masuk)
          _labeledStepper(
            label: _t(2, 'Keluar'),
            value: item.qo,
            onDecrement: item.qo > 0
                ? () {
                    setState(() {
                      item.qo--;
                    });
                    TaskItemBuilder.draftRev.value++;
                  }
                : null,
            onIncrement: () {
              setState(() {
                item.qo++;
              });
              TaskItemBuilder.draftRev.value++;
            },
          ),
          const SizedBox(height: 8),
          _labeledStepper(
            label: _t(3, 'Masuk'),
            value: item.qi,
            onDecrement: item.qi > 0
                ? () {
                    setState(() {
                      item.qi--;
                    });
                    TaskItemBuilder.draftRev.value++;
                  }
                : null,
            onIncrement: () {
              setState(() {
                item.qi++;
              });
              TaskItemBuilder.draftRev.value++;
            },
          ),
        ] else if (item.tx == 'sale') ...[
          // Sale: qo (keluar) only
          _labeledStepper(
            label: _t(2, 'Keluar'),
            value: item.qo,
            onDecrement: item.qo > 0
                ? () {
                    setState(() {
                      item.qo--;
                    });
                    TaskItemBuilder.draftRev.value++;
                  }
                : null,
            onIncrement: () {
              setState(() {
                item.qo++;
              });
              TaskItemBuilder.draftRev.value++;
            },
          ),
        ],
        const SizedBox(height: 8),
        // Price input (all tx types in supplier mode).
        // labelIndex 4 = supplier text slot for "Harga".
        _priceInput(item, labelIndex: 4),
        // Per-line subtotal
        if (_supplierSubtotal(item) > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${_t(5, 'Subtotal')}: ${AdminCreateTaskSupport.formatRupiah(_supplierSubtotal(item))}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B), // slate-500
            ),
          ),
        ],
      ],
    );
  }

  // ── Seed body (single qty stepper, no price, no tx selector) ──────
  Widget _buildSeedBody(DraftItem item, int index) {
    return _labeledStepper(
      label: _t(2, 'Qty'),
      value: item.ps,
      onDecrement: item.ps > 0
          ? () {
              setState(() {
                item.ps--;
              });
              TaskItemBuilder.draftRev.value++;
            }
          : null,
      onIncrement: () {
        setState(() {
          item.ps++;
        });
        TaskItemBuilder.draftRev.value++;
      },
    );
  }

  /// Supplier per-line subtotal: hrg * max(qo, qi).
  int _supplierSubtotal(DraftItem item) {
    final int qty = item.qo > item.qi ? item.qo : item.qi;
    return item.hg * qty;
  }

  /// TX option selector: segmented chips parsed from txOptions config.
  /// Convention #2: autheniumDecode applied inside parseTxOptions.
  Widget _txOptionSelector(
    DraftItem item,
    List<MapEntry<String, String>> txOpts,
  ) {
    return Row(
      children: [
        for (int i = 0; i < txOpts.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _toggleChip(
            txOpts[i].value, // display label: 'Beli', 'Tukar', 'Jual'
            item.tx ==
                txOpts[i].key, // active: compare with 'buy', 'refill', 'sale'
            () {
              final String newTx = txOpts[i].key;
              setState(() {
                // Seed qo=qi ONCE on switching to refill (interview decision).
                if (newTx == 'refill' && item.tx != 'refill') {
                  item.qo = item.qi;
                }
                item.tx = newTx;
              });
              TaskItemBuilder.draftRev.value++;
            },
            activeColor: _supplierTxColor(txOpts[i].key),
          ),
        ],
      ],
    );
  }

  /// Per-tx accent color for supplier segmented chips.
  Color _supplierTxColor(String tx) {
    switch (tx) {
      case 'buy':
        return const Color(0xFF8B5CF6); // violet-500
      case 'refill':
        return const Color(0xFF047857); // emerald-700
      case 'sale':
        return const Color(0xFF0D9488); // teal-600
      default:
        return const Color(0xFF6B7280); // gray-500
    }
  }

  // ── Inline price input ──────────────────────────────────────────────
  Widget _priceInput(DraftItem item, {int labelIndex = 14}) {
    // Get-or-create controller for this item. Keyed by ii (unique in draft).
    // Created once, reused across Obx rebuilds, disposed on item removal.
    final TextEditingController controller = _priceControllers.putIfAbsent(
      item.ii,
      () => TextEditingController(text: item.hg > 0 ? item.hg.toString() : ''),
    );

    return Row(
      children: [
        Text(
          '${_t(labelIndex, 'Harga')}: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B), // slate-500
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'Rp ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ), // slate-800
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AdminTierColors.okAction),
                ),
                hintText: '0',
                hintStyle: const TextStyle(
                  color: Color(0xFFCBD5E1),
                ), // slate-300
              ),
              onChanged: (String v) {
                final int parsed = int.tryParse(v) ?? 0;
                item.hg = parsed;
                TaskItemBuilder.draftRev.value++;
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Condition toggle (full / empty) ──────────────────────────────────
  Widget _conditionToggle({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final String kosong = _t(5, 'Kosong');
    final String penuh = _t(6, 'Penuh');
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ), // slate-500
        const SizedBox(width: 8),
        _toggleChip(penuh, value == 'full', () => onChanged('full')),
        const SizedBox(width: 6),
        _toggleChip(kosong, value == 'empty', () => onChanged('empty')),
      ],
    );
  }

  // ── Water toggle (ro / refill) ───────────────────────────────────────
  Widget _waterToggle({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final String ro = _t(7, 'Air RO');
    final String isiUlang = _t(8, 'Isi Ulang');
    return Row(
      children: [
        const Text(
          'Jenis: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 8),
        _toggleChip(
          ro,
          value == 'ro',
          () => onChanged('ro'),
          activeColor: const Color(0xFF047857),
        ),
        const SizedBox(width: 6),
        _toggleChip(
          isiUlang,
          value != 'ro',
          () => onChanged('refill'),
          activeColor: const Color(0xFF047857),
        ),
      ],
    );
  }

  Widget _toggleChip(
    String label,
    bool active,
    VoidCallback onTap, {
    Color activeColor = const Color(0xFF0D9488),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? activeColor
              : const Color(0xFFF1F5F9), // active / slate-100
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF64748B), // slate-500
          ),
        ),
      ),
    );
  }

  // ── Labeled stepper (label + CustodyStepper) ─────────────────────────
  Widget _labeledStepper({
    required String label,
    required int value,
    required VoidCallback? onDecrement,
    required VoidCallback onIncrement,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CustodyStepper(
          value: value,
          onDecrement: onDecrement,
          onIncrement: onIncrement,
          min: 0,
          enabled: true,
          statusLine: hint != null
              ? Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF94A3B8),
                  ),
                ) // slate-400
              : null,
        ),
      ],
    );
  }

  // ── Tx type chip ─────────────────────────────────────────────────────
  Widget _txChip(String tx) {
    final String label;
    final Color bg;
    final bool isSupplier = _mode == 'supplier';
    switch (tx) {
      case 'deliver':
        label = 'ANTAR';
        bg = const Color(0xFF4F46E5); // indigo-600
        break;
      case 'buy':
        label = 'BELI';
        bg = const Color(0xFF8B5CF6); // violet-500
        break;
      case 'sale':
        label = isSupplier ? 'JUAL' : _t(3, 'Jual').toUpperCase();
        bg = const Color(0xFF0D9488); // teal-600 (sale)
        break;
      case 'purchase':
        label = _t(4, 'Beli').toUpperCase();
        bg = const Color(0xFF8B5CF6); // violet-500
        break;
      case 'refill':
        label = isSupplier ? 'TUKAR' : _t(2, 'Refill').toUpperCase();
        bg = const Color(0xFF047857); // emerald-700
        break;
      default:
        label = tx.toUpperCase();
        bg = const Color(0xFF6B7280); // gray-500
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: bg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── CTA row (add buttons) ────────────────────────────────────────────
  // Config-driven from txTypes: only types listed in the config get a button,
  // in the order they appear. Absent/empty txTypes -> all 4 (backward-compat).
  // Unknown types silently skipped (only known types have picker/card support).
  Widget _buildCtaRow(BuildContext context) {
    // Supplier/seed: single "+ Barang" button (tx is per-line, not per-picker).
    if (_mode == 'supplier' || _mode == 'seed') {
      final Color color = AdminTierColors.okAction;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _showProductPicker(context, ''),
            icon: Icon(Icons.add, size: 16, color: color),
            label: Text(
              _t(1, '+ Barang'),
              style: TextStyle(fontSize: 13, color: color),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
      );
    }
    // ponytail: walkin mode forces sale-only regardless of txTypes config.
    final List<String> types = _mode == 'walkin'
        ? const ['sale']
        : TaskItemBuilder.parseTxTypes(widget.component);
    final List<Widget> buttons = [];
    for (final String tx in types) {
      final String? label = _ctaLabel(tx);
      if (label == null) continue; // unknown type -> skip silently
      buttons.add(_ctaButton(context, label, tx));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  /// CTA button label for a known tx type, or null for unknown types.
  /// Label shape: deliver = bare text; sale/purchase/refill = "+ " prefix.
  String? _ctaLabel(String tx) {
    switch (tx) {
      case 'deliver':
        return _t(0, 'Tambah Item');
      case 'sale':
        return '+ ${_t(3, 'Jual')}';
      case 'purchase':
        return '+ ${_t(4, 'Beli')}';
      case 'refill':
        return '+ ${_t(2, 'Refill')}';
      default:
        return null;
    }
  }

  /// Per-type accent color for CTA buttons (both empty-state and filled-state).
  Color _ctaColor(String tx) {
    switch (tx) {
      case 'deliver':
        return AdminTierColors.okAction; // #2563EB
      case 'sale':
        return const Color(0xFF0D9488); // teal-600
      case 'refill':
        return const Color(0xFF047857); // emerald-700
      case 'purchase':
        return const Color(0xFF8B5CF6); // violet-500
      default:
        return const Color(0xFF6B7280); // gray fallback
    }
  }

  Widget _ctaButton(BuildContext context, String label, String txType) {
    final Color color = _ctaColor(txType);
    return OutlinedButton.icon(
      onPressed: () => _showProductPicker(context, txType),
      icon: Icon(Icons.add, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 13, color: color)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 44),
      ),
    );
  }

  // ── Footer summary ───────────────────────────────────────────────────
  Widget _buildFooterSummary(TaskTotals totals) {
    // Seed: show total qty count (not Rp).
    if (_mode == 'seed') {
      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final int totalQty = AdminCreateTaskSupport.computeSeedTotalQty(draft);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC), // slate-50
          borderRadius: BorderRadius.circular(8),
        ),
        child: _summaryPill('TOTAL $totalQty', AdminTierColors.okAction),
      );
    }
    // Supplier: show running total only (per-line subtotals are in each card).
    if (_mode == 'supplier') {
      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final int total = AdminCreateTaskSupport.computeSupplierTotal(draft);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC), // slate-50
          borderRadius: BorderRadius.circular(8),
        ),
        child: _summaryPill(
          '${_t(5, 'Subtotal')} ${AdminCreateTaskSupport.formatRupiah(total)}',
          AdminTierColors.okAction,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), // slate-50
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (totals.totalDrop > 0)
                _summaryPill(
                  '${_t(10, 'Drop')} ${totals.totalDrop}',
                  const Color(0xFF4F46E5),
                ), // indigo (was blue-500)
              if (totals.totalPickup > 0)
                _summaryPill(
                  '${_t(11, 'Pickup')} ${totals.totalPickup}',
                  const Color(0xFF6D28D9),
                ), // violet-700 (was violet-500)
              if (totals.totalSale > 0)
                _summaryPill(
                  '${_t(3, 'Jual')} ${totals.totalSale}',
                  const Color(0xFF0D9488),
                ), // teal (was amber-500)
              if (totals.totalPurchase > 0)
                _summaryPill(
                  '${_t(4, 'Beli')} ${totals.totalPurchase}',
                  const Color(0xFF8B5CF6),
                ), // violet-500 (unchanged)
              if (totals.totalRefill > 0)
                _summaryPill(
                  '${_t(2, 'Refill')} ${totals.totalRefill}',
                  const Color(0xFF047857),
                ), // emerald (was teal)
            ],
          ),
          // Total sale price (Rp)
          if (totals.totalSalePrice > 0) ...[
            const SizedBox(height: 8),
            _summaryPill(
              '${_t(15, 'Total')} ${AdminCreateTaskSupport.formatRupiah(totals.totalSalePrice)}',
              const Color(0xFF0D9488), // teal, matches Jual (was amber)
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
} // end _TaskItemBuilderState

// ── Product picker sheet (inline) ──────────────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({
    required this.items,
    required this.idField,
    required this.nameField,
    required this.catField,
    required this.title,
    required this.onPick,
    required this.searchField,
    required this.searchHint,
    required this.emptyText,
  });

  final List<Map<String, dynamic>> items;
  final String idField, nameField, catField, title;
  final ValueChanged<Map<String, dynamic>> onPick;
  final String searchField;
  final String searchHint;
  final String emptyText;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((doc) {
      if (_query.isEmpty) return true;
      final String val = (doc[widget.searchField] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return val.contains(_query.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1), // slate-300
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() {
                _query = v;
              }),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // List or empty state
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.emptyText,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final doc = filtered[i];
                      final String name = (doc[widget.nameField] ?? '')
                          .toString()
                          .trim();
                      final String cat = (doc[widget.catField] ?? '')
                          .toString()
                          .trim();
                      return ListTile(
                        title: Text(
                          name.isNotEmpty
                              ? name
                              : doc[widget.idField].toString(),
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: cat.isNotEmpty
                            ? Text(
                                cat,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              )
                            : null,
                        onTap: () => widget.onPick(doc),
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
