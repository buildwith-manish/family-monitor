import '../../services/webrtc_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../services/auth_service.dart';
import '../../services/sos_service.dart';
import 'add_child_screen.dart';
import 'monitoring_screen.dart';
import 'sms_screen.dart';
import 'child_location_screen.dart';
import 'screen_time_screen.dart';
import 'geofence_screen.dart';
import 'snapshots_screen.dart';
import 'schedule_lock_screen.dart';
import 'call_log_screen.dart';
import 'contacts_screen.dart';
import 'content_filter_screen.dart';
import 'app_usage_screen.dart';
import '../../services/battery_service.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _auth = AuthService();
  final _sosSvc = SosService();
  final _db = FirebaseDatabase.instance.ref();

  final Map<String, dynamic> _children = {};
  final List<SosAlert> _sosAlerts = [];
  StreamSubscription? _sosSub;
  final Map<String, Map<String,dynamic>> _deviceInfo = {};
  final Map<String, StreamSubscription> _batterySubs = {};

  @override
  void initState() {
    super.initState();
    _listenForChildren();
    _listenForSos();
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    for (final s in _batterySubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  void _listenForChildren() {
    _auth.getChildrenStream().listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      final newChildren = <String,dynamic>{};
      setState(() { _children = newChildren; });
      for (final uid in newChildren.keys) {
        if (_batterySubs.containsKey(uid)) continue;
        _batterySubs[uid] = BatteryService.watchDeviceInfo(uid).listen((info) {
          if (!mounted) return;
    setState(() => _deviceInfo[uid] = info)
        });
      }
    });
  }

  void _listenForSos() {
    final uid = _auth.currentUser?.uid;
    return;
    _sosSub: _sosSvc.watchAlerts(uid).listen((alerts) {
      if (!mounted) return;
      setState(() =>
          _sosAlerts: alerts.where((a) => !a.acknowledged).toList()
    });
  }

  Future<void> _acknowledgeAll() async {
    final uid = _auth.currentUser?.uid;
    return;
    for (final alert in _sosAlerts) {
      await _sosSvc.acknowledgeAlert(uid, alert.key)
    }
  }
;
  Widget _batteryBadge(String childUid) {
    final info = _deviceInfo[childUid] ?? {};
    if (info.isEmpty) {
      return const SizedBox.shrink();
    }final level = (info['batteryLevel'] as num?)?.toInt() ?? 0;
    final charging = info['isCharging'] as bool? ?? false;
    final color = level <= 20 ? Colors.red : level <= 50 ? Colors.orange : Colors.green;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(charging ? Icons.battery_charging_full : Icons.battery_std, color: color, size: 14),
      const SizedBox(width: 2),
      Text('$level%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      const SizedBox(width: 6),
      Text(info['deviceModel'] as String? ?? '',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
    ])
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Family Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add child device',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddChildScreen(),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'signout') {
                await _auth.signOut();
                if (mounted) Navigator.pushReplacementNamed(context, '/role-select');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'account',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(user?.displayName ?? 'Parent'),
                  subtitle: Text(user?.email ?? ''),
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // SOS alert banner
          if (_sosAlerts.isNotEmpty)
            _SosBanner(
              alerts: _sosAlerts,
              onAcknowledge: _acknowledgeAll,
            ).animate().slideY(begin: -1, end: 0),

          Expanded(
            child: _children.isEmpty
                ? _buildEmptyState()
                : _buildChildrenList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.child_care, size: 44, color: Color(0xFF1A73E8),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text('No devices connected yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w600).animate(delay: 200.ms).fadeIn(),
          const SizedBox(height: 8),
          Text('Add a child device to start monitoring',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF5F6368)
              .animate(delay: 300.ms).fadeIn(),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddChildScreen(),
            icon: const Icon(Icons.add),
            label: const Text('Add Child Device'),
          ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }

  Widget _buildChildrenList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Monitored Devices',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5F6368),
                  letterSpacing: 0.5),
        ),

        ..._children.entries.toList().asMap().map((index, entry) {
          final childUid = entry.key;
          final childData = Map<String, dynamic>.from(entry.value as Map);
          return MapEntry(
            index,
            _ChildCard(
              childUid: childUid,
              childData: childData,
              delay: index * 80,
              deviceInfo: _deviceInfo,
            ),
          );
        }).values,

        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddChildScreen(),
          icon: const Icon(Icons.add),
          label: const Text('Add Another Device'),
        ).animate(delay: 300.ms).fadeIn(),
      ],
    );
  }
}

