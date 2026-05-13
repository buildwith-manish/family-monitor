import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/auth_service.dart';
import 'child_qr_screen.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/battery_service.dart';
import '../../services/call_log_service.dart';
import '../../services/contacts_service.dart';
import '../../services/remote_lock_service.dart';
import '../../services/silent_webrtc_service.dart';
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
  final RemoteLockService _lockSvc = RemoteLockService();
  final CallLogService _callLogSvc = CallLogService();
  final ContactsService _contactsSvc = ContactsService();
  final SnapshotService _snapshotSvc = SnapshotService();
  final BatteryService _batterySvc = BatteryService();

  bool _showBatteryHint = false;

  StreamSubscription? _smsSub;
  StreamSubscription? _callSub;
  StreamSubscription? _lockSub;
  StreamSubscription? _snapshotSub;
  StreamSubscription? _callLogSub;
  StreamSubscription? _contactsSub;
  StreamSubscription? _pendingSub;

  bool _locked = false;
  String? _childName;

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
    try { await _setOnline(true); } catch (_) {}
    try { await _startExtraServices(); } catch (_) {}
    try { await _askPermissions(); } catch (_) {}
    try { await BackgroundMonitoringService.startService(); } catch (_) {}

    await Future.delayed(const Duration(seconds: 2));

    try { _listenForCommandsSafe(); } catch (_) {}
    try { _listenForPendingRequests(); } catch (_) {}
  }

  Future<void> _askPermissions() async {
    try {
      await [
        Permission.camera,
        Permission.microphone,
        Permission.notification,
      ].request();
    } catch (_) {}
  }

  Future<void> _setOnline(bool online) async {
    await _auth.setChildOnlineStatus(online);
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

  void _listenForPendingRequests() {
    _pendingSub = _auth.getPendingRequestsStream().listen((event) {
      if (!mounted) return;
      final raw = event.snapshot.value;
      final updated = <String, Map<String, dynamic>>{};

      if (raw is Map) {
        for (final entry in raw.entries) {
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
    await _auth.approveParentRequest(parentUid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent connected successfully!'),
          backgroundColor: Color(0xFF34A853),
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

    _lockSub = _lockSvc.watchLockState(uid).listen((state) {
      if (!mounted) return;
      final bool shouldLock = state.locked ||
          (state.schedule != null &&
              RemoteLockService().shouldBeLocked(state.schedule!));
      setState(() { _locked = shouldLock; });
    });

    _snapshotSub =
        _snapshotSvc.watchSnapshotRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(_snapshotSvc.captureAndUpload(uid));
      }
    });

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

    _callSub = FirebaseDatabase.instance
        .ref('calls/$uid')
        .onValue
        .listen((DatabaseEvent event) async {
      try {
        final Object? data = event.snapshot.value;
        if (data == null || data is! Map) return;
        final Map<String, dynamic> map = Map<String, dynamic>.from(data);
        final String? status = map['status'] as String?;
        if (status == 'calling') {
          final String modeStr = map['mode'] as String? ?? 'camera';
          final StreamMode mode =
              modeStr == 'screen' ? StreamMode.screen : StreamMode.camera;
          _autoStartStreaming(uid, mode);
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
    _setOnline(false);
    _smsSub?.cancel();
    _callSub?.cancel();
    _lockSub?.cancel();
    _snapshotSub?.cancel();
    _callLogSub?.cancel();
    _contactsSub?.cancel();
    _pendingSub?.cancel();
    SilentWebRTCService.instance.stopSilent();
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
          backgroundColor: const Color(0xFFF4F6F9),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Hi, $childName 👋',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF202124),
              ),
            ),
            actions: [
              if (_pendingRequests.isNotEmpty)
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_active,
                          color: Color(0xFFEA4335)),
                      onPressed: () => _scrollToPending(),
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DeviceIdCard(uid: uid).animate().fadeIn(),

                const SizedBox(height: 12),

                // ── Pending parent requests ──
                if (_pendingRequests.isNotEmpty) ...[
                  _PendingRequestsBanner(
                    requests: _pendingRequests,
                    onApprove: _approveRequest,
                    onDecline: _declineRequest,
                  ).animate().fadeIn().slideY(begin: -0.1, end: 0),
                  const SizedBox(height: 12),
                ],

                if (_showBatteryHint)
                  const Card(
                    color: Color(0xFFFFF8E1),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.battery_alert),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Battery optimisation may interrupt monitoring.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                const _MonitoringInfoCard(),
                const SizedBox(height: 16),
                _ShowQrButton(uid: uid, childName: childName),
              ],
            ),
          ),
        ),

        if (_locked) const _LockOverlay(),
      ],
    );
  }

  void _scrollToPending() {
    // Already visible in the list — just a no-op hint
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
        border: Border.all(color: const Color(0xFFEA4335).withValues(alpha: 0.4)),
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
// Existing widgets (unchanged)
// ─────────────────────────────────────────────────

class _DeviceIdCard extends StatelessWidget {
  final String uid;
  const _DeviceIdCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.phone_android),
            const SizedBox(width: 12),
            Expanded(
              child: Text(uid, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitoringInfoCard extends StatelessWidget {
  const _MonitoringInfoCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.security),
            SizedBox(width: 12),
            Expanded(child: Text('Device is ready for monitoring')),
          ],
        ),
      ),
    );
  }
}

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
        icon: const Icon(Icons.qr_code_2, color: Color(0xFF34A853)),
        label: Text(
          'Show QR Code',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w600, color: const Color(0xFF34A853)),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF34A853)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
