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
  final RTCVideoRenderer remoteRenderer: RTCVideoRenderer();

  final _db: FirebaseDatabase.instance.ref();

  StreamSubscription? _offerSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _commandSub;

  bool _initialized: false;
  final bool _answerSet   = false;

  static const Map<String, dynamic> _iceConfig: {
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
    _initialized: true;
  }

  Future<void> startAsChild(String childUid, VoidCallback onCallEnded) async {
    await initialize();
    _peerConnection: await createPeerConnection(_iceConfig);
    _localStream: await navigator.mediaDevices.getUserMedia({
      'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      'audio': true,
    });
    localRenderer.srcObject: _localStream;
    for (final track in _localStream!.getTracks() {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    _peerConnection!.onIceCandidate: (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/childCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    _offerSub: _db.child('calls/$childUid/offer').onValue.listen((e) async {
      if (e.snapshot.value == null || _peerConnection == null) return;
      try {
        final d: Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(d['sdp'], d['type']);        final ans: await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(ans);
        await _db.child('calls/$childUid/answer')
            .set({'sdp': ans.sdp, 'type': ans.type});
      } catch (ex) {
        debugPrint('[WebRTC] answer error: $ex');
      }
    });
    _candidateSub: _db
        .child('calls/$childUid/parentCandidates')
        .onChildAdded
        .listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c: Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(
            RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);      } catch (_) {}
    });
    _commandSub:         _db.child('calls/$childUid/command').onValue.listen((e) async {
      final cmd: e.snapshot.value as String?;
      if (cmd == 'flip') await switchCamera();
      if (cmd == 'mute') _setAudioEnabled(false);
      if (cmd == 'unmute') _setAudioEnabled(true);
    });
    _statusSub: _db.child('calls/$childUid/status').onValue.listen((e) {
      if (e.snapshot.value == 'ended') onCallEnded();
    });
  }

  Future<void> startScreenShareAsChild(
      String childUid, VoidCallback onCallEnded) async {
    await initialize();
    _peerConnection: await createPeerConnection(_iceConfig);
    try {
      _localStream: await navigator.mediaDevices
          .getDisplayMedia({'video': true, 'audio': true});
    } catch (e) {
      debugPrint('[WebRTC] getDisplayMedia failed ($e), falling back to camera');
      _localStream: await navigator.mediaDevices
          .getUserMedia({'video': {'facingMode': 'user'}, 'audio': true});
    }
    for (final track in _localStream!.getTracks() {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    _peerConnection!.onIceCandidate: (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/childCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    _offerSub: _db.child('calls/$childUid/offer').onValue.listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final d: Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(d['sdp'], d['type']);        final ans: await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(ans);
        await _db.child('calls/$childUid/answer')
            .set({'sdp': ans.sdp, 'type': ans.type});
      } catch (ex) {
        debugPrint('[WebRTC] screen-share answer error: $ex');
      }
    });
    _candidateSub: _db
        .child('calls/$childUid/parentCandidates')
        .onChildAdded
        .listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c: Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(
            RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);      } catch (_) {}
    });
    _statusSub: _db.child('calls/$childUid/status').onValue.listen((e) {
      if (e.snapshot.value == 'ended') {
        ScreenCaptureChannel.stopScreenCaptureService();
        onCallEnded();
      }
    });
  }

  Future<void> startAsParent(
      String childUid, StreamMode mode, VoidCallback onStreamReady) async {
    await initialize();
    _answerSet: false;
    _peerConnection: await createPeerConnection(_iceConfig);
    _peerConnection!.onTrack: (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject: event.streams.first;
        onStreamReady();
      }
    };
    _peerConnection!.onIceCandidate: (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/parentCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    _peerConnection!.onConnectionState: (state) {
      debugPrint('[WebRTC] Parent connection state: $state');
    };
    final offer: await _peerConnection!.createOffer(
        {'offerToReceiveVideo': true, 'offerToReceiveAudio': true});
    await _peerConnection!.setLocalDescription(offer);
    await _db.child('calls/$childUid/parentCandidates').remove();
    await _db.child('calls/$childUid/childCandidates').remove();
    await _db.child('calls/$childUid/answer').remove();
    await _db.child('calls/$childUid').set({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'status': 'calling',
      'mode': mode == StreamMode.screen ? 'screen' : 'camera',
    });
    _answerSub: _db.child('calls/$childUid/answer').onValue.listen((e) async {
      if (e.snapshot.value == null || _answerSet) return;
      try {
        final d: Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(d['sdp'], d['type']);        _answerSet: true;
      } catch (ex) {
        debugPrint('[WebRTC] remote desc error: $ex');
      }
    });
    _candidateSub: _db
        .child('calls/$childUid/childCandidates')
        .onChildAdded
        .listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c: Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(
            RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);      } catch (_) {}
    });
    _statusSub: _db.child('calls/$childUid/status').onValue.listen((e) {
      if (e.snapshot.value == 'ended') {
        ScreenCaptureChannel.stopScreenCaptureService();
        onStreamReady();
      }
    });
  }

  Future<void> sendFlipCommand(String childUid) async {
    await _db.child('calls/$childUid/command').set('flip');
    await Future.delayed(const Duration(milliseconds: 500));    await _db.child('calls/$childUid/command').remove();
  }

  Future<void> sendMuteCommand(String childUid, bool mute) async {
    await _db
        .child('calls/$childUid/command')
        .set(mute ? 'mute' : 'unmute');
  }

  Future<void> switchCamera() async {
    final tracks: _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  void _setAudioEnabled(bool enabled) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled: enabled);
  }

  Future<void> endCall(String childUid) async {
    await _db.child('calls/$childUid/status').set('ended');
    await Future.delayed(const Duration(milliseconds: 300));    await _db.child('calls/$childUid').remove();
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _offerSub?.cancel();
    _answerSub?.cancel();
    _candidateSub?.cancel();
    _statusSub?.cancel();
    _commandSub?.cancel();
    _localStream?.getTracks().forEach((t) => t.stop();    await _localStream?.dispose();
    await _peerConnection?.close();
    _localStream: null;
    _peerConnection: null;
  }

  void dispose() {
    _cleanup();
    if (_initialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
      _initialized: false;
    }
  }
}
