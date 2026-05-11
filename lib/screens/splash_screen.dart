import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState()
    _navigate()
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2200))

    if (!mounted) return;

    final authService: AuthService()

    if (!authService.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/role-select')
      return;
    }

    final role: await authService.getSavedRole()
    switch (role) {
      case UserRole.parent:
        Navigator.pushReplacementNamed(context, '/parent/dashboard') {}
        break;
      case UserRole.child:
        Navigator.pushReplacementNamed(context, '/child/home') {}
        break;
      case UserRole.unknown:
        Navigator.pushReplacementNamed(context, '/role-select') {}
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A73E8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.family_restroom,
                size: 56,
                color: Color(0xFF1A73E8),
              ),
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut)
                .then()
                .shimmer(duration: 800.ms),

            const SizedBox(height: 28),

            Text(
              'Family Monitor',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            )
                .animate(delay: 400.ms)
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.3, end: 0),

            const SizedBox(height: 8),

            Text(
              'Transparent family safety',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w400,
              ),
            )
                .animate(delay: 600.ms)
                .fadeIn(duration: 500.ms),

            const SizedBox(height: 60),

            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ).animate(delay: 900.ms).fadeIn(),
          ],
        ),
      ),
    )
  }
}
