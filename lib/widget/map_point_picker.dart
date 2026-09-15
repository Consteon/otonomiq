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

// Indonesia bounding box. A pasted link whose coordinates fall outside it is
// rejected (spec §5.3) -- catches foreign links and non-maps URLs that happen
// to contain two decimal numbers. No config key by design: the spec names none.
const double _idMinLat = -11.0;
const double _idMaxLat = 6.0;
const double _idMinLng = 95.0;
const double _idMaxLng = 141.0;

// Short-link expansion budget (spec §5.1). _shortLinkTimeout is the TOTAL
// wall-clock budget for the whole redirect chain, NOT one timeout per hop --
// see expandMapsShortLink. Per-hop it would allow 3 x 8 = 24 s, which breaks
// the 8 s promise in the acceptance criteria.
const int _shortLinkMaxHops = 3;
const Duration _shortLinkTimeout = Duration(seconds: 8);

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

/// Join a reverse-geocoded address and an optional note for `addressPosition`.
///
/// Leaves no dangling separator in either direction (spec acceptance item 7):
/// an empty note yields the bare address -- byte-identical to v1 -- and an
/// empty address yields the bare note. The separator is U+2014 EM DASH with
/// one ASCII space on each side; it is not in [forbiddenCharacter], so
/// stringCleanUp carries it intact all the way to Firestore.
///
/// Top-level and exported on purpose: this is the only new business rule in
/// the note half of the feature, and _writeToController (a State method)
/// cannot be reached by a test in this repo.
String joinAddressNote(String address, String note) {
  if (note.isEmpty) return address;
  if (address.isEmpty) return note;
  return '$address — $note';
}

/// Coordinate patterns for a pasted Google Maps link, most precise first
/// (spec §5.2). The first pattern that matches wins: an `@lat,lng` pair is the
/// map viewport, i.e. the screen centre, not the point the customer shared, so
/// it only runs when nothing better is present.
///
/// The `query=` entry is Google's own documented Maps-URLs share format
/// (`/maps/search/?api=1&query=lat,lng`). It is case-insensitive and accepts
/// the percent-encoded comma that shape usually carries; it sits below `q=` so
/// the established priority order is untouched.
///
/// The last pattern accepts bare pasted text such as `-6.316754, 106.644907`.
/// Its `(?:^|\s)` prefix is load-bearing: without it, digits buried in a URL
/// path (`https://example.com/foo/-6.3,106.6`) would be read as coordinates.
final List<RegExp> _mapsCoordPatterns = [
  RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
  RegExp(r'[?&]q=(?:loc:)?(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
  RegExp(
    r'[?&]query=(-?\d+\.\d+)(?:,|%2C)\s*(-?\d+\.\d+)',
    caseSensitive: false,
  ),
  RegExp(r'/maps/place/(-?\d+\.\d+),(-?\d+\.\d+)'),
  RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
  RegExp(r'(?:^|\s)(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)'),
];

/// Extract a coordinate from pasted Google Maps link text, or from bare
/// "lat, lng" text. Returns null when nothing matches OR when the match falls
/// outside Indonesia -- the caller shows text segment 12 for both cases.
///
/// No Google API is involved: this is pure string work on the link the
/// customer already shared over WhatsApp (spec §10, zero-cost decision).
LatLng? extractLatLngFromText(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;
  for (final pattern in _mapsCoordPatterns) {
    final m = pattern.firstMatch(s);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1) ?? '');
    final lng = double.tryParse(m.group(2) ?? '');
    if (lat == null || lng == null) return null;
    if (lat < _idMinLat || lat > _idMaxLat) return null;
    if (lng < _idMinLng || lng > _idMaxLng) return null;
    return LatLng(lat, lng);
  }
  return null;
}

/// Hosts whose short links may be expanded by an HTTP GET.
///
/// Matched against the PARSED host, never as a substring of the pasted text:
/// `https://evil.example.com/x?ref=maps.app.goo.gl` carries the allowlisted
/// name but is not on the allowlisted host, and must never be fetched.
const Set<String> _shortLinkHosts = {'maps.app.goo.gl', 'goo.gl'};

/// First http(s) URL inside a block of text. Case-insensitive because a pasted
/// link can arrive upper-cased (`HTTPS://MAPS.APP.GOO.GL/...`).
final RegExp _urlInText = RegExp(r'https?://\S+', caseSensitive: false);

