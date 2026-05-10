import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../services/auth_service.dart';
import '../../services/foreground_service.dart';
import '../../services/location_service.dart';
import '../../services/remote_lock_service.dart';
import '../../services/call_log_service.dart';
import '../../services/contacts_service.dart';
import '../../services/snapshot_service.dart';
import '../../services/battery_service.dart';
import '../../services/sms_service.dart';
import '../../main_child.dart';
import '../../services/screen_time_service.dart';
import '../../services/webrtc_service.dart';
import 'child_streaming_screen.dart';
import '../../services/webrtc_service.dart';
import 'child_qr_screen.dart';
import 'sos_screen.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  final _auth = AuthService();
  final _foreground = MonitoringForegroundService();
  final _locationSvc = LocationService();
  final _lockSvc = RemoteLockService();
  final _callLogSvc = CallLogService();
  final _contactsSvc = ContactsService();
  final _snapshotSvc = SnapshotService();
  final _screenTimeSvc = ScreenTimeService();
  final _batterySvc = BatteryService();
  final _smsSvc = SmsService();
  StreamSubscription? _smsSub;

  Map<String, dynamic> _pendingRequests = {};
  Map<String, dynamic> _approvedParents = {};
  String? _childName;
  bool _isMonitoring = false;
  bool _locationSharing = false;
  bool _locked = false;

  StreamSubscription? _lockSub;
  StreamSubscription? _callSub;
  StreamSubscription? _snapshotSub;
  StreamSubscription? _callLogSub;
  StreamSubscription? _contactsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MonitoringForegroundService.initForegroundTask();
    _loadData();
    _listenForRequests();
    _setOnline(true);
    _listenForCommands();
    _startExtraServices();
  }

  @override
  void dispose() {
    _setOnline(false);
    _locationSvc.stopTracking();
    _lockSub?.cancel();
    _callSub?.cancel();
    _snapshotSub?.cancel();
    _callLogSub?.cancel();
    _contactsSub?.cancel();
    _smsSub?.cancel();
    _batterySvc.stopReporting();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _setOnline(false);
    } else if (state == AppLifecycleState.resumed) {
      _setOnline(true);
      _screenTimeSvc.uploadUsage(); // sync screen time when app opens
    }
  }

  Future<void> _setOnline(bool online) async {
    await _auth.setChildOnlineStatus(online);
  }

  Future<void> _startExtraServices() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _batterySvc.startReporting(uid);
    _smsSub = _smsSvc.watchSyncRequest(uid).listen((req) {
      if (req) {
        _smsSvc.syncSms(uid);
        FirebaseDatabase.instance.ref('commands/$uid/syncSms/requested').set(false);
      }
    });
    _screenTimeSvc.uploadUsage();
  }

  Future<void> _loadData() async {
    final uid = _auth.currentUser!.uid;
    final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
    if (snap.value != null && mounted) {
      final data = Map<String, dynamic>.from(snap.value as Map);
      setState(() => _childName = data['childName']);
    }
  }

  void _listenForRequests() {
    final uid = _auth.currentUser!.uid;
    FirebaseDatabase.instance
        .ref('users/$uid/pendingParentRequests')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final raw = event.snapshot.value;
      if (raw != null) {
        setState(() =>
            _pendingRequests = Map<String, dynamic>.from(raw as Map));
      } else {
        setState(() => _pendingRequests = {});
      }
    });

    FirebaseDatabase.instance
        .ref('users/$uid/approvedParents')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final raw = event.snapshot.value;
      if (raw != null) {
        setState(() =>
            _approvedParents = Map<String, dynamic>.from(raw as Map));
      } else {
        setState(() => _approvedParents = {});
      }
    });
  }

  void _listenForCommands() {
    final uid = _auth.currentUser!.uid;

    // Remote lock
    _lockSub = _lockSvc.watchLockState(uid).listen((state) {
      if (!mounted) return;
      final shouldLock = state.locked ||
          (state.schedule != null &&
              RemoteLockService.shouldBeLocked(state.schedule!));
      setState(() => _locked = shouldLock);
    });

    // Snapshot request
    _snapshotSub = _snapshotSvc.watchSnapshotRequest(uid).listen((requested) {
      if (requested) _snapshotSvc.captureAndUpload(uid);
    });

    // Call log sync
    _callLogSub = _callLogSvc.watchSyncRequest(uid).listen((requested) {
      if (requested) {
        _callLogSvc.syncCallLog();
        FirebaseDatabase.instance
            .ref('commands/$uid/syncCallLog/requested')
            .set(false);
      }
    });

    // Contacts sync
    _contactsSub = _contactsSvc.watchSyncRequest(uid).listen((requested) {
      if (requested) {
        _contactsSvc.syncContacts();
        FirebaseDatabase.instance
            .ref('commands/$uid/syncContacts/requested')
            .set(false);
      }
    });
  
    // Incoming call from parent — read mode (camera / screen) from Firebase
    _callSub = FirebaseDatabase.instance
        .ref('calls/$uid')
        .onValue
        .listen((event) async {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data == null) return;
      final map  = Map<String, dynamic>.from(data as Map);
      final status = map['status'] as String?;
      if (status == 'calling') {
        final modeStr = map['mode'] as String? ?? 'camera';
        final mode = modeStr == 'screen' ? StreamMode.screen : StreamMode.camera;
        _autoStartStreaming(uid, mode);
      }
    });
  }

  void _autoStartStreaming(String uid, [StreamMode mode = StreamMode.camera]) {
    final nav = childNavKey.currentState ?? (mounted ? Navigator.of(context) : null);
    nav?.push(MaterialPageRoute(
      builder: (_) => ChildStreamingScreen(childUid: uid, mode: mode),
    ));
  }

  Future<void> _approveParent(String parentUid) async {
    final uid = _auth.currentUser!.uid;
    final childName = _childName ?? 'Child';
    await FirebaseDatabase.instance
        .ref('users/$uid/pendingParentRequests/$parentUid/status')
        .set('approved');
    await FirebaseDatabase.instance
        .ref('users/$uid/approvedParents/$parentUid')
        .set(true);
    await FirebaseDatabase.instance
        .ref('users/$parentUid/children/$uid')
        .update({'childName': childName, 'uid': uid});
  }

  Future<void> _declineParent(String parentUid) async {
    final uid = _auth.currentUser!.uid;
    await FirebaseDatabase.instance
        .ref('users/$uid/pendingParentRequests/$parentUid')
        .remove();
  }

  void _startMonitoring(String parentUid) {
    final uid = _auth.currentUser!.uid;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChildStreamingScreen(
          childUid: uid,
          parentUid: parentUid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid ?? '';
    final childName = _childName ?? 'Child';

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8FAFB),
          appBar: AppBar(
            title: Text('Hi, $childName 👋'),
            actions: [
              // SOS button in app bar
              IconButton(
                icon: const Icon(Icons.sos, color: Color(0xFFEA4335)),
                tooltip: 'Emergency SOS',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SosScreen()),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'signout') {
                    await _auth.signOut();
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/');
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'account',
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(childName),
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
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Device ID card
              _DeviceIdCard(uid: uid).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 12),

              // Location sharing toggle
              _LocationToggleCard(
                isSharing: _locationSharing,
                onToggle: (enabled) async {
                  if (enabled) {
                    final granted = await _locationSvc.requestPermission();
                    if (!granted) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Location permission denied. Enable it in Settings.')),
                        );
                      }
                      return;
                    }
                    await _locationSvc.startTracking();
                    if (mounted) setState(() => _locationSharing = true);
                  } else {
                    await _locationSvc.stopTracking();
                    if (mounted) setState(() => _locationSharing = false);
                  }
                },
              ).animate(delay: 50.ms).fadeIn(duration: 400.ms),

              const SizedBox(height: 16),

              // Pending requests
              if (_pendingRequests.isNotEmpty) ...[
                _SectionHeader(
                  title: '🔔 Pending Requests',
                  subtitle: 'Someone wants to monitor this device',
                ),
                const SizedBox(height: 8),
                ..._pendingRequests.entries.toList().asMap().entries.map((e) {
                  final parentUid = e.value.key;
                  final reqData =
                      Map<String, dynamic>.from(e.value.value as Map);
                  return _PendingRequestCard(
                    parentUid: parentUid,
                    requestData: reqData,
                    delay: e.key * 100,
                    onApprove: () => _approveParent(parentUid),
                    onDecline: () => _declineParent(parentUid),
                  );
                }),
                const SizedBox(height: 16),
              ],

              // Approved parents
              _SectionHeader(
                title: '✅ Approved Parents',
                subtitle: _approvedParents.isEmpty
                    ? 'No approved parents yet'
                    : 'These parents can monitor this device',
              ),
              const SizedBox(height: 8),
              if (_approvedParents.isEmpty)
                _EmptyApprovedCard()
              else
                ..._approvedParents.keys.toList().asMap().entries.map((e) {
                  return _ApprovedParentCard(
                    parentUid: e.value,
                    delay: e.key * 100,
                    onStartMonitoring: () => _startMonitoring(e.value),
                  );
                }),

              const SizedBox(height: 24),
              _MonitoringInfoCard(),
            ],
          ),
          // SOS floating action button
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SosScreen()),
            ),
            backgroundColor: const Color(0xFFEA4335),
            icon: const Icon(Icons.sos, color: Colors.white),
            label: Text('SOS',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),

        // Remote lock overlay
        if (_locked) _LockOverlay(),
      ],
    );
  }
}

