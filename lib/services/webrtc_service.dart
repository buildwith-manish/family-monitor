import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';
import 'screen_capture_channel.dart';

enum StreamMode { camera, screen }

/// WebRTC signalling service backed by Firebase Realtime Database.
///
/// Firebase path layout for a session keyed on [childUid]:
///   calls/{childUid}/offer          – parent's SDP offer
///   calls/{childUid}/answer         – child's SDP answer
///   calls/{childUid}/parentCandidates/{auto-id} – parent ICE candidates
///   calls/{childUid}/childCandidates/{auto-id}  – child ICE candidates
///   calls/{childUid}/status         – "calling" | "ended"
///   calls/{childUid}/mode           – "camera" | "screen"
///   calls/{childUid}/command        – "flip" | "mute" | "unmute"
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final RTCVideoRenderer localRenderer  = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final _db = FirebaseDatabase.instance.ref();

  StreamSubscription? _offerSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _commandSub;

  bool _initialized = false;
  bool _answerSet   = false;

  // Three Google STUN servers for NAT traversal
  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ── Renderer init ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _initialized = true;
  }

  // ── CHILD: camera stream ──────────────────────────────────────────────────────

  /// Opens the front camera + mic and responds to the parent's offer.
  Future<void> startAsChild(
      String childUid, VoidCallback onCallEnded) async {
    await initialize();
    _peerConnection = await createPeerConnection(_iceConfig);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      'audio': true,
    });
    localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/childCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    // Listen for the parent's offer (re-fires on reconnect)
    _offerSub =
        _db.child('calls/$childUid/offer').onValue.listen((e) async {
      if (e.snapshot.value == null || _peerConnection == null) return;
      try {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(d['sdp'], d['type']));
        final ans = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(ans);
        await _db
            .child('calls/$childUid/answer')
            .set({'sdp': ans.sdp, 'type': ans.type});
      } catch (ex) {
        debugPrint('[WebRTC] answer error: $ex');
      }
    });

    _candidateSub = _db
        .child('calls/$childUid/parentCandidates')
        .onChildAdded
        .listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(RTCIceCandidate(
            c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
      } catch (_) {}
    });

    // Listen for flip / mute commands from parent
    _commandSub =
        _db.child('calls/$childUid/command').onValue.listen((e) async {
      final cmd = e.snapshot.value as String?;
      if (cmd == 'flip') await switchCamera();
      if (cmd == 'mute') _setAudioEnabled(false);
      if (cmd == 'unmute') _setAudioEnabled(true);
    });

    _statusSub =
        _db.child('calls/$childUid/status').onValue.listen((e) {
      if (e.snapshot.value == 'ended') onCallEnded();
    });
  }

  // ── CHILD: screen stream ──────────────────────────────────────────────────────

  /// Starts a screen-share session as the child device.
  ///
  /// The setup wizard (or [ChildStreamingScreen]) must have already called
  /// [ScreenCaptureChannel.requestScreenCapture()] so [ScreenCaptureService]
  /// is running and holds a valid MediaProjection token.
  ///
  /// flutter_webrtc's `getDisplayMedia()` internally picks up that token via
  /// the Android plugin bridge.
  Future<void> startScreenShareAsChild(
      String childUid, VoidCallback onCallEnded) async {
    await initialize();
    _peerConnection = await createPeerConnection(_iceConfig);

    try {
      // getDisplayMedia() triggers the MediaProjection flow on Android.
      // Because ScreenCaptureService is already running the token is valid.
      _localStream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': true, // captures system audio where Android permits it
      });
    } catch (e) {
      debugPrint('[WebRTC] getDisplayMedia failed ($e), falling back to camera');
      _localStream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': true,
      });
    }

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/childCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    _offerSub =
        _db.child('calls/$childUid/offer').onValue.listen((e) async {
      if (e.snapshot.value == null || _peerConnection == null) return;
      try {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(d['sdp'], d['type']));
        final ans = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(ans);
        await _db
            .child('calls/$childUid/answer')
            .set({'sdp': ans.sdp, 'type': ans.type});
      } catch (ex) {
        debugPrint('[WebRTC] screen-share answer error: $ex');
      }
    });

    _candidateSub = _db
        .child('calls/$childUid/parentCandidates')
        .onChildAdded
        .listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(RTCIceCandidate(
            c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
      } catch (_) {}
    });

    _statusSub =
        _db.child('calls/$childUid/status').onValue.listen((e) {
      if (e.snapshot.value == 'ended') {
        ScreenCaptureChannel.stopScreenCaptureService();
        onCallEnded();
      }
    });
  }

  // ── PARENT: create offer, receive child stream ────────────────────────────────

  Future<void> startAsParent(String childUid, StreamMode mode,
      VoidCallback onStreamReady) async {
    await initialize();
    _answerSet     = false;
    _peerConnection = await createPeerConnection(_iceConfig);

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        onStreamReady();
      }
    };

    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/parentCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    final offer = await _peerConnection!
        .createOffer({'offerToReceiveVideo': true, 'offerToReceiveAudio': true});
    await _peerConnection!.setLocalDescription(offer);
    await _db.child('calls/$childUid').set({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'status': 'calling',
      'mode': mode == StreamMode.screen ? 'screen' : 'camera',
    });

    _answerSub =
        _db.child('calls/$childUid/answer').onValue.listen((e) async {
      if (e.snapshot.value == null || _answerSet) return;
      try {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (_peerConnection?.signalingState !=
            RTCSignalingState.RTCSignalingStateStable) {
          await _peerConnection!
              .setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          _answerSet = true;
        }
      } catch (ex) {
        debugPrint('[WebRTC] remote desc error: $ex');
      }
    });

    _candidateSub = _db
        .child('calls/$childUid/childCandidates')
        .onChildAdded
        .listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(RTCIceCandidate(
            c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
      } catch (_) {}
    });
  }

  // ── Remote commands (parent → child) ─────────────────────────────────────────

  Future<void> sendFlipCommand(String childUid) async {
    await _db.child('calls/$childUid/command').set('flip');
    await Future.delayed(const Duration(milliseconds: 500));
    await _db.child('calls/$childUid/command').remove();
  }

  Future<void> sendMuteCommand(String childUid, bool mute) async {
    await _db
        .child('calls/$childUid/command')
        .set(mute ? 'mute' : 'unmute');
  }

  // ── Local helpers ─────────────────────────────────────────────────────────────

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  void _setAudioEnabled(bool enabled) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = enabled);
  }

  // ── Session teardown ──────────────────────────────────────────────────────────

  Future<void> endCall(String childUid) async {
    await _db.child('calls/$childUid/status').set('ended');
    await Future.delayed(const Duration(milliseconds: 300));
    await _db.child('calls/$childUid').remove();
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _offerSub?.cancel();
    _answerSub?.cancel();
    _candidateSub?.cancel();
    _statusSub?.cancel();
    _commandSub?.cancel();
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _peerConnection?.close();
    _localStream    = null;
    _peerConnection = null;
  }

  void dispose() {
    _cleanup();
    if (_initialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
      _initialized = false;
    }
  }
}
