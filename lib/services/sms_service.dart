// ignore_for_file: unnecessary_cast, prefer_iterable_wheretype
import 'dart:async';
import 'package:flutter/foundation.dart';
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
      final status = await Permission.sms.status;
      if (!status.isGranted) {
        debugPrint('[SmsService] READ_SMS not granted — status: $status');
        return;
      }

      final List raw = await _ch.invokeMethod('readSms', {'limit': 100});

      final Map<String, dynamic> data = {};
      for (final m in raw) {
        final mm = Map<String, dynamic>.from(m as Map);
        // Key = timestamp + sanitised address — guarantees uniqueness and
        // stable identity so repeated syncs don't create duplicate entries.
        final address = (mm['address'] as String? ?? '')
            .replaceAll(RegExp(r'[^0-9+]'), '');
        final date = mm['date']?.toString() ?? '0';
        final key = '${date}_$address';
        data[key] = mm;
      }

      // BUG-FIX: was set() which wiped all SMS history on every sync.
      // update() merges the new batch into the existing dataset, so older
      // messages that fall outside the current query window are preserved.
      if (data.isNotEmpty) {
        await _db.child('sms/$childUid').update(data);
        debugPrint('[SmsService] Synced ${data.length} SMS to Firebase');
      }
    } on PlatformException catch (e) {
      // BUG-FIX: was silently ignored. Log so developers see the failure.
      debugPrint('[SmsService] PlatformException in readSms: '
          'code=${e.code} message=${e.message}');
    } catch (e, st) {
      debugPrint('[SmsService] syncSms error: $e\n$st');
    }
  }

  Stream<bool> watchSyncRequest(String childUid) =>
      _db.child('commands/$childUid/syncSms/requested').onValue.map((e) => e.snapshot.value == true);

  static Stream<List<SmsEntry>> watchMessages(String childUid) {
    return FirebaseDatabase.instance.ref('sms/$childUid').orderByChild('date').limitToLast(200)
        .onValue.map((e) {
      final raw = e.snapshot.value;
      if (raw == null || raw is! Map) return <SmsEntry>[];
      final map = Map<String, dynamic>.from(raw);
      final list = map.values
          .where((v) => v is Map)
          .map((v) => SmsEntry.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  static Future<void> requestSync(String childUid) async {
    await FirebaseDatabase.instance.ref('commands/$childUid/syncSms')
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
  String get timeLabel { final d=DateTime.now().difference(dateTime); if(d.inMinutes<1)return 'Just now'; if(d.inHours<1)return '${d.inMinutes}m ago'; if(d.inDays<1)return '${d.inHours}h ago'; return '${d.inDays}d ago'; }
}
