import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryService {
  static final BatteryService _instance = BatteryService._internal();
  factory BatteryService() => _instance;
  BatteryService._internal();

  static const _kOptDone           = 'battery_opt_done';
  static const _kOnboardingDone    = 'batteryOnboardingCompleted';
  static const _kFailureCount      = 'battery_failure_count';
  static const _kLastFailureHint   = 'battery_last_failure_hint_ms';
  static const _kFailureCooldownMs = 3 * 60 * 60 * 1000; // 3 h
  static const _kFailureThreshold  = 3;
  static const _channel  = MethodChannel('family_monitor/screen_capture');

  final Battery _battery = Battery();
  final _db = FirebaseDatabase.instance.ref();
  Timer? _timer;

  // ── Reporting ────────────────────────────────────────────

  Future<void> startReporting(String childUid) async {
    _timer?.cancel();
    await _report(childUid);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _report(childUid));
  }

  void stopReporting() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _report(String childUid) async {
    try {
      final level  = await _battery.batteryLevel;
      final state  = await _battery.batteryState;
      final info   = await DeviceInfoPlugin().androidInfo;
      await _db.child('deviceInfo/$childUid').set({
        'batteryLevel':    level,
        'isCharging':      state == BatteryState.charging || state == BatteryState.full,
        'deviceModel':     info.model,
        'androidVersion':  info.version.release,
        'manufacturer':    info.manufacturer,
        'lastSeen':        DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  // ── Optimization state ───────────────────────────────────

  Future<bool> isOptimizationDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptDone) ?? false;
  }

  Future<void> setOptimizationDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptDone, true);
  }

  Future<bool> isExempt() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBatteryOptimizationExempt');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestExemption() async {
    try { await _channel.invokeMethod('requestBatteryOptimizationExemption'); }
    on PlatformException { /* user may have denied */ }
  }

  // ── Onboarding completion flag ─────────────────────────────

  Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  Future<void> setOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  // ── Failure hint logic (cooldown-based) ─────────────────

  /// Records a monitoring failure. Returns true when the UI should show
  /// a re-check battery optimisation hint (after [_kFailureThreshold]
  /// consecutive failures and once per [_kFailureCooldownMs]).
  Future<bool> recordMonitoringFailure() async {
    final prefs = await SharedPreferences.getInstance();
    int count = (prefs.getInt(_kFailureCount) ?? 0) + 1;
    await prefs.setInt(_kFailureCount, count);

    if (count < _kFailureThreshold) return false;

    final lastHint = prefs.getInt(_kLastFailureHint) ?? 0;
    final now      = DateTime.now().millisecondsSinceEpoch;

    if (now - lastHint < _kFailureCooldownMs) return false;

    await prefs.setInt(_kLastFailureHint, now);
    await prefs.setInt(_kFailureCount, 0);

    return true;
  }

  Future<void> resetFailureCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFailureCount, 0);
  }

  // ── Manufacturer detection ───────────────────────────────

  Future<String> getManufacturer() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.manufacturer.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  /// Returns instructions specific to the device manufacturer.
  Future<ManufacturerGuide> getManufacturerGuide() async {
    final mfr = await getManufacturer();
    if (mfr.contains('xiaomi') || mfr.contains('redmi') || mfr.contains('poco')) {
      return ManufacturerGuide(
        name: 'Xiaomi / MIUI',
        steps: [
          'Open the "Security" app',
          'Tap "Permissions" → "Autostart"',
          'Find "Family Monitor" and enable the toggle',
          'Go back to Security app → "Battery & performance"',
          'Tap "Choose apps" → find "Family Monitor"',
          'Select "No restrictions"',
        ],
        hasAutostart: true,
      );
    }
    if (mfr.contains('oppo') || mfr.contains('realme')) {
      return ManufacturerGuide(
        name: mfr.contains('realme') ? 'Realme / ColorOS' : 'Oppo / ColorOS',
        steps: [
          'Open "Settings" → "Battery" → "Power saving mode"',
          'Tap "App battery management" → find "Family Monitor"',
          'Select "Allow background activity"',
          'Open "Security Center" (or "Privacy Permissions")',
          'Tap "Startup manager" → enable "Family Monitor"',
        ],
        hasAutostart: true,
      );
    }
    if (mfr.contains('vivo')) {
      return ManufacturerGuide(
        name: 'Vivo / FuntouchOS',
        steps: [
          'Open "i Manager" → "App Manager" → "Autostart"',
          'Find "Family Monitor" and enable it',
          'Tap "Battery" → "Background power consumption"',
          'Find "Family Monitor" → select "Allow"',
        ],
        hasAutostart: true,
      );
    }
    if (mfr.contains('oneplus')) {
      return ManufacturerGuide(
        name: 'OnePlus / OxygenOS',
        steps: [
          'Open "Settings" → "Battery" → "Battery optimization"',
          'Find "Family Monitor" → tap "Don\'t optimize"',
          'Open recent apps → long-press "Family Monitor" tile → lock it',
        ],
        hasAutostart: false,
      );
    }
    if (mfr.contains('samsung')) {
      return ManufacturerGuide(
        name: 'Samsung / One UI',
        steps: [
          'Open "Settings" → "Device care" → "Battery"',
          'Tap "App power management" → "Apps that won\'t be put to sleep"',
          'Tap "Add" and select "Family Monitor"',
          'Go to "Settings" → "Apps" → "Family Monitor" → "Battery"',
          'Select "Unrestricted"',
        ],
        hasAutostart: false,
      );
    }
    if (mfr.contains('huawei') || mfr.contains('honor')) {
      return ManufacturerGuide(
        name: 'Huawei / EMUI',
        steps: [
          'Open "Phone Manager" → "App launch"',
          'Find "Family Monitor" → turn off "Manage automatically"',
          'Enable "Auto-launch", "Secondary launch", and "Run in background"',
          'Also go to "Settings" → "Battery" → "App launch"',
          'Repeat the same steps for "Family Monitor" there',
        ],
        hasAutostart: true,
      );
    }
    // Generic Android
    return ManufacturerGuide(
      name: 'Android',
      steps: [
        'Open Settings → Battery → Battery Optimization',
        'Find "Family Monitor" → select "Don\'t optimize"',
        'Tap "OK" to confirm',
      ],
      hasAutostart: false,
    );
  }

  // ── Watch child device info ──────────────────────────────

  static Stream<Map<String, dynamic>> watchDeviceInfo(String childUid) {
    return FirebaseDatabase.instance
        .ref('deviceInfo/$childUid')
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value == null || value is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(value);
    });
  }
}

class ManufacturerGuide {
  final String name;
  final List<String> steps;
  final bool hasAutostart;
  const ManufacturerGuide({
    required this.name,
    required this.steps,
    required this.hasAutostart,
  });
}
