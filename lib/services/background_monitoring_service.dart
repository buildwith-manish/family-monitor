import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import 'device_event_service.dart';
import 'silent_webrtc_service.dart';

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
          debugPrint('[BackgroundService] Restoring monitoring after crash...');
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

  // Inform the parent dashboard that monitoring has started successfully.
  DeviceEventService.writeEvent(
    childUid: uid,
    type: 'service_started',
    message: 'Background monitoring service started successfully.',
    severity: 'info',
  );

  // ── Stop command listener ──────────────────────────────
  // Registered before session setup so the service is always stoppable.
  service.on('stop').listen((_) async {
    _cancelSessionResources();
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
    DeviceEventService.writeEvent(
      childUid: uid,
      type: 'service_crash',
      message: 'Monitoring setup failed after recovery attempt. Service stopped.',
      severity: 'error',
    );
    service.stopSelf();
  }
}

// ─────────────────────────────────────────────────────────────
// Isolate-level session state.
// These are file-level globals so they survive across calls to
// _setupMonitoringSession and can be reliably cancelled before
// each new session is established.  Without this, every call to
// _setupMonitoringSession (e.g. from the health-check watchdog)
// would accumulate duplicate Timer.periodic instances and
// Firebase listeners — causing exponential resource growth.
// ─────────────────────────────────────────────────────────────

StreamSubscription? _connectedSub;
StreamSubscription? _callsSub;
Timer? _heartbeatTimer;
Timer? _pingTimer;
Timer? _watchdogTimer;
Timer? _screenTimeTimer;

/// Cancel all session resources created by [_setupMonitoringSession].
/// Safe to call multiple times; idempotent.
void _cancelSessionResources() {
  _connectedSub?.cancel();    _connectedSub    = null;
  _callsSub?.cancel();        _callsSub        = null;
  _heartbeatTimer?.cancel();  _heartbeatTimer  = null;
  _pingTimer?.cancel();       _pingTimer       = null;
  _watchdogTimer?.cancel();   _watchdogTimer   = null;
  _screenTimeTimer?.cancel(); _screenTimeTimer = null;
}

/// Sets up all Firebase listeners and periodic timers for a monitoring session.
/// Cancels any previously running resources first to prevent proliferation.
Future<void> _setupMonitoringSession(
  ServiceInstance service,
  String uid,
) async {
  // Cancel any previously running session resources before creating new ones.
  // This prevents timer/listener accumulation when the watchdog restarts the session.
  _cancelSessionResources();

  // Restore online presence after potential process death
  await FirebaseDatabase.instance.ref('users/$uid/isOnline').set(true);
  await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);

  // Mark online / offline via .info/connected
  _connectedSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) async {
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
    if (callSnap.value != null && callSnap.value is Map) {
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
  _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      await FirebaseDatabase.instance
          .ref('users/$uid/lastSeen')
          .set(ServerValue.timestamp);
    } catch (_) {}
  });

  // Watch for call state changes
  _callsSub = FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
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

  // ── Screen-time enforcement — checked every 60 s ──────────
  // Reads limits from screen_time_limits/$uid and current usage from
  // UsageStatsManager. If any app has exceeded its daily limit, writes a
  // block command to app_locks/$uid/$packageName so the AppLockService on the
  // foreground layer can intercept it. Removes the lock at midnight (daily reset).
  _screenTimeTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
    try {
      final limitsSnap =
          await FirebaseDatabase.instance.ref('screen_time_limits/$uid').get();
      if (limitsSnap.value == null || limitsSnap.value is! Map) return;

      final limits = Map<String, dynamic>.from(limitsSnap.value as Map);
      if (limits.isEmpty) return;

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final stats = await UsageStats.queryUsageStats(midnight, now);

      for (final entry in limits.entries) {
        final pkg = entry.key;
        final limitMinutes = (entry.value as num?)?.toInt() ?? 0;
        if (limitMinutes <= 0) continue;

        final stat = stats.firstWhere(
          (s) => s.packageName == pkg,
          orElse: () => UsageInfo(),
        );
        final usedMs =
            int.tryParse(stat.totalTimeInForeground ?? '0') ?? 0;
        final usedMinutes = usedMs ~/ 60000;

        final blockRef =
            FirebaseDatabase.instance.ref('app_locks/$uid/$pkg');

        if (usedMinutes >= limitMinutes) {
          // Lock the app — AppLockService on the foreground layer intercepts opens.
          await blockRef.set({
            'blocked': true,
            'reason': 'screen_time_limit',
            'limitMinutes': limitMinutes,
            'usedMinutes': usedMinutes,
            'lockedAt': DateTime.now().millisecondsSinceEpoch,
          });
          debugPrint(
              '[BgService] Screen time limit hit for $pkg: ${usedMinutes}m >= ${limitMinutes}m');
        } else {
          // Check if previously auto-locked by screen time and unlock if today's
          // usage is now under limit (handles cases where the clock rolled over).
          final lockSnap = await blockRef.get();
          if (lockSnap.value is Map) {
            final lockData = Map<String, dynamic>.from(lockSnap.value as Map);
            if (lockData['reason'] == 'screen_time_limit') {
              await blockRef.remove();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BgService] Screen time check error: $e');
    }
  });

  // Ping Flutter layer every 20 s
  _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => service.invoke('ping', {}));

  // ── Health-check watchdog ──────────────────────────────
  // Non-recursive: cancels all current resources before restarting.
  // This prevents infinite timer accumulation from self-calls.
  int healthFailures = 0;

  _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
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
          debugPrint('[BgService] Restarting session after repeated failures');
          // Cancel all current resources (including this watchdog timer).
          // _setupMonitoringSession will create fresh ones — no recursion risk
          // because _watchdogTimer is null after _cancelSessionResources().
          _cancelSessionResources();
          DeviceEventService.writeEvent(
            childUid: uid,
            type: 'service_restored',
            message: 'Monitoring session restarted by health watchdog after repeated connectivity failures.',
            severity: 'warning',
          );
          await Future.delayed(const Duration(seconds: 2));
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
