import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class SnapshotService {
  static final SnapshotService _i = SnapshotService._();
  factory SnapshotService() => _i;
  SnapshotService._();
  final _db = FirebaseDatabase.instance.ref();
  final _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();
  CameraController? _ctrl;
  bool _capturing = false;

  static const MethodChannel _snapshotChannel =
      MethodChannel('com.familymonitor/snapshot');

  /// Attempts to capture a JPEG via the native Camera2 foreground path.
  /// Returns null if the native side is unavailable (e.g. no Activity).
  Future<Uint8List?> _takeNativeSnapshot() async {
    try {
      final bytes = await _snapshotChannel
          .invokeMethod<Uint8List>('takeNativeSnapshot');
      return bytes;
    } on PlatformException catch (e) {
      debugPrint('[Snapshot] Native capture failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> requestSnapshot(String childUid) async {
    await _db.child('commands/$childUid/snapshot').set(
        {'requested': true, 'requestedAt': DateTime.now().millisecondsSinceEpoch});
  }

  Stream<bool> watchSnapshotRequest(String childUid) =>
      _db.child('commands/$childUid/snapshot/requested').onValue.map((e) => e.snapshot.value == true);

  /// Captures a photo and uploads it to Firebase Storage.
  ///
  /// Strategy (in order):
  ///   1. Native Camera2 via MethodChannel — works while the app is
  ///      backgrounded because the call is handled by MainActivity which
  ///      uses Android's Camera2 API with an ImageReader (no preview
  ///      surface required). This satisfies the checklist requirement that
  ///      snapshots must not depend on the Flutter UI being in the
  ///      foreground.
  ///   2. Flutter CameraController fallback — used only when the Activity
  ///      is in the foreground and the native channel is unavailable.
  Future<void> captureAndUpload(String childUid) async {
    // Guard against concurrent calls overwriting _ctrl before disposal.
    if (_capturing) return;
    _capturing = true;
    try {
      await _db.child('commands/$childUid/snapshot/requested').set(false);

      // --- Path 1: native Camera2 (works in background) ---
      final nativeBytes = await _takeNativeSnapshot();
      if (nativeBytes != null && nativeBytes.isNotEmpty) {
        await _uploadPhoto(childUid, nativeBytes);
        return;
      }

      // --- Path 2: Flutter CameraController (foreground only) ---
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // Use a local controller to avoid singleton field race conditions.
      final ctrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      _ctrl = ctrl;
      try {
        await ctrl.initialize();
        await Future.delayed(const Duration(milliseconds: 500));
        final xFile = await ctrl.takePicture();
        final bytes = await File(xFile.path).readAsBytes();
        await _uploadPhoto(childUid, bytes);
      } finally {
        await ctrl.dispose();
        if (_ctrl == ctrl) _ctrl = null;
      }
    } catch (_) {
      await _ctrl?.dispose();
      _ctrl = null;
    } finally {
      _capturing = false;
    }
  }

  Future<void> _uploadPhoto(String childUid, Uint8List bytes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'snapshots/$childUid/$key.jpg';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _db.child('snapshots/$childUid/$key').set({'url': url, 'path': path, 'timestamp': timestamp});
  }

  Stream<List<SnapshotEntry>> watchSnapshots(String childUid) {
    return _db.child('snapshots/$childUid').orderByChild('timestamp').limitToLast(50).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <SnapshotEntry>[];
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      return map.entries
          .where((e) => e.value is Map)
          .map((e) => SnapshotEntry.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  Future<void> deleteSnapshot(String childUid, SnapshotEntry entry) async {
    await _db.child('snapshots/$childUid/${entry.key}').remove();
    try { await _storage.ref(entry.storagePath).delete(); } catch (_) {}
  }
}

class SnapshotEntry {
  final String key, url, storagePath;
  final DateTime timestamp;
  const SnapshotEntry({required this.key, required this.url, required this.storagePath, required this.timestamp});
  factory SnapshotEntry.fromMap(String key, Map<String, dynamic> m) => SnapshotEntry(
    key: key, url: m['url'] as String? ?? '', storagePath: m['path'] as String? ?? '',
    timestamp: DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as num?)?.toInt() ?? 0));
  String get timeLabel { final d=DateTime.now().difference(timestamp); if(d.inMinutes<1)return 'Just now'; if(d.inHours<1)return '${d.inMinutes}m ago'; if(d.inDays<1)return '${d.inHours}h ago'; return '${timestamp.day}/${timestamp.month}'; }
}
