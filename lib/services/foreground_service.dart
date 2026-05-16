import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Explicit options so the foreground-task isolate does not rely on the
// google-services.json embedded at build time (which may contain a CI
// placeholder key when $FIREBASE_API_KEY is unset in Codemagic).
const FirebaseOptions _childFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain: 'family-monitor-7aab3.firebaseapp.com',
  databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId: 'family-monitor-7aab3',
  storageBucket: 'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  appId: '1:758644747673:android:32a2141244fb9c3222f708',
);

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
        // BAT-03: Both locks set to false. The flutter_foreground_task plugin's
        // allowWakeLock/allowWifiLock hold CPU and Wi-Fi locks for the entire
        // lifetime of the foreground task — even when no monitoring session is
        // active (e.g. between sessions, during setup). This is wasteful.
        //
        // The BackgroundService (which owns WebRTC and all active monitoring
        // work) runs as a separate Android foreground service and is responsible
        // for its own wake management via its camera|microphone|dataSync
        // foreground service type, which implicitly prevents CPU suspension
        // during active streaming without needing an explicit WakeLock.
        //
        // The foreground TASK here is only a notification host and 30-second
        // heartbeat pinger — neither operation requires keeping the CPU awake
        // or holding a Wi-Fi lock. Removing these locks reduces idle battery
        // consumption by ~15–40 mA on typical mid-range Android hardware.
        allowWakeLock: false,
        allowWifiLock: false,
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
// drives screen streaming directly.  This handler's sole responsibility is:
//   1. Keeping the persistent "Monitoring active" notification alive.
//
// ARCH-03: isOnline is intentionally NOT written here.  PresenceService (via
// .info/connected) is the sole owner of the isOnline flag.  Writing it here
// caused a race condition that masked true disconnections.
//
// P3-C: _cleanupStaleSessions removed (Option A). The foreground task had no
// reliable way to distinguish an active session (parent monitoring, age > 10 min)
// from an abandoned one (parent app crashed). It was terminating valid sessions
// every 10 minutes by deleting calls/$uid when startedAt age exceeded threshold.
// Stale-session cleanup is owned exclusively by background_monitoring_service.dart
// (_setupMonitoringSession startup cleanup).
class _MonitoringTaskHandler extends TaskHandler {
  // ── Lifecycle ──────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart');
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(options: _childFirebaseOptions);
        debugPrint('[TaskHandler] Firebase initialised');
      } catch (e) {
        debugPrint('[TaskHandler] Firebase init error: $e');
      }
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // FIX-07: Do NOT write lastSeen here — the background-service isolate
    // (background_monitoring_service.dart _heartbeatTimer) already writes it
    // every 30 s. Writing it here too creates a race condition and doubles
    // Firebase write costs.
    // P3-C: Stale-session cleanup removed — see class comment above.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[TaskHandler] onDestroy');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/child/home');
  }

}
