import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

class DailyReportService {
  static final DailyReportService _i = DailyReportService._();
  factory DailyReportService() => _i;
  DailyReportService._();

  final _db = FirebaseDatabase.instance.ref();

  Stream<List<Map<String, dynamic>>> watchReports(String childUid) {
    return _db
        .child('daily_reports/$childUid')
        .orderByKey()
        .limitToLast(30)
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];
      final list = (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['_key'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => (b['date'] as String? ?? '')
            .compareTo(a['date'] as String? ?? ''));
      return list;
    });
  }

  Stream<Map<String, dynamic>?> watchTodayUsage(String childUid) {
    return _db.child('app_usage/$childUid/daily').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return null;
      return Map<String, dynamic>.from(v);
    });
  }
}
