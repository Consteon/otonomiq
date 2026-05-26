import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart';
import 'ftz_row_of_button_2.dart';
import 'item_card_detail.dart';

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
      if (row[idx].toString().trim().toUpperCase() != val.toUpperCase()) {
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
    _configs[scrName] ??= [];
    _configs[scrName]!.add(StickyBarConfig(
      component: _deepCopy(component) as Map<dynamic, dynamic>,
      scrName: scrName,
      type: type,
      defaultStatus: defaultStatus,
      widgetKey: widgetKey,
      dialog: dialog,
      lPad: lPad,
      tPad: tPad,
      rPad: rPad,
      bPad: bPad,
    ));
    version.value++;
  }

  static void clearConfigs(String scrName) {
    _configs.remove(scrName);
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
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: bars,
      );
    });
  }

  Widget _buildApproval(StickyBarConfig config) {
    String s = ItemCardDetail.screenStatus[config.scrName] ?? '';
    if (config.defaultStatus != null && s != config.defaultStatus) {
      return const SizedBox.shrink();
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
