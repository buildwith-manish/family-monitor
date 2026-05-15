// ignore_for_file: no_leading_underscores_for_local_identifiers
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages FCM token registration, local notification display, and
/// writing alert triggers to Firebase so the child-side can push them
/// to the parent device.
///
/// Architecture:
///   Child device  → writes alerts to Firebase (geofence_alerts, battery_alerts,
///                   users/$uid/isOnline = false)
///   Cloud Function → would ideally send FCM to parent token. Since we have no
///                   server, the PARENT device polls these nodes directly and
///                   uses FlutterLocalNotifications to surface an alert.
///
/// This service runs on the PARENT side. It:
///   1. Requests FCM permission and saves the parent's FCM token.
///   2. Listens to battery_alerts/$childUid and geofence_alerts/$childUid.
///   3. Listens to users/$childUid/isOnline for offline events.
///   4. Shows a local notification for each new unread alert.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final _db = FirebaseDatabase.instance.ref();
  final _localNotif = FlutterLocalNotificationsPlugin();

  final Map<String, StreamSubscription> _subs = {};

  // Instance-level seen-sets keyed by alert type + childUid.
  // Keeping them at instance scope (not as local closure variables) prevents
  // the sets being reset to empty every time watchChild() cancels and
  // recreates a subscription, which would produce duplicate notifications.
  final Map<String, Set<String>> _seenAlerts = {};

  // P8-A: Bounded LRU-style pruning prevents unbounded memory growth over
  // long monitoring sessions. Firebase push keys are lexicographically ordered
  // by timestamp — removing the oldest 50 % when over 500 entries keeps memory
  // bounded while still deduplicating any alert from the last ~30 days.
  Set<String> _seenFor(String key) {
    final set = _seenAlerts.putIfAbsent(key, () => <String>{});
    if (set.length > 500) {
      final sorted = set.toList()..sort();
      set.removeAll(sorted.take(250));
    }
    return set;
  }

  bool _initialized = false;
  int _notifId = 1000;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization (call once from ParentDashboardScreen.initState)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request FCM permission.
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[Notif] FCM auth status: ${settings.authorizationStatus}');

    // Initialize flutter_local_notifications.
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _localNotif.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Create a high-priority notification channel on Android.
    const channel = AndroidNotificationChannel(
      'family_monitor_alerts',
      'Family Monitor Alerts',
      description: 'Geofence, battery and offline alerts',
      importance: Importance.high,
      playSound: true,
    );
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Handle FCM foreground messages on the parent side.
    FirebaseMessaging.onMessage.listen((msg) {
      final title = msg.notification?.title ?? 'Family Monitor';
      final body = msg.notification?.body ?? '';
      if (body.isNotEmpty) _show(title, body);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Watch a specific child's alerts (call for each child card)
  // ─────────────────────────────────────────────────────────────────────────

  void watchChild(String childUid, String childName) {
    _watchBatteryAlerts(childUid, childName);
    _watchGeofenceAlerts(childUid, childName);
    _watchOffline(childUid, childName);
    _watchServiceCrash(childUid, childName);
  }

  void unwatchChild(String childUid) {
    for (final k in [
      'battery_$childUid', 'geofence_$childUid', 'offline_$childUid',
      'crash_$childUid',
    ]) {
      _subs[k]?.cancel();
      _subs.remove(k);
      _seenAlerts.remove(k);
    }
  }

  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _seenAlerts.clear();
    _initialized = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Battery alerts
  // ─────────────────────────────────────────────────────────────────────────

  void _watchBatteryAlerts(String childUid, String childName) {
    final key = 'battery_$childUid';
    _subs[key]?.cancel();

    // Use instance-level seen-set so it survives subscription recreations.
    final seen = _seenFor(key);
    // Only notify about battery alerts that are written AFTER the parent app
    // opened this session.  Subtract 5 s to avoid missing events written just
    // before we subscribed, while still skipping old unread alerts that were
    // already in Firebase from a previous session.  This matches the behaviour
    // of Flash Get Kids — no spurious notification on every app open.
    final int startMs = DateTime.now().millisecondsSinceEpoch - 5000;

    _subs[key] = _db
        .child('battery_alerts/$childUid')
        .orderByChild('read')
        .equalTo(false)
        .onChildAdded
        .listen((event) {
      final alertKey = event.snapshot.key;
      if (alertKey == null || seen.contains(alertKey)) return;
      seen.add(alertKey);

      final v = event.snapshot.value;
      if (v == null || v is! Map) return;
      final m = Map<String, dynamic>.from(v);

      // Skip any alert that existed before this session started.
      final ts = (m['timestamp'] as num?)?.toInt() ?? 0;
      if (ts > 0 && ts < startMs) return;

      final level = (m['level'] as num?)?.toInt() ?? 0;
      _show(
        '$childName — Low Battery',
        'Battery is at $level%. Charge the device soon.',
        channelId: 'family_monitor_alerts',
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Geofence alerts
  // ─────────────────────────────────────────────────────────────────────────

  void _watchGeofenceAlerts(String childUid, String childName) {
    final key = 'geofence_$childUid';
    _subs[key]?.cancel();

    final seen = _seenFor(key);

    _subs[key] = _db
        .child('geofence_alerts/$childUid')
        .orderByChild('read')
        .equalTo(false)
        .onChildAdded
        .listen((event) {
      final alertKey = event.snapshot.key;
      if (alertKey == null || seen.contains(alertKey)) return;
      seen.add(alertKey);

      final v = event.snapshot.value;
      if (v == null || v is! Map) return;
      final m = Map<String, dynamic>.from(v);
      final type = m['type'] as String? ?? 'exit';
      final name = m['fenceName'] as String? ?? 'Safe Zone';

      _show(
        '$childName — Zone ${type == 'exit' ? 'Left' : 'Entered'}',
        type == 'exit'
            ? '$childName has left "$name".'
            : '$childName has entered "$name".',
        channelId: 'family_monitor_alerts',
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Offline alerts
  // ─────────────────────────────────────────────────────────────────────────

  void _watchOffline(String childUid, String childName) {
    final key = 'offline_$childUid';
    _subs[key]?.cancel();

    bool? _lastOnline;

    _subs[key] = _db
        .child('users/$childUid/isOnline')
        .onValue
        .listen((event) {
      final online = event.snapshot.value == true;
      // Only notify on the transition from online → offline, not on initial load.
      if (_lastOnline == true && !online) {
        _show(
          '$childName — Device Offline',
          '$childName\'s device has gone offline.',
          channelId: 'family_monitor_alerts',
        );
      }
      _lastOnline = online;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Service crash / device health alerts
  // ─────────────────────────────────────────────────────────────────────────

  void _watchServiceCrash(String childUid, String childName) {
    final key = 'crash_$childUid';
    _subs[key]?.cancel();

    final seen = _seenFor(key);
    // Subtract 5 s so we do not miss events written just before we subscribed,
    // but skip anything older that belongs to a previous session.
    final int startMs = DateTime.now().millisecondsSinceEpoch - 5000;

    _subs[key] = _db
        .child('device_events/$childUid')
        .onChildAdded
        .listen((event) {
      final alertKey = event.snapshot.key;
      if (alertKey == null || seen.contains(alertKey)) return;
      seen.add(alertKey);

      final v = event.snapshot.value;
      if (v == null || v is! Map) return;
      final m = Map<String, dynamic>.from(v);

      final severity = m['severity'] as String? ?? 'info';
      if (severity == 'info') return;

      // Skip pre-existing events from earlier sessions.
      final ts = (m['timestamp'] as int?) ?? 0;
      if (ts > 0 && ts < startMs) return;

      final type    = m['type']    as String? ?? '';
      final message = m['message'] as String? ?? '';

      final String title;
      switch (type) {
        case 'service_crash':
          title = '$childName \u2014 Monitoring Crashed';
          break;
        case 'service_restored':
          title = '$childName \u2014 Monitoring Restored';
          break;
        case 'monitoring_error':
          title = '$childName \u2014 Monitoring Error';
          break;
        case 'flutter_error':
          title = '$childName \u2014 App Error';
          break;
        default:
          title = '$childName \u2014 Device Alert';
      }

      _show(
        title,
        message.isNotEmpty ? message : 'Check Device Health for details.',
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Manual / one-shot notifications
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showImmediate(String title, String body) =>
      _show(title, body);

  // ─────────────────────────────────────────────────────────────────────────
  // Show a local notification
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _show(
    String title,
    String body, {
    String channelId = 'family_monitor_alerts',
  }) async {
    final id = _notifId++;
    await _localNotif.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Family Monitor Alerts',
          channelDescription: 'Geofence, battery and offline alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    debugPrint('[Notif] Showed: $title — $body');
  }
}
