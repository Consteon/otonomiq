import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../global.dart';
import '../theme_tokens.dart';
import 'map_page_support.dart';

/// Why the map cannot be drawn at all. Both land on the same empty state, only
/// the wording and the settings screen differ.
enum _MapBlock { serviceOff, permissionDenied }

class MapPage extends StatefulWidget {
  final double lat;
  final double lng;
  final String title;

  /// Server-driven look, passed through from the component that opened this
  /// screen. `v6` selects the Vertika v6 layout; absent or anything else keeps
  /// the classic screen byte-for-byte. Same idiom as `ftz_scanner_screen.dart`
  /// and `photo_camera.dart`.
  final String variant;

  /// The caller's last accuracy reading, in metres. v6 opens with the fix the
  /// `LocationDetector` card already paid for instead of spending a second
  /// GPS acquisition on the same position; null means "no fix yet" and the
  /// sheet opens in its searching state.
  final double? accuracy;

  const MapPage({
    super.key,
    required this.lat,
    required this.lng,
    required this.title,
    this.variant = '',
    this.accuracy,
  }) : assert(lat >= -90 && lat <= 90, 'lat must be in [-90, 90]'),
       assert(lng >= -180 && lng <= 180, 'lng must be in [-180, 180]');

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  late final MapController _mapController;
  late LatLng _currentPoint;
  bool _isRefreshing = false;

  // ── v6 only ──────────────────────────────────────────────────────────
  double? _accuracy;
  LqrSite? _site;
  DateTime? _lastUpdated;
  bool _hasFix = false;
  _MapBlock? _blocked;

  /// Whether the camera still follows the position. Any pan by hand turns it
  /// off, which is what makes the "centre on me" control worth having.
  bool _follow = true;

