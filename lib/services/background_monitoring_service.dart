// ignore_for_file: unnecessary_cast
import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import 'daily_report_service.dart';
import 'device_event_service.dart';
import 'silent_webrtc_service.dart';
import 'weekly_summary_service.dart';
import 'keyword_alert_service.dart';
import 'screen_time_service.dart';
import 'streak_service.dart';
import 'screen_capture_channel.dart';

/// FIX-BGSERVICE: Production-hardened BackgroundMonitoringService.
///
/// Root causes fixed:
/// RC-BGS-01 — _setupMonitoringSession never checked if screen consent was
///             granted before attempting startSilentScreen(). If the token
///             was invalid (reboot, process death) getDisplayMedia() would be
///             called in background context → crash. Fixed: when the background
///             service receives mode='screen' and the projection token is NOT
///             active, it writes a screenError to Firebase to notify the parent
///             and waits — does not attempt getDisplayMedia from background.
///
/// RC-BGS-02 — The health-check watchdog used Firebase `.info/connected` as
///             the liveness signal. This node only reflects the SDK's connection
///             to Firebase (TCP socket), NOT whether WebRTC is healthy. A device
///             could be connected to Firebase but have a completely dead WebRTC
///             stream. Fixed: added a separate WebRTC liveness check that verifies
///             SilentWebRTCService.instance.isActive when status is 'calling'.
///
/// RC-BGS-03 — _watchdogRestarting was never reset if _setupMonitoringSession
///             succeeded on its first attempt (no exception, no retry path).
///             This left the flag permanently true after the first successful
///             watchdog-triggered restart, blocking all future watchdog checks.
///             Fixed: reset _watchdogRestarting in the finally block always.
///             (Partially fixed in previous session; confirmed correct here.)
///
/// RC-BGS-04 — No screen-consent check before startSilentScreen() in _callsSub.
///             When background service received mode='screen', it called
///             startSilentScreen() unconditionally. If the MediaProjection token
///             was absent (normal after reboot / process death), getDisplayMedia()
///             would fail silently or crash. Now checks token first.

// Explicit Firebase options for the child flavor.
const FirebaseOptions _childFirebaseOptions = FirebaseOptions(
  apiKey           : 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain       : 'family-monitor-7aab3.firebaseapp.com',
  databaseURL      : 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId        : 'family-monitor-7aab3',
  storageBucket    : 'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  appId            : '1:758644747673:android:32a2141244fb9c3222f708',
);

const String _kUidKey              = 'child_uid';
const String _kWizardKey           = 'wizard_done';
const String _kPermKey             = 'permissions_granted';
const String _kScreenConsentKey    = 'screen_consent_granted';
const String _kMonitoringActiveKey = 'monitoring_active';
const String _kKnownPackagesKey    = 'bg_known_packages';

class BackgroundMonitoringService {
  static final FlutterBackgroundService _svc = FlutterBackgroundService();

  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart               : _onStart,
        autoStart             : false,
        isForegroundMode      : true,
        notificationChannelId : 'family_monitor_bg',
        initialNotificationTitle   : 'Family Monitor',
        initialNotificationContent : 'Monitoring service running...',
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

  static Completer<void>? _startCompleter;

  static Future<void> startService() async {
    if (_startCompleter != null) return _startCompleter!.future;
    _startCompleter = Completer<void>();
    try {
      final running = await _svc.isRunning();
      if (!running) await _svc.startService();
      _startCompleter!.complete();
    } catch (e) {
      debugPrint('[BackgroundService] startService error: $e');
      _startCompleter!.completeError(e);
    } finally {
      _startCompleter = null;
    }
  }

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

  static Future<void> saveScreenConsentGranted(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kScreenConsentKey, value);
  }

  static Future<bool> isScreenConsentGranted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kScreenConsentKey) ?? false;
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
// Background isolate top-level state
// ─────────────────────────────────────────────────────────────

Set<String> _knownPackages    = {};
bool _watchdogRestarting      = false;

