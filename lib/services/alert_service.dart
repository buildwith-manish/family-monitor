import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Manages low-battery alert thresholds and fires alerts when the child
/// device's battery drops at or below the threshold set by the parent.
///
/// Parent side — call [setThreshold] to configure, [watchAlerts] for live feed.
/// Child side  — [BatteryService._report] writes to `deviceInfo/$uid/batteryLevel`;
///               this service watches that node and fires an alert if needed.
class AlertService {
  static final AlertService _instance = AlertService._();
  static AlertService get instance => _instance;
  AlertService._();

  final _db = FirebaseDatabase.instance.ref();
  StreamSubscription? _batterySub;

  // BUG-FIX: in-memory flag to prevent a duplicate-alert race condition.
  // Two rapid battery events can both read _lastBatteryAlertAt = 0 before
  // either has written the new timestamp, firing two alerts in the same
  // 1-hour cooldown window. This flag serialises the check-and-write.
  bool _batteryAlertInFlight = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Child side — monitoring
  // ─────────────────────────────────────────────────────────────────────────

  /// Start watching the battery level for [uid].
  /// When it drops to or below the parent's threshold, writes an alert.
  void startBatteryMonitoring(String uid) {
    _batterySub?.cancel();

    _batterySub = _db.child('deviceInfo/$uid/batteryLevel').onValue.listen(
      (event) async {
        final level = (event.snapshot.value as num?)?.toInt();
        if (level == null) return;

        try {
          final thSnap =
              await _db.child('alert_settings/$uid/batteryThreshold').get();
          final threshold = (thSnap.value as num?)?.toInt();
          if (threshold == null) return;

          if (level <= threshold) {
            await _maybeFirBatteryAlert(uid, level, threshold);
          }
        } catch (e) {
          debugPrint('[Alert] battery check error: $e');
        }
      },
    );
  }

  void stopBatteryMonitoring() {
    _batterySub?.cancel();
    _batterySub = null;
  }

  /// Fires a battery alert only if one hasn't been fired in the last hour
  /// (prevents flooding the alert feed with duplicates while battery stays low).
  ///
  /// Uses [_batteryAlertInFlight] to serialise concurrent calls so that two
  /// rapid battery updates cannot both read lastFiredAt = 0 and both fire.
  Future<void> _maybeFirBatteryAlert(
      String uid, int level, int threshold) async {
    // BUG-FIX: guard against concurrent invocations racing through the
    // cooldown check before either has written the new timestamp to Firebase.
    if (_batteryAlertInFlight) return;
    _batteryAlertInFlight = true;

    try {
      final lastFiredRef =
          _db.child('alert_settings/$uid/_lastBatteryAlertAt');
      final lastFiredSnap = await lastFiredRef.get();
      final lastFired = (lastFiredSnap.value as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - lastFired < 60 * 60 * 1000) return; // 1-hour cooldown

      // Write the timestamp FIRST so any parallel call that slips past the
      // in-memory flag will also be blocked by the Firebase cooldown check.
      await lastFiredRef.set(now);

      final alertRef = _db.child('battery_alerts/$uid').push();
      await alertRef.set({
        'level':     level,
        'threshold': threshold,
        'timestamp': now,
        'read':      false,
      });
      debugPrint('[Alert] Low battery alert fired: $level% (threshold $threshold%)');
    } catch (e) {
      debugPrint('[Alert] _maybeFirBatteryAlert error: $e');
    } finally {
      _batteryAlertInFlight = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parent side — configuration & streams
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> setThreshold(String childUid, int percent) async {
    await _db
        .child('alert_settings/$childUid/batteryThreshold')
        .set(percent);
  }

  Future<void> removeThreshold(String childUid) async {
    await _db.child('alert_settings/$childUid/batteryThreshold').remove();
    await _db.child('alert_settings/$childUid/_lastBatteryAlertAt').remove();
  }

  Future<int?> getThreshold(String childUid) async {
    final snap =
        await _db.child('alert_settings/$childUid/batteryThreshold').get();
    return (snap.value as num?)?.toInt();
  }

  Stream<int?> watchThreshold(String childUid) {
    return _db
        .child('alert_settings/$childUid/batteryThreshold')
        .onValue
        .map((e) => (e.snapshot.value as num?)?.toInt());
  }

  /// Live feed of battery alerts — newest first.
  Stream<List<Map<String, dynamic>>> watchBatteryAlerts(String childUid) {
    return _db
        .child('battery_alerts/$childUid')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];

      final list = (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['_key'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => ((b['timestamp'] as int?) ?? 0)
            .compareTo((a['timestamp'] as int?) ?? 0));

      return list;
    });
  }

  Future<void> markAlertRead(String childUid, String alertKey) async {
    await _db.child('battery_alerts/$childUid/$alertKey/read').set(true);
  }

  Future<void> clearAlerts(String childUid) async {
    await _db.child('battery_alerts/$childUid').remove();
  }
}
