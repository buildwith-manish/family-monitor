class CallRecord {
  final String number, name, type;
  final DateTime date;
  final int duration;
  CallRecord({required this.number, required this.name, required this.type, required this.date, required this.duration});
  String get displayName => name.isNotEmpty ? name : number;
  String get timeLabel { final d=DateTime.now().difference(date); if(d.inMinutes<1)return 'Just now'; if(d.inHours<1)return '\${d.inMinutes}m ago'; if(d.inDays<1)return '\${d.inHours}h ago'; return '\${date.day}/\${date.month}'; }
  String get durationLabel { if(type=='missed')return 'Missed'; if(duration<60)return '\${duration}s'; return '\${duration~/60}m \${duration%60}s'; }
}
class CallLogService {
  Stream<List<CallRecord>> watchCallLog(String childUid) => Stream.value([]);
  Future<void> requestSync(String childUid) async {}
  Future<void> syncCallLog() async {}
  Stream<bool> watchSyncRequest(String uid) => Stream.value(false);
}
