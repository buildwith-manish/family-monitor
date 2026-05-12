import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kUidKey    = 'child_uid';
const String _kWizardKey = 'wizard_done';
const String _kPermKey   = 'permissions_granted';

// Paste your firebase options here — must match firebase_options.dart
const _firebaseOptions = FirebaseOptions(
  apiKey:            'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain:        'family-monitor-7aab3.firebaseapp.com',
  databaseURL:       'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId:         'family-monitor-7aab3',
  storageBucket:     'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  appId:             '1:758644747673:android:69ef23a2fa4b508122f708',
);

class BackgroundMonitoringService {
  static final FlutterBackgroundService _svc = FlutterBackgroundService();

  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'family_monitor_bg',
        initialNotificationTitle: 'Family Monitor',
        initialNotificationContent: 'Monitoring service running...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [
          AndroidForegroundType.camera,
          AndroidForegroundType.microphone,
        ],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> startService() async {
    try {
      final running = await _svc.isRunning();
      if (!running) await _svc.startService();
    } catch (e) {
      debugPrint('[BackgroundService] startService error: $e');
    }
  }

  static Future<void> stopService() async {
    try { _svc.invoke('stop'); } catch (_) {}
  }

  // ── SharedPreferences helpers ────────────────────────────

  static Future<void> saveChildUid(String uid) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUidKey, uid);
  }

  static Future<String?> getChildUid() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUidKey);
  }

  static Future<void> setWizardDone(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWizardKey, value);
  }

  static Future<bool> isWizardDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kWizardKey) ?? false;
  }

  static Future<void> savePermissionsGranted(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPermKey, value);
  }

  static Future<bool> arePermissionsGranted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kPermKey) ?? false;
  }
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Init Firebase if not already done
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(options: _firebaseOptions);
    } catch (e) {
      debugPrint('[BgService] Firebase init error: $e');
      service.stopSelf();
      return;
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final uid   = prefs.getString(_kUidKey);
  if (uid == null) { service.stopSelf(); return; }

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title:   'Family Monitor Active',
      content: 'Monitoring running. Tap to open.',
    );
  }

  // Restore online status after potential process death
  try {
    await FirebaseDatabase.instance.ref('users/$uid/isOnline').set(true);
    await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);
  } catch (_) {}

  // Clean up any stale call session from previous death
  try {
    final callSnap = await FirebaseDatabase.instance.ref('calls/$uid').get();
    if (callSnap.value != null) {
      final data = Map<String, dynamic>.from(callSnap.value as Map);
      final status = data['status'] as String?;
      final startedAt = data['startedAt'] as int?;
      if (status == 'calling' && startedAt != null) {
        final age = DateTime.now().millisecondsSinceEpoch - startedAt;
        if (age > 5 * 60 * 1000) {
          await FirebaseDatabase.instance.ref('calls/$uid').remove();
          debugPrint('[BgService] Cleaned stale call session');
        }
      }
    }
  } catch (_) {}

  // Handle stop command
  service.on('stop').listen((_) => service.stopSelf());

  bool streamActive = false;
  String? activeMode;

  // Heartbeat — every 30 s
  Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);
    } catch (_) {}
  });

  // Watch for call state changes
  FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
    final data = event.snapshot.value;
    if (data == null || data is! Map) {
      if (streamActive) { service.invoke('silent_stop'); streamActive = false; activeMode = null; }
      return;
    }
    final map    = Map<String, dynamic>.from(data);
    final status = map['status'] as String?;
    final mode   = map['mode'] as String? ?? 'camera';

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title:   status == 'calling' ? 'Family Monitor — Active Session' : 'Family Monitor Active',
        content: status == 'calling' ? 'Parent is viewing this device.' : 'Monitoring running.',
      );
    }

    if (status == 'calling') {
      if (!streamActive || activeMode != mode) {
        if (streamActive) service.invoke('silent_stop');
        streamActive = true;
        activeMode   = mode;
        service.invoke('silent_stream', {'uid': uid, 'mode': mode});
      }
    } else if (status == 'ended') {
      service.invoke('silent_stop');
      streamActive = false;
      activeMode   = null;
    }
  });

  // Ping Flutter layer every 20 s
  Timer.periodic(const Duration(seconds: 20), (_) => service.invoke('ping', {}));
}
