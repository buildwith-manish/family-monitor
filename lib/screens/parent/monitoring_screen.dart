import '../../services/webrtc_service.dart';
import '../../services/stream_mode.dart';
import '../../services/stream_viewer_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MonitoringScreen extends StatefulWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  final StreamMode mode;

  const MonitoringScreen({
    super.key,
    required this.childUid,
    required this.childData,
    this.mode = StreamMode.camera,
  });

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final _webrtc = WebRTCService();
  bool _hasStream = false;
  bool _isMuted = true;
  bool _showControls = true;
  String _status = 'Connecting...';
  bool _isChildOnline = false;
  bool _isRetrying = false; // BUG-2 FIX: Track retry state
  Timer? _timeout;
  Timer? _controlsTimer;
  StreamSubscription? _statusSub;
  StreamSubscription? _heartbeatSub;
  StreamSubscription? _screenErrorSub;

  // BUG-2-FIX: Native capture mode — when flutter_webrtc's getDisplayMedia()
  // fails (e.g. on Android 14+), the child device falls back to native frame
  // capture using VirtualDisplay + ImageReader. Frames are relayed via Firebase
  // RTDB as base64 strings. The parent side detects this and displays frames
  // instead of waiting for a WebRTC stream.
  bool _nativeCaptureMode = false;
  Uint8List? _currentFrame;
  StreamSubscription? _nativeCaptureSub;
  StreamSubscription? _nativeCaptureModeSub;

  // STREAM-01: WebSocket stream viewer — low-latency binary frame streaming.
  // When the child's ScreenStreamService pushes frames over WebSocket to the
  // relay server, the parent connects via StreamViewerService to receive frames.
  // This is much faster than Firebase RTDB base64 relay (10+ FPS vs 3 FPS).
  StreamViewerService? _streamViewer;
  StreamSubscription? _wsFrameSub;
  StreamSubscription? _wsConnStateSub;
  bool _wsStreamMode = false;
  double _streamFps = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _webrtc.onRemoteStream = () {
      if (!mounted) return;
      setState(() {
        _hasStream = true;
        _status = 'Connected';
      });
      _timeout?.cancel();
      _startControlsTimer();
      // Enforce muted-by-default: send the mute command as soon as the
      // stream connects so the child's mic is silenced from the first frame.
      _webrtc.sendMuteCommand(widget.childUid, true).catchError((_) {});
    };
    _startMonitoring();
    _listenToPresence();
    // BUG-2 FIX: Use a shorter timeout for screen mode since the parent
    // needs feedback faster. Screen capture consent may need to be granted
    // on the child device, and the parent should see actionable feedback
    // within 15 seconds.
    _timeout = Timer(Duration(seconds: widget.mode == StreamMode.screen ? 15 : 30), () {
      if (mounted && !_hasStream && !_nativeCaptureMode) {
        setState(() {
          _isRetrying = false;
          _status = widget.mode == StreamMode.screen
              ? 'Screen share not available yet.\nMake sure the child app is open and screen permission is granted.\nTap Retry to try again.'
              : 'Waiting for child device...\nMake sure the child app is open and camera permission has been granted.';
        });
      }
    });
  }

  void _listenToPresence() {
    final db = FirebaseDatabase.instance.ref();

    _statusSub = db
        .child('calls/${widget.childUid}/status')
        .onValue
        .listen((e) {
      if (!mounted) return;
      final status = e.snapshot.value is String ? e.snapshot.value as String : null;
      setState(() {
        _isChildOnline = status == 'online' ||
            status == 'calling' ||
            status == 'streaming';
      });
    });

    _heartbeatSub = db
        .child('calls/${widget.childUid}/heartbeat')
        .onValue
        .listen((e) {
      if (!mounted) return;
      final ts = e.snapshot.value;
      if (ts is int) {
        final stale = DateTime.now().millisecondsSinceEpoch - ts > 30000;
        setState(() {
          _isChildOnline = !stale;
        });
      }
    });

    // BUG-2-FIX: Listen for screen errors from the child device so the
    // parent sees actionable feedback when screen capture can't start.
    _screenErrorSub = db
        .child('calls/${widget.childUid}/screenError')
        .onValue
        .listen((e) {
      if (!mounted) return;
      final error = e.snapshot.value is String ? e.snapshot.value as String : null;
      if (error != null && !_hasStream && !_nativeCaptureMode) {
        setState(() {
          _status = error;
        });
      }
    });

    // BUG-2-FIX: Listen for native capture mode signal from child device.
    // When the child's flutter_webrtc can't acquire a MediaStream (e.g. on
    // Android 14+ due to Intent URI serialization losing the Binder extra),
    // it falls back to native VirtualDisplay + ImageReader capture and sets
    // nativeCaptureMode=true. We listen for this and start displaying frames.
    _nativeCaptureModeSub = db
        .child('calls/${widget.childUid}/nativeCaptureMode')
        .onValue
        .listen((e) {
      if (!mounted) return;
      final isNativeMode = e.snapshot.value == true;
      if (isNativeMode && !_nativeCaptureMode) {
        debugPrint('[MonitoringScreen] Native capture mode detected — switching to frame display');
        setState(() {
          _nativeCaptureMode = true;
          _status = 'Receiving screen frames...';
        });
        _timeout?.cancel();

        // STREAM-01: If WebSocket relay is configured, use it for low-latency frames.
        // Otherwise, fall back to Firebase RTDB base64 relay.
        _tryStartWebSocketViewer().then((started) {
          if (!started) {
            _startNativeFrameListener();
          }
        });
      } else if (!isNativeMode && _nativeCaptureMode) {
        debugPrint('[MonitoringScreen] Native capture mode ended');
        setState(() {
          _nativeCaptureMode = false;
        });
        _nativeCaptureSub?.cancel();
        _nativeCaptureSub = null;
      }
    });

    // STREAM-01: Listen for WebSocket stream mode signal from child device.
    // When the child's ScreenStreamService pushes frames over WebSocket,
    // it sets wsStreamMode=true. We connect the StreamViewerService.
    db.child('calls/${widget.childUid}/wsStreamMode')
        .onValue
        .listen((e) {
      if (!mounted) return;
      final isWsMode = e.snapshot.value == true;
      if (isWsMode && !_wsStreamMode) {
        debugPrint('[MonitoringScreen] WebSocket stream mode detected');
        setState(() {
          _wsStreamMode = true;
          _nativeCaptureMode = true;
          _status = 'Live stream connected';
        });
        _timeout?.cancel();
        _tryStartWebSocketViewer();
      } else if (!isWsMode && _wsStreamMode) {
        debugPrint('[MonitoringScreen] WebSocket stream mode ended');
        setState(() {
          _wsStreamMode = false;
        });
        _stopWebSocketViewer();
      }
    });
  }

  /// BUG-2-FIX: Listen for screen frames relayed via Firebase RTDB.
  /// Frames are base64-encoded JPEG images written by the child device's
  /// native VirtualDisplay + ImageReader capture pipeline.
  void _startNativeFrameListener() {
    _nativeCaptureSub?.cancel();
    _nativeCaptureSub = FirebaseDatabase.instance
        .ref('calls/${widget.childUid}/screenFrame')
        .onValue
        .listen((e) {
      if (!mounted || !_nativeCaptureMode) return;

      final value = e.snapshot.value;
      if (value is! Map) return;

      final data = Map<String, dynamic>.from(value);
      final base64Str = data['data'] as String?;
      if (base64Str == null) return;

      try {
        final frameBytes = base64Decode(base64Str);
        setState(() {
          _currentFrame = frameBytes;
          if (_status != 'Connected') {
            _status = 'Connected';
          }
        });
      } catch (err) {
        debugPrint('[MonitoringScreen] Frame decode error: $err');
      }
    });
  }

  // ── STREAM-01: WebSocket stream viewer methods ────────────────────────

  /// Try to start the WebSocket stream viewer for low-latency frame display.
  /// Returns true if the viewer was started, false if no relay URL is configured.
  Future<bool> _tryStartWebSocketViewer() async {
    try {
      var prefs = await SharedPreferences.getInstance();
      var relayUrl = prefs.getString('stream_relay_url');

      // STREAM-FIX: If relay URL is empty/null or is a Firebase RTDB URL,
      // don't attempt WebSocket — use RTDB frame relay instead.
      if (relayUrl == null ||
          relayUrl.isEmpty ||
          relayUrl.contains('firebaseio.com')) {
        debugPrint('[MonitoringScreen] No WebSocket relay — using RTDB frame mode');
        return false;
      }

      // STREAM-RELAY-URL: Fallback — try reading the relay URL from the
      // child's Firebase data if not configured locally on the parent device.
      if (relayUrl == null || relayUrl.isEmpty) {
        try {
          final snap = await FirebaseDatabase.instance
              .ref('users/${widget.childUid}/streamRelayUrl')
              .get()
              .timeout(const Duration(seconds: 5));
          if (snap.value is String && (snap.value as String).isNotEmpty) {
            relayUrl = snap.value as String;
            debugPrint('[MonitoringScreen] Using relay URL from Firebase: $relayUrl');
            // Cache it locally for next time
            try {
              await prefs.setString('stream_relay_url', relayUrl);
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('[MonitoringScreen] Firebase relay URL lookup failed: $e');
        }
      }

      if (relayUrl == null || relayUrl.isEmpty) {
        debugPrint('[MonitoringScreen] No WebSocket relay URL configured — using Firebase relay');
        return false;
      }

      debugPrint('[MonitoringScreen] Starting WebSocket viewer at $relayUrl');
      _stopWebSocketViewer(); // Clean up any existing viewer

      _streamViewer = StreamViewerService(relayUrl: relayUrl);

      // Listen for connection state changes
      _wsConnStateSub = _streamViewer!.connectionState.listen((state) {
        if (!mounted) return;
        debugPrint('[MonitoringScreen] WebSocket state: $state');
        switch (state) {
          case StreamConnectionState.connected:
            setState(() {
              _status = 'Live stream connected';
            });
            break;
          case StreamConnectionState.childOffline:
            setState(() {
              _status = 'Child device disconnected from stream';
            });
            break;
          case StreamConnectionState.error:
            setState(() {
              _status = 'Stream connection error. Tap Retry.';
            });
            break;
          case StreamConnectionState.connecting:
            setState(() {
              _status = 'Connecting to stream...';
            });
            break;
          case StreamConnectionState.disconnected:
            break;
        }
      });

      // Listen for frames
      _wsFrameSub = _streamViewer!.frameStream.listen((frameBytes) {
        if (!mounted) return;
        setState(() {
          _currentFrame = frameBytes;
          _streamFps = _streamViewer?.currentFps ?? 0;
          if (_status != 'Connected') {
            _status = 'Connected';
          }
        });
      });

      await _streamViewer!.connect(widget.childUid);
      return true;
    } catch (e) {
      debugPrint('[MonitoringScreen] WebSocket viewer start error: $e');
      return false;
    }
  }

  /// Stop the WebSocket stream viewer.
  void _stopWebSocketViewer() {
    _wsFrameSub?.cancel();
    _wsFrameSub = null;
    _wsConnStateSub?.cancel();
    _wsConnStateSub = null;
    _streamViewer?.disconnect();
    _streamViewer = null;
  }

  Future<void> _startMonitoring() async {
    try {
      // Clear any stale screenError from a previous session so it doesn't
      // bleed into this new session as a false-positive banner.
      await FirebaseDatabase.instance
          .ref('calls/${widget.childUid}/screenError')
          .remove();
      // BUG-2-FIX: Clear stale native capture mode flag
      await FirebaseDatabase.instance
          .ref('calls/${widget.childUid}/nativeCaptureMode')
          .remove();
      await FirebaseDatabase.instance
          .ref('calls/${widget.childUid}/screenFrame')
          .remove();
      // BUG-2/BUG-3 FIX: Clear stale needsConsent and projectionReady flags
      await FirebaseDatabase.instance
          .ref('calls/${widget.childUid}/needsConsent')
          .remove();
      await FirebaseDatabase.instance
          .ref('calls/${widget.childUid}/projectionReady')
          .remove();
      // STREAM-01: Clear stale WebSocket stream mode flag
      await FirebaseDatabase.instance
          .ref('calls/${widget.childUid}/wsStreamMode')
          .remove();

      await _webrtc.startAsParent(
          childUid: widget.childUid, mode: widget.mode);
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _status = widget.mode == StreamMode.screen
            ? 'Requesting screen share from child device...'
            : 'Waiting for child device to respond...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _status = 'Connection error. Tap Retry to try again.';
      });
    }
  }

  /// BUG-2 FIX: Retry starting the monitoring session.
  /// This is useful when the initial connection fails or times out,
  /// especially for screen sharing where the child device may need
  /// to grant MediaProjection consent first.
  Future<void> _retryMonitoring() async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
      _status = 'Retrying connection...';
    });
    // Cancel any existing timeout
    _timeout?.cancel();
    // Restart the monitoring session
    await _startMonitoring();
    // Re-arm the timeout
    _timeout = Timer(Duration(seconds: widget.mode == StreamMode.screen ? 15 : 30), () {
      if (mounted && !_hasStream && !_nativeCaptureMode) {
        setState(() {
          _isRetrying = false;
          _status = widget.mode == StreamMode.screen
              ? 'Screen share not available yet.\nMake sure the child app is open and screen permission is granted.\nTap Retry to try again.'
              : 'Waiting for child device...\nMake sure the child app is open and camera permission has been granted.';
        });
      }
    });
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() { _showControls = !_showControls; });
    if (_showControls) {
      _startControlsTimer();
    }
  }

  Future<void> _flipCamera() async {
    await _webrtc.sendFlipCommand(widget.childUid);
  }

  Future<void> _toggleMic() async {
    await _webrtc.sendMuteCommand(widget.childUid, !_isMuted);
    if (!mounted) return;
    setState(() { _isMuted = !_isMuted; });
  }

  bool _callEnded = false;

  Future<void> _endSession() async {
    // LC-02: Guard against double-invocation (e.g. "End" button tap racing
    // with the system back gesture, or dispose() calling after _endSession).
    if (_callEnded) return;
    _callEnded = true;
    _timeout?.cancel();
    _controlsTimer?.cancel();
    await _webrtc.endCall(widget.childUid);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _controlsTimer?.cancel();
    _statusSub?.cancel();
    _heartbeatSub?.cancel();
    _screenErrorSub?.cancel();
    _nativeCaptureSub?.cancel();
    _nativeCaptureModeSub?.cancel();
    // STREAM-01: Clean up WebSocket stream viewer
    _wsFrameSub?.cancel();
    _wsConnStateSub?.cancel();
    _streamViewer?.dispose();
    _streamViewer = null;
    _webrtc.onRemoteStream = null;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // P5-B: Chain endCall → dispose so the Firebase 'ended' write reaches the
    // child's _callsSub before the peer connection is torn down.
    if (!_callEnded) {
      _webrtc.endCall(widget.childUid)
          .catchError((_) {})
          .whenComplete(() => _webrtc.dispose());
    } else {
      _webrtc.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final childName = widget.childData['childName'] as String? ?? 'Child';
    final isScreen = widget.mode == StreamMode.screen;
    final isCameraMode = !isScreen;

    // BUG-2-FIX: Determine if we should show native frame display instead
    // of the WebRTC RTCVideoView. This happens when the child device falls
    // back to native VirtualDisplay + ImageReader capture because
    // flutter_webrtc's getDisplayMedia() failed.
    final showNativeFrames = _nativeCaptureMode && _currentFrame != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(fit: StackFit.expand, children: [
          // BUG-2-FIX: Native frame display for screen capture fallback.
          // When flutter_webrtc's getDisplayMedia() fails on the child
          // device (Android 14+ Intent serialization issue), the child
          // falls back to native VirtualDisplay + ImageReader capture.
          // Frames are relayed via Firebase RTDB and displayed here.
          if (showNativeFrames)
            Center(
              child: Image.memory(
                _currentFrame!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      'Frame decode error',
                      style: GoogleFonts.inter(color: Colors.white54),
                    ),
                  );
                },
              ),
            ),

          // Video feed — always in the widget tree so the native surface
          // is created before srcObject is assigned. Hiding it with
          // Offstage avoids the blank-renderer problem on Android.
          if (!showNativeFrames)
            Offstage(
              offstage: !_hasStream,
              child: RTCVideoView(
                _webrtc.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),

          // Waiting state (only when no stream AND no native frames)
          if (!_hasStream && !showNativeFrames)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isScreen ? Icons.screen_share : Icons.videocam,
                    color: Colors.white24,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isScreen ? 'Screen Share' : 'Camera',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ).animate().fadeIn(),
                  const SizedBox(height: 16),
                  if (_isRetrying)
                    const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3)
                  else ...[
                    // BUG-2 FIX: Show a retry button instead of just a spinner
                    // when the connection times out or fails. This gives the
                    // parent an actionable way to retry, especially for screen
                    // sharing where the child device may need to grant consent.
                    const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    _status,
                    style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(),
                  const SizedBox(height: 16),
                  // BUG-2 FIX: Show retry button when not currently retrying
                  // and the stream hasn't connected yet.
                  if (!_isRetrying)
                    TextButton.icon(
                      onPressed: _retryMonitoring,
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                      label: Text(
                        'Retry',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ),
                ]),
              ),
            ),

          // Controls overlay
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: SafeArea(
              child: Column(children: [
                // Top bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(children: [
                    IconButton(
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _endSession,
                    ),
                    const SizedBox(width: 4),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            childName,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: _isChildOnline
                                      ? Colors.greenAccent
                                      : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                _isChildOnline ? 'Online' : 'Offline',
                                style: GoogleFonts.inter(
                                  color: _isChildOnline
                                      ? Colors.greenAccent
                                      : Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isScreen ? '📱 Screen' : '📷 Camera',
                                style: GoogleFonts.inter(
                                  color: Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                              // BUG-2-FIX: Show capture mode indicator
                              if (_nativeCaptureMode) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _wsStreamMode
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.amber.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _wsStreamMode
                                        ? 'Live ${_streamFps > 0 ? '${_streamFps.toStringAsFixed(0)}fps' : ''}'
                                        : 'Frame Mode',
                                    style: GoogleFonts.inter(
                                      color: _wsStreamMode
                                          ? Colors.greenAccent
                                          : Colors.amberAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ]),
                    const Spacer(),
                    if (_hasStream || showNativeFrames) _liveBadge(),
                    const SizedBox(width: 8),
                  ]),
                ),

                const Spacer(),

                // BUG-1 FIX: Bottom controls clearly separated by mode.
                // Camera mode: mute + flip + end buttons.
                // Screen mode: only end button (no camera-specific controls).
                // This prevents the camera toggle (flip) from showing when
                // the parent is viewing the child's screen share.
                if (_hasStream || showNativeFrames)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // BUG-1 FIX: Camera-specific controls ONLY in camera mode.
                        // These MUST NOT appear in screen mode.
                        if (isCameraMode) ...[
                          _controlBtn(
                            icon: _isMuted ? Icons.mic_off : Icons.mic,
                            label: _isMuted ? 'Unmute' : 'Mute',
                            onTap: _toggleMic,
                            color: _isMuted ? Colors.red : Colors.white24,
                          ),
                          _controlBtn(
                            icon: Icons.flip_camera_android,
                            label: 'Flip',
                            onTap: _flipCamera,
                            color: Colors.white24,
                          ),
                        ],
                        // BUG-1 FIX: Screen mode shows only the End button.
                        // No camera toggle (flip) or mute button in screen mode.
                        _controlBtn(
                          icon: Icons.call_end,
                          label: 'End',
                          onTap: _endSession,
                          color: Colors.red,
                          size: 68,
                        ),
                      ],
                    ),
                  ),
              ]),
            ),
          ),

          // BUG-1: Persistent mode badge — always visible regardless of
          // _showControls or _hasStream, so the user can always tell which
          // mode (Camera vs Screen) they are in.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isScreen ? Colors.blueAccent : Colors.orangeAccent,
                  width: 1.5,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  isScreen ? Icons.screen_share : Icons.camera_alt,
                  color: isScreen ? Colors.blueAccent : Colors.orangeAccent,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Text(
                  isScreen ? 'Screen Share' : 'Camera',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _liveBadge() => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 800.ms),
          const SizedBox(width: 6),
          Text('LIVE',
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    double size = 56,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: size,
            height: size,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 11)),
        ]),
      );
}
