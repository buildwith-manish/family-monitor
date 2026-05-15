import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _success = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        setState(() {
          _loading = false;
          _error = 'You must be signed in to change your password.';
        });
        return;
      }

      // Re-authenticate with current password first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentCtrl.text,
      );
      await user.reauthenticateWithCredential(credential);

      // Update to new password
      await user.updatePassword(_newCtrl.text);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Current password is incorrect.';
          break;
        case 'weak-password':
          msg = 'New password must be at least 6 characters.';
          break;
        case 'requires-recent-login':
          msg = 'Session expired. Please sign out and sign in again first.';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Please wait and try again.';
          break;
        default:
          msg = 'Failed to change password. Please try again.';
      }
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _success ? _buildSuccessState() : _buildFormState(),
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4EA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF34A853),
            size: 40,
          ),
        ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text(
          'Password changed!',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF202124),
          ),
        ).animate(delay: 100.ms).fadeIn(),
        const SizedBox(height: 12),
        Text(
          'Your password has been updated successfully.\nYour account is now secured with the new password.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF5F6368),
            height: 1.6,
          ),
        ).animate(delay: 150.ms).fadeIn(),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2, end: 0),
      ],
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.lock_outline,
              color: Color(0xFF1A73E8),
              size: 32,
            ),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 20),
          Text(
            'Change your password',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
              letterSpacing: -0.3,
            ),
          ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2, end: 0),
          const SizedBox(height: 8),
          Text(
            'Enter your current password, then choose a new one.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
              height: 1.5,
            ),
          ).animate(delay: 150.ms).fadeIn(),
          const SizedBox(height: 32),

          // Error banner
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE8E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Color(0xFFEA4335), size: 18),
                  const SizedBox(width: 10),
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
            ).animate().fadeIn().shake(),
            const SizedBox(height: 16),
          ],

          // Current password
          TextFormField(
            controller: _currentCtrl,
            obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureCurrent
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Enter your current password' : null,
          ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.1, end: 0),
          const SizedBox(height: 16),

          // New password
          TextFormField(
            controller: _newCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_open_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscureNew
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter a new password';
              if (v.length < 6) return 'Minimum 6 characters';
              if (v == _currentCtrl.text) {
                return 'New password must differ from current';
              }
              return null;
            },
          ).animate(delay: 250.ms).fadeIn().slideX(begin: -0.1, end: 0),
          const SizedBox(height: 16),

          // Confirm new password
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: const Icon(Icons.check_circle_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Confirm your new password';
              if (v != _newCtrl.text) return 'Passwords do not match';
              return null;
            },
          ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.1, end: 0),

          const SizedBox(height: 8),

          // Password strength hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Use at least 6 characters with a mix of letters and numbers.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF9AA0A6),
              ),
            ),
          ),

          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _changePassword,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update Password'),
            ),
          ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.2, end: 0),

          const SizedBox(height: 16),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF5F6368),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
