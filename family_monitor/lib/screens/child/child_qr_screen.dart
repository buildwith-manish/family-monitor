import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ChildQrScreen extends StatelessWidget {
  final String uid;
  final String childName;

  const ChildQrScreen({
    super.key,
    required this.uid,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Share Device ID'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Instruction card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner,
                        color: Color(0xFF1A73E8), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ask your parent to open Family Monitor → Add Child Device → Scan QR Code, then point their camera at this screen.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF1A4FA8),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 36),

              // QR code card
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Name badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        childName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A73E8),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // QR Code
                    QrImageView(
                      data: uid,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF202124),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF202124),
                      ),
                    ).animate(delay: 200.ms).scale(
                          duration: 500.ms,
                          curve: Curves.elasticOut,
                        ),

                    const SizedBox(height: 20),

                    // UID text
                    Text(
                      uid,
                      style: GoogleFonts.robotoMono(
                        fontSize: 10,
                        color: const Color(0xFF5F6368),
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.15, end: 0),

              const SizedBox(height: 28),

              // Copy button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: uid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Device ID copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy Device ID'),
                ),
              ).animate(delay: 400.ms).fadeIn(),

              const SizedBox(height: 12),

              // Privacy note
              Text(
                'This QR code only contains your device ID — no personal data.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF9AA0A6),
                ),
                textAlign: TextAlign.center,
              ).animate(delay: 500.ms).fadeIn(),
            ],
          ),
        ),
      ),
    );
  }
}
