import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

class DailyReportService {
  static final DailyReportService _i = DailyReportService._();
  factory DailyReportService() => _i;
  DailyReportService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Parent reads ──────────────────────────────────────────────────────────

  /// Live stream of the last 30 daily reports for [childUid], newest first.
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

  /// Live stream of today's per-app usage from app_usage/$childUid/daily.
  /// Updated every 60 s by the background service.
  Stream<Map<String, dynamic>?> watchTodayUsage(String childUid) {
    return _db.child('app_usage/$childUid/daily').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return null;
      return Map<String, dynamic>.from(v);
    });
  }

  // ── Parent commands ───────────────────────────────────────────────────────

  /// Ask the child device to generate reports for the given [dates] and
  /// [sections].  The background service listens on
  /// commands/$childUid/generateReport and processes each pending date.
  ///
  /// [dates]    — list of ISO date strings, e.g. ["2025-05-13", "2025-05-12"]
  /// [sections] — content sections to include, e.g. ["App Usage", "Call Log"]
  Future<void> requestReportGeneration(
    String childUid,
    List<String> dates,
    List<String> sections,
  ) async {
    final payload = <String, dynamic>{
      'sections': sections,
      'requestedAt': DateTime.now().millisecondsSinceEpoch,
    };
    for (final date in dates) {
      await _db
          .child('commands/$childUid/generateReport/$date')
          .set(payload);
    }
  }

  // ── Child-side helpers ────────────────────────────────────────────────────

  /// Stream of pending report-generation requests for [childUid].
  /// The background service uses this to pick up parent requests.
  Stream<Map<String, dynamic>> watchPendingGenerationRequests(
      String childUid) {
    return _db
        .child('commands/$childUid/generateReport')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(v);
    });
  }

  /// Mark a generation request as completed (removes it from commands).
  Future<void> clearGenerationRequest(
      String childUid, String dateStr) async {
    await _db
        .child('commands/$childUid/generateReport/$dateStr')
        .remove();
  }

  /// Write a completed report to daily_reports/$childUid/$dateStr.
  Future<void> writeReport(
    String childUid,
    String dateStr, {
    required int totalMs,
    required List<Map<String, dynamic>> topApps,
    required List<String> sections,
  }) async {
    await _db.child('daily_reports/$childUid/$dateStr').set({
      'date': dateStr,
      'totalMs': totalMs,
      'totalMinutes': totalMs ~/ 60000,
      'appCount': topApps.length,
      'topApps': topApps.take(5).toList(),
      'sections': sections,
      'generatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
