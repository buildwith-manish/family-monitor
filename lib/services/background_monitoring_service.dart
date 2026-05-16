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
import 'weekly_summary_service.dart';
import 'keyword_alert_service.dart';
import 'screen_time_service.dart';
import 'streak_service.dart';
import 'screen_capture_channel.dart';

/// FIX-BGSERVICE: Production-hardened BackgroundMonitoringService.
///
/// Root causes fixed:
/// RC-BGS-01 — _setupMonitoringSession never checked if screen consent was
///             granted before attempting to start the screen stream. If the
///             MediaProjection token was invalid (reboot, process death) the
///             stream would fail. Fixed: when the background service receives
///             mode='screen' and the projection token is NOT active, it writes
///             a screenError to Firebase to notify the parent and waits — does
///             not attempt to start streaming from background without a token.
///
/// RC-BGS-02 — The health-check watchdog used Firebase `.info/connected` as
///             the liveness signal. This node only reflects the SDK's connection
///             to Firebase (TCP socket), NOT whether the screen stream is
///             healthy. A device could be connected to Firebase but have a
///             completely dead screen stream. Fixed: added a separate stream
///             liveness check that verifies ScreenCaptureChannel.isScreenStreamRunning()
///             when status is 'calling'.
///
/// RC-BGS-03 — _watchdogRestarting was never reset if _setupMonitoringSession
///             succeeded on its first attempt (no exception, no retry path).
///             This left the flag permanently true after the first successful
///             watchdog-triggered restart, blocking all future watchdog checks.
///             Fixed: reset _watchdogRestarting in the finally block always.
///             (Partially fixed in previous session; confirmed correct here.)
///
/// RC-BGS-04 — No screen-consent check before starting screen stream in _callsSub.
///             When background service received mode='screen', it started
///             streaming unconditionally. If the MediaProjection token was
///             absent (normal after reboot / process death), the stream would
///             fail silently or crash. Now checks token first.

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
// BUG-3-FIX: Keys for service health tracking and watchdog restart signalling.
const String _kBgServiceHealthyKey  = 'bg_service_last_healthy';
const String _kWatchdogRestartKey   = 'watchdog_triggered_restart';

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
  } else {
    // BUG-3-FIX: After successful setup, check if this was a watchdog-triggered
    // restart and try to reconnect to any active monitoring sessions.
    try {
      final wasWatchdogRestart = prefs.getBool(_kWatchdogRestartKey) ?? false;
      if (wasWatchdogRestart) {
        await prefs.setBool(_kWatchdogRestartKey, false);
        debugPrint('[BgService] Watchdog-triggered restart — reconnecting active sessions');
        _checkAndReconnectActiveSession(uid).catchError((e) {
          debugPrint('[BgService] Active session reconnect error: $e');
        });
      }
    } catch (e) {
      debugPrint('[BgService] Watchdog restart check error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Isolate-level session state (file-level globals)
// ─────────────────────────────────────────────────────────────

StreamSubscription? _connectedSub;
StreamSubscription? _callsSub;
StreamSubscription? _appLocksSub;
StreamSubscription? _generateReportSub;
// BUG-2-FIX: Subscription for projectionReady signal from child app.
StreamSubscription? _projectionReadySub;
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
  _projectionReadySub?.cancel(); _projectionReadySub = null;
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

/// Helper: resolve the stream relay URL from SharedPreferences or Firebase.
///
/// Looks up the relay URL needed for WebSocket screen streaming. First checks
/// SharedPreferences for a cached value, then falls back to Firebase
/// `users/$uid/streamRelayUrl`. If found via Firebase, caches it to
/// SharedPreferences for future use.
Future<String?> _resolveRelayUrl(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var relayUrl = prefs.getString('stream_relay_url');
    if (relayUrl != null && relayUrl.isNotEmpty) return relayUrl;

    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/$uid/streamRelayUrl')
          .get()
          .timeout(const Duration(seconds: 5));
      if (snap.value is String && (snap.value as String).isNotEmpty) {
        relayUrl = snap.value as String;
        await prefs.setString('stream_relay_url', relayUrl);
        return relayUrl;
      }
    } catch (_) {}
  } catch (_) {}
  return null;
}

/// Helper: start WebSocket screen streaming via ScreenCaptureChannel.
///
/// Resolves the relay URL and starts the screen stream. If successful, sets
/// the `wsStreamMode` and `nativeCaptureMode` flags in Firebase so the parent
/// app knows the stream is using WebSocket mode.
///
/// Returns true if the stream was started successfully.
Future<bool> _startWebSocketScreenStream(String uid) async {
  try {
    final relayUrl = await _resolveRelayUrl(uid);
    if (relayUrl == null || relayUrl.isEmpty) {
      debugPrint('[BgService] No relay URL available — cannot start WebSocket screen stream');
      return false;
    }

    final started = await ScreenCaptureChannel.startScreenStream(
      uid: uid,
      serverUrl: relayUrl,
    );
    if (started) {
      await FirebaseDatabase.instance.ref('calls/$uid/wsStreamMode').set(true);
      await FirebaseDatabase.instance.ref('calls/$uid/nativeCaptureMode').set(true);
      debugPrint('[BgService] WebSocket screen stream started successfully');
      return true;
    }
  } catch (e) {
    debugPrint('[BgService] _startWebSocketScreenStream error: $e');
  }
  return false;
}

/// Helper: stop all screen streaming.
///
/// Stops both the WebSocket screen stream and native screen capture, ignoring
/// any errors.
Future<void> _stopAllScreenStreams() async {
  try { await ScreenCaptureChannel.stopScreenStream(); } catch (_) {}
  try { await ScreenCaptureChannel.stopNativeScreenCapture(); } catch (_) {}
}

/// Helper: signal that camera streaming mode is not available.
///
/// Called when a non-screen monitoring mode is requested. Writes a Firebase
/// status indicating camera streaming is not supported — only screen monitoring
/// is available via WebSocket streaming.
Future<void> _signalCameraModeUnavailable(String uid) async {
  debugPrint('[BgService] Camera streaming mode not supported without WebRTC');
  try {
    await FirebaseDatabase.instance.ref('calls/$uid/screenError').set(
      'Camera streaming is not available. Screen monitoring only.',
    );
  } catch (_) {}
}

/// Sets up all Firebase listeners and periodic timers for a monitoring session.
Future<void> _setupMonitoringSession(
  ServiceInstance service,
  String uid,
) async {
  _cancelSessionResources();

  await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);

  // BUG-2/BUG-3 FIX: Clean up stale consent/signaling flags from previous
  // sessions. These flags can persist if the previous session was terminated
  // abnormally (process kill, app crash), causing the new session to
  // incorrectly wait for signals that will never come.
  try {
    await FirebaseDatabase.instance.ref('calls/$uid/needsConsent').remove();
    await FirebaseDatabase.instance.ref('calls/$uid/projectionReady').remove();
    await FirebaseDatabase.instance.ref('calls/$uid/screenError').remove();
    await FirebaseDatabase.instance.ref('calls/$uid/wsStreamMode').remove();
  } catch (_) {}

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

  // BUG-3-FIX: Clean up stale call sessions, but preserve active screen sessions.
  // Screen sessions that are briefly interrupted (e.g., by service restart) should
  // be reconnected rather than killed — the parent may still be watching.
  try {
    final callSnap = await FirebaseDatabase.instance.ref('calls/$uid').get();
    if (callSnap.value != null && callSnap.value is Map) {
      final data      = Map<String, dynamic>.from(callSnap.value as Map);
      final status    = data['status']    as String?;
      final mode      = data['mode']      as String?;
      final startedAt = data['startedAt'] as int?;
      if (status == 'calling' && startedAt != null) {
        final age = DateTime.now().millisecondsSinceEpoch - startedAt;
        if (age > 5 * 60 * 1000) {
          if (mode == 'screen') {
            // BUG-3-FIX: Don't remove active screen sessions — try to reconnect
            // instead. An active screen session that was briefly interrupted (e.g.,
            // service restart) should be preserved and reconnected, not killed.
            debugPrint('[BgService] Active screen session detected (age=${age ~/ 1000}s) — attempting reconnect instead of cleanup');
            _tryReconnectActiveScreenSession(uid).catchError((e) {
              debugPrint('[BgService] Screen session reconnect failed: $e');
            });
          } else {
            await FirebaseDatabase.instance.ref('calls/$uid').remove();
            debugPrint('[BgService] Cleaned stale call session (mode=$mode)');
          }
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
      // BUG-3-FIX: Update health flag so WatchdogReceiver can verify service health.
      // The watchdog reads this timestamp; if stale > 2 min it treats the service
      // as unhealthy and triggers a restart.
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kBgServiceHealthyKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  });

  // ── Screen stream call driver ─────────────────────────────────────────────
  _callsSub = FirebaseDatabase.instance.ref('calls/$uid').onValue.listen((event) {
    final data = event.snapshot.value;
    if (data == null || data is! Map) {
      if (streamActive) {
        _stopAllScreenStreams().catchError((_) {});
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
        if (streamActive) _stopAllScreenStreams().catchError((_) {});
        streamActive = true;
        activeMode   = mode;
        if (mode == 'screen') {
          // RC-BGS-04: Check projection token BEFORE starting screen stream.
          // Screen streaming from background context requires the MediaProjection
          // token to already be active (ScreenCaptureService holds it). If not
          // available, signal the parent to re-open the child app.
          _startScreenStreamSafe(uid).catchError((_) {});
        } else {
          _signalCameraModeUnavailable(uid).catchError((_) {});
        }
      }
    } else if (status == 'ended') {
      _stopAllScreenStreams().catchError((_) {});
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
  // RC-BGS-02: Added screen stream liveness check alongside Firebase connectivity.
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
            // BUG-3-FIX: After watchdog-triggered session restart, check for
            // active calls and reconnect the screen stream automatically.
            await _checkAndReconnectActiveSession(uid);
          } finally {
            // RC-BGS-03: Always reset the flag — even on success path.
            _watchdogRestarting = false;
          }
        }
      } else {
        healthFailures = 0;

        // BUG-3-FIX: Screen stream health check.
        // Firebase connectivity alone doesn't guarantee the screen stream is alive.
        // If the call status is 'calling' but the stream is inactive, trigger a reconnect.
        try {
          final callSnap = await FirebaseDatabase.instance.ref('calls/$uid').get();
          if (callSnap.value != null && callSnap.value is Map) {
            final callData   = Map<String, dynamic>.from(callSnap.value as Map);
            final callStatus = callData['status'] as String?;
            final callMode   = callData['mode']   as String?;
            final isStreamRunning = await ScreenCaptureChannel.isScreenStreamRunning();
            if (callStatus == 'calling' && !isStreamRunning) {
              debugPrint('[BgService] Screen stream dead but call active — triggering reconnect (mode=$callMode)');
              if (callMode == 'screen') {
                _startScreenStreamSafe(uid).catchError((_) {});
              } else {
                _signalCameraModeUnavailable(uid).catchError((_) {});
              }
            }
          }
        } catch (e) {
          debugPrint('[BgService] Stream health check error: $e');
        }
      }
    } catch (e) {
      debugPrint('[BgService] Watchdog error: $e');
      _watchdogRestarting = false;
    }
  });
}

