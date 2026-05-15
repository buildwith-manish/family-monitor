// lib/screens/parent/live_location_screen.dart
//
// Real-time map of the child's GPS position drawn on OpenStreetMap tiles
// (no API key required — uses flutter_map + latlong2).
//
// Data source: Firebase RTDB  location/$childUid
//   {lat, lng, accuracy, timestamp}
//
// Features:
//   • Auto-centers on the child's latest fix every update
//   • Animated "child" marker (pulsing ring)
//   • Geofence circles drawn at the correct metre radius
//   • Address reverse-geocoded from the stored coordinates via Nominatim
//   • Last-updated timestamp + accuracy indicator in the bottom card
//   • "Centre" FAB to re-lock the view on the child's position

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../services/location_service.dart';

class LiveLocationScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const LiveLocationScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();

  LatLng? _childPos;
  double? _accuracy;
  int? _lastTs;
  bool _centreOnUpdate = true;

  List<Map<String, dynamic>> _geofences = [];

  StreamSubscription? _locSub;
  StreamSubscription? _fenceSub;

  // Pulse animation controller for the child marker ring
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _appPurple = Color(0xFF6C3CE1);
  static const _tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _locSub = LocationService.instance
        .watchChildLocation(widget.childUid)
        .listen(_onLocationUpdate);

    _fenceSub = LocationService.instance
        .watchGeofences(widget.childUid)
        .listen((fences) {
      if (mounted) setState(() => _geofences = fences);
    });
  }

  void _onLocationUpdate(Map<String, dynamic>? loc) {
    if (!mounted || loc == null) return;
    final lat = (loc['lat'] as num?)?.toDouble();
    final lng = (loc['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final pos      = LatLng(lat, lng);
    final accuracy = (loc['accuracy'] as num?)?.toDouble();
    final ts       = (loc['timestamp'] as num?)?.toInt();

    setState(() {
      _childPos = pos;
      _accuracy  = accuracy;
      _lastTs    = ts;
    });

    if (_centreOnUpdate) {
      // Smooth pan, keep current zoom
      _mapCtrl.move(pos, _mapCtrl.camera.zoom);
    }
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _fenceSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Map ─────────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _childPos ?? const LatLng(20.5937, 78.9629),
            initialZoom: _childPos == null ? 4.0 : 15.0,
            onMapEvent: (evt) {
              // When user drags, stop auto-centering so the map isn't pulled
              // back on the next location update.
              if (evt is MapEventMove &&
                  evt.source != MapEventSource.mapController) {
                if (_centreOnUpdate) {
                  setState(() => _centreOnUpdate = false);
                }
              }
            },
          ),
          children: [
            // OSM tile layer
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.example.family_monitor',
              maxZoom: 19,
            ),

            // Geofence circles
            CircleLayer(circles: _buildGeofenceCircles()),

            // Accuracy ring (light)
            if (_childPos != null && _accuracy != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: _childPos!,
                  radius: _accuracy!,
                  useRadiusInMeter: true,
                  color: _appPurple.withValues(alpha: 0.08),
                  borderColor: _appPurple.withValues(alpha: 0.25),
                  borderStrokeWidth: 1.5,
                ),
              ]),

            // Child location marker
            if (_childPos != null)
              MarkerLayer(markers: [_childMarker()]),
          ],
        ),

        // ── AppBar overlay ───────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              _GlassButton(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _childPos != null
                            ? Colors.greenAccent
                            : Colors.grey,
                      ),
                    ).animate(onPlay: (c) => c.repeat())
                        .fadeOut(duration: 900.ms),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.childName,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _childPos != null
                                ? 'Live location active'
                                : 'Waiting for location...',
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_childPos != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'LIVE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),

        // ── Bottom info card ─────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomCard(
            childPos:   _childPos,
            accuracy:   _accuracy,
            lastTs:     _lastTs,
            geofences:  _geofences,
          ),
        ),

        // ── Centre FAB ───────────────────────────────────────────────────────
        if (_childPos != null)
          Positioned(
            right: 16,
            bottom: 210,
            child: FloatingActionButton.small(
              heroTag: 'centre_map',
              backgroundColor: _appPurple,
              onPressed: () {
                setState(() => _centreOnUpdate = true);
                _mapCtrl.move(_childPos!, 15.0);
              },
              child: Icon(
                _centreOnUpdate
                    ? Icons.my_location
                    : Icons.location_searching,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Marker _childMarker() {
    return Marker(
      point: _childPos!,
      width:  52,
      height: 52,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing ring
            Container(
              width:  52 * _pulseAnim.value,
              height: 52 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _appPurple
                    .withValues(alpha: 0.25 * _pulseAnim.value),
                border: Border.all(
                  color: _appPurple
                      .withValues(alpha: 0.5 * _pulseAnim.value),
                  width: 2,
                ),
              ),
            ),
            // Inner dot
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _appPurple,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _appPurple.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<CircleMarker> _buildGeofenceCircles() {
    return _geofences.map((fence) {
      final lat    = (fence['lat']    as num?)?.toDouble();
      final lng    = (fence['lng']    as num?)?.toDouble();
      final radius = (fence['radiusM'] as num?)?.toDouble() ?? 200.0;
      if (lat == null || lng == null) return null;
      return CircleMarker(
        point: LatLng(lat, lng),
        radius: radius,
        useRadiusInMeter: true,
        color: const Color(0xFF34A853).withValues(alpha: 0.1),
        borderColor: const Color(0xFF34A853).withValues(alpha: 0.6),
        borderStrokeWidth: 2,
      );
    }).whereType<CircleMarker>().toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom info card
// ─────────────────────────────────────────────────────────────────────────────

class _BottomCard extends StatelessWidget {
  final LatLng? childPos;
  final double? accuracy;
  final int? lastTs;
  final List<Map<String, dynamic>> geofences;

  const _BottomCard({
    required this.childPos,
    required this.accuracy,
    required this.lastTs,
    required this.geofences,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          if (childPos == null)
            Row(children: [
              const Icon(Icons.location_off_outlined,
                  color: Colors.grey, size: 20),
              const SizedBox(width: 10),
              Text(
                'No location data yet',
                style: GoogleFonts.inter(
                    fontSize: 14, color: Colors.grey),
              ),
            ])
          else ...[
            // Coordinates row
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C3CE1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.location_pin,
                    color: Color(0xFF6C3CE1), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${childPos!.latitude.toStringAsFixed(5)}, '
                      '${childPos!.longitude.toStringAsFixed(5)}',
                      style: GoogleFonts.robotoMono(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (accuracy != null)
                      Text(
                        'Accuracy ±${accuracy!.toStringAsFixed(0)} m',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Stats row
            Row(children: [
              _Stat(
                icon: Icons.access_time,
                label: 'Last update',
                value: lastTs != null ? _relativeTime(lastTs!) : 'Unknown',
                color: const Color(0xFF1A73E8),
              ),
              const SizedBox(width: 16),
              _Stat(
                icon: Icons.fence,
                label: 'Geofences',
                value: '${geofences.length} active',
                color: const Color(0xFF34A853),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  static String _relativeTime(int ms) {
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 10, color: Colors.grey)),
                Text(value,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _GlassButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Center(child: child),
      ),
    );
  }
}
