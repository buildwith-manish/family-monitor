import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

class _GeofenceScreenState extends State<GeofenceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Map<String, dynamic>> _fences = [];
  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic>? _currentLocation;

  StreamSubscription? _fencesSub;
  StreamSubscription? _alertsSub;
  StreamSubscription? _locationSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _listenAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _fencesSub?.cancel();
    _alertsSub?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  void _listenAll() {
    _fencesSub = LocationService.instance
        .watchGeofences(widget.childUid)
        .listen((f) {
      if (mounted) setState(() => _fences = f);
    });

    _alertsSub = LocationService.instance
        .watchGeofenceAlerts(widget.childUid)
        .listen((a) {
      if (mounted) setState(() => _alerts = a);
    });

    _locationSub = LocationService.instance
        .watchChildLocation(widget.childUid)
        .listen((loc) {
      if (mounted) setState(() => _currentLocation = loc);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location & Geofences',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            Text(widget.childName,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
          labelColor: const Color(0xFF1A73E8),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1A73E8),
          tabs: const [
            Tab(text: 'Location'),
            Tab(text: 'Zones'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LocationTab(location: _currentLocation),
          _ZonesTab(
            fences: _fences,
            childUid: widget.childUid,
            onAdd: _showAddFenceDialog,
            onDelete: _deleteFence,
          ),
          _AlertsTab(
            alerts: _alerts,
            childUid: widget.childUid,
            onMarkRead: _markAlertRead,
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFenceDialog() async {
    final nameCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final radiusCtrl = TextEditingController(text: '200');
    bool alertOnExit = true;
    bool alertOnEnter = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Add Safe Zone',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(nameCtrl, 'Zone name', 'e.g. Home'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _field(latCtrl, 'Latitude', '0.000000')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(lngCtrl, 'Longitude', '0.000000')),
                ]),
                const SizedBox(height: 10),
                _field(radiusCtrl, 'Radius (metres)', '200',
                    type: TextInputType.number),
                const SizedBox(height: 12),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Alert when leaving',
                      style: GoogleFonts.inter(fontSize: 13)),
                  value: alertOnExit,
                  activeColor: const Color(0xFF1A73E8),
                  onChanged: (v) => setSt(() => alertOnExit = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Alert when entering',
                      style: GoogleFonts.inter(fontSize: 13)),
                  value: alertOnEnter,
                  activeColor: const Color(0xFF1A73E8),
                  onChanged: (v) => setSt(() => alertOnEnter = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final lat = double.tryParse(latCtrl.text.trim());
                final lng = double.tryParse(lngCtrl.text.trim());
                final radius =
                    double.tryParse(radiusCtrl.text.trim()) ?? 200;

                if (name.isEmpty || lat == null || lng == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Please fill in name, lat and lng')));
                  return;
                }

                Navigator.pop(ctx);
                await LocationService.instance.addGeofence(
                  childUid: widget.childUid,
                  name: name,
                  lat: lat,
                  lng: lng,
                  radiusMeters: radius,
                  alertOnExit: alertOnExit,
                  alertOnEnter: alertOnEnter,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Zone "$name" added'),
                    backgroundColor: const Color(0xFF34A853),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
              child: const Text('Add Zone'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: c,
      keyboardType: type,
      style: GoogleFonts.inter(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inter(fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Future<void> _deleteFence(String fenceId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Remove Zone',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Remove the safe zone "$name"?',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await LocationService.instance.removeGeofence(widget.childUid, fenceId);
    }
  }

  Future<void> _markAlertRead(String key) async {
    await LocationService.instance.markAlertRead(widget.childUid, key);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location tab
// ─────────────────────────────────────────────────────────────────────────────

class _LocationTab extends StatelessWidget {
  final Map<String, dynamic>? location;
  const _LocationTab({required this.location});

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No location data yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            Text('Location shares when child device is active',
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    final lat = (location!['lat'] as num?)?.toDouble() ?? 0;
    final lng = (location!['lng'] as num?)?.toDouble() ?? 0;
    final accuracy = (location!['accuracy'] as num?)?.toInt() ?? 0;
    final ts = location!['timestamp'] as int?;
    final updated = ts != null
        ? _timeAgo(DateTime.fromMillisecondsSinceEpoch(ts))
        : 'Unknown';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          icon: Icons.my_location,
          iconColor: const Color(0xFF1A73E8),
          title: 'Current Position',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Latitude', lat.toStringAsFixed(6)),
              _row('Longitude', lng.toStringAsFixed(6)),
              _row('Accuracy', '±${accuracy}m'),
              _row('Updated', updated),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.1),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.map_outlined,
          iconColor: const Color(0xFF34A853),
          title: 'Open in Maps',
          content: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Copy coords: launch your maps app with the coordinates above'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '$lat, $lng',
                style: GoogleFonts.robotoMono(
                    fontSize: 14,
                    color: const Color(0xFF1A73E8),
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.1),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zones tab
// ─────────────────────────────────────────────────────────────────────────────

class _ZonesTab extends StatelessWidget {
  final List<Map<String, dynamic>> fences;
  final String childUid;
  final VoidCallback onAdd;
  final Future<void> Function(String, String) onDelete;

  const _ZonesTab({
    required this.fences,
    required this.childUid,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add Safe Zone'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        if (fences.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.place_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No safe zones yet',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Add a zone to receive alerts when the child leaves',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey.shade400),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: fences.length,
              itemBuilder: (_, i) {
                final f = fences[i];
                final name = f['name'] as String? ?? 'Zone';
                final lat = (f['lat'] as num?)?.toStringAsFixed(4) ?? '-';
                final lng = (f['lng'] as num?)?.toStringAsFixed(4) ?? '-';
                final radius =
                    (f['radiusMeters'] as num?)?.toInt() ?? 200;
                final onExit = f['alertOnExit'] as bool? ?? true;
                final onEnter = f['alertOnEnter'] as bool? ?? false;
                final id = f['_id'] as String;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.place,
                          color: Color(0xFF1A73E8), size: 20),
                    ),
                    title: Text(name,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$lat, $lng  •  ${radius}m radius',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Row(children: [
                          if (onExit)
                            _tag('Exit alert', Colors.red.shade100,
                                Colors.red.shade700),
                          if (onExit && onEnter)
                            const SizedBox(width: 4),
                          if (onEnter)
                            _tag('Entry alert', Colors.green.shade100,
                                Colors.green.shade700),
                        ]),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => onDelete(id, name),
                    ),
                  ),
                ).animate(delay: Duration(milliseconds: i * 60)).fadeIn();
              },
            ),
          ),
      ],
    );
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alerts tab
// ─────────────────────────────────────────────────────────────────────────────

class _AlertsTab extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final String childUid;
  final Future<void> Function(String) onMarkRead;

  const _AlertsTab({
    required this.alerts,
    required this.childUid,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No alerts yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            Text('Alerts appear when a safe zone is breached',
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      itemBuilder: (_, i) {
        final a = alerts[i];
        final type = a['type'] as String? ?? 'exit';
        final name = a['fenceName'] as String? ?? 'Zone';
        final ts = a['timestamp'] as int?;
        final read = a['read'] as bool? ?? false;
        final key = a['_key'] as String;
        final isExit = type == 'exit';

        final time = ts != null
            ? _fmt(DateTime.fromMillisecondsSinceEpoch(ts))
            : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: read ? Colors.white : const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: read
                ? null
                : Border.all(color: Colors.orange.shade200, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isExit
                  ? Colors.red.shade100
                  : Colors.green.shade100,
              child: Icon(
                isExit
                    ? Icons.logout
                    : Icons.login,
                color: isExit ? Colors.red : Colors.green,
                size: 20,
              ),
            ),
            title: Text(
              isExit
                  ? 'Left "$name"'
                  : 'Entered "$name"',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(time,
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey)),
            trailing: read
                ? null
                : TextButton(
                    onPressed: () => onMarkRead(key),
                    child: Text('Mark read',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF1A73E8))),
                  ),
          ),
        ).animate(delay: Duration(milliseconds: i * 50)).fadeIn();
      },
    );
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget content;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }
}
