#!/usr/bin/env bash
set -e
cd /workspaces/family-monitor

python3 - << 'PYEOF'
import re, os
fixes = {
  "lib/screens/parent/parent_auth_screen.dart": [
    ("if (!_formKey.currentState!.validate() return;","if (!_formKey.currentState!.validate()) return;"),
    ("if (!v.contains('@') return 'Enter a valid email';","if (!v.contains('@')) return 'Enter a valid email';"),
    ("_nameCtrl.dispose()\n    _emailCtrl.dispose()\n    _passCtrl.dispose()\n    super.dispose()","_nameCtrl.dispose();\n    _emailCtrl.dispose();\n    _passCtrl.dispose();\n    super.dispose();"),
    ("_loading: true;","_loading = true;"),("_error: null;","_error = null;"),
    ("setState(() => _loading: false)","setState(() => _loading = false);"),
  ],
  "lib/screens/parent/parent_dashboard_screen.dart": [
    ("final Map<String, Map<String,dynamic>> _deviceInfo: {};","final Map<String, Map<String,dynamic>> _deviceInfo = {};"),
    ("if (_batterySubs.containsKey(uid) continue;","if (_batterySubs.containsKey(uid)) continue;"),
  ],
  "lib/screens/parent/parent_qr_scanner_screen.dart": [
    ("final MobileScannerController _ctrl: MobileScannerController(\n    facing = CameraFacing.back,\n    torchEnabled = false,\n  );","final MobileScannerController _ctrl = MobileScannerController(\n    facing: CameraFacing.back,\n    torchEnabled: false,\n  );"),
    ("setState(() => _scanned: true)\n      _ctrl.stop()\n      Navigator.of(context).pop(raw)","setState(() => _scanned = true);\n      _ctrl.stop();\n      Navigator.of(context).pop(raw);"),
    ("      .color: color\n      .strokeWidth: strokeWidth\n      .strokeCap: StrokeCap.round\n      .style: PaintingStyle.stroke;","      ..color = color\n      ..strokeWidth = strokeWidth\n      ..strokeCap = StrokeCap.round\n      ..style = PaintingStyle.stroke;"),
    ("    const r: const Radius.circular(4)","    final r = const Radius.circular(4);"),
  ],
  "lib/screens/parent/schedule_lock_screen.dart": [
    ("LockSchedule _schedule: LockSchedule.defaultBedtime();","LockSchedule _schedule = LockSchedule.defaultBedtime();"),
    ("setState(() => _saving: true)","setState(() => _saving = true);"),
    ("setState(() => _saving: false)","setState(() => _saving = false);"),
  ],
  "lib/screens/parent/app_usage_screen.dart": [
    ("final List<Map<String, dynamic>> _apps: [];","final List<Map<String, dynamic>> _apps = [];"),
    ("setState(() => _loading: true)","setState(() => _loading = true);"),
    ("setState(() { _apps: list; _loading: false; });","setState(() { _apps = list; _loading = false; });"),
    ("setState(() { _apps: []; _loading: false; });","setState(() { _apps = []; _loading = false; });"),
  ],
  "lib/screens/parent/add_child_screen.dart": [
    ("_loading: true;","_loading = true;"),
    ("setState(() => _loading: false)","setState(() => _loading = false);"),
  ],
  "lib/screens/parent/call_log_screen.dart": [
    ("setState(() { _allCalls: data; _loading: false; });","setState(() { _allCalls = data; _loading = false; });"),
    ("setState(() => _loading: false);","setState(() => _loading = false);"),
    ("setState(() => _requesting: true)","setState(() => _requesting = true);"),
    ("setState(() => _requesting: false)","setState(() => _requesting = false);"),
  ],
  "lib/screens/parent/child_location_screen.dart": [
    ("_loading: false;","_loading = false;"),
    ("setState(() => _followChild: true)","setState(() => _followChild = true);"),
    ("setState(() => _mapReady: true),","setState(() => _mapReady = true),"),
    ("setState(() => _followChild: false)","setState(() => _followChild = false);"),
  ],
  "lib/screens/parent/contacts_screen.dart": [
    ("setState(() => _requesting: true)","setState(() => _requesting = true);"),
    ("setState(() => _requesting: false)","setState(() => _requesting = false);"),
  ],
  "lib/screens/parent/geofence_screen.dart": [("_addingZone: false;","_addingZone = false;")],
  "lib/screens/parent/monitoring_screen.dart": [
    ("setState(() { _hasStream: true; _status: 'Connected'; });","setState(() { _hasStream = true; _status = 'Connected'; });"),
    ("setState(() => _showControls: false)","setState(() => _showControls = false);"),
  ],
  "lib/screens/parent/screen_time_screen.dart": [
    ("setState(() { _usage: data; _loading: false; });","setState(() { _usage = data; _loading = false; });"),
    ("setState(() => _loading: false)","setState(() => _loading = false);"),
  ],
  "lib/screens/parent/sms_screen.dart": [
    ("setState(() { _msgs: m; _loading: false; });","setState(() { _msgs = m; _loading = false; });"),
  ],
  "lib/screens/parent/snapshots_screen.dart": [
    ("setState(() => _requesting: true)","setState(() => _requesting = true);"),
    ("setState(() => _requesting: false)","setState(() => _requesting = false);"),
  ],
}
for filepath, replacements in fixes.items():
    if not os.path.exists(filepath): print(f"SKIP {filepath}"); continue
    with open(filepath) as f: src = f.read()
    orig = src
    for old, new in replacements: src = src.replace(old, new)
    if src != orig:
        with open(filepath,"w") as f: f.write(src)
        print(f"Fixed: {filepath}")
    else: print(f"OK:    {filepath}")