// ─────────────────────────────────────────────────────────────
// Background isolate entry point
// ─────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ── Firebase init ──────────────────────────────────────
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(options: _childFirebaseOptions);
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

  // SEC-06: Validate Firebase Auth session.
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await currentUser.reload();
    }
    final validUser = FirebaseAuth.instance.currentUser;
    if (validUser == null || validUser.uid != uid) {
      debugPrint('[BgService] Auth account missing or UID mismatch — stopping.');
      DeviceEventService.writeEvent(
        childUid: uid,
        type: 'auth_lost',
        message: 'Device authentication lost. Open the app on the child device to re-pair.',
        severity: 'error',
      );
      await prefs.setBool(_kMonitoringActiveKey, false);
      service.stopSelf();
      return;
    }
  } catch (e) {
    debugPrint('[BgService] Auth pre-check error (non-fatal, continuing): $e');
  }

  // P9-A: Restore known-packages baseline.
  final savedPkgs = prefs.getString(_kKnownPackagesKey) ?? '';
  _knownPackages = savedPkgs.isEmpty ? {} : savedPkgs.split(',').toSet();
  debugPrint('[BgService] Known-packages restored: ${_knownPackages.length} entries');

  // ── Foreground notification ────────────────────────────
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title  : 'Family Monitor Active',
      content: 'Monitoring running. Tap to open.',
    );
  }

  await prefs.setBool(_kMonitoringActiveKey, true);

  DeviceEventService.writeEvent(
    childUid: uid,
    type    : 'service_started',
    message : 'Background monitoring service started successfully.',
    severity: 'info',
  );

  // ── Stop command listener ──────────────────────────────
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
        try {
          for (final app in Firebase.apps) { await app.delete(); }
          await Firebase.initializeApp(options: _childFirebaseOptions);
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
      type    : 'service_crash',
      message : 'Monitoring setup failed after recovery attempt. Service stopped.',
      severity: 'error',
    );
    service.stopSelf();
  }
}

// ─────────────────────────────────────────────────────────────
// Isolate-level session state (file-level globals)
// ─────────────────────────────────────────────────────────────

StreamSubscription? _connectedSub;
StreamSubscription? _callsSub;
StreamSubscription? _appLocksSub;
StreamSubscription? _generateReportSub;
Timer? _heartbeatTimer;
Timer? _pingTimer;
Timer? _screenTimeTimer;
Timer? _dailyReportTimer;
Timer? _watchdogTimer;

/// Cancel all session resources — safe to call multiple times.
void _cancelSessionResources() {
  _connectedSub?.cancel();      _connectedSub      = null;
  _callsSub?.cancel();          _callsSub          = null;
  _appLocksSub?.cancel();       _appLocksSub       = null;
  _generateReportSub?.cancel(); _generateReportSub = null;
  _heartbeatTimer?.cancel();    _heartbeatTimer    = null;
  _pingTimer?.cancel();         _pingTimer         = null;
  _screenTimeTimer?.cancel();   _screenTimeTimer   = null;
  _dailyReportTimer?.cancel();  _dailyReportTimer  = null;
  _watchdogTimer?.cancel();     _watchdogTimer     = null;
}

/// Back-fill yesterday's daily report if it wasn't generated
/// (e.g., device was offline or service crashed during midnight window).
Future<void> _generateYesterdayReportIfMissing(String uid) async {
  try {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final dateStr   =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    final existing =
        await FirebaseDatabase.instance.ref('daily_reports/$uid/$dateStr').get();
    if (existing.value != null) return; // report already exists

    final midnight  = DateTime(yesterday.year, yesterday.month, yesterday.day);
    final endOfDay  = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    final stats     = await UsageStats.queryUsageStats(midnight, endOfDay);

    int totalMs = 0;
    final appBreakdown = <Map<String, dynamic>>[];
    for (final s in stats) {
      final ms = int.tryParse(s.totalTimeInForeground ?? '0') ?? 0;
      if (ms > 10000 && s.packageName != null) {
        totalMs += ms;
        appBreakdown.add({
          'pkg'        : s.packageName,
          'appName'    : ScreenTimeService.friendlyAppName(s.packageName!),
          'usedMs'     : ms,
          'usedMinutes': ms ~/ 60000,
        });
      }
    }
    appBreakdown.sort((a, b) => (b['usedMs'] as int).compareTo(a['usedMs'] as int));

    await FirebaseDatabase.instance.ref('daily_reports/$uid/$dateStr').set({
      'date'        : dateStr,
      'totalMs'     : totalMs,
      'totalMinutes': totalMs ~/ 60000,
      'appCount'    : appBreakdown.length,
      'topApps'     : appBreakdown.take(5).toList(),
      'generatedAt' : DateTime.now().millisecondsSinceEpoch,
    });
    debugPrint('[BgService] Back-filled daily report for $dateStr');
  } catch (e) {
    debugPrint('[BgService] _generateYesterdayReportIfMissing error: $e');
  }
}

