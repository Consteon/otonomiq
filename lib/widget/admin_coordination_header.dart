import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'admin_home_support.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// ADMIN_COORDINATION_HEADER -- identity bar for the Admin "Koordinasi" screen.
///
/// Displays: admin name (from #NAME) + 2 chips (N berjalan, N sinyal).
/// (Role label + "Ganti" runtime-switch button removed per design.)
///
/// Subscribes to: vehicle_check (for berjalan count), task + stock_location +
/// vehicle_check + evidence (for signal count, via deriveAdminSignals).
///
/// Pinned at top, not scrollable. Read-only: no txfController, no write.
class AdminCoordinationHeader extends StatefulWidget {
  const AdminCoordinationHeader({
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
  State<AdminCoordinationHeader> createState() =>
      _AdminCoordinationHeaderState();
}

class _AdminCoordinationHeaderState extends State<AdminCoordinationHeader> {
  List<String> _textArray = [];

  // Subscription codes
  String _taskCode = '';
  String _slCode = '';
  String _vcCode = '';
  String _evCode = '';

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

  /// Text slot accessors (slots [0] role + [1] switch no longer rendered):
  ///  [2] berjalan chip suffix (default "berjalan")
  ///  [3] sinyal chip suffix (default "sinyal")
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Task subscription
    final String rawTaskTable = (widget.component['taskTable'] ?? '')
        .toString()
        .trim();
    if (rawTaskTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTaskTable);
      if (tp.tableDocId.isNotEmpty) {
        // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
        _taskCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _taskCode);
      }
    }

    // Stock_location subscription
    final String rawSlTable = (widget.component['vehicleTable'] ?? '')
        .toString()
        .trim();
    if (rawSlTable.isNotEmpty) {
      final TablePath slp = parseTablePath(rawSlTable);
      if (slp.tableDocId.isNotEmpty) {
        _slCode = '$appVid/${slp.tableDocId}/${slp.subColl}';
        subscribeToMapCollection(appVid, slp.tableDocId, slp.subColl, _slCode);
      }
    }

    // Vehicle_check subscription
    final String rawVcTable = (widget.component['checkTable'] ?? '')
        .toString()
        .trim();
    if (rawVcTable.isNotEmpty) {
      final TablePath vcp = parseTablePath(rawVcTable);
      if (vcp.tableDocId.isNotEmpty) {
        _vcCode = '$appVid/${vcp.tableDocId}/${vcp.subColl}';
        subscribeToMapCollection(appVid, vcp.tableDocId, vcp.subColl, _vcCode);
      }
    }

