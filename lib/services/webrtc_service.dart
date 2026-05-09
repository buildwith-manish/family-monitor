class WebRTCService {
  Future<void> initialize() async {}
  Future<void> startCall(String roomId) async {}
  Future<void> endCall() async {}
  Future<void> joinParentSession(String uid, {Function? onLocal, Function? onRemote}) async {}
  Future<void> switchCamera() async {}
  void dispose() {}
}