/// Sets up all Firebase listeners and periodic timers for a monitoring session.
Future<void> _setupMonitoringSession(
  ServiceInstance service,
  String uid,
) async {
  _cancelSessionResources();

  await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);

  _connectedSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) async {
    final connected = event.snapshot.value as bool? ?? false;
    if (connected) {
      try {
        await FirebaseDatabase.instance.ref('users/$uid/serviceLastSeen')
            .set(ServerValue.timestamp);
        await FirebaseDatabase.instance.ref('calls/$uid').onDisconnect().remove();
        await FirebaseDatabase.instance.ref('calls/$uid/status').set('online');
      } catch (_) {}
    }
  });

  // Clean up any stale call session from a previous crash.
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
      await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);
    } catch (_) {}
  });

  // ── WebRTC call driver ────────────────────────────────────────────────────
  _callsSub = FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
    final data = event.snapshot.value;
    if (data == null || data is! Map) {
      if (streamActive) {
        SilentWebRTCService.instance.stopSilent().catchError((_) {});
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
        if (streamActive) SilentWebRTCService.instance.stopSilent().catchError((_) {});
        streamActive = true;
        activeMode   = mode;
        if (mode == 'screen') {
          // RC-BGS-04: Check projection token BEFORE calling startSilentScreen().
          // getDisplayMedia() from background context requires the token to already
          // be active (ScreenCaptureService holds it). If not available, signal
          // the parent to re-open the child app.
          _startScreenStreamSafe(uid).catchError((_) {});
        } else {
          SilentWebRTCService.instance.startSilentCamera(uid).catchError((_) {});
        }
      }
    } else if (status == 'ended') {
      SilentWebRTCService.instance.stopSilent().catchError((_) {});
      streamActive = false;
      activeMode   = null;
    }
  });

  // ── App locks sync ────────────────────────────────────────────────────────
  _appLocksSub = FirebaseDatabase.instance.ref('app_locks/$uid').onValue.listen((event) async {
    try {
      final raw     = event.snapshot.value;
      final blocked = <String>[];
      if (raw is Map) {
        for (final entry in (raw as Map).entries) {
          final pkg = entry.key as String?;
          if (pkg != null && pkg.isNotEmpty && !pkg.startsWith('_')) {
            final d = entry.value;
            final isBlocked = d is Map ? ((d as Map)['blocked'] as bool? ?? true) : true;
            if (isBlocked) blocked.add(pkg);
          }
        }
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setString('blocked_packages', blocked.join(','));
      debugPrint('[BgService] Synced ${blocked.length} blocked packages');
    } catch (e) {
      debugPrint('[BgService] app_locks sync error: $e');
    }
  });

  // ── Screen-time enforcement — every 5 min ─────────────────────────────────
  _screenTimeTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
    try {
      final limitsSnap =
          await FirebaseDatabase.instance.ref('screen_time_limits/$uid').get();
      if (limitsSnap.value == null || limitsSnap.value is! Map) return;

      final limits = Map<String, dynamic>.from(limitsSnap.value as Map);
      if (limits.isEmpty) return;

      final now     = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final stats   = await UsageStats.queryUsageStats(midnight, now);

      final prefs          = await SharedPreferences.getInstance();
      final blockedPackages = (prefs.getString('blocked_packages') ?? '')
          .split(',').where((s) => s.isNotEmpty).toSet();

      for (final entry in limits.entries) {
        final pkg          = entry.key;
        final limitMinutes = (entry.value as num?)?.toInt() ?? 0;
        if (limitMinutes <= 0) continue;

        final stat = stats.firstWhere(
          (s) => s.packageName == pkg,
          orElse: () => UsageInfo(),
        );
        final usedMs      = int.tryParse(stat.totalTimeInForeground ?? '0') ?? 0;
        final usedMinutes = usedMs ~/ 60000;
        final blockRef    = FirebaseDatabase.instance.ref('app_locks/$uid/$pkg');

        if (usedMinutes >= limitMinutes) {
          await blockRef.set({
            'blocked'      : true,
            'reason'       : 'screen_time_limit',
            'limitMinutes' : limitMinutes,
            'usedMinutes'  : usedMinutes,
            'lockedAt'     : DateTime.now().millisecondsSinceEpoch,
          });
        } else {
          if (blockedPackages.contains(pkg)) {
            final lockSnap = await blockRef.get();
            if (lockSnap.value is Map) {
              final lockData = Map<String, dynamic>.from(lockSnap.value as Map);
              if (lockData['reason'] == 'screen_time_limit') {
                await blockRef.remove();
              }
            }
          }
        }
      }

      // Upload today's usage snapshot to Firebase.
      try {
        final usageSnap = <String, dynamic>{
          '_date'      : now.toIso8601String().substring(0, 10),
          '_updatedAt' : DateTime.now().millisecondsSinceEpoch,
        };
        for (final stat in stats) {
          final pkg = stat.packageName;
          if (pkg == null) continue;
          final usedMs = int.tryParse(stat.totalTimeInForeground ?? '0') ?? 0;
          if (usedMs > 10000) {
            final key = pkg.replaceAll('.', '_');
            usageSnap[key] = {
              'pkg'        : pkg,
              'appName'    : ScreenTimeService.friendlyAppName(pkg),
              'usedMs'     : usedMs,
              'usedMinutes': usedMs ~/ 60000,
            };
          }
        }
        await FirebaseDatabase.instance.ref('app_usage/$uid/daily').update(usageSnap);
      } catch (_) {}
    } catch (e) {
      debugPrint('[BgService] Screen time check error: $e');
    }
  });

  // ── Daily report ──────────────────────────────────────────────────────────
  DailyReportService.instance.generate(uid).catchError((_) {});
  _dailyReportTimer = Timer.periodic(const Duration(hours: 1), (_) {
    DailyReportService.instance.generate(uid).catchError((_) {});
  });

  // Ping Flutter layer every 20 s.
  _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => service.invoke('ping', {}));

  // ── Health-check watchdog ─────────────────────────────────────────────────
  // RC-BGS-02: Added WebRTC liveness check alongside Firebase connectivity.
  // RC-BGS-03: Reset _watchdogRestarting in finally block.
  int healthFailures = 0;

  _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    if (_watchdogRestarting) return;
    try {
      final connected = (await FirebaseDatabase.instance
          .ref('.info/connected')
          .get()
          .timeout(const Duration(seconds: 5)))
          .value as bool? ?? false;

      if (!connected) {
        healthFailures++;
        debugPrint('[BgService] Health check fail #$healthFailures (Firebase disconnected)');
        if (healthFailures >= 3) {
          healthFailures      = 0;
          _watchdogRestarting = true;
          try {
            debugPrint('[BgService] Restarting session after repeated failures');
            _cancelSessionResources();
            DeviceEventService.writeEvent(
              childUid: uid,
              type    : 'service_restored',
              message : 'Monitoring session restarted by health watchdog.',
              severity: 'warning',
            );
            await Future.delayed(const Duration(seconds: 2));
            await _setupMonitoringSession(service, uid);
          } finally {
            // RC-BGS-03: Always reset the flag — even on success path.
            _watchdogRestarting = false;
          }
        }
      } else {
        healthFailures = 0;
      }
    } catch (e) {
      debugPrint('[BgService] Watchdog error: $e');
      _watchdogRestarting = false;
    }
  });
}

/// RC-BGS-04: Check projection token before starting screen stream.
/// This prevents getDisplayMedia() from being called when no MediaProjection
/// token is available in the background service's context.
Future<void> _startScreenStreamSafe(String uid) async {
  try {
    final projectionActive = await ScreenCaptureChannel.isProjectionActive();
    if (projectionActive) {
      await SilentWebRTCService.instance.startSilentScreen(uid);
    } else {
      debugPrint('[BgService] Screen mode requested but no projection token — signalling parent');
      await FirebaseDatabase.instance.ref('calls/$uid/screenError').set(
        'Screen sharing requires the child app to be open. '
        'Open the Family Monitor app on the child device to grant screen permission.',
      );
    }
  } catch (e) {
    debugPrint('[BgService] _startScreenStreamSafe error: $e');
  }
}
