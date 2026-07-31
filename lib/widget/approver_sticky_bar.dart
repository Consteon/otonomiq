import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart';
import 'driver_home_support.dart'; // resolveAppVid, filterDriverHomeDocs
import 'dsl_eq.dart';
import 'ftz_row_of_button_2.dart';
import 'item_card_detail.dart';
import 'list_card_support.dart'; // GateSlotConfig, SlotTerms, parseGateSlot, parseSlotTerms, isVisibleBySlotGate
import 'panel_card_support.dart'; // TablePath, parseTablePath

dynamic _deepCopy(dynamic value) {
  if (value is Map) {
    return Map<dynamic, dynamic>.fromEntries(
      value.entries.map((e) => MapEntry(e.key, _deepCopy(e.value))),
    );
  }
  if (value is List) return value.map(_deepCopy).toList();
  return value;
}

bool evaluateRbtSearch(String searchStr, List<dynamic> row) {
  searchStr = autheniumDecode(searchStr) ?? searchStr;
  for (var part in searchStr.split('⭘')) {
    List<String> kv = part.split('◼');
    if (kv.length >= 2) {
      int? idx = int.tryParse(kv[0].trim());
      String val = kv[1].trim();
      if (idx == null || idx >= row.length) return false;
      if (!eq(row[idx].toString().trim().toUpperCase(), val.toUpperCase())) {
        return false;
      }
    }
  }
  return true;
}

class StickyBarConfig {
  final Map<dynamic, dynamic> component;
  final String scrName;
  final String type;
  final String? defaultStatus;
  final Key widgetKey;
  final bool dialog;
  final double lPad, tPad, rPad, bPad;

  StickyBarConfig({
    required this.component,
    required this.scrName,
    required this.type,
    this.defaultStatus,
    required this.widgetKey,
    this.dialog = false,
    this.lPad = 0,
    this.tPad = 0,
    this.rPad = 0,
    this.bPad = 0,
  });
}

class ApproverStickyBar {
  static final ValueNotifier<WidgetBuilder?> slot = ValueNotifier(null);
  static final ValueNotifier<bool> overlaysHidden = ValueNotifier(false);
  static final ValueNotifier<String> activeBarScreen = ValueNotifier('');
  static final ValueNotifier<int> version = ValueNotifier(0);

  static final Map<String, List<StickyBarConfig>> _configs = {};
  static bool _routeListenerAttached = false;

  /// Gate subscription codes, keyed by '$scrName#$position'. Set once per RBT
  /// slot in register() when gateTable is present. Read by _buildApproval to
  /// look up the mapTableContent key. Cleared by clearConfigs().
  ///
  /// Keyed by the composite (scrName + position), NOT scrName alone: one screen
  /// can carry several RBTs and register() dedups configs on `position`, so a
  /// screen-only key would collapse distinct RBTs into one subscription (W2).
  static final Map<String, String> _gateSubscriptions = {};

  static void ensureRouteListener() {
    if (_routeListenerAttached) return;
    _routeListenerAttached = true;
    try {
      final current = transactionStore.state.screenTx['#CURRENT_ROUTE'];
      if (current is String && current.isNotEmpty) {
        activeBarScreen.value = current;
      }
    } catch (_) {}
    transactionStore.onChange.listen((state) {
      final route = state.screenTx['#CURRENT_ROUTE'];
      if (route is String && route.isNotEmpty) {
        // onChange fires on EVERY dispatch (the store is not distinct), so
        // gate the clear on an actual route CHANGE — an unconditional clear
        // would wipe currentRow mid-screen on any #GPSDATA/timer dispatch and
        // blank the incident bar until the detail card happens to rebuild.
        if (route != activeBarScreen.value) {
          // Per-screen state cleared on route change: currentRow is a single
          // static Rx published by the leaving screen's detail card
          // (ItemCardDetail / WorkerCardDetailKeyed); left uncleared, the
          // previous worker's row leaks into the next screen's incident bar
          // until that screen's own publisher runs.
          ItemCardDetail.currentRow.value = const [];
        }
        activeBarScreen.value = route;
        ItemCardDetail.screenStatus.remove(route);
      }
    });
  }

