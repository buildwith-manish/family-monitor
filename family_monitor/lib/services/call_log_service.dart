import 'package:call_log/call_log.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';

/// Reads the device call log (child side) and syncs to Firebase for parent view.
class CallLogService {
  static final CallLogService _i = CallLogService._();
  factory CallLogService() => _i;
  CallLogService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Permission ─────────────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    final call = await Permission.phone.request();
    final sms = await Permission.sms.request();
    return call.isGranted && sms.isGranted;
  }

  Future<bool> get hasPermissions async {
    return await Permission.phone.isGranted &&
        await Permission.sms.isGranted;
  }

  // ── Read call log from device (child) ─────────────────────────────────────
  Future<List<CallLogEntry>> getRecentCalls({int limit = 100}) async {
    final granted = await requestPermissions();
    if (!granted) return [];

    final entries = await CallLog.get();
    return entries.take(limit).toList();
  }

  // ── Upload call log to Firebase (child) ───────────────────────────────────
  Future<void> syncCallLog() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final entries = await getRecentCalls(limit: 200);
    final data = <String, dynamic>{};

    for (final entry in entries) {
      final key = '${entry.timestamp ?? DateTime.now().millisecondsSinceEpoch}';
      data[key] = {
        'number': entry.number ?? '',
        'name': entry.name ?? '',
        'duration': entry.duration ?? 0,
        'type': _typeLabel(entry.callType),
        'timestamp': entry.timestamp ?? 0,
      };
    }

    await _db.child('call_logs/$uid').set({
      ...data,
      '_syncedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Watch call log (parent side) ──────────────────────────────────────────
  Stream<List<CallRecord>> watchCallLog(String childUid) {
    return _db
        .child('call_logs/$childUid')
        .orderByChild('timestamp')
        .limitToLast(200)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <CallRecord>[];
      final map = Map<String, dynamic>.from(raw as Map);
      final records = map.entries
          .where((e) => e.key != '_syncedAt')
          .map((e) =>
              CallRecord.fromMap(Map<String, dynamic>.from(e.value as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return records;
    });
  }

  // ── Request sync from parent (parent writes command) ──────────────────────
  Future<void> requestSync(String childUid) async {
    await _db.child('commands/$childUid/syncCallLog').set({
      'requested': true,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Listen for sync request (child side) ──────────────────────────────────
  Stream<bool> watchSyncRequest(String childUid) {
    return _db
        .child('commands/$childUid/syncCallLog/requested')
        .onValue
        .map((e) => e.snapshot.value == true);
  }

  static String _typeLabel(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return 'incoming';
      case CallType.outgoing:
        return 'outgoing';
      case CallType.missed:
        return 'missed';
      case CallType.rejected:
        return 'rejected';
      default:
        return 'unknown';
    }
  }
}

class CallRecord {
  final String number;
  final String name;
  final int durationSeconds;
  final String type;
  final DateTime timestamp;

  const CallRecord({
    required this.number,
    required this.name,
    required this.durationSeconds,
    required this.type,
    required this.timestamp,
  });

  factory CallRecord.fromMap(Map<String, dynamic> map) {
    return CallRecord(
      number: map['number'] as String? ?? '',
      name: map['name'] as String? ?? '',
      durationSeconds: (map['duration'] as num?)?.toInt() ?? 0,
      type: map['type'] as String? ?? 'unknown',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? 0),
    );
  }

  String get displayName => name.isNotEmpty ? name : number.isNotEmpty ? number : 'Unknown';

  String get durationLabel {
    if (durationSeconds == 0) return '—';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  String get timeLabel {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays == 0) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}