PYEOF
echo "Part 1 done — now paste Part 2"

mkdir -p android/app/src/main/res/xml

cat > android/app/src/main/kotlin/com/example/family_monitor/FamilyDeviceAdminReceiver.kt << 'KT'
package com.example.family_monitor
import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
class FamilyDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        context.getSharedPreferences("fm_prefs",Context.MODE_PRIVATE).edit().putBoolean("admin_active",true).apply()
    }
    override fun onDisabled(context: Context, intent: Intent) {
        context.getSharedPreferences("fm_prefs",Context.MODE_PRIVATE).edit().putBoolean("admin_active",false).apply()
    }
}
KT

cat > android/app/src/main/res/xml/device_admin_policies.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<device-admin xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-policies>
    <limit-password/><wipe-data/><force-lock/><watch-login/>
    <reset-password/><disable-camera/><disable-keyguard-features/>
  </uses-policies>
</device-admin>
XML

python3 - << 'PYEOF'
path = "android/app/src/main/AndroidManifest.xml"
with open(path) as f: src = f.read()
block = '''
        <receiver android:name=".FamilyDeviceAdminReceiver" android:exported="true"
            android:permission="android.permission.BIND_DEVICE_ADMIN">
            <meta-data android:name="android.app.device_admin" android:resource="@xml/device_admin_policies"/>
            <intent-filter><action android:name="android.app.action.DEVICE_ADMIN_ENABLED"/></intent-filter>
        </receiver>
'''
if "FamilyDeviceAdminReceiver" not in src:
    src = src.replace("        <!-- Boot Receiver -->", block + "        <!-- Boot Receiver -->")
    with open(path,"w") as f: f.write(src)
    print("Manifest patched")
else: print("Manifest already patched")
PYEOF

cat > lib/services/screen_capture_channel.dart << 'DART'
import 'dart:async';
import 'package:flutter/services.dart';
class ScreenCaptureChannel {
  static const _ch = MethodChannel('family_monitor/screen_capture');
  static Future<bool> requestScreenCapture() async {
    try { final r=await _ch.invokeMethod<Map>('requestScreenCapture'); return r?['granted']==true; }
    on PlatformException catch(e){ if(e.code=='ALREADY_PENDING')return false; rethrow; }
  }
  static Future<void> stopScreenCaptureService() async => _ch.invokeMethod('stopScreenCaptureService');
  static Future<void> requestBatteryOptimizationExemption() async => _ch.invokeMethod('requestBatteryOptimizationExemption');
  static Future<bool> isBatteryOptimizationExempt() async { final r=await _ch.invokeMethod<bool>('isBatteryOptimizationExempt'); return r??false; }
  static Future<bool> hideLauncherIcon() async { try{return await _ch.invokeMethod<bool>('hideLauncherIcon')??false;}catch(_){return false;} }
  static Future<bool> showLauncherIcon() async { try{return await _ch.invokeMethod<bool>('showLauncherIcon')??false;}catch(_){return false;} }
  static Future<bool> isDeviceAdminActive() async { final r=await _ch.invokeMethod<bool>('isDeviceAdminActive'); return r??false; }
  static Future<bool> requestDeviceAdmin() async { try{final r=await _ch.invokeMethod<bool>('requestDeviceAdmin');return r??false;}on PlatformException catch(_){return false;} }
  static Future<bool> removeDeviceAdmin() async { try{final r=await _ch.invokeMethod<bool>('removeDeviceAdmin');return r??false;}on PlatformException catch(_){return false;} }
}
DART

echo "All files written. Running build..."
flutter build apk --flavor parent --target lib/main_parent.dart --release
echo "✅ Done! APK: build/app/outputs/flutter-apk/app-parent-release.apk"
