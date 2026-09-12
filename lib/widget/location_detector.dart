import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../global.dart';
import '../model/otq_state.dart';
import '../page/map_page.dart';
import '../theme_tokens.dart';

class LocationDetector extends StatefulWidget {
  const LocationDetector({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final bool single;

  @override
  State<LocationDetector> createState() => _LocationDetectorState();
}

class _LocationDetectorState extends State<LocationDetector>
    with SingleTickerProviderStateMixin {
  late List<String> _texts;
  late Map<String, dynamic> _gps;
  late bool _showViewMap;
  late bool _showRefresh;
  late double _borderRadius;

  String? _address;
  double? _lat;
  double? _lng;
  double? _accuracy;
  DateTime? _lastUpdated;
  String _gpsStatus = 'last_known';
  bool _isLoading = false;

  /// Server-driven look. Absent -> the original card, unchanged. Only `v4`
  /// opts a screen in to the redesign, so a tenant that never edits its
  /// screen JSON keeps exactly what it has. Same idiom as every other
  /// variant widget in the repo (display_list.dart:59, selectable_btn.dart:52).
  late String _variant;

  /// v6 keeps the v4 card -- there is no separate v6 card design, the v6
  /// mockup's home panel IS this one -- and additionally opts the map screen
  /// behind "Lihat Peta" into its redesign. So a tenant on `v4` sees nothing
  /// change, and moving that one cell to `v6` keeps the panel it already
  /// approved while the map stops being a red pin on a purple FAB.
  bool get _isV4 => _variant == 'v4' || _isV6;
  bool get _isV6 => _variant == 'v6';

  /// The one automatic motion the v4 system allows: the status dot's pulse.
  /// Only built for v4, and stopped outright under `disableAnimations` -- a
  /// repeating controller keeps requesting frames even with nothing listening.
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _texts = diamondTextToList(widget.component['text'] as String? ?? '');
    _gps = (widget.component['gps'] as Map?)?.cast<String, dynamic>() ?? {};
    _gpsStatus = _gps['status'] as String? ?? 'last_known';
    _showViewMap =
        (widget.component['showViewMap']?.toString().toUpperCase() ?? 'TRUE') !=
        'FALSE';
    _showRefresh =
        (widget.component['showRefresh']?.toString().toUpperCase() ?? 'TRUE') !=
        'FALSE';
    _borderRadius =
        (widget.component['borderRadius'] as num?)?.toDouble() ?? 10;
    _variant = (widget.component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (_isV4) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      );
    }
    _fetchLocationData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not available in initState, so the reduced-motion decision
    // lands here -- and re-lands if the user flips the OS setting.
    final AnimationController? pulse = _pulse;
    if (pulse == null) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      pulse.stop();
    } else if (!pulse.isAnimating) {
      pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  Future<void> _fetchLocationData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final otqState = await OtqState().setAllDataAsync();
      if (!otqState.gpsOn) throw Exception('Location not available');
      final lat = otqState.latitude;
      final lng = otqState.longitude;
      final status = _deriveGpsStatus(otqState);

      String address;
      if (status == 'inside') {
        address = _getInsideLocationName(otqState) ?? _fallbackAddress;
      } else {
        try {
          final parts = [
            otqState.subLocality,
            otqState.locality.replaceFirst(RegExp(r'^[Kk]ecamatan\s+'), ''),
            otqState.subAdministrativeArea.replaceFirst(
              RegExp(r'^([Kk]abupaten|[Kk]ota)\s+'),
              '',
            ),
            otqState.postalCode,
          ].where((s) => s.isNotEmpty).toList();
          address = parts.isNotEmpty ? parts.join(', ') : _fallbackAddress;
        } catch (_) {
          address = _fallbackAddress;
        }
      }

      if (mounted) {
        setState(() {
          _lat = lat;
          _lng = lng;
          _address = address;
          _accuracy = otqState.accuracy;
          _lastUpdated = DateTime.now();
          _gpsStatus = status;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _address = _fallbackAddress;
          _isLoading = false;
        });
      }
    }
  }

  String? _getInsideLocationName(dynamic position) {
    try {
      final dynamic lqrList = transactionStore.state.screenTx['#LQR_LIST'];
      if (lqrList == null || lqrList is! Map || lqrList.isEmpty) return null;
      String? nearestName;
      double minDistance = double.infinity;
      for (final entry in lqrList.values) {
        final e = entry as List;
        final double targetLat = (e[1] as num).toDouble();
        final double targetLng = (e[2] as num).toDouble();
        final double tolerance = (e[3] as num).toDouble();
        final double zone2 = tolerance + (position.accuracy as double) * 2;
        final double distance = Geolocator.distanceBetween(
          targetLat,
          targetLng,
          position.latitude,
          position.longitude,
        );
        if (distance <= zone2 && distance < minDistance) {
          minDistance = distance;
          nearestName = e[0].toString();
        }
      }
      return nearestName;
    } catch (_) {
      return null;
    }
  }

  String _deriveGpsStatus(dynamic position) {
    try {
      final dynamic lqrList = transactionStore.state.screenTx['#LQR_LIST'];
      if (lqrList == null || lqrList is! Map || lqrList.isEmpty) {
        return _gps['status'] as String? ?? 'last_known';
      }
      double minDistance = double.infinity;
      double matchZone2 = 0;
      for (final entry in lqrList.values) {
        final e = entry as List;
        final double targetLat = (e[1] as num).toDouble();
        final double targetLng = (e[2] as num).toDouble();
        final double tolerance = (e[3] as num).toDouble();
        final double zone2 = tolerance + position.accuracy * 2;
        final double distance = Geolocator.distanceBetween(
          targetLat,
          targetLng,
          position.latitude,
          position.longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
          matchZone2 = zone2;
        }
      }
      return minDistance <= matchZone2 ? 'inside' : 'outside';
    } catch (_) {
      return _gps['status'] as String? ?? 'last_known';
    }
  }

  String _deriveAccuracyLevel() {
    if (_accuracy == null) return '';
    if (_accuracy! <= 15) return 'high';
    if (_accuracy! <= 30) return 'medium';
    return 'stale';
  }

  // Relative time is the one string in this widget that does NOT come from
  // `text`, so it is written in the app's language directly. Every tenant on
  // this component gets Indonesian; if one ever needs another language the
  // fix is five more `text` slots (11-15), not a second hardcoded set.
  String get _formattedUpdatedAt {
    if (_lastUpdated == null) return '';
    final seconds = DateTime.now().difference(_lastUpdated!).inSeconds;
    if (seconds < 10) return 'baru saja';
    if (seconds < 60) return '$seconds detik lalu';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes menit lalu';
    return '${minutes ~/ 60} jam lalu';
  }

  String get _fallbackAddress =>
      _texts.length > 10 ? _texts[10] : 'Location not found';

  Future<void> _openMap() async {
    if (_lat == null || _lng == null) {
      await _fetchLocationData();
    }
    if (!mounted || _lat == null || _lng == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPage(
          lat: _lat!,
          lng: _lng!,
          title: _texts.isNotEmpty ? _texts[0] : 'Location Detection',
          variant: _variant,
          accuracy: _accuracy,
        ),
      ),
    );
    // The map screen has its own Perbarui, and the user may have walked while
    // it was open. v6 re-reads the fix on the way back so the card cannot show
    // a status the map already contradicted. Classic keeps its old behaviour.
    if (_isV6 && mounted) await _fetchLocationData();
  }

  /// [onDark] selects the dot palette. The on-dark set clears 3:1 for a mark
  /// but NOT 4.5:1 for text (measured on `#0B6E80`: 3.87 / 5.07 / 3.11), which
  /// is why the label itself is never colour-coded -- the wording already says
  /// Inside / Outside / Near Boundary, so meaning never rests on colour.
  _StatusConfig _statusConfig(bool onDark) {
    switch (_gpsStatus) {
      case 'inside':
        return _StatusConfig(
          label: _texts.length > 1 ? _texts[1] : 'Inside Site',
          dot: onDark ? OtqPalette.successOnDark : OtqPalette.successText,
        );
      case 'outside':
        return _StatusConfig(
          label: _texts.length > 2 ? _texts[2] : 'Outside Site',
          dot: onDark ? OtqPalette.dangerOnDark : OtqPalette.dangerText,
        );
      case 'near_boundary':
        return _StatusConfig(
          label: _texts.length > 3 ? _texts[3] : 'Near Boundary',
          dot: onDark ? OtqPalette.warningOnDark : OtqPalette.warningText,
        );
      case 'last_known':
      default:
        return _StatusConfig(
          label: _texts.length > 3 ? _texts[3] : 'Last Known',
          dot: onDark
              ? Colors.white.withValues(alpha: 0.55)
              : OtqPalette.mutedFg,
        );
    }
  }

  String _accuracyLabel() {
    switch (_deriveAccuracyLevel()) {
      case 'high':
        return _texts.length > 4 ? _texts[4] : 'High Accuracy';
      case 'medium':
      case 'stale':
        return _texts.length > 5 ? _texts[5] : 'Low Accuracy';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) =>
      _isV4 ? _buildV4(context) : _buildClassic(context);

  // ---------------------------------------------------------------------
  // Classic — what every screen without `variant: "v4"` still renders.
  // Structurally identical to what shipped before; only the colours moved,
  // and only because five of them failed WCAG (see OtqPalette).
  // ---------------------------------------------------------------------
  Widget _buildClassic(BuildContext context) {
    const Color fg = OtqPalette.foreground;
    const Color mutedFg = OtqPalette.mutedFg;
    final config = _statusConfig(false);
    final updatedAt = _formattedUpdatedAt;
    final Color accuracyFg = _isLowAccuracy ? OtqPalette.warningText : mutedFg;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadius),
        border: Border.all(color: OtqPalette.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: mutedFg),
              const SizedBox(width: 6),
              Text(
                (_texts.isNotEmpty ? _texts[0] : 'LOCATION').toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: mutedFg,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The dot carries the colour; the label stays in `fg`.
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: config.dot,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                config.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_isLoading)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else
            Text(
              _address ?? '--',
              style: const TextStyle(fontSize: 14, color: fg),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          if (_accuracy != null)
            Row(
              children: [
                Icon(Icons.bolt, size: 14, color: accuracyFg),
                const SizedBox(width: 4),
                Text(
                  _accuracyText,
                  style: TextStyle(fontSize: 12, color: accuracyFg),
                ),
                const SizedBox(width: 8),
                const Text('·', style: TextStyle(color: mutedFg)),
                const SizedBox(width: 8),
                Text(
                  'Diperbarui $updatedAt',
                  style: const TextStyle(fontSize: 12, color: mutedFg),
                ),
              ],
            ),
          if (_showViewMap || _showRefresh) ...[
            const SizedBox(height: 12),
            const Divider(color: OtqPalette.border, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_showViewMap)
                  Expanded(
                    child: _cardButton(
                      onPressed: _openMap,
                      icon: Icons.map_outlined,
                      label: _texts.length > 8 ? _texts[8] : 'View Map',
                      fg: fg,
                      fill: const Color(0xFFF2F6F7),
                    ),
                  ),
                if (_showViewMap && _showRefresh) const SizedBox(width: 8),
                if (_showRefresh)
                  Expanded(
                    child: _cardButton(
                      onPressed: _fetchLocationData,
                      icon: Icons.refresh,
                      label: _texts.length > 9 ? _texts[9] : 'Refresh',
                      fg: fg,
                      fill: const Color(0xFFF2F6F7),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // v4 — the design-system panel. Same data, same `text` indexes, same GPS
  // logic; only the arrangement changes. Index 0 ("Location") is unused
  // here: v4 drops the small header label and leads with the status.
  // ---------------------------------------------------------------------
  Widget _buildV4(BuildContext context) {
    // Same colour as the app bar, by construction rather than by copying a
    // hex: main_page.dart paints the bar with Theme.of(context).primaryColor,
    // which vertriz_app.dart fills from the tenant's theme doc. Read it the
    // same way and the panel can never drift out of sync with the bar.
    final Color cardBg = Theme.of(context).primaryColor;
    // Measured rather than assumed: a tenant whose primaryColor is light
    // would otherwise get white text at 2-3:1.
    final Color fg = otqOn(cardBg);
    final bool onDark = fg == Colors.white;
    final Color fgMuted = onDark
        ? Colors.white.withValues(alpha: 0.86)
        : OtqPalette.mutedFg;
    final config = _statusConfig(onDark);

    return CustomPaint(
      // The panel meets the screen edges and the app bar, as in the v4 mockup.
      // It PAINTS past its box instead of resizing it: the page applies its
      // padding on the ListView, and a widget cannot lay itself out wider than
      // the constraints it is handed without an overflow warning. Painting is
      // free of that, and the viewport clips anything that runs off-screen.
      painter: BleedPainter(color: cardBg, inset: _pageInset()),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _pulseDot(config.dot),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              config.label,
                              style: TextStyle(
                                // 20, a deliberate step below MASTER's 24: still
                                // 1.25x the 16px address and 700 against 500, so
                                // the hierarchy stays unambiguous while the panel
                                // stops dominating the screen.
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: fg,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (_isLoading)
                        SizedBox(
                          height: 21,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: fgMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        Text(
                          _address ?? '--',
                          style: TextStyle(
                            // Stays 16: ui-ux-pro-max flags anything smaller as
                            // body text on mobile. Height comes off the padding
                            // and the controls, never off the address.
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                            color: fgMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (_showViewMap) ...[
                  const SizedBox(width: 12),
                  _glassButton(
                    onPressed: _openMap,
                    icon: Icons.map_outlined,
                    label: _texts.length > 8 ? _texts[8] : 'View Map',
                    fg: fg,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_accuracy != null) _accuracyChip(fg, fgMuted),
                if (_showRefresh) _refreshLink(fgMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// How far the page's own padding insets this widget, so the panel knows
  /// how far to paint back out. Read from the same Mobile config the page
  /// reads (main_page.dart:223); anything missing or malformed means 0, i.e.
  /// no bleed, never a crash.
  EdgeInsets _pageInset() {
    double read(String key) {
      try {
        final dynamic v = systemUIComponent?['Mobile']?[key];
        return v is num ? v.toDouble() : 0.0;
      } catch (_) {
        return 0.0;
      }
    }

    return EdgeInsets.only(
      left: read('leftPad'),
      right: read('rightPad'),
      top: read('topPad'),
    );
  }

  /// Status dot with the v4 system's single automatic motion: a ring that
  /// scales out and fades. [_pulse] is null (and the ring absent) whenever
  /// the OS asks for reduced motion.
  Widget _pulseDot(Color color) {
    final Widget dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    final AnimationController? pulse = _pulse;
    if (pulse == null || !pulse.isAnimating) return dot;
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: pulse,
              builder: (BuildContext context, Widget? child) {
                final double t = pulse.value;
                return Opacity(
                  opacity: (0.7 * (1 - t)).clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.55 + t * 1.05, child: child),
                );
              },
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
            ),
            dot,
          ],
        ),
      ),
    );
  }

  /// Glass action sitting beside the status. 48dp tall: the mockup's 44dp
  /// relies on an invisible hit area that has no equivalent here.
  Widget _glassButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color fg,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        // 40 to look at, 48 to hit: `padded` grows the tap target to the
        // Android minimum without inflating the pill -- the same trick the
        // mockup pulls with its invisible `.hit` area.
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Accuracy pill. The fill is a DARK tint, not a white one: a white tint
  /// over the teal raises background luminance and drops `warningOnDark` to
  /// 3.84:1. Over `rgba(15,42,51,.22)` it measures 6.26:1.
  Widget _accuracyChip(Color fg, Color fgMuted) {
    final Color chipFg = _isLowAccuracy ? OtqPalette.warningOnDark : fg;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        // v6 `.chip-on-primary`: no fill, a 1 dp ring at 40% of the chip's own
        // text colour (`inset 0 0 0 1px rgba(254,240,138,.4)`). The ring
        // follows [chipFg] rather than being pinned to the warning yellow, so
        // the good-accuracy chip outlines itself in the panel foreground
        // instead of claiming a warning colour it has not earned.
        //
        // Dropping the old 22% #0F2A33 fill costs almost nothing in contrast:
        // the yellow label measures 13.14:1 on the filled chip and 12.98:1 on
        // the bare navy panel. The ring itself lands at 3.0:1, which clears the
        // non-text bar — and it is decoration, not the boundary of a control:
        // this chip is not tappable.
        color: Colors.transparent,
        border: Border.all(color: chipFg.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 13, color: chipFg),
          const SizedBox(width: 4),
          Text(
            _accuracyText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: chipFg,
            ),
          ),
        ],
      ),
    );
  }

  /// "Updated ..." doubles as the refresh control, as in the mockup. The
  /// `Refresh` label (text index 9) becomes its accessible name, so the
  /// control is still announced by what it DOES, not by its timestamp.
  Widget _refreshLink(Color fgMuted) {
    return Semantics(
      button: true,
      label: _texts.length > 9 ? _texts[9] : 'Refresh',
      child: TextButton.icon(
        onPressed: _fetchLocationData,
        icon: const Icon(Icons.refresh, size: 15),
        label: Text(
          'Diperbarui $_formattedUpdatedAt',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: TextButton.styleFrom(
          foregroundColor: fgMuted,
          // Sized so the chip and this link share ONE Wrap row at typical
          // widths; the Wrap still reflows to two on a narrow phone rather
          // than clipping, per the text-reflow rule.
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  bool get _isLowAccuracy {
    final String level = _deriveAccuracyLevel();
    return level == 'medium' || level == 'stale';
  }

  String get _accuracyText =>
      '${_accuracyLabel()} ${_texts.length > 6 ? _texts[6] : '±'}'
      '${_accuracy!.round()}${_texts.length > 7 ? _texts[7] : 'm'}';

  /// Filled, borderless, 48dp-tall action.
  ///
  /// Replaces an `OutlinedButton` whose `#D1D5DB` border measured 1.47:1 (below
  /// the 3:1 a control boundary needs) and whose `vertical: 10` padding could
  /// land the whole target under the 48dp Android minimum.
  Widget _cardButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color fg,
    required Color fill,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: fill,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Paints the v4 surface out past the widget's own box by [inset], so the
/// panel reads as one block with the app bar instead of a card floating
/// inside the page padding. Bottom corners are rounded, top corners square --
/// the panel continues the bar rather than sitting under it.
class BleedPainter extends CustomPainter {
  const BleedPainter({required this.color, required this.inset});

  final Color color;
  final EdgeInsets inset;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(
      -inset.left,
      -inset.top,
      size.width + inset.left + inset.right,
      size.height + inset.top,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        bottomLeft: const Radius.circular(24),
        bottomRight: const Radius.circular(24),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(BleedPainter old) =>
      old.color != color || old.inset != inset;
}

class _StatusConfig {
  final String label;

  /// Colour of the status MARK only, never of [label]. See [_statusConfig].
  final Color dot;
  const _StatusConfig({required this.label, required this.dot});
}
