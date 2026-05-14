// =============================================================================
// ANDROID PRIVACY INDICATOR NOTICE
// On Android 12+ (API 31+) the system displays a green camera/microphone dot
// in the status bar whenever any app accesses those sensors, even with no
// visible UI. This behaviour is intentional and CANNOT be suppressed — doing
// so would violate Google Play Developer Policy (section 4.8 / Deceptive
// Behaviour). Do NOT attempt to hide or work around the privacy indicator.
// Parents should be informed that the device will show this indicator during
// active monitoring sessions; "completely invisible" monitoring is not
// achievable on Android 12+ and must not be advertised as such.
// =============================================================================
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SilentWebRTCService {
  static SilentWebRTCService? _instance;

  static SilentWebRTCService get instance =>
      _instance ??= SilentWebRTCService._();

  SilentWebRTCService._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  bool _active = false;
  bool _connecting = false;
  int _activeStreams = 0;

  String? _activeUid;
  String? _activeMode;

  StreamSubscription? _offerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _commandSub;
  StreamSubscription? _connectivitySub;

  bool _answerSet = false;
  bool _handlingOffer = false;

  int _reconnectAttempts = 0;

  DateTime? _lastReconnectTime;

  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _heartbeatTimer;
  Timer? _connectionTimer;

  DateTime? _lastIceActivity;

  static const _ice = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ],
      },
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };

  bool get isActive => _active;

  Future<void> startSilentCamera(String childUid) async {
    if (_active && _activeUid == childUid && _activeMode == 'camera') {
      return;
    }

    await stopSilent();

    _activeMode = 'camera';

    await _startStream(childUid);
  }

  Future<void> startSilentScreen(String childUid) async {
    if (_active && _activeUid == childUid && _activeMode == 'screen') {
      return;
    }

    await stopSilent();

    _activeMode = 'screen';

    await _startStream(childUid);
  }

  Future<void> _startStream(String childUid) async {
    _active = true;
    _activeUid = childUid;
    _answerSet = false;
    _reconnectAttempts = 0;

    _subscribeConnectivity(childUid);

    _activeStreams++;
    if (_activeStreams == 1) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }

    await _connect(childUid);
  }

  Future<void> _connect(String childUid) async {
    if (_connecting) return;

    _connecting = true;
    _handlingOffer = true;

    try {
      await _cleanupPcOnly();

      _pc = await createPeerConnection(_ice);

      _lastIceActivity = DateTime.now();

      _pc!.onIceConnectionState = (state) {
        debugPrint('[SilentWebRTC] ICE: $state');

        _lastIceActivity = DateTime.now();

        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _reconnectAttempts = 0;
          _connectionTimer?.cancel();
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          try {
            _pc?.restartIce();
          } catch (_) {}

          _scheduleReconnect(childUid);
        }
      };

      _pc!.onConnectionState = (state) {
        debugPrint('[SilentWebRTC] Connection: $state');

        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _reconnectAttempts = 0;
            _connectionTimer?.cancel();
            break;

          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            if (_active) {
              _scheduleReconnect(childUid);
            }
            break;

          default:
            break;
        }
      };

      _localStream = await _acquireMedia();

      if (_localStream == null || !_active) {
        _connecting = false;
        return;
      }

      final tracks = _localStream!.getTracks();

      if (tracks.isEmpty) {
        debugPrint('[SilentWebRTC] No tracks found');

        _active = false;
        _connecting = false;

        return;
      }

      for (final track in tracks) {
        await _pc!.addTrack(track, _localStream!);

        track.onEnded = () {
          if (!_active) return;

          debugPrint('[SilentWebRTC] Track ended');

          _scheduleReconnect(childUid);
        };
      }

      final db = FirebaseDatabase.instance.ref();

      _pc!.onIceCandidate = (candidate) {
        if (!_active || candidate.candidate == null) return;

        db.child('calls/$childUid/childCandidates').push().set({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      await db.child('calls/$childUid/offer').remove();
      await db.child('calls/$childUid/childCandidates').remove();

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await db.child('calls/$childUid/offer').set({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      debugPrint('[SilentWebRTC] Offer sent');

      _handlingOffer = false;
      _offerSub =
          db.child('calls/$childUid/answer').onValue.listen((event) async {
        if (!_active ||
            _pc == null ||
            _answerSet ||
            event.snapshot.value == null) {
          return;
        }

        try {
          final raw = event.snapshot.value;
          if (raw is! Map) return;
          final data = Map<String, dynamic>.from(raw);

          if (data['sdp'] == null) return;

          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              data['sdp'],
              data['type'],
            ),
          );

          _answerSet = true;

          debugPrint('[SilentWebRTC] Answer received and set');
        } catch (e) {
          debugPrint('[SilentWebRTC] Answer set error: $e');
        }
      });

      _candidateSub = db
          .child('calls/$childUid/parentCandidates')
          .onChildAdded
          .listen((event) async {
        if (!_active || _pc == null || event.snapshot.value == null) {
          return;
        }

        try {
          final rawCand = event.snapshot.value;
          if (rawCand is! Map) return;
          final candidate = Map<String, dynamic>.from(rawCand);

          await _pc!.addCandidate(
            RTCIceCandidate(
              candidate['candidate'],
              candidate['sdpMid'],
              candidate['sdpMLineIndex'],
            ),
          );
        } catch (e) {
          debugPrint('[SilentWebRTC] Candidate error: $e');
        }
      });

      _commandSub =
          db.child('calls/$childUid/command').onValue.listen((event) async {
        if (!_active) return;

        final command = event.snapshot.value is String ? event.snapshot.value as String : null;

        if (command == 'flip') {
          final tracks = _localStream?.getVideoTracks() ?? [];

          if (tracks.isNotEmpty) {
            try {
              await Helper.switchCamera(tracks.first);
            } catch (_) {}
          }
        } else if (command == 'mute') {
          for (final track in _localStream?.getAudioTracks() ?? []) {
            track.enabled = false;
          }
        } else if (command == 'unmute') {
          for (final track in _localStream?.getAudioTracks() ?? []) {
            track.enabled = true;
          }
        }
      });

      _statusSub =
          db.child('calls/$childUid/status').onValue.listen((event) async {
        final status = event.snapshot.value is String ? event.snapshot.value as String : null;

        if (status == 'ended' || status == null) {
          await stopSilent();
        }
      });

      _connectionTimer?.cancel();

      _connectionTimer = Timer(
        const Duration(seconds: 15),
        () {
          if (!_active) return;

          debugPrint(
            '[SilentWebRTC] Connection timeout — reconnecting',
          );

          _scheduleReconnect(childUid);
        },
      );

      _startWatchdog(childUid);

      _startHeartbeat(childUid, db);

      debugPrint(
        '[SilentWebRTC] Streaming started (mode: $_activeMode)',
      );
    } catch (e) {
      debugPrint('[SilentWebRTC] Connect error: $e');

      _scheduleReconnect(childUid);
    } finally {
      _connecting = false;
    }
  }

  Future<MediaStream?> _acquireMedia() async {
    if (_activeMode == 'screen') {
      debugPrint(
        '[SilentWebRTC] Screen capture unavailable in background — using camera fallback',
      );

      if (_activeUid != null) {
        try {
          await FirebaseDatabase.instance
              .ref('calls/$_activeUid/screenError')
              .set(
                'Screen sharing unavailable – showing camera instead',
              );
        } catch (_) {}
      }

      _activeMode = 'camera';
    }

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
      debugPrint(
        '[SilentWebRTC] Camera acquisition failed: $e',
      );

      return null;
    }
  }

  void _scheduleReconnect(String childUid) {
    if (!_active) return;

    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    final seconds = _reconnectAttempts > 5 ? 60 : (1 << _reconnectAttempts);

    final delay = Duration(seconds: seconds);

    debugPrint(
      '[SilentWebRTC] Reconnect #$_reconnectAttempts in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, () async {
      if (!_active) return;

      await _connect(childUid);
    });
  }

  void _startWatchdog(String childUid) {
    _watchdogTimer?.cancel();

    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        if (!_active) {
          _watchdogTimer?.cancel();
          return;
        }

        if (_lastIceActivity != null &&
            DateTime.now().difference(_lastIceActivity!) >
                const Duration(seconds: 60)) {
          debugPrint(
            '[SilentWebRTC] Watchdog detected stale ICE',
          );

          if (_activeUid != null) {
            _scheduleReconnect(_activeUid!);
          }
        }
      },
    );
  }

  void _startHeartbeat(
    String childUid,
    DatabaseReference db,
  ) {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        if (!_active) {
          _heartbeatTimer?.cancel();
          return;
        }

        try {
          await db
              .child('calls/$childUid/heartbeat')
              .set(ServerValue.timestamp);
        } catch (_) {}
      },
    );
  }

  Future<void> _cleanupPcOnly() async {
    await _offerSub?.cancel();
    await _candidateSub?.cancel();
    await _statusSub?.cancel();
    await _commandSub?.cancel();

    _offerSub = null;
    _candidateSub = null;
    _statusSub = null;
    _commandSub = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _connectionTimer?.cancel();
    _connectionTimer = null;

    _answerSet = false;

    try {
      for (final track in _localStream?.getTracks() ?? []) {
        await track.stop();
      }
    } catch (_) {}

    try {
      await _localStream?.dispose();
    } catch (_) {}

    _localStream = null;

    try {
      await _pc?.close();
    } catch (_) {}

    _pc = null;
  }

  Future<void> stopSilent() async {
    _active = false;

    _activeUid = null;
    _activeMode = null;

    _reconnectAttempts = 0;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    _connectionTimer?.cancel();
    _connectionTimer = null;

    if (_activeStreams > 0) _activeStreams--;
    if (_activeStreams == 0) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }

    await _cleanupPcOnly();

    debugPrint('[SilentWebRTC] Stopped');
  }

  void _subscribeConnectivity(String childUid) {
    _connectivitySub?.cancel();

    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final connected = results.any((r) => r != ConnectivityResult.none);

        if (!connected || !_active) {
          return;
        }

        final now = DateTime.now();

        if (_lastReconnectTime != null &&
            now.difference(_lastReconnectTime!).inSeconds < 10) {
          return;
        }

        debugPrint(
          '[SilentWebRTC] Connectivity restored — checking connection',
        );

        final pcState = _pc?.iceConnectionState;

        if (_pc == null ||
            pcState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            pcState ==
                RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _lastReconnectTime = now;

          _reconnectTimer?.cancel();

          await _connect(childUid);
        }
      },
    );
  }
}