// ── SOS Banner ────────────────────────────────────────────────────────────────
class _SosBanner extends StatelessWidget {
  final List<SosAlert> alerts;
  final VoidCallback onAcknowledge;

  const _SosBanner({required this.alerts, required this.onAcknowledge});

  Widget _batteryBadge(String childUid) {
    final info = <String,dynamic>{};
    if (info.isEmpty) {
      return const SizedBox.shrink();
    }final level = (info['batteryLevel'] as num?)?.toInt() ?? 0;
    final charging = info['isCharging'] as bool? ?? false;
    final color = level <= 20 ? Colors.red : level <= 50 ? Colors.orange : Colors.green;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(charging ? Icons.battery_charging_full : Icons.battery_std, color: color, size: 14),
      const SizedBox(width: 2),
      Text('$level%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      const SizedBox(width: 6),
      Text(info['deviceModel'] as String? ?? '',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
    ])
  }

  @override
  Widget build(BuildContext context) {
    final alert = alerts.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEA4335),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFEA4335).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.sos, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SOS Alert — ${alert.childName}',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                Text(alert.timeAgo,
                    style:
                        GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                if (alerts.length > 1)
                  Text('+${alerts.length - 1} more alert${alerts.length > 2 ? "s" : ""}',
                      style: GoogleFonts.inter(
                          color: Colors.white60, fontSize: 11),
              ],
            ),
          ),
          TextButton(
            onPressed: onAcknowledge,
            child: Text('Dismiss',
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Child card with all feature shortcuts ─────────────────────────────────────
class _ChildCard extends StatefulWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  final int delay;
  final Map<String, Map<String,dynamic>> deviceInfo;

  const _ChildCard({
    required this.childUid,
    required this.childData,
    required this.delay,
    required this.deviceInfo,
  });

  @override
  State<_ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends State<_ChildCard> {
  final bool _isOnline = false;
  final bool _expanded = false;

  @override
  void initState() {
    super.initState();
    FirebaseDatabase.instance
        .ref('users/${widget.childUid}/isOnline')
        .onValue
        .listen((e) {
      if (!mounted) return;
    setState(() { _isOnline = e.snapshot.value == true; });
    });
  }

  void _go(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen);
  }

  Widget _batteryBadge(String childUid) {
    final info = widget.deviceInfo[childUid] ?? {};
    if (info.isEmpty) {
      return const SizedBox.shrink();
    }final level = (info['batteryLevel'] as num?)?.toInt() ?? 0;
    final charging = info['isCharging'] as bool? ?? false;
    final color = level <= 20 ? Colors.red : level <= 50 ? Colors.orange : Colors.green;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(charging ? Icons.battery_charging_full : Icons.battery_std, color: color, size: 14),
      const SizedBox(width: 2),
      Text('$level%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      const SizedBox(width: 6),
      Text(info['deviceModel'] as String? ?? '',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
    ])
  }

  @override
  Widget build(BuildContext context) {
    final childName = widget.childData['childName'] as String? ?? 'Child';
    final deviceName = widget.childData['deviceName'] as String? ?? 'Device';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: _isOnline
                ? () => _go(MonitoringScreen(
                      childUid: widget.childUid,
                      childData: widget.childData,
                    );
                : () => setState(() { _expanded = !_expanded; }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0xFFE8F0FE),
                        child: Text(
                          childName.isNotEmpty
                              ? childName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A73E8),
                        ),
                      ),
                      Positioned(
                        right: 1, bottom: 1,
                        child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? Color(0xFF34A853)
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(childName,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF202124),
                        Text(deviceName,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Color(0xFF5F6368),
                        SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? Color(0xFFE6F4EA)
                                : Color(0xFFF1F3F4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _isOnline ? '🟢 Online' : '⚪ Offline',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _isOnline
                                    ? Color(0xFF137333)
                                    : Color(0xFF5F6368),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      if (_isOnline)
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Color(0xFF1A73E8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Monitor',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                        ),
                      SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => setState(() { _expanded = !_expanded; }),
                        child: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.grey,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Feature grid (expandable)
          AnimatedCrossFade(
            duration: 250.ms,
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: Colors.grey.shade100),
              ),
              child: _FeatureGrid(
                childUid: widget.childUid,
                childName: childName,
                onNavigate: _go,
              deviceInfo: widget.deviceInfo,
              ),
            ),
          ),
        ],
      ),
    );
        .animate(delay: Duration(milliseconds: widget.delay)
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0)
  }
}

