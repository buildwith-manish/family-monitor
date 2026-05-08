import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/auth_service.dart';

class ChildSetupWizardScreen extends StatefulWidget {
  const ChildSetupWizardScreen({super.key});

  @override
  State<ChildSetupWizardScreen> createState() => _ChildSetupWizardScreenState();
}

class _ChildSetupWizardScreenState extends State<ChildSetupWizardScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  bool _loading = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();

  final _auth = AuthService();

  static const int _totalPages = 4;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _totalPages - 1) {
      if (_currentPage == 3) {
        _finish();
        return;
      }
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  Future<void> _finish() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final deviceName = _deviceCtrl.text.trim().isEmpty
        ? 'My Phone'
        : _deviceCtrl.text.trim();

    final result = await _auth.setupChildDevice(
      childName: _nameCtrl.text.trim(),
      deviceName: deviceName,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      Navigator.pushReplacementNamed(context, '/child/home');
    } else {
      setState(() => _error = result['error'] ?? 'Setup failed. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            _buildProgressBar(),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _WizardPage1(),
                  _WizardPage2(),
                  _WizardPage3(onRequestPermissions: _requestPermissions),
                  _WizardPage4(
                    nameCtrl: _nameCtrl,
                    deviceCtrl: _deviceCtrl,
                    error: _error,
                    loading: _loading,
                  ),
                ],
              ),
            ),

            // Navigation buttons
            _buildNavButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Row(
            children: [
              if (_currentPage > 0)
                GestureDetector(
                  onTap: _prev,
                  child: const Icon(Icons.arrow_back_ios,
                      size: 18, color: Color(0xFF5F6368)),
                )
              else
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close,
                      size: 20, color: Color(0xFF5F6368)),
                ),
              const Spacer(),
              Text(
                'Step ${_currentPage + 1} of $_totalPages',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF5F6368),
                ),
              ),
            ],
          ),
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
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _loading ? null : _next,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF34A853),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  _currentPage == _totalPages - 1
                      ? 'Complete Setup'
                      : 'Continue',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Page 1: What is Family Monitor ──────────────────────────────────────────────
class _WizardPage1 extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.visibility,
                size: 44,
                color: Color(0xFF34A853),
              ),
            ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          ),
          const SizedBox(height: 24),
          Text(
            'Family Monitor keeps your family safe — openly',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
              letterSpacing: -0.3,
              height: 1.3,
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2, end: 0),
          const SizedBox(height: 16),
          Text(
            'This app lets your parent monitor this device. Unlike hidden parental controls, everything here is transparent — you always know when monitoring is active.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
              height: 1.6,
            ),
          ).animate(delay: 300.ms).fadeIn(),
          const SizedBox(height: 28),
          ...[
            ['👁️', 'You always know', 'A notification is always visible when monitoring is on.'],
            ['✋', 'You control access', 'You must approve each parent before they can monitor.'],
            ['🛑', 'You can stop', 'You can disable monitoring at any time from this app.'],
          ].asMap().entries.map(
            (e) => _FeatureRow(
              emoji: e.value[0],
              title: e.value[1],
              desc: e.value[2],
              delay: 400 + (e.key * 100),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 2: What will be monitored ──────────────────────────────────────────────
class _WizardPage2 extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'What your parent can see',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
              letterSpacing: -0.3,
            ),
          ).animate().fadeIn().slideY(begin: 0.2, end: 0),
          const SizedBox(height: 8),
          Text(
            'Only when you\'re connected to an approved parent:',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
            ),
          ).animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 24),
          ...[
            [Icons.videocam, 'Camera', 'Live video from your front or back camera'],
            [Icons.mic, 'Microphone', 'Live audio from this device'],
            [Icons.screen_share, 'Screen', 'Live view of what\'s on your screen'],
            [Icons.wifi, 'Online status', 'Whether this device is active'],
          ].asMap().entries.map(
            (e) => _MonitorItem(
              icon: e.value[0] as IconData,
              title: e.value[1] as String,
              desc: e.value[2] as String,
              delay: 200 + (e.key * 100),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFCC02), width: 1),
            ),
            child: Text(
              'Note: Monitoring only works when the Family Monitor app is open and you\'ve approved a parent. You see a notification whenever it\'s active.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF6D4C41),
                height: 1.5,
              ),
            ),
          ).animate(delay: 700.ms).fadeIn(),
        ],
      ),
    );
  }
}

