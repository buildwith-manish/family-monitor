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

// Explicit Firebase options for the child flavor.
// Background and foreground-task isolates run in their own Dart isolate /
// Android thread and MUST initialise Firebase themselves.  Using explicit
// options here means the background service does not depend on the embedded
// google-services.json having a valid API key — preventing auth failures that
// originated from the Codemagic CI placeholder fallback.
const FirebaseOptions _childFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain: 'family-monitor-7aab3.firebaseapp.com',
  databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId: 'family-monitor-7aab3',
  storageBucket: 'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  appId: '1:758644747673:android:32a2141244fb9c3222f708',
);

const String _kUidKey              = 'child_uid';
const String _kWizardKey           = 'wizard_done';
const String _kPermKey             = 'permissions_granted';
const String _kScreenConsentKey    = 'screen_consent_granted';
const String _kMonitoringActiveKey = 'monitoring_active';
// P9-A: Persist the known-packages baseline so watchdog restarts do not
// re-fire install alerts for every app already present on the device.
const String _kKnownPackagesKey    = 'bg_known_packages';

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

  static Completer<void>? _startCompleter;

  static Future<void> startService() async {
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }
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

// P9-A: known-packages baseline — persisted across watchdog restarts so that
// every restart does NOT fire install alerts for every app already present.
Set<String> _knownPackages = {};

// P4-B: guard flag to prevent concurrent watchdog-triggered session restarts.
bool _watchdogRestarting = false;

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

  // P3-A: Do NOT call setPersistenceEnabled() here. Firebase RTDB persistence
  // is a process-level Android SDK setting. main_child.dart already calls it
  // before any DatabaseReference is created. The background isolate shares the
  // same Java-level FirebaseDatabase instance (same Android process) and
  // inherits the persistence setting automatically. Calling it again throws
  // DatabaseException (caught silently) and can destabilise the Dart plugin
  // layer's event channels in this isolate.

  // ── UID guard ──────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  final uid   = prefs.getString(_kUidKey);
  if (uid == null) {
    debugPrint('[BgService] No UID stored — stopping.');
    service.stopSelf();
    return;
  }

  // SEC-06: Validate the Firebase Auth session before starting monitoring.
  // Anonymous accounts can be deleted from the Firebase console or disabled
  // by an admin, leaving the device with a stored UID that no longer has
  // write access to any Firebase node. Detect this early and notify the parent.
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // reload() forces a server round-trip that detects deleted/disabled accounts.
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
    // Non-fatal: could be offline or a transient error. Continue and let
    // Firebase RTDB enforce permissions on any actual write attempt.
    debugPrint('[BgService] Auth pre-check error (non-fatal, continuing): $e');
  }

  // P9-A: Restore known-packages baseline persisted by the previous session.
  // Without this, every watchdog-triggered restart would see _knownPackages
  // as empty and fire an "installed" alert for every app on the device.
  final savedPkgs = prefs.getString(_kKnownPackagesKey) ?? '';
  _knownPackages = savedPkgs.isEmpty ? {} : savedPkgs.split(',').toSet();
  debugPrint('[BgService] Known-packages restored: ${_knownPackages.length} entries');

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
StreamSubscription? _appLocksSub;
StreamSubscription? _generateReportSub;
Timer? _heartbeatTimer;
Timer? _pingTimer;
Timer? _watchdogTimer;
Timer? _screenTimeTimer;
Timer? _dailyReportTimer;

/// Cancel all session resources created by [_setupMonitoringSession].
/// Safe to call multiple times; idempotent.
void _cancelSessionResources() {
  _connectedSub?.cancel();       _connectedSub       = null;
  _callsSub?.cancel();           _callsSub           = null;
  _appLocksSub?.cancel();        _appLocksSub        = null;
  _heartbeatTimer?.cancel();     _heartbeatTimer     = null;
  _pingTimer?.cancel();          _pingTimer          = null;
  _watchdogTimer?.cancel();      _watchdogTimer      = null;
  _screenTimeTimer?.cancel();    _screenTimeTimer    = null;
  _dailyReportTimer?.cancel();   _dailyReportTimer   = null;
  // FIX-01: Stop WebRTC in this isolate. stopSilent() sets _active=false
  // synchronously — the async teardown is fire-and-forget safe.
  SilentWebRTCService.instance.stopSilent().catchError((_) {});
}

