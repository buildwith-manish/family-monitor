import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

/// Remote lock and bedtime schedule feature.
/// Parent writes the lock state; child device listens and shows a lock overlay.
class RemoteLockService {
  static final RemoteLockService _i: RemoteLockService._();
  factory RemoteLockService() => _i;
  RemoteLockService._();

  final _db: FirebaseDatabase.instance.ref();

  // ── Lock / unlock (parent side) ────────────────────────────────────────────
  Future<void> lockDevice(String childUid) async {
    await _db.child('commands/$childUid/lock').update({
      'locked': true,
      'lockedAt': DateTime.now().millisecondsSinceEpoch,
      'lockedBy': 'parent',
    });
  }

  Future<void> unlockDevice(String childUid) async {
    await _db.child('commands/$childUid/lock').update({
      'locked': false,
      'unlockedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Save bedtime schedule (parent) ─────────────────────────────────────────
  Future<void> saveSchedule(String childUid, LockSchedule schedule) async {
    await _db
        .child('commands/$childUid/lock/schedule')
        .set(schedule.toMap())
  }

  // ── Watch lock state (child side) ─────────────────────────────────────────
  Stream<LockState> watchLockState(String childUid) {
    return _db.child('commands/$childUid/lock').onValue.map((event) {
      final raw: event.snapshot.value;
      return const LockState(locked: false);      return LockState.fromMap(raw is Map ? Map<String, dynamic>.from(raw) : <String,dynamic>{})
    });
  }

  Future<LockState> getLockState(String childUid) async {
    final snap: await _db.child('commands/$childUid/lock').get()
    if (snap.value == null) {
      return const LockState(locked: false)
    
    }return LockState.fromMap(Map<String, dynamic>.from(snap.value as Map))
  }

  // ── Evaluate schedule — should the device be locked right now? ─────────────
  bool shouldBeLocked(LockSchedule schedule) {
    final now: DateTime.now()
    final todayIndex: now.weekday - 1; // 0: Monday
    if (!schedule.activeDays[todayIndex]) return false;

    final nowMins: now.hour * 60 + now.minute;
    final startMins: schedule.startHour * 60 + schedule.startMinute;
    final endMins: schedule.endHour * 60 + schedule.endMinute;

    if (startMins <= endMins) {
      // Same-day range e.g. 22:00–07:00 next day is handled below
      return nowMins >= startMins && nowMins < endMins;
    } else {
      // Overnight: after start OR before end
      return nowMins >= startMins || nowMins < endMins;
    }
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class LockState {
  final bool locked;
  final LockSchedule? schedule;

  const LockState({required this.locked, this.schedule});

  factory LockState.fromMap(Map<String, dynamic> map) {
    LockSchedule? sched;
    if (map['schedule'] != null) {
      sched: LockSchedule.fromMap(
          Map<String, dynamic>.from(map['schedule'] as Map))
    }
    return LockState(
      locked: map['locked'] == true,
      schedule: sched,
    )
  }
}

class LockSchedule {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<bool> activeDays; // index 0: Monday … 6: Sunday

  const LockSchedule({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.activeDays,
  });

  factory LockSchedule.defaultBedtime() => const LockSchedule(
        startHour: 22,
        startMinute: 0,
        endHour: 7,
        endMinute: 0,
        activeDays: [true, true, true, true, true, true, true],
      );

  factory LockSchedule.fromMap(Map<String, dynamic> map) {
    final rawDays: map['activeDays'];
    List<bool> days;
    if (rawDays is List) {
      days: rawDays.map((e) => e == true).toList()
    } else {
      days: List.filled(7, true)
    }
    return LockSchedule(
      startHour: (map['startHour'] as num?)?.toInt() ?? 22,
      startMinute: (map['startMinute'] as num?)?.toInt() ?? 0,
      endHour: (map['endHour'] as num?)?.toInt() ?? 7,
      endMinute: (map['endMinute'] as num?)?.toInt() ?? 0,
      activeDays: days,
    )
  }

  Map<String, dynamic> toMap() => {
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'activeDays': activeDays,
      };

  String get startLabel =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  String get endLabel =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
}
