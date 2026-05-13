import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kUidKey              = 'child_uid';
const String _kWizardKey           = 'wizard_done';
const String _kPermKey             = 'permissions_granted';
const String _kMonitoringActiveKey = 'monitoring_active';

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
          AndroidForegroundType.dataSync,
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

  /// Re-starts monitoring on app launch if the service was previously active
  /// but the process was killed (crash recovery).
  static Future<void> restoreIfNeeded() async {
    try {
      final wasActive    = await isMonitoringActive();
      final wizardDone   = await isWizardDone();
      final permsGranted = await arePermissionsGranted();
      if (wasActive && wizardDone && permsGranted) {
        final running = await _svc.isRunning();
        if (!running) {
          debugPrint('[BackgroundService] Restoring monitoring after crash…');
          await _svc.startService();
        }
      }
    } catch (e) {
      debugPrint('[BackgroundService] restoreIfNeeded error: $e');
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

  static Future<void> setMonitoringActive(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMonitoringActiveKey, value);
  }

  static Future<bool> isMonitoringActive() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kMonitoringActiveKey) ?? false;
  }
}

// ─────────────────────────────────────────────────────────────
// Background isolate entry point
// ─────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ── Firebase init ──────────────────────────────────────
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[BgService] Firebase init error: $e');
      service.stopSelf();
      return;
    }
  }

  // ── UID guard ──────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  final uid   = prefs.getString(_kUidKey);
  if (uid == null) {
    debugPrint('[BgService] No UID stored — stopping.');
    service.stopSelf();
    return;
  }

  // ── Foreground notification ────────────────────────────
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title:   'Family Monitor Active',
      content: 'Monitoring running. Tap to open.',
    );
  }

  // Persist that monitoring is intentionally active so we can detect an
  // unclean exit on next startup and automatically re-join the session.
  await prefs.setBool(_kMonitoringActiveKey, true);

  // ── Stop command listener ──────────────────────────────
  // Registered before session setup so the service is always stoppable.
  service.on('stop').listen((_) async {
    await prefs.setBool(_kMonitoringActiveKey, false);
    service.stopSelf();
  });

  // ── Session setup with single-retry crash recovery ─────
  bool setupOk = false;
  for (int attempt = 0; attempt < 2; attempt++) {
    try {
      await _setupMonitoringSession(service, uid);
      setupOk = true;
      break;
    } catch (e, st) {
      debugPrint('[BgService] _setupMonitoringSession attempt ${attempt + 1} failed: $e');
      debugPrintStack(stackTrace: st);

      if (attempt == 0) {
        // Single recovery attempt: tear down and re-initialise Firebase.
        try {
          for (final app in Firebase.apps) {
            await app.delete();
          }
          await Firebase.initializeApp();
          debugPrint('[BgService] Firebase re-initialised for retry');
        } catch (reinitErr) {
          debugPrint('[BgService] Firebase re-init also failed: $reinitErr');
          break;
        }
      }
    }
  }

  if (!setupOk) {
    debugPrint('[BgService] Monitoring setup failed after recovery — stopping.');
    await prefs.setBool(_kMonitoringActiveKey, false);
    service.stopSelf();
  }
}

/// Sets up all Firebase listeners and periodic timers for a monitoring session.
/// Extracted so it can be retried independently of the [_onStart] scaffolding.
Future<void> _setupMonitoringSession(
  ServiceInstance service,
  String uid,
) async {
  // Restore online presence after potential process death
  await FirebaseDatabase.instance.ref('users/$uid/isOnline').set(true);
  await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);

  // Mark online / offline via .info/connected
  FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) async {
    final connected = event.snapshot.value as bool? ?? false;
    if (connected) {
      try {
        final statusRef = FirebaseDatabase.instance.ref('calls/$uid/status');
        await statusRef.onDisconnect().set('offline');
        await statusRef.set('online');
      } catch (_) {}
    }
  });

  // Clean up any stale call session left from a previous crash
  try {
    final callSnap = await FirebaseDatabase.instance.ref('calls/$uid').get();
    if (callSnap.value != null) {
      final data      = Map<String, dynamic>.from(callSnap.value as Map);
      final status    = data['status']    as String?;
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

  bool streamActive = false;
  String? activeMode;

  // Heartbeat — every 30 s
  Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      await FirebaseDatabase.instance
          .ref('users/$uid/lastSeen')
          .set(ServerValue.timestamp);
    } catch (_) {}
  });

  // Watch for call state changes
  FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
    final data = event.snapshot.value;
    if (data == null || data is! Map) {
      if (streamActive) {
        service.invoke('silent_stop');
        streamActive = false;
        activeMode   = null;
      }
      return;
    }

    final map    = Map<String, dynamic>.from(data);
    final status = map['status'] as String?;
    final mode   = map['mode']   as String? ?? 'camera';

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: status == 'calling'
            ? 'Family Monitor — Active Session'
            : 'Family Monitor Active',
        content: status == 'calling'
            ? 'Parent is viewing this device.'
            : 'Monitoring running.',
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

  // ── Health-check watchdog ──────────────────────────────
  int healthFailures = 0;

  Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      final connected = (await FirebaseDatabase.instance
          .ref('.info/connected')
          .get()
          .timeout(const Duration(seconds: 5)))
          .value as bool? ?? false;

      if (!connected) {
        healthFailures++;

        debugPrint('[BgService] Health check fail #$healthFailures');

        if (healthFailures >= 3) {
          healthFailures = 0;

          debugPrint(
            '[BgService] Restarting session after repeated failures',
          );

          await _setupMonitoringSession(service, uid);
        }
      } else {
        healthFailures = 0;
      }
    } catch (e) {
      debugPrint('[BgService] Watchdog error: $e');
    }
  });
}
