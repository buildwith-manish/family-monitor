// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures, prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/presence_service.dart';
import 'add_child_screen.dart';
import '../../services/battery_service.dart';
import 'battery_alerts_screen.dart';
import 'contacts_screen.dart';
import 'geofence_screen.dart';
import 'monitoring_screen.dart';
import '../../services/webrtc_service.dart';
import 'app_usage_screen.dart';
import 'app_lock_screen.dart';
import 'snapshots_screen.dart';
import 'sms_call_log_screen.dart';
import '../../services/device_event_service.dart';
import 'crash_report_screen.dart';
import 'daily_report_screen.dart';
import 'app_install_alerts_screen.dart';

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
  final Map<String, StreamSubscription> _presenceSubs = {};
  final Map<String, bool> _presenceMap = {};
  final Map<String, int> _crashCounts = {};
  final Map<String, StreamSubscription> _crashCountSubs = {};

  StreamSubscription? _childrenSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.initialize();
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
    for (final s in _presenceSubs.values) {
      s.cancel();
    }
    for (final s in _crashCountSubs.values) {
      s.cancel();
    }
    NotificationService.instance.dispose();
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

      for (final uid in newChildren.keys) {
        if (!_batterySubs.containsKey(uid)) {
          _batterySubs[uid] = BatteryService.watchDeviceInfo(uid).listen((info) {
            if (!mounted) return;
            setState(() => _deviceInfo[uid] = info);
          });
        }

        // Real-time presence via PresenceService — updates arrive within
        // milliseconds of the child going offline rather than waiting for
        // the next battery-service heartbeat.
        if (!_presenceSubs.containsKey(uid)) {
          _presenceSubs[uid] =
              PresenceService.instance.watchChildPresence(uid).listen((online) {
            if (!mounted) return;
            setState(() => _presenceMap[uid] = online);
          });
        }

        // Push notification watchers — fire local alerts for battery,
        // geofence and offline events for each monitored child.
        final childName = (newChildren[uid] as Map?)?['childName'] as String?
            ?? (newChildren[uid] as Map?)?['displayName'] as String?
            ?? 'Child';
        NotificationService.instance.watchChild(uid, childName);
        if (!_crashCountSubs.containsKey(uid)) {
          _crashCountSubs[uid] =
              DeviceEventService.watchUnreadCount(uid).listen((count) {
            if (!mounted) return;
            setState(() => _crashCounts[uid] = count);
          });
        }
      }

      final removed = _batterySubs.keys
          .where((uid) => !newChildren.containsKey(uid))
          .toList();
      for (final uid in removed) {
        _batterySubs[uid]?.cancel();
        _batterySubs.remove(uid);
        _deviceInfo.remove(uid);
        _presenceSubs[uid]?.cancel();
        _presenceSubs.remove(uid);
        _presenceMap.remove(uid);
        NotificationService.instance.unwatchChild(uid);
        _crashCountSubs[uid]?.cancel();
        _crashCountSubs.remove(uid);
        _crashCounts.remove(uid);
      }
    }, onError: (_) {
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), _reattachChildrenListener);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final parentName = user?.displayName ?? user?.email ?? 'Parent';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: const Color(0xFF1A73E8),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Family Monitor',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          parentName,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_outlined, color: Colors.white),
                tooltip: 'Add child device',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddChildScreen()),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) async {
                  if (v == 'signout') {
                    await _auth.signOut();
                    if (mounted) {
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
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_children.isEmpty)
                  _buildEmptyState()
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Monitored Devices',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF5F6368),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ..._children.entries.toList().asMap().entries.map((e) {
                    final index = e.key;
                    final childUid = e.value.key;
                    final childData =
                        Map<String, dynamic>.from(e.value.value as Map);
                    return _ChildCard(
                      childUid: childUid,
                      childData: childData,
                      delay: index * 80,
                      deviceInfo: _deviceInfo,
                      isOnline: _presenceMap[childUid] ?? false,
                      crashCount: _crashCounts[childUid] ?? 0,
                      onRemove: () async {
                        await _auth.removeChild(childUid);
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddChildScreen()),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Another Device'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1A73E8)),
                      foregroundColor: const Color(0xFF1A73E8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ).animate(delay: 300.ms).fadeIn(),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 400,
      child: Center(
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Child Card
// ─────────────────────────────────────────────────

class _ChildCard extends StatelessWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  final int delay;
  final Map<String, Map<String, dynamic>> deviceInfo;
  // Live presence fed from PresenceService.watchChildPresence stream.
  // True = device is online right now (Firebase .info/connected confirmed).
  final bool isOnline;
  final int crashCount;
  final Future<void> Function() onRemove;

  const _ChildCard({
    required this.childUid,
    required this.childData,
    required this.delay,
    required this.deviceInfo,
    required this.isOnline,
    required this.crashCount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = childData['childName'] as String? ??
        childData['displayName'] as String? ??
        'Child';
    final info = deviceInfo[childUid] ?? {};
    final battery = (info['batteryLevel'] ?? info['battery']) as int?;
    final isCharging = info['isCharging'] == true;
    final networkType = info['networkType'] as String?;
    final deviceModel = info['deviceModel'] as String?;

    final initials = name.trim().split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    Color batteryColor = const Color(0xFF34A853);
    if (battery != null) {
      if (battery < 20) batteryColor = const Color(0xFFEA4335);
      else if (battery < 40) batteryColor = const Color(0xFFFF6D00);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFE8F0FE),
                      child: Text(
                        initials,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A73E8),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF34A853)
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                    if (crashCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA4335),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              crashCount > 9 ? '!' : '$crashCount',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: const Color(0xFF202124),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? const Color(0xFF34A853)
                                  : Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isOnline
                                  ? const Color(0xFF34A853)
                                  : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (deviceModel != null) ...[
                            const SizedBox(width: 6),
                            Text('·',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 6),
                            Text(
                              deviceModel,
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Three-dot menu — remove device
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 20, color: Color(0xFF9AA0A6)),
                  tooltip: 'Options',
                  onSelected: (v) async {
                    if (v != 'remove') return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: Text('Remove $name?',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700)),
                        content: Text(
                          'This will disconnect $name\'s device from '
                          'your account. You can reconnect it later '
                          'by scanning the QR code again.',
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFEA4335),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(8)),
                            ),
                            onPressed: () =>
                                Navigator.pop(context, true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await onRemove();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'remove',
                      child: Row(
                        children: [
                          const Icon(Icons.link_off,
                              color: Color(0xFFEA4335), size: 18),
                          const SizedBox(width: 10),
                          Text('Remove device',
                              style: GoogleFonts.inter(
                                  color: const Color(0xFFEA4335),
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Stats row
          if (battery != null || networkType != null)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFB),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (battery != null) ...[
                    Icon(
                      isCharging
                          ? Icons.battery_charging_full
                          : battery < 20
                              ? Icons.battery_alert
                              : Icons.battery_std,
                      color: batteryColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$battery%${isCharging ? ' ⚡' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: batteryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (networkType != null) ...[
                    Icon(
                      networkType == 'WiFi'
                          ? Icons.wifi
                          : networkType == 'Mobile Data'
                              ? Icons.signal_cellular_alt
                              : Icons.signal_wifi_off,
                      size: 16,
                      color: networkType == 'No Connection'
                          ? Colors.grey
                          : const Color(0xFF1A73E8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      networkType,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: networkType == 'No Connection'
                            ? Colors.grey
                            : const Color(0xFF1A73E8),
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showFeatureSheet(context, name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Manage',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => _showFeatureSheet(context, name),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFE8F0FE),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Manage Device',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A73E8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn().slideY(
        begin: 0.1, end: 0);
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
          child: SingleChildScrollView(
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
                _sectionLabel('Activity & History'),
                const SizedBox(height: 8),

                _FeatureRow(
                  icon: Icons.bar_chart,
                  label: 'App Usage & Screen Time',
                  subtitle: 'View usage + set daily limits per app',
                  color: const Color(0xFFFF6D00),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppUsageScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.message_outlined,
                  label: 'Messages & Calls',
                  subtitle: 'View SMS inbox and call history',
                  color: const Color(0xFF1A73E8),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SmsCallLogScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.contacts_outlined,
                  label: 'Contact Book',
                  subtitle: 'Browse contacts, approve or block individuals',
                  color: const Color(0xFF9334E6),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactsScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
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
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.assessment_outlined,
                  label: 'Daily Reports',
                  subtitle: 'View nightly activity summaries & screen time',
                  color: const Color(0xFF1565C0),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DailyReportScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.app_registration,
                  label: 'App Install Alerts',
                  subtitle: 'Get notified when apps are installed or removed',
                  color: const Color(0xFF2E7D32),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppInstallAlertsScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 8),
                _sectionLabel('Safety & Alerts'),
                const SizedBox(height: 8),

                _FeatureRow(
                  icon: Icons.location_on_outlined,
                  label: 'Location & Geofences',
                  subtitle: 'Track location, set safe zones, get breach alerts',
                  color: const Color(0xFF00897B),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GeofenceScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.battery_alert,
                  label: 'Battery Alerts',
                  subtitle: 'Get notified when battery drops below a threshold',
                  color: const Color(0xFFFF6D00),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BatteryAlertsScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                _FeatureRow(
                  icon: Icons.health_and_safety_outlined,
                  label: 'Device Health',
                  subtitle: crashCount > 0
                      ? 'Crash & service events \u00b7 $crashCount unread'
                      : 'Crash reports & service health events',
                  color: const Color(0xFFEA4335),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CrashReportScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 8),
                _sectionLabel('Parental Controls'),
                const SizedBox(height: 8),

                _FeatureRow(
                  icon: Icons.lock_outlined,
                  label: 'App Lock',
                  subtitle: 'Block specific apps on child\'s device',
                  color: const Color(0xFFEA4335),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppLockScreen(
                          childUid: childUid,
                          childName:
                              childData['childName'] as String? ?? name,
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
        style:
            GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
