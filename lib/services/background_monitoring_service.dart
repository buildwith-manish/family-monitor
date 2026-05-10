import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kUidKey = 'child_uid';
const _kWizardDone = 'wizard_done';
const _kPermKey = 'permissions_granted';

class BackgroundMonitoringService {
  static final _svc = FlutterBackgroundService();

  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'family_monitor_bg',
        initialNotificationTitle: 'Family Monitor',
        initialNotificationContent: 'Monitoring service running',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> startService() async {
    if (!await _svc.isRunning()) await _svc.startService();
  }

  static Future<void> saveChildUid(String uid) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUidKey, uid);
  }

  static Future<void> setWizardDone(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWizardDone, v);
  }

  static Future<bool> isWizardDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kWizardDone) ?? false;
  }

  static Future<void> savePermissionsGranted(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPermKey, v);
  }
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final uid = prefs.getString(_kUidKey);
  if (uid == null) return;

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Family Monitor Active',
      content: 'Running in background. Tap to open.',
    );
  }

  service.on('stop').listen((_) => service.stopSelf());

  FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
    final data = event.snapshot.value;
    if (data == null) return;
    final map = Map<String, dynamic>.from(data as Map);
    final status = map['status'] as String?;
    if (status == 'calling') {
      service.invoke('bring_to_foreground', {'uid': uid, 'mode': map['mode'] ?? 'camera'});
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Family Monitor — Active',
          content: 'Parent is monitoring this device',
        );
      }
    } else if (status == 'ended') {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Family Monitor Active',
          content: 'Running in background. Tap to open.',
        );
      }
    }
  });

  Timer.periodic(const Duration(seconds: 20), (_) => service.invoke('ping'));
}
