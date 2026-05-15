import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Panic / SOS feature.
///
/// Child side:
///   [sendPanic] — called when the child long-presses the SOS button.
///   Grabs the current GPS position (or last known) and writes to
///   panic_alerts/$uid with timestamp, lat, lng, and read=false.
///
/// Parent side:
///   [watchPanicAlerts] — live stream of all panic events, newest first.
///   [markRead]         — mark an alert as read.
///   [clearAlerts]      — delete all panic alerts for this child.
class PanicService {
  static final PanicService _i = PanicService._();
  factory PanicService() => _i;
  PanicService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Child side ────────────────────────────────────────────────────────────

  /// Fire an SOS alert.  Gets the most accurate location available within
  /// 5 seconds, falls back to last known position if GPS is slow.
  Future<void> sendPanic(String uid) async {
    double? lat;
    double? lng;
    double? accuracy;

    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
        accuracy = pos.accuracy;
      }
    } catch (_) {
      // Fallback: read the last uploaded location from Firebase.
      try {
        final snap = await _db.child('location/$uid').get();
        if (snap.value is Map) {
          final m = Map<String, dynamic>.from(snap.value as Map);
          lat = (m['lat'] as num?)?.toDouble();
          lng = (m['lng'] as num?)?.toDouble();
          accuracy = (m['accuracy'] as num?)?.toDouble();
        }
      } catch (_) {}
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.child('panic_alerts/$uid').push().set({
      'timestamp': now,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'read': false,
    });

    debugPrint('[Panic] SOS sent: lat=$lat, lng=$lng');
  }

  // ── Parent side ───────────────────────────────────────────────────────────

  /// Live stream of all panic alerts for [childUid], newest first.
  Stream<List<Map<String, dynamic>>> watchPanicAlerts(String childUid) {
    return _db
        .child('panic_alerts/$childUid')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];
      return (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['_key'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => ((b['timestamp'] as num?) ?? 0)
            .compareTo((a['timestamp'] as num?) ?? 0));
    });
  }

  Future<void> markRead(String childUid, String alertKey) async {
    await _db.child('panic_alerts/$childUid/$alertKey/read').set(true);
  }

  Future<void> clearAlerts(String childUid) async {
    await _db.child('panic_alerts/$childUid').remove();
  }
}
