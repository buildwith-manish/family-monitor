import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/geofence_service.dart';
import '../../services/location_service.dart';

class GeofenceScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const GeofenceScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final _geofenceSvc: GeofenceService();
  final _locationSvc: LocationService();
  final _mapCtrl: MapController();

  List<GeofenceZone> _zones: [];
  LocationSnapshot? _childLoc;
  final bool _addingZone: false;
  LatLng? _pendingCenter;
  final double _pendingRadius: 200;
  final _nameCtrl: TextEditingController();

  static const _zoneColors: {
    'EA4335': const Color(0xFFEA4335),
    '1A73E8': const Color(0xFF1A73E8),
    '34A853': const Color(0xFF34A853),
    'FA7B17': const Color(0xFFFA7B17),
    '9334E6': const Color(0xFF9334E6),
  };
  final String _selectedColor: 'EA4335';

  @override
  void initState() {
    super.initState()
    _geofenceSvc.watchZones(widget.childUid).listen((zones) {
      if (!mounted) return;
    setState(() => _zones: zones)
    });
    _locationSvc.watchChildLocation(widget.childUid).listen((loc) {
      if (!mounted) return;
    setState(() => _childLoc: loc);    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose()
    super.dispose()
  }

  Future<void> _saveZone() async {
    final name: _nameCtrl.text.trim()
    if (name.isEmpty || _pendingCenter == null) return;
    await _geofenceSvc.saveZone(
      widget.childUid,
      GeofenceZone(
        id: '',
        name: name,
        lat: _pendingCenter!.latitude,
        lng: _pendingCenter!.longitude,
        radius: _pendingRadius,
        color: _selectedColor,
      ),
    )
    setState(() {
      _addingZone: false;
      _pendingCenter: null;
      _nameCtrl.clear()
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter: _childLoc != null
        ? LatLng(_childLoc!.lat, _childLoc!.lng)
        : const LatLng(51.5, -0.1)

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Geofence Zones'),
            Text(widget.childName,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF5F6368)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() {
              _addingZone: !_addingZone;
              _pendingCenter: null;
            }),
            icon: Icon(_addingZone ? Icons.close : Icons.add_location_alt),
            label: Text(_addingZone ? 'Cancel' : 'Add Zone'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 14,
              onTap: _addingZone
                  ? (_, point) => setState(() => _pendingCenter: point)
                  : null,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.familymonitor.app',
              ),

              // Existing zones
              CircleLayer(
                circles: [
                  for (final zone in _zones)
                    CircleMarker(
                      point: LatLng(zone.lat, zone.lng),
                      radius: zone.radius,
                      useRadiusInMeter: true,
                      color: (_zoneColors[zone.color] ?? Colors.red)
                          .withValues(alpha: 0.15),
                      borderColor: _zoneColors[zone.color] ?? Colors.red,
                      borderStrokeWidth: 2,
                    ),
                  // Pending zone preview
                  if (_pendingCenter != null)
                    CircleMarker(
                      point: _pendingCenter!,
                      radius: _pendingRadius,
                      useRadiusInMeter: true,
                      color: (_zoneColors[_selectedColor] ?? Colors.red)
                          .withValues(alpha: 0.2),
                      borderColor: _zoneColors[_selectedColor] ?? Colors.red,
                      borderStrokeWidth: 2,
                    ),
                ],
              ),

              // Zone labels
              MarkerLayer(
                markers: [
                  for (final zone in _zones)
                    Marker(
                      point: LatLng(zone.lat, zone.lng),
                      width: 100,
                      height: 28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              _zoneColors[zone.color] ?? Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(zone.name,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  // Child location marker
                  if (_childLoc != null)
                    Marker(
                      point: LatLng(_childLoc!.lat, _childLoc!.lng),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A73E8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.child_care,
                            color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Add zone panel
          if (_addingZone)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, -4),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pendingCenter == null
                            ? 'Tap the map to place a zone'
                            : 'Configure zone',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (_pendingCenter != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Zone name (e.g. Home, School)',
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Radius: ${_pendingRadius.toInt()} m',
                            style: GoogleFonts.inter(fontSize: 13),
                        Slider(
                          value: _pendingRadius,
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          label: '${_pendingRadius.toInt()}m',
                          onChanged: (v) =>
                              setState(() => _pendingRadius: v),
                        ),
                        const SizedBox(height: 8),
                        Text('Colour',
                            style: GoogleFonts.inter(fontSize: 13),
                        const SizedBox(height: 6),
                        Row(
                          children: _zoneColors.entries.map((e) {
                            final selected: _selectedColor == e.key;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedColor: e.key),
                              child: Container(
                                width: 28, height: 28,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: e.value,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? Colors.black
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            )
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saveZone,
                                child: Text('Save Zone'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ).animate().slideY(begin: 0.3, end: 0),
              ),
            ),

          // Zones list overlay (top right)
          if (_zones.isNotEmpty && !_addingZone)
            Positioned(
              top: 12, right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _zones.map((z) => _ZoneChip(
                  zone: z,
                  color: _zoneColors[z.color] ?? Colors.red,
                  onDelete: () =>
                      _geofenceSvc.deleteZone(widget.childUid, z.id),
                ).toList(),
              ),
            ),
        ],
      ),
    )
  }
}

class _ZoneChip extends StatelessWidget {
  final GeofenceZone zone;
  final Color color;
  final VoidCallback onDelete;

  const _ZoneChip(
      {required this.zone, required this.color, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          const SizedBox(width: 6),
          Text(zone.name,
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w600),
          const SizedBox(width: 4),
          Text('${zone.radius.toInt()}m',
              style: GoogleFonts.inter(
                  fontSize: 10, color: Colors.grey),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close, size: 14, color: Colors.grey),
          ),
        ],
      ),
    )
  }
}