/// RC-BGS-04: Check projection token before starting screen stream.
/// This prevents streaming from being attempted when no MediaProjection
/// token is available in the background service's context.
///
/// BUG-2-FIX (timing): Replaced the single 2-second wait with a proper
/// polling loop that waits up to 15 seconds for the projection token to
/// become available. Also listens for the `projectionReady` signal from
/// the child app's UI layer (which has Activity context to show the consent
/// dialog), so the background service can start the screen stream as soon
/// as the user grants consent — without needing to retry from scratch.
///
/// BUG-2-FIX (retry): Added a Firebase listener for `projectionReady` that
/// automatically triggers screen stream start when the child app signals
/// that consent has been granted. This eliminates the need for the parent
/// to manually retry.
Future<void> _startScreenStreamSafe(String uid) async {
  try {
    var projectionActive = await ScreenCaptureChannel.isProjectionActive();

    if (projectionActive) {
      await _startWebSocketScreenStream(uid);
      return;
    }

    // ── BUG-2-FIX: Signal the child app that screen consent is needed ──
    // Write a flag to Firebase so the child app's UI layer can detect it
    // and show the consent dialog (it has Activity context; we don't).
    await FirebaseDatabase.instance.ref('calls/$uid/needsConsent').set(true);

    // ── BUG-2-FIX: Try silent restart with polling ──
    // If consent was previously granted, try to silently restart the
    // ScreenCaptureService. Poll for the token for up to 15 seconds.
    final consentGranted = await BackgroundMonitoringService.isScreenConsentGranted();

    if (consentGranted) {
      debugPrint('[BgService] Projection inactive but consent granted — attempting silent restart');
      final started = await ScreenCaptureChannel.startSilentProjection();
      if (started) {
        // BUG-2-FIX: Poll for the token instead of waiting a fixed 2 seconds.
        // The projection service may take several seconds to start, especially
        // if it needs to request consent via the UI.
        const pollInterval = Duration(milliseconds: 500);
        const maxWait = Duration(seconds: 15);
        final deadline = DateTime.now().add(maxWait);

        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(pollInterval);
          projectionActive = await ScreenCaptureChannel.isProjectionActive();
          if (projectionActive) {
            debugPrint('[BgService] Projection re-acquired after silent restart');
            await FirebaseDatabase.instance.ref('calls/$uid/needsConsent').remove();
            await _startWebSocketScreenStream(uid);
            return;
          }
        }
        debugPrint('[BgService] Projection not available after 15s polling — waiting for consent signal');
      }
    }

    // ── BUG-2-FIX: Listen for projectionReady signal from child app ──
    // The child app's UI layer will write projectionReady=true when the
    // user grants consent. We listen for this and automatically start the
    // screen stream when it arrives.
    _projectionReadySub?.cancel();
    _projectionReadySub = FirebaseDatabase.instance
        .ref('calls/$uid/projectionReady')
        .onValue
        .listen((event) async {
      final ready = event.snapshot.value == true;
      if (!ready) return;

      debugPrint('[BgService] projectionReady signal received from child app');

      // Small delay to allow ScreenCaptureService to fully initialize
      await Future.delayed(const Duration(milliseconds: 500));

      final nowActive = await ScreenCaptureChannel.isProjectionActive();
      if (nowActive) {
        debugPrint('[BgService] Projection confirmed active — starting screen stream');
        await FirebaseDatabase.instance.ref('calls/$uid/projectionReady').remove();
        await FirebaseDatabase.instance.ref('calls/$uid/needsConsent').remove();
        await _startWebSocketScreenStream(uid);
      } else {
        debugPrint('[BgService] projectionReady signal but token not yet active — polling');
        // Poll for a few more seconds
        const pollInterval = Duration(milliseconds: 500);
        const maxWait = Duration(seconds: 10);
        final deadline = DateTime.now().add(maxWait);

        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(pollInterval);
          final active = await ScreenCaptureChannel.isProjectionActive();
          if (active) {
            debugPrint('[BgService] Projection confirmed active after polling — starting screen stream');
            await FirebaseDatabase.instance.ref('calls/$uid/projectionReady').remove();
            await FirebaseDatabase.instance.ref('calls/$uid/needsConsent').remove();
            await _startWebSocketScreenStream(uid);
            return;
          }
        }
        // Still not active after polling — signal parent
        debugPrint('[BgService] Projection still not active after projectionReady signal');
      }
    });

    // Signal parent that consent is needed
    debugPrint('[BgService] Screen mode requested but no projection token — signalling parent');
    await FirebaseDatabase.instance.ref('calls/$uid/screenError').set(
      'Screen sharing requires the child app to be open. '
      'Open the Family Monitor app on the child device to grant screen permission.',
    );
  } catch (e) {
    debugPrint('[BgService] _startScreenStreamSafe error: $e');
  }
}

