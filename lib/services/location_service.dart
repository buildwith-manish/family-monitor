// ignore_for_file: unnecessary_cast
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Tracks the child device's GPS position and uploads it to Firebase.
///
/// Child side — call [startTracking] after permissions are granted.
/// Parent side — call [watchChildLocation] to get a live position stream,
/// and [watchGeofenceAlerts] to listen for breach events.
class LocationService {
  static final LocationService _instance = LocationService._();
  static LocationService get instance => _instance;
  LocationService._();

  StreamSubscription<Position>? _positionSub;
  Timer? _geofenceCheckTimer;
  String? _activeUid;

  final _db = FirebaseDatabase.instance.ref();

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Child side — tracking
  // ─────────────────────────────────────────────────────────────────────────

  /// Start continuous GPS tracking and upload to Firebase.
  /// Checks against saved geofences after every position update.
  Future<void> startTracking(String uid) async {
    if (_activeUid == uid) return;
    await stopTracking();
    _activeUid = uid;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 30, // metres — only fire when moved >30 m
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
      _activeUid = uid; // keep alive
      try {
        await _db.child('location/$uid').set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'timestamp': pos.timestamp.millisecondsSinceEpoch,
        });
        await _checkGeofences(uid, pos.latitude, pos.longitude);
      } catch (e) {
        debugPrint('[Location] upload error: $e');
      }
    }, onError: (e) {
      debugPrint('[Location] stream error: $e');
    });
  }

  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _geofenceCheckTimer?.cancel();
    _geofenceCheckTimer = null;
    _activeUid = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Geofence checking (child side)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkGeofences(
      String uid, double lat, double lng) async {
    try {
      final snap = await _db.child('geofences/$uid').get();
      if (snap.value == null || snap.value is! Map) return;

      final fences = Map<String, dynamic>.from(snap.value as Map);
      for (final entry in fences.entries) {
        final id = entry.key;
        final raw = Map<String, dynamic>.from(entry.value as Map);

        final fenceLat = (raw['lat'] as num?)?.toDouble();
        final fenceLng = (raw['lng'] as num?)?.toDouble();
        final radiusM = (raw['radiusMeters'] as num?)?.toDouble() ?? 200;
        final name = raw['name'] as String? ?? 'Zone';
        final alertOnExit = raw['alertOnExit'] as bool? ?? true;
        final alertOnEnter = raw['alertOnEnter'] as bool? ?? false;
        final wasInside = raw['_lastInside'] as bool? ?? false;

        if (fenceLat == null || fenceLng == null) continue;

        final distanceM = Geolocator.distanceBetween(lat, lng, fenceLat, fenceLng);
        final nowInside = distanceM <= radiusM;

        // State changed?
        if (nowInside != wasInside) {
          await _db.child('geofences/$uid/$id/_lastInside').set(nowInside);

          if (!nowInside && alertOnExit) {
            await _writeAlert(uid, id, name, 'exit', lat, lng);
          } else if (nowInside && alertOnEnter) {
            await _writeAlert(uid, id, name, 'enter', lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint('[Location] geofence check error: $e');
    }
  }

  Future<void> _writeAlert(String uid, String fenceId, String fenceName,
      String type, double lat, double lng) async {
    final alertRef = _db.child('geofence_alerts/$uid').push();
    await alertRef.set({
      'fenceId': fenceId,
      'fenceName': fenceName,
      'type': type, // 'exit' or 'enter'
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'read': false,
    });
    debugPrint('[Location] Geofence alert: $type "$fenceName"');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parent side — streams
  // ─────────────────────────────────────────────────────────────────────────

  /// Live stream of the child's current GPS position.
  Stream<Map<String, dynamic>?> watchChildLocation(String childUid) {
    return _db.child('location/$childUid').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return null;
      return Map<String, dynamic>.from(v);
    });
  }

  /// Live stream of geofence breach alerts (newest first, unread only).
  Stream<List<Map<String, dynamic>>> watchGeofenceAlerts(String childUid) {
    return _db
        .child('geofence_alerts/$childUid')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];

      final list = (v as Map).entries
          .map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            m['_key'] = e.key;
            return m;
          })
          .toList()
        ..sort((a, b) => ((b['timestamp'] as int?) ?? 0)
            .compareTo((a['timestamp'] as int?) ?? 0));

      return list;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Geofence CRUD (parent side)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> addGeofence({
    required String childUid,
    required String name,
    required double lat,
    required double lng,
    required double radiusMeters,
    bool alertOnExit = true,
    bool alertOnEnter = false,
  }) async {
    final ref = _db.child('geofences/$childUid').push();
    await ref.set({
      'name': name,
      'lat': lat,
      'lng': lng,
      'radiusMeters': radiusMeters,
      'alertOnExit': alertOnExit,
      'alertOnEnter': alertOnEnter,
      '_lastInside': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeGeofence(String childUid, String fenceId) async {
    await _db.child('geofences/$childUid/$fenceId').remove();
  }

  Stream<List<Map<String, dynamic>>> watchGeofences(String childUid) {
    return _db.child('geofences/$childUid').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];
      return (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['_id'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => ((a['createdAt'] as int?) ?? 0)
            .compareTo((b['createdAt'] as int?) ?? 0));
    });
  }

  Future<void> markAlertRead(String childUid, String alertKey) async {
    await _db.child('geofence_alerts/$childUid/$alertKey/read').set(true);
  }
}
