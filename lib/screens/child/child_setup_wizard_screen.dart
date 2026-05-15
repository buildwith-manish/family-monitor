import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/background_monitoring_service.dart';
import '../../services/battery_service.dart';
import '../../services/device_admin_service.dart';
import '../../services/screen_capture_channel.dart';
import '../../services/screen_time_service.dart';

class ChildSetupWizardScreen extends StatefulWidget {
  final String? childUid;

  const ChildSetupWizardScreen({
    super.key,
    this.childUid,
  });

  @override
  State<ChildSetupWizardScreen> createState() =>
      _ChildSetupWizardScreenState();
}

class _ChildSetupWizardScreenState
    extends State<ChildSetupWizardScreen>
    with WidgetsBindingObserver {
  late final PageController _pageCtrl;

  int _currentPage = 0;
  bool _loading = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();

  final _auth = AuthService();
  final _batterySvc = BatteryService();

  static const int _totalPages = 9;

  bool _cameraGranted = false;
  bool _micGranted = false;
  bool _notifGranted = false;
  bool _batteryExempt = false;
  bool _screenConsented = false;
  bool _notifDisabled = false;
  bool _adminActive = false;

  ManufacturerGuide? _guide;

  Map<String, dynamic> _pendingRequests = {};

  StreamSubscription? _requestSub;

  bool _approvalDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageCtrl = PageController();
    _refreshStatus();
    _loadGuide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_currentPage == 8) _checkNotifDisabled();
      if (_currentPage == 4) {
        DeviceAdminService.isActive().then((v) {
          if (mounted) setState(() => _adminActive = v);
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _deviceCtrl.dispose();
    _requestSub?.cancel();
    super.dispose();
  }

  Future<void> _loadGuide() async {
    final g = await _batterySvc.getManufacturerGuide();

    if (!mounted) return;

    setState(() => _guide = g);
  }

  Future<void> _refreshStatus() async {
    final cam = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted;
    final notif = await Permission.notification.isGranted;
    final batt = await ScreenCaptureChannel.isBatteryOptimizationExempt();
    final admin = await DeviceAdminService.isActive();

    if (!mounted) return;

    setState(() {
      _cameraGranted = cam;
      _micGranted = mic;
      _notifGranted = notif;
      _batteryExempt = batt;
      _adminActive = admin;
    });
  }

  Future<void> _requestDeviceAdmin() async {
    await DeviceAdminService.requestActivation();
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final active = await DeviceAdminService.isActive();
    setState(() => _adminActive = active);
  }

  Future<void> _checkNotifDisabled() async {
    final notif = await Permission.notification.isGranted;
    if (!mounted) return;
    setState(() {
      _notifDisabled = !notif;
    });
  }

  Future<void> _openNotifSettings() async {
    await openAppSettings();
    await Future.delayed(const Duration(milliseconds: 600));
    await _checkNotifDisabled();
  }

  Future<void> _requestCorePermissions() async {
    await _requestSinglePermission(
      Permission.camera,
      'Camera',
    );

    await _requestSinglePermission(
      Permission.microphone,
      'Microphone',
    );

    final notifStatus =
        await Permission.notification.request();

    if (mounted) {
      setState(() => _notifGranted = notifStatus.isGranted);
    }

    // BUG-FIX: location and usage-stats permissions were never requested
    // in the wizard, so background location tracking and app-usage reporting
    // silently failed on fresh installs.
    await _requestSinglePermission(
      Permission.locationWhenInUse,
      'Location (While Using)',
    );

    // Request background location separately — Android requires the user to
    // first grant "while in use", then "all the time" separately.
    final locStatus = await Permission.locationWhenInUse.status;
    if (locStatus.isGranted) {
      await _requestSinglePermission(
        Permission.locationAlways,
        'Location (Always)',
      );
    }

    // READ_SMS — needed for SMS sync feature.
    await _requestSinglePermission(
      Permission.sms,
      'SMS Access',
    );

    // READ_CALL_LOG — needed for call log sync.
    await _requestSinglePermission(
      Permission.phone,
      'Phone / Call Logs',
    );

    // PACKAGE_USAGE_STATS is a special permission that cannot be granted
    // via the standard permission_handler dialog — it requires the user
    // to navigate to Settings > Apps > Special app access > Usage access.
    // Request it by opening the system settings page.
    final hasUsage = await ScreenTimeService().hasPermission();
    if (!hasUsage) {
      await ScreenTimeService().requestPermission();
    }

    await _refreshStatus();
  }

  Future<void> _requestSinglePermission(
    Permission permission,
    String label,
  ) async {
    final status = await permission.request();

    if (!mounted) return;

    if (status.isPermanentlyDenied) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$label Permission Required'),
          content: Text(
            '$label permission was permanently denied. '
            'Please enable it in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);

                await openAppSettings();

                await Future.delayed(
                  const Duration(milliseconds: 500),
                );

                if (mounted) {
                  await _refreshStatus();
                }
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }

    await _refreshStatus();
  }

  Future<void> _requestBattery() async {
    await ScreenCaptureChannel
        .requestBatteryOptimizationExemption();

    await Future.delayed(
      const Duration(milliseconds: 800),
    );

    if (!mounted) return;

    await _refreshStatus();

    if (_batteryExempt) {
      await _batterySvc.setOptimizationDone();
    }
  }

  Future<void> _requestScreenCapture() async {
    final result =
        await ScreenCaptureChannel.requestScreenCapture();

    if (!mounted) return;

    setState(() => _screenConsented = result);
  }

  bool get _canProceedFromPermissions =>
      _cameraGranted && _micGranted;

  String get _childUidForQr =>
      _auth.currentUser?.uid ??
      widget.childUid ??
      '';

  void _enterQrPage() {
    final uid = _childUidForQr;

    if (uid.isEmpty) return;

    _requestSub?.cancel();

    _requestSub = FirebaseDatabase.instance
        .ref('users/$uid/pendingParentRequests')
        .onValue
        .listen((event) {
      if (!mounted) return;

      final raw = event.snapshot.value;

      if (raw == null) {
        setState(() => _pendingRequests = {});
        return;
      }

      final map =
          Map<String, dynamic>.from(raw as Map);

      setState(() => _pendingRequests = map);
    });
  }

  Future<void> _approveRequest(
    String parentUid,
  ) async {
    setState(() => _loading = true);

    try {
      final result =
          await _auth.approveParentRequest(parentUid);

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() => _approvalDone = true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Parent connected successfully!',
            ),
            backgroundColor: Color(0xFF34A853),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(
          () => _error =
              result['error'] ?? 'Approval failed.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Approval failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _declineRequest(
    String parentUid,
  ) async {
    await _auth.declineParentRequest(parentUid);

    if (!mounted) return;

    setState(() {
      _pendingRequests.remove(parentUid);
    });
  }

  void _next() {
    if (_currentPage == 2 &&
        !_canProceedFromPermissions) {
      setState(() {
        _error =
            'Camera and microphone are required.';
      });

      return;
    }

    setState(() => _error = null);

    if (_currentPage == 5) {
      _saveProfileFirst();
      return;
    }

    if (_currentPage == 6) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );

      return;
    }

    if (_currentPage == _totalPages - 1) {
      _finish();
    } else {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveProfileFirst() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter your name.';
      });

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid =
          _auth.currentUser?.uid ??
          widget.childUid;

      if (uid == null || uid.isEmpty) {
        setState(() {
          _error =
              'Session expired. Please sign in again.';
          _loading = false;
        });

        return;
      }

      final deviceName =
          _deviceCtrl.text.trim().isEmpty
              ? 'My Phone'
              : _deviceCtrl.text.trim();

      // BUG-FIX: was a set() equivalent (update with approvedParents: {})
      // which wiped all existing approved parents on every profile save.
      // Now uses update() WITHOUT the approvedParents field, and only sets
      // pendingParentRequests when there are none yet (preserving existing ones).
      final existingRequests = await _existingRequests(uid);
      await FirebaseDatabase.instance
          .ref('users/$uid')
          .update({
        'childName': _nameCtrl.text.trim(),
        'deviceName': deviceName,
        'role': 'child',
        'isOnline': false,
        if (existingRequests.isNotEmpty)
          'pendingParentRequests': existingRequests,
      });
    } catch (_) {}

    if (!mounted) return;

    setState(() => _loading = false);

    _enterQrPage();

    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<Map<String, dynamic>>
      _existingRequests(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/$uid/pendingParentRequests')
          .get();

      if (snap.value != null) {
        return Map<String, dynamic>.from(
          snap.value as Map,
        );
      }
    } catch (_) {}

    return {};
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid =
          _auth.currentUser?.uid ??
          widget.childUid;

      if (uid == null || uid.isEmpty) {
        setState(() {
          _error =
              'Session expired. Please sign in again.';
          _loading = false;
        });

        return;
      }

      await BackgroundMonitoringService
          .saveChildUid(uid);

      await BackgroundMonitoringService
          .setWizardDone(true);

      await BackgroundMonitoringService
          .savePermissionsGranted(true);

      // ICON-FIX: hideAppIcon() removed — child app icon must always be visible.

      try {
        await FirebaseDatabase.instance
            .ref('calls/$uid')
            .remove();
      } catch (_) {}

      _requestSub?.cancel();

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/child/home',
      );

      Future.delayed(
        const Duration(seconds: 1),
        () async {
          try {
            await BackgroundMonitoringService
                .startService();
          } catch (_) {}
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error =
            'Setup failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
                physics:
                    const NeverScrollableScrollPhysics(),
                onPageChanged: (i) {
                  setState(() {
                    _currentPage = i;
                    _error = null;
                  });
                },
                children: [
                  const _PageWelcome(),

                  const _PageFeatures(),

                  _PagePermissions(
                    cameraGranted:
                        _cameraGranted,
                    micGranted: _micGranted,
                    notifGranted:
                        _notifGranted,
                    onRequest:
                        _requestCorePermissions,
                    error:
                        _currentPage == 2
                            ? _error
                            : null,
                  ),

                  _PageBatteryScreen(
                    batteryExempt:
                        _batteryExempt,
                    screenConsented:
                        _screenConsented,
                    onBattery:
                        _requestBattery,
                    onScreen:
                        _requestScreenCapture,
                    guide: _guide,
                  ),

                  _PageDeviceAdmin(
                    adminActive: _adminActive,
                    onRequest: _requestDeviceAdmin,
                  ),

                  _PageProfile(
                    nameCtrl: _nameCtrl,
                    deviceCtrl:
                        _deviceCtrl,
                    error:
                        _currentPage == 4
                            ? _error
                            : null,
                  ),

                  _PageQrCode(
                    uid: _childUidForQr,
                    childName:
                        _nameCtrl
                                .text
                                .trim()
                                .isEmpty
                            ? 'Child'
                            : _nameCtrl.text
                                .trim(),
                  ),

                  _PageApproval(
                    pendingRequests:
                        _pendingRequests,
                    approvalDone:
                        _approvalDone,
                    loading: _loading,
                    error:
                        _currentPage == 6
                            ? _error
                            : null,
                    onApprove:
                        _approveRequest,
                    onDecline:
                        _declineRequest,
                  ),

                  _PageDisableNotifications(
                    notifDisabled: _notifDisabled,
                    onOpenSettings: _openNotifSettings,
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
      padding: const EdgeInsets.fromLTRB(
        24,
        16,
        24,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap:
                    _currentPage > 0
                        ? _prev
                        : () => Navigator.pop(
                            context,
                          ),
                child: Icon(
                  _currentPage > 0
                      ? Icons.arrow_back_ios
                      : Icons.close,
                  size: 20,
                  color:
                      const Color(0xFF5F6368),
                ),
              ),

              const Spacer(),

              Text(
                'Step ${_currentPage + 1} of $_totalPages',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color:
                      const Color(0xFF5F6368),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  (_currentPage + 1) /
                  _totalPages,
              backgroundColor:
                  Colors.grey.shade200,
              color:
                  const Color(0xFF34A853),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isPermPage = _currentPage == 2;
    final isNotifPage = _currentPage == 8;

    final blocked =
        (isPermPage && !_canProceedFromPermissions) ||
        (isNotifPage && !_notifDisabled);

    String label;

    if (_currentPage == 4) {
      label = _adminActive ? 'Protected — Continue' : 'Skip for now';
    } else if (_currentPage == 5) {
      label = 'Continue to QR Code';
    } else if (_currentPage == 6) {
      label = 'I\'m Waiting for Parent';
    } else if (_currentPage ==
        _totalPages - 1) {
      label = 'Complete Setup';
    } else {
      label = 'Continue';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24,
      ),
      child: Column(
        children: [
          if (_error != null &&
              _currentPage != 2)
            Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 8,
              ),
              child: Text(
                _error!,
                textAlign:
                    TextAlign.center,
                style:
                    GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.red,
                ),
              ),
            ),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed:
                  (_loading || blocked)
                      ? null
                      : _next,
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFF34A853,
                ),
                disabledBackgroundColor:
                    Colors.grey.shade300,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
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
                          color:
                              Colors.white,
                        ),
                      )
                      : Text(
                        label,
                        style:
                            GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight:
                              FontWeight
                                  .w600,
                          color:
                              Colors.white,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageWelcome extends StatelessWidget {
  const _PageWelcome();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),

          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color:
                  const Color(0xFFE6F4EA),
              borderRadius:
                  BorderRadius.circular(
                28,
              ),
            ),
            child: const Icon(
              Icons.security,
              size: 56,
              color: Color(0xFF34A853),
            ),
          ).animate().scale(
            duration: 600.ms,
            curve: Curves.elasticOut,
          ),

          const SizedBox(height: 32),

          Text(
            'Family Monitor',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight:
                  FontWeight.w800,
              color:
                  const Color(0xFF202124),
            ),
          ).animate().fadeIn(
            delay: 200.ms,
          ),

          const SizedBox(height: 12),

          Text(
            'This app lets your parent keep you safe by monitoring this device transparently.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color:
                  const Color(0xFF5F6368),
              height: 1.6,
            ),
          ).animate().fadeIn(
            delay: 300.ms,
          ),
        ],
      ),
    );
  }
}

