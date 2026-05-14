import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';

class CallRecord {
  final String number;
  final String name;
  final String type;
  final DateTime date;
  final int duration;

  CallRecord({
    required this.number,
    required this.name,
    required this.type,
    required this.date,
    required this.duration,
  });

  factory CallRecord.fromMap(Map<String, dynamic> m) => CallRecord(
        number: m['number'] as String? ?? '',
        name: m['name'] as String? ?? '',
        type: m['type'] as String? ?? 'incoming',
        date: DateTime.fromMillisecondsSinceEpoch(
            (m['date'] as num?)?.toInt() ?? 0),
        duration: (m['duration'] as num?)?.toInt() ?? 0,
      );

  String get displayName => name.isNotEmpty ? name : number;

  String get timeLabel {
    final d = DateTime.now().difference(date);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${date.day}/${date.month}';
  }

  String get durationLabel {
    if (type == 'missed') return 'Missed';
    if (duration < 60) return '${duration}s';
    return '${duration ~/ 60}m ${duration % 60}s';
  }
}

class CallLogService {
  static const _ch = MethodChannel('com.familymonitor/screen_capture');
  final _db = FirebaseDatabase.instance.ref();

  Stream<List<CallRecord>> watchCallLog(String childUid) {
    return _db
        .child('callLog/$childUid')
        .orderByChild('date')
        .limitToLast(150)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return <CallRecord>[];
      final map =
          Map<String, dynamic>.from(event.snapshot.value as Map);
      final list = map.values
          .map((v) =>
              CallRecord.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Future<void> requestSync(String childUid) async {
    await _db.child('commands/$childUid/syncCallLog').set({
      'requested': true,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> syncCallLog() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final List raw = await _ch.invokeMethod('readCallLog');
      final data = <String, dynamic>{};
      for (final m in raw) {
        final mm = Map<String, dynamic>.from(m as Map);
        final key =
            '${mm["date"]}_${(mm["number"] as String).replaceAll(RegExp(r'[^0-9+]'), '')}';
        data[key] = mm;
      }
      await _db.child('callLog/$uid').set(data);
    } on PlatformException catch (_) {
    } catch (_) {}
  }

  Stream<bool> watchSyncRequest(String uid) => _db
      .child('commands/$uid/syncCallLog/requested')
      .onValue
      .map((e) => e.snapshot.value == true);
}
