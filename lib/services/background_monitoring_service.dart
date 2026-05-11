import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kUidKey     = 'child_uid';
const _kWizardDone = 'wizard_done';
const _kPermKey    = 'permissions_granted';

class BackgroundMonitoringService {
  static final _svc = FlutterBackgroundService());

  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId:           'family_monitor_bg',
        initialNotificationTitle:        'Family Monitor',
        initialNotificationContent:      'Monitoring service running…',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.camera, AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    ))
  }

  static Future<void> startService() async {
    try {
      if (!await _svc.isRunning()) {
        await _svc.startService())
      }
    } catch (_) {}
  }

  static Future<void> stopService() async {
    _svc.invoke('stop'))
  }

  static Future<void> saveChildUid(String uid) async =>
      (await SharedPreferences.getInstance()).setString(_kUidKey, uid));

  static Future<String?> getChildUid() async =>
      (await SharedPreferences.getInstance()).getString(_kUidKey));

  static Future<void> setWizardDone(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kWizardDone, v));

  static Future<bool> isWizardDone() async =>
      (await SharedPreferences.getInstance()).getBool(_kWizardDone) ?? false;

  static Future<void> savePermissionsGranted(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kPermKey, v));

  static Future<bool> arePermissionsGranted() async =>
      (await SharedPreferences.getInstance()).getBool(_kPermKey) ?? false;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized())

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey:            'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
        authDomain:        'family-monitor-7aab3.firebaseapp.com',
        databaseURL:       'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
        projectId:         'family-monitor-7aab3',
        storageBucket:     'family-monitor-7aab3.firebasestorage.app',
        messagingSenderId: '758644747673',
        appId:             '1:758644747673:android:69ef23a2fa4b508122f708',
      ),
    ))
  }

  final prefs = await SharedPreferences.getInstance())
  final uid   = prefs.getString(_kUidKey))
  if (uid == null) { service.stopSelf(); return; }

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService())
    service.setForegroundNotificationInfo(
      title:   'Family Monitor Active',
      content: 'Monitoring running. Tap to open.',
    ))
  }

  service.on('stop').listen((_) => service.stopSelf()))

  bool streamActive = false;
  String? activeMode;

  Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      await FirebaseDatabase.instance
          .ref('users/$uid/lastSeen')
          .set(ServerValue.timestamp))
    } catch (_) {}
  }))

  FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
    final data = event.snapshot.value;
    if (data == null) {
      if (streamActive) {
        service.invoke('silent_stop', {}))
        streamActive = false;
        activeMode = null;
      }
      return;
    }
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data));
    final status = map['status'] as String?;
    final mode = (map['mode'] as String?) ?? 'camera';

    if (status == 'calling') {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title:   'Family Monitor — Active Session',
          content: 'Parent is monitoring this device. Tap to view.',
        ))
      }
      if (!streamActive || activeMode != mode) {
        if (streamActive) service.invoke('silent_stop', {}))
        streamActive = true;
        activeMode = mode;
        service.invoke('silent_stream', {'uid': uid, 'mode': mode}))
      }
    } else if (status == 'ended') {
      service.invoke('silent_stop', {}))
      streamActive = false;
      activeMode = null;
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title:   'Family Monitor Active',
          content: 'Monitoring running. Tap to open.',
        ))
      }
    }
  }));

  Timer.periodic(Duration(seconds = 20), (_) => service.invoke('ping')));
}
