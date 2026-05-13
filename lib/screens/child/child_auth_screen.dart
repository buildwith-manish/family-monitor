import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';

import 'child_home_screen.dart';
import 'child_setup_wizard_screen.dart';

class ChildAuthScreen extends StatefulWidget {
  const ChildAuthScreen({super.key});

  @override
  State<ChildAuthScreen> createState() =>
      _ChildAuthScreenState();
}

class _ChildAuthScreenState
    extends State<ChildAuthScreen> {
  final AuthService _auth = AuthService();

  final TextEditingController _emailCtrl =
      TextEditingController();

  final TextEditingController _passCtrl =
      TextEditingController();

  final TextEditingController _nameCtrl =
      TextEditingController();

  bool _isLogin = true;
  bool _loading = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAlreadyLoggedIn();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();

    super.dispose();
  }

  Future<void> _checkAlreadyLoggedIn() async {
    final String? uid =
        _auth.currentUser?.uid;

    if (uid == null) {
      return;
    }

    final bool wizardDone =
        await BackgroundMonitoringService
            .isWizardDone();

    if (!mounted) {
      return;
    }

    if (wizardDone) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const ChildHomeScreen(),
        ),
      );
    }
  }

  Future<void> _submit() async {
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
          _error =
              result['error']?.toString() ??
                  'Authentication failed.';
        });

        return;
      }

      final String? uid =
          _auth.currentUser?.uid;

      if (uid == null) {
        setState(() {
          _error =
              'Authentication failed.';
        });

        return;
      }

      await BackgroundMonitoringService
          .saveChildUid(uid);

      try {
        await FirebaseMessaging.instance
            .getToken()
            .timeout(
              const Duration(seconds: 5),
            );
      } catch (_) {}

      if (!mounted) {
        return;
      }

      final bool wizardDone =
          await BackgroundMonitoringService
              .isWizardDone();

      if (!mounted) {
        return;
      }

      if (!wizardDone) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChildSetupWizardScreen(
              childUid: uid,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const ChildHomeScreen(),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e
            .toString()
            .replaceAll(
              'Exception: ',
              '',
            );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF8FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF34A853,
                  ).withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                ),
                child: const Icon(
                  Icons.child_care,
                  color:
                      Color(0xFF34A853),
                  size: 36,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                _isLogin
                    ? 'Child Sign In'
                    : 'Create Child Account',
                style:
                    GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      const Color(
                    0xFF202124,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _isLogin
                    ? 'Sign in to your child account'
                    : 'Set up your child profile',
                style:
                    GoogleFonts.inter(
                  fontSize: 14,
                  color:
                      const Color(
                    0xFF5F6368,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              if (!_isLogin) ...[
                TextField(
                  controller: _nameCtrl,
                  decoration:
                      InputDecoration(
                    labelText:
                        'Your Name',
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                    prefixIcon:
                        const Icon(
                      Icons
                          .person_outline,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],

              TextField(
                controller: _emailCtrl,
                keyboardType:
                    TextInputType
                        .emailAddress,
                decoration:
                    InputDecoration(
                  labelText: 'Email',
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                  prefixIcon:
                      const Icon(
                    Icons.email_outlined,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration:
                    InputDecoration(
                  labelText:
                      'Password',
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                  prefixIcon:
                      const Icon(
                    Icons.lock_outline,
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),

                Text(
                  _error!,
                  style:
                      const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _loading
                          ? null
                          : _submit,
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(
                      0xFF34A853,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                  ),
                  child:
                      _loading
                          ? const CircularProgressIndicator(
                              color:
                                  Colors.white,
                            )
                          : Text(
                              _isLogin
                                  ? 'Sign In'
                                  : 'Create Account',
                              style:
                                  GoogleFonts.inter(
                                fontSize:
                                    16,
                                fontWeight:
                                    FontWeight
                                        .w600,
                                color:
                                    Colors
                                        .white,
                              ),
                            ),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin =
                          !_isLogin;

                      _error = null;
                    });
                  },
                  child: Text(
                    _isLogin
                        ? 'Don\'t have an account? Sign Up'
                        : 'Already have an account? Sign In',
                    style:
                        GoogleFonts.inter(
                      color:
                          const Color(
                        0xFF34A853,
                      ),
                      fontWeight:
                          FontWeight.w600,
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
}
