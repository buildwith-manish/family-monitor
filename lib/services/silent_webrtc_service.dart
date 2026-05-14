// ignore_for_file: unused_field
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
import 'screen_capture_channel.dart';
import 'turn_config_service.dart';

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

  // After this many consecutive failed reconnects we treat the parent as gone
  // and stop the camera rather than retrying indefinitely. This prevents the
  // camera staying on forever when the parent app is killed without calling
  // endCall (e.g. OS force-stop, crash).
  static const int _maxReconnectAttempts = 8;

  DateTime? _lastReconnectTime;

  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _heartbeatTimer;
  Timer? _connectionTimer;

  DateTime? _lastIceActivity;

  // SEC-01 / WEB-03: ICE configuration loaded at runtime from TurnConfigService.
  // TURN credentials are never baked into the APK — they are read from Firebase
  // at `config/turnServers`. iceCandidatePoolSize is 0 (was 10).
  Future<Map<String, dynamic>> _getIce() =>
      TurnConfigService.instance.getIceConfig();

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

      _pc = await createPeerConnection(await _getIce());

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
          // Flip only makes sense for camera mode — screen capture has no camera to switch.
          if (_activeMode == 'camera') {
            final tracks = _localStream?.getVideoTracks() ?? [];

            if (tracks.isNotEmpty) {
              try {
                await Helper.switchCamera(tracks.first);
              } catch (_) {}
            }
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
      // Screen mode: use MediaProjection/getDisplayMedia — NEVER fall back to camera.
      try {
        final projectionActive =
            await ScreenCaptureChannel.isProjectionActive();

        if (!projectionActive) {
          debugPrint(
            '[SilentWebRTC] No active MediaProjection token — screen share requires foreground permission grant first',
          );

          if (_activeUid != null) {
            try {
              await FirebaseDatabase.instance
                  .ref('calls/$_activeUid/screenError')
                  .set(
                    'Screen sharing requires the child app to be open. Open the child app and grant screen permission.',
                  );
            } catch (_) {}
          }

          return null;
        }

        debugPrint('[SilentWebRTC] MediaProjection active — calling getDisplayMedia');

        final stream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'frameRate': {'ideal': 15, 'max': 30},
            'width': {'ideal': 1280},
            'height': {'ideal': 720},
          },
          'audio': false,
        });

        debugPrint('[SilentWebRTC] getDisplayMedia succeeded — screen tracks: ${stream.getVideoTracks().length}');

        return stream;
      } catch (e) {
        debugPrint('[SilentWebRTC] Screen capture failed: $e');

        if (_activeUid != null) {
          try {
            await FirebaseDatabase.instance
                .ref('calls/$_activeUid/screenError')
                .set(
                  'Screen capture failed — open the child app and grant screen permission again.',
                );
          } catch (_) {}
        }

        // Do NOT fall back to camera. Return null so the caller stops cleanly.
        return null;
      }
    }

    // Camera mode — completely separate path, no cross-contamination.
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
    if (!_active) return;

    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    // If the parent has been unreachable for too many consecutive attempts,
    // treat the session as orphaned (parent crashed / was force-killed without
    // calling endCall) and release the camera. This prevents the camera from
    // running indefinitely in the background with no viewer.
    if (_reconnectAttempts > _maxReconnectAttempts) {
      debugPrint(
        '[SilentWebRTC] Max reconnect attempts reached — stopping orphan session',
      );
      // WEB-04: Notify the parent that the monitoring session was lost so
      // they know to re-initiate rather than staring at a frozen stream.
      final uid = _activeUid;
      if (uid != null) {
        FirebaseDatabase.instance
            .ref('calls/$uid/screenError')
            .set(
              'Monitoring connection lost — open the parent app and tap View again.',
            )
            .catchError((_) {});
      }
      stopSilent();
      return;
    }

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

    // FIX-17: Reduce poll interval 30→20 s and stale-ICE threshold 60→45 s
    // so orphaned connections are detected and reconnected ~33% faster.
    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) async {
        if (!_active) {
          _watchdogTimer?.cancel();
          return;
        }

        if (_lastIceActivity != null &&
            DateTime.now().difference(_lastIceActivity!) >
                const Duration(seconds: 45)) {
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
