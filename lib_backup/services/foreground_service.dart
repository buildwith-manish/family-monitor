import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _MonitoringTaskHandler extends TaskHandler {
  int _heartbeatCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    _heartbeatCount++;
    // Update Firebase presence every 30 s
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance
            .ref('users/$uid/lastSeen')
            .set(ServerValue.timestamp);
        // Clean up stale call rooms older than 10 minutes
        if (_heartbeatCount % 20 == 0) {
          await _cleanupStaleSessions(uid);
        }
      }
    } catch (e) {
      debugPrint('[TaskHandler] heartbeat error: $e');
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

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[TaskHandler] onDestroy');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/child/home');
  }
}
