import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_service.dart';

class ChildStreamingScreen extends StatefulWidget {
  final String childUid;
  final String? childName;
  final String? parentUid;
  const ChildStreamingScreen({
    super.key,
    required this.childUid,
    this.childName,
    this.parentUid,
  });
  @override
  State<ChildStreamingScreen> createState() => _ChildStreamingScreenState();
}

class _ChildStreamingScreenState extends State<ChildStreamingScreen> {
  final _webrtc = WebRTCService();
  bool _isConnecting = true;
  bool _isFrontCamera = false;
  String _statusMsg = 'Starting camera...';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startStreaming();
  }

  Future<void> _startStreaming() async {
    try {
      await _webrtc.startAsChild(widget.childUid, () {
        if (mounted) Navigator.pop(context);
      });
      if (mounted) setState(() { _isConnecting = false; _statusMsg = 'Streaming to parent'; });
    } catch (e) {
      if (mounted) setState(() { _isConnecting = false; _statusMsg = 'Camera error: $e'; });
    }
  }

  Future<void> _stop() async {
    await _webrtc.endCall(widget.childUid);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _flipCamera() async {
    await _webrtc.switchCamera();
    if (mounted) setState(() => _isFrontCamera = !_isFrontCamera);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (!_isConnecting)
          RTCVideoView(_webrtc.localRenderer,
              mirror: _isFrontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        if (_isConnecting)
          const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Starting camera...', style: TextStyle(color: Colors.white, fontSize: 14)),
          ])),
        SafeArea(child: Column(children: [
          _topBar(),
          const Spacer(),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent])),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _circleBtn(icon: Icons.flip_camera_android, onTap: _flipCamera, bg: Colors.white24, size: 56, iconSize: 24),
              const SizedBox(width: 48),
              _circleBtn(icon: Icons.call_end, onTap: _stop, bg: Colors.red, size: 68, iconSize: 30),
            ]),
          ),
        ])),
      ]),
    );
  }

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent])),
    child: Row(children: [
      if (!_isConnecting) _liveBadge(),
      const SizedBox(width: 12),
      Expanded(child: Text(_statusMsg,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _liveBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
          .animate(onPlay: (c) => c.repeat()).fadeOut(duration: 800.ms),
      const SizedBox(width: 6),
      Text('LIVE', style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _circleBtn({required IconData icon, required VoidCallback onTap,
      required Color bg, required double size, required double iconSize}) =>
      GestureDetector(onTap: onTap, child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ));
}
