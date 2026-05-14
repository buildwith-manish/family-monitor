import 'package:firebase_database/firebase_database.dart';

class AppLockService {
  static final _db = FirebaseDatabase.instance.ref();

  static Future<void> blockApp(
    String childUid,
    String packageName,
    String appName,
  ) async {
    await _db.child('app_locks/$childUid/$packageName').set({
      'packageName': packageName,
      'appName': appName,
      'blockedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> unblockApp(
    String childUid,
    String packageName,
  ) async {
    await _db.child('app_locks/$childUid/$packageName').remove();
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
