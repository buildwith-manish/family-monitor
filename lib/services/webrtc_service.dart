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
  bool _initialized = false, _answerSet = false;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  Future<void> initialize() async {
    if (_initialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _initialized = true;
  }

  Future<void> startAsChild({required String childUid, required StreamMode mode}) async {
    await initialize();
    _localStream = await _getStream(mode);
    localRenderer.srcObject = _localStream;
    _peerConnection = await createPeerConnection(_iceConfig);
    _localStream!.getTracks().forEach((t) => _peerConnection!.addTrack(t, _localStream!));
    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) _db.child('webrtc/\$childUid/childCandidates').push().set(c.toMap());
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) remoteRenderer.srcObject = event.streams[0];
    };
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _db.child('webrtc/\$childUid/offer').set({'sdp': offer.sdp, 'type': offer.type});
    _answerSub = _db.child('webrtc/\$childUid/answer').onValue.listen((e) async {
      if (_answerSet) return;
      final val = e.snapshot.value;
      if (val == null) return;
      final map = Map<String, dynamic>.from(val as Map);
      if (map['sdp'] == null) return;
      _answerSet = true;
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(map['sdp'], map['type']));
    });
    _candidateSub = _db.child('webrtc/\$childUid/parentCandidates').onChildAdded.listen((e) async {
      final val = e.snapshot.value;
      if (val == null) return;
      final map = Map<String, dynamic>.from(val as Map);
      await _peerConnection!.addCandidate(RTCIceCandidate(map['candidate'], map['sdpMid'], map['sdpMLineIndex']));
    });
  }

  Future<void> startAsParent({required String childUid}) async {
    await initialize();
    _peerConnection = await createPeerConnection(_iceConfig);
    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) _db.child('webrtc/\$childUid/parentCandidates').push().set(c.toMap());
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) remoteRenderer.srcObject = event.streams[0];
    };
    _offerSub = _db.child('webrtc/\$childUid/offer').onValue.listen((e) async {
      final val = e.snapshot.value;
      if (val == null) return;
      final map = Map<String, dynamic>.from(val as Map);
      if (map['sdp'] == null) return;
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(map['sdp'], map['type']));
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      await _db.child('webrtc/\$childUid/answer').set({'sdp': answer.sdp, 'type': answer.type});
    });
    _candidateSub = _db.child('webrtc/\$childUid/childCandidates').onChildAdded.listen((e) async {
      final val = e.snapshot.value;
      if (val == null) return;
      final map = Map<String, dynamic>.from(val as Map);
      await _peerConnection!.addCandidate(RTCIceCandidate(map['candidate'], map['sdpMid'], map['sdpMLineIndex']));
    });
  }

  Future<MediaStream> _getStream(StreamMode mode) async {
    if (mode == StreamMode.camera) {
      return navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
    } else {
      try {
        final granted = await ScreenCaptureChannel.requestScreenCapture();
        if (!granted) throw Exception('not granted');
        return navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
      } catch (e) {
        debugPrint('Screen fallback to camera: \$e');
        return navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
      }
    }
  }

  Future<void> dispose() async {
    await _offerSub?.cancel(); await _answerSub?.cancel(); await _candidateSub?.cancel();
    await _localStream?.dispose(); await _peerConnection?.close();
    localRenderer.dispose(); remoteRenderer.dispose();
    _initialized = false; _answerSet = false;
  }
  Future<void> sendFlipCommand(String childUid) async {}
  Future<void> sendMuteCommand(String childUid, bool mute) async {}
  Future<void> endCall(String childUid) async {}
  Future<void> startScreenShareAsChild(String childUid, VoidCallback onEnded) async {
    await startAsChild(childUid: childUid, mode: StreamMode.screen);
  }
  Future<void> startSilentScreen(String roomId, String userId, {bool audioEnabled = false}) async {
    // Delegate to existing implementation
    await initialize(roomId: roomId);
  }
  Future<void> startSilentScreen(String roomId, String userId, {bool audioEnabled = false}) async {
    try {
      await initialize(roomId);
    } catch (e) {
      debugPrint('startSilentScreen error: \$e');
    }
  }
}
