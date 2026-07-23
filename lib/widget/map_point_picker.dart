import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../global.dart';
import '../global2.dart';

// ── Constants (single-point-of-change per spec §4.1) ─────────────────

const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
const String _tileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _tileUserAgent = 'com.consteon.widgetdev';
const String _nominatimUserAgent = 'otonomiq/1.0 (design@consteon.com)';

// Indonesia center fallback (when no GPS, no initialCenter)
const double _fallbackLat = -2.5;
const double _fallbackLng = 118.0;
const double _fallbackZoom = 5.0;

// ── Exported pure helpers (tested in test/map_point_picker_test.dart) ─

/// Format lat,lng as a locale-independent string: dot-decimal, 6dp,
/// comma separator, no space. Example: "-6.302154,106.653428".
///
/// Uses [double.toStringAsFixed] which is locale-independent in Dart
/// (always '.') — this is the CRITICAL anti-corruption guarantee that
/// retires the spreadsheet id_ID locale bug.
String formatLatLng(double lat, double lng) =>
    '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// Parse an optional position from server config.
///
/// Accepts int, String (parseable to positive int), null, or empty string.
/// Returns null when the position should be skipped (empty/zero/negative/NaN).
int? parseOptionalPosition(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final n = int.tryParse(s);
  return (n != null && n > 0) ? n : null;
}

/// Length-guarded text-slot access for MAP_POINT_PICKER text segments.
///
/// Returns [fallback] when [index] is out of range OR the value at
/// [index] is empty. Mirrors [scannerSlot] in scanner.dart.
String mapPickerSlot(List<String> arr, int index, String fallback) {
  return arr.length > index && arr[index].isNotEmpty ? arr[index] : fallback;
}

/// Parse a "lat,long" string into a [LatLng], or null if unparseable.
///
/// Tolerates whitespace around parts. Rejects out-of-range values.
LatLng? parseLatLng(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(',');
  if (parts.length < 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return LatLng(lat, lng);
}

// ── Nominatim service (private, rate-limited, cached) ────────────────

class _NominatimResult {
  final double lat;
  final double lng;
  final String displayName;
  const _NominatimResult({
    required this.lat,
    required this.lng,
    required this.displayName,
  });
}

class _NominatimService {
  // ponytail: static rate-limit + cache is per-app-instance; upgrade to
  // per-isolate or provider if Nominatim load changes.
  static DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  static _NominatimResult? _lastReverseResult;
  static LatLng? _lastReverseCoord;

  static Map<String, String> get _headers => {
    'User-Agent': _nominatimUserAgent,
    'Accept': 'application/json',
  };

  /// Enforce min 1 second between requests (Nominatim usage policy).
  static Future<void> _rateLimit() async {
    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed.inMilliseconds < 1000) {
      await Future.delayed(
        Duration(milliseconds: 1000 - elapsed.inMilliseconds),
      );
    }
    _lastRequestTime = DateTime.now();
  }

  /// Reverse-geocode: (lat, lng) -> display name.
  ///
  /// Returns cached result if coordinates match the last call.
  /// Returns null on any failure (caller shows coordinate fallback).
  static Future<_NominatimResult?> reverse(double lat, double lng) async {
    // Cache hit
    if (_lastReverseCoord != null &&
        _lastReverseCoord!.latitude == lat &&
        _lastReverseCoord!.longitude == lng &&
        _lastReverseResult != null) {
      return _lastReverseResult;
    }
    try {
      await _rateLimit();
      final uri = Uri.parse(
        '$_nominatimBaseUrl/reverse?format=json'
        '&lat=${lat.toStringAsFixed(6)}&lon=${lng.toStringAsFixed(6)}'
        '&zoom=18&addressdetails=0',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = _NominatimResult(
          lat: lat,
          lng: lng,
          displayName: data['display_name']?.toString() ?? '',
        );
        _lastReverseCoord = LatLng(lat, lng);
        _lastReverseResult = result;
        return result;
      }
    } catch (_) {
      // Geocode failure is non-fatal (spec §4 rule 3)
    }
    return null;
  }

  /// Forward search: query -> list of results.
  ///
  /// Returns empty list on any failure.
  static Future<List<_NominatimResult>> search(
    String query, {
    String countryCode = '',
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      await _rateLimit();
      final params = <String, String>{
        'format': 'json',
        'q': query,
        'limit': '5',
      };
      if (countryCode.isNotEmpty) params['countrycodes'] = countryCode;
      final uri = Uri.parse(
        '$_nominatimBaseUrl/search',
      ).replace(queryParameters: params);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map(
              (e) => _NominatimResult(
                lat: double.tryParse(e['lat']?.toString() ?? '') ?? 0,
                lng: double.tryParse(e['lon']?.toString() ?? '') ?? 0,
                displayName: e['display_name']?.toString() ?? '',
              ),
            )
            .toList();
      }
    } catch (_) {
      // Search failure is non-fatal
    }
    return [];
  }
}