/// True when [u] is an http(s) URI on an allowlisted Google short-link host.
///
/// Applied to the pasted URL AND again before every redirect hop, so a chain
/// that leaves the allowlist ends there instead of becoming the target of
/// another GET.
bool _isAllowedShortLinkHost(Uri u) {
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  final host = u.host.toLowerCase();
  // Uri.tryParse('https://') yields a hostless URI rather than null, so
  // "it parsed" is not the same as "it is a valid target".
  if (host.isEmpty || !_shortLinkHosts.contains(host)) return false;
  // goo.gl is a general-purpose shortener; only its /maps space is ours.
  if (host == 'goo.gl' && !u.path.toLowerCase().startsWith('/maps')) {
    return false;
  }
  return true;
}

/// The allowlisted Google short-link URI inside [text], or null.
///
/// The URL is pulled out of the surrounding message first, because the
/// feature's primary input is a whole WhatsApp message -- "Ini lokasi rumah
/// saya https://maps.app.goo.gl/X" -- and `Uri.tryParse` returns null for that
/// string as a whole. The bare-coordinate path already tolerates surrounding
/// prose; this makes the short-link path match it.
Uri? mapsShortLinkUri(String text) {
  final match = _urlInText.firstMatch(text);
  if (match == null) return null;
  final uri = Uri.tryParse(match.group(0)!);
  if (uri == null) return null;
  return _isAllowedShortLinkHost(uri) ? uri : null;
}

