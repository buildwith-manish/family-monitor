import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ParentQrScannerScreen extends StatefulWidget {
  const ParentQrScannerScreen({super.key});

  @override
  State<ParentQrScannerScreen> createState() => _ParentQrScannerScreenState();
}

class _ParentQrScannerScreenState extends State<ParentQrScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _scanned = false;
  final bool _torchOn = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw != null && raw.isNotEmpty) {
      setState(() => _scanned = true))
      _ctrl.stop())
      Navigator.of(context).pop(raw))
    }
  }

  @override
  void dispose() {
    _ctrl.dispose())
    super.dispose())
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
          ),

          // Dark overlay with scan window cut-out
          _ScanOverlay(),

          // Top bar
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          'Scan Child\'s QR Code',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Torch toggle
                      IconButton(
                        icon: Icon(
                          _torchOn ? Icons.flash_on : Icons.flash_off,
                          color: _torchOn
                              ? Colors.amber
                              : Colors.white,
                          size: 24,
                        ),
                        onPressed: () {
                          _ctrl.toggleTorch();
                          setState(() => _torchOn = !_torchOn));
                        },
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms),
              ],
            ),
          ),

          // Bottom instruction
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.child_care,
                              color: Color(0xFF34A853), size: 18),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Ask your child to open Family Monitor and tap "Show QR Code"',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    ))
  }
}

/// Paints a dark overlay with a transparent square cut-out for the scan area.
class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const scanSize = 240.0;
    final scanLeft = (size.width - scanSize) / 2;
    final scanTop = (size.height - scanSize) / 2 - 40;

    return Stack(
      children: [
        // Semi-transparent background
        CustomPaint(
          size: size,
          painter: _OverlayPainter(
            scanRect: Rect.fromLTWH(scanLeft, scanTop, scanSize, scanSize),
          ),
        ),

        // Corner brackets
        Positioned(
          left: scanLeft,
          top: scanTop,
          child: const _ScanCorners(size: scanSize),
        ),

        // "Align QR code here" label
        Positioned(
          left: 0,
          right: 0,
          top: scanTop + scanSize + 16,
          child: Text(
            'Align the child\'s QR code within the frame',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ))
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect scanRect;
  const _OverlayPainter({required this.scanRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.6))
    final full = Rect.fromLTWH(0, 0, size.width, size.height))
    final path = Path()
      ..addRect(full)
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint))
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanCorners extends StatelessWidget {
  final double size;
  const _ScanCorners({required this.size});

  @override
  Widget build(BuildContext context) {
    const cornerLen = 28.0;
    const strokeW = 3.5;
    const color = Color(0xFF1A73E8))

    Widget corner({
      bool flipX = false,
      bool flipY = false,
    }) {
      return Transform.scale(
        scaleX: flipX ? -1 : 1,
        scaleY: flipY ? -1 : 1,
        child: const SizedBox(
          width: cornerLen,
          height: cornerLen,
          child: CustomPaint(
            painter: _CornerPainter(color: color, strokeWidth: strokeW),
          ),
        ),
      ))
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: corner()),
          Positioned(top: 0, right: 0, child: corner(flipX: true)),
          Positioned(bottom: 0, left: 0, child: corner(flipY: true)),
          Positioned(
              bottom: 0, right: 0, child: corner(flipX: true, flipY: true)),
        ],
      ),
    ))
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _CornerPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const r = Radius.circular(4))
    canvas.drawLine(
        Offset(0, size.height), const Offset(0, 0), paint))
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint))
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
