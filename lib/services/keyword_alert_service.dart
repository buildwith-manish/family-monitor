import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Manages the parent's keyword watchlist and fires alerts when the child's
/// SMS messages contain any configured keyword.
///
/// Parent side:
///   [watchKeywords]   — live stream of the current keyword list.
///   [addKeyword]      — add a word/phrase to the watchlist.
///   [removeKeyword]   — remove a word/phrase.
///   [watchAlerts]     — live stream of triggered keyword alerts.
///   [markRead]        — mark an alert as read.
///   [clearAlerts]     — delete all alerts.
///
/// Child side (called from background service):
///   [scanSmsForKeywords] — called after each SMS sync to check new messages.
class KeywordAlertService {
  static final KeywordAlertService _i = KeywordAlertService._();
  factory KeywordAlertService() => _i;
  KeywordAlertService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Parent side ───────────────────────────────────────────────────────────

  Stream<List<String>> watchKeywords(String childUid) {
    return _db.child('keyword_settings/$childUid/keywords').onValue.map((e) {
      final v = e.snapshot.value;
      if (v == null) return <String>[];
      if (v is List) return v.map((k) => k.toString()).toList();
      if (v is Map) return v.values.map((k) => k.toString()).toList();
      return <String>[];
    });
  }

  Future<void> addKeyword(String childUid, String word) async {
    final snap = await _db.child('keyword_settings/$childUid/keywords').get();
    final List<String> current = [];
    final v = snap.value;
    if (v is List) current.addAll(v.map((k) => k.toString()));
    if (v is Map)  current.addAll(v.values.map((k) => k.toString()));
    if (!current.contains(word.toLowerCase())) {
      current.add(word.toLowerCase());
    }
    await _db.child('keyword_settings/$childUid/keywords').set(current);
  }

  Future<void> removeKeyword(String childUid, String word) async {
    final snap = await _db.child('keyword_settings/$childUid/keywords').get();
    final List<String> current = [];
    final v = snap.value;
    if (v is List) current.addAll(v.map((k) => k.toString()));
    if (v is Map)  current.addAll(v.values.map((k) => k.toString()));
    current.remove(word.toLowerCase());
    await _db.child('keyword_settings/$childUid/keywords').set(current);
  }

  Stream<List<Map<String, dynamic>>> watchAlerts(String childUid) {
    return _db
        .child('keyword_alerts/$childUid')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map) return <Map<String, dynamic>>[];
      return (v as Map).entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['_key'] = e.key;
        return m;
      }).toList()
        ..sort((a, b) => ((b['timestamp'] as num?) ?? 0)
            .compareTo((a['timestamp'] as num?) ?? 0));
    });
  }

  Future<void> markRead(String childUid, String alertKey) async {
    await _db.child('keyword_alerts/$childUid/$alertKey/read').set(true);
  }

  Future<void> clearAlerts(String childUid) async {
    await _db.child('keyword_alerts/$childUid').remove();
  }

  // ── Child side ────────────────────────────────────────────────────────────

  /// Scan the child's recent SMS messages for parent-configured keywords.
  /// Called by the background service after each SMS sync.
  /// Only checks messages newer than [sinceMs].
  Future<void> scanSmsForKeywords(String uid, {int sinceMs = 0}) async {
    try {
      final kwSnap =
          await _db.child('keyword_settings/$uid/keywords').get();
      if (kwSnap.value == null) return;

      final List<String> keywords = [];
      final kv = kwSnap.value;
      if (kv is List) keywords.addAll(kv.map((k) => k.toString()));
      if (kv is Map)  keywords.addAll(kv.values.map((k) => k.toString()));
      if (keywords.isEmpty) return;

      final smsSnap = await _db.child('sms/$uid').get();
      if (smsSnap.value == null || smsSnap.value is! Map) return;
      final smsMap = Map<String, dynamic>.from(smsSnap.value as Map);

      final now = DateTime.now().millisecondsSinceEpoch;

      for (final entry in smsMap.entries) {
        if (entry.value is! Map) continue;
        final msg = Map<String, dynamic>.from(entry.value as Map);
        final ts  = (msg['date'] as num?)?.toInt() ?? 0;
        if (ts < sinceMs) continue; // skip old messages

        final body    = (msg['body']    as String? ?? '').toLowerCase();
        final address = (msg['address'] as String? ?? '');

        for (final kw in keywords) {
          if (body.contains(kw.toLowerCase())) {
            // Only fire if we haven't already alerted for this message+keyword.
            final alertKey = '${entry.key}_${kw.replaceAll(' ', '_')}';
            final existing = await _db
                .child('keyword_alerts/$uid/$alertKey')
                .get();
            if (existing.value != null) continue;

            await _db.child('keyword_alerts/$uid/$alertKey').set({
              'keyword': kw,
              'messageSnippet': body.length > 80 ? body.substring(0, 80) : body,
              'from': address,
              'timestamp': ts > 0 ? ts : now,
              'read': false,
            });
            debugPrint('[Keyword] Alert fired: "$kw" in message from $address');
          }
        }
      }
    } catch (e) {
      debugPrint('[Keyword] scan error: $e');
    }
  }
}
