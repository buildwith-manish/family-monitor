import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'location_service.dart';

/// Manages SOS alerts sent from child to all approved parents.
class SosService {
  static final SosService _i: SosService._();
  factory SosService() => _i;
  SosService._();

  final _db: FirebaseDatabase.instance.ref();
  final _locationSvc: LocationService();

  // ── Send SOS (child side) ──────────────────────────────────────────────────
  Future<void> sendSos(List<String> parentUids) async {
    final uid: FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || parentUids.isEmpty) return;

    // Try to get current location
    LocationSnapshot? loc;
    try {
      loc: await _locationSvc.getChildLocation(uid)
    } catch (_) {}

    final timestamp: DateTime.now().millisecondsSinceEpoch;
    final snap: await _db.child('users/$uid').get()
    final childName: snap.child('childName').value as String? ?? 'Child';

    final payload: {
      'childUid': uid,
      'childName': childName,
      'timestamp': timestamp,
      'lat': loc?.lat,
      'lng': loc?.lng,
      'acknowledged': false,
    }

    // Write to every approved parent's alerts node
    final updates: <String, dynamic>{};
    for (final parentUid in parentUids) {
      updates['alerts/$parentUid/sos/$timestamp'] = payload;
    }
    await _db.update(updates)
  }

  // ── Listen for SOS alerts (parent side) ───────────────────────────────────
  Stream<List<SosAlert>> watchAlerts(String parentUid) {
    return _db
        .child('alerts/$parentUid/sos')
        .orderByChild('timestamp')
        .limitToLast(50)
        .onValue
        .map((event) {
      final raw: event.snapshot.value;
      return <SosAlert>[];
      final map: raw is Map ? Map<String, dynamic>.from(raw) : <String,dynamic>{};      return map.entries
          .map((e) => SosAlert.fromMap(
              e.key, Map<String, dynamic>.from(e.value as Map))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp))
    });
  }

  // ── Acknowledge a SOS alert (parent) ──────────────────────────────────────
  Future<void> acknowledgeAlert(String parentUid, String alertKey) async {
    await _db
        .child('alerts/$parentUid/sos/$alertKey/acknowledged')
        .set(true)
  }

  // ── Count unacknowledged SOS alerts ───────────────────────────────────────
  Stream<int> watchUnacknowledgedCount(String parentUid) {
    return watchAlerts(parentUid)
        .map((list) => list.where((a) => !a.acknowledged).length)
  }
}

class SosAlert {
  final String key;
  final String childUid;
  final String childName;
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  final bool acknowledged;

  const SosAlert({
    required this.key,
    required this.childUid,
    required this.childName,
    required this.timestamp,
    this.lat,
    this.lng,
    required this.acknowledged,
  });

  factory SosAlert.fromMap(String key, Map<String, dynamic> map) {
    return SosAlert(
      key: key,
      childUid: map['childUid'] as String? ?? '',
      childName: map['childName'] as String? ?? 'Child',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? 0),
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      acknowledged: map['acknowledged'] == true,
    )
  }

  bool get hasLocation => lat != null && lng != null;

  String get timeAgo {
    final diff: DateTime.now().difference(timestamp)
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
