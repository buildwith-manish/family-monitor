import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

import 'screen_capture_channel.dart';

enum StreamMode { camera, screen }

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer localRenderer  = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final _db = FirebaseDatabase.instance.ref();

  StreamSubscription? _offerSub, _answerSub, _candidateSub;
  bool _initialized = false;
  bool _answerSet   = false;
  bool _disposed    = false;

  int _reconnectAttempts = 0;
  static const int _maxReconnect = 5;
  Timer? _reconnectTimer;
  String? _lastChildUid;
  StreamMode? _lastMode;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };

  Future<void> initialize() async {
    if (_initialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _initialized = true;
  }

  Future<void> startAsChild({
    required String childUid,
    required StreamMode mode,
  }) async {
    if (_disposed) return;
    _lastChildUid = childUid;
    _lastMode     = mode;
    _reconnectAttempts = 0;
    await _cancelSubs();
    await _closePC();
    await initialize();

    try {
      _localStream = await _getStream(mode);
      if (_disposed) return;
      localRenderer.srcObject = _localStream;
      _peerConnection = await createPeerConnection(_iceConfig);
      _setupPCHandlers(childUid, isChild: true);
      _localStream!.getTracks().forEach((t) => _peerConnection!.addTrack(t, _localStream!));

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await _db.child('webrtc/$childUid/offer').set({'sdp': offer.sdp, 'type': offer.type});

      _answerSub = _db.child('webrtc/$childUid/answer').onValue.listen((e) async {
        if (_answerSet || _disposed) return;
        final val = e.snapshot.value;
        if (val == null) return;
        final map = Map<String, dynamic>.from(val as Map);
        if (map['sdp'] == null) return;
        _answerSet = true;
        await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(map['sdp'], map['type']));
      });

      _candidateSub = _db.child('webrtc/$childUid/parentCandidates').onChildAdded.listen((e) async {
        if (_disposed) return;
        final val = e.snapshot.value;
        if (val == null) return;
        final map = Map<String, dynamic>.from(val as Map);
        try {
          await _peerConnection?.addCandidate(
              RTCIceCandidate(map['candidate'], map['sdpMid'], map['sdpMLineIndex']));
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[WebRTC] startAsChild error: $e');
      _scheduleReconnect(childUid, mode: mode, isChild: true);
    }
  }

  Future<void> startAsParent({required String childUid}) async {
    if (_disposed) return;
    _lastChildUid = childUid;
    _reconnectAttempts = 0;
    await _cancelSubs();
    await _closePC();
    await initialize();

    try {
      _peerConnection = await createPeerConnection(_iceConfig);
      _setupPCHandlers(childUid, isChild: false);

      _offerSub = _db.child('webrtc/$childUid/offer').onValue.listen((e) async {
        if (_disposed) return;
        final val = e.snapshot.value;
        if (val == null) return;
        final map = Map<String, dynamic>.from(val as Map);
        if (map['sdp'] == null) return;
        try {
          await _peerConnection?.setRemoteDescription(
              RTCSessionDescription(map['sdp'], map['type']));
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          await _db.child('webrtc/$childUid/answer').set(
              {'sdp': answer.sdp, 'type': answer.type});
        } catch (ex) {
          debugPrint('[WebRTC] answer error: $ex');
        }
      });

      _candidateSub = _db.child('webrtc/$childUid/childCandidates').onChildAdded.listen((e) async {
        if (_disposed) return;
        final val = e.snapshot.value;
        if (val == null) return;
        final map = Map<String, dynamic>.from(val as Map);
        try {
          await _peerConnection?.addCandidate(
              RTCIceCandidate(map['candidate'], map['sdpMid'], map['sdpMLineIndex']));
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[WebRTC] startAsParent error: $e');
      _scheduleReconnect(childUid, isChild: false);
    }
  }

  void _setupPCHandlers(String childUid, {required bool isChild}) {
    _peerConnection?.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _scheduleReconnect(childUid, mode: _lastMode, isChild: isChild);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _reconnectAttempts = 0;
      }
    };

    _peerConnection?.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _scheduleReconnect(childUid, mode: _lastMode, isChild: isChild);
      }
    };

    _peerConnection?.onIceCandidate = (c) {
      if (c.candidate == null || _disposed) return;
      final path = isChild
          ? 'webrtc/$childUid/childCandidates'
          : 'webrtc/$childUid/parentCandidates';
      _db.child(path).push().set(c.toMap());
    };

    _peerConnection?.onTrack = (event) {
      if (event.streams.isNotEmpty) remoteRenderer.srcObject = event.streams[0];
    };
  }

  void _scheduleReconnect(String childUid, {StreamMode? mode, required bool isChild}) {
    if (_disposed || _reconnectAttempts >= _maxReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * _reconnectAttempts); // exp backoff
    debugPrint('[WebRTC] Reconnect #$_reconnectAttempts in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      if (isChild && mode != null) {
        await startAsChild(childUid: childUid, mode: mode);
      } else if (!isChild) {
        await startAsParent(childUid: childUid);
      }
    });
  }

  Future<MediaStream> _getStream(StreamMode mode) async {
    if (mode == StreamMode.camera) {
      return navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'environment', 'width': 640, 'height': 480, 'frameRate': 15},
        'audio': true,
      });
    } else {
      try {
        final result = await ScreenCaptureChannel.requestScreenCapture();
        if (!result) throw Exception('Screen capture not granted');
        return navigator.mediaDevices.getDisplayMedia({
          'video': {'frameRate': 15, 'width': 720},
          'audio': false,
        });
      } catch (e) {
        debugPrint('[WebRTC] Screen fallback to camera: $e');
        return navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
      }
    }
  }

  Future<void> _cancelSubs() async {
    await _offerSub?.cancel();
    await _answerSub?.cancel();
    await _candidateSub?.cancel();
    _offerSub = null;
    _answerSub = null;
    _candidateSub = null;
    _answerSet = false;
  }

  Future<void> _closePC() async {
    try { await _localStream?.dispose(); } catch (_) {}
    try { await _peerConnection?.close(); } catch (_) {}
    _localStream    = null;
    _peerConnection = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _cancelSubs();
    await _closePC();
    try { localRenderer.dispose(); }  catch (_) {}
    try { remoteRenderer.dispose(); } catch (_) {}
    _initialized = false;
  }

  Future<void> sendFlipCommand(String childUid) async {
    await _db.child('calls/$childUid/command').set('flip');
  }

  Future<void> sendMuteCommand(String childUid, bool mute) async {
    await _db.child('calls/$childUid/command').set(mute ? 'mute' : 'unmute');
  }

  Future<void> endCall(String childUid) async {
    await _db.child('calls/$childUid/status').set('ended');
  }

  Future<void> startScreenShareAsChild(String childUid, VoidCallback onEnded) async {
    await startAsChild(childUid: childUid, mode: StreamMode.screen);
  }

  Future<void> startSilentScreen(String roomId, String userId, {bool audioEnabled = false}) async {}
}
