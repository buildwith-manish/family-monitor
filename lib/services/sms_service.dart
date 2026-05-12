import 'dart:async';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  static final SmsService _i = SmsService._();
  factory SmsService() => _i;
  SmsService._();
  static const _ch = MethodChannel('family_monitor/sms');
  final _db = FirebaseDatabase.instance.ref();

  Future<bool> requestPermission() async => (await Permission.sms.request()).isGranted;

  Future<void> syncSms(String childUid) async {
    try {
      if (!await Permission.sms.isGranted) return;
      final List raw = await _ch.invokeMethod('readSms', {'limit': 100});
      final Map<String, dynamic> data = {};
      for (final m in raw) {
        final mm = Map<String, dynamic>.from(m as Map);
        const key = '\${mm["date"]}_\${(mm["address"] as String).replaceAll(RegExp(r"[^0-9+]"), "")}';
        data[key] = mm;
      }
      await _db.child('sms/\$childUid').set(data);
    } on PlatformException catch (_) {}
  }

  Stream<bool> watchSyncRequest(String childUid) =>
      _db.child('commands/\$childUid/syncSms/requested').onValue.map((e) => e.snapshot.value == true);

  static Stream<List<SmsEntry>> watchMessages(String childUid) {
    return FirebaseDatabase.instance.ref('sms/\$childUid').orderByChild('date').limitToLast(200)
        .onValue.map((e) {
      if (e.snapshot.value == null) return <SmsEntry>[];
      final map = Map<String, dynamic>.from(e.snapshot.value as Map);
      final list = map.values.map((v) => SmsEntry.fromMap(Map<String, dynamic>.from(v as Map))).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  static Future<void> requestSync(String childUid) async {
    await FirebaseDatabase.instance.ref('commands/\$childUid/syncSms')
        .set({'requested': true, 'at': DateTime.now().millisecondsSinceEpoch});
  }
}

class SmsEntry {
  final String address, body;
  final int date, type;
  const SmsEntry({required this.address, required this.body, required this.date, required this.type});
  factory SmsEntry.fromMap(Map<String, dynamic> m) => SmsEntry(
    address: m['address'] as String? ?? '', body: m['body'] as String? ?? '',
    date: (m['date'] as num?)?.toInt() ?? 0, type: (m['type'] as num?)?.toInt() ?? 1);
  bool get isIncoming => type == 1;
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);
  String get timeLabel { final d=DateTime.now().difference(dateTime); if(d.inMinutes<1)return 'Just now'; if(d.inHours<1)return '\${d.inMinutes}m ago'; if(d.inDays<1)return '\${d.inHours}h ago'; return '\${d.inDays}d ago'; }
}