// ── MapPointPicker — the SDUI form-field widget ──────────────────────

enum _PickState { empty, loading, selected }

class MapPointPicker extends StatefulWidget {
  const MapPointPicker({
    super.key,
    required this.component,
    required this.scrName,
    this.lPad = 0,
    this.tPad = 0,
    this.rPad = 0,
    this.bPad = 0,
  });

  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  State<MapPointPicker> createState() => _MapPointPickerState();
}

class _MapPointPickerState extends State<MapPointPicker> {
  // ── Config parsed from component ───────────────────────────────────
  late final int _position;
  late final int? _addressPosition;
  late final int? _latPosition;
  late final int? _lngPosition;
  late final double _zoom;
  late final bool _searchEnabled;
  late final String _searchCountry;
  late final List<String> _texts;
  late final LatLng? _initialCenter;

  // ── Mutable state ──────────────────────────────────────────────────
  _PickState _state = _PickState.empty;
  double? _lat;
  double? _lng;
  String _displayName = '';
  String? _errorText;
  double? _accuracy;

  @override
  void initState() {
    super.initState();
    _position = getPosition(widget.component['position']);
    _addressPosition = parseOptionalPosition(
      widget.component['addressPosition'],
    );
    _latPosition = parseOptionalPosition(widget.component['latPosition']);
    _lngPosition = parseOptionalPosition(widget.component['lngPosition']);
    _zoom = (widget.component['zoom'] as num?)?.toDouble() ?? 17;
    _searchEnabled =
        (widget.component['searchEnabled']?.toString().toUpperCase() ??
            'TRUE') ==
        'TRUE';
    _searchCountry = widget.component['searchCountry']?.toString() ?? '';
    _texts = diamondTextToList(widget.component['text'] as String? ?? '');
    _initialCenter = parseLatLng(widget.component['initialCenter']?.toString());

    // Restore from txfController if a value was previously selected
    _restoreFromController();
  }

  void _restoreFromController() {
    final ctrl = txfController[widget.scrName]?[_position];
    if (ctrl != null &&
        ctrl.finalData.isNotEmpty &&
        ctrl.finalData != emptyString) {
      final restored = parseLatLng(ctrl.finalData);
      if (restored != null) {
        _lat = restored.latitude;
        _lng = restored.longitude;
        _state = _PickState.selected;
        // Recover display name from stateObject (persisted across rebuilds)
        if (ctrl.stateObject is Map) {
          _displayName = (ctrl.stateObject as Map)['name']?.toString() ?? '';
        }
        if (_displayName.isEmpty) {
          _displayName = formatLatLng(_lat!, _lng!);
        }
      }
    }
  }

  // ── Write values to txfController ──────────────────────────────────

  void _writeToController() {
    if (_lat == null || _lng == null) return;
    final value = formatLatLng(_lat!, _lng!);

    // Main position (sets finalData, controller.text, stateObject)
    addToTxfController(
      _position,
      widget.scrName,
      value,
      stateObject: {'name': _displayName},
    );

    // Optional auxiliary positions (direct writes, no table/stateObject)
    _writeAux(_latPosition, _lat!.toStringAsFixed(6));
    _writeAux(_lngPosition, _lng!.toStringAsFixed(6));
    _writeAux(_addressPosition, _displayName);
  }

  void _writeAux(int? pos, String value) {
    if (pos == null) return;
    txfControllerCheck(widget.scrName, pos);
    txfController[widget.scrName]![pos]!.finalData = value;
    txfController[widget.scrName]![pos]!.controller.text = value;
  }

