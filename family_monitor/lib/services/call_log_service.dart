class CallLogService {
  // Call log feature disabled - requires special Android permissions
  Future<List<Map<String, dynamic>>> getCallLogs(String childUid) async {
    return [];
  }
}
