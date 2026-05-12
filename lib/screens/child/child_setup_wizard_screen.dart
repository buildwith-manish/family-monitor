import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/battery_service.dart';
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
  final _batterySvc = BatteryService();

  static const int _totalPages = 5;

  bool _cameraGranted   = false;
  bool _micGranted      = false;
  bool _notifGranted    = false;
  bool _batteryExempt   = false;
  bool _screenConsented = false;
  ManufacturerGuide? _guide;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _refreshStatus();
    _loadGuide();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGuide() async {
    final g = await _batterySvc.getManufacturerGuide();
    if (!mounted) return;
    setState(() => _guide = g);
  }

  Future<void> _refreshStatus() async {
    final cam   = await Permission.camera.isGranted;
    final mic   = await Permission.microphone.isGranted;
    final notif = await Permission.notification.isGranted;
    final batt  = await ScreenCaptureChannel.isBatteryOptimizationExempt();
    if (!mounted) return;
    setState(() {
      _cameraGranted  = cam;
      _micGranted     = mic;
      _notifGranted   = notif;
      _batteryExempt  = batt;
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
    if (!mounted) return;
    await _refreshStatus();
    if (_batteryExempt) await _batterySvc.setOptimizationDone();
  }

  Future<void> _requestScreenCapture() async {
    final result = await ScreenCaptureChannel.requestScreenCapture();
    if (!mounted) return;
    setState(() => _screenConsented = result);
  }

  bool get _canProceedFromPermissions =>
      _cameraGranted && _micGranted;

  void _next() {
    if (_currentPage == 2 && !_canProceedFromPermissions) {
      setState(() => _error = 'Camera and microphone are required to continue.');
      return;
    }
    setState(() => _error = null);
    if (_currentPage == _totalPages - 1) {
      _finish();
    } else {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      setState(() => _error = null);
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name.');
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
      setState(() => _error = 'Setup failed. Please try again.');
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
                onPageChanged: (i) => setState(() { _currentPage = i; _error = null; }),
                children: [
                  const _PageWelcome(),
                  const _PageFeatures(),
                  _PagePermissions(
                    cameraGranted: _cameraGranted,
                    micGranted:    _micGranted,
                    notifGranted:  _notifGranted,
                    onRequest:     _requestCorePermissions,
                    error:         _currentPage == 2 ? _error : null,
                  ),
                  _PageBatteryScreen(
                    batteryExempt:   _batteryExempt,
                    screenConsented: _screenConsented,
                    onBattery:       _requestBattery,
                    onScreen:        _requestScreenCapture,
                    guide:           _guide,
                  ),
                  _PageProfile(
                    nameCtrl:   _nameCtrl,
                    deviceCtrl: _deviceCtrl,
                    error:      _currentPage == 4 ? _error : null,
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
    final isPermPage = _currentPage == 2;
    final blocked = isPermPage && !_canProceedFromPermissions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          if (_error != null && _currentPage != 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.red)),
            ),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: (_loading || blocked) ? null : _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF34A853),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(
                      _currentPage == _totalPages - 1 ? 'Complete Setup' : 'Continue',
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 1 — Welcome
// ─────────────────────────────────────────────────────────────
class _PageWelcome extends StatelessWidget {
  const _PageWelcome();
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
            style: GoogleFonts.plusJakartaSans(
                fontSize: 28, fontWeight: FontWeight.w800, color: const Color(0xFF202124)))
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

// ─────────────────────────────────────────────────────────────
// Page 2 — Features
// ─────────────────────────────────────────────────────────────
class _PageFeatures extends StatelessWidget {
  const _PageFeatures();
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const SizedBox(height: 32),
        Text('What your parent can do',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF202124))),
        const SizedBox(height: 24),
        const _InfoRow(icon: Icons.videocam,      text: 'Live camera streaming'),
        const _InfoRow(icon: Icons.screen_share,  text: 'Live screen viewing'),
        const _InfoRow(icon: Icons.record_voice_over, text: 'Microphone monitoring'),
        const _InfoRow(icon: Icons.lock_clock,    text: 'Screen time limits'),
        const _InfoRow(icon: Icons.location_on,   text: 'Location tracking'),
        const _InfoRow(icon: Icons.block,         text: 'App and content filtering'),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 3 — Permissions
// ─────────────────────────────────────────────────────────────
class _PagePermissions extends StatelessWidget {
  final bool cameraGranted, micGranted, notifGranted;
  final VoidCallback onRequest;
  final String? error;

  const _PagePermissions({
    required this.cameraGranted,
    required this.micGranted,
    required this.notifGranted,
    required this.onRequest,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Text('Permissions Required',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF202124))),
        const SizedBox(height: 8),
        Text('These permissions are needed for monitoring to work.',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF5F6368))),
        const SizedBox(height: 24),
        _PermRow(label: 'Camera',        granted: cameraGranted,  required: true),
        _PermRow(label: 'Microphone',    granted: micGranted,     required: true),
        _PermRow(label: 'Notifications', granted: notifGranted,   required: false),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: GoogleFonts.inter(fontSize: 13, color: Colors.red)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 48,
          child: OutlinedButton.icon(
            onPressed: onRequest,
            icon: const Icon(Icons.security, size: 18),
            label: Text('Grant Permissions',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        Text('If a permission is denied, tap "Grant" then open Settings to enable it manually.',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9AA0A6))),
      ]),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String label;
  final bool granted, required;
  const _PermRow({required this.label, required this.granted, required this.required});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? const Color(0xFF34A853) : (required ? Colors.red : Colors.grey),
            size: 22),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF3C4043))),
        if (required) ...[
          const SizedBox(width: 4),
          Text('*', style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
        const Spacer(),
        Text(granted ? 'Granted' : (required ? 'Required' : 'Optional'),
            style: GoogleFonts.inter(
                fontSize: 12,
                color: granted ? const Color(0xFF34A853) : (required ? Colors.red : Colors.grey))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 4 — Battery & Screen
// ─────────────────────────────────────────────────────────────
class _PageBatteryScreen extends StatelessWidget {
  final bool batteryExempt, screenConsented;
  final VoidCallback onBattery, onScreen;
  final ManufacturerGuide? guide;

  const _PageBatteryScreen({
    required this.batteryExempt,
    required this.screenConsented,
    required this.onBattery,
    required this.onScreen,
    this.guide,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Text('Battery & Screen',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF202124))),
        const SizedBox(height: 16),

        // Battery optimization
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(batteryExempt ? Icons.battery_full : Icons.battery_alert,
                    color: batteryExempt ? const Color(0xFF34A853) : Colors.orange),
                const SizedBox(width: 8),
                Text('Battery Optimization',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                if (batteryExempt)
                  const Icon(Icons.check_circle, color: Color(0xFF34A853), size: 18),
              ]),
              if (!batteryExempt) ...[
                const SizedBox(height: 8),
                if (guide != null) ...[
                  Text('${guide!.name} instructions:',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  ...guide!.steps.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${e.key + 1}. ${e.value}',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF5F6368))),
                  )),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  onPressed: onBattery,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34A853)),
                  child: Text('Disable Battery Optimization',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
                ),
              ],
            ]),
          ),
        ),

        const SizedBox(height: 12),

        // Screen capture consent
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(screenConsented ? Icons.screen_share : Icons.screen_share_outlined,
                    color: screenConsented ? const Color(0xFF34A853) : Colors.grey),
                const SizedBox(width: 8),
                Text('Screen Sharing',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                if (screenConsented)
                  const Icon(Icons.check_circle, color: Color(0xFF34A853), size: 18),
              ]),
              if (!screenConsented) ...[
                const SizedBox(height: 8),
                Text(
                  'Your parent will be able to view your screen when monitoring is active. '
                  'You\'ll see a notification whenever screen sharing is on.',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF5F6368)),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onScreen,
                  child: Text('Allow Screen Sharing',
                      style: GoogleFonts.inter(fontSize: 13)),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 5 — Profile
// ─────────────────────────────────────────────────────────────
class _PageProfile extends StatelessWidget {
  final TextEditingController nameCtrl, deviceCtrl;
  final String? error;
  const _PageProfile({required this.nameCtrl, required this.deviceCtrl, this.error});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Text('Your Profile',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF202124))),
        const SizedBox(height: 8),
        Text('Let your parent know who\'s using this device.',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF5F6368))),
        const SizedBox(height: 24),
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'Your Name *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: deviceCtrl,
          decoration: InputDecoration(
            labelText: 'Device Name (optional)',
            hintText: 'e.g. My Phone',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.phone_android),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: GoogleFonts.inter(fontSize: 13, color: Colors.red)),
        ],
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
