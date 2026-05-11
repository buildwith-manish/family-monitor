import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

class GeofenceService {
  static final GeofenceService _i = GeofenceService._();

  factory GeofenceService() {
    return _i;
  }

  GeofenceService._();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  final Uuid _uuid = const Uuid();

  final Map<String, bool> _insideZone = <String, bool>{};

  Future<String> saveZone(
    String childUid,
    GeofenceZone zone,
  ) async {
    final String id = zone.id.isNotEmpty ? zone.id : _uuid.v4();

    await _db
        .child(
          'geofences/$childUid/$id',
        )
        .set(
          zone.copyWith(id: id).toMap(),
        );

    return id;
  }

  Future<void> deleteZone(
    String childUid,
    String zoneId,
  ) async {
    await _db
        .child(
          'geofences/$childUid/$zoneId',
        )
        .remove();
  }

  Stream<List<GeofenceZone>> watchZones(
    String childUid,
  ) {
    return _db
        .child(
          'geofences/$childUid',
        )
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null) {
        return <GeofenceZone>[];
      }

      final Map<String, dynamic> map =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      return map.entries.map((e) {
        return GeofenceZone.fromMap(
          e.key,
          Map<String, dynamic>.from(
            e.value as Map,
          ),
        );
      }).toList();
    });
  }

  Future<List<GeofenceZone>> getZones(
    String childUid,
  ) async {
    final DataSnapshot snap = await _db
        .child(
          'geofences/$childUid',
        )
        .get();

    if (snap.value == null) {
      return <GeofenceZone>[];
    }

    final Map<String, dynamic> map = Map<String, dynamic>.from(
      snap.value as Map,
    );

    return map.entries.map((e) {
      return GeofenceZone.fromMap(
        e.key,
        Map<String, dynamic>.from(
          e.value as Map,
        ),
      );
    }).toList();
  }

  Future<void> checkZones({
    required String childUid,
    required double lat,
    required double lng,
    required List<String> parentUids,
  }) async {
    final List<GeofenceZone> zones = await getZones(childUid);

    final DataSnapshot snap = await _db
        .child(
          'users/$childUid',
        )
        .get();

    final String childName =
        snap.child('childName').value as String? ?? 'Child';

    for (final GeofenceZone zone in zones) {
      final bool inside = _distanceMeters(
            lat,
            lng,
            zone.lat,
            zone.lng,
          ) <=
          zone.radius;

      final bool wasInside = _insideZone[zone.id] ?? false;

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
        );
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
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    final Map<String, dynamic> payload = <String, dynamic>{
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

    final Map<String, dynamic> updates = <String, dynamic>{};

    for (final String parentUid in parentUids) {
      updates['alerts/$parentUid/geofence/$timestamp'] = payload;
    }

    await _db.update(updates);
  }

  Stream<List<GeofenceAlert>> watchGeofenceAlerts(
    String parentUid,
  ) {
    return _db
        .child(
          'alerts/$parentUid/geofence',
        )
        .orderByChild(
          'timestamp',
        )
        .limitToLast(100)
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null) {
        return <GeofenceAlert>[];
      }

      final Map<String, dynamic> map =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      final List<GeofenceAlert> alerts = map.entries.map((e) {
        return GeofenceAlert.fromMap(
          e.key,
          Map<String, dynamic>.from(
            e.value as Map,
          ),
        );
      }).toList();

      alerts.sort(
        (a, b) => b.timestamp.compareTo(
          a.timestamp,
        ),
      );

      return alerts;
    });
  }

  Future<void> acknowledgeGeofenceAlert(
    String parentUid,
    String alertKey,
  ) async {
    await _db
        .child(
          'alerts/$parentUid/geofence/$alertKey/acknowledged',
        )
        .set(true);
  }

  double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double r = 6371000.0;

    final double dLat = _toRad(lat2 - lat1);

    final double dLng = _toRad(lng2 - lng1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);

    final double c = 2 *
        atan2(
          sqrt(a),
          sqrt(1 - a),
        );

    return r * c;
  }

  double _toRad(
    double deg,
  ) {
    return deg * pi / 180;
  }
}

class GeofenceZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radius;
  final String color;

  const GeofenceZone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
    this.color = 'EA4335',
  });

  factory GeofenceZone.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return GeofenceZone(
      id: id,
      name: map['name'] as String? ?? 'Zone',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      radius: (map['radius'] as num).toDouble(),
      color: map['color'] as String? ?? 'EA4335',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'color': color,
    };
  }

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
    );
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
  });

  factory GeofenceAlert.fromMap(
    String key,
    Map<String, dynamic> map,
  ) {
    return GeofenceAlert(
      key: key,
      childName: map['childName'] as String? ?? 'Child',
      zoneName: map['zoneName'] as String? ?? 'Zone',
      entered: map['entered'] == true,
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? 0,
      ),
      acknowledged: map['acknowledged'] == true,
    );
  }

  String get timeAgo {
    final Duration diff = DateTime.now().difference(
      timestamp,
    );

    if (diff.inSeconds < 60) {
      return 'Just now';
    }

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }

    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }

    return '${diff.inDays}d ago';
  }
}
