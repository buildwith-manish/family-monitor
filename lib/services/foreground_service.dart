import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_webrtc_service.dart';

class MonitoringForegroundService {
  static final MonitoringForegroundService _instance =
      MonitoringForegroundService._internal();
  factory MonitoringForegroundService() => _instance;
  MonitoringForegroundService._internal();

  static bool _initialized = false;

  /// Call once from main() before runApp.
  static void initForegroundTask() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'family_monitor_channel',
        channelName: 'Family Monitor',
        channelDescription: 'Shows when your device is being monitored.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000), // 30 s heartbeat
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static String _buildTitle({required String childName, required String parentName}) =>
      '$childName — Monitored by $parentName';

  static String _buildBody({
    required bool cameraActive,
    required bool audioActive,
    required bool screenActive,
  }) {
    final active = <String>[
      if (cameraActive) 'Camera',
      if (audioActive) 'Audio',
      if (screenActive) 'Screen',
    ];
    return active.isEmpty ? 'Monitoring active' : 'Sharing: ${active.join(', ')}';
  }

  Future<void> startService({
    required String childName,
    required String parentName,
    bool cameraActive = false,
    bool audioActive = false,
    bool screenActive = false,
  }) async {
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        await updateNotification(
          childName: childName,
          parentName: parentName,
          cameraActive: cameraActive,
          audioActive: audioActive,
          screenActive: screenActive,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        notificationTitle: _buildTitle(childName: childName, parentName: parentName),
        notificationText: _buildBody(
          cameraActive: cameraActive,
          audioActive: audioActive,
          screenActive: screenActive,
        ),
        callback: _startCallback,
      );
    } catch (e) {
      debugPrint('[ForegroundService] startService error: $e');
    }
  }

  Future<void> updateNotification({
    required String childName,
    required String parentName,
    bool cameraActive = false,
    bool audioActive = false,
    bool screenActive = false,
  }) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _buildTitle(childName: childName, parentName: parentName),
        notificationText: _buildBody(
          cameraActive: cameraActive,
          audioActive: audioActive,
          screenActive: screenActive,
        ),
      );
    } catch (e) {
      debugPrint('[ForegroundService] updateNotification error: $e');
    }
  }

  Future<void> stopService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('[ForegroundService] stopService error: $e');
    }
  }

  Future<bool> get isRunning async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Foreground task entry point — runs in its own Dart isolate
