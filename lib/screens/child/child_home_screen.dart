import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/battery_service.dart';
import '../../services/call_log_service.dart';
import '../../services/contacts_service.dart';
import '../../services/remote_lock_service.dart';
import '../../services/screen_time_service.dart';
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
  final RemoteLockService _lockSvc = RemoteLockService();
  final CallLogService _callLogSvc = CallLogService();
  final ContactsService _contactsSvc = ContactsService();
  final SnapshotService _snapshotSvc = SnapshotService();
  final ScreenTimeService _screenTimeSvc = ScreenTimeService();
  final BatteryService _batterySvc = BatteryService();
  final SmsService _smsSvc = SmsService();

  bool _showBatteryHint = false;

  StreamSubscription? _smsSub;
  StreamSubscription? _callSub;
  StreamSubscription? _lockSub;
  StreamSubscription? _snapshotSub;
  StreamSubscription? _callLogSub;
  StreamSubscription? _contactsSub;
  StreamSubscription? _requestsSub;
  StreamSubscription? _approvedParentsSub;

  final Map<String, dynamic> _pendingRequests = <String, dynamic>{};
  final Map<String, dynamic> _approvedParents = <String, dynamic>{};

  String? _childName;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _safeInit();
  }

  Future<void> _safeInit() async {
    try { await _loadData(); } catch (_) {}
    try { _listenForRequests(); } catch (_) {}
    try { await _setOnline(true); } catch (_) {}
    try { await _startExtraServices(); } catch (_) {}
    try { await _askPermissions(); } catch (_) {}
    try { await BackgroundMonitoringService.startService(); } catch (_) {}
    await Future.delayed(const Duration(seconds: 3));
    try { _listenForCommandsSafe(); } catch (_) {}
  }

  Future<void> _askPermissions() async {
    try {
      final List<Permission> perms = <Permission>[
        Permission.camera,
        Permission.microphone,
      ];
      if (await Permission.notification.status != PermissionStatus.granted) {
        perms.add(Permission.notification);
      }
      await perms.request();
    } catch (_) {}
  }

  Future<void> _checkBatteryHint() async {
    final bool exempt = await _batterySvc.isExempt();
    if (exempt) {
      await _batterySvc.resetFailureCount();
      if (mounted) setState(() => _showBatteryHint = false);
      return;
    }
    final bool show = await _batterySvc.recordMonitoringFailure();
    if (show && mounted) setState(() => _showBatteryHint = true);
  }

  void _openBatteryGuide() {
    Navigator.pushNamed(context, '/child/battery-guide');
  }

  @override
  void dispose() {
    _setOnline(false);
    _lockSub?.cancel();
    _snapshotSub?.cancel();
    _callLogSub?.cancel();
    _contactsSub?.cancel();
    _smsSub?.cancel();
    _callSub?.cancel();
    _requestsSub?.cancel();
    _approvedParentsSub?.cancel();
    SilentWebRTCService.instance.stopSilent();
    _batterySvc.stopReporting();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
      _screenTimeSvc.uploadUsage();
    }
  }

  Future<void> _setOnline(bool online) async {
    await _auth.setChildOnlineStatus(online);
  }

  Future<void> _startExtraServices() async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _batterySvc.startReporting(uid);
    unawaited(_checkBatteryHint());

    try {
      _smsSub = _smsSvc.watchSyncRequest(uid).listen((bool req) {
        if (req) {
          try { _smsSvc.syncSms(uid); } catch (_) {}
          try {
            FirebaseDatabase.instance
                .ref('commands/$uid/syncSms/requested')
                .set(false);
          } catch (_) {}
        }
      });
    } catch (_) {}

    try { _screenTimeSvc.uploadUsage(); } catch (_) {}
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

  void _listenForRequests() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _requestsSub = FirebaseDatabase.instance
        .ref('users/$uid/pendingParentRequests')
        .onValue
        .listen((DatabaseEvent event) {
      if (!mounted) return;
      final Object? raw = event.snapshot.value;
      if (raw is Map) {
        setState(() {
          _pendingRequests
            ..clear()
            ..addAll(Map<String, dynamic>.from(raw));
        });
      } else {
        setState(() { _pendingRequests.clear(); });
      }
    });

    _approvedParentsSub = FirebaseDatabase.instance
        .ref('users/$uid/approvedParents')
        .onValue
        .listen((DatabaseEvent event) {
      if (!mounted) return;
      final Object? raw = event.snapshot.value;
      if (raw is Map) {
        setState(() {
          _approvedParents
            ..clear()
            ..addAll(Map<String, dynamic>.from(raw));
        });
      } else {
        setState(() { _approvedParents.clear(); });
      }
    });
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

    _snapshotSub = _snapshotSvc
        .watchSnapshotRequest(uid)
        .listen((bool requested) {
      if (requested) unawaited(_snapshotSvc.captureAndUpload(uid));
    });

    _callLogSub = _callLogSvc.watchSyncRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(_callLogSvc.syncCallLog());
        unawaited(FirebaseDatabase.instance
            .ref('commands/$uid/syncCallLog/requested')
            .set(false));
      }
    });

    _contactsSub = _contactsSvc.watchSyncRequest(uid).listen((bool requested) {
      if (requested) {
        unawaited(_contactsSvc.syncContacts());
        unawaited(FirebaseDatabase.instance
            .ref('commands/$uid/syncContacts/requested')
            .set(false));
      }
    });

    _callSub = FirebaseDatabase.instance
        .ref('calls/$uid')
        .onValue
        .listen((DatabaseEvent event) async {
      try {
        if (!mounted) return;
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

  Future<void> _approveParent(String parentUid) async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final String childName = _childName ?? 'Child';

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
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await FirebaseDatabase.instance
        .ref('users/$uid/pendingParentRequests/$parentUid')
        .remove();
  }

  @override
  Widget build(BuildContext context) {
    final String uid = _auth.currentUser?.uid ?? '';
    final String childName = _childName ?? 'Child';

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8FAFB),
          appBar: AppBar(
            title: Text('Hi, $childName 👋'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (String value) async {
                  if (value == 'signout') {
                    await _auth.signOut();
                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    Navigator.pushReplacementNamed(context, '/');
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
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DeviceIdCard(uid: uid)
                      .animate()
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 12),

                  if (_showBatteryHint)
                    Card(
                      color: const Color(0xFFFFF8E1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.battery_alert,
                              color: Color(0xFFF9A825),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Monitoring may have been interrupted. '
                                'Check battery optimisation settings.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: _openBatteryGuide,
                              child: const Text('Fix'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  if (_pendingRequests.isNotEmpty) ...[
                    const _SectionHeader(
                      title: 'Connection Requests',
                      subtitle: 'Parents waiting for approval',
                    ),
                    const SizedBox(height: 8),
                    ..._pendingRequests.entries.toList().asMap().entries.map(
                      (entry) {
                        final String parentUid = entry.value.key;
                        final Map<String, dynamic> reqData =
                            Map<String, dynamic>.from(
                          entry.value.value as Map,
                        );
                        return _PendingRequestCard(
                          parentUid: parentUid,
                          requestData: reqData,
                          delay: entry.key * 100,
                          onApprove: () => _approveParent(parentUid),
                          onDecline: () => _declineParent(parentUid),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  const _SectionHeader(
                    title: 'Approved Parents',
                    subtitle: 'Parents who can monitor this device',
                  ),
                  const SizedBox(height: 8),

                  if (_approvedParents.isEmpty)
                    const _EmptyApprovedCard()
                  else
                    ..._approvedParents.keys.toList().asMap().entries.map(
                      (entry) => _ApprovedParentCard(
                        parentUid: entry.value,
                        delay: entry.key * 100,
                      ),
                    ),

                  const SizedBox(height: 24),
                  const _MonitoringInfoCard(),
                ],
              ),
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

  const _DeviceIdCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device ID',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              uid,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(requestData['name'] as String? ?? 'Unknown Parent'),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onDecline,
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyApprovedCard extends StatelessWidget {
  const _EmptyApprovedCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No approved parents yet',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedParentCard extends StatelessWidget {
  final String parentUid;
  final int delay;

  const _ApprovedParentCard({
    required this.parentUid,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF34A853)),
        title: Text(
          parentUid,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('Monitoring access granted', style: TextStyle(fontSize: 11)),
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
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.security, size: 32),
            SizedBox(height: 8),
            Text('This device is ready for monitoring'),
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
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Device Locked',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ],
        ),
      ),
    );
  }
}
