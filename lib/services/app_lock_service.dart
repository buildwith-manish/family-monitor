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
      if (event.snapshot.value == null) return <String, dynamic>{};
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  static Future<Map<String, dynamic>> getBlockedApps(String childUid) async {
    final snap = await _db.child('app_locks/$childUid').get();
    if (snap.value == null) return {};
    return Map<String, dynamic>.from(snap.value as Map);
  }

  static Stream<Set<String>> watchBlockedPackages(String childUid) {
    return _db.child('app_locks/$childUid').onValue.map((event) {
      if (event.snapshot.value == null) return <String>{};
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      return map.keys.toSet();
    });
  }
}
