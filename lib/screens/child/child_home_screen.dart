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

  bool _locked = false;
  String? _childName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _safeInit();
  }

  Future<void> _safeInit() async {
    try {
      await _loadData();
    } catch (_) {}

    try {
      await _setOnline(true);
    } catch (_) {}

    try {
      await _startExtraServices();
    } catch (_) {}

    try {
      await _askPermissions();
    } catch (_) {}

    try {
      await BackgroundMonitoringService.startService();
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 2));

    try {
      _listenForCommandsSafe();
    } catch (_) {}
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
      setState(() {
        _showBatteryHint = true;
      });
    }
  }
  void _listenForCommandsSafe() {
    final String? uid = _auth.currentUser?.uid;

    if (uid == null) return;

    _lockSub = _lockSvc.watchLockState(uid).listen((state) {
      if (!mounted) return;

      final bool shouldLock = state.locked ||
          (state.schedule != null &&
              RemoteLockService().shouldBeLocked(state.schedule!));

      setState(() {
        _locked = shouldLock;
      });
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

        final Map<String, dynamic> map =
            Map<String, dynamic>.from(data);

        final String? status = map['status'] as String?;

        if (status == 'calling') {
          final String modeStr =
              map['mode'] as String? ?? 'camera';

          final StreamMode mode =
              modeStr == 'screen'
                  ? StreamMode.screen
                  : StreamMode.camera;

          _autoStartStreaming(uid, mode);
        }
      } catch (_) {}
    });
  }

  void _autoStartStreaming(String uid, StreamMode mode) {
    if (mode == StreamMode.screen) {
      SilentWebRTCService.instance
          .startSilentScreen(uid)
          .catchError((_) {});
    } else {
      SilentWebRTCService.instance
          .startSilentCamera(uid)
          .catchError((_) {});
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
          ),

          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DeviceIdCard(uid: uid)
                    .animate()
                    .fadeIn(),

                const SizedBox(height: 12),

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
}
class _DeviceIdCard extends StatelessWidget {
  final String uid;

  const _DeviceIdCard({
    required this.uid,
  });

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
              child: Text(
                uid,
                overflow: TextOverflow.ellipsis,
              ),
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
            Expanded(
              child: Text(
                'Device is ready for monitoring',
              ),
            ),
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
            const Icon(
              Icons.lock_outline,
              size: 72,
              color: Colors.white,
            ),

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
              style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 14,
              ),
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
              builder: (_) =>
                  ChildQrScreen(uid: uid, childName: childName),
            ),
          );
        },
        icon: const Icon(Icons.qr_code_2, color: Color(0xFF34A853)),
        label: Text(
          'Show QR Code',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF34A853)),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF34A853)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