  static void register({
    required String scrName,
    required Map component,
    required String type,
    String? defaultStatus,
    required Key widgetKey,
    bool dialog = false,
    double lPad = 0,
    double tPad = 0,
    double rPad = 0,
    double bPad = 0,
  }) {
    ensureRouteListener();
    final List<StickyBarConfig> list = _configs[scrName] ??= [];
    final copy = _deepCopy(component) as Map<dynamic, dynamic>;
    final newConfig = StickyBarConfig(
      component: copy,
      scrName: scrName,
      type: type,
      defaultStatus: defaultStatus,
      widgetKey: widgetKey,
      dialog: dialog,
      lPad: lPad,
      tPad: tPad,
      rPad: rPad,
      bPad: bPad,
    );
    // Idempotent registration. AnyPage (the page class for every non-home screen,
    // incl. approval) rebuilds via StoreConnector on EVERY Redux state change and
    // calls buildPage(clear:false) — which does NOT clearConfigs — and nested
    // clear:false builds (DisplayList widgetList, dialogs, bottom sheets) re-enter
    // here too. Appending blindly grows _configs[scrName] so StickyBarRenderer's
    // Column stacks N identical approve/reject bars (the iOS "stacked buttons"
    // bug; latent on Android, just fires less often). Dedup on the component's
    // stable slot ('position'): replace the existing config for that slot so an
    // updated component/status/padding takes effect, while keeping genuinely
    // distinct RBTs (different position) as separate bars. NOT widgetKey — that is
    // an ObjectKey over a freshly-interpolated "$scrName-$position" String, which
    // compares by identity and would never match across rebuilds.
    final dynamic pos = copy['position'];
    final int idx = pos == null
        ? -1
        : list.indexWhere((c) => c.component['position'] == pos);
    if (idx >= 0) {
      list[idx] = newConfig;
    } else {
      list.add(newConfig);
    }
    version.value++;

    // ── Gate subscription (once per RBT slot, idempotent) ─────────────────
    // Mirrors list_action_card.dart:407-415 (_subscribe from initState).
    // Kicked off here (not in build/_buildApproval) so no Firestore listener
    // is attached mid-build (W2). Keyed by '$scrName#$position' — one screen
    // can carry several RBTs and register() dedups configs on `position`
    // above, so a screen-only key would collapse distinct RBTs.
    final String gateSubKey = '$scrName#$pos';
    final String rawGateTable = (copy['gateTable'] ?? '').toString().trim();
    if (rawGateTable.isNotEmpty &&
        !_gateSubscriptions.containsKey(gateSubKey)) {
      final String appVid = resolveAppVid(copy);
      final TablePath gtp = parseTablePath(rawGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        final String gateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
        _gateSubscriptions[gateSubKey] = gateCode;
        subscribeToMapCollection(appVid, gtp.tableDocId, gtp.subColl, gateCode);
      }
    }
  }

  static void clearConfigs(String scrName) {
    _configs.remove(scrName);
    // Remove every gate subscription belonging to this screen. Keys are
    // '$scrName#$position' (one per RBT slot), so prefix-match on '$scrName#'
    // to clear them all on route change (W2).
    _gateSubscriptions.removeWhere((k, _) => k.startsWith('$scrName#'));
  }

  static List<StickyBarConfig>? getConfigs(String route) => _configs[route];