/// BUG-3-FIX: Try to reconnect an active screen session after service restart.
///
/// Called when the stale-call cleanup detects a screen session with
/// status='calling' that is older than 5 minutes. Instead of removing it
/// (which would kill the parent's live view), we attempt to re-establish the
/// screen stream. If the MediaProjection token is still valid, the stream
/// restarts immediately. If not, we try a silent restart of the projection
/// service. If that also fails, we signal the parent that re-consent is needed.
Future<void> _tryReconnectActiveScreenSession(String uid) async {
  try {
    final projectionActive = await ScreenCaptureChannel.isProjectionActive();

    if (projectionActive) {
      debugPrint('[BgService] Projection still active — restarting screen stream');
      await _startWebSocketScreenStream(uid);
      return;
    }

    // Projection token is gone — try a silent restart if consent was previously granted.
    final consentGranted = await BackgroundMonitoringService.isScreenConsentGranted();
    if (consentGranted) {
      debugPrint('[BgService] Projection inactive but consent granted — attempting silent restart for reconnect');
      final started = await ScreenCaptureChannel.startSilentProjection();
      if (started) {
        const pollInterval = Duration(milliseconds: 500);
        const maxWait      = Duration(seconds: 15);
        final deadline     = DateTime.now().add(maxWait);

        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(pollInterval);
          final nowActive = await ScreenCaptureChannel.isProjectionActive();
          if (nowActive) {
            debugPrint('[BgService] Projection re-acquired for reconnect — starting screen stream');
            await _startWebSocketScreenStream(uid);
            return;
          }
        }
      }
    }

    // Could not reconnect — signal the parent so they can prompt the child to
    // re-open the app (which re-grants projection consent).
    debugPrint('[BgService] Could not reconnect screen session — signalling parent');
    await FirebaseDatabase.instance.ref('calls/$uid/screenError').set(
      'Screen session interrupted. Open the child app to restore screen monitoring.',
    );
  } catch (e) {
    debugPrint('[BgService] _tryReconnectActiveScreenSession error: $e');
  }
}