  // ── GPS one-tap ────────────────────────────────────────────────────

  Future<void> _getGpsLocation() async {
    if (!mounted) return;
    setState(() {
      _state = _PickState.loading;
      _errorText = null;
    });

    try {
      // Permission check (mirrors api.dart lines 184-189)
      final bool gpsEnabled = await Geolocator.isLocationServiceEnabled();
      if (!gpsEnabled) throw Exception('GPS disabled');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permission denied');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      _lat = position.latitude;
      _lng = position.longitude;
      _accuracy = position.accuracy;

      // Best-effort reverse-geocode (non-blocking on failure)
      final result = await _NominatimService.reverse(_lat!, _lng!);
      _displayName = result?.displayName ?? formatLatLng(_lat!, _lng!);

      _state = _PickState.selected;
      _writeToController();
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _PickState.empty;
        _errorText = mapPickerSlot(_texts, 7, 'GPS error');
      });
    }
  }

  // ── Open fullscreen map picker ─────────────────────────────────────

  Future<void> _openMapPicker() async {
    LatLng center;
    double zoom = _zoom;
    if (_lat != null && _lng != null) {
      center = LatLng(_lat!, _lng!);
    } else if (_initialCenter != null) {
      center = _initialCenter;
    } else {
      // Best-effort GPS for initial center; fallback to Indonesia view
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
        center = LatLng(pos.latitude, pos.longitude);
      } catch (_) {
        center = const LatLng(_fallbackLat, _fallbackLng);
        zoom = _fallbackZoom;
      }
    }

    if (!mounted) return;

    // Navigator.push, NOT routeStack -- this is a transient picker screen
    // (same pattern as location_detector.dart line 188).
    final result = await Navigator.push<_MapPickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _MapPointPickerScreen(
          initialCenter: center,
          zoom: zoom,
          searchEnabled: _searchEnabled,
          searchCountry: _searchCountry,
          texts: _texts,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _lat = result.lat;
        _lng = result.lng;
        _displayName = result.displayName;
        _accuracy = null; // map pick has no GPS accuracy
        _state = _PickState.selected;
        _errorText = null;
      });
      _writeToController();
    }
  }

  // ── Clear selection (cancel) ───────────────────────────────────────

  void _clearSelection() {
    setState(() {
      _lat = null;
      _lng = null;
      _displayName = '';
      _accuracy = null;
      _errorText = null;
      _state = _PickState.empty;
    });
    // Empty out main + aux slots so submit and restore see no stale value
    _writeAux(_position, '');
    txfController[widget.scrName]?[_position]?.stateObject = null;
    _writeAux(_latPosition, '');
    _writeAux(_lngPosition, '');
    _writeAux(_addressPosition, '');
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final label = widget.component['label']?.toString() ?? '';

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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Label row + check mark ─────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
                if (_state == _PickState.selected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF22C55E),
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── State: empty ───────────────────────────────────────
            if (_state == _PickState.empty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  mapPickerSlot(_texts, 0, 'Belum ada lokasi terpilih'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _getGpsLocation,
                      icon: const Icon(Icons.my_location, size: 16),
                      label: Text(mapPickerSlot(_texts, 1, 'Lokasi Saya')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openMapPicker,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: Text(mapPickerSlot(_texts, 2, 'Cari di Peta')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // ── State: loading ─────────────────────────────────────
            if (_state == _PickState.loading)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    mapPickerSlot(_texts, 6, 'Mencari lokasi...'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),

            // ── State: selected ────────────────────────────────────
            if (_state == _PickState.selected) ...[
              // Primary: display name (split on first comma for
              // name vs address presentation)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 18,
                    color: Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _primaryName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1F2937),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_secondaryAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _secondaryAddress,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // Coordinates (small line)
              if (_lat != null && _lng != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    formatLatLng(_lat!, _lng!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
              // Accuracy badge when >30 m (GPS picks only)
              if (_accuracy != null && _accuracy! > 30) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '±${_accuracy!.round()} m',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openMapPicker,
                      icon: const Icon(Icons.edit_location_outlined, size: 16),
                      label: Text(mapPickerSlot(_texts, 3, 'Ganti Lokasi')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(mapPickerSlot(_texts, 9, 'Hapus')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Display name splitting (first comma -> name / address) ─────────

  String get _primaryName {
    final idx = _displayName.indexOf(',');
    if (idx > 0) return _displayName.substring(0, idx).trim();
    return _displayName;
  }

  String get _secondaryAddress {
    final idx = _displayName.indexOf(',');
    if (idx > 0 && idx < _displayName.length - 1) {
      return _displayName.substring(idx + 1).trim();
    }
    return '';
  }
}

// ── Return type for fullscreen picker ────────────────────────────────

class _MapPickResult {
  final double lat;
  final double lng;
  final String displayName;
  const _MapPickResult({
    required this.lat,
    required this.lng,
    required this.displayName,
  });
}

// ── _MapPointPickerScreen — fullscreen drag-to-pick (Gojek pattern) ──

class _MapPointPickerScreen extends StatefulWidget {
  final LatLng initialCenter;
  final double zoom;
  final bool searchEnabled;
  final String searchCountry;
  final List<String> texts;

  const _MapPointPickerScreen({
    required this.initialCenter,
    required this.zoom,
    required this.searchEnabled,
    required this.searchCountry,
    required this.texts,
  });

  @override
  State<_MapPointPickerScreen> createState() => _MapPointPickerScreenState();
}

class _MapPointPickerScreenState extends State<_MapPointPickerScreen> {
  late final MapController _mapController;
  late final TextEditingController _searchController;
  Timer? _idleTimer;
  Timer? _searchDebounce;

  String _centerName = '';
  double _centerLat = 0;
  double _centerLng = 0;
  bool _isGeocoding = false;
  bool _isSearching = false;
  List<_NominatimResult> _searchResults = [];
  bool _showResults = false;
  Offset _pinDragOffset = Offset.zero;
  bool _isDraggingPin = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController = TextEditingController();
    _centerLat = widget.initialCenter.latitude;
    _centerLng = widget.initialCenter.longitude;
    // Initial reverse-geocode for the starting center
    _reverseGeocode(_centerLat, _centerLng);
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _idleTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Map idle detection ─────────────────────────────────────────────

  void _onMapEvent(MapEvent event) {
    // These three event types signal the map has come to rest after a
    // user gesture. flutter_map 8.3.0 fires MapEventMoveEnd for drag-end,
    // MapEventFlingAnimationEnd when a fling finishes, and
    // MapEventFlingAnimationNotStarted when a drag ended too slowly to fling.
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventFlingAnimationNotStarted) {
      _idleTimer?.cancel();
      _idleTimer = Timer(const Duration(milliseconds: 800), () {
        final center = _mapController.camera.center;
        _centerLat = center.latitude;
        _centerLng = center.longitude;
        if (mounted) setState(() {});
        _reverseGeocode(center.latitude, center.longitude);
      });
    }
  }

  // ── Pin drag (move pin instead of map) ─────────────────────────────

  /// On release: convert pin tip's screen position to LatLng, recenter
  /// map there, snap pin back to center. Keeps the invariant that the
  /// selected point is always the map center.
  void _onPinDragEnd() {
    final camera = _mapController.camera;
    final target = camera.screenOffsetToLatLng(
      camera.nonRotatedSize.center(Offset.zero) + _pinDragOffset,
    );
    setState(() {
      _pinDragOffset = Offset.zero;
      _isDraggingPin = false;
      _centerLat = target.latitude;
      _centerLng = target.longitude;
    });
    _mapController.move(target, camera.zoom);
    _reverseGeocode(target.latitude, target.longitude);
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);
    final result = await _NominatimService.reverse(lat, lng);
    if (!mounted) return;
    setState(() {
      _centerName = result?.displayName ?? '';
      _isGeocoding = false;
    });
  }

  // ── Search ─────────────────────────────────────────────────────────

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _showResults = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    final results = await _NominatimService.search(
      query,
      countryCode: widget.searchCountry,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _showResults = results.isNotEmpty;
      _isSearching = false;
    });
  }

  void _onSearchSubmitted(String query) {
    _searchDebounce?.cancel();
    _doSearch(query);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
      return;
    }
    // Debounce 600ms (Nominatim policy: no autocomplete-per-keystroke)
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _doSearch(query);
    });
  }

  void _selectSearchResult(_NominatimResult result) {
    setState(() {
      _showResults = false;
      _searchResults = [];
      _searchController.clear();
      _centerLat = result.lat;
      _centerLng = result.lng;
      _centerName = result.displayName;
    });
    _mapController.move(LatLng(result.lat, result.lng), widget.zoom);
    FocusScope.of(context).unfocus();
  }

  // ── GPS jump ───────────────────────────────────────────────────────

  Future<void> _jumpToGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      _mapController.move(point, widget.zoom);
      _centerLat = pos.latitude;
      _centerLng = pos.longitude;
      setState(() {});
      _reverseGeocode(pos.latitude, pos.longitude);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapPickerSlot(widget.texts, 7, 'GPS error'))),
      );
    }
  }

  // ── Confirm ────────────────────────────────────────────────────────

  void _confirmSelection() {
    final name = _centerName.isNotEmpty
        ? _centerName
        : formatLatLng(_centerLat, _centerLng);
    Navigator.pop(
      context,
      _MapPickResult(lat: _centerLat, lng: _centerLng, displayName: name),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayCoord = formatLatLng(_centerLat, _centerLng);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // ── Map area ─────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // The map
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: widget.initialCenter,
                      initialZoom: widget.zoom,
                      onMapEvent: _onMapEvent,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _tileUrlTemplate,
                        userAgentPackageName: _tileUserAgent,
                      ),
                    ],
                  ),
                  // Pin shadow dot at center (hidden while dragging —
                  // dot marks map center, which is stale mid-drag)
                  if (!_isDraggingPin)
                    Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  // Center pin overlay — draggable. Pin tip sits at
                  // screen center when offset is zero; user can drag
                  // the pin itself, release recenters map at the tip.
                  Center(
                    child: Transform.translate(
                      offset: _pinDragOffset,
                      child: GestureDetector(
                        onPanStart: (_) =>
                            setState(() => _isDraggingPin = true),
                        onPanUpdate: (d) =>
                            setState(() => _pinDragOffset += d.delta),
                        onPanEnd: (_) => _onPinDragEnd(),
                        onPanCancel: () => setState(() {
                          _pinDragOffset = Offset.zero;
                          _isDraggingPin = false;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 48),
                          child: Icon(
                            Icons.location_pin,
                            color: Colors.red.withValues(
                              alpha: _isDraggingPin ? 0.75 : 1,
                            ),
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── Floating top bar: back + search ─────────
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        // Back button (circular, floating)
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 3,
                          shadowColor: Colors.black26,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.pop(context),
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.arrow_back,
                                size: 22,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ),
                        if (widget.searchEnabled) ...[
                          const SizedBox(width: 8),
                          // Search field (floating card)
                          Expanded(
                            child: Material(
                              elevation: 3,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                              child: TextField(
                                controller: _searchController,
                                onChanged: _onSearchChanged,
                                onSubmitted: _onSearchSubmitted,
                                textInputAction: TextInputAction.search,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: mapPickerSlot(
                                    widget.texts,
                                    4,
                                    'Cari alamat / tempat...',
                                  ),
                                  hintStyle: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 20,
                                    color: Color(0xFF6B7280),
                                  ),
                                  suffixIcon: _isSearching
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : (_searchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                  color: Color(0xFF6B7280),
                                                ),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  setState(() {
                                                    _searchResults = [];
                                                    _showResults = false;
                                                  });
                                                },
                                              )
                                            : null),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 13,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Search results overlay (below top bar)
                  if (_showResults && _searchResults.isNotEmpty)
                    Positioned(
                      top: 60,
                      left: 64,
                      right: 12,
                      child: Material(
                        elevation: 4,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _searchResults[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.location_on_outlined,
                                size: 18,
                              ),
                              title: Text(
                                r.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              onTap: () => _selectSearchResult(r),
                            );
                          },
                        ),
                      ),
                    ),
                  // GPS button
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'mapPickerGps',
                      onPressed: _jumpToGps,
                      backgroundColor: Colors.white,
                      child: const Icon(
                        Icons.my_location,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom panel ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isGeocoding)
                    const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      _centerName.isNotEmpty ? _centerName : displayCoord,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1F2937),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    displayCoord,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirmSelection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        mapPickerSlot(widget.texts, 5, 'Pakai Lokasi Ini'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
