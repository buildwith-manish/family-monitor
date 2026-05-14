import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DeviceEvent — a single health / crash log entry written by the child device
// and read in real-time by the parent dashboard.
//
// Firebase path:  device_events/$childUid/$pushKey  →  { type, message,
//                                                        severity, timestamp,
//                                                        read }
//
// severity values:  'info' | 'warning' | 'error'
// type values:      'service_started'  | 'service_stopped' | 'service_crash'
//                   'service_restored' | 'monitoring_error'| 'flutter_error'
// ─────────────────────────────────────────────────────────────────────────────

class DeviceEvent {
  final String key;
  final String type;
  final String message;
  final int timestamp;
  final bool read;
  final String severity;

  const DeviceEvent({
    required this.key,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.read,
    required this.severity,
  });

  factory DeviceEvent.fromSnapshot(DataSnapshot snap) {
    final v = snap.value;
    if (v == null || v is! Map) throw const FormatException('Bad snapshot');
    final m = Map<String, dynamic>.from(v);
    return DeviceEvent(
      key:       snap.key ?? '',
      type:      m['type']      as String? ?? 'unknown',
      message:   m['message']   as String? ?? '',
      timestamp: (m['timestamp'] as int?)  ?? 0,
      read:      m['read'] == true,
      severity:  m['severity']  as String? ?? 'info',
    );
  }

  String get typeLabel {
    switch (type) {
      case 'service_started':  return 'Monitoring Started';
      case 'service_stopped':  return 'Monitoring Stopped';
      case 'service_crash':    return 'Service Crashed';
      case 'service_restored': return 'Service Restored';
      case 'monitoring_error': return 'Monitoring Error';
      case 'flutter_error':    return 'App Error';
      default:                 return 'Device Event';
    }
  }

  bool get isError         => severity == 'error';
  bool get isWarning       => severity == 'warning';
  bool get isInfo          => severity == 'info';
  bool get needsAttention  => isError || isWarning;

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp);
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceEventService — static helpers for child-side writing and
// parent-side reading.
// ─────────────────────────────────────────────────────────────────────────────

class DeviceEventService {
  static DatabaseReference get _db => FirebaseDatabase.instance.ref();

  // ── Child side: write an event to Firebase ───────────────────────────────

  static Future<void> writeEvent({
    required String childUid,
    required String type,
    required String message,
    required String severity,
  }) async {
    try {
      final truncated = message.length > 300
          ? '${message.substring(0, 300)}...'
          : message;
      await _db.child('device_events/$childUid').push().set({
        'type':      type,
        'message':   truncated,
        'severity':  severity,
        'timestamp': ServerValue.timestamp,
        'read':      false,
      });
    } catch (e) {
      debugPrint('[DeviceEventService] writeEvent error: $e');
    }
  }

  // ── Parent side: real-time stream of events (newest first) ───────────────

  static Stream<List<DeviceEvent>> watchEvents(String childUid) {
    return _db
        .child('device_events/$childUid')
        .orderByChild('timestamp')
        .limitToLast(50)
        .onValue
        .map((event) {
      try {
        final events = <DeviceEvent>[];
        for (final child in event.snapshot.children) {
          try {
            events.add(DeviceEvent.fromSnapshot(child));
          } catch (_) {}
        }
        // Firebase returns ASC; reverse for newest-first display.
        return events.reversed.toList();
      } catch (_) {
        return <DeviceEvent>[];
      }
    });
  }

  // Count of unread error/warning events — used for badge display.
  static Stream<int> watchUnreadCount(String childUid) {
    return watchEvents(childUid).map(
      (events) =>
          events.where((e) => !e.read && e.needsAttention).length,
    );
  }

  // ── Parent side: bulk actions ─────────────────────────────────────────────

  static Future<void> markAllRead(String childUid) async {
    try {
      final snap = await _db.child('device_events/$childUid').get();
      if (snap.value is! Map) return;
      final updates = <String, dynamic>{};
      for (final key in (snap.value as Map).keys) {
        updates['device_events/$childUid/$key/read'] = true;
      }
      if (updates.isNotEmpty) await _db.update(updates);
    } catch (e) {
      debugPrint('[DeviceEventService] markAllRead error: $e');
    }
  }

  static Future<void> clearAll(String childUid) async {
    try {
      await _db.child('device_events/$childUid').remove();
    } catch (e) {
      debugPrint('[DeviceEventService] clearAll error: $e');
    }
  }
}
