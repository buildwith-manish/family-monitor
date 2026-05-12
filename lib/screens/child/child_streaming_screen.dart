import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/screen_capture_channel.dart';
import '../../services/webrtc_service.dart';

class ChildStreamingScreen extends StatefulWidget {
  final String childUid;
  final String? childName;
  final String? parentUid;
  final StreamMode mode;

  const ChildStreamingScreen({
    super.key,
    required this.childUid,
    this.childName,
    this.parentUid,
    this.mode = StreamMode.camera,
  });

  @override
  State<ChildStreamingScreen> createState() =>
      _ChildStreamingScreenState();
}

class _ChildStreamingScreenState
    extends State<ChildStreamingScreen> {
  final WebRTCService _webrtc =
      WebRTCService();

  bool _isConnecting = true;
  bool _isFrontCamera = true;
  bool _retrying = false;

  String _statusMsg = 'Starting...';

  Timer? _retryTimer;

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
    if (!mounted) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _retrying = false;
    });

    try {
      if (widget.mode ==
          StreamMode.screen) {
        setState(() {
          _statusMsg =
              'Requesting screen permission...';
        });

        final bool granted =
            await ScreenCaptureChannel
                .requestScreenCapture();

        if (!granted) {
          if (!mounted) {
            return;
          }

          setState(() {
            _isConnecting = false;
            _statusMsg =
                'Screen sharing permission denied.';
          });

          return;
        }

        setState(() {
          _statusMsg =
              'Starting screen share...';
        });

        await _webrtc
            .startSilentScreen(
          widget.childUid,
          () {
            if (mounted) {
              Navigator.pop(
                context,
              );
            }
          },
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _isConnecting = false;
          _statusMsg =
              'Sharing screen with parent';
        });
      } else {
        setState(() {
          _statusMsg =
              'Starting camera...';
        });

        await _webrtc.startAsChild(
          widget.childUid,
          () {
            if (mounted) {
              Navigator.pop(
                context,
              );
            }
          },
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _isConnecting = false;
          _statusMsg =
              'Camera streaming active';
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isConnecting = false;
        _retrying = true;
        _statusMsg =
            'Connection failed. Retrying in 5 seconds...';
      });

      _retryTimer?.cancel();

      _retryTimer = Timer(
        const Duration(seconds: 5),
        () {
          if (mounted &&
              _retrying) {
            _startStreaming();
          }
        },
      );
    }
  }

  Future<void> _stop() async {
    await _webrtc.endCall(
      widget.childUid,
    );

    if (widget.mode ==
        StreamMode.screen) {
      await ScreenCaptureChannel
          .stopScreenCaptureService();
    }

    if (!mounted) {
      return;
    }

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();

    SystemChrome
        .setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _webrtc.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isScreen =
        widget.mode ==
            StreamMode.screen;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_isConnecting &&
              !isScreen)
            RTCVideoView(
              _webrtc.localRenderer,
              mirror:
                  _isFrontCamera,
              objectFit:
                  RTCVideoViewObjectFit
                      .RTCVideoViewObjectFitCover,
            ),

          if (!_isConnecting &&
              isScreen)
            Center(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.screen_share,
                    color:
                        Colors.white54,
                    size: 64,
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Text(
                    'Sharing screen with parent',
                    style:
                        GoogleFonts.inter(
                      color:
                          Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          if (_isConnecting)
            Center(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color:
                        Colors.white,
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Text(
                    _statusMsg,
                    style:
                        GoogleFonts.inter(
                      color:
                          Colors.white70,
                      fontSize: 13,
                    ),
                    textAlign:
                        TextAlign.center,
                  ),
                ],
              ),
            ),

          if (!_isConnecting &&
              _retrying)
            Center(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off,
                    color:
                        Colors.white54,
                    size: 48,
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Text(
                    _statusMsg,
                    style:
                        GoogleFonts.inter(
                      color:
                          Colors.white60,
                      fontSize: 13,
                    ),
                    textAlign:
                        TextAlign.center,
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  TextButton(
                    onPressed:
                        _startStreaming,
                    child: Text(
                      'Retry now',
                      style:
                          GoogleFonts.inter(
                        color:
                            Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                _topBar(),

                const Spacer(),

                _bottomBar(
                  isScreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration:
          const BoxDecoration(
        gradient: LinearGradient(
          begin:
              Alignment.topCenter,
          end:
              Alignment.bottomCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          if (!_isConnecting)
            _liveBadge(),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Text(
              _statusMsg,
              style:
                  GoogleFonts.inter(
                color:
                    Colors.white70,
                fontSize: 12,
              ),
              overflow:
                  TextOverflow
                      .ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(
    bool isScreen,
  ) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        20,
        24,
        40,
      ),
      decoration:
          const BoxDecoration(
        gradient: LinearGradient(
          begin:
              Alignment.bottomCenter,
          end:
              Alignment.topCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment
                .center,
        children: [
          _circleBtn(
            icon:
                Icons.call_end,
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
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration:
          BoxDecoration(
        color: Colors.red,
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(
              color: Colors.white,
              shape:
                  BoxShape.circle,
            ),
          )
              .animate(
                onPlay:
                    (controller) =>
                        controller
                            .repeat(),
              )
              .fadeOut(
                duration: 800.ms,
              ),

          const SizedBox(
            width: 6,
          ),

          Text(
            'LIVE',
            style:
                GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight:
                  FontWeight.w800,
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
        decoration:
            BoxDecoration(
          color: bg,
          shape:
              BoxShape.circle,
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
