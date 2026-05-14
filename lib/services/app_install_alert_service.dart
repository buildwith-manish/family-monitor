import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

class AppInstallAlertService {
  static final AppInstallAlertService _i = AppInstallAlertService._();
  factory AppInstallAlertService() => _i;
  AppInstallAlertService._();

  final _db = FirebaseDatabase.instance.ref();

  Stream<List<Map<String, dynamic>>> watchAlerts(String childUid) {
    return _db
        .child('app_install_alerts/$childUid')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];
      final list = (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['_key'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => ((b['timestamp'] as int?) ?? 0)
            .compareTo((a['timestamp'] as int?) ?? 0));
      return list;
    });
  }

  Future<void> markRead(String childUid, String key) async {
    await _db.child('app_install_alerts/$childUid/$key/read').set(true);
  }

  Future<void> clearAll(String childUid) async {
    await _db.child('app_install_alerts/$childUid').remove();
  }
}
