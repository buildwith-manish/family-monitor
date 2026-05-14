import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Generates and serves weekly activity digests.
///
/// Child side: [generateWeeklySummary] is called by the background service
///   every Sunday night at 23:00.  It reads the last 7 daily_reports and
///   aggregates screen time, top apps, call count, and SMS count.
///
/// Parent side: [watchWeeklySummaries] streams the last 8 weekly digests.
class WeeklySummaryService {
  static final WeeklySummaryService _i = WeeklySummaryService._();
  factory WeeklySummaryService() => _i;
  WeeklySummaryService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Child side ────────────────────────────────────────────────────────────

  /// Build and write this week's summary to Firebase.
  /// [weekKey] format: "2025-W20" (ISO year + week number).
  Future<void> generateWeeklySummary(String uid) async {
    try {
      final now = DateTime.now();
      final weekKey = _weekKey(now);

      // Don't overwrite an existing summary.
      final existing =
          await _db.child('weekly_summaries/$uid/$weekKey').get();
      if (existing.value != null) return;

      // Read last 7 daily_reports.
      final reportsSnap =
          await _db.child('daily_reports/$uid').orderByKey().limitToLast(7).get();
      if (reportsSnap.value == null || reportsSnap.value is! Map) return;

      final raw = Map<String, dynamic>.from(reportsSnap.value as Map);

      int totalScreenMs = 0;
      final appTotals = <String, int>{};
      int totalCalls = 0;
      int totalSms = 0;
      int daysWithData = 0;

      for (final entry in raw.entries) {
        if (entry.value is! Map) continue;
        final report = Map<String, dynamic>.from(entry.value as Map);
        totalScreenMs += (report['totalMs'] as num?)?.toInt() ?? 0;
        totalCalls    += (report['callCount'] as num?)?.toInt() ?? 0;
        totalSms      += (report['smsCount'] as num?)?.toInt() ?? 0;
        daysWithData++;

        final topApps = report['topApps'] as List? ?? [];
        for (final a in topApps) {
          if (a is! Map) continue;
          final m = Map<String, dynamic>.from(a);
          final pkg = m['pkg'] as String? ?? '';
          final ms = (m['usedMs'] as num?)?.toInt() ?? 0;
          if (pkg.isNotEmpty) appTotals[pkg] = (appTotals[pkg] ?? 0) + ms;
        }
      }

      // Top 5 apps by total usage.
      final sortedApps = appTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topApps = sortedApps.take(5).map((e) => {
        'pkg': e.key,
        'usedMs': e.value,
        'usedMinutes': e.value ~/ 60000,
      }).toList();

      // Read call + SMS counts for the week from their own nodes.
      final callSnap = await _db.child('call_logs/$uid').get();
      if (callSnap.value is Map) {
        final calls = Map<String, dynamic>.from(callSnap.value as Map);
        // Count calls from the last 7 days.
        final cutoff = now.subtract(const Duration(days: 7))
            .millisecondsSinceEpoch;
        totalCalls = calls.values.where((v) {
          if (v is! Map) return false;
          final ts = (v as Map)['timestamp'] as int? ?? 0;
          return ts >= cutoff;
        }).length;
      }

      final smsSnap = await _db.child('sms/$uid').get();
      if (smsSnap.value is Map) {
        final msgs = Map<String, dynamic>.from(smsSnap.value as Map);
        final cutoff = now.subtract(const Duration(days: 7))
            .millisecondsSinceEpoch;
        totalSms = msgs.values.where((v) {
          if (v is! Map) return false;
          final ts = (v as Map)['date'] as int? ?? 0;
          return ts >= cutoff;
        }).length;
      }

      await _db.child('weekly_summaries/$uid/$weekKey').set({
        'weekKey': weekKey,
        'weekStart': _weekStart(now).millisecondsSinceEpoch,
        'weekEnd': now.millisecondsSinceEpoch,
        'totalScreenMs': totalScreenMs,
        'totalScreenMinutes': totalScreenMs ~/ 60000,
        'avgDailyMs': daysWithData > 0 ? totalScreenMs ~/ daysWithData : 0,
        'daysWithData': daysWithData,
        'totalCalls': totalCalls,
        'totalSms': totalSms,
        'topApps': topApps,
        'generatedAt': now.millisecondsSinceEpoch,
      });

      debugPrint('[WeeklySummary] Generated $weekKey');
    } catch (e) {
      debugPrint('[WeeklySummary] error: $e');
    }
  }

  // ── Parent side ───────────────────────────────────────────────────────────

  /// Live stream of the last 8 weekly summaries, newest first.
  Stream<List<Map<String, dynamic>>> watchWeeklySummaries(String childUid) {
    return _db
        .child('weekly_summaries/$childUid')
        .orderByKey()
        .limitToLast(8)
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];
      return (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map? ?? {});
        m['_key'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => (b['_key'] as String).compareTo(a['_key'] as String));
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// ISO week key, e.g. "2025-W20".
  String _weekKey(DateTime dt) {
    final year = dt.year;
    final jan1 = DateTime(year, 1, 1);
    final week = ((dt.difference(jan1).inDays + jan1.weekday - 1) ~/ 7) + 1;
    return '$year-W${week.toString().padLeft(2, '0')}';
  }

  /// Monday of the week containing [dt].
  DateTime _weekStart(DateTime dt) {
    return dt.subtract(Duration(days: dt.weekday - 1));
  }
}
