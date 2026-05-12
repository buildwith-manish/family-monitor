import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/screen_capture_channel.dart';

class ChildSetupWizardScreen extends StatefulWidget {
  final String? childUid;
  const ChildSetupWizardScreen({super.key, this.childUid});

  @override
  State<ChildSetupWizardScreen> createState() => _ChildSetupWizardScreenState();
}

class _ChildSetupWizardScreenState extends State<ChildSetupWizardScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;
  bool _loading = false;
  String? _error;

  final _nameCtrl   = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _auth       = AuthService();

  static const int _totalPages = 5;

  bool _cameraGranted    = false;
  bool _micGranted       = false;
  bool _notifGranted     = false;
  bool _batteryExempt    = false;
  bool _screenConsented  = false;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _refreshStatus();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final cam   = await Permission.camera.isGranted;
    final mic   = await Permission.microphone.isGranted;
    final notif = await Permission.notification.isGranted;
    final batt  = await ScreenCaptureChannel.isBatteryOptimizationExempt();
    if (!mounted) return;
    setState(() {
      _cameraGranted   = cam;
      _micGranted      = mic;
      _notifGranted    = notif;
      _batteryExempt   = batt;
    });
  }

  Future<void> _requestCorePermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();
    await _refreshStatus();
  }

  Future<void> _requestBattery() async {
    await ScreenCaptureChannel.requestBatteryOptimizationExemption();
    await Future.delayed(const Duration(milliseconds: 800));
    await _refreshStatus();
  }

  Future<void> _requestScreenCapture() async {
    final granted = await ScreenCaptureChannel.requestScreenCapture();
    if (!mounted) return;
    setState(() => _screenConsented = granted);
  }

  void _next() {
    if (_currentPage == _totalPages - 1) { _finish(); return; }
    _pageCtrl.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  Future<void> _finish() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _auth.currentUser?.uid ?? widget.childUid;
      if (uid == null || uid.isEmpty) {
        setState(() { _error = 'Session expired. Please sign in again.'; _loading = false; });
        return;
      }
      final deviceName = _deviceCtrl.text.trim().isEmpty ? 'My Phone' : _deviceCtrl.text.trim();
      await FirebaseDatabase.instance.ref('users/$uid').update({
        'childName':  _nameCtrl.text.trim(),
        'deviceName': deviceName,
        'role':       'child',
        'isOnline':   false,
      });
      await BackgroundMonitoringService.saveChildUid(uid);
      await BackgroundMonitoringService.setWizardDone(true);
      await BackgroundMonitoringService.savePermissionsGranted(true);
      try { await FirebaseDatabase.instance.ref('calls/$uid').remove(); } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/child/home');
      Future.microtask(() async {
        try { await BackgroundMonitoringService.startService(); } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Setup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _PageWelcome(),
                  _PageFeatures(),
                  _PagePermissions(
                    cameraGranted: _cameraGranted,
                    micGranted:    _micGranted,
                    notifGranted:  _notifGranted,
                    onRequest:     _requestCorePermissions,
                  ),
                  _PageBatteryScreen(
                    batteryExempt:   _batteryExempt,
                    screenConsented: _screenConsented,
                    onBattery:       _requestBattery,
                    onScreen:        _requestScreenCapture,
                  ),
                  _PageProfile(
                    nameCtrl:   _nameCtrl,
                    deviceCtrl: _deviceCtrl,
                    error:      _error,
                  ),
                ],
              ),
            ),
            _buildNavButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(children: [
        Row(children: [
          GestureDetector(
            onTap: _currentPage > 0 ? _prev : () => Navigator.pop(context),
            child: Icon(
              _currentPage > 0 ? Icons.arrow_back_ios : Icons.close,
              size: 20, color: const Color(0xFF5F6368),
            ),
          ),
          const Spacer(),
          Text('Step ${_currentPage + 1} of $_totalPages',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF5F6368))),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_currentPage + 1) / _totalPages,
            backgroundColor: Colors.grey.shade200,
            color: const Color(0xFF34A853),
            minHeight: 6,
          ),
        ),
      ]),
    );
  }

  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _loading ? null : _next,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34A853)),
          child: _loading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(
                  _currentPage == _totalPages - 1 ? 'Complete Setup' : 'Continue',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 1 — Welcome
// ─────────────────────────────────────────────────────────────
class _PageWelcome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 40),
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4EA),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(Icons.security, size: 56, color: Color(0xFF34A853)),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 32),
        Text('Family Monitor',
            style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800,
                color: const Color(0xFF202124)))
            .animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 12),
        Text('This app lets your parent keep you safe by monitoring this device transparently.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF5F6368), height: 1.6))
            .animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 32),
        const _InfoRow(icon: Icons.visibility, text: 'Your parent can see live camera & screen'),
        const _InfoRow(icon: Icons.mic,        text: 'Audio monitoring when active'),
        const _InfoRow(icon: Icons.lock,       text: 'Device can be locked remotely'),
        const _InfoRow(icon: Icons.camera_alt, text: 'Periodic snapshots may be taken'),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: const Color(0xFF34A853)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(text,
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF3C4043)))),
      ]),
    );
  }
}
