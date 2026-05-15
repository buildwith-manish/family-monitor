import '../../services/webrtc_service.dart';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  bool _isMuted = false;
  bool _showControls = true;
  String _status = 'Connecting...';
  bool _isChildOnline = false;
  Timer? _timeout;
  Timer? _controlsTimer;
  StreamSubscription? _statusSub;
  StreamSubscription? _heartbeatSub;

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
    };
    _startMonitoring();
    _listenToPresence();
    _timeout = Timer(const Duration(seconds: 30), () {
      if (mounted && !_hasStream) {
        setState(() {
          _status = 'Waiting for child device...\nMake sure the child app has camera permission granted.';
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
  }

  Future<void> _startMonitoring() async {
    try {
      await _webrtc.startAsParent(
          childUid: widget.childUid, mode: widget.mode);
      if (!mounted) return;
      setState(() {
        _status = 'Waiting for child device to respond...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _status = 'Connection error. Retrying...'; });
    }
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
    _webrtc.onRemoteStream = null;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // LC-02: Only send endCall from dispose if _endSession() was NOT already
    // called (i.e. the user used a system back gesture bypassing _endSession).
    // Without this guard, endCall fires twice — once from _endSession and
    // once from dispose — which can produce a second 'ended' write that
    // races with a new session the parent immediately starts.
    if (!_callEnded) {
      _webrtc.endCall(widget.childUid).catchError((_) {});
    }
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final childName = widget.childData['childName'] as String? ?? 'Child';
    final isScreen = widget.mode == StreamMode.screen;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(fit: StackFit.expand, children: [
          // Video feed — always in the widget tree so the native surface
          // is created before srcObject is assigned. Hiding it with
          // Offstage avoids the blank-renderer problem on Android where
          // assigning srcObject before the SurfaceViewRenderer is attached
          // to a native view produces a permanently blank frame.
          Offstage(
            offstage: !_hasStream,
            child: RTCVideoView(
              _webrtc.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
          ),

          // Waiting state
          if (!_hasStream)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 3),
                const SizedBox(height: 24),
                Text(
                  _status,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(),
                const SizedBox(height: 8),
                Text(
                  isScreen
                      ? 'Requesting screen from child device silently...'
                      : 'Connecting to child device silently...',
                  style:
                      GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ]),
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
                            ],
                          ),
                        ]),
                    const Spacer(),
                    if (_hasStream) _liveBadge(),
                    const SizedBox(width: 8),
                  ]),
                ),

                const Spacer(),

                // Bottom controls
                if (_hasStream)
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
                        if (!isScreen)
                          _controlBtn(
                            icon: _isMuted ? Icons.mic_off : Icons.mic,
                            label: _isMuted ? 'Unmute' : 'Mute',
                            onTap: _toggleMic,
                            color: _isMuted ? Colors.red : Colors.white24,
                          ),
                        if (!isScreen)
                          _controlBtn(
                            icon: Icons.flip_camera_android,
                            label: 'Flip',
                            onTap: _flipCamera,
                            color: Colors.white24,
                          ),
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
