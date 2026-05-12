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

  static const _kOptDone = 'battery_opt_done';
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
          'Open Settings → Apps → Manage apps',
          'Find "Family Monitor" and tap it',
          'Tap "Battery saver" → select "No restrictions"',
          'Also enable "Autostart" in Security app',
        ],
        hasAutostart: true,
      );
    }
    if (mfr.contains('oppo') || mfr.contains('realme')) {
      return ManufacturerGuide(
        name: mfr.contains('realme') ? 'Realme / ColorOS' : 'Oppo / ColorOS',
        steps: [
          'Open Settings → Battery → Battery Optimization',
          'Find "Family Monitor" → tap "Don\'t optimize"',
          'Open Phone Manager → App freeze → unfreeze Family Monitor',
          'Settings → Privacy → Special app access → Autostart → enable',
        ],
        hasAutostart: true,
      );
    }
    if (mfr.contains('vivo')) {
      return ManufacturerGuide(
        name: 'Vivo / FuntouchOS',
        steps: [
          'Open i-Manager → App Manager → Background Power',
          'Find "Family Monitor" → toggle off power restriction',
          'Settings → More Settings → Applications → Background app refresh → enable',
        ],
        hasAutostart: true,
      );
    }
    if (mfr.contains('oneplus')) {
      return ManufacturerGuide(
        name: 'OnePlus / OxygenOS',
        steps: [
          'Open Settings → Battery → Battery Optimization',
          'Find "Family Monitor" → set to "Don\'t optimize"',
          'Settings → Apps → Family Monitor → Battery → Allow background activity',
        ],
        hasAutostart: false,
      );
    }
    if (mfr.contains('samsung')) {
      return ManufacturerGuide(
        name: 'Samsung / One UI',
        steps: [
          'Open Settings → Device Care → Battery → Background usage limits',
          'Remove "Family Monitor" from sleeping apps',
          'Settings → Apps → Family Monitor → Battery → select "Unrestricted"',
        ],
        hasAutostart: false,
      );
    }
    if (mfr.contains('huawei') || mfr.contains('honor')) {
      return ManufacturerGuide(
        name: 'Huawei / EMUI',
        steps: [
          'Open Phone Manager → Protected apps → enable Family Monitor',
          'Settings → Battery → App launch → Family Monitor → Manage manually',
          'Enable "Auto-launch", "Secondary launch", "Run in background"',
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
