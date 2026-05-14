import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/pin_service.dart';

import 'child_home_screen.dart';
import 'child_setup_wizard_screen.dart';

class ChildAuthScreen extends StatefulWidget {
  const ChildAuthScreen({super.key});

  @override
  State<ChildAuthScreen> createState() =>
      _ChildAuthScreenState();
}

class _ChildAuthScreenState extends State<ChildAuthScreen> {
  final AuthService _auth = AuthService();

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl  = TextEditingController();
  final TextEditingController _nameCtrl  = TextEditingController();
  final TextEditingController _pinCtrl   = TextEditingController();
  final TextEditingController _pinConfirmCtrl = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePass = true;
  String? _error;

  // PIN dot state (signup only)
  final ValueNotifier<int> _pinLength        = ValueNotifier(0);
  final ValueNotifier<int> _pinConfirmLength = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _checkAlreadyLoggedIn();
    _pinCtrl.addListener(() => _pinLength.value = _pinCtrl.text.length);
    _pinConfirmCtrl.addListener(
        () => _pinConfirmLength.value = _pinConfirmCtrl.text.length);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    _pinLength.dispose();
    _pinConfirmLength.dispose();
    super.dispose();
  }

  Future<void> _checkAlreadyLoggedIn() async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final bool wizardDone =
        await BackgroundMonitoringService.isWizardDone();
    if (!mounted) return;

    if (wizardDone) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
      );
    }
  }

  Future<void> _submit() async {
    // Validate PIN for signup
    if (!_isLogin) {
      if (_pinCtrl.text.length != 4) {
        setState(() => _error = 'Safety PIN must be exactly 4 digits.');
        return;
      }
      if (_pinCtrl.text != _pinConfirmCtrl.text) {
        setState(() => _error = 'PINs do not match. Please try again.');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      late Map<String, dynamic> result;

      if (_isLogin) {
        result = await _auth.signInChild(
          _emailCtrl.text.trim(),
          _passCtrl.text.trim(),
        );
      } else {
        result = await _auth.signUpChild(
          _emailCtrl.text.trim(),
          _passCtrl.text.trim(),
          _nameCtrl.text.trim(),
        );
      }

      if (result['success'] != true) {
        setState(() {
          _error = result['error']?.toString() ?? 'Authentication failed.';
        });
        return;
      }

      final String? uid = _auth.currentUser?.uid;
      if (uid == null) {
        setState(() => _error = 'Authentication failed.');
        return;
      }

      await BackgroundMonitoringService.saveChildUid(uid);

      // Save PIN for new accounts
      if (!_isLogin) {
        await PinService.savePin(uid, _pinCtrl.text.trim());
      }

      // Save FCM token
      try {
        final token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 5));
        if (token != null) {
          await FirebaseDatabase.instance
              .ref('users/$uid/fcmToken')
              .set(token);
        }
      } catch (_) {}

      if (!mounted) return;

      final bool wizardDone =
          await BackgroundMonitoringService.isWizardDone();
      if (!mounted) return;

      if (!wizardDone) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChildSetupWizardScreen(childUid: uid),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF34A853).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.child_care,
                  color: Color(0xFF34A853),
                  size: 36,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                _isLogin ? 'Child Sign In' : 'Create Child Account',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF202124),
                ),
              ),

              const SizedBox(height: 6),

              Text(
                _isLogin
                    ? 'Sign in to your child account'
                    : 'Set up your child profile and safety PIN',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF5F6368),
                ),
              ),

              const SizedBox(height: 28),

              // Error banner
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE8E6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEA4335), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Name (signup only)
              if (!_isLogin) ...[
                _buildField(
                  controller: _nameCtrl,
                  label: 'Your Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 14),
              ],

              // Email
              _buildField(
                controller: _emailCtrl,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 14),

              // Password
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              // PIN setup section (signup only)
              if (!_isLogin) ...[
                const SizedBox(height: 24),

                // Divider + label
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 15, color: Color(0xFF5F6368)),
                          const SizedBox(width: 4),
                          Text(
                            'Safety PIN',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF5F6368),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 8),

                Text(
                  'Choose a 4-digit PIN. You\'ll need this to delete the app.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF5F6368),
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 16),

                // PIN field with live dots
                _PinField(
                  controller: _pinCtrl,
                  lengthNotifier: _pinLength,
                  label: 'Safety PIN (4 digits)',
                ),

                const SizedBox(height: 12),

                _PinField(
                  controller: _pinConfirmCtrl,
                  lengthNotifier: _pinConfirmLength,
                  label: 'Confirm PIN',
                ),
              ],

              const SizedBox(height: 28),

              // Submit button
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34A853),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _isLogin ? 'Sign In' : 'Create Account',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _isLogin = !_isLogin;
                    _error = null;
                    _pinCtrl.clear();
                    _pinConfirmCtrl.clear();
                  }),
                  child: Text(
                    _isLogin
                        ? 'Don\'t have an account? Sign Up'
                        : 'Already have an account? Sign In',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF34A853),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
        prefixIcon: Icon(icon),
      ),
    );
  }
}

// ─── PIN field with live dot indicator ────────────────────────────────────────
class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final ValueNotifier<int> lengthNotifier;
  final String label;

  const _PinField({
    required this.controller,
    required this.lengthNotifier,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dot indicators
        ValueListenableBuilder<int>(
          valueListenable: lengthNotifier,
          builder: (_, len, __) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < len;
                return Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? const Color(0xFF34A853)
                        : const Color(0xFFE8EAED),
                    border: Border.all(
                      color: filled
                          ? const Color(0xFF34A853)
                          : const Color(0xFFBDC1C6),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(height: 10),
        // Hidden numeric input
        TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.pin_outlined),
            counterText: '',
          ),
        ),
      ],
    );
  }
}