    // Evidence subscription
    final String rawEvTable = (widget.component['evidenceTable'] ?? '')
        .toString()
        .trim();
    if (rawEvTable.isNotEmpty) {
      final TablePath evp = parseTablePath(rawEvTable);
      if (evp.tableDocId.isNotEmpty) {
        _evCode = '$appVid/${evp.tableDocId}/${evp.subColl}';
        subscribeToMapCollection(appVid, evp.tableDocId, evp.subColl, _evCode);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Obx(() {
      // Touch reactive deps to register Obx dependency
      final List<Map<String, dynamic>> tasks = List<Map<String, dynamic>>.from(
        mapTableContent[_taskCode] ?? const [],
      );
      final List<Map<String, dynamic>> stockLocations =
          List<Map<String, dynamic>>.from(mapTableContent[_slCode] ?? const []);
      final List<Map<String, dynamic>> vehicleChecks =
          List<Map<String, dynamic>>.from(mapTableContent[_vcCode] ?? const []);
      final List<Map<String, dynamic>> evidenceDocs =
          List<Map<String, dynamic>>.from(mapTableContent[_evCode] ?? const []);

      // Admin name from #NAME
      final String adminName = (transactionStore.state.screenTx['#NAME'] ?? '')
          .toString()
          .trim();

      // Berjalan count
      final String todayStr = todayEpochMidnightWib();
      final int berjalanCount = countBerjalan(
        vehicleChecks,
        todayStr: todayStr,
      );

      // Signal count (same helper as coordinationSignalList)
      final List<Signal> signals = deriveAdminSignals(
        tasks: tasks,
        stockLocations: stockLocations,
        vehicleChecks: vehicleChecks,
        evidenceDocs: evidenceDocs,
        todayStr: todayStr,
      );
      final int sinyalCount = signals.length;

      // Labels
      final String berjalanSuffix = _t(2, 'berjalan');
      final String sinyalSuffix = _t(3, 'sinyal');

      // Resolve plate from stock_location via plateSearch. Degrade-safe: no
      // plateSearch config, no match, or empty `ln` -> name alone (no plate
      // subline). Lifted out of the old inline Builder so the identity row can
      // render it as a dedicated secondary line.
      String plate = '';
      final String rawPlateSearch = (widget.component['plateSearch'] ?? '')
          .toString()
          .trim();
      if (rawPlateSearch.isNotEmpty && stockLocations.isNotEmpty) {
        final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
          stockLocations,
          rawPlateSearch,
          widget.scrName,
        );
        if (matched.isNotEmpty) {
          plate = (matched.first['ln'] ?? '').toString().trim();
        }
      }

      // Monogram = first code point of the admin name (surrogate-safe, no
      // `characters` import dependency).
      final String monogram = adminName.isNotEmpty
          ? String.fromCharCode(adminName.runes.first).toUpperCase()
          : '';

      // Depth via the white-label primaryColor only -> derive a darker foot for
      // the gradient + a soft shadow so the bar reads as a floating "command"
      // panel rather than a flat fill. No hardcoded brand blue.
      final Color barTop = theme.primaryColor;
      final Color barBottom =
          Color.lerp(theme.primaryColor, Colors.black, 0.18) ?? barTop;
      final Color shadowColor =
          (Color.lerp(theme.primaryColor, Colors.black, 0.45) ?? Colors.black)
              .withValues(alpha: 0.30);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Full-bleed gradient: breaks out of the body ListView padding
          // (lPad/rPad/tPad — same systemUIComponent['Mobile'] source the
          // widget is handed) via NEGATIVE Positioned offsets, which are legal
          // where a negative Container/Padding margin asserts. The body
          // ListView clips to the full viewport (padding moved onto
          // ListView.padding in main_page.dart), so this reaches the screen
          // edges and sits flush under the AppBar.
          Positioned(
            left: -widget.lPad,
            right: -widget.rPad,
            top: -widget.tPad,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [barTop, barBottom],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          // Content sits at the normal inset (the ListView padding) -> already
          // padded lPad/rPad/tPad in from the full-bleed gradient edges.
          // width:infinity forces the Stack (and thus the gradient) to span the
          // full item width; the extra top/bottom are breathing room.
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 10, 0, widget.bPad + 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Identity row: monogram tile + name (+ optional plate subline).
                  if (adminName.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            monogram,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.0,
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
                                adminName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                  height: 1.15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (plate.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.local_shipping_rounded,
                                      size: 13,
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        plate,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(
                                            alpha: 0.78,
                                          ),
                                          letterSpacing: 0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Status LEDs: live "berjalan" (green, gently pulsing when active)
                  // + attention-aware "sinyal" (amber when pending, muted when clear).
                  Row(
                    children: [
                      _buildStatusChip(
                        count: berjalanCount,
                        label: berjalanSuffix,
                        tier: berjalanCount > 0
                            ? _ChipTier.active
                            : _ChipTier.calm,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(
                        count: sinyalCount,
                        label: sinyalSuffix,
                        tier: sinyalCount > 0
                            ? _ChipTier.attention
                            : _ChipTier.calm,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Status chip with a leading "LED" dot whose colour encodes state. Meaning is
  /// never colour-only: the numeric count + suffix label always carry the
  /// semantics. The count is emphasised over the label for scannability.
  Widget _buildStatusChip({
    required int count,
    required String label,
    required _ChipTier tier,
  }) {
    final (Color dotColor, Color bgColor, Color borderColor) = switch (tier) {
      _ChipTier.active => (
        const Color(0xFF4ADE80), // green-400, bright on blue
        Colors.white.withValues(alpha: 0.12),
        Colors.white.withValues(alpha: 0.16),
      ),
      _ChipTier.attention => (
        const Color(0xFFFBBF24), // amber-400
        const Color(0xFFFBBF24).withValues(alpha: 0.20),
        const Color(0xFFFBBF24).withValues(alpha: 0.55),
      ),
      _ChipTier.calm => (
        Colors.white.withValues(alpha: 0.45),
        Colors.white.withValues(alpha: 0.10),
        Colors.white.withValues(alpha: 0.14),
      ),
    };

    return Semantics(
      label: '$count $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulseDot(color: dotColor, active: tier == _ChipTier.active),
            const SizedBox(width: 7),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$count',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  TextSpan(
                    text: ' $label',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visual tier for a header status chip.
enum _ChipTier { active, attention, calm }

/// A small "LED" status dot. When [active] (and the platform is not in
/// reduced-motion), a soft ring breathes outward to convey a live, real-time
/// state; otherwise it renders as a calm static dot with a faint glow. Owns its
/// own controller so it survives the parent's `Obx` rebuilds and disposes
/// cleanly.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  static const double _core = 8;

  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // Construct eagerly here (element is mounting → createTicker is safe).
    // A lazy `late final ... = AnimationController(...)` would defer creation
    // to first access; an inactive dot never touches _c until dispose(), which
    // then builds a controller on a deactivated element and crashes.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final Widget dot = Container(
      width: _core,
      height: _core,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: widget.color.withValues(alpha: 0.55), blurRadius: 6),
        ],
      ),
    );

    if (!widget.active || reduceMotion) {
      return SizedBox(width: _core, height: _core, child: dot);
    }

    return SizedBox(
      width: _core,
      height: _core,
      child: AnimatedBuilder(
        animation: _c,
        child: dot,
        builder: (context, child) {
          final double t = _c.value;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: (1 - t) * 0.45,
                child: Container(
                  width: _core + _core * 0.7 * t,
                  height: _core + _core * 0.7 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color, width: 1.2),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
      ),
    );
  }
}