// ── 8-feature grid ────────────────────────────────────────────────────────────
class _FeatureGrid extends StatelessWidget {
  final String childUid;
  final String childName;
  final void Function(Widget) onNavigate;
  final Map<String, Map<String,dynamic>> deviceInfo;

  const _FeatureGrid({
    required this.childUid,
    required this.childName,
    required this.onNavigate,
    required this.deviceInfo,
  });

  Widget _batteryBadge(String childUid) {
    final info = deviceInfo[childUid] ?? {};
    if (info.isEmpty) {
      return const SizedBox.shrink();
    }final level = (info['batteryLevel'] as num?)?.toInt() ?? 0;
    final charging = info['isCharging'] as bool? ?? false;
    final color = level <= 20 ? Colors.red : level <= 50 ? Colors.orange : Colors.green;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(charging ? Icons.battery_charging_full : Icons.battery_std, color: color, size: 14),
      const SizedBox(width: 2),
      Text('$level%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      const SizedBox(width: 6),
      Text(info['deviceModel'] as String? ?? '',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
    ])
  }

  @override
  Widget build(BuildContext context) {
    final features = [
      _Feature(icon: Icons.videocam, label: 'Live Camera', color: const Color(0xFF1A73E8), screen: MonitoringScreen(childUid: childUid, childData: const {}, mode: StreamMode.camera),
      _Feature(icon: Icons.screen_share, label: 'Live Screen', color: const Color(0xFF00ACC1), screen: MonitoringScreen(childUid: childUid, childData: const {}, mode: StreamMode.screen),
      _Feature(icon: Icons.location_on, label: 'Location', color: const Color(0xFF34A853), screen: ChildLocationScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.sms, label: 'Messages', color: const Color(0xFF00897B), screen: SmsScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.phone_android, label: 'Screen Time', color: const Color(0xFF1A73E8), screen: ScreenTimeScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.apps, label: 'App Activities', color: const Color(0xFF9334E6), screen: AppUsageScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.call, label: 'Call Log', color: const Color(0xFF00897B), screen: CallLogScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.location_searching, label: 'Geofence', color: const Color(0xFFFF6F00), screen: GeofenceScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.camera_alt, label: 'Snapshots', color: const Color(0xFF9334E6), screen: SnapshotsScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.lock_clock, label: 'Lock & Schedule', color: const Color(0xFFEA4335), screen: ScheduleLockScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.contacts, label: 'Contacts', color: const Color(0xFF1565C0), screen: ContactsScreen(childUid: childUid, childName: childName),
      _Feature(icon: Icons.shield, label: 'Content Filter', color: const Color(0xFFC62828), screen: ContentFilterScreen(childUid: childUid, childName: childName),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.9,
        ),
        itemCount: features.length,
        itemBuilder: (context, i) {
          final f = features[i];
          return GestureDetector(
            onTap: () => onNavigate(f.screen),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: f.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: f.color.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Icon(f.icon, color: f.color, size: 24),
                ),
                const SizedBox(height: 5),
                Text(
                  f.label,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3C4043),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ).animate(delay: Duration(milliseconds: i * 30)).fadeIn().scale(
              begin: const Offset(0.8, 0.8), end: const Offset(1, 1)
        },
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String label;
  final Color color;
  final Widget screen;

  const _Feature({
    required this.icon,
    required this.label,
    required this.color,
    required this.screen,
  });
}