/// Follow a Google Maps short link to the long URL that carries the
/// coordinates, without downloading a page body.
///
/// Takes a [Uri] already vetted by [mapsShortLinkUri] -- no re-parsing of free
/// text here. Sends GET with automatic redirects OFF and reads the `location`
/// response header, at most [_shortLinkMaxHops] times, stopping early as soon
/// as the URL contains coordinates. EVERY hop is host-checked, not just the
/// first, so the `location` header of one response can never aim the next GET
/// off the allowlist. The whole chain shares ONE [_shortLinkTimeout] budget,
/// so the caller's spinner can never outlive it. Returns the last URL reached,
/// or null on timeout / offline / malformed URL. Every failure mode reaches
/// the user the same way (text segment 12), so the caller does not need to
/// tell them apart.
Future<String?> expandMapsShortLink(Uri url) async {
  final client = http.Client();
  // ONE total budget for the whole chain, not one per hop: a per-hop timeout
  // would let 3 slow hops hold the spinner for 24 s, while §3.1 and manual
  // check 5 both promise the failure lands within _shortLinkTimeout.
  final deadline = DateTime.now().add(_shortLinkTimeout);
  try {
    Uri current = url;
    for (int hop = 0; hop < _shortLinkMaxHops; hop++) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return null;
      // A finalized Request cannot be resent -- build a fresh one per hop.
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await client.send(request).timeout(remaining);
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        // ponytail: no <meta http-equiv=refresh> parser. If Google starts
        // serving a consent interstitial here instead of a 30x, add one more
        // hop that pulls the refresh URL out of the body (spec §12).
        return current.toString();
      }
      final next = current.resolve(location);
      final nextUrl = next.toString();
      if (extractLatLngFromText(nextUrl) != null) return nextUrl;
      // The redirect target is fetched only while it is STILL allowlisted.
      // Otherwise hand it back and let the caller read coordinates out of it:
      // the normal Google chain lands on www.google.com, which is a fine
      // ANSWER but must never become the next GET.
      if (!_isAllowedShortLinkHost(next)) return nextUrl;
      current = next;
    }
    return current.toString();
  } catch (_) {
    // TimeoutException, socket error, FormatException from a malformed URL.
    return null;
  } finally {
    // IOClient.close() force-closes, so the undrained redirect body cannot
    // hold a socket open. No stream.drain() needed.
    client.close();
  }
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
  late final bool _pasteEnabled;
  late final bool _noteEnabled;
  late final List<String> _texts;
  late final LatLng? _initialCenter;

  // ── Mutable state ──────────────────────────────────────────────────
  _PickState _state = _PickState.empty;
  double? _lat;
  double? _lng;
  String _displayName = '';
  String? _errorText;
  double? _accuracy;

  /// Optional free-text note (gate: `noteEnabled`). It is joined onto the
  /// address only at write time -- never into [_displayName], which the card
  /// splits on its first comma (see _primaryName / _secondaryAddress).
  ///
  /// The controller is the single source of truth; [_note] reads through it so
  /// there is no second copy to keep in sync. It is always constructed (even
  /// when the gate is off) so dispose() has nothing to branch on.
  late final TextEditingController _noteController;

  /// Gated at the getter, so a stale note left in `stateObject` by an earlier
  /// config revision cannot leak into the output after `noteEnabled` is
  /// switched off server-side.
  String get _note => _noteEnabled ? _noteController.text.trim() : '';

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
    // Both v2 gates default OFF -- that is what makes a v1 config (no flags,
    // 10 text segments) render and behave exactly as before. Note the
    // asymmetry with _searchEnabled above, which defaults to TRUE.
    _pasteEnabled =
        widget.component['pasteEnabled']?.toString().toUpperCase() == 'TRUE';
    _noteEnabled =
        widget.component['noteEnabled']?.toString().toUpperCase() == 'TRUE';
    _texts = diamondTextToList(widget.component['text'] as String? ?? '');
    _initialCenter = parseLatLng(widget.component['initialCenter']?.toString());

    // Must exist before _restoreFromController(), which writes into it.
    _noteController = TextEditingController();

    // Restore from txfController if a value was previously selected
    _restoreFromController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
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
        // Recover display name + note from stateObject (persisted across
        // rebuilds). The note is NOT parsed back out of addressPosition by
        // splitting on " -- ": a Nominatim display_name can legitimately
        // contain an em dash, so that round trip is not safe.
        if (ctrl.stateObject is Map) {
          final st = ctrl.stateObject as Map;
          _displayName = st['name']?.toString() ?? '';
          _noteController.text = st['note']?.toString() ?? '';
        }
        if (_displayName.isEmpty) {
          _displayName = formatLatLng(_lat!, _lng!);
        }
      }
    }
  }

  // ── Write values to txfController ──────────────────────────────────

  void _writeToController() {
    // Early return by design: a note typed before a point is picked simply
    // waits here, and is joined the moment the point lands.
    if (_lat == null || _lng == null) return;
    final value = formatLatLng(_lat!, _lng!);

    // Main position (sets finalData, controller.text, stateObject)
    addToTxfController(
      _position,
      widget.scrName,
      value,
      stateObject: {'name': _displayName, 'note': _note},
    );

    // Optional auxiliary positions (direct writes, no table/stateObject)
    _writeAux(_latPosition, _lat!.toStringAsFixed(6));
    _writeAux(_lngPosition, _lng!.toStringAsFixed(6));
    // The note rides on the address slot (spec §2, §8) -- no new DB field.
    // The four-branch join lives in joinAddressNote (Task 3) so it can be
    // unit-tested; this method cannot be reached by a test.
    _writeAux(_addressPosition, joinAddressNote(_displayName, _note));
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
          pasteEnabled: _pasteEnabled,
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
    // Hapus is a full field reset: the note goes with the point. A surviving
    // note would silently re-attach to the next, different point.
    _noteController.clear();
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

            // ── Note field (gate: noteEnabled) ─────────────────────
            // Always visible when enabled, NOT gated on a point being
            // selected: a note typed first is held in the controller and
            // picked up when the point lands (_writeToController early-returns
            // while _lat is null). Requires addressPosition to be configured;
            // without it the note has nowhere to go.
            if (_noteEnabled) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 12),
              Text(
                mapPickerSlot(_texts, 13, 'Catatan (opsional)'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                onChanged: (_) => _writeToController(),
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 2,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: mapPickerSlot(_texts, 14, ''),
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
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
  final bool pasteEnabled;
  final List<String> texts;

  const _MapPointPickerScreen({
    required this.initialCenter,
    required this.zoom,
    required this.searchEnabled,
    required this.searchCountry,
    required this.pasteEnabled,
    required this.texts,
  });

  @override
  State<_MapPointPickerScreen> createState() => _MapPointPickerScreenState();
}

class _MapPointPickerScreenState extends State<_MapPointPickerScreen> {
  late final MapController _mapController;
  late final TextEditingController _searchController;
  late final TextEditingController _pasteController;
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
  bool _isExpandingLink = false;

  // ── Floating-overlay geometry ──────────────────────────────────────
  // The top bar starts at y=8 and each floating row is ~44 high with an 8 px
  // gap -- that is where v1's hard-coded `top: 60` for the search results came
  // from, and _resultsTop reproduces exactly 60 when pasteEnabled is false.
  // ponytail: hand-tuned, not measured. If the paste row grows, bump
  // _pasteRowHeight; being a few px off only shifts a floating card.
  static const double _barTop = 8;
  static const double _barRowHeight = 44;
  static const double _barGap = 8;
  static const double _pasteRowHeight = 52;

  double get _pasteRowTop => _barTop + _barRowHeight + _barGap; // 60
  double get _resultsTop => widget.pasteEnabled
      ? _pasteRowTop +
            _pasteRowHeight +
            _barGap // 120
      : _barTop + _barRowHeight + _barGap; // 60 -- v1, unchanged

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController = TextEditingController();
    _pasteController = TextEditingController();
    _centerLat = widget.initialCenter.latitude;
    _centerLng = widget.initialCenter.longitude;
    // Initial reverse-geocode for the starting center
    _reverseGeocode(_centerLat, _centerLng);
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _pasteController.dispose();
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
    // The paste field sits directly under this one, so admins do paste the
    // WhatsApp link into the wrong box. Try coordinates first, fall through to
    // Nominatim otherwise. Gated on pasteEnabled so a v1 config (no flags, no
    // paste field) behaves exactly as before -- spec acceptance item 8.
    // Extraction only, no network hop: a short link typed here still searches.
    if (widget.pasteEnabled) {
      final pasted = extractLatLngFromText(query);
      if (pasted != null) {
        _searchController.clear();
        _jumpToPastedPoint(pasted);
        return;
      }
    }
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

  // ── Paste a Google Maps link ───────────────────────────────────────

  /// Read coordinates out of pasted text, expanding a Google short link first
  /// when the text needs it.
  ///
  /// Every failure mode -- no coordinates, coordinates outside Indonesia,
  /// timeout, offline, malformed URL -- lands on the same segment-12 SnackBar
  /// and leaves the picker fully usable by hand (spec acceptance items 4, 5).
  Future<void> _onPasteSubmitted(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _isExpandingLink) return;

    LatLng? point = extractLatLngFromText(text);

    // Host-vetted once here; expandMapsShortLink re-checks every hop.
    final shortLink = point == null ? mapsShortLinkUri(text) : null;
    if (shortLink != null) {
      setState(() => _isExpandingLink = true);
      final expanded = await expandMapsShortLink(shortLink);
      if (!mounted) return;
      setState(() => _isExpandingLink = false);
      if (expanded != null) point = extractLatLngFromText(expanded);
    }

    if (!mounted) return;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapPickerSlot(widget.texts, 12, 'Link tidak memuat koordinat'),
          ),
        ),
      );
      return;
    }
    _pasteController.clear();
    _jumpToPastedPoint(point);
  }

  /// Move the map -- and therefore the selected point, since the invariant is
  /// "selection == map centre" -- to [point].
  ///
  /// MapController.move() does NOT emit MapEventMoveEnd: flutter_map 8.3.0
  /// fires that only from gesture handling (MapControllerImpl.moveEnded), so
  /// the 800 ms idle reverse-geocode in _onMapEvent never runs for a
  /// programmatic move. Call it explicitly, exactly as _jumpToGps does.
  void _jumpToPastedPoint(LatLng point) {
    _mapController.move(point, widget.zoom);
    setState(() {
      _centerLat = point.latitude;
      _centerLng = point.longitude;
      _searchResults = [];
      _showResults = false;
    });
    FocusScope.of(context).unfocus();
    _reverseGeocode(point.latitude, point.longitude);
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
                  // ── Paste-a-Maps-link field (gate: pasteEnabled) ──
                  // Own Positioned rather than a second row inside the top
                  // bar: that leaves v1's Row untouched, and the only v1 line
                  // affected is the results offset below, which now derives
                  // from _resultsTop instead of a literal 60.
                  if (widget.pasteEnabled)
                    Positioned(
                      top: _pasteRowTop,
                      left: 64,
                      right: 12,
                      child: Material(
                        elevation: 3,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        child: TextField(
                          controller: _pasteController,
                          onSubmitted: _onPasteSubmitted,
                          textInputAction: TextInputAction.go,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: mapPickerSlot(
                              widget.texts,
                              10,
                              'Tempel Link Lokasi',
                            ),
                            labelStyle: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                            hintText: mapPickerSlot(widget.texts, 11, ''),
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                            prefixIcon: const Icon(
                              Icons.content_paste,
                              size: 18,
                              color: Color(0xFF6B7280),
                            ),
                            suffixIcon: _isExpandingLink
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
                                : IconButton(
                                    icon: const Icon(
                                      Icons.arrow_forward,
                                      size: 18,
                                      color: Color(0xFF3B82F6),
                                    ),
                                    onPressed: () => _onPasteSubmitted(
                                      _pasteController.text,
                                    ),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Search results overlay (below the top bar, and below the
                  // paste row when that is on)
                  if (_showResults && _searchResults.isNotEmpty)
                    Positioned(
                      top: _resultsTop,
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