/// BUG-3-FIX: Check Firebase for any active monitoring sessions and reconnect.
///
/// Called after a watchdog-triggered restart (or boot) to ensure the screen
/// stream is re-established for any ongoing call. This is a belt-and-suspenders
/// check — the `_callsSub` listener inside `_setupMonitoringSession` should
/// also handle this when it fires with the current snapshot, but this explicit
/// check covers the case where the listener hasn't fired yet or was cancelled
/// during the restart.
Future<void> _checkAndReconnectActiveSession(String uid) async {
  try {
    final callSnap = await FirebaseDatabase.instance.ref('calls/$uid').get();
    if (callSnap.value == null || callSnap.value is! Map) {
      debugPrint('[BgService] No active call found — nothing to reconnect');
      return;
    }

    final data   = Map<String, dynamic>.from(callSnap.value as Map);
    final status = data['status'] as String?;
    final mode   = data['mode']   as String?;

    if (status != 'calling') {
      debugPrint('[BgService] Call exists but status=$status — no reconnect needed');
      return;
    }

    debugPrint('[BgService] Active call found (mode=$mode) — reconnecting stream');

    // STREAM-RELAY-URL: Also check for WebSocket stream mode and restart it if needed.
    final wsStreamMode = data['wsStreamMode'] == true;
    if (wsStreamMode) {
      debugPrint('[BgService] WebSocket stream mode detected — attempting direct restart');
      try {
        final prefs = await SharedPreferences.getInstance();
        final relayUrl = prefs.getString('stream_relay_url');
        if (relayUrl != null && relayUrl.isNotEmpty) {
          final projectionActive = await ScreenCaptureChannel.isProjectionActive();
          if (projectionActive) {
            final started = await ScreenCaptureChannel.startScreenStream(
              uid: uid,
              serverUrl: relayUrl,
            );
            if (started) {
              debugPrint('[BgService] WebSocket stream restarted directly');
              await FirebaseDatabase.instance.ref('calls/$uid/wsStreamMode').set(true);
              await FirebaseDatabase.instance.ref('calls/$uid/nativeCaptureMode').set(true);
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('[BgService] WebSocket stream restart failed: $e');
      }
    }

    if (mode == 'screen') {
      await _startScreenStreamSafe(uid);
    } else {
      await _signalCameraModeUnavailable(uid);
    }
  } catch (e) {
    debugPrint('[BgService] _checkAndReconnectActiveSession error: $e');
  }
}
