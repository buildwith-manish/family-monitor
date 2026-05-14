import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';

class AppLockService {
  static final _db = FirebaseDatabase.instance.ref();

  // FIX-15: MethodChannel to reach MainActivity's DPM suspend handlers.
  // setPackagesSuspended is only available when the app is a Device Admin
  // (API 24+, minSdk=24). Falls back silently when admin is not active.
  static const MethodChannel _ch = MethodChannel('com.example.family_monitor/device');

  /// Suspend [packages] using DevicePolicyManager.setPackagesSuspended so the
  /// user sees a system dialog instead of the app launching. Returns the list
  /// of packages that could not be suspended (empty on success or no-admin).
  static Future<List<String>> suspendPackagesNative(List<String> packages) async {
    if (packages.isEmpty) return [];
    try {
      final failed = await _ch.invokeListMethod<String>(
        'suspendPackages',
        {'packages': packages},
      );
      return failed ?? [];
    } on PlatformException catch (e) {
      // Log and swallow — AccessibilityService path is the fallback.
      // ignore: avoid_print
      print('[AppLockService] suspendPackages error: ${e.message}');
      return packages;
    }
  }

  /// Lift DPM suspension for [packages].
  static Future<void> unsuspendPackagesNative(List<String> packages) async {
    if (packages.isEmpty) return;
    try {
      await _ch.invokeMethod<void>('unsuspendPackages', {'packages': packages});
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[AppLockService] unsuspendPackages error: ${e.message}');
    }
  }

  static Future<void> blockApp(
    String childUid,
    String packageName,
    String appName,
  ) async {
    await _db.child('app_locks/$childUid/$packageName').set({
      'packageName': packageName,
      'appName': appName,
      'blocked': true,
      'blockedAt': DateTime.now().millisecondsSinceEpoch,
    });
    // FIX-15: Also suspend via DPM when device admin is active.
    await suspendPackagesNative([packageName]);
  }

  static Future<void> unblockApp(
    String childUid,
    String packageName,
  ) async {
    await _db.child('app_locks/$childUid/$packageName').remove();
    // FIX-15: Lift DPM suspension.
    await unsuspendPackagesNative([packageName]);
  }

  static Stream<Map<String, dynamic>> watchBlockedApps(String childUid) {
    return _db.child('app_locks/$childUid').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(v);
    });
  }

  static Future<Map<String, dynamic>> getBlockedApps(String childUid) async {
    final snap = await _db.child('app_locks/$childUid').get();
    final v = snap.value;
    if (v == null || v is! Map) return {};
    return Map<String, dynamic>.from(v);
  }

  static Stream<Set<String>> watchBlockedPackages(String childUid) {
    return _db.child('app_locks/$childUid').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <String>{};
      return Map<String, dynamic>.from(v).keys.toSet();
    });
  }
}
