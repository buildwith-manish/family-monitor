import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

class RemoteLockService {
  static final RemoteLockService _i = RemoteLockService._();

  factory RemoteLockService() {
    return _i;
  }

  RemoteLockService._();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> lockDevice(
    String childUid,
  ) async {
    await _db
        .child(
      'commands/$childUid/lock',
    )
        .update({
      'locked': true,
      'lockedAt': DateTime.now().millisecondsSinceEpoch,
      'lockedBy': 'parent',
    });
  }

  Future<void> unlockDevice(
    String childUid,
  ) async {
    await _db
        .child(
      'commands/$childUid/lock',
    )
        .update({
      'locked': false,
      'unlockedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> saveSchedule(
    String childUid,
    LockSchedule schedule,
  ) async {
    await _db
        .child(
          'commands/$childUid/lock/schedule',
        )
        .set(
          schedule.toMap(),
        );
  }

  Stream<LockState> watchLockState(
    String childUid,
  ) {
    return _db
        .child(
          'commands/$childUid/lock',
        )
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null) {
        return const LockState(
          locked: false,
        );
      }

      final Map<String, dynamic> data =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      return LockState.fromMap(
        data,
      );
    });
  }

  Future<LockState> getLockState(
    String childUid,
  ) async {
    final DataSnapshot snap = await _db
        .child(
          'commands/$childUid/lock',
        )
        .get();

    if (snap.value == null) {
      return const LockState(
        locked: false,
      );
    }

    return LockState.fromMap(
      Map<String, dynamic>.from(
        snap.value as Map,
      ),
    );
  }

  bool shouldBeLocked(
    LockSchedule schedule,
  ) {
    final DateTime now = DateTime.now();

    // weekday is 1 (Mon) – 7 (Sun); convert to 0-based index.
    final int todayIndex = now.weekday - 1;

    // Guard: activeDays may have fewer than 7 entries if the data came from an
    // older app version or was partially written — treat missing days as inactive
    // to avoid a RangeError that would crash the lock-state listener.
    if (todayIndex < 0 ||
        todayIndex >= schedule.activeDays.length ||
        !schedule.activeDays[todayIndex]) {
      return false;
    }

    final int nowMins = now.hour * 60 + now.minute;

    final int startMins = schedule.startHour * 60 + schedule.startMinute;

    final int endMins = schedule.endHour * 60 + schedule.endMinute;

    if (startMins <= endMins) {
      return nowMins >= startMins && nowMins < endMins;
    }

    return nowMins >= startMins || nowMins < endMins;
  }
}

class LockState {
  final bool locked;

  final LockSchedule? schedule;

  const LockState({
    required this.locked,
    this.schedule,
  });

  factory LockState.fromMap(
    Map<String, dynamic> map,
  ) {
    LockSchedule? sched;

    if (map['schedule'] != null) {
      sched = LockSchedule.fromMap(
        Map<String, dynamic>.from(
          map['schedule'] as Map,
        ),
      );
    }

    return LockState(
      locked: map['locked'] == true,
      schedule: sched,
    );
  }
}

class LockSchedule {
  final int startHour;

  final int startMinute;

  final int endHour;

  final int endMinute;

  final List<bool> activeDays;

  const LockSchedule({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.activeDays,
  });

  factory LockSchedule.defaultBedtime() {
    return const LockSchedule(
      startHour: 22,
      startMinute: 0,
      endHour: 7,
      endMinute: 0,
      activeDays: <bool>[
        true,
        true,
        true,
        true,
        true,
        true,
        true,
      ],
    );
  }

  factory LockSchedule.fromMap(
    Map<String, dynamic> map,
  ) {
    final dynamic rawDays = map['activeDays'];

    List<bool> days;

    if (rawDays is List) {
      days = rawDays
          .map(
            (e) => e == true,
          )
          .toList();
    } else {
      days = List<bool>.filled(
        7,
        true,
      );
    }

    return LockSchedule(
      startHour: (map['startHour'] as num?)?.toInt() ?? 22,
      startMinute: (map['startMinute'] as num?)?.toInt() ?? 0,
      endHour: (map['endHour'] as num?)?.toInt() ?? 7,
      endMinute: (map['endMinute'] as num?)?.toInt() ?? 0,
      activeDays: days,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'activeDays': activeDays,
    };
  }

  String get startLabel {
    return '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  }

  String get endLabel {
    return '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
  }
}