// ── Lock overlay ──────────────────────────────────────────────────────────────
class _LockOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E).withOpacity(0.97),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock, color: Colors.white, size: 44),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05),
                      duration: 1500.ms),
              const SizedBox(height: 28),
              Text('Device Locked',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'A parent has restricted access to this device.\nContact your parent to unlock.',
                style: GoogleFonts.inter(
                    color: Colors.white60, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Emergency call is always allowed
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                ),
                onPressed: () {
                  // Launch dialer with emergency number
                },
                icon: const Icon(Icons.call, size: 18),
                label: const Text('Emergency Call'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Device ID card ────────────────────────────────────────────────────────────
class _DeviceIdCard extends StatelessWidget {
  final String uid;
  const _DeviceIdCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smartphone, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Your Device ID',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.8),
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Text(uid,
              style: GoogleFonts.robotoMono(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Text('Share this ID with your parent so they can connect',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.white.withOpacity(0.7))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: uid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Device ID copied!'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.copy, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text('Copy ID',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChildQrScreen(
                          uid: uid,
                          childName: 'My Device',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code,
                            color: Color(0xFF1A73E8), size: 14),
                        const SizedBox(width: 6),
                        Text('Show QR',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF1A73E8),
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Location sharing toggle ───────────────────────────────────────────────────
class _LocationToggleCard extends StatelessWidget {
  final bool isSharing;
  final Future<void> Function(bool) onToggle;

  const _LocationToggleCard({
    required this.isSharing,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSharing
              ? const Color(0xFF34A853).withOpacity(0.4)
              : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isSharing
                  ? const Color(0xFF34A853).withOpacity(0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isSharing ? Icons.location_on : Icons.location_off,
              color: isSharing ? const Color(0xFF34A853) : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location Sharing',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: const Color(0xFF202124))),
                Text(
                  isSharing
                      ? 'Your location is visible to approved parents'
                      : 'Parents cannot see your location',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isSharing
                          ? const Color(0xFF34A853)
                          : const Color(0xFF9AA0A6)),
                ),
              ],
            ),
          ),
          Switch(
            value: isSharing,
            onChanged: (val) => onToggle(val),
            activeColor: const Color(0xFF34A853),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: const Color(0xFF202124))),
        Text(subtitle,
            style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFF5F6368))),
      ],
    );
  }
}

