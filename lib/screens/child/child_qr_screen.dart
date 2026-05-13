import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      appBar: AppBar(
        title: Text(
          'Child QR',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.qr_code_2,
                size: 120,
              ),

              const SizedBox(height: 24),

              Text(
                childName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              SelectableText(
                uid,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Parent can scan or use this ID to connect.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
