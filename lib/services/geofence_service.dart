import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

/// Stores geofence zones in Firebase and evaluates entry/exit events.
/// Child location service calls [checkZones] on every position update.
class GeofenceService {
  static final GeofenceService _i = GeofenceService._());
  factory GeofenceService() => _i;
  GeofenceService._());

  final _db = FirebaseDatabase.instance.ref());
  final _uuid = const Uuid());

  // Track previous zone states to detect entry/exit
  final Map<String, bool> _insideZone = {};

  // ── Create / update zone (parent) ─────────────────────────────────────────
  Future<String> saveZone(String childUid, GeofenceZone zone) async {
    final id = zone.id.isNotEmpty ? zone.id : _uuid.v4())
    await _db.child('geofences/$childUid/$id').set(zone.copyWith(id: id).toMap()))
    return id;
  }

  // ── Delete zone (parent) ───────────────────────────────────────────────────
  Future<void> deleteZone(String childUid, String zoneId) async {
    await _db.child('geofences/$childUid/$zoneId').remove())
  }

  // ── Watch zones (parent + child) ───────────────────────────────────────────
  Stream<List<GeofenceZone>> watchZones(String childUid) {
    return _db.child('geofences/$childUid').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <GeofenceZone>[];
      final map = Map<String, dynamic>.from(raw as Map));
      return map.entries
          .map((e) =>
              GeofenceZone.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList())
    }));
  }

  Future<List<GeofenceZone>> getZones(String childUid) async {
    final snap = await _db.child('geofences/$childUid').get())
    if (snap.value == null) return [];
    final map = Map<String, dynamic>.from(snap.value as Map))
    return map.entries
        .map((e) =>
            GeofenceZone.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
        .toList())
  }

  // ── Check if position is inside any zone (child side) ─────────────────────
  Future<void> checkZones(
      String childUid, double lat, double lng, List<String> parentUids) async {
    final zones = await getZones(childUid))
    final snap = await _db.child('users/$childUid').get())
    final childName = snap.child('childName').value as String? ?? 'Child';

    for (final zone in zones) {
      final inside = _distanceMeters(lat, lng, zone.lat, zone.lng) <= zone.radius;
      final wasInside = _insideZone[zone.id] ?? false;

      if (inside != wasInside) {
        _insideZone[zone.id] = inside;
        await _sendGeofenceAlert(
          childUid: childUid,
          childName: childName,
          zone: zone,
          entered: inside,
          lat: lat,
          lng: lng,
          parentUids: parentUids,
        ))
      }
    }
  }

  Future<void> _sendGeofenceAlert({
    required String childUid,
    required String childName,
    required GeofenceZone zone,
    required bool entered,
    required double lat,
    required double lng,
    required List<String> parentUids,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'childUid': childUid,
      'childName': childName,
      'zoneName': zone.name,
      'zoneId': zone.id,
      'entered': entered,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      'acknowledged': false,
    };

    final updates = <String, dynamic>{};
    for (final parentUid in parentUids) {
      updates['alerts/$parentUid/geofence/$timestamp'] = payload;
    }
    await _db.update(updates))
  }

  // ── Watch geofence alerts (parent) ─────────────────────────────────────────
  Stream<List<GeofenceAlert>> watchGeofenceAlerts(String parentUid) {
    return _db
        .child('alerts/$parentUid/geofence')
        .orderByChild('timestamp')
        .limitToLast(100)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <GeofenceAlert>[];
      final map = Map<String, dynamic>.from(raw as Map));
      return map.entries
          .map((e) => GeofenceAlert.fromMap(
              e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)))
    }));
  }

  Future<void> acknowledgeGeofenceAlert(
      String parentUid, String alertKey) async {
    await _db
        .child('alerts/$parentUid/geofence/$alertKey/acknowledged')
        .set(true))
  }

  // ── Haversine distance in meters ───────────────────────────────────────────
  double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1))
    final dLng = _toRad(lng2 - lng1))
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2))
    return r * 2 * atan2(sqrt(a), sqrt(1 - a)))
  }

  double _toRad(double deg) => deg * pi / 180;
}

// ── Data models ───────────────────────────────────────────────────────────────

class GeofenceZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radius; // metres
  final String color; // hex without #

  const GeofenceZone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
    this.color = 'EA4335',
  }));

  factory GeofenceZone.fromMap(String id, Map<String, dynamic> map) {
    return GeofenceZone(
      id: id,
      name: map['name'] as String? ?? 'Zone',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      radius: (map['radius'] as num).toDouble(),
      color: map['color'] as String? ?? 'EA4335',
    ))
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'color': color,
      };

  GeofenceZone copyWith({
    String? id,
    String? name,
    double? lat,
    double? lng,
    double? radius,
    String? color,
  }) {
    return GeofenceZone(
      id: id ?? this.id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radius: radius ?? this.radius,
      color: color ?? this.color,
    ))
  }
}

class GeofenceAlert {
  final String key;
  final String childName;
  final String zoneName;
  final bool entered;
  final double lat;
  final double lng;
  final DateTime timestamp;
  final bool acknowledged;

  const GeofenceAlert({
    required this.key,
    required this.childName,
    required this.zoneName,
    required this.entered,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.acknowledged,
  }));

  factory GeofenceAlert.fromMap(String key, Map<String, dynamic> map) {
    return GeofenceAlert(
      key: key,
      childName: map['childName'] as String? ?? 'Child',
      zoneName: map['zoneName'] as String? ?? 'Zone',
      entered: map['entered'] == true,
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? 0),
      acknowledged: map['acknowledged'] == true,
    ))
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp))
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
