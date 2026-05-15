// lib/services/daily_report_service.dart
//
// Generates a structured daily summary for a child device and persists it
// to Firebase at  daily_reports/$childUid/$yyyy-MM-dd
//
// The report is idempotent — calling generate() multiple times on the same
// calendar day merges into the existing node with update() so partial data
// is never silently wiped by a later call in the same day.
//
// What is captured:
//   • Top 5 apps by screen-time (minutes)
//   • Total screen time across all apps (minutes)
//   • Most recent GPS fix (lat/lng/accuracy)
//   • End-of-day battery level & charging state
//   • Count of battery alerts fired today
//   • Count of geofence alerts fired today
//   • Count of device-health events today (warnings + errors)
//   • Timestamp when the report was generated

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';

class DailyReportService {
  static final DailyReportService _instance = DailyReportService._();
  static DailyReportService get instance => _instance;
  DailyReportService._();

  final _db = FirebaseDatabase.instance.ref();

  // Track the last date we generated a report so we only run once per day.
  String? _lastReportDate;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generate and persist a daily report for [childUid].
  ///
  /// Idempotent within a calendar day — safe to call on every screen-time
  /// timer tick; it bails out early if today's report has already been filed.
  Future<void> generate(String childUid) async {
    final today = _dateKey(DateTime.now());

    // Rate-limit: only generate once per calendar day per process.
    if (_lastReportDate == today) return;

    try {
      await _buildAndWrite(childUid, today);
      _lastReportDate = today;
      debugPrint('[DailyReport] Report written for $today');
    } catch (e) {
      debugPrint('[DailyReport] generate error: $e');
    }
  }

  /// Force-regenerate today's report regardless of the in-memory guard.
  /// Useful when the parent requests an on-demand refresh.
  Future<void> forceGenerate(String childUid) async {
    final today = _dateKey(DateTime.now());
    try {
      await _buildAndWrite(childUid, today);
      _lastReportDate = today;
      debugPrint('[DailyReport] Force-regenerated report for $today');
    } catch (e) {
      debugPrint('[DailyReport] forceGenerate error: $e');
    }
  }

  // ── Parent-side reading ──────────────────────────────────────────────────

  /// Stream of daily reports for [childUid], newest first.
  /// Each map has keys: date, generatedAt, screenTimeMinutes, topApps,
  /// lastLocation, batteryLevel, batteryAlertCount, geofenceAlertCount,
  /// healthEventCount.
  Stream<List<Map<String, dynamic>>> watchReports(
    String childUid, {
    int limit = 30,
  }) {
    return _db
        .child('daily_reports/$childUid')
        .orderByChild('generatedAt')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return <Map<String, dynamic>>[];

      final reports = (raw as Map).entries.map((e) {
        final m = e.value is Map
            ? Map<String, dynamic>.from(e.value as Map)
            : <String, dynamic>{};
        m['date'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => ((b['generatedAt'] as int?) ?? 0)
            .compareTo((a['generatedAt'] as int?) ?? 0));

      return reports;
    });
  }

  /// One-shot read of a specific date's report (or null if none).
  Future<Map<String, dynamic>?> getReport(
    String childUid,
    DateTime date,
  ) async {
    final snap =
        await _db.child('daily_reports/$childUid/${_dateKey(date)}').get();
    if (snap.value == null || snap.value is! Map) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  // ── Internal helpers ─────────────────────────────────────────────────────

  Future<void> _buildAndWrite(String childUid, String dateKey) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    // ── Screen time ────────────────────────────────────────────────────────
    int totalScreenMinutes = 0;
    final topApps = <Map<String, dynamic>>[];

    try {
      final stats = await UsageStats.queryUsageStats(midnight, now);
      final validStats = stats
          .where((s) =>
              s.packageName != null &&
              s.totalTimeInForeground != null &&
              (int.tryParse(s.totalTimeInForeground ?? '0') ?? 0) > 60000)
          .toList()
        ..sort((a, b) {
          final at = int.tryParse(a.totalTimeInForeground ?? '0') ?? 0;
          final bt = int.tryParse(b.totalTimeInForeground ?? '0') ?? 0;
          return bt.compareTo(at);
        });

      for (final s in validStats) {
        final ms = int.tryParse(s.totalTimeInForeground ?? '0') ?? 0;
        totalScreenMinutes += ms ~/ 60000;
      }

      for (final s in validStats.take(5)) {
        final ms = int.tryParse(s.totalTimeInForeground ?? '0') ?? 0;
        topApps.add({
          'packageName': s.packageName,
          'minutes': ms ~/ 60000,
        });
      }
    } catch (e) {
      debugPrint('[DailyReport] UsageStats error: $e');
    }

    // ── Last known location ────────────────────────────────────────────────
    Map<String, dynamic>? lastLocation;
    try {
      final locSnap = await _db.child('location/$childUid').get();
      if (locSnap.value is Map) {
        lastLocation = Map<String, dynamic>.from(locSnap.value as Map);
      }
    } catch (_) {}

    // ── Device info (battery) ──────────────────────────────────────────────
    int? batteryLevel;
    bool? isCharging;
    try {
      final devSnap = await _db.child('deviceInfo/$childUid').get();
      if (devSnap.value is Map) {
        final dev = Map<String, dynamic>.from(devSnap.value as Map);
        batteryLevel = (dev['batteryLevel'] as num?)?.toInt();
        isCharging   = dev['isCharging'] as bool?;
      }
    } catch (_) {}

    // ── Alert counts (today only) ──────────────────────────────────────────
    final midnightMs = midnight.millisecondsSinceEpoch;
    int batteryAlertCount  = 0;
    int geofenceAlertCount = 0;
    int healthEventCount   = 0;

    try {
      final battSnap = await _db
          .child('battery_alerts/$childUid')
          .orderByChild('timestamp')
          .startAt(midnightMs)
          .get();
      if (battSnap.value is Map) {
        batteryAlertCount = (battSnap.value as Map).length;
      }
    } catch (_) {}

    try {
      final geoSnap = await _db
          .child('geofence_alerts/$childUid')
          .orderByChild('timestamp')
          .startAt(midnightMs)
          .get();
      if (geoSnap.value is Map) {
        geofenceAlertCount = (geoSnap.value as Map).length;
      }
    } catch (_) {}

    try {
      final evtSnap = await _db.child('device_events/$childUid').get();
      if (evtSnap.value is Map) {
        final events = Map<String, dynamic>.from(evtSnap.value as Map);
        for (final v in events.values) {
          if (v is! Map) continue;
          final ts        = (v['timestamp'] as int?) ?? 0;
          final severity  = v['severity']  as String? ?? 'info';
          if (ts >= midnightMs &&
              (severity == 'warning' || severity == 'error')) {
            healthEventCount++;
          }
        }
      }
    } catch (_) {}

    // ── Write report ───────────────────────────────────────────────────────
    final report = <String, dynamic>{
      'generatedAt':        now.millisecondsSinceEpoch,
      'screenTimeMinutes':  totalScreenMinutes,
      'topApps':            topApps,
      'batteryAlertCount':  batteryAlertCount,
      'geofenceAlertCount': geofenceAlertCount,
      'healthEventCount':   healthEventCount,
    };

    if (batteryLevel != null) report['batteryLevel']   = batteryLevel;
    if (isCharging   != null) report['isCharging']     = isCharging;
    if (lastLocation != null) report['lastLocation']   = lastLocation;

    // update() so that a second call in the same day merges rather than wipes.
    await _db.child('daily_reports/$childUid/$dateKey').update(report);
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
