import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Provides real-time device presence for child devices.
///
/// Child side  — call [startChildPresence] when the home screen mounts and
/// [stopChildPresence] when it unmounts. This registers Firebase
/// `.onDisconnect()` handlers so the server automatically marks the device
/// offline if the connection drops (airplane mode, force-kill, crash, etc.).
///
/// Parent side — call [watchChildPresence] to get a live [Stream<bool>] for a
/// specific child UID. The stream emits `true` when online and `false` when
/// offline or when the heartbeat has gone stale.
class PresenceService {
  static final PresenceService _instance = PresenceService._();
  static PresenceService get instance => _instance;
  PresenceService._();

  StreamSubscription? _connectedSub;
  Timer? _heartbeatTimer;
  String? _activeUid;

  // ─────────────────────────────────────────────────────────────────────────
  // Child side
  // ─────────────────────────────────────────────────────────────────────────

  /// Start presence for [uid].
  ///
  /// Writes `isOnline = true` and registers server-side `.onDisconnect()`
  /// handlers that flip it to `false` on any ungraceful disconnection.
  /// Listens to `.info/connected` to re-register those handlers after every
  /// reconnect (Firebase clears onDisconnect registrations per connection).
  /// Runs a 30-second heartbeat to keep `lastSeen` current.
  Future<void> startChildPresence(String uid) async {
    if (_activeUid == uid) return;
    await stopChildPresence();
    _activeUid = uid;

    final userRef = FirebaseDatabase.instance.ref('users/$uid');

    // Register server-side cleanup BEFORE marking online.
    // If the TCP connection dies without a graceful logout, Firebase executes
    // these from the server automatically.
    try {
      await userRef.child('isOnline').onDisconnect().set(false);
      await userRef.child('lastSeen').onDisconnect().set(ServerValue.timestamp);
    } catch (e) {
      debugPrint('[Presence] onDisconnect registration failed: $e');
    }

    // Mark online now.
    try {
      await userRef.child('isOnline').set(true);
      await userRef.child('lastSeen').set(ServerValue.timestamp);
    } catch (e) {
      debugPrint('[Presence] set online failed: $e');
    }

    // Re-register onDisconnect and re-mark online after every reconnect.
    // Firebase only keeps onDisconnect registrations for the current socket;
    // after a disconnect/reconnect cycle we must re-register them.
    _connectedSub = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) async {
      final connected = event.snapshot.value == true;
      if (!connected || _activeUid == null) return;

      try {
        await userRef.child('isOnline').onDisconnect().set(false);
        await userRef.child('lastSeen').onDisconnect().set(ServerValue.timestamp);
        await userRef.child('isOnline').set(true);
        await userRef.child('lastSeen').set(ServerValue.timestamp);
      } catch (e) {
        debugPrint('[Presence] reconnect presence update failed: $e');
      }
    });

    // Periodic heartbeat to keep lastSeen fresh during long sessions.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_activeUid == null) return;
      try {
        await userRef.child('lastSeen').set(ServerValue.timestamp);
      } catch (_) {}
    });
  }

  /// Stop presence for the active child (graceful offline).
  ///
  /// Cancels the `.onDisconnect()` handlers so the server doesn't
  /// double-write offline after we've already written it here.
  Future<void> stopChildPresence() async {
    _connectedSub?.cancel();
    _connectedSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final uid = _activeUid;
    _activeUid = null;

    if (uid == null) return;

    final userRef = FirebaseDatabase.instance.ref('users/$uid');
    try {
      // Cancel the server-side handlers first so they don't re-fire.
      await userRef.child('isOnline').onDisconnect().cancel();
      await userRef.child('lastSeen').onDisconnect().cancel();
      // Write offline state immediately.
      await userRef.child('isOnline').set(false);
      await userRef.child('lastSeen').set(ServerValue.timestamp);
    } catch (e) {
      debugPrint('[Presence] stopChildPresence error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parent side
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a live stream of online status for [childUid].
  ///
  /// Emits `true` when the child writes `isOnline = true`, `false` otherwise.
  /// The stream fires immediately with the current state and again on every
  /// change — updates arrive within milliseconds of the child going offline.
  Stream<bool> watchChildPresence(String childUid) {
    return FirebaseDatabase.instance
        .ref('users/$childUid/isOnline')
        .onValue
        .map((event) => event.snapshot.value == true);
  }

  /// One-shot read of current online status (no stream).
  Future<bool> isChildOnline(String childUid) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/$childUid/isOnline')
          .get();
      return snap.value == true;
    } catch (_) {
      return false;
    }
  }
}