// with full plugin access via DartPluginRegistrant.
// This keeps monitoring alive when the app is closed (swiped
// away). Android restarts it via START_STICKY automatically.
// ─────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _MonitoringTaskHandler extends TaskHandler {
  int _heartbeatCount = 0;
  String? _childUid;

  StreamSubscription? _callSub;
  StreamSubscription? _bgStreamSub;
  StreamSubscription? _bgStopSub;

  bool _streamActive = false;
  String? _activeStreamMode;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart');

    // Register Flutter plugins so camera, Firebase, etc. are accessible
    DartPluginRegistrant.ensureInitialized();

    // Initialise Firebase if this isolate started fresh (app was closed)
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
        debugPrint('[TaskHandler] Firebase initialised');
      } catch (e) {
        debugPrint('[TaskHandler] Firebase init error: $e');
      }
    }

    // Load child UID from SharedPreferences (persisted on first login)
    await _loadUid();

    if (_childUid != null) {
      _subscribeFirebase(_childUid!);
    }

    // Secondary trigger: forward events from the background-service isolate.
    // Covers the edge case where the bg-service detects a call before us.
    try {
      _bgStreamSub =
          FlutterBackgroundService().on('silent_stream').listen((data) async {
        if (data == null || data is! Map) return;
        final uid = data['uid'] as String?;
        final mode = (data['mode'] as String?) ?? 'camera';
        if (uid == null) return;
        await _handleStream(uid, mode);
      });

      _bgStopSub =
          FlutterBackgroundService().on('silent_stop').listen((_) async {
        await _stopStream();
      });
    } catch (e) {
      debugPrint('[TaskHandler] bg-service listener error: $e');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    _heartbeatCount++;

    // Retry UID resolution on every tick until one is available
    if (_childUid == null) {
      await _loadUid();
      if (_childUid != null) {
        _subscribeFirebase(_childUid!);
        debugPrint('[TaskHandler] UID resolved on repeat: $_childUid');
      }
    }

    // Firebase presence heartbeat — keeps child shown as online
    try {
      final uid = _childUid ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance
            .ref('users/$uid/lastSeen')
            .set(ServerValue.timestamp);
        await FirebaseDatabase.instance
            .ref('users/$uid/isOnline')
            .set(true);

        if (_heartbeatCount % 20 == 0) {
          await _cleanupStaleSessions(uid);
        }
      }
    } catch (e) {
      debugPrint('[TaskHandler] heartbeat error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[TaskHandler] onDestroy');
    _callSub?.cancel();
    _bgStreamSub?.cancel();
    _bgStopSub?.cancel();
    await _stopStream();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/child/home');
  }

  // ── Internal helpers ───────────────────────────────────────

  Future<void> _loadUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _childUid = prefs.getString('child_uid')
          ?? FirebaseAuth.instance.currentUser?.uid;
    } catch (e) {
      debugPrint('[TaskHandler] UID load error: $e');
    }
  }

  /// Subscribe directly to Firebase `calls/$uid` so WebRTC streaming
  /// starts even when the Flutter UI isolate (main app) is no longer alive.
  void _subscribeFirebase(String uid) {
    _callSub?.cancel();
    _callSub = FirebaseDatabase.instance
        .ref('calls/$uid')
        .onValue
        .listen((event) async {
      final data = event.snapshot.value;

      if (data == null || data is! Map) {
        await _stopStream();
        return;
      }

      final map = Map<String, dynamic>.from(data);
      final status = map['status'] as String?;
      final mode = (map['mode'] as String?) ?? 'camera';

      if (status == 'calling') {
        await _handleStream(uid, mode);
      } else if (status == 'ended' || status == null) {
        await _stopStream();
      }
    });

    debugPrint('[TaskHandler] Subscribed to Firebase calls/$uid');
  }

  Future<void> _handleStream(String uid, String mode) async {
    // Already streaming the same mode — nothing to do
    if (_streamActive && _activeStreamMode == mode) return;

    // Mode switched — stop the previous stream first
    if (_streamActive) await _stopStream();

    _streamActive = true;
    _activeStreamMode = mode;

    debugPrint('[TaskHandler] Starting stream — mode: $mode uid: $uid');

    try {
      if (mode == 'screen') {
        await SilentWebRTCService.instance.startSilentScreen(uid);
      } else {
        await SilentWebRTCService.instance.startSilentCamera(uid);
      }
    } catch (e) {
      debugPrint('[TaskHandler] stream start error: $e');
      _streamActive = false;
      _activeStreamMode = null;
    }
  }

  Future<void> _stopStream() async {
    if (!_streamActive) return;
    _streamActive = false;
    _activeStreamMode = null;
    try {
      await SilentWebRTCService.instance.stopSilent();
    } catch (e) {
      debugPrint('[TaskHandler] stopStream error: $e');
    }
    debugPrint('[TaskHandler] Stream stopped');
  }

  Future<void> _cleanupStaleSessions(String uid) async {
    try {
      final ref = FirebaseDatabase.instance.ref('calls/$uid');
      final snap = await ref.get();
      if (snap.value == null) return;
      final data = Map<String, dynamic>.from(snap.value as Map);
      final status = data['status'] as String?;
      final ts = data['startedAt'] as int?;
      if (status == 'calling' && ts != null) {
        final age = DateTime.now().millisecondsSinceEpoch - ts;
        if (age > 10 * 60 * 1000) {
          debugPrint('[TaskHandler] Cleaning stale session');
          await ref.remove();
        }
      }
    } catch (_) {}
  }
}
