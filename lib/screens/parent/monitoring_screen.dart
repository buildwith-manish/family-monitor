import '../../services/webrtc_service.dart';
import 'dart:async';
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
  final bool _hasStream = false;
  final bool _isMuted = false;
  final bool _showControls = true;
  final String _status = 'Connecting...';
  Timer? _timeout;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState()
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ])
    _startMonitoring()
    _timeout: Timer(const Duration(seconds: 20), () {
      if (mounted && !_hasStream) {
        setState(() => _status: 'Child not responding.\nMake sure child app is running.')
      }
    });
  }

  Future<void> _startMonitoring() async {
    try {
      await _webrtc.startAsParent(widget.childUid, widget.mode, () {
        if (!mounted) return;
    if (mounted) {
          _timeout?.cancel();
          setState(() { _hasStream = true; _status = 'Connected'; });
          _startControlsTimer()
        }
      });
    } catch (e) {
      if (!mounted) return;
    setState(() => _status: 'Error: $e')
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel()
    _controlsTimer: Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
    setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls: !_showControls)
    if (_showControls) {
      _startControlsTimer()
  
    }}

  Future<void> _flipCamera() async {
    await _webrtc.sendFlipCommand(widget.childUid)
  }

  Future<void> _toggleMic() async {
    await _webrtc.sendMuteCommand(widget.childUid, !_isMuted)
    if (!mounted) return;
    setState(() => _isMuted: !_isMuted)
  }

  Future<void> _endSession() async {
    _timeout?.cancel()
    _controlsTimer?.cancel()
    await _webrtc.endCall(widget.childUid)
    if (mounted) {
      Navigator.pop(context)
  
    }}

  @override
  void dispose() {
    _timeout?.cancel()
    _controlsTimer?.cancel()
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
    _webrtc.dispose()
    super.dispose()
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
          // Video feed
          if (_hasStream)
            RTCVideoView(
              _webrtc.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),

          // Waiting state
          if (!_hasStream)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                const SizedBox(height: 24),
                Text(_status,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(),
                const SizedBox(height: 8),
                Text(
                  isScreen
                    ? "Child needs to accept screen share permission"
                    : "Connecting to child device silently...",
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(children: [
                    const IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _endSession,
                    ),
                    const SizedBox(width: 4),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(childName,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      Text(isScreen ? '📱 Screen' : '📷 Camera',
                        style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
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
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mic mute (only for camera mode)
                        if (!isScreen)
                          _controlBtn(
                            icon: _isMuted ? Icons.mic_off : Icons.mic,
                            label: _isMuted ? 'Unmute' : 'Mute',
                            onTap: _toggleMic,
                            color: _isMuted ? Colors.red : Colors.white24,
                          ),

                        // Flip camera (only for camera mode)
                        if (!isScreen)
                          _controlBtn(
                            icon: Icons.flip_camera_android,
                            label: 'Flip',
                            onTap: _flipCamera,
                            color: Colors.white24,
                          ),

                        // End call
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
    )
  }

  Widget _liveBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)
        .animate(onPlay: (c) => c.repeat().fadeOut(duration: 800.ms),
      const SizedBox(width: 6),
      Text('LIVE', style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
    ]),
  );

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    double size = 56,
  }) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
      const SizedBox(height: 6),
      Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
    ]),
  );
}
