import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/screen_capture_channel.dart';

/// ChildStreamingScreen — WebSocket-only screen streaming.
///
/// Uses the FlashGet Kids approach:
///   1. Request MediaProjection permission via MethodChannel
///   2. Start ScreenStreamService (VirtualDisplay + ImageReader → WebSocket)
///   3. Monitor stream status via periodic polling
///
/// NO WebRTC fallback — the WebSocket relay pipeline is the sole path.
class ChildStreamingScreen extends StatefulWidget {
  final String childUid;
  final String? childName;
  final String? parentUid;
  final String? serverUrl;

  const ChildStreamingScreen({
    super.key,
    required this.childUid,
    this.childName,
    this.parentUid,
    this.serverUrl,
  });

  @override
  State<ChildStreamingScreen> createState() => _ChildStreamingScreenState();
}

class _ChildStreamingScreenState extends State<ChildStreamingScreen> {
  bool _isConnecting = true;
  bool _isStreaming = false;
  bool _retrying = false;
  String _statusMsg = 'Starting...';

  Timer? _retryTimer;
  Timer? _statusTimer;

  int _frameCount = 0;
  bool _wsConnected = false;

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
    if (!mounted) return;

    setState(() {
      _isConnecting = true;
      _retrying = false;
      _statusMsg = 'Requesting screen permission...';
    });

    try {
      // Step 1: Request MediaProjection permission
      final bool granted =
          await ScreenCaptureChannel.requestScreenCapture();

      if (!granted) {
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
          _statusMsg = 'Screen sharing permission denied.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _statusMsg = 'Starting WebSocket screen stream...';
      });

      // Step 2: Start WebSocket screen stream via native ScreenStreamService
      final bool started = await ScreenCaptureChannel.startScreenStream(
        uid: widget.childUid,
        serverUrl: widget.serverUrl,
      );

      if (!started) {
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
          _retrying = true;
          _statusMsg = 'Failed to start stream. Retrying...';
        });
        _scheduleRetry();
        return;
      }

      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _isStreaming = true;
        _statusMsg = 'Sharing screen with parent';
      });

      // Step 3: Start monitoring stream status
      _startStatusPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _retrying = true;
        _statusMsg = 'Connection failed. Retrying in 5 seconds...';
      });
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _retrying) {
        _startStreaming();
      }
    });
  }

  /// Periodically poll the native ScreenStreamService status.
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || !_isStreaming) return;

      try {
        final status = await ScreenCaptureChannel.getStreamStatus();
        if (status != null) {
          final streaming = status['isStreaming'] as bool? ?? false;
          final wsOk = status['wsConnected'] as bool? ?? false;
          final frames = status['frameCount'] as int? ?? 0;

          if (mounted) {
            setState(() {
              _wsConnected = wsOk;
              _frameCount = frames;
            });
          }

          // If streaming stopped unexpectedly, try to recover
          if (!streaming && _isStreaming) {
            debugPrint('[ChildStreaming] Stream stopped unexpectedly — recovering');
            if (mounted) {
              setState(() {
                _isStreaming = false;
                _retrying = true;
                _statusMsg = 'Stream interrupted. Reconnecting...';
              });
            }
            _scheduleRetry();
          }
        }
      } catch (e) {
        debugPrint('[ChildStreaming] Status poll error: $e');
      }
    });
  }

  Future<void> _stop() async {
    _statusTimer?.cancel();

    // Stop the WebSocket screen stream
    await ScreenCaptureChannel.stopScreenStream();

    // Release the MediaProjection
    await ScreenCaptureChannel.releaseProjection();

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _statusTimer?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Active streaming indicator
          if (!_isConnecting && _isStreaming)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.screen_share,
                    color: Colors.white54,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sharing screen with parent',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // WebSocket connection status
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _wsConnected ? Colors.green : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _wsConnected ? 'WebSocket connected' : 'Connecting to server...',
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (_frameCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Frames sent: $_frameCount',
                      style: GoogleFonts.inter(
                        color: Colors.white24,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Connecting spinner
          if (_isConnecting)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _statusMsg,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Retry state
          if (!_isConnecting && _retrying)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off,
                    color: Colors.white54,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusMsg,
                    style: GoogleFonts.inter(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _startStreaming,
                    child: Text(
                      'Retry now',
                      style: GoogleFonts.inter(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          // Top bar + bottom bar
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                _bottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          if (_isStreaming) _liveBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMsg,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _circleBtn(
            icon: Icons.call_end,
            onTap: _stop,
            bg: Colors.red,
            size: 68,
            iconSize: 30,
          ),
        ],
      ),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (controller) => controller.repeat())
              .fadeOut(duration: 800.ms),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    required Color bg,
    required double size,
    required double iconSize,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }
}
