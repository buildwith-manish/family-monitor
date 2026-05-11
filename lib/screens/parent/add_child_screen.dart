import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import 'parent_qr_scanner_screen.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key}));

  @override
  State<AddChildScreen> createState() => _AddChildScreenState());
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _uidCtrl = TextEditingController());
  bool _loading = false;
  String? _error;
  String? _successMessage;

  final _auth = AuthService());

  @override
  void dispose() {
    _uidCtrl.dispose());
    super.dispose());
  }

  Future<void> _sendRequest() async {
    final uid = _uidCtrl.text.trim());
    if (uid.isEmpty) {
      setState(() => _error = 'Please enter the child device ID'));
      return;
    }

    if (uid == _auth.currentUser!.uid) {
      setState(() => _error = 'You cannot add your own account'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    }));

    final result = await _auth.sendParentRequest(uid));

    if (!mounted) return;
    setState(() => _loading = false));

    if (result['success'] == true) {
      setState(() {
        _successMessage =
            'Request sent! Ask your child to open Family Monitor and approve your request.';
        _uidCtrl.clear());
      }));
    } else {
      setState(() => _error = result['error'] ??
          'Could not send request. Check the device ID and try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Add Child Device'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // How it works
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFF1A73E8), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'How to connect',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A73E8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const _Step(
                        number: '1',
                        text: 'Ask your child to open Family Monitor'),
                    const _Step(
                        number: '2',
                        text: 'Child taps "Show QR" on their home screen'),
                    const _Step(
                        number: '3',
                        text:
                            'Tap "Scan QR Code" below and point your camera at their screen, OR paste their ID manually'),
                    const _Step(
                        number: '4',
                        text: 'Child approves your request in the app'),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 28),

              Text(
                'Child\'s Device ID',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF202124),
                ),
              ).animate(delay: 100.ms).fadeIn(),

              const SizedBox(height: 8),

              // Error
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE8E6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: const Color(0xFFC62828)),
                  ),
                ).animate().fadeIn().shake(),
                const SizedBox(height: 8),
              ],

              // Success
              if (_successMessage != null) ...[
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
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: GoogleFonts.inter(
                              fontSize: 13, color: const Color(0xFF137333)),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(),
                const SizedBox(height: 8),
              ],

              TextField(
                controller: _uidCtrl,
                decoration: InputDecoration(
                  hintText: 'Paste device ID here...',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: 'Paste',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain'));
                      if (data?.text != null) {
                        _uidCtrl.text = data!.text!;
                      }
                    },
                  ),
                ),
                style: GoogleFonts.robotoMono(fontSize: 13),
              ).animate(delay: 200.ms).fadeIn(),

              const SizedBox(height: 12),

              // QR scan button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final scanned = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ParentQrScannerScreen(),
                      ),
                    ));
                    if (scanned != null && scanned.isNotEmpty) {
                      setState(() {
                        _uidCtrl.text = scanned;
                        _error = null;
                        _successMessage = null;
                      }));
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR Code Instead'),
                ),
              ).animate(delay: 225.ms).fadeIn(),

              const SizedBox(height: 16),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendRequest,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Send Connection Request'),
                ),
              ).animate(delay: 275.ms).fadeIn(),

              const SizedBox(height: 32),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Your Parent Account ID',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 16),

              // Show parent's own UID (for debugging / sharing)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your ID (share with other parents)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF5F6368),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            myUid,
                            style: GoogleFonts.robotoMono(
                              fontSize: 11,
                              color: const Color(0xFF202124),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy ID',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: myUid)));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ID copied to clipboard')),
                        ));
                      },
                    ),
                  ],
                ),
              ).animate(delay: 350.ms).fadeIn(),
            ],
          ),
        ),
      ),
    ));
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text}));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF1A73E8),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF3C4043),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