  static bool hasCommentInput(String scrName) {
    try {
      final children = screenUIComponent[scrName]?['children'] ?? [];
      for (final c in children) {
        if (c is Map) {
          final type = c['type']?.toString().toLowerCase() ?? '';
          final variant = c['variant']?.toString().toLowerCase() ?? '';
          if (type == 'txf' && variant == 'commentbox') return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

/// Renders bottom bar from stored config data — creates fresh deep copy each render.
class StickyBarRenderer extends StatelessWidget {
  const StickyBarRenderer({super.key, required this.configs});

  final List<StickyBarConfig> configs;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      List<Widget> bars = [];
      for (final config in configs) {
        Widget bar;
        if (config.type == 'approval') {
          bar = _buildApproval(config);
        } else {
          bar = _buildIncident(config);
        }
        bars.add(bar);
      }
      if (bars.isEmpty) return const SizedBox.shrink();
      return Column(mainAxisSize: MainAxisSize.min, children: bars);
    });
  }

  Widget _buildApproval(StickyBarConfig config) {
    // Observable read #1 — MUST stay first (Obx dep registration; zero-obs
    // crash guard). screenStatus is RxMap<String, String>.
    String s = ItemCardDetail.screenStatus[config.scrName] ?? '';
    if (config.defaultStatus != null && s != config.defaultStatus) {
      return const SizedBox.shrink();
    }

    // Observable read #2 — currentRow (Obx dep; repaints when detail card
    // publishes a new row or route change clears it).
    final List<dynamic> currentRow = ItemCardDetail.currentRow.value;

    // ── Slot gate (detail button gating) ──────────────────────────────────
    // Intent switch: gateTable absent → gating never requested → render
    // buttons unchanged (back-compat for every existing sticky bar).
    final String rawGateTable = (config.component['gateTable'] ?? '')
        .toString()
        .trim();
    if (rawGateTable.isNotEmpty) {
      try {
        // C1: empty currentRow → fail-closed. Covers direct navigation,
        // route change (cleared at approver_sticky_bar.dart:89), and the
        // window before ItemCardDetail publishes at item_card_detail.dart:358.
        if (currentRow.isEmpty) {
          devPrint(
            'StickyBar slot gate: currentRow empty '
            '→ buttons hidden (pre-publish or direct nav)',
          );
          return const SizedBox.shrink();
        }

        final String rawGateSearch = (config.component['gateSearch'] ?? '')
            .toString()
            .trim();
        final String rawRowSlot = (config.component['gateRowSlot'] ?? '')
            .toString()
            .trim();
        final String decodedRowSlot = autheniumDecode(rawRowSlot) ?? rawRowSlot;
        final GateSlotConfig gsc = parseGateSlot(decodedRowSlot);

        // Parse pointer/level as numeric row indexes. Same index base as the
        // RBT `search` key (evaluateRbtSearch, :19-33): 0-based into the
        // published row, NOT the ◁N▷/◀N▶ marker grammar.
        final int? pointerIdx = int.tryParse(gsc.pointerField);
        final int? levelIdx = int.tryParse(gsc.levelField);

        // All-or-nothing: intent declared (gateTable present) but config
        // incomplete → fail-closed (permission gate never fails open — F1).
        if (gsc.isEmpty ||
            rawGateSearch.isEmpty ||
            (pointerIdx == null && levelIdx == null)) {
          devPrint(
            'StickyBar slot gate: incomplete config — expected '
            'gateRowSlot as plain integers, e.g. sc◆5◆7 '
            '(gsc.isEmpty=${gsc.isEmpty} '
            'rawGateSearch.isEmpty=${rawGateSearch.isEmpty} '
            'pointerIdx=$pointerIdx levelIdx=$levelIdx) '
            '→ buttons hidden',
          );
          return const SizedBox.shrink();
        }

        // Length-guard: out-of-range OR negative index → fail-closed
        // (Convention 3 + W3: int.tryParse('-1') succeeds, so reject < 0 too,
        // else currentRow[-1] throws and the catch-all masks the bad config).
        if (pointerIdx != null &&
            (pointerIdx < 0 || pointerIdx >= currentRow.length)) {
          devPrint(
            'StickyBar slot gate: pointerIdx=$pointerIdx '
            'out of range for row.length=${currentRow.length} '
            '→ buttons hidden',
          );
          return const SizedBox.shrink();
        }
        if (levelIdx != null &&
            (levelIdx < 0 || levelIdx >= currentRow.length)) {
          devPrint(
            'StickyBar slot gate: levelIdx=$levelIdx '
            'out of range for row.length=${currentRow.length} '
            '→ buttons hidden',
          );
          return const SizedBox.shrink();
        }

        // Extract pointer/level from the DISPLAYED row.
        final String pointer = pointerIdx != null
            ? currentRow[pointerIdx].toString().trim()
            : '';
        final String level = levelIdx != null
            ? currentRow[levelIdx].toString().trim()
            : '';

        // Read gate subscription code (set by register()). Composite key
        // '$scrName#$position' matches the identity register() dedups on (W2).
        final String gateSubKey =
            '${config.scrName}#${config.component['position']}';
        final String gateCode =
            ApproverStickyBar._gateSubscriptions[gateSubKey] ?? '';
        if (gateCode.isEmpty) {
          devPrint(
            'StickyBar slot gate: no gate subscription for '
            '"$gateSubKey" → buttons hidden',
          );
          return const SizedBox.shrink();
        }

        // Observable read #3 — gate docs (registers Obx dep on
        // mapTableContent RxMap so the bar rebuilds when grants arrive).
        final List<Map<String, dynamic>> rawGateDocs =
            List<Map<String, dynamic>>.from(
              mapTableContent[gateCode] ?? const [],
            );

        // Filter by gateSearch → current user's grant docs.
        // filterDriverHomeDocs decodes + resolves {userVid} etc. internally
        // — do NOT pre-decode rawGateSearch (F6).
        final List<Map<String, dynamic>> matchedGrants = filterDriverHomeDocs(
          rawGateDocs,
          rawGateSearch,
          config.scrName,
        );

        if (matchedGrants.isEmpty) {
          devPrint(
            'StickyBar slot gate: no grant docs match gateSearch '
            '"$rawGateSearch" over ${rawGateDocs.length} gate docs '
            '(gateCode="$gateCode") → buttons hidden',
          );
          return const SizedBox.shrink();
        }

        // Parse slot terms (union across all matched grants).
        final Set<String> allConcrete = {};
        final Set<String> allWildcardLevels = {};
        for (final grantDoc in matchedGrants) {
          final String rawSlotVal = (grantDoc[gsc.slotField] ?? '')
              .toString()
              .trim();
          final SlotTerms terms = parseSlotTerms(rawSlotVal);
          allConcrete.addAll(terms.concrete);
          allWildcardLevels.addAll(terms.wildcardLevels);
        }

        if (!isVisibleBySlotGate(
          pointer,
          level,
          allConcrete,
          allWildcardLevels,
        )) {
          devPrint(
            'StickyBar slot gate: mismatch pointer="$pointer" '
            'level="$level" concrete=$allConcrete '
            'wildcardLevels=$allWildcardLevels → buttons hidden',
          );
          return const SizedBox.shrink();
        }
        devPrint(
          'StickyBar slot gate: PASS pointer="$pointer" '
          'level="$level" grants=${matchedGrants.length} '
          'concrete=$allConcrete wildcardLevels=$allWildcardLevels',
        );
      } catch (e) {
        // Permission gate — any error = fail-closed (F1).
        devPrint('StickyBar slot gate: error=$e → buttons hidden');
        return const SizedBox.shrink();
      }
    }

    final copy = _deepCopy(config.component) as Map<dynamic, dynamic>;
    return FtzRowOfButton2(
      key: config.widgetKey,
      component: copy,
      scrName: config.scrName,
      dialog: config.dialog,
      lPad: config.lPad,
      tPad: config.tPad,
      rPad: config.rPad,
      bPad: config.bPad,
    );
  }

  Widget _buildIncident(StickyBarConfig config) {
    List<dynamic> row = ItemCardDetail.currentRow.value;
    if (row.isEmpty) return const SizedBox.shrink();
    final copy = _deepCopy(config.component) as Map<dynamic, dynamic>;
    List<dynamic> allChildren = copy['children'] as List<dynamic>? ?? [];
    List<dynamic> visible = allChildren.where((child) {
      String cs = (child['search'] ?? '').toString().trim();
      if (cs.isEmpty) return true;
      return evaluateRbtSearch(cs, row);
    }).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    copy['children'] = visible;
    return FtzRowOfButton2(
      key: config.widgetKey,
      component: copy,
      scrName: config.scrName,
      dialog: config.dialog,
      lPad: config.lPad,
      tPad: config.tPad,
      rPad: config.rPad,
      bPad: config.bPad,
    );
  }
}

/// Minimal widget for slot mode (commentbox screens).
/// Reads config from ApproverStickyBar registry, passes to Timeline via slot.
class StickyBarSlot extends StatefulWidget {
  const StickyBarSlot({super.key, required this.scrName});

  final String scrName;

  @override
  State<StickyBarSlot> createState() => _StickyBarSlotState();
}

class _StickyBarSlotState extends State<StickyBarSlot> {
  WidgetBuilder? _registeredBuilder;

  void _registerSlot() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final configs = ApproverStickyBar.getConfigs(widget.scrName);
      if (configs == null || configs.isEmpty) return;
      _registeredBuilder = (_) => StickyBarRenderer(configs: configs);
      ApproverStickyBar.slot.value = _registeredBuilder;
    });
  }

  @override
  void initState() {
    super.initState();
    _registerSlot();
  }

  @override
  void didUpdateWidget(covariant StickyBarSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registerSlot();
  }

  @override
  void dispose() {
    if (ApproverStickyBar.slot.value == _registeredBuilder) {
      ApproverStickyBar.slot.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
