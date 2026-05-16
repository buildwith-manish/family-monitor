import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Manages monitoring session lifecycle, IDs, and state.
class SessionManager {
  static SessionManager? _instance;
  static SessionManager get instance => _instance ??= SessionManager._();

  SessionManager._();

  String? _currentSessionId;
  String? _currentStreamId;
  String? _childUid;
  SessionState _state = SessionState.idle;
  DateTime? _sessionStartTime;
  String? _reconnectToken;

  String? get currentSessionId => _currentSessionId;
  String? get currentStreamId => _currentStreamId;
  String? get childUid => _childUid;
  SessionState get state => _state;
  DateTime? get sessionStartTime => _sessionStartTime;
  bool get isActive => _state == SessionState.active;
  bool get isReconnecting => _state == SessionState.reconnecting;

  /// Start a new monitoring session.
  Future<void> startSession(String uid, {String mode = 'screen'}) async {
    _childUid = uid;
    _currentSessionId = 'sess_${uid}_${DateTime.now().millisecondsSinceEpoch}';
    _currentStreamId = 'stream_${uid}_${DateTime.now().millisecondsSinceEpoch}';
    _sessionStartTime = DateTime.now();
    _state = SessionState.connecting;

    // Generate reconnect token
    _reconnectToken = 'rt_${DateTime.now().millisecondsSinceEpoch}_${uid.hashCode.abs()}';

    // Write session metadata to Firebase
    try {
      await FirebaseDatabase.instance.ref('calls/$uid/session').set({
        'sessionId': _currentSessionId,
        'streamId': _currentStreamId,
        'reconnectToken': _reconnectToken,
        'startTime': ServerValue.timestamp,
        'state': 'connecting',
        'mode': mode,
      });
    } catch (e) {
      debugPrint('[SessionManager] Failed to write session metadata: $e');
    }

    debugPrint('[SessionManager] Session started: $_currentSessionId');
  }

  /// Mark session as active (connected).
  void markActive() {
    _state = SessionState.active;
    _updateSessionState('active');
  }

  /// Mark session as reconnecting.
  void markReconnecting() {
    _state = SessionState.reconnecting;
    _updateSessionState('reconnecting');
  }

  /// End the current session.
  Future<void> endSession() async {
    if (_childUid != null) {
      try {
        await FirebaseDatabase.instance.ref('calls/$_childUid/session').update({
          'state': 'ended',
          'endTime': ServerValue.timestamp,
        });
      } catch (e) {
        debugPrint('[SessionManager] Failed to update session end: $e');
      }
    }

    _currentSessionId = null;
    _currentStreamId = null;
    _childUid = null;
    _state = SessionState.idle;
    _sessionStartTime = null;
    _reconnectToken = null;

    debugPrint('[SessionManager] Session ended');
  }

  /// Try to resume a session using a reconnect token.
  Future<bool> tryResumeSession(String uid) async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('calls/$uid/session')
          .get();

      if (!snapshot.exists) return false;

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      if (data['state'] == 'active' || data['state'] == 'connecting') {
        _childUid = uid;
        _currentSessionId = data['sessionId'] as String?;
        _currentStreamId = data['streamId'] as String?;
        _reconnectToken = data['reconnectToken'] as String?;
        _state = SessionState.reconnecting;
        debugPrint('[SessionManager] Session resumed: $_currentSessionId');
        return true;
      }
    } catch (e) {
      debugPrint('[SessionManager] Resume failed: $e');
    }
    return false;
  }

  /// Write capture status event to Firebase.
  Future<void> reportCaptureStatus(String status, {String? error, Map<String, dynamic>? extras}) async {
    if (_childUid == null) return;
    try {
      await FirebaseDatabase.instance.ref('calls/$_childUid/captureStatus').set({
        'status': status,
        'error': error,
        'sessionId': _currentSessionId,
        'timestamp': ServerValue.timestamp,
        if (extras != null) ...extras,
      });
    } catch (e) {
      debugPrint('[SessionManager] Failed to report capture status: $e');
    }
  }

  /// Write stream health stats to Firebase.
  Future<void> reportStreamHealth(Map<String, dynamic> health) async {
    if (_childUid == null) return;
    try {
      await FirebaseDatabase.instance.ref('calls/$_childUid/streamHealth').set({
        'sessionId': _currentSessionId,
        'timestamp': ServerValue.timestamp,
        ...health,
      });
    } catch (e) {
      debugPrint('[SessionManager] Failed to report stream health: $e');
    }
  }

  void _updateSessionState(String state) {
    if (_childUid == null) return;
    FirebaseDatabase.instance
        .ref('calls/$_childUid/session/state')
        .set(state)
        .catchError((_) => null);
  }
}

enum SessionState {
  idle,
  connecting,
  active,
  reconnecting,
  ended,
}
