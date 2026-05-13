import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import 'add_child_screen.dart';
import '../../services/battery_service.dart';
import 'monitoring_screen.dart';
import '../../services/webrtc_service.dart';
import 'app_usage_screen.dart';
import 'content_filter_screen.dart';
import 'schedule_lock_screen.dart';
import 'snapshots_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen>
    with WidgetsBindingObserver {
  final _auth = AuthService();

  final Map<String, dynamic> _children = {};
  final Map<String, Map<String, dynamic>> _deviceInfo = {};
  final Map<String, StreamSubscription> _batterySubs = {};

  StreamSubscription? _childrenSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForChildren();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reattachChildrenListener();
    }
  }

  void _reattachChildrenListener() {
    _childrenSub?.cancel();
    _childrenSub = null;
    _listenForChildren();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _childrenSub?.cancel();
    for (final s in _batterySubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  void _listenForChildren() {
    final user = _auth.currentUser;
    if (user == null) return;

    _childrenSub = _auth.getChildrenStream().listen((event) {
      if (!mounted) return;

      final newChildren = <String, dynamic>{};
      final raw = event.snapshot.value;
      if (raw is Map) {
        for (final entry in raw.entries) {
          newChildren[entry.key as String] = entry.value;
        }
      }

      setState(() {
        _children.clear();
        _children.addAll(newChildren);
      });

      // Start battery watchers for newly added children.
      for (final uid in newChildren.keys) {
        if (_batterySubs.containsKey(uid)) continue;
        _batterySubs[uid] = BatteryService.watchDeviceInfo(uid).listen((info) {
          if (!mounted) return;
          setState(() => _deviceInfo[uid] = info);
        });
      }

      // Cancel battery watchers for children that are no longer in the list.
      final removed = _batterySubs.keys
          .where((uid) => !newChildren.containsKey(uid))
          .toList();
      for (final uid in removed) {
        _batterySubs[uid]?.cancel();
        _batterySubs.remove(uid);
        _deviceInfo.remove(uid);
      }
    }, onError: (_) {
      // Re-attach on stream error (e.g. network reconnect).
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), _reattachChildrenListener);
      }
    });
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
              MaterialPageRoute(builder: (_) => const AddChildScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'signout') {
                await _auth.signOut();
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  Navigator.pushReplacementNamed(context, '/role-select');
                }
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.child_care,
                size: 44, color: Color(0xFF1A73E8)),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text('No devices connected yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Add a child device to start monitoring',
              style: GoogleFonts.inter(
                  fontSize: 14, color: const Color(0xFF5F6368))),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddChildScreen())),
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
                  letterSpacing: 0.5)),
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
              MaterialPageRoute(builder: (_) => const AddChildScreen())),
          icon: const Icon(Icons.add),
          label: const Text('Add Another Device'),
        ).animate(delay: 300.ms).fadeIn(),
      ],
    );
  }
}

class _ChildCard extends StatelessWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  final int delay;
  final Map<String, Map<String, dynamic>> deviceInfo;

  const _ChildCard({
    required this.childUid,
    required this.childData,
    required this.delay,
    required this.deviceInfo,
  });

  @override
  Widget build(BuildContext context) {
    final name = childData['childName'] as String? ??
        childData['displayName'] as String? ??
        'Child';
    final info = deviceInfo[childUid] ?? {};
    final battery = (info['batteryLevel'] ?? info['battery']) as int?;
    final isOnline = info['lastSeen'] != null &&
        (DateTime.now().millisecondsSinceEpoch -
                (info['lastSeen'] as int)) <
            120000;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE8F0FE),
              child: Text(name[0].toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A73E8))),
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34A853),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(name,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        subtitle: battery != null
            ? Text('Battery: $battery%',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showFeatureSheet(context, name),
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn();
  }

  void _showFeatureSheet(BuildContext context, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a monitoring feature',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),

                _sectionLabel('Live Monitoring'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _FeatureTile(
                        icon: Icons.videocam,
                        label: 'Camera',
                        color: const Color(0xFF1A73E8),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MonitoringScreen(
                                childUid: childUid,
                                childData: childData,
                                mode: StreamMode.camera,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FeatureTile(
                        icon: Icons.screen_share,
                        label: 'Screen',
                        color: const Color(0xFF34A853),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MonitoringScreen(
                                childUid: childUid,
                                childData: childData,
                                mode: StreamMode.screen,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                _sectionLabel('Parental Controls'),
                const SizedBox(height: 8),

                _FeatureRow(
                  icon: Icons.bar_chart,
                  label: 'App Usage',
                  subtitle: 'View screen time & app activity',
                  color: const Color(0xFFFF6D00),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppUsageScreen(
                          childUid: childUid,
                          childName: childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.block,
                  label: 'Content Filter',
                  subtitle: 'Block websites & categories',
                  color: const Color(0xFFEA4335),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContentFilterScreen(
                          childUid: childUid,
                          childName: childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.schedule,
                  label: 'Schedule & Lock',
                  subtitle: 'Set screen time limits & lock device',
                  color: const Color(0xFF9C27B0),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScheduleLockScreen(
                          childUid: childUid,
                          childName: childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.camera_alt,
                  label: 'Snapshots',
                  subtitle: 'Capture & view device screenshots',
                  color: const Color(0xFF00897B),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SnapshotsScreen(
                          childUid: childUid,
                          childName: childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
          letterSpacing: 0.5,
        ),
      );
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FeatureRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