  bool get _isV6 => widget.variant.trim().toLowerCase() == 'v6';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentPoint = LatLng(widget.lat, widget.lng);
    if (_isV6) {
      _accuracy = widget.accuracy;
      _hasFix = widget.accuracy != null;
      _lastUpdated = _hasFix ? DateTime.now() : null;
      _site = _resolveSite(_currentPoint);
      WidgetsBinding.instance.addObserver(this);
      unawaited(_checkAvailability());
    }
  }

  @override
  void dispose() {
    if (_isV6) WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  /// Location services and the location permission are exactly what the user
  /// went to Settings to change, so the empty state re-tests both on resume
  /// instead of stranding them on a screen that is no longer true.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isV6 && state == AppLifecycleState.resumed && _blocked != null) {
      unawaited(_checkAvailability());
    }
  }

  /// The geofence is re-resolved on every fix: walking between two registered
  /// sites must move the ring, not keep the one that was nearest at open.
  LqrSite? _resolveSite(LatLng at) {
    try {
      return nearestLqrSite(
        transactionStore.state.screenTx['#LQR_LIST'],
        at.latitude,
        at.longitude,
      );
    } catch (_) {
      // transactionStore is declared `dynamic`; a missing store must not take
      // the map down with it.
      return null;
    }
  }

  /// Location services and permission are the two reasons this screen can have
  /// nothing to show. Both are checked before the first acquisition, and again
  /// after a failed refresh, so a user who turns GPS off mid-session gets the
  /// empty state rather than a Perbarui button that quietly does nothing.
  Future<void> _checkAvailability({bool thenFetch = true}) async {
    _MapBlock? blocked;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        blocked = _MapBlock.serviceOff;
      } else {
        final LocationPermission permission =
            await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          blocked = _MapBlock.permissionDenied;
        }
      }
    } catch (_) {
      blocked = null; // Never block the map on a failed probe.
    }
    if (!mounted) return;
    setState(() => _blocked = blocked);
    if (blocked == null && thenFetch && !_hasFix) {
      await _refreshLocation();
    }
  }

  Future<void> _refreshLocation() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final newPoint = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentPoint = newPoint;
          _isRefreshing = false;
          if (_isV6) {
            _accuracy = position.accuracy;
            _hasFix = true;
            _lastUpdated = DateTime.now();
            _site = _resolveSite(newPoint);
            _blocked = null;
          }
        });
        if (!_isV6) {
          _mapController.move(newPoint, 16);
        } else if (_follow) {
          _mapController.move(newPoint, _currentZoom(17));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isRefreshing = false);
      // A refusal here is nearly always services-off or a revoked permission.
      if (_isV6) await _checkAvailability(thenFetch: false);
    }
  }

  /// `camera` throws until the map has laid itself out once.
  double _currentZoom(double fallback) {
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return fallback;
    }
  }

  // ── Derived state (v6) ───────────────────────────────────────────────

  double? get _distanceToCentre => (_site == null || !_hasFix)
      ? null
      : distanceToSite(_site!, _currentPoint.latitude, _currentPoint.longitude);

  MapFixStatus get _status => mapFixStatus(
    distance: _distanceToCentre,
    radius: _site?.radius,
    accuracy: _hasFix ? _accuracy : null,
  );

  bool get _accuracyIsLow =>
      _hasFix && _accuracy != null && _accuracy! > kLowAccuracyMeters;

  bool get _accuracyIsCoarse =>
      _hasFix && _accuracy != null && _accuracy! > kCoarseAccuracyMeters;

  /// Relative time, hardcoded Indonesian for the same reason the v6 scanner's
  /// hint is: no `text` slot exists for it and no tenant varies it.
  String get _updatedLabel {
    if (_lastUpdated == null) return '';
    final int seconds = DateTime.now().difference(_lastUpdated!).inSeconds;
    if (seconds < 10) return 'Diperbarui baru saja';
    if (seconds < 60) return 'Diperbarui $seconds detik lalu';
    final int minutes = seconds ~/ 60;
    if (minutes < 60) return 'Diperbarui $minutes menit lalu';
    return 'Diperbarui ${minutes ~/ 60} jam lalu';
  }

  @override
  Widget build(BuildContext context) =>
      _isV6 ? _buildV6(context) : _buildClassic();

  // ── Classic — every caller that does not pass `variant: "v6"` ────────

  Widget _buildClassic() {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: _currentPoint, initialZoom: 16),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.consteon.widgetdev',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _currentPoint,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        shape: CircleBorder(),
        onPressed: _refreshLocation,
        tooltip: 'Refresh lokasi',
        child: _isRefreshing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.red,
                ),
              )
            : const Icon(Icons.refresh),
      ),
    );
  }

  // ── v6 ───────────────────────────────────────────────────────────────

  Widget _buildV6(BuildContext context) {
    final Color primary = Theme.of(context).primaryColor;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: Colors.white,
              ),
            ),
            Text(
              _barSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
          ],
        ),
      ),
      body: _blocked != null ? _blockedTree(primary) : _mapTree(primary),
    );
  }

  String get _barSubtitle {
    final String name = _site?.name.trim() ?? '';
    return name.isEmpty ? 'area absen' : '$name · area absen';
  }

  Widget _mapTree(Color primary) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _map(primary)),
        Positioned(left: 12, top: 12, child: _legend(primary)),
        Positioned(right: 12, top: 12, child: _controls(primary)),
        Positioned(left: 0, right: 0, bottom: 0, child: _sheet(primary)),
      ],
    );
  }

  Widget _map(Color primary) {
    final bool outside = _status == MapFixStatus.outside;
    final LatLng? centre = _site == null
        ? null
        : LatLng(_site!.lat, _site!.lng);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: centre ?? _currentPoint,
        initialZoom: 16,
        onPositionChanged: (MapCamera camera, bool hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
        onMapReady: _fitAll,
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.consteon.widgetdev',
        ),
        if (centre != null)
          CircleLayer<Object>(
            circles: <CircleMarker<Object>>[
              CircleMarker<Object>(
                point: centre,
                radius: _site!.radius,
                useRadiusInMeter: true,
                color: outside
                    ? OtqPalette.v6DangerMark.withValues(alpha: 0.06)
                    : primary.withValues(alpha: 0.10),
                // Outside, the ring is redrawn dashed by the polyline below —
                // two borders on the same circle would read as a second fence.
                borderColor: outside ? Colors.transparent : primary,
                borderStrokeWidth: outside ? 0 : 2,
              ),
            ],
          ),
        if (centre != null && outside)
          PolylineLayer<Object>(
            polylines: <Polyline<Object>>[
              Polyline<Object>(
                points: _ring(centre, _site!.radius),
                color: primary,
                strokeWidth: 2,
                // Not `const`: the ctor's own assert reads `segments.length`.
                pattern: StrokePattern.dashed(segments: const <double>[6, 4]),
              ),
            ],
          ),
        if (_hasFix && _accuracy != null)
          CircleLayer<Object>(
            circles: <CircleMarker<Object>>[
              CircleMarker<Object>(
                point: _currentPoint,
                radius: _accuracy!,
                useRadiusInMeter: true,
                color: _accuracyIsCoarse
                    ? OtqPalette.warningText.withValues(alpha: 0.10)
                    : OtqPalette.v6Secondary.withValues(alpha: 0.14),
                borderColor: _accuracyIsCoarse
                    ? OtqPalette.warningText.withValues(alpha: 0.45)
                    : OtqPalette.v6Secondary.withValues(alpha: 0.50),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        MarkerLayer(
          markers: <Marker>[
            if (centre != null) _siteMarker(centre, primary),
            if (_hasFix) _meMarker(),
          ],
        ),
      ],
    );
  }

  /// The dashed geofence ring. `CircleMarker` has no dash pattern, so the
  /// outside state draws the same circle as a 72-segment polyline.
  List<LatLng> _ring(LatLng centre, double radius) {
    const Distance distance = Distance();
    return <LatLng>[
      for (int i = 0; i <= 72; i++) distance.offset(centre, radius, i * 5.0),
    ];
  }

  Marker _siteMarker(LatLng centre, Color primary) {
    final String name = _site?.name.trim() ?? '';
    return Marker(
      point: centre,
      width: 160,
      height: 46,
      // The pin's tip is its bottom edge, so the whole box sits above the
      // point rather than straddling it.
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (name.isNotEmpty)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
          Icon(Icons.place, size: 24, color: primary),
        ],
      ),
    );
  }

  Marker _meMarker() {
    return Marker(
      point: _currentPoint,
      width: 26,
      height: 26,
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: OtqPalette.v6Secondary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Two chips naming the two objects on the map. Excluded from semantics on
  /// purpose: the sheet below states the same thing in sentences.
  Widget _legend(Color primary) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _legendChip(
            const BoxDecoration(
              color: OtqPalette.v6Secondary,
              shape: BoxShape.circle,
            ),
            'Anda',
          ),
          const SizedBox(width: 6),
          _legendChip(
            BoxDecoration(
              color: primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: primary, width: 1.5),
            ),
            'Area absen',
          ),
        ],
      ),
    );
  }

  Widget _legendChip(BoxDecoration mark, String label) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: OtqPalette.foreground.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 10, height: 10, decoration: mark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OtqPalette.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(Color primary) {
    return Column(
      children: <Widget>[
        _roundButton(
          icon: Icons.my_location,
          label: 'Pusatkan ke posisi saya',
          selected: _follow,
          primary: primary,
          onTap: _hasFix
              ? () {
                  setState(() => _follow = true);
                  _mapController.move(_currentPoint, 17);
                }
              : null,
        ),
        const SizedBox(height: 8),
        _roundButton(
          icon: Icons.crop_free,
          label: 'Tampilkan seluruh area absen',
          selected: false,
          primary: primary,
          onTap: _site == null && !_hasFix
              ? null
              : () {
                  setState(() => _follow = false);
                  _fitAll();
                },
        ),
      ],
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String label,
    required bool selected,
    required Color primary,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.white,
        shape: CircleBorder(
          side: selected
              ? BorderSide(color: primary, width: 2)
              : BorderSide.none,
        ),
        elevation: 3,
        shadowColor: OtqPalette.foreground.withValues(alpha: 0.30),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null
                  ? OtqPalette.v6DisabledFg
                  : (selected ? primary : OtqPalette.foreground),
            ),
          ),
        ),
      ),
    );
  }

  /// Frames the geofence and the position together. The bottom inset keeps the
  /// result clear of the sheet.
  // ponytail: the sheet's height is estimated, not measured. It only ever
  // costs a slightly loose fit; measure with a GlobalKey if that ever shows.
  void _fitAll() {
    final List<LatLng> points = <LatLng>[];
    const Distance distance = Distance();
    if (_site != null) {
      final LatLng centre = LatLng(_site!.lat, _site!.lng);
      for (final double bearing in const <double>[0, 90, 180, 270]) {
        points.add(distance.offset(centre, _site!.radius, bearing));
      }
    }
    if (_hasFix) {
      final double margin = (_accuracy ?? 0) + 30;
      for (final double bearing in const <double>[0, 90, 180, 270]) {
        points.add(distance.offset(_currentPoint, margin, bearing));
      }
    }
    if (points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: EdgeInsets.only(
          left: 32,
          right: 32,
          top: 72,
          bottom: _accuracyIsLow ? 300 : 250,
        ),
        maxZoom: 18,
      ),
    );
  }

  // ── The bottom sheet: the screen's actual answer ─────────────────────

  Widget _sheet(Color primary) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double? boundary = metersToBoundary(_distanceToCentre, _site?.radius);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: OtqPalette.foreground.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 20 + bottomInset),
      // Landscape leaves less height than this sheet wants; scrolling is the
      // one-line answer to a whole class of overflow.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _statusRow(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                _statusSentence,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _stat(
                    'Ke batas',
                    metersLabel(boundary),
                    danger: _status == MapFixStatus.outside,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _stat(
                    'Akurasi',
                    accuracyLabel(_hasFix ? _accuracy : null),
                    warn: _accuracyIsLow,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _stat('Radius', metersLabel(_site?.radius))),
              ],
            ),
            if (_accuracyIsLow) ...<Widget>[
              const SizedBox(height: 12),
              _warnBox(),
            ],
            const SizedBox(height: 14),
            _refreshButton(),
            if (_lastUpdated != null && !_isRefreshing) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _updatedLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusRow() {
    final Color mark;
    final Color label;
    final String word;
    if (!_hasFix) {
      mark = OtqPalette.v6BorderStrong;
      label = OtqPalette.foreground;
      word = 'Mencari lokasi…';
    } else if (_site == null) {
      mark = OtqPalette.v6BorderStrong;
      label = OtqPalette.foreground;
      word = 'Posisi Anda';
    } else {
      switch (_status) {
        case MapFixStatus.inside:
          mark = OtqPalette.v6SuccessMark;
          label = OtqPalette.successText;
          word = 'Di dalam area';
        case MapFixStatus.outside:
          mark = OtqPalette.v6DangerMark;
          label = OtqPalette.dangerText;
          word = 'Di luar area';
        case MapFixStatus.unsure:
        case MapFixStatus.searching:
          mark = OtqPalette.v6BorderStrong;
          label = OtqPalette.foreground;
          word = 'Belum bisa dipastikan';
      }
    }

    return Row(
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: mark, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            word,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: label,
            ),
          ),
        ),
      ],
    );
  }

  /// One sentence saying what to do next. Never claims the attendance itself
  /// succeeded — this screen only looks, the block on Beranda submits.
  String get _statusSentence {
    if (!_hasFix) return 'Biasanya kurang dari 10 detik di luar ruangan';
    if (_site == null) {
      return 'Tidak ada area absen terdaftar untuk akun ini';
    }
    switch (_status) {
      case MapFixStatus.inside:
        return 'Absen GPS bisa dilakukan dari posisi ini';
      case MapFixStatus.outside:
        final String away = metersLabel(
          metersToBoundary(_distanceToCentre, _site!.radius),
        );
        final String name = _site!.name.trim();
        return name.isEmpty
            ? 'Mendekatlah ±$away ke area absen, atau gunakan QR/Selfie'
            : 'Mendekatlah ±$away ke arah $name untuk absen GPS, '
                  'atau gunakan QR/Selfie';
      case MapFixStatus.unsure:
        // With the new rule this band is only ever reached from OUTSIDE the
        // drawn ring, so there is exactly one thing to say.
        return 'Tepat di luar batas area, masih dalam toleransi GPS '
            '${accuracyLabel(_accuracy)}';
      case MapFixStatus.searching:
        return 'Biasanya kurang dari 10 detik di luar ruangan';
    }
  }

  Widget _stat(
    String key,
    String value, {
    bool warn = false,
    bool danger = false,
  }) {
    final Color valueColor = value == '—'
        ? OtqPalette.v6DisabledFg
        : danger
        ? OtqPalette.dangerText
        : warn
        ? OtqPalette.warningText
        : OtqPalette.foreground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: OtqPalette.v6Muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            key,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: OtqPalette.v6MutedFg,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: valueColor,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _warnBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: OtqPalette.v6WarningSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          Icon(Icons.error_outline, size: 18, color: OtqPalette.warningText),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Akurasi rendah. Pindah ke tempat terbuka atau dekat jendela, '
              'nyalakan Wi-Fi, lalu perbarui — atau gunakan QR.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: OtqPalette.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _refreshButton() {
    final bool enabled = !_isRefreshing;
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: OtqPalette.v6Muted,
          foregroundColor: OtqPalette.foreground,
          disabledBackgroundColor: OtqPalette.v6Muted,
          disabledForegroundColor: OtqPalette.v6DisabledFg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: enabled ? _refreshLocation : null,
        icon: _isRefreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: OtqPalette.v6DisabledFg,
                ),
              )
            : const Icon(Icons.refresh, size: 20),
        label: const Text('Perbarui lokasi'),
      ),
    );
  }

  // ── Location off / permission denied ─────────────────────────────────

  Widget _blockedTree(Color primary) {
    final bool serviceOff = _blocked == _MapBlock.serviceOff;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: OtqPalette.v6Muted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.location_off_outlined,
                size: 34,
                color: OtqPalette.v6MutedFg,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              serviceOff ? 'Lokasi belum aktif' : 'Izin lokasi belum diberikan',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: OtqPalette.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              serviceOff
                  ? 'Peta area absen membutuhkan layanan lokasi. Nyalakan '
                        'lokasi perangkat, lalu kembali ke sini.'
                  : 'Peta area absen membutuhkan izin lokasi. Aktifkan izin '
                        'Lokasi di pengaturan aplikasi, lalu kembali ke sini.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: OtqPalette.v6MutedFg,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: OtqPalette.v6Accent,
                  foregroundColor: OtqPalette.v6OnAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => unawaited(
                  serviceOff
                      ? Geolocator.openLocationSettings()
                      : Geolocator.openAppSettings(),
                ),
                child: Text(
                  serviceOff
                      ? 'Buka pengaturan lokasi'
                      : 'Buka pengaturan aplikasi',
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Kembali',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