class _PageFeatures extends StatelessWidget {
  const _PageFeatures();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 32),

          Text(
            'What your parent can do',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight:
                  FontWeight.w700,
              color:
                  const Color(0xFF202124),
            ),
          ),

          const SizedBox(height: 24),

          const _InfoIconRow(
            icon: Icons.videocam,
            text:
                'Live camera streaming',
          ),

          const _InfoIconRow(
            icon: Icons.screen_share,
            text: 'Live screen viewing',
          ),

          const _InfoIconRow(
            icon:
                Icons.record_voice_over,
            text:
                'Microphone monitoring',
          ),

          const _InfoIconRow(
            icon: Icons.lock_clock,
            text:
                'Screen time limits',
          ),

          const _InfoIconRow(
            icon: Icons.location_on,
            text:
                'Location tracking',
          ),

          const _InfoIconRow(
            icon: Icons.block,
            text:
                'App and content filtering',
          ),
        ],
      ),
    );
  }
}

class _PagePermissions
    extends StatelessWidget {
  final bool cameraGranted;
  final bool micGranted;
  final bool notifGranted;

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
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          Text(
            'Permissions Required',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight:
                  FontWeight.w700,
              color:
                  const Color(0xFF202124),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'These permissions are needed for monitoring.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color:
                  const Color(0xFF5F6368),
            ),
          ),

          const SizedBox(height: 24),

          _PermRow(
            label: 'Camera',
            granted: cameraGranted,
            required: true,
          ),

          _PermRow(
            label: 'Microphone',
            granted: micGranted,
            required: true,
          ),

          _PermRow(
            label: 'Notifications',
            granted: notifGranted,
            required: false,
          ),

          if (error != null) ...[
            const SizedBox(height: 12),

            Text(
              error!,
              style:
                  GoogleFonts.inter(
                fontSize: 13,
                color: Colors.red,
              ),
            ),
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 48,
            child:
                OutlinedButton.icon(
              onPressed: onRequest,
              icon: const Icon(
                Icons.security,
                size: 18,
              ),
              label: Text(
                'Grant Permissions',
                style:
                    GoogleFonts.inter(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String label;
  final bool granted;
  final bool required;

  const _PermRow({
    required this.label,
    required this.granted,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            granted
                ? Icons.check_circle
                : Icons
                    .radio_button_unchecked,
            color:
                granted
                    ? const Color(
                      0xFF34A853,
                    )
                    : required
                    ? Colors.red
                    : Colors.grey,
            size: 22,
          ),

          const SizedBox(width: 12),

          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 15,
              color:
                  const Color(0xFF3C4043),
            ),
          ),

          const Spacer(),

          Text(
            granted
                ? 'Granted'
                : required
                ? 'Required'
                : 'Optional',
            style: GoogleFonts.inter(
              fontSize: 12,
              color:
                  granted
                      ? const Color(
                        0xFF34A853,
                      )
                      : required
                      ? Colors.red
                      : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}


class _PageBatteryScreen extends StatelessWidget {
  final bool batteryExempt;
  final bool screenConsented;

  final VoidCallback onBattery;
  final VoidCallback onScreen;

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
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          Text(
            'Battery & Screen',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight:
                  FontWeight.w700,
              color:
                  const Color(0xFF202124),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    children: [
                      Icon(
                        batteryExempt
                            ? Icons
                                .battery_full
                            : Icons
                                .battery_alert,
                        color:
                            batteryExempt
                                ? const Color(
                                  0xFF34A853,
                                )
                                : Colors
                                    .orange,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Text(
                        'Battery Optimization',
                        style:
                            GoogleFonts.inter(
                          fontWeight:
                              FontWeight
                                  .w600,
                          fontSize: 15,
                        ),
                      ),

                      const Spacer(),

                      if (batteryExempt)
                        const Icon(
                          Icons
                              .check_circle,
                          color: Color(
                            0xFF34A853,
                          ),
                          size: 18,
                        ),
                    ],
                  ),

                  if (!batteryExempt) ...[
                    const SizedBox(
                      height: 8,
                    ),

                    if (guide != null) ...[
                      Text(
                        '${guide!.name} instructions:',
                        style:
                            GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              FontWeight
                                  .w500,
                        ),
                      ),

                      const SizedBox(
                        height: 4,
                      ),

                      ...guide!.steps
                          .asMap()
                          .entries
                          .map(
                        (e) => Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 4,
                          ),
                          child: Text(
                            '${e.key + 1}. ${e.value}',
                            style:
                                GoogleFonts.inter(
                              fontSize:
                                  12,
                              color:
                                  const Color(
                                0xFF5F6368,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),
                    ],

                    ElevatedButton(
                      onPressed:
                          onBattery,
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(
                          0xFF34A853,
                        ),
                      ),
                      child: Text(
                        'Disable Battery Optimization',
                        style:
                            GoogleFonts.inter(
                          fontSize: 13,
                          color:
                              Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    children: [
                      Icon(
                        screenConsented
                            ? Icons
                                .screen_share
                            : Icons
                                .screen_share_outlined,
                        color:
                            screenConsented
                                ? const Color(
                                  0xFF34A853,
                                )
                                : Colors
                                    .grey,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Text(
                        'Screen Sharing',
                        style:
                            GoogleFonts.inter(
                          fontWeight:
                              FontWeight
                                  .w600,
                          fontSize: 15,
                        ),
                      ),

                      const Spacer(),

                      if (screenConsented)
                        const Icon(
                          Icons
                              .check_circle,
                          color: Color(
                            0xFF34A853,
                          ),
                          size: 18,
                        ),
                    ],
                  ),

                  if (!screenConsented) ...[
                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      'Your parent will be able to view your screen when monitoring is active.',
                      style:
                          GoogleFonts.inter(
                        fontSize: 12,
                        color:
                            const Color(
                          0xFF5F6368,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    OutlinedButton(
                      onPressed:
                          onScreen,
                      child: Text(
                        'Allow Screen Sharing',
                        style:
                            GoogleFonts.inter(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageProfile extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController deviceCtrl;

  final String? error;

  const _PageProfile({
    required this.nameCtrl,
    required this.deviceCtrl,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          Text(
            'Your Profile',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight:
                  FontWeight.w700,
              color:
                  const Color(0xFF202124),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Let your parent know who uses this device.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color:
                  const Color(0xFF5F6368),
            ),
          ),

          const SizedBox(height: 24),

          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText:
                  'Your Name *',
              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              prefixIcon:
                  const Icon(
                Icons.person_outline,
              ),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: deviceCtrl,
            decoration: InputDecoration(
              labelText:
                  'Device Name (optional)',
              hintText:
                  'e.g. My Phone',
              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              prefixIcon:
                  const Icon(
                Icons.phone_android,
              ),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 12),

            Text(
              error!,
              style:
                  GoogleFonts.inter(
                fontSize: 13,
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageQrCode extends StatelessWidget {
  final String uid;
  final String childName;

  const _PageQrCode({
    required this.uid,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          Text(
            'Show QR to Parent',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight:
                  FontWeight.w700,
              color:
                  const Color(0xFF202124),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Ask your parent to scan this QR code.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color:
                  const Color(0xFF5F6368),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 28),

          if (uid.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(
                  24,
                ),
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: uid,
                    version:
                        QrVersions.auto,
                    size: 200,
                    backgroundColor:
                        Colors.white,
                  ),

                  const SizedBox(
                    height: 10,
                  ),

                  Text(
                    childName,
                    style:
                        GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight:
                          FontWeight
                              .w700,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color:
                  const Color(0xFFF1F3F4),
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    uid,
                    style:
                        GoogleFonts.robotoMono(
                      fontSize: 11,
                    ),
                  ),
                ),

                IconButton(
                  icon: const Icon(
                    Icons.copy,
                    size: 18,
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: uid,
                      ),
                    );

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Device ID copied',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageApproval extends StatelessWidget {
  final Map<String, dynamic>
      pendingRequests;

  final bool approvalDone;
  final bool loading;

  final String? error;

  final Future<void> Function(String)
      onApprove;

  final Future<void> Function(String)
      onDecline;

  const _PageApproval({
    required this.pendingRequests,
    required this.approvalDone,
    required this.loading,
    required this.onApprove,
    required this.onDecline,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          Text(
            'Parent Approval',
            style:
                GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const SizedBox(height: 24),

          if (pendingRequests.isEmpty)
            Container(
              padding:
                  const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color:
                    const Color(0xFFF1F3F4),
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
              ),
              child: Column(
                children: [
                  const CircularProgressIndicator(),

                  const SizedBox(
                    height: 16,
                  ),

                  Text(
                    'Waiting for parent request...',
                    style:
                        GoogleFonts.inter(
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children:
                  pendingRequests.entries.map(
                (entry) {
                  final parentUid =
                      entry.key;

                  final data =
                      Map<String, dynamic>.from(
                    entry.value as Map,
                  );

                  final name =
                      data['parentName']
                              as String? ??
                          'Unknown Parent';

                  return Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        16,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              Expanded(
                                child: Text(
                                  name,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 14,
                          ),

                          Row(
                            children: [
                              Expanded(
                                child:
                                    OutlinedButton(
                                  onPressed:
                                      loading
                                          ? null
                                          : () => onDecline(
                                            parentUid,
                                          ),
                                  child:
                                      const Text(
                                    'Decline',
                                  ),
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              Expanded(
                                child:
                                    ElevatedButton(
                                  onPressed:
                                      loading
                                          ? null
                                          : () => onApprove(
                                            parentUid,
                                          ),
                                  child:
                                      const Text(
                                    'Approve',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ).toList(),
            ),

          if (error != null) ...[
            const SizedBox(height: 12),

            Text(
              error!,
              style:
                  GoogleFonts.inter(
                fontSize: 13,
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageDisableNotifications extends StatelessWidget {
  final bool notifDisabled;
  final VoidCallback onOpenSettings;

  const _PageDisableNotifications({
    required this.notifDisabled,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 32),

          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: notifDisabled
                  ? const Color(0xFFE6F4EA)
                  : const Color(0xFFFEF3CD),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              notifDisabled
                  ? Icons.notifications_off
                  : Icons.notifications_active,
              size: 52,
              color: notifDisabled
                  ? const Color(0xFF34A853)
                  : const Color(0xFFF59E0B),
            ),
          ).animate().scale(
                duration: 600.ms,
                curve: Curves.elasticOut,
              ),

          const SizedBox(height: 32),

          Text(
            'Turn Off Notifications',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF202124),
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 16),

          Text(
            'To keep monitoring quiet and private, you must turn off notifications for this app. This prevents any alerts or banners from appearing on the screen.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: const Color(0xFF5F6368),
              height: 1.6,
            ),
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 32),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: notifDisabled
                  ? const Color(0xFFE6F4EA)
                  : const Color(0xFFFFF8E1),
              border: Border.all(
                color: notifDisabled
                    ? const Color(0xFF34A853)
                    : const Color(0xFFFFD54F),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  notifDisabled
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  color: notifDisabled
                      ? const Color(0xFF34A853)
                      : const Color(0xFFF59E0B),
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notifDisabled
                            ? 'Notifications are OFF'
                            : 'Notifications are still ON',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: notifDisabled
                              ? const Color(0xFF34A853)
                              : const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notifDisabled
                            ? 'All set! Tap Complete Setup below.'
                            : 'Tap the button below to open settings and turn them off.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: notifDisabled
                              ? const Color(0xFF34A853)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 28),

          if (!notifDisabled)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings, size: 18),
                label: Text(
                  'Open Notification Settings',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: Color(0xFF1A73E8),
                    width: 1.5,
                  ),
                  foregroundColor: const Color(0xFF1A73E8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 500.ms),

          const SizedBox(height: 16),

          Text(
            'Steps: Settings → Notifications → Turn off all',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF9AA0A6),
              height: 1.5,
            ),
          ).animate().fadeIn(delay: 600.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 4 — Device Administrator (optional but strongly recommended)
// ─────────────────────────────────────────────────────────────────────────────

class _PageDeviceAdmin extends StatelessWidget {
  final bool adminActive;
  final VoidCallback onRequest;

  const _PageDeviceAdmin({
    required this.adminActive,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 24),

          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: adminActive
                  ? const Color(0xFFE6F4EA)
                  : const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              adminActive ? Icons.verified_user : Icons.shield_outlined,
              size: 50,
              color: adminActive
                  ? const Color(0xFF34A853)
                  : const Color(0xFFFF6D00),
            ),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

          const SizedBox(height: 28),

          Text(
            adminActive
                ? 'Device Protected!'
                : 'Protect This Device',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: adminActive
                  ? const Color(0xFF34A853)
                  : const Color(0xFF202124),
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 12),

          Text(
            adminActive
                ? 'Family Monitor is protected. It cannot be uninstalled '
                  'without going through a warning screen first.'
                : 'Activating Device Administrator prevents this app from '
                  'being silently uninstalled. It also lets monitoring '
                  'restart automatically if the phone is rebooted.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
              height: 1.6,
            ),
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 32),

          if (!adminActive) ...[
            _InfoIconRow(
              icon: Icons.block,
              color: const Color(0xFFEA4335),
              text: 'Prevents silent uninstallation',
            ),
            _InfoIconRow(
              icon: Icons.restart_alt,
              color: const Color(0xFF1A73E8),
              text: 'Allows auto-restart after reboot',
            ),
            _InfoIconRow(
              icon: Icons.lock_outline,
              color: const Color(0xFF34A853),
              text: 'Keeps monitoring running 24/7',
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onRequest,
                icon: const Icon(Icons.admin_panel_settings, size: 20),
                label: Text(
                  'Activate Device Administrator',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 12),

            Text(
              'You can skip this step, but monitoring may stop if the app is '
              'removed from the device.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 600.ms),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF34A853), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This device is protected. Tap Continue to proceed.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF137333),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms),
          ],
        ],
      ),
    );
  }
}

class _InfoIconRow extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String text;

  const _InfoIconRow({
    required this.icon,
    this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (color ?? const Color(0xFF34A853)).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color ?? const Color(0xFF34A853)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF2D3748),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
