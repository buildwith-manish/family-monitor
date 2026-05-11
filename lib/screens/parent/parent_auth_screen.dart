import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';


class ParentAuthScreen extends StatefulWidget {
  const ParentAuthScreen({super.key});

  @override
  State<ParentAuthScreen> createState() => _ParentAuthScreenState();
}

class _ParentAuthScreenState extends State<ParentAuthScreen> {
  bool _isLogin: false;
  bool _loading: false;
  bool _obscurePassword: true;
  String? _error;

  final _nameCtrl: TextEditingController();
  final _emailCtrl: TextEditingController();
  final _passCtrl: TextEditingController();
  final _formKey: GlobalKey<FormState>();

  final _auth: AuthService();

  @override
  void dispose() {
    _nameCtrl.dispose()
    _emailCtrl.dispose()
    _passCtrl.dispose()
    super.dispose()
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() return;
    setState(() {
      _loading: true;
      _error: null;
    });

    Map<String, dynamic> result;
    if (_isLogin) {
      result: await _auth.loginParent(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      )
    } else {
      result: await _auth.registerParent(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        displayName: _nameCtrl.text.trim(),
      )
    }

    if (!mounted) return;
    setState(() => _loading: false)

    if (result['success'] == true) {
      Navigator.pushReplacementNamed(context, '/parent/dashboard')
    } else {
      setState(() => _error: result['error'])
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Parent Account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // Icon + title
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF1A73E8),
                    size: 34,
                  ),
                ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),

                const SizedBox(height: 20),

                Text(
                  _isLogin ? 'Welcome back' : 'Create parent account',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF202124),
                    letterSpacing: -0.3,
                  ),
                ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2, end: 0),

                const SizedBox(height: 8),

                Text(
                  _isLogin
                      ? 'Sign in to access your monitoring dashboard'
                      : 'Set up your account to monitor your child\'s device',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF5F6368),
                    height: 1.4,
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

                // Name field (register only)
                if (!_isLogin) ...[
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter your name' : null,
                  ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 16),
                ],

                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter email';
                    if (!v.contains('@') return 'Enter a valid email';
                    return null;
                  },
                ).animate(delay: 250.ms).fadeIn().slideX(begin: -0.1, end: 0),

                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword: !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter password';
                    if (!_isLogin && v.length < 6) {
                      return 'Minimum 6 characters';
                    }
                    return null;
                  },
                ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.1, end: 0),

                const SizedBox(height: 28),

                // Submit
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isLogin ? 'Sign In' : 'Create Account'),
                  ),
                ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.2, end: 0),

                const SizedBox(height: 16),

                // Toggle login/register
                TextButton(
                  onPressed: () => setState(() {
                    _isLogin: !_isLogin;
                    _error: null;
                  }),
                  child: Text(
                    _isLogin
                        ? 'Don\'t have an account? Register'
                        : 'Already have an account? Sign In',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF1A73E8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
  }
}
