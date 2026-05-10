#!/usr/bin/env python3
"""
Family Monitor - WebRTC Live Camera Implementation (v2 fixed)
Run:  python3 implement_webrtc.py
"""
import os, re

BASE = '/workspaces/family-monitor'

def write(rel, content):
    path = os.path.join(BASE, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(content)
    print('  OK ' + rel)

def read(rel):
    with open(os.path.join(BASE, rel)) as f:
        return f.read()

def save(rel, content):
    with open(os.path.join(BASE, rel), 'w') as f:
        f.write(content)

# --------------------------------------------------------------------------
# 1. pubspec.yaml
# --------------------------------------------------------------------------
print('\n[1/6] pubspec.yaml')
pub = read('pubspec.yaml')
if 'flutter_webrtc' in pub:
    print('  OK flutter_webrtc already present')
else:
    for t in ['  wakelock_plus:', '  firebase_database:', '  firebase_auth:', 'dependencies:\n']:
        idx = pub.find(t)
        if idx != -1:
            eol = pub.find('\n', idx)
            pub = pub[:eol] + '\n  flutter_webrtc: ^0.9.47' + pub[eol:]
            save('pubspec.yaml', pub)
            print('  OK flutter_webrtc: ^0.9.47 added')
            break
    else:
        print('  FAIL - add manually: flutter_webrtc: ^0.9.47')

# --------------------------------------------------------------------------
# 2. AndroidManifest.xml
# --------------------------------------------------------------------------
print('\n[2/6] AndroidManifest.xml')
PERMS = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.CAMERA"/>\n'
    '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n'
    '    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
    '    <uses-permission android:name="android.permission.READ_CALL_LOG"/>\n'
    '    <uses-permission android:name="android.permission.READfind /workspaces -name "implement_webrtc.py" 2>/dev/null_CONTACTS"/>\n'
    '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
    '    <uses-feature android:name="android.hardware.camera.front" android:required="false"/>\n'
)
mf = read('android/app/src/main/AndroidManifest.xml')
if 'android.permission.INTERNET' in mf:
    print('  OK permissions already present')
else:
    mf2 = re.sub(r'(<manifest\b[^>]*>)', r'\1\n' + PERMS, mf, count=1)
    if mf2 == mf:
        print('  FAIL - add permissions manually')
    else:
        save('android/app/src/main/AndroidManifest.xml', mf2)
        print('  OK all permissions added')

# --------------------------------------------------------------------------
# 3. webrtc_service.dart
# --------------------------------------------------------------------------
print('\n[3/6] webrtc_service.dart')
write('lib/services/webrtc_service.dart', """import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final _db = FirebaseDatabase.instance.ref();

  StreamSubscription? _offerSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _candidateSub;
  StreamSubscription? _statusSub;

  bool _initialized = false;
  bool _answerSet = false;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> initialize() async {
    if (_initialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _initialized = true;
  }

  // CHILD: open camera and respond to parent offer
  Future<void> startAsChild(String childUid, VoidCallback onCallEnded) async {
    await initialize();
    _peerConnection = await createPeerConnection(_iceConfig);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {'facingMode': 'environment', 'width': 640, 'height': 480},
      'audio': false,
    });
    localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/childCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    _offerSub = _db.child('calls/$childUid/offer').onValue.listen((e) async {
      if (e.snapshot.value == null || _peerConnection == null) return;
      try {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
        final ans = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(ans);
        await _db.child('calls/$childUid/answer').set({'sdp': ans.sdp, 'type': ans.type});
      } catch (ex) { debugPrint('[WebRTC] answer error: $ex'); }
    });

    _candidateSub = _db.child('calls/$childUid/parentCandidates').onChildAdded.listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
      } catch (_) {}
    });

    _statusSub = _db.child('calls/$childUid/status').onValue.listen((e) {
      if (e.snapshot.value == 'ended') onCallEnded();
    });
  }

  // PARENT: create offer, receive child stream
  Future<void> startAsParent(String childUid, VoidCallback onStreamReady) async {
    await initialize();
    _answerSet = false;
    _peerConnection = await createPeerConnection(_iceConfig);

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        onStreamReady();
      }
    };

    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _db.child('calls/$childUid/parentCandidates').push().set({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    final offer = await _peerConnection!.createOffer({'offerToReceiveVideo': true, 'offerToReceiveAudio': false});
    await _peerConnection!.setLocalDescription(offer);
    await _db.child('calls/$childUid').set({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'status': 'calling',
    });

    _answerSub = _db.child('calls/$childUid/answer').onValue.listen((e) async {
      if (e.snapshot.value == null || _answerSet) return;
      try {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (_peerConnection?.signalingState != RTCSignalingState.RTCSignalingStateStable) {
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
          _answerSet = true;
        }
      } catch (ex) { debugPrint('[WebRTC] remote desc error: $ex'); }
    });

    _candidateSub = _db.child('calls/$childUid/childCandidates').onChildAdded.listen((e) async {
      if (e.snapshot.value == null) return;
      try {
        final c = Map<String, dynamic>.from(e.snapshot.value as Map);
        await _peerConnection!.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
      } catch (_) {}
    });
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> endCall(String childUid) async {
    await _db.child('calls/$childUid/status').set('ended');
    await Future.delayed(const Duration(milliseconds: 300));
    await _db.child('calls/$childUid').remove();
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _offerSub?.cancel(); _answerSub?.cancel();
    _candidateSub?.cancel(); _statusSub?.cancel();
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _peerConnection?.close();
    _localStream = null; _peerConnection = null;
  }

  void dispose() {
    _cleanup();
    if (_initialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
      _initialized = false;
    }
  }
}
""")

