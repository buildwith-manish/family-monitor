import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'screen_capture_channel.dart';
import 'turn_config_service.dart';

enum StreamMode { camera, screen }

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  VoidCallback? onRemoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final _db = FirebaseDatabase.instance.ref();

  StreamSubscription? _offerSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _connectivitySub;

  bool _initialized = false;
  bool _answerSet = false;
  bool _disposed = false;

  int _reconnectAttempts = 0;

  Timer? _reconnectTimer;
  Timer? _connectionTimer;

  StreamMode? _lastMode;
  DateTime? _lastReconnectTime;

  // SEC-01 / WEB-03: ICE configuration is loaded at runtime from
  // TurnConfigService which reads TURN credentials from Firebase RTDB at
  // `config/turnServers`.  Credentials are never baked into the APK.
  // iceCandidatePoolSize is 0 (was 15) — pre-allocation wastes battery and
  // can expose the internal network topology unnecessarily.
  // See lib/services/turn_config_service.dart for setup instructions.
  Future<Map<String, dynamic>> _getIceConfig() =>
      TurnConfigService.instance.getIceConfig();

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

    _lastMode = mode;
    _reconnectAttempts = 0;

    _subscribeConnectivity(childUid: childUid, isChild: true, mode: mode);

    await initialize();
    await _cancelSubs();
    await _closePC();

    try {
      await _db.child('calls/$childUid/offer').remove();
      await _db.child('calls/$childUid/answer').remove();
      await _db.child('calls/$childUid/childCandidates').remove();

      _localStream = await _getStream(mode);

      if (_disposed) return;

      localRenderer.srcObject = _localStream;

      _peerConnection = await createPeerConnection(await _getIceConfig());

      _setupPCHandlers(
        childUid,
        isChild: true,
      );

      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);

        track.onEnded = () {
          if (_disposed) return;

          debugPrint('[WebRTC] Local track ended');

          _scheduleReconnect(
            childUid,
            mode: mode,
            isChild: true,
          );
        };
      }

      final offer = await _peerConnection!.createOffer();

      await _peerConnection!.setLocalDescription(offer);

      await _db.child('calls/$childUid/offer').set({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      _answerSub =
          _db.child('calls/$childUid/answer').onValue.listen((event) async {
        if (_disposed || _answerSet) return;

        final value = event.snapshot.value;

        if (value == null || value is! Map) return;

        final map = Map<String, dynamic>.from(value);

        if (map['sdp'] == null) return;

        _answerSet = true;

        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(
            map['sdp'],
            map['type'],
          ),
        );
      });

      _candidateSub = _db
          .child('calls/$childUid/parentCandidates')
          .onChildAdded
          .listen((event) async {
        if (_disposed) return;

        final value = event.snapshot.value;

        if (value == null || value is! Map) return;

        final map = Map<String, dynamic>.from(value);

        try {
          await _peerConnection?.addCandidate(
            RTCIceCandidate(
              map['candidate'],
              map['sdpMid'],
              map['sdpMLineIndex'],
            ),
          );
        } catch (e) {
          debugPrint('[WebRTC] addCandidate child error: $e');
        }
      });
    } catch (e) {
      debugPrint('[WebRTC] startAsChild error: $e');

      _scheduleReconnect(
        childUid,
        mode: mode,
        isChild: true,
      );
    }
  }

  Future<void> startAsParent({
    required String childUid,
    StreamMode mode = StreamMode.camera,
  }) async {
    if (_disposed) return;

    _lastMode = mode;
    _reconnectAttempts = 0;

    _subscribeConnectivity(childUid: childUid, isChild: false, mode: mode);

    await initialize();
    await _cancelSubs();
    await _closePC();

    try {
      await _db.child('calls/$childUid/offer').remove();
      await _db.child('calls/$childUid/answer').remove();
      await _db.child('calls/$childUid/parentCandidates').remove();
      await _db.child('calls/$childUid/childCandidates').remove();

      await _db.child('calls/$childUid/status').set('calling');
      await _db.child('calls/$childUid/mode').set(
        mode == StreamMode.screen ? 'screen' : 'camera',
      );

      _peerConnection = await createPeerConnection(await _getIceConfig());

      _setupPCHandlers(
        childUid,
        isChild: false,
      );

      _connectionTimer?.cancel();

      _connectionTimer = Timer(
        const Duration(seconds: 15),
        () {
          if (_disposed) return;

          debugPrint('[WebRTC] Connection timeout');

          _scheduleReconnect(
            childUid,
            mode: mode,
            isChild: false,
          );
        },
      );

      _offerSub =
          _db.child('calls/$childUid/offer').onValue.listen((event) async {
        if (_disposed) return;

        final value = event.snapshot.value;

        if (value == null || value is! Map) return;

        final map = Map<String, dynamic>.from(value);

        if (map['sdp'] == null) return;

        try {
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(
              map['sdp'],
              map['type'],
            ),
          );

          final answer = await _peerConnection!.createAnswer();

          await _peerConnection!.setLocalDescription(answer);

          await _db.child('calls/$childUid/answer').set({
            'sdp': answer.sdp,
            'type': answer.type,
          });
        } catch (e) {
          debugPrint('[WebRTC] answer error: $e');
        }
      });

      _candidateSub = _db
          .child('calls/$childUid/childCandidates')
          .onChildAdded
          .listen((event) async {
        if (_disposed) return;

        final value = event.snapshot.value;

        if (value == null || value is! Map) return;

        final map = Map<String, dynamic>.from(value);

        try {
          await _peerConnection?.addCandidate(
            RTCIceCandidate(
              map['candidate'],
              map['sdpMid'],
              map['sdpMLineIndex'],
            ),
          );
        } catch (e) {
          debugPrint('[WebRTC] addCandidate parent error: $e');
        }
      });
    } catch (e) {
      debugPrint('[WebRTC] startAsParent error: $e');

      _scheduleReconnect(
        childUid,
        mode: mode,
        isChild: false,
      );
    }
  }

  void _setupPCHandlers(
    String childUid, {
    required bool isChild,
  }) {
    _peerConnection?.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE State: $state');

      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _reconnectAttempts = 0;
        _connectionTimer?.cancel();
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        try {
          _peerConnection?.restartIce();
        } catch (_) {}

        _scheduleReconnect(
          childUid,
          mode: _lastMode,
          isChild: isChild,
        );
      }
    };

    _peerConnection?.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection State: $state');

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _reconnectAttempts = 0;
          _connectionTimer?.cancel();
          break;

        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (!_disposed) {
            _scheduleReconnect(
              childUid,
              mode: _lastMode,
              isChild: isChild,
            );
          }
          break;

        default:
          break;
      }
    };

    _peerConnection?.onIceCandidate = (candidate) {
      if (_disposed || candidate.candidate == null) return;

      final path = isChild
          ? 'calls/$childUid/childCandidates'
          : 'calls/$childUid/parentCandidates';

      _db.child(path).push().set(candidate.toMap());
    };

    _peerConnection?.onTrack = (event) async {
      // On some Android devices/flutter_webrtc builds, event.streams can be
      // empty even though the track is valid. We collect tracks manually into
      // our own MediaStream so the renderer always gets a valid source.
      MediaStream? stream;

      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        // Build or reuse a remote stream to hold arriving tracks.
        _remoteStream ??= await createLocalMediaStream('remote');
        stream = _remoteStream;
        try {
          await stream!.addTrack(event.track);
        } catch (_) {}
      }

      if (stream == null) return;

      // Deduplicate: remove any older track of the same kind.
      final existing = stream.getTracks();
      for (final t in existing) {
        if (t.kind == event.track.kind && t.id != event.track.id) {
          try {
            t.stop();
          } catch (_) {}
          try {
            await stream.removeTrack(t);
          } catch (_) {}
        }
      }

      remoteRenderer.srcObject = stream;
      _connectionTimer?.cancel();
      onRemoteStream?.call();
    };
  }

  void _scheduleReconnect(
    String childUid, {
    required bool isChild,
    StreamMode? mode,
  }) {
    if (_disposed) return;

    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    final seconds = _reconnectAttempts > 5 ? 60 : (1 << _reconnectAttempts);

    final delay = Duration(seconds: seconds);

    debugPrint(
      '[WebRTC] Reconnect #$_reconnectAttempts in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;

      if (isChild && mode != null) {
        await startAsChild(
          childUid: childUid,
          mode: mode,
        );
      } else if (!isChild) {
        await startAsParent(
          childUid: childUid,
          mode: mode ?? StreamMode.camera,
        );
      }
    });
  }

  Future<MediaStream> _getStream(StreamMode mode) async {
    if (mode == StreamMode.camera) {
      return navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'environment',
          'width': 640,
          'height': 480,
          'frameRate': 15,
        },
        'audio': true,
      });
    }

    try {
      final granted = await ScreenCaptureChannel.requestScreenCapture();

      if (!granted) {
        throw Exception('Screen capture permission denied');
      }

      return navigator.mediaDevices.getDisplayMedia({
        'video': {
          'frameRate': 15,
          'width': 720,
        },
        'audio': false,
      });
    } catch (e) {
      debugPrint('[WebRTC] Screen capture fallback: $e');

      return navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': true,
      });
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
    if (_initialized) {
      remoteRenderer.srcObject = null;
      localRenderer.srcObject = null;
    }

    try {
      for (final track in _localStream?.getTracks() ?? []) {
        await track.stop();
      }
    } catch (_) {}

    try {
      await _localStream?.dispose();
    } catch (_) {}

    try {
      for (final track in _remoteStream?.getTracks() ?? []) {
        await track.stop();
      }
    } catch (_) {}

    try {
      await _remoteStream?.dispose();
    } catch (_) {}

    try {
      await _peerConnection?.close();
    } catch (_) {}

    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
  }

  Future<void> dispose() async {
    _disposed = true;

    _reconnectTimer?.cancel();
    _connectionTimer?.cancel();

    _connectivitySub?.cancel();
    _connectivitySub = null;

    await _cancelSubs();
    await _closePC();

    try {
      await localRenderer.dispose();
    } catch (_) {}

    try {
      await remoteRenderer.dispose();
    } catch (_) {}

    _initialized = false;
  }

  Future<void> sendFlipCommand(String childUid) async {
    await _db.child('calls/$childUid/command').set('flip');
  }

  Future<void> sendMuteCommand(
    String childUid,
    bool mute,
  ) async {
    await _db.child('calls/$childUid/command').set(mute ? 'mute' : 'unmute');
  }

  Future<void> endCall(String childUid) async {
    await _db.child('calls/$childUid/status').set('ended');
  }

  Future<void> startScreenShareAsChild(
    String childUid,
    VoidCallback onEnded,
  ) async {
    await startAsChild(
      childUid: childUid,
      mode: StreamMode.screen,
    );
  }

  Future<void> startSilentScreen(
    String roomId,
    String userId, {
    bool audioEnabled = false,
  }) async {
    await startAsChild(
      childUid: userId,
      mode: StreamMode.screen,
    );
  }

  void _subscribeConnectivity({
    required String childUid,
    required bool isChild,
    required StreamMode mode,
  }) {
    _connectivitySub?.cancel();

    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final connected = results.any((r) => r != ConnectivityResult.none);

        if (!connected || _disposed) {
          return;
        }

        final now = DateTime.now();

        if (_lastReconnectTime != null &&
            now.difference(_lastReconnectTime!).inSeconds < 10) {
          return;
        }

        debugPrint(
          '[WebRTC] Connectivity restored — checking connection',
        );

        final pcState = _peerConnection?.iceConnectionState;

        if (_peerConnection == null ||
            pcState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            pcState ==
                RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _lastReconnectTime = now;

          _reconnectTimer?.cancel();

          if (isChild) {
            await startAsChild(
              childUid: childUid,
              mode: mode,
            );
          } else {
            await startAsParent(
              childUid: childUid,
              mode: mode,
            );
          }
        }
      },
    );
  }
}
