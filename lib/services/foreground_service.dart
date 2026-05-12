import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class MonitoringForegroundService {
  static final MonitoringForegroundService _instance =
      MonitoringForegroundService._internal();
  factory MonitoringForegroundService() => _instance;
  MonitoringForegroundService._internal();

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
        autoRunOnBoot: true,
        allowWifiLock: true,
      ),
    );
  }

  String _buildTitle({required String childName, required String parentName}) {
    return '$childName — Monitored by $parentName';
  }

  String _buildBody({
    required bool cameraActive,
    required bool audioActive,
    required bool screenActive,
  }) {
    final List<String> active = [];
    if (cameraActive) active.add('Camera');
    if (audioActive)  active.add('Audio');
    if (screenActive) active.add('Screen');
    if (active.isEmpty) return 'Monitoring paused — no streams active';
    return 'Sharing: ${active.join(', ')} • Tap to open app';
  }

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
      notificationTitle: _buildTitle(childName: childName, parentName: parentName),
      notificationText: _buildBody(
          cameraActive: cameraActive,
          audioActive: audioActive,
          screenActive: screenActive),
      callback: _startCallback,
    );
  }

  Future<void> updateNotification({
    required String childName,
    required String parentName,
    required bool cameraActive,
    required bool audioActive,
    required bool screenActive,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: _buildTitle(childName: childName, parentName: parentName),
      notificationText: _buildBody(
          cameraActive: cameraActive,
          audioActive: audioActive,
          screenActive: screenActive),
    );
  }

  Future<void> stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<bool> get isRunning async => FlutterForegroundTask.isRunningService;
}

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
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/child/home');
  }
}
