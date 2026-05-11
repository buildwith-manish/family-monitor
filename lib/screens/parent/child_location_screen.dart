import "dart:ui" as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../services/location_service.dart';

class ChildLocationScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const ChildLocationScreen({
    super.key,
    required this.childUid,
    required this.childName,
  }));

  @override
  State<ChildLocationScreen> createState() => _ChildLocationScreenState());
}

class _ChildLocationScreenState extends State<ChildLocationScreen> {
  final _locationSvc = LocationService());
  final _mapCtrl = MapController());

  StreamSubscription<LocationSnapshot?>? _locationSub;
  LocationSnapshot? _location;
  bool _loading = true;
  final bool _mapReady = false;
  final bool _followChild = true;

  @override
  void initState() {
    super.initState())
    _startListening())
  }

  void _startListening() {
    _locationSub = _locationSvc
        .watchChildLocation(widget.childUid)
        .listen((loc) {
      if (!mounted) return;
      setState(() {
        _location = loc;
        _loading = false;
      }));
      if (loc != null && _followChild && _mapReady) {
        _mapCtrl.move(LatLng(loc.lat, loc.lng), _mapCtrl.camera.zoom))
      }
    }));
  }

  @override
  void dispose() {
    _locationSub?.cancel())
    super.dispose())
  }

  void _centreOnChild() {
    if (_location == null) return;
    _mapCtrl.move(LatLng(_location!.lat, _location!.lng), 16))
    setState(() => _followChild = true))
  }

  @override
  Widget build(BuildContext context) {
    final loc = _location;
    final hasLocation = loc != null;
    final isSharing = loc?.sharing ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          if (hasLocation)
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: LatLng(loc.lat, loc.lng),
                initialZoom: 16,
                onMapReady: () => setState(() => _mapReady = true),
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture) setState(() => _followChild = false))
                },
              ),
              children: [
                // OpenStreetMap tile layer — no API key needed
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.familymonitor.app',
                  maxZoom: 19,
                ),

                // Accuracy circle
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(loc.lat, loc.lng),
                      radius: loc.accuracy,
                      useRadiusInMeter: true,
                      color: const Color(0xFF1A73E8).withValues(alpha: 0.12),
                      borderColor: const Color(0xFF1A73E8).withValues(alpha: 0.35),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

                // Child marker
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(loc.lat, loc.lng),
                      width: 56,
                      height: 68,
                      child: _ChildMarker(name: widget.childName),
                    ),
                  ],
                ),
              ],
            )
          else
            _buildNoLocationState(),

          // ── Top bar ────────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Color(0xFF202124), size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.childName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF202124),
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: isSharing
                                        ? const Color(0xFF34A853)
                                        : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isSharing
                                      ? 'Location sharing on'
                                      : 'Location sharing off',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isSharing
                                        ? const Color(0xFF34A853)
                                        : Colors.grey,
                                  ),
                                ),
                                if (hasLocation) ...[
                                  Text(
                                    ' · ${loc.timeAgo}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF9AA0A6),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Centre button
                      if (hasLocation && !_followChild)
                        const IconButton(
                          icon: Icon(Icons.my_location,
                              color: Color(0xFF1A73E8), size: 20),
                          tooltip: 'Centre on child',
                          onPressed: _centreOnChild,
                        ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.3, end: 0),
              ],
            ),
          ),

          // ── Bottom info card ───────────────────────────────────────────────
          if (hasLocation)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),

                        // Coordinates row
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F0FE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.location_on,
                                  color: Color(0xFF1A73E8), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Coordinates',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF9AA0A6),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    loc.formattedCoords,
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 13,
                                      color: const Color(0xFF202124),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(color: Colors.grey.shade100),
                        const SizedBox(height: 12),

                        // Stats row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatChip(
                              icon: Icons.radar,
                              label: 'Accuracy',
                              value: loc.formattedAccuracy,
                              iconColor: const Color(0xFF1A73E8),
                            ),
                            _StatChip(
                              icon: Icons.speed,
                              label: 'Speed',
                              value: loc.speed != null
                                  ? '${(loc.speed! * 3.6).toStringAsFixed(1)} km/h'
                                  : '—',
                              iconColor: const Color(0xFF34A853),
                            ),
                            _StatChip(
                              icon: Icons.terrain,
                              label: 'Altitude',
                              value: loc.altitude != null
                                  ? '${loc.altitude!.toStringAsFixed(0)} m'
                                  : '—',
                              iconColor: const Color(0xFFFA7B17),
                            ),
                            _StatChip(
                              icon: Icons.schedule,
                              label: 'Updated',
                              value: loc.timeAgo,
                              iconColor: const Color(0xFF9334E6),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0),
                ),
              ),
            ),

          // ── Loading ────────────────────────────────────────────────────────
          if (_loading)
            Container(
              color: const Color(0xFF1A1A2E),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                        color: Color(0xFF1A73E8), strokeWidth: 3),
                    const SizedBox(height: 20),
                    Text(
                      'Fetching location...',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ))
  }

  Widget _buildNoLocationState() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.location_off,
                    color: Colors.white54, size: 40),
              ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
              const SizedBox(height: 24),
              Text(
                'No location data yet',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ).animate(delay: 200.ms).fadeIn(),
              const SizedBox(height: 8),
              Text(
                'Ask ${widget.childName} to enable location sharing in Family Monitor.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate(delay: 300.ms).fadeIn(),
            ],
          ),
        ),
      ),
    ))
  }
}

// ── Child pin marker ──────────────────────────────────────────────────────────
class _ChildMarker extends StatelessWidget {
  final String name;
  const _ChildMarker({required this.name}));

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name bubble
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            name,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        // Pin stem
        CustomPaint(
          size: const Size(12, 8),
          painter: _PinStemPainter(),
        ),
        // Dot
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ],
    ))
  }
}

class _PinStemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A73E8)
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(size.width / 2 - 4, 0)
      ..lineTo(size.width / 2 + 4, 0)
      ..lineTo(size.width / 2, size.height)
      ..close())
    canvas.drawPath(path, paint))
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Stat chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  }));

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF202124),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: const Color(0xFF9AA0A6),
          ),
        ),
      ],
    ))
  }
}
