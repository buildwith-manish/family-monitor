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
}

class CallLogService {
  Future<List<CallRecord>> getCallLogs(String childUid) async => [];
  Stream<List<CallRecord>> watchCallLog(String childUid) => Stream.value([]);
  Future<void> syncCallLog() async {}
  Future<void> requestSync(String childUid) async {}
  Stream<bool> watchSyncRequest(String uid) => Stream.value(false);
}
