import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// ARCH-01: The foreground task handler no longer owns WebRTC.  After the
// ARCH-01 fix, the background-service isolate (background_monitoring_service.dart)
// drives SilentWebRTCService directly.  This handler's sole responsibilities are:
//   1. Keeping the persistent "Monitoring active" notification alive.
//   2. Writing a lastSeen heartbeat to Firebase every 30 s.
//   3. Cleaning up stale call sessions every ~10 minutes.
//
// ARCH-03: isOnline is intentionally NOT written here.  PresenceService (via
// .info/connected) is the sole owner of the isOnline flag.  Writing it here
// caused a race condition that masked true disconnections.
class _MonitoringTaskHandler extends TaskHandler {
  int _heartbeatCount = 0;
  String? _childUid;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart');
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
        debugPrint('[TaskHandler] Firebase initialised');
      } catch (e) {
        debugPrint('[TaskHandler] Firebase init error: $e');
      }
    }
    await _loadUid();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    _heartbeatCount++;
    // FIX-07: Do NOT write lastSeen here — the background-service isolate
    // (background_monitoring_service.dart _heartbeatTimer) already writes it
    // every 30 s. Writing it here too creates a race condition and doubles
    // Firebase write costs. Stale-session cleanup is retained as it is low-
    // frequency (every 20 ticks = ~10 min) and harmless to run twice.
    if (_childUid == null) {
      await _loadUid();
    }
    try {
      final uid = _childUid;
      if (uid != null && _heartbeatCount % 20 == 0) {
        await _cleanupStaleSessions(uid);
      }
    } catch (e) {
      debugPrint('[TaskHandler] cleanup error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[TaskHandler] onDestroy');
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
