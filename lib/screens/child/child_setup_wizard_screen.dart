import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/screen_capture_channel.dart';

class ChildSetupWizardScreen
    extends StatefulWidget {
  final String? childUid;

  const ChildSetupWizardScreen({
    super.key,
    this.childUid,
  });

  @override
  State<ChildSetupWizardScreen>
      createState() =>
          _ChildSetupWizardScreenState();
}

class _ChildSetupWizardScreenState
    extends State<
        ChildSetupWizardScreen> {
  late final PageController
      _pageCtrl;

  int _currentPage = 0;

  bool _loading = false;

  String? _error;

  final TextEditingController
      _nameCtrl =
      TextEditingController();

  final TextEditingController
      _deviceCtrl =
      TextEditingController();

  final AuthService _auth =
      AuthService();

  static const int _totalPages =
      5;

  bool _screenCaptureConsented =
      false;

  bool _batteryExempt = false;

  @override
  void initState() {
    super.initState();

    _pageCtrl = PageController();

    _checkBatteryAndScreenStatus();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();

    _nameCtrl.dispose();
    _deviceCtrl.dispose();

    super.dispose();
  }

  void _next() {
    if (_currentPage ==
        _totalPages - 1) {
      _finish();

      return;
    }

    _pageCtrl.nextPage(
      duration: const Duration(
        milliseconds: 400,
      ),
      curve: Curves.easeInOut,
    );
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(
          milliseconds: 400,
        ),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void>
      _requestPermissions() async {
    final List<Permission>
        permissions =
        <Permission>[
      Permission.camera,
      Permission.microphone,
    ];

    // Notification permission intentionally removed

    await permissions.request();
  }

  Future<void>
      _checkBatteryAndScreenStatus() async {
    final bool exempt =
        await ScreenCaptureChannel
            .isBatteryOptimizationExempt();

    if (!mounted) {
      return;
    }

    setState(() {
      _batteryExempt =
          exempt;
    });
  }

  Future<void>
      _requestBatteryExemption() async {
    await ScreenCaptureChannel
        .requestBatteryOptimizationExemption();

    await Future.delayed(
      const Duration(seconds: 1),
    );

    await _checkBatteryAndScreenStatus();
  }

  Future<void>
      _requestScreenCaptureConsent() async {
    final bool granted =
        await ScreenCaptureChannel
            .requestScreenCapture();

    if (!mounted) {
      return;
    }

    setState(() {
      _screenCaptureConsented =
          granted;
    });
  }

  Future<void> _finish() async {
    if (_nameCtrl.text
        .trim()
        .isEmpty) {
      setState(() {
        _error =
            'Please enter your name';
      });

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String? uid =
          _auth.currentUser?.uid ??
              widget.childUid;

      if (uid == null ||
          uid.isEmpty) {
        setState(() {
          _error =
              'Session expired. Please sign in again.';
          _loading = false;
        });

        return;
      }

      final String deviceName =
          _deviceCtrl.text
                  .trim()
                  .isEmpty
              ? 'My Phone'
              : _deviceCtrl.text
                  .trim();

      await FirebaseDatabase
          .instance
          .ref('users/$uid')
          .update({
        'childName':
            _nameCtrl.text.trim(),
        'deviceName':
            deviceName,
        'role': 'child',
        'isOnline': false,
      });

      await BackgroundMonitoringService
          .saveChildUid(uid);

      await BackgroundMonitoringService
          .setWizardDone(true);

      await BackgroundMonitoringService
          .savePermissionsGranted(
        true,
      );

      try {
        await FirebaseDatabase
            .instance
            .ref('calls/$uid')
            .remove();
      } catch (_) {}

      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        '/child/home',
      );

      Future.microtask(() async {
        try {
          await BackgroundMonitoringService
              .startService();
        } catch (e) {
          debugPrint(
            'Background service failed: $e',
          );
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'Setup failed: $e';
      });
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF8FAFB,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),

            Expanded(
              child: PageView(
                controller:
                    _pageCtrl,
                physics:
                    const NeverScrollableScrollPhysics(),
                onPageChanged:
                    (int index) {
                  setState(() {
                    _currentPage =
                        index;
                  });
                },
                children: [
                  const _WizardPage1(),
                  const _WizardPage2(),
                  _WizardPage3(
                    onRequestPermissions:
                        _requestPermissions,
                  ),
                  _WizardPage3b(
                    screenCaptureConsented:
                        _screenCaptureConsented,
                    batteryExempt:
                        _batteryExempt,
                    onRequestScreenCapture:
                        _requestScreenCaptureConsent,
                    onRequestBattery:
                        _requestBatteryExemption,
                  ),
                  _WizardPage4(
                    nameCtrl:
                        _nameCtrl,
                    deviceCtrl:
                        _deviceCtrl,
                    error: _error,
                    loading:
                        _loading,
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
      padding:
          const EdgeInsets.fromLTRB(
        24,
        16,
        24,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (_currentPage > 0)
                GestureDetector(
                  onTap: _prev,
                  child: const Icon(
                    Icons
                        .arrow_back_ios,
                    size: 18,
                    color: Color(
                      0xFF5F6368,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () {
                    Navigator.pop(
                      context,
                    );
                  },
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: Color(
                      0xFF5F6368,
                    ),
                  ),
                ),

              const Spacer(),

              Text(
                'Step ${_currentPage + 1} of $_totalPages',
                style:
                    GoogleFonts.inter(
                  fontSize: 12,
                  color:
                      const Color(
                    0xFF5F6368,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              4,
            ),
            child:
                LinearProgressIndicator(
              value:
                  (_currentPage +
                          1) /
                      _totalPages,
              backgroundColor:
                  Colors.grey
                      .shade200,
              color:
                  const Color(
                0xFF34A853,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed:
              _loading
                  ? null
                  : _next,
          style:
              ElevatedButton.styleFrom(
            backgroundColor:
                const Color(
              0xFF34A853,
            ),
          ),
          child:
              _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2.5,
                        color: Colors
                            .white,
                      ),
                    )
                  : Text(
                      _currentPage ==
                              _totalPages -
                                  1
                          ? 'Complete Setup'
                          : 'Continue',
                      style:
                          GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight:
                            FontWeight
                                .w600,
                        color: Colors
                            .white,
                      ),
                    ),
        ),
      ),
    );
  }
}

class _WizardPage1
    extends StatelessWidget {
  const _WizardPage1();

  @override
  Widget build(
    BuildContext context,
  ) {
    return const Center(
      child: Text(
        'Welcome to Family Monitor',
      ),
    );
  }
}

class _WizardPage2
    extends StatelessWidget {
  const _WizardPage2();

  @override
  Widget build(
    BuildContext context,
  ) {
    return const Center(
      child: Text(
        'Monitoring Features',
      ),
    );
  }
}

class _WizardPage3
    extends StatelessWidget {
  final Future<void>
      Function()
      onRequestPermissions;

  const _WizardPage3({
    required this
        .onRequestPermissions,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child: ElevatedButton(
        onPressed:
            onRequestPermissions,
        child: const Text(
          'Grant Permissions',
        ),
      ),
    );
  }
}

class _WizardPage3b
    extends StatelessWidget {
  final bool
      screenCaptureConsented;

  final bool batteryExempt;

  final VoidCallback
      onRequestScreenCapture;

  final VoidCallback
      onRequestBattery;

  const _WizardPage3b({
    required this
        .screenCaptureConsented,
    required this
        .batteryExempt,
    required this
        .onRequestScreenCapture,
    required this
        .onRequestBattery,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return const Center(
      child: Text(
        'Screen Sharing Setup',
      ),
    );
  }
}

class _WizardPage4
    extends StatelessWidget {
  final TextEditingController
      nameCtrl;

  final TextEditingController
      deviceCtrl;

  final String? error;

  final bool loading;

  const _WizardPage4({
    required this.nameCtrl,
    required this.deviceCtrl,
    required this.loading,
    this.error,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.all(
        24,
      ),
      child: Column(
        children: [
          TextField(
            controller:
                nameCtrl,
            decoration:
                const InputDecoration(
              hintText:
                  'Your Name',
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          TextField(
            controller:
                deviceCtrl,
            decoration:
                const InputDecoration(
              hintText:
                  'Device Name',
            ),
          ),

          if (error != null)
            Padding(
              padding:
                  const EdgeInsets.only(
                top: 16,
              ),
              child: Text(
                error!,
              ),
            ),
        ],
      ),
    );
  }
}
