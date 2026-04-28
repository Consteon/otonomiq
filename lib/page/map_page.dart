import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  final double lat;
  final double lng;
  final String title;

  const MapPage({
    super.key,
    required this.lat,
    required this.lng,
    required this.title,
  })  : assert(lat >= -90 && lat <= 90, 'lat must be in [-90, 90]'),
        assert(lng >= -180 && lng <= 180, 'lng must be in [-180, 180]');

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final MapController _mapController;
  late LatLng _currentPoint;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentPoint = LatLng(widget.lat, widget.lng);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final newPoint = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentPoint = newPoint;
          _isRefreshing = false;
        });
        _mapController.move(newPoint, 16);
      }
    } catch (_) {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentPoint,
          initialZoom: 16,
        ),
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
}
