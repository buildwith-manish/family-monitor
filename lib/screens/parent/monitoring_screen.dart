import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_service.dart';

class MonitoringScreen extends StatefulWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  const MonitoringScreen({
    super.key,
    required this.childUid,
    required this.childData,
  });
  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final _webrtc = WebRTCService();
  bool _hasStream = false;
  String _status = 'Waiting for child device...';
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startMonitoring();
    _timeout = Timer(const Duration(seconds: 40), () {
      if (mounted && !_hasStream) {
        setState(() => _status =
            'Child not responding.\nMake sure child app is open.');
      }
    });
  }

  Future<void> _startMonitoring() async {
    try {
      await _webrtc.startAsParent(widget.childUid, () {
        if (mounted) {
          _timeout?.cancel();
          setState(() {
            _hasStream = true;
            _status = 'Connected';
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _endSession() async {
    _timeout?.cancel();
    await _webrtc.endCall(widget.childUid);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final childName =
        widget.childData['childName'] as String? ?? 'Child';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
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
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              Text(
                _status,
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ).animate().fadeIn(),
              const SizedBox(height: 8),
              Text(
                "Open Family Monitor on the child's device",
                style:
                    GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        // Overlay controls
        SafeArea(
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
                Text(
                  childName,
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_hasStream)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                      )
                          .animate(onPlay: (c) => c.repeat())
                          .fadeOut(duration: 800.ms),
                      const SizedBox(width: 6),
                      Text('LIVE',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                const SizedBox(width: 8),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: GestureDetector(
                onTap: _endSession,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.call_end,
                      color: Colors.white, size: 30),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