// ── Page 3: Permissions ──────────────────────────────────────────────────────────
class _WizardPage3 extends StatefulWidget {
  final VoidCallback onRequestPermissions;
  const _WizardPage3({required this.onRequestPermissions});

  @override
  State<_WizardPage3> createState() => _WizardPage3State();
}

class _WizardPage3State extends State<_WizardPage3> {
  bool _cameraGranted = false;
  bool _micGranted = false;

  Future<void> _checkAndRequest() async {
    
    final camStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    setState(() {
      _cameraGranted = camStatus.isGranted;
      _micGranted = micStatus.isGranted;
    });
  }

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final camStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    setState(() {
      _cameraGranted = camStatus.isGranted;
      _micGranted = micStatus.isGranted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Grant permissions',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
            ),
          ).animate().fadeIn().slideY(begin: 0.2, end: 0),
          const SizedBox(height: 8),
          Text(
            'Family Monitor needs these to enable monitoring:',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
            ),
          ).animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 28),
          _PermissionRow(
            icon: Icons.videocam,
            title: 'Camera',
            desc: 'For live video streaming',
            granted: _cameraGranted,
            delay: 200,
          ),
          _PermissionRow(
            icon: Icons.mic,
            title: 'Microphone',
            desc: 'For audio monitoring',
            granted: _micGranted,
            delay: 300,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkAndRequest,
              icon: const Icon(Icons.security),
              label: const Text('Grant Permissions'),
            ),
          ).animate(delay: 400.ms).fadeIn(),
          if (_cameraGranted && _micGranted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF34A853), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'All permissions granted! Ready to continue.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF137333),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(),
          ],
        ],
      ),
    );
  }
}

// ── Page 4: Enter name ───────────────────────────────────────────────────────────
class _WizardPage4 extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController deviceCtrl;
  final String? error;
  final bool loading;

  const _WizardPage4({
    required this.nameCtrl,
    required this.deviceCtrl,
    this.error,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Almost done!',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
            ),
          ).animate().fadeIn().slideY(begin: 0.2, end: 0),
          const SizedBox(height: 8),
          Text(
            'Enter your name so your parent can identify this device.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
              height: 1.4,
            ),
          ).animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 28),

          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE8E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                error!,
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFFC62828)),
              ),
            ).animate().fadeIn().shake(),
            const SizedBox(height: 16),
          ],

          Text(
            'Your Name',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF3C4043),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Alex',
              prefixIcon: Icon(Icons.child_care),
            ),
          ).animate(delay: 200.ms).fadeIn(),
          const SizedBox(height: 20),
          Text(
            'Device Name (optional)',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF3C4043),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: deviceCtrl,
            decoration: const InputDecoration(
              hintText: 'e.g. Alex\'s Samsung Galaxy',
              prefixIcon: Icon(Icons.smartphone),
            ),
          ).animate(delay: 300.ms).fadeIn(),
        ],
      ),
    );
  }
}

// ── Shared subwidgets ─────────────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;
  final int delay;

  const _FeatureRow({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF202124),
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF5F6368),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn().slideX(begin: -0.1, end: 0);
  }
}

class _MonitorItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final int delay;

  const _MonitorItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF1A73E8), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF202124),
                    ),
                  ),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF5F6368),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn().slideX(begin: -0.1, end: 0);
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool granted;
  final int delay;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: granted
                  ? const Color(0xFFE6F4EA)
                  : const Color(0xFFF1F3F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: granted
                  ? const Color(0xFF34A853)
                  : const Color(0xFF5F6368),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF202124),
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF5F6368),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? const Color(0xFF34A853) : Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn().slideX(begin: -0.1, end: 0);
  }
}
