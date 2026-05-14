// ignore_for_file: unnecessary_cast, unused_local_variable, unused_element
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/alert_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/panic_service.dart';
import '../../services/presence_service.dart';
import '../../widgets/streak_card_widget.dart';
import 'child_qr_screen.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/battery_service.dart';
import '../../services/call_log_service.dart';
import '../../services/contacts_service.dart';
import '../../services/foreground_service.dart';
import '../../services/silent_webrtc_service.dart';
import '../../services/sms_service.dart';
import '../../services/snapshot_service.dart';
import '../../services/webrtc_service.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  final CallLogService _callLogSvc = CallLogService();
  final ContactsService _contactsSvc = ContactsService();
  final SnapshotService _snapshotSvc = SnapshotService();
  final BatteryService _batterySvc = BatteryService();

  bool _showBatteryHint = false;

  StreamSubscription? _callSub;
  StreamSubscription? _snapshotSub;
  StreamSubscription? _callLogSub;
  StreamSubscription? _contactsSub;
  StreamSubscription? _smsSub;
  StreamSubscription? _appListSub;
  StreamSubscription? _pendingSub;
  StreamSubscription? _parentSub;

  static const _kScreenCaptureCh = MethodChannel('com.familymonitor/screen_capture');

  bool _locked = false;
  String? _childName;
  String? _deviceName;

  // Connected parent info
  String? _connectedParentName;
  String? _connectedParentEmail;
  bool _parentOnline = false;

  // pending requests: parentUid -> {parentName, parentEmail, requestedAt}
  final Map<String, Map<String, dynamic>> _pendingRequests = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _safeInit();
  }

  Future<void> _safeInit() async {
    try { await _loadData(); } catch (_) {}
    // MEM-02: Check mounted after each await — the widget may have been
    // disposed (back navigation, screen rotation) during the async work.
    if (!mounted) return;
    try { await _setOnline(true); } catch (_) {}
    if (!mounted) return;
    try { await _startExtraServices(); } catch (_) {}
    if (!mounted) return;
    try { await _askPermissions(); } catch (_) {}
    if (!mounted) return;
    try { await _startLocationAndAlerts(); } catch (_) {}

    final String? uid = _auth.currentUser?.uid;
    if (uid != null) {
      try { await BackgroundMonitoringService.saveChildUid(uid); } catch (_) {}
    }

    try { await BackgroundMonitoringService.startService(); } catch (_) {}

    try {
      await MonitoringForegroundService().startService(
        childName: _childName ?? 'Child',
        parentName: _connectedParentName ?? 'Parent',
      );
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 2));

    // Guard: widget may have been disposed during the 2-second delay.
    if (!mounted) return;

    try { _listenForCommandsSafe(); } catch (_) {}
    try { _listenForPendingRequests(); } catch (_) {}
    try { _listenForConnectedParent(); } catch (_) {}
  }

  Future<void> _askPermissions() async {
    try {
      await [
        Permission.camera,
        Permission.microphone,
        Permission.notification,
        Permission.location,
      ].request();
    } catch (_) {}
  }

  Future<void> _startLocationAndAlerts() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Start GPS tracking if permission is available.
    final hasLoc = await LocationService.instance.hasPermission();
    if (hasLoc) {
      await LocationService.instance.startTracking(uid);
    }

    // Start battery alert monitoring (reads threshold from Firebase and fires
    // alerts when battery drops to or below the parent-configured level).
    AlertService.instance.startBatteryMonitoring(uid);
  }

  Future<void> _setOnline(bool online) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    if (online) {
      await PresenceService.instance.startChildPresence(uid);
    } else {
      await PresenceService.instance.stopChildPresence();
    }
  }

  Future<void> _loadData() async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final DataSnapshot snap =
        await FirebaseDatabase.instance.ref('users/$uid').get();

    if (snap.value != null && mounted) {
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(snap.value as Map);
      setState(() {
        _childName = data['childName'] as String?;
        _deviceName = data['deviceName'] as String?;
      });
    }
  }

  Future<void> _startExtraServices() async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _batterySvc.startReporting(uid);

    final bool exempt = await _batterySvc.isExempt();
    if (!exempt && mounted) {
      setState(() { _showBatteryHint = true; });
    }
  }

  void _listenForConnectedParent() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _parentSub?.cancel();
    _parentSub = FirebaseDatabase.instance
        .ref('users/$uid/connectedParent')
        .onValue
        .listen((event) async {
      if (!mounted) return;
      final raw = event.snapshot.value;
      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        final parentUid = data['uid'] as String?;
        String? parentName = data['parentName'] as String?;
        String? parentEmail = data['parentEmail'] as String?;
        bool parentOnline = false;

        if (parentUid != null) {
          try {
            final parentSnap = await FirebaseDatabase.instance
                .ref('users/$parentUid')
                .get();
            if (parentSnap.value is Map) {
              final pd = Map<String, dynamic>.from(parentSnap.value as Map);
              parentName ??= pd['parentName'] as String?;
              parentEmail ??= pd['email'] as String?;
              parentOnline = pd['online'] == true;
            }
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            _connectedParentName = parentName;
            _connectedParentEmail = parentEmail;
            _parentOnline = parentOnline;
          });
        }
      } else {
        // Try reading from approvedParents node instead
        _loadConnectedParentFromApproved(uid);
      }
    });
  }

  Future<void> _loadConnectedParentFromApproved(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/$uid/approvedParents')
          .get();
      if (snap.value is Map && mounted) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        if (map.isEmpty) return;
        final firstEntry = map.entries.first;
        final parentUid = firstEntry.key as String;

        // approvedParents/$parentUid may be stored as `true` (boolean) rather
        // than a Map — guard against the type mismatch before casting.
        String? parentName;
        String? parentEmail;
        if (firstEntry.value is Map) {
          final data = Map<String, dynamic>.from(firstEntry.value as Map);
          parentName = data['parentName'] as String?;
          parentEmail = data['parentEmail'] as String?;
        }

        bool parentOnline = false;
        try {
          final parentSnap = await FirebaseDatabase.instance
              .ref('users/$parentUid')
              .get();
          if (parentSnap.value is Map) {
            final pd = Map<String, dynamic>.from(parentSnap.value as Map);
            parentName ??= pd['displayName'] as String? ?? pd['parentName'] as String?;
            parentEmail ??= pd['email'] as String?;
            parentOnline = pd['online'] == true;
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _connectedParentName = parentName;
            _connectedParentEmail = parentEmail;
            _parentOnline = parentOnline;
          });
        }
      }
    } catch (_) {}
  }

  void _listenForPendingRequests() {
    _pendingSub?.cancel();
    _pendingSub = _auth.getPendingRequestsStream().listen((event) {
      if (!mounted) return;
      final raw = event.snapshot.value;
      final updated = <String, Map<String, dynamic>>{};

      if (raw is Map) {
        for (final entry in raw.entries) {
          // Guard: value must be a Map — skip malformed or non-Map entries
          // to prevent a type-cast crash when data is unexpected.
          if (entry.value is! Map) continue;
          final parentUid = entry.key as String;
          final data = Map<String, dynamic>.from(entry.value as Map);
          final status = data['status'] as String?;
          if (status == 'pending') {
            updated[parentUid] = data;
          }
        }
      }

      setState(() {
        _pendingRequests
          ..clear()
          ..addAll(updated);
      });
    });
  }

  Future<void> _approveRequest(String parentUid) async {
    final result = await _auth.approveParentRequest(parentUid);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent connected successfully!'),
          backgroundColor: Color(0xFF34A853),
          behavior: SnackBarBehavior.floating,
        ),
      );
      final parentName =
          _pendingRequests[parentUid]?['parentName'] as String? ?? 'Parent';
      try {
        await MonitoringForegroundService().updateNotification(
          childName: _childName ?? 'Child',
          parentName: parentName,
        );
      } catch (_) {}
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Failed to connect parent.'),
          backgroundColor: const Color(0xFFEA4335),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineRequest(String parentUid) async {
    await _auth.declineParentRequest(parentUid);
  }

  void _listenForCommandsSafe() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _snapshotSub?.cancel();
    _snapshotSub =
        _snapshotSvc.watchSnapshotRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(_snapshotSvc.captureAndUpload(uid));
      }
    });

    _callLogSub?.cancel();
    _callLogSub =
        _callLogSvc.watchSyncRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(_callLogSvc.syncCallLog());
        unawaited(
          FirebaseDatabase.instance
              .ref('commands/$uid/syncCallLog/requested')
              .set(false),
        );
      }
    });

    _contactsSub?.cancel();
    _contactsSub =
        _contactsSvc.watchSyncRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(_contactsSvc.syncContacts());
        unawaited(
          FirebaseDatabase.instance
              .ref('commands/$uid/syncContacts/requested')
              .set(false),
        );
      }
    });

    _smsSub?.cancel();
    _smsSub = SmsService().watchSyncRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(SmsService().syncSms(uid));
        unawaited(
          FirebaseDatabase.instance
              .ref('commands/$uid/syncSms/requested')
              .set(false),
        );
      }
    });

    _appListSub?.cancel();
    _appListSub = FirebaseDatabase.instance
        .ref('commands/$uid/syncAppList/requested')
        .onValue
        .listen((DatabaseEvent event) async {
      if (event.snapshot.value != true) return;
      try {
        final List raw = await _kScreenCaptureCh.invokeMethod('getInstalledApps');
        final Map<String, dynamic> data = {};
        for (final item in raw) {
          final m = Map<String, dynamic>.from(item as Map);
          final pkg = m['packageName'] as String? ?? '';
          if (pkg.isEmpty) continue;
          data[pkg.replaceAll('.', '_')] = m;
        }
        await FirebaseDatabase.instance.ref('appList/$uid').set(data);
      } on PlatformException catch (_) {}
      unawaited(
        FirebaseDatabase.instance
            .ref('commands/$uid/syncAppList/requested')
            .set(false),
      );
    });

    // Listen ONLY to calls/$uid/status — not the entire calls/$uid node.
    // Listening to the whole node caused _autoStartStreaming() to fire on
    // every ICE-candidate push / answer write / heartbeat update because
    // onValue re-fires for any descendant change while status was still
    // 'calling'. Scoping to the status leaf eliminates those spurious triggers.
    _callSub?.cancel();
    _callSub = FirebaseDatabase.instance
        .ref('calls/$uid/status')
        .onValue
        .listen((DatabaseEvent event) async {
      try {
        final String? status = event.snapshot.value is String
            ? event.snapshot.value as String
            : null;
        if (status == 'calling') {
          // Fetch the mode from a sibling node (single read, not a stream).
          final modeSnap = await FirebaseDatabase.instance
              .ref('calls/$uid/mode')
              .get();
          final String modeStr =
              modeSnap.value is String ? modeSnap.value as String : 'camera';
          final StreamMode _mode =
              modeStr == 'screen' ? StreamMode.screen : StreamMode.camera;
          // WEB-02 / ARCH-01: The background-service isolate now drives
          // SilentWebRTCService directly. Calling _autoStartStreaming() here
          // would start a second, conflicting WebRTC connection from the UI
          // isolate. The background service's _callsSub already handles this.
        } else if (status == 'ended' || status == null) {
          // WEB-02: Background service handles the stop — calling stopSilent()
          // here races with the background-isolate cleanup and can leave the
          // peer connection in a half-closed state.
        }
      } catch (_) {}
    });
  }

  void _autoStartStreaming(String uid, StreamMode mode) {
    if (mode == StreamMode.screen) {
      SilentWebRTCService.instance.startSilentScreen(uid).catchError((_) {});
    } else {
      SilentWebRTCService.instance.startSilentCamera(uid).catchError((_) {});
    }
  }

  @override
  void dispose() {
    // LC-01: Do not call _setOnline(false) here — presence is managed by
    // PresenceService via .info/connected. Writing false on dispose() can
    // incorrectly mark the child offline when the Activity is recreated
    // (e.g. screen rotation) while the background service is still running.
    _callSub?.cancel();
    _snapshotSub?.cancel();
    _callLogSub?.cancel();
    _contactsSub?.cancel();
    _smsSub?.cancel();
    _appListSub?.cancel();
    _pendingSub?.cancel();
    _parentSub?.cancel();
    // FIX-01: Do NOT call SilentWebRTCService.instance.stopSilent() here.
    // WebRTC is now owned by the background-service isolate. Stopping it from
    // the UI dispose races with the background isolate and would kill an active
    // monitoring session whenever the UI is recreated (rotation, navigation).
    LocationService.instance.stopTracking();
    AlertService.instance.stopBatteryMonitoring();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String uid = _auth.currentUser?.uid ?? '';
    final String childName = _childName ?? 'Child';

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF0F4FF),
          body: CustomScrollView(
            slivers: [
              _buildSliverHeader(childName, uid),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),

                    // Pending requests
                    if (_pendingRequests.isNotEmpty) ...[
                      _PendingRequestsBanner(
                        requests: _pendingRequests,
                        onApprove: _approveRequest,
                        onDecline: _declineRequest,
                      ).animate().fadeIn().slideY(begin: -0.1, end: 0),
                      const SizedBox(height: 14),
                    ],

                    // Connected parent card
                    _ParentStatusCard(
                      parentName: _connectedParentName,
                      parentEmail: _connectedParentEmail,
                      parentOnline: _parentOnline,
                    ).animate().fadeIn(delay: 100.ms),

                    const SizedBox(height: 14),

                    // Monitoring active card
                    const _MonitoringActiveCard()
                        .animate().fadeIn(delay: 180.ms),

                    const SizedBox(height: 14),

                    // Battery warning
                    if (_showBatteryHint) ...[
                      _BatteryWarningCard()
                          .animate().fadeIn(delay: 220.ms),
                      const SizedBox(height: 14),
                    ],

                    // Screen-time streak card (child read-only view)
                    StreakCardWidget(childUid: uid)
                        .animate().fadeIn(delay: 240.ms),

                    const SizedBox(height: 14),

                    // Device ID card
                    _DeviceIdCard(uid: uid)
                        .animate().fadeIn(delay: 280.ms),

                    const SizedBox(height: 14),

                    // QR button
                    _ShowQrButton(uid: uid, childName: childName)
                        .animate().fadeIn(delay: 320.ms),

                    const SizedBox(height: 14),

                    // SOS panic button
                    _PanicButton(uid: uid)
                        .animate().fadeIn(delay: 360.ms),
                  ]),
                ),
              ),
            ],
          ),
        ),

        if (_locked) const _LockOverlay(),
      ],
    );
  }

  Widget _buildSliverHeader(String childName, String uid) {
    final initials = childName.isNotEmpty
        ? childName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : 'C';

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      elevation: 0,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          initials,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hi, $childName!',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            if (_deviceName != null)
                              Text(
                                _deviceName!,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_pendingRequests.isNotEmpty)
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications_active,
                                  color: Colors.white),
                              onPressed: () {},
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEA4335),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${_pendingRequests.length}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 9),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF34A853),
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat())
                            .fadeOut(duration: 900.ms)
                            .then()
                            .fadeIn(duration: 900.ms),
                        const SizedBox(width: 6),
                        Text(
                          'Monitoring Active',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Connected Parent Status Card
// ─────────────────────────────────────────────────

class _ParentStatusCard extends StatelessWidget {
  final String? parentName;
  final String? parentEmail;
  final bool parentOnline;

  const _ParentStatusCard({
    this.parentName,
    this.parentEmail,
    this.parentOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool connected = parentName != null;
    final initials = connected && parentName!.trim().isNotEmpty
        ? parentName!.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : 'P';

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: connected
                      ? const Color(0xFFE8F0FE)
                      : const Color(0xFFF1F3F4),
                  child: Text(
                    initials,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: connected
                          ? const Color(0xFF1A73E8)
                          : const Color(0xFF9AA0A6),
                    ),
                  ),
                ),
                if (connected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: parentOnline
                            ? const Color(0xFF34A853)
                            : const Color(0xFF9AA0A6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: connected
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parentName!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF202124),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (parentEmail != null)
                          Text(
                            parentEmail!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF5F6368),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: parentOnline
                                    ? const Color(0xFF34A853)
                                    : const Color(0xFF9AA0A6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              parentOnline ? 'Online now' : 'Offline',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: parentOnline
                                    ? const Color(0xFF34A853)
                                    : const Color(0xFF9AA0A6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No parent connected',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF5F6368),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ask your parent to scan the QR code below',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF9AA0A6),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFFE6F4EA)
                    : const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                connected ? 'Connected' : 'Waiting',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: connected
                      ? const Color(0xFF34A853)
                      : const Color(0xFF9AA0A6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Monitoring Active Card
// ─────────────────────────────────────────────────

class _MonitoringActiveCard extends StatelessWidget {
  const _MonitoringActiveCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Protection Active',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This device is being monitored by a parent',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: Color(0xFF81C995), size: 22),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Battery Warning Card
// ─────────────────────────────────────────────────

class _BatteryWarningCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.battery_alert,
                color: Color(0xFFE65100), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Battery Optimisation On',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE65100),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'May interrupt background monitoring. Disable it in Settings.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFFBF360C),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Device ID Card
// ─────────────────────────────────────────────────

class _DeviceIdCard extends StatelessWidget {
  final String uid;
  const _DeviceIdCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    final shortId = uid.length > 16 ? '${uid.substring(0, 8)}...${uid.substring(uid.length - 8)}' : uid;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phone_android,
                  color: Color(0xFF5F6368), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device ID',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF9AA0A6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shortId,
                    style: GoogleFonts.robotoMono(
                      fontSize: 13,
                      color: const Color(0xFF202124),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined,
                  color: Color(0xFF9AA0A6), size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: uid));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Device ID copied'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Pending Requests Banner
// ─────────────────────────────────────────────────

class _PendingRequestsBanner extends StatelessWidget {
  final Map<String, Map<String, dynamic>> requests;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onDecline;

  const _PendingRequestsBanner({
    required this.requests,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEA4335).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA4335).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.supervisor_account,
                    color: Color(0xFFEA4335), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Parent Connection Request${requests.length > 1 ? 's' : ''}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFEA4335),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...requests.entries.map((entry) {
            final parentUid = entry.key;
            final data = entry.value;
            final parentName =
                data['parentName'] as String? ?? 'Unknown Parent';
            final parentEmail = data['parentEmail'] as String? ?? '';

            return _RequestTile(
              parentName: parentName,
              parentEmail: parentEmail,
              onApprove: () => onApprove(parentUid),
              onDecline: () => onDecline(parentUid),
            );
          }),
        ],
      ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  final String parentName;
  final String parentEmail;
  final Future<void> Function() onApprove;
  final Future<void> Function() onDecline;

  const _RequestTile({
    required this.parentName,
    required this.parentEmail,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE8F0FE),
            radius: 22,
            child: Text(
              widget.parentName.isNotEmpty
                  ? widget.parentName[0].toUpperCase()
                  : 'P',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A73E8),
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.parentName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.parentEmail.isNotEmpty)
                  Text(
                    widget.parentEmail,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF5F6368)),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEA4335),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
              onPressed: () async {
                setState(() => _loading = true);
                await widget.onDecline();
                if (mounted) setState(() => _loading = false);
              },
              child: const Text('Decline'),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF34A853),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                setState(() => _loading = true);
                await widget.onApprove();
                if (mounted) setState(() => _loading = false);
              },
              child: const Text('Allow', style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Lock Overlay
// ─────────────────────────────────────────────────

class _LockOverlay extends StatelessWidget {
  const _LockOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 72, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Device Locked',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Locked by your parent',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// SOS / Panic Button
// ─────────────────────────────────────────────────

class _PanicButton extends StatefulWidget {
  final String uid;
  const _PanicButton({required this.uid});

  @override
  State<_PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<_PanicButton>
    with SingleTickerProviderStateMixin {
  bool _sending = false;
  bool _holding = false;
  double _progress = 0;
  late AnimationController _anim;

  static const _kHoldSeconds = 3;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _kHoldSeconds),
    )..addListener(() {
        if (mounted) setState(() => _progress = _anim.value);
      });
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.completed) _firePanic();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_sending) return;
    setState(() => _holding = true);
    _anim.forward(from: 0);
  }

  void _cancelHold() {
    _anim.stop();
    _anim.reset();
    if (mounted) setState(() { _holding = false; _progress = 0; });
  }

  Future<void> _firePanic() async {
    setState(() { _holding = false; _sending = true; _progress = 0; });
    try {
      await PanicService().sendPanic(widget.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🚨 SOS alert sent to your parent with your location'),
          backgroundColor: Color(0xFFEA4335),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send SOS: $e'),
          backgroundColor: Colors.grey,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _cancelHold(),
      onLongPressCancel: _cancelHold,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: _holding
              ? const Color(0xFFEA4335)
              : const Color(0xFFFCE8E6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFEA4335).withValues(alpha: 0.5)),
        ),
        child: Stack(children: [
          // Hold-progress fill
          if (_holding)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: const Color(0xFFEA4335),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFF7043)),
                  minHeight: double.infinity,
                ),
              ),
            ),
          Center(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_sending)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFEA4335)),
                )
              else
                Icon(
                  Icons.sos_outlined,
                  size: 22,
                  color: _holding
                      ? Colors.white
                      : const Color(0xFFEA4335),
                ),
              const SizedBox(width: 10),
              Text(
                _sending
                    ? 'Sending SOS…'
                    : _holding
                        ? 'Hold to send SOS…'
                        : 'Hold 3s to send SOS',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _holding
                      ? Colors.white
                      : const Color(0xFFEA4335),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Show QR Button
// ─────────────────────────────────────────────────

class _ShowQrButton extends StatelessWidget {
  final String uid;
  final String childName;
  const _ShowQrButton({required this.uid, required this.childName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChildQrScreen(uid: uid, childName: childName),
            ),
          );
        },
        icon: const Icon(Icons.qr_code_2, color: Color(0xFF1A73E8)),
        label: Text(
          'Show Pairing QR Code',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w600, color: const Color(0xFF1A73E8)),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF1A73E8)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
