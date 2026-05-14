import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2200));

    if (!mounted) return;

    // Wait for Firebase Auth to restore the persisted session.
    // On cold start, currentUser can be null for 300-800ms even with a valid
    // cached token — authStateChanges emits the true state within ~100ms.
    // Capped at 3 seconds as a safety net against a hung Firebase init.
    User? user;
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }

    if (!mounted) return;

    if (user == null) {
      Navigator.pushReplacementNamed(context, '/role-select');
      return;
    }

    // P1-B: Force a server round-trip to validate the cached token.
    // Catches deleted/disabled accounts and revoked tokens that would
    // otherwise appear authenticated until the local cache expires (~1 h).
    // Only FirebaseAuthException (auth-specific) triggers sign-out —
    // generic network errors are swallowed so offline users are not
    // logged out during brief connectivity gaps.
    try {
      await user.getIdToken(true);
    } on FirebaseAuthException {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/role-select');
      return;
    }

    final role = await AuthService().getSavedRole();

    if (!mounted) return;

    switch (role) {
      case UserRole.parent:
        Navigator.pushReplacementNamed(context, '/parent/dashboard');
        break;
      case UserRole.child:
        Navigator.pushReplacementNamed(context, '/child/home');
        break;
      case UserRole.unknown:
        // HIGH-02: When the authenticated user's role is absent from
        // SharedPreferences (device transfer, factory reset without full wipe,
        // or crash during sign-out), fall back to the authoritative RTDB record
        // rather than sending them to role-select and losing session context.
        // If RTDB also has no role, fall through to role-select normally.
        try {
          final snap = await FirebaseDatabase.instance
              .ref('users/${user.uid}/role')
              .get();
          final remoteRole = snap.value as String?;
          if (!mounted) return;
          if (remoteRole == 'parent' || remoteRole == 'child') {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_role', remoteRole!);
            if (!mounted) return;
            Navigator.pushReplacementNamed(
              context,
              remoteRole == 'parent' ? '/parent/dashboard' : '/child/home',
            );
          } else {
            Navigator.pushReplacementNamed(context, '/role-select');
          }
        } catch (_) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/role-select');
        }
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
            ).animate(delay: 600.ms).fadeIn(duration: 500.ms),

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
    );
  }
}
