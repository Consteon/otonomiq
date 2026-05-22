import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../global.dart';
import '../model/otq_state.dart';
import '../page/map_page.dart';

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

class _LocationDetectorState extends State<LocationDetector> {
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
    _fetchLocationData();
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
            otqState.subAdministrativeArea.replaceFirst(RegExp(r'^([Kk]abupaten|[Kk]ota)\s+'), ''),
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

  String get _formattedUpdatedAt {
    if (_lastUpdated == null) return '';
    final seconds = DateTime.now().difference(_lastUpdated!).inSeconds;
    if (seconds < 10) return 'just now';
    if (seconds < 60) return '${seconds}s ago';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min ago';
    return '${minutes ~/ 60} hr ago';
  }

  String get _fallbackAddress =>
      _texts.length > 10 ? _texts[10] : 'Location not found';

  Future<void> _openMap() async {
    if (_lat == null || _lng == null) {
      await _fetchLocationData();
    }
    if (!mounted || _lat == null || _lng == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPage(
          lat: _lat!,
          lng: _lng!,
          title: _texts.isNotEmpty ? _texts[0] : 'Location Detection',
        ),
      ),
    );
  }

  _StatusConfig _statusConfig() {
    switch (_gpsStatus) {
      case 'inside':
        return _StatusConfig(
          label: _texts.length > 1 ? _texts[1] : 'Inside Site',
          color: const Color(0xFF22C55E),
        );
      case 'outside':
        return _StatusConfig(
          label: _texts.length > 2 ? _texts[2] : 'Outside Site',
          color: const Color(0xFFEF4444),
        );
      case 'near_boundary':
        return _StatusConfig(
          label: _texts.length > 3 ? _texts[3] : 'Near Boundary',
          color: const Color(0xFFF59E0B),
        );
      case 'last_known':
      default:
        return _StatusConfig(
          label: _texts.length > 3 ? _texts[3] : 'Last Known',
          color: const Color(0xFF6B7280),
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
  Widget build(BuildContext context) {
    final config = _statusConfig();
    final updatedAt = _formattedUpdatedAt;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Color(0xffE2E8F0))),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Text(
                (_texts.isNotEmpty ? _texts[0] : 'LOCATION').toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Status dot + label
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: config.color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                config.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: config.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Address
          if (_isLoading)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              _address ?? '--',
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          // Accuracy row
          if (_accuracy != null)
            Row(
              children: [
                const Icon(Icons.bolt, size: 14, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Text(
                  '${_accuracyLabel()} ${_texts.length > 6 ? _texts[6] : '±'}${_accuracy!.round()}${_texts.length > 7 ? _texts[7] : 'm'}',
                  style:
                  const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(width: 8),
                const Text('·', style: TextStyle(color: Color(0xFF9CA3AF))),
                const SizedBox(width: 8),
                Text(
                  'Updated $updatedAt',
                  style:
                  const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          if (_showViewMap || _showRefresh) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFE5E7EB), height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_showViewMap)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openMap,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: Text(_texts.length > 8 ? _texts[8] : 'View Map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                if (_showViewMap && _showRefresh) const SizedBox(width: 8),
                if (_showRefresh)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _fetchLocationData,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(_texts.length > 9 ? _texts[9] : 'Refresh'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusConfig {
  final String label;
  final Color color;
  const _StatusConfig({required this.label, required this.color});
}