# --------------------------------------------------------------------------
# 4. child_streaming_screen.dart
# --------------------------------------------------------------------------
print('\n[4/6] child_streaming_screen.dart')
write('lib/screens/child/child_streaming_screen.dart', """import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_service.dart';

class ChildStreamingScreen extends StatefulWidget {
  final String childUid;
  const ChildStreamingScreen({super.key, required this.childUid});
  @override
  State<ChildStreamingScreen> createState() => _ChildStreamingScreenState();
}

class _ChildStreamingScreenState extends State<ChildStreamingScreen> {
  final _webrtc = WebRTCService();
  bool _isConnecting = true;
  bool _isFrontCamera = false;
  String _statusMsg = 'Starting camera...';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startStreaming();
  }

  Future<void> _startStreaming() async {
    try {
      await _webrtc.startAsChild(widget.childUid, () {
        if (mounted) Navigator.pop(context);
      });
      if (mounted) setState(() { _isConnecting = false; _statusMsg = 'Streaming to parent'; });
    } catch (e) {
      if (mounted) setState(() { _isConnecting = false; _statusMsg = 'Camera error: $e'; });
    }
  }

  Future<void> _stop() async {
    await _webrtc.endCall(widget.childUid);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _flipCamera() async {
    await _webrtc.switchCamera();
    if (mounted) setState(() => _isFrontCamera = !_isFrontCamera);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (!_isConnecting)
          RTCVideoView(_webrtc.localRenderer,
              mirror: _isFrontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        if (_isConnecting)
          const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Starting camera...', style: TextStyle(color: Colors.white, fontSize: 14)),
          ])),
        SafeArea(child: Column(children: [
          // Top bar
          _topBar(),
          const Spacer(),
          // Bottom controls
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent]),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _circleBtn(icon: Icons.flip_camera_android, onTap: _flipCamera,
                  bg: Colors.white24, size: 56, iconSize: 24),
              const SizedBox(width: 48),
              _circleBtn(icon: Icons.call_end, onTap: _stop,
                  bg: Colors.red, size: 68, iconSize: 30),
            ]),
          ),
        ])),
      ]),
    );
  }

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent])),
    child: Row(children: [
      if (!_isConnecting) _liveBadge(),
      const SizedBox(width: 12),
      Expanded(child: Text(_statusMsg,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _liveBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
          .animate(onPlay: (c) => c.repeat()).fadeOut(duration: 800.ms),
      const SizedBox(width: 6),
      Text('LIVE', style: GoogleFonts.inter(color: Colors.white, fontSize: 11,
          fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _circleBtn({required IconData icon, required VoidCallback onTap,
      required Color bg, required double size, required double iconSize}) =>
      GestureDetector(onTap: onTap, child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ));
}
""")

