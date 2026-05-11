import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screen_capture_channel.dart';

enum StreamMode { camera, screen }

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream?       _localStream;

  final RTCVideoRenderer localRenderer  = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final _db = FirebaseDatabase.instance.ref();

  StreamSubscription? _offerSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _commandSub;

  bool _initialized   = false;
  bool _answerSet     = false;
  bool _disposed      = false;

  int  _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;
  VoidCallback? _onCallEndedCallback;
  String? _activeChildUid;
  StreamMode _activeMode = StreamMode.camera;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  Future<void> initialize() async {
    if (_initialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _initialized = true;
  }

  // Check permissions silently — only shows dialog if revoked manually
  static Future<bool> ensureCameraPermissions() async {
    final camStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    if (camStatus.isGranted && micStatus.isGranted) return true;
    if (camStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
      debugPrint('[WebRTC] Permanently denied — user must enable in Settings.');
      return false;
    }
    final results = await [Permission.camera, Permission.microphone].request();
    return results[Permission.camera]!.isGranted &&
           results[Permission.microphone]!.isGranted;
  }

  Future<void> startAsChild(String childUid, VoidCallback onCallEnded) async {
    if (_disposed) return;
    await _cleanupPeerConnection();
    await initialize();
    _activeChildUid      = childUid;
    _activeMode          = StreamMode.camera;
    _onCallEndedCallback = onCallEnded;
    _reconnectAttempts   = 0;
    final hasPerms = await ensureCameraPermissions();
    if (!hasPerms) { onCallEnded(); return; }
    await _buildCameraConnection(childUid, onCallEnded);
  }

  Future<void> _buildCameraConnection(String childUid, VoidCallback onCallEnded) async {
    try {
      _peerConnection = await createPeerConnection(_iceConfig);
      _localStream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}, 'frameRate': {'ideal': 24}},
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
      });
      localRenderer.srcObject = _localStream;
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
      _peerConnection!.onIceCandidate = (c) {
        if (c.candidate != null && !_disposed) {
          _db.child('calls/$childUid/childCandidates').push().set({
            'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex,
          });
        }
      };
      _peerConnection!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _scheduleReconnect(childUid, onCallEnded);
        }
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _reconnectAttempts = 0;
          _reconnectTimer?.cancel();
        }
      };
      _offerSub = _db.child('calls/$childUid/offer').onValue.listen((e) async {
        if (e.snapshot.value == null || _peerConnection == null || _disposed) return;
        try {
          final d = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          final ans = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(ans);
          if (!_disposed) await _db.child('calls/$childUid/answer').set({'sdp': ans.sdp, 'type': ans.type});
        } catch (ex) { debugPrint('[WebRTC] answer error: $ex'); }
      });
      _candidateSub = _db.child('calls/$childUid/parentCandidates').onChildAdded.listen((e) async {
        if (e.snapshot.value == null || _peerConnection == null) return;
        try {
          final c = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _peerConnection!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
        } catch (_) {}
      });
      _commandSub = _db.child('calls/$childUid/command').onValue.listen((e) async {
        final cmd = e.snapshot.value as String?;
        if (cmd == 'flip')   await switchCamera();
        if (cmd == 'mute')   _setAudioEnabled(false);
        if (cmd == 'unmute') _setAudioEnabled(true);
      });
      _statusSub = _db.child('calls/$childUid/status').onValue.listen((e) {
        if (e.snapshot.value == 'ended' && !_disposed) {
          _reconnectTimer?.cancel();
          onCallEnded();
        }
      });
    } catch (e) {
      debugPrint('[WebRTC] _buildCameraConnection error: $e');
      _scheduleReconnect(childUid, onCallEnded);
    }
  }

  void _scheduleReconnect(String childUid, VoidCallback onCallEnded) {
    if (_disposed || _reconnectAttempts >= _maxReconnectAttempts) { onCallEnded(); return; }
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      await _cleanupPeerConnection();
      if (_activeMode == StreamMode.camera) {
        await _buildCameraConnection(childUid, onCallEnded);
      } else {
        await _buildScreenConnection(childUid, onCallEnded);
      }
    });
  }

  Future<void> startScreenShareAsChild(String childUid, VoidCallback onCallEnded) async {
    if (_disposed) return;
    await _cleanupPeerConnection();
    await initialize();
    _activeChildUid      = childUid;
    _activeMode          = StreamMode.screen;
    _onCallEndedCallback = onCallEnded;
    _reconnectAttempts   = 0;
    await _buildScreenConnection(childUid, onCallEnded);
  }

  Future<void> _buildScreenConnection(String childUid, VoidCallback onCallEnded) async {
    try {
      _peerConnection = await createPeerConnection(_iceConfig);
      try {
        _localStream = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': true});
      } catch (e) {
        debugPrint('[WebRTC] getDisplayMedia failed: $e — fallback to camera');
        final hasPerms = await ensureCameraPermissions();
        if (!hasPerms) { onCallEnded(); return; }
        _localStream = await navigator.mediaDevices.getUserMedia({'video': {'facingMode': 'user'}, 'audio': true});
      }
      for (final track in _localStream!.getTracks()) await _peerConnection!.addTrack(track, _localStream!);
      _peerConnection!.onIceCandidate = (c) {
        if (c.candidate != null && !_disposed) {
          _db.child('calls/$childUid/childCandidates').push().set({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
        }
      };
      _peerConnection!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _scheduleReconnect(childUid, onCallEnded);
        }
      };
      _offerSub = _db.child('calls/$childUid/offer').onValue.listen((e) async {
        if (e.snapshot.value == null || _peerConnection == null || _disposed) return;
        try {
          final d = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          final ans = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(ans);
          if (!_disposed) await _db.child('calls/$childUid/answer').set({'sdp': ans.sdp, 'type': ans.type});
        } catch (ex) { debugPrint('[WebRTC] screen answer: $ex'); }
      });
      _candidateSub = _db.child('calls/$childUid/parentCandidates').onChildAdded.listen((e) async {
        if (e.snapshot.value == null || _peerConnection == null) return;
        try {
          final c = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _peerConnection!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
        } catch (_) {}
      });
      _statusSub = _db.child('calls/$childUid/status').onValue.listen((e) {
        if (e.snapshot.value == 'ended' && !_disposed) {
          ScreenCaptureChannel.stopScreenCaptureService();
          _reconnectTimer?.cancel();
          onCallEnded();
        }
      });
    } catch (e) {
      debugPrint('[WebRTC] _buildScreenConnection error: $e');
      _scheduleReconnect(childUid, onCallEnded);
    }
  }

  Future<void> startAsParent(String childUid, StreamMode mode, VoidCallback onStreamReady) async {
    if (_disposed) return;
    await _cleanupPeerConnection();
    await initialize();
    _answerSet = false;
    _peerConnection = await createPeerConnection(_iceConfig);
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty && !_disposed) {
        remoteRenderer.srcObject = event.streams.first;
        onStreamReady();
      }
    };
    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null && !_disposed) {
        _db.child('calls/$childUid/parentCandidates').push().set({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
      }
    };
    final offer = await _peerConnection!.createOffer({'offerToReceiveVideo': true, 'offerToReceiveAudio': true});
    await _peerConnection!.setLocalDescription(offer);
    await _db.child('calls/$childUid').set({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'status': 'calling',
      'mode': mode == StreamMode.screen ? 'screen' : 'camera',
    });
    _answerSub = _db.child('calls/$childUid/answer').onValue.listen((e) async {
      if (e.snapshot.value == null || _answerSet || _disposed) return;
      try {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        final sigState = _peerConnection?.signalingState;
        if (sigState != RTCSignalingState.RTCSignalingStateStable) {
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          _answerSet = true;
        }
      } catch (ex) { debugPrint('[WebRTC][Parent] remote desc: $ex'); }
    });
    _candidateSub = _db.child('calls/$childUid/childCandidates').onChildAdded.listen((e) async {
      if (e.snapshot.value == null || _peerConnection == null) return;
      try {
        final c = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
      } catch (_) {}
    });
  }

  Future<void> sendFlipCommand(String childUid) async {
    await _db.child('calls/$childUid/command').set('flip');
    await Future.delayed(const Duration(milliseconds: 500));
    await _db.child('calls/$childUid/command').remove();
  }

  Future<void> sendMuteCommand(String childUid, bool mute) async {
    await _db.child('calls/$childUid/command').set(mute ? 'mute' : 'unmute');
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  void _setAudioEnabled(bool enabled) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = enabled);
  }

  Future<void> _cleanupPeerConnection() async {
    _reconnectTimer?.cancel();
    _offerSub?.cancel(); _answerSub?.cancel(); _candidateSub?.cancel();
    _statusSub?.cancel(); _commandSub?.cancel();
    _offerSub = _answerSub = _candidateSub = _statusSub = _commandSub = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    try { await _peerConnection?.close(); } catch (_) {}
    _peerConnection = null;
    _answerSet = false;
  }

  Future<void> endCall(String childUid) async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    try {
      await _db.child('calls/$childUid/status').set('ended');
      await Future.delayed(const Duration(milliseconds: 300));
      await _db.child('calls/$childUid').remove();
    } catch (_) {}
    await _cleanupPeerConnection();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanupPeerConnection();
    if (_initialized) {
      try { localRenderer.dispose(); remoteRenderer.dispose(); } catch (_) {}
      _initialized = false;
    }
  }
}
