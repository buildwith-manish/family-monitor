import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Screen-time goal streak tracking.
///
/// Parent side:
///   [setDailyGoal]    — set the daily screen-time goal in minutes.
///   [watchGoal]       — stream the current goal.
///   [watchStreak]     — stream the current streak data.
///
/// Child side (background service):
///   [evaluateDayStreak] — call at end of day (~23:55) to check whether
///     today's usage was under the goal.  Increments or resets the streak.
class StreakService {
  static final StreakService _i = StreakService._();
  factory StreakService() => _i;
  StreakService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Parent side ───────────────────────────────────────────────────────────

  Future<void> setDailyGoal(String childUid, int dailyLimitMinutes) async {
    await _db
        .child('screen_time_goal/$childUid/dailyLimitMinutes')
        .set(dailyLimitMinutes);
  }

  Future<int?> getGoal(String childUid) async {
    final snap =
        await _db.child('screen_time_goal/$childUid/dailyLimitMinutes').get();
    return (snap.value as num?)?.toInt();
  }

  Stream<int?> watchGoal(String childUid) {
    return _db
        .child('screen_time_goal/$childUid/dailyLimitMinutes')
        .onValue
        .map((e) => (e.snapshot.value as num?)?.toInt());
  }

  /// Live stream of streak data:
  ///   current (int), best (int), lastChecked (String date), goalMinutes (int)
  Stream<Map<String, dynamic>> watchStreak(String childUid) {
    return _db.child('streaks/$childUid').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(v);
    });
  }

  // ── Child side ────────────────────────────────────────────────────────────

  /// Evaluate today's screen time against the parent's goal.
  /// If under goal → increment streak (and update `best` if needed).
  /// If over goal  → reset streak to 0.
  /// Skips evaluation if today was already checked.
  Future<void> evaluateDayStreak(String uid) async {
    try {
      final today = _dateStr(DateTime.now());

      // Don't evaluate the same day twice.
      final lastSnap =
          await _db.child('streaks/$uid/lastChecked').get();
      if (lastSnap.value == today) return;

      // Get goal.
      final goalSnap =
          await _db.child('screen_time_goal/$uid/dailyLimitMinutes').get();
      final goal = (goalSnap.value as num?)?.toInt();
      if (goal == null) return; // no goal set — nothing to track

      // Get today's total screen time from app_usage/$uid/daily.
      final usageSnap =
          await _db.child('app_usage/$uid/daily').get();
      int totalMs = 0;
      if (usageSnap.value is Map) {
        final raw = Map<String, dynamic>.from(usageSnap.value as Map);
        for (final entry in raw.entries) {
          if (entry.key.startsWith('_')) continue;
          if (entry.value is Map) {
            totalMs += (((entry.value as Map)['usedMs'] as num?)?.toInt() ?? 0);
          }
        }
      }
      final totalMinutes = totalMs ~/ 60000;
      final underGoal = totalMinutes <= goal;

      // Read current streak.
      final streakSnap = await _db.child('streaks/$uid').get();
      int current = 0;
      int best    = 0;
      if (streakSnap.value is Map) {
        final m = Map<String, dynamic>.from(streakSnap.value as Map);
        current = (m['current'] as num?)?.toInt() ?? 0;
        best    = (m['best']    as num?)?.toInt() ?? 0;
      }

      if (underGoal) {
        current++;
        if (current > best) best = current;
        debugPrint('[Streak] Day under goal ($totalMinutes/$goal min). Streak: $current');
      } else {
        debugPrint('[Streak] Day over goal ($totalMinutes/$goal min). Streak reset.');
        current = 0;
      }

      await _db.child('streaks/$uid').update({
        'current':     current,
        'best':        best,
        'lastChecked': today,
        'goalMinutes': goal,
        'todayMinutes': totalMinutes,
        'todayUnderGoal': underGoal,
      });
    } catch (e) {
      debugPrint('[Streak] evaluateDayStreak error: $e');
    }
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