# --------------------------------------------------------------------------
# 5. monitoring_screen.dart
# --------------------------------------------------------------------------
print('\n[5/6] monitoring_screen.dart')
write('lib/screens/parent/monitoring_screen.dart', """import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_service.dart';

class MonitoringScreen extends StatefulWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  const MonitoringScreen({super.key, required this.childUid, required this.childData});
  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final _webrtc = WebRTCService();
  bool _hasStream = false;
  String _status = 'Waiting for child device...';
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
    ]);
    _startMonitoring();
    _timeout = Timer(const Duration(seconds: 40), () {
      if (mounted && !_hasStream)
        setState(() => _status = 'Child not responding.\\nMake sure child app is open.');
    });
  }

  Future<void> _startMonitoring() async {
    try {
      await _webrtc.startAsParent(widget.childUid, () {
        if (mounted) { _timeout?.cancel(); setState(() { _hasStream = true; _status = 'Connected'; }); }
      });
    } catch (e) { if (mounted) setState(() => _status = 'Error: $e'); }
  }

  Future<void> _endSession() async {
    _timeout?.cancel();
    await _webrtc.endCall(widget.childUid);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final childName = widget.childData['childName'] as String? ?? 'Child';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_hasStream) RTCVideoView(_webrtc.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
        if (!_hasStream)
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 48, height: 48,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
            const SizedBox(height: 24),
            Text(_status, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center).animate().fadeIn(),
            const SizedBox(height: 8),
            Text("Open Family Monitor on the child's device",
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center),
          ])),
        SafeArea(child: Column(children: [
          // Top bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent])),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _endSession),
              const SizedBox(width: 4),
              Text(childName, style: GoogleFonts.plusJakartaSans(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_hasStream) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                      .animate(onPlay: (c) => c.repeat()).fadeOut(duration: 800.ms),
                  const SizedBox(width: 6),
                  Text('LIVE', style: GoogleFonts.inter(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 8),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: GestureDetector(onTap: _endSession,
              child: Container(width: 68, height: 68,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.call_end, color: Colors.white, size: 30)),
            ),
          ),
        ])),
      ]),
    );
  }
}
""")

# --------------------------------------------------------------------------
# 6. child_home_screen.dart  – add call listener (smart regex-based patching)
# --------------------------------------------------------------------------
print('\n[6/6] child_home_screen.dart')
ch = read('lib/screens/child/child_home_screen.dart')
changed = False

# 6a. Import
imp = "import 'child_streaming_screen.dart';"
if imp not in ch:
    idx = ch.find('\n', ch.find('import ')) + 1
    ch = ch[:idx] + imp + '\n' + ch[idx:]
    changed = True; print('  OK import added')
else:
    print('  OK import exists')

# 6b. _callSub field
if '_callSub' not in ch:
    m = re.search(r'(  StreamSubscription\?[^\n]+;\n)', ch)
    if m:
        ch = ch[:m.end()] + '  StreamSubscription? _callSub;\n' + ch[m.end():]
        changed = True; print('  OK _callSub field added')
    else:
        print('  WARN could not add _callSub field - add manually')
else:
    print('  OK _callSub exists')

# 6c. Cancel in dispose
if '_callSub?.cancel()' not in ch:
    m = re.search(r'(_\w+Sub\?\.cancel\(\);)', ch)
    if m:
        ch = ch[:m.end()] + '\n    _callSub?.cancel();' + ch[m.end():]
        changed = True; print('  OK cancel added')
    else:
        print('  WARN could not add cancel - add _callSub?.cancel(); in dispose manually')
else:
    print('  OK cancel exists')

# 6d. Call listener block inside _listenForCommands
LISTENER = """
    // Incoming call from parent
    _callSub = FirebaseDatabase.instance
        .ref('calls/$uid/status')
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (event.snapshot.value == 'calling') {
        _showIncomingCallDialog(uid);
      }
    });
  }

  void _showIncomingCallDialog(String uid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Parent wants to monitor'),
        content: const Text('A parent is requesting to view your camera. Allow?'),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseDatabase.instance.ref('calls/$uid/status').set('declined');
              await FirebaseDatabase.instance.ref('calls/$uid').remove();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChildStreamingScreen(childUid: uid),
              ));
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }"""

if '_showIncomingCallDialog' not in ch:
    m = re.search(r'void _listenForCommands\(', ch)
    if m:
        start = m.start()
        depth = 0
        i = ch.find('{', start)
        while i < len(ch):
            if ch[i] == '{': depth += 1
            elif ch[i] == '}':
                depth -= 1
                if depth == 0:
                    ch = ch[:i] + LISTENER + ch[i+1:]
                    changed = True; print('  OK call listener added')
                    break
            i += 1
        else:
            print('  WARN brace walk failed - add call listener manually')
    else:
        print('  WARN _listenForCommands not found - add call listener manually')
else:
    print('  OK listener exists')

if changed:
    save('lib/screens/child/child_home_screen.dart', ch)

print("""
========================================================
  Done! Run these commands:
  cd /workspaces/family-monitor
  flutter pub get
  git add -A
  git commit -m "feat: implement live camera with WebRTC"
  git push
========================================================
""")