class _PendingRequestCard extends StatelessWidget {
  final String parentUid;
  final Map<String, dynamic> requestData;
  final int delay;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const _PendingRequestCard({
    required this.parentUid,
    required this.requestData,
    required this.delay,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final parentName = requestData['parentName'] as String? ?? 'Parent';
    final parentEmail = requestData['parentEmail'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD600).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  color: Color(0xFFF9A825), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(parentName,
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (parentEmail.isNotEmpty)
                      Text(parentEmail,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEA4335),
                    side: const BorderSide(color: Color(0xFFEA4335)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 400.ms);
  }
}

class _ApprovedParentCard extends StatelessWidget {
  final String parentUid;
  final int delay;
  final VoidCallback onStartMonitoring;

  const _ApprovedParentCard({
    required this.parentUid,
    required this.delay,
    required this.onStartMonitoring,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE8F0FE),
            child: const Icon(Icons.person, color: Color(0xFF1A73E8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Approved Parent',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(parentUid.substring(0, 8) + '…',
                    style: GoogleFonts.robotoMono(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onStartMonitoring,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Start Session'),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0);
  }
}

class _EmptyApprovedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.person_add_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('No parents approved yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5F6368))),
          const SizedBox(height: 4),
          Text('Share your Device ID with a parent so they can send a request.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _MonitoringInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF1A73E8), size: 18),
              const SizedBox(width: 8),
              Text('How monitoring works',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A73E8))),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'When a parent starts monitoring from their dashboard, you\'ll receive a visible notification showing exactly what\'s being monitored. You can stop monitoring anytime by dismissing the notification.',
            style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFF3C4043), height: 1.5),
          ),
        ],
      ),
    );
  }
}
