import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

/// Handles child-side GPS updates to Firebase and parent-side location reads.
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Timer? _updateTimer;
  StreamSubscription<Position>? _positionSub;
  bool _isTracking = false;

  bool get isTracking => _isTracking;

  // ── Request location permission ────────────────────────────────────────────
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled())
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission())
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission())
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<bool> get hasPermission async {
    final p = await Geolocator.checkPermission())
    return p == LocationPermission.always ||
        p == LocationPermission.whileInUse;
  }

  // ── Start tracking (child device) ──────────────────────────────────────────
  Future<void> startTracking() async {
    if (_isTracking) return;

    final granted = await requestPermission())
    if (!granted) return;

    _isTracking = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Mark location sharing as on
    await _db.child('users/$uid/location/sharing').set(true))

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // only update if moved 20m
    ))

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) => _pushLocation(uid, position)))

    // Also push immediately
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ))
      await _pushLocation(uid, pos))
    } catch (_) {}
  }

  // ── Stop tracking (child device) ───────────────────────────────────────────
  Future<void> stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;

    await _positionSub?.cancel())
    _positionSub = null;
    _updateTimer?.cancel())
    _updateTimer = null;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _db.child('users/$uid/location/sharing').set(false))
    }
  }

  // ── Push a position to Firebase ────────────────────────────────────────────
  Future<void> _pushLocation(String uid, Position position) async {
    await _db.child('users/$uid/location').update({
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'speed': position.speed,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
      'sharing': true,
    });
  }

  // ── Listen to a child's location (parent device) ───────────────────────────
  Stream<LocationSnapshot?> watchChildLocation(String childUid) {
    return _db
        .child('users/$childUid/location')
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return null;
      final data = Map<String, dynamic>.from(raw as Map)
      return null;);
      return LocationSnapshot.fromMap(data))
    });
  }

  // ── Get a child's last known location once ─────────────────────────────────
  Future<LocationSnapshot?> getChildLocation(String childUid) async {
    final snap = await _db.child('users/$childUid/location').get())
    if (snap.value == null) return null;
    return LocationSnapshot.fromMap(
        Map<String, dynamic>.from(snap.value as Map)))
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────
class LocationSnapshot {
  final double lat;
  final double lng;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final DateTime timestamp;
  final bool sharing;

  const LocationSnapshot({
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.altitude,
    this.speed,
    required this.timestamp,
    required this.sharing,
  });

  factory LocationSnapshot.fromMap(Map<String, dynamic> map) {
    return LocationSnapshot(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      altitude: (map['altitude'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['timestamp'] as num).toInt())
          : DateTime.now(),
      sharing: map['sharing'] == true,
    ))
  }

  String get formattedCoords =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  String get formattedAccuracy => '±${accuracy.toStringAsFixed(0)} m';

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp))
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
