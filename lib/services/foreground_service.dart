import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the Android foreground service notification that keeps
/// monitoring alive when the child exits the app, and visibly informs
/// the child of exactly what is being monitored.
class MonitoringForegroundService {
  static final MonitoringForegroundService _instance =
      MonitoringForegroundService._internal();
  factory MonitoringForegroundService() => _instance;
  MonitoringForegroundService._internal();

  // ── Static initialisation (call once at app start) ───────────────────────────
  static void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'family_monitor_channel',
        channelName: 'Family Monitor',
        channelDescription:
            'Shows when your device is being monitored by a parent.',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  // ── Build notification text ───────────────────────────────────────────────────
  String _buildTitle({
    required String childName,
    required String parentName,
  }) {
    return '$childName — Monitored by $parentName';
  }

  String _buildBody({
    required bool cameraActive,
    required bool audioActive,
    required bool screenActive,
  }) {
    final List<String> active = [];
    if (cameraActive) active.add('Camera');
    if (audioActive) active.add('Audio');
    if (screenActive) active.add('Screen');

    if (active.isEmpty) return 'Monitoring paused — no streams active';
    return 'Sharing: ${active.join(', ')} • Tap to open app';
  }

  // ── Start the foreground service ──────────────────────────────────────────────
  Future<void> startService({
    required String childName,
    required String parentName,
    required bool cameraActive,
    required bool audioActive,
    required bool screenActive,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
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
      notificationTitle: _buildTitle(
        childName: childName,
        parentName: parentName,
      ),
      notificationText: _buildBody(
        cameraActive: cameraActive,
        audioActive: audioActive,
        screenActive: screenActive,
      ),
      callback: _startCallback,
    );
  }

  // ── Update the notification text ──────────────────────────────────────────────
  Future<void> updateNotification({
    required String childName,
    required String parentName,
    required bool cameraActive,
    required bool audioActive,
    required bool screenActive,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: _buildTitle(
        childName: childName,
        parentName: parentName,
      ),
      notificationText: _buildBody(
        cameraActive: cameraActive,
        audioActive: audioActive,
        screenActive: screenActive,
      ),
    );
  }

  // ── Stop the foreground service ───────────────────────────────────────────────
  Future<void> stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  // ── Check if service is running ───────────────────────────────────────────────
  Future<bool> get isRunning async =>
      FlutterForegroundTask.isRunningService;
}

// ── Top-level task handler (required by flutter_foreground_task) ────────────────
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onButtonPressed(String id) {
    if (id == 'stop_monitoring') {
      // Signal the main isolate to stop monitoring
      //FlutterForegroundTask.sendPort?.send({'action': 'stop_monitoring'});
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/child/home');
  }
}
