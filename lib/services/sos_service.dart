import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'location_service.dart';

class SosService {
  static final SosService _i = SosService._();
  factory SosService() => _i;
  SosService._();
  final _db = FirebaseDatabase.instance.ref();
  final _locationSvc = LocationService();

  Future<void> sendSos(List<String> parentUids) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || parentUids.isEmpty) return;
    LocationSnapshot? loc;
    try { loc = await _locationSvc.getChildLocation(uid); } catch (_) {}
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final snap = await _db.child('users/\$uid').get();
    final childName = snap.child('childName').value as String? ?? 'Child';
    final payload = {'childUid': uid, 'childName': childName, 'timestamp': timestamp,
      'lat': loc?.lat, 'lng': loc?.lng, 'acknowledged': false};
    final updates = <String, dynamic>{};
    for (final p in parentUids) updates['alerts/\$p/sos/\$timestamp'] = payload;
    await _db.update(updates);
  }

  Stream<List<SosAlert>> watchAlerts(String parentUid) {
    return _db.child('alerts/\$parentUid/sos').orderByChild('timestamp').limitToLast(50)
        .onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <SosAlert>[];
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      return map.entries.map((e) => SosAlert.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  Future<void> acknowledgeAlert(String parentUid, String alertKey) async {
    await _db.child('alerts/\$parentUid/sos/\$alertKey/acknowledged').set(true);
  }

  Stream<int> watchUnacknowledgedCount(String parentUid) =>
      watchAlerts(parentUid).map((l) => l.where((a) => !a.acknowledged).length);
}

class SosAlert {
  final String key, childUid, childName;
  final DateTime timestamp;
  final double? lat, lng;
  final bool acknowledged;
  const SosAlert({required this.key, required this.childUid, required this.childName,
      required this.timestamp, this.lat, this.lng, required this.acknowledged});
  factory SosAlert.fromMap(String key, Map<String, dynamic> m) => SosAlert(
    key: key, childUid: m['childUid'] as String? ?? '',
    childName: m['childName'] as String? ?? 'Child',
    timestamp: DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as num?)?.toInt() ?? 0),
    lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(),
    acknowledged: m['acknowledged'] == true);
  bool get hasLocation => lat != null && lng != null;
  String get timeAgo { final d=DateTime.now().difference(timestamp); if(d.inSeconds<60)return 'Just now'; if(d.inMinutes<60)return '\${d.inMinutes}m ago'; if(d.inHours<24)return '\${d.inHours}h ago'; return '\${d.inDays}d ago'; }
}