/// Generates a daily report for yesterday if one doesn't already exist.
/// Called at service startup to handle the case where the nightly midnight
/// timer never fired because the service was killed before midnight.
Future<void> _generateYesterdayReportIfMissing(String uid) async {
  try {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final dateStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    final existing =
        await FirebaseDatabase.instance.ref('daily_reports/$uid/$dateStr').get();
    if (existing.value != null) return; // report already exists

    final midnight =
        DateTime(yesterday.year, yesterday.month, yesterday.day);
    final endOfDay = DateTime(
        yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);

    final stats = await UsageStats.queryUsageStats(midnight, endOfDay);
    int totalMs = 0;
    final appBreakdown = <Map<String, dynamic>>[];
    for (final s in stats) {
      final ms = int.tryParse(s.totalTimeInForeground ?? '0') ?? 0;
      if (ms > 10000 && s.packageName != null) {
        totalMs += ms;
        appBreakdown.add({
          'pkg':        s.packageName,
          'appName':    ScreenTimeService.friendlyAppName(s.packageName!),
          'usedMs':     ms,
          'usedMinutes': ms ~/ 60000,
        });
      }
    }
    appBreakdown
        .sort((a, b) => (b['usedMs'] as int).compareTo(a['usedMs'] as int));

    await FirebaseDatabase.instance.ref('daily_reports/$uid/$dateStr').set({
      'date': dateStr,
      'totalMs': totalMs,
      'totalMinutes': totalMs ~/ 60000,
      'appCount': appBreakdown.length,
      'topApps': appBreakdown.take(5).toList(),
      'generatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    debugPrint('[BgService] Back-filled daily report for $dateStr');
  } catch (e) {
    debugPrint('[BgService] _generateYesterdayReportIfMissing error: $e');
  }
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

  // HIGH-01: Do NOT write isOnline here. PresenceService (UI isolate) is the
  // sole authority for users/$uid/isOnline. Writing from two isolates causes
  // rapid online↔offline flips on the parent dashboard: when one connection
  // drops (e.g. background service restarts), its onDisconnect fires 'false',
  // then the UI isolate's connection immediately rewrites 'true' — visible as
  // a child flickering offline/online every network transition.
  // Only update lastSeen (benign, non-conflicting) and service-specific nodes.
  await FirebaseDatabase.instance.ref('users/$uid/lastSeen').set(ServerValue.timestamp);

  // FIX-03: Register onDisconnect for calls/$uid in the background isolate.
  // Firebase executes the onDisconnect handler server-side when the socket
  // closes (crash, battery pull, network loss), which prevents a stale
  // 'calling' session node with orphaned ICE candidates from persisting.
  //
  // FB-02: onDisconnect().remove() targets the ENTIRE calls/$uid node so
  // all fields (status, mode, offer, candidates, startedAt) are cleaned up
  // atomically. The previous onDisconnect().set('offline') on the status
  // sub-field left mode/offer/candidates in place — the parent dashboard
  // could read a stale 'calling' mode with no valid session to connect to.
  //
  // serviceLastSeen acts as a background-only heartbeat so the parent can
  // distinguish "app foregrounded" from "background service running".
  // isOnline is intentionally NOT written or registered here.
  _connectedSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) async {
    final connected = event.snapshot.value as bool? ?? false;
    if (connected) {
      try {
        await FirebaseDatabase.instance.ref('users/$uid/serviceLastSeen')
            .set(ServerValue.timestamp);
        // Register server-side cleanup of the entire calls/$uid node on disconnect.
        await FirebaseDatabase.instance.ref('calls/$uid').onDisconnect().remove();
        await FirebaseDatabase.instance.ref('calls/$uid/status').set('online');
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

  // FIX-01: Drive WebRTC directly in this background isolate.
  // DartPluginRegistrant.ensureInitialized() at the top of _onStart gives
  // this isolate full plugin access, so flutter_webrtc's getUserMedia works
  // here without needing to relay through the UI isolate via service.invoke.
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
          SilentWebRTCService.instance.startSilentScreen(uid).catchError((_) {});
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

  // FIX-02: Sync blocked packages to SharedPreferences so the native
  // AppBlockAccessibilityService can read them without hitting Firebase.
  // The key "blocked_packages" is stored with Flutter's "flutter." prefix
  // by SharedPreferences, readable in Kotlin as "flutter.blocked_packages".
  _appLocksSub = FirebaseDatabase.instance.ref('app_locks/$uid').onValue.listen((event) async {
    try {
      final raw = event.snapshot.value;
      final blocked = <String>[];
      if (raw is Map) {
        for (final entry in (raw as Map).entries) {
          final pkg = entry.key as String?;
          if (pkg != null && pkg.isNotEmpty && !pkg.startsWith('_')) {
            final data = entry.value;
            final isBlocked = data is Map
                ? ((data as Map)['blocked'] as bool? ?? true)
                : true;
            if (isBlocked) blocked.add(pkg);
          }
        }
      }
      // Use a fresh SharedPreferences instance — `prefs` is local to _onStart.
      final sp = await SharedPreferences.getInstance();
      await sp.setString('blocked_packages', blocked.join(','));
      debugPrint('[BgService] Synced ${blocked.length} blocked packages to SharedPreferences');
    } catch (e) {
      debugPrint('[BgService] app_locks sync error: $e');
    }
  });

  // ── Screen-time enforcement — checked every 5 min ─────────
  // Reads limits from screen_time_limits/$uid and current usage from
  // UsageStatsManager. If any app has exceeded its daily limit, writes a
  // block command to app_locks/$uid/$packageName so the AppLockService on the
  // foreground layer can intercept it. Removes the lock at midnight (daily reset).
  //
  // BAT-02: Interval changed from 60 s to 5 min. A 60 s polling rate caused
  // the background isolate to query UsageStatsManager and perform multiple
  // Firebase reads every minute. Screen-time enforcement with 5-minute
  // granularity is industry-standard (e.g. Screen Time on iOS) and keeps
  // battery impact negligible. For apps nearing their limit, the 5-minute
  // window still provides timely enforcement with at most ~5 min of over-run.
  _screenTimeTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
    try {
      final limitsSnap =
          await FirebaseDatabase.instance.ref('screen_time_limits/$uid').get();
      if (limitsSnap.value == null || limitsSnap.value is! Map) return;

      final limits = Map<String, dynamic>.from(limitsSnap.value as Map);
      if (limits.isEmpty) return;

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final stats = await UsageStats.queryUsageStats(midnight, now);

      // P6-A: Read the blocked_packages cache ONCE here rather than doing one
      // Firebase get() per under-limit app inside the loop. The cache is kept
      // fresh by _appLocksSub which writes to SharedPreferences within seconds
      // of any lock state change from Firebase.
      final prefs = await SharedPreferences.getInstance();
      final blockedPackages = (prefs.getString('blocked_packages') ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();

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
          // P6-A: Use the in-memory blocked_packages cache (maintained by
          // _appLocksSub) instead of a per-app Firebase get() call. This
          // eliminates N sequential reads per timer tick for under-limit apps
          // (e.g. 10 apps × read latency ~150 ms = 1.5 s blocked per cycle).
          // Only hit Firebase when the local cache confirms the app IS blocked,
          // reducing reads from N-per-tick to at-most-overLimit-per-tick.
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

      // FIX-14: Upload today's full usage snapshot to Firebase so the parent
      // dashboard can display per-app screen time without a separate sync request.
      try {
        final usageSnap = <String, dynamic>{
          '_date':      now.toIso8601String().substring(0, 10),
          '_updatedAt': DateTime.now().millisecondsSinceEpoch,
        };
        for (final stat in stats) {
          final pkg = stat.packageName;
          if (pkg == null) continue;
          final usedMs = int.tryParse(stat.totalTimeInForeground ?? '0') ?? 0;
          if (usedMs > 10000) {
            final key = pkg.replaceAll('.', '_');
            usageSnap[key] = {
              'pkg':         pkg,
              'appName':     ScreenTimeService.friendlyAppName(pkg),
              'usedMs':      usedMs,
              'usedMinutes': usedMs ~/ 60000,
            };
          }
        }
        // BUG-FIX: was set() which wiped the node on every 60-second tick.
        // update() merges into the existing snapshot so concurrent writers
        // (e.g. ScreenTimeService.uploadUsage) do not race to wipe each other.
        await FirebaseDatabase.instance.ref('app_usage/$uid/daily').update(usageSnap);
      } catch (_) {}
    } catch (e) {
      debugPrint('[BgService] Screen time check error: $e');
    }
  });

  // ── Daily report — generated once per calendar day ────────────────────
  // Run immediately on session start, then check every hour. The service
  // is idempotent within a day so repeated calls from session restarts
  // (watchdog, crash recovery) are safe and do not double-write.
  DailyReportService.instance.generate(uid).catchError((_) {});
  _dailyReportTimer = Timer.periodic(const Duration(hours: 1), (_) {
    DailyReportService.instance.generate(uid).catchError((_) {});
  });

  // Ping Flutter layer every 20 s
  _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => service.invoke('ping', {}));

  // ── Health-check watchdog ──────────────────────────────
  // Non-recursive: cancels all current resources before restarting.
  // This prevents infinite timer accumulation from self-calls.
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
        debugPrint('[BgService] Health check fail #$healthFailures');

        if (healthFailures >= 3) {
          healthFailures = 0;
          _watchdogRestarting = true;
          debugPrint('[BgService] Restarting session after repeated failures');
          _cancelSessionResources();
          DeviceEventService.writeEvent(
            childUid: uid,
            type: 'service_restored',
            message: 'Monitoring session restarted by health watchdog after repeated connectivity failures.',
            severity: 'warning',
          );
          await Future.delayed(const Duration(seconds: 2));
          await _setupMonitoringSession(service, uid);
          // P4-B: Reset the flag on the SUCCESS path. Previously it was only
          // reset in the catch block, so a successful restart left
          // _watchdogRestarting = true permanently — suppressing all future
          // watchdog restarts for the lifetime of the service process.
          _watchdogRestarting = false;
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
