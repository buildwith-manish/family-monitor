import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:usage_stats/usage_stats.dart';

/// Queries Android UsageStats and syncs app usage data to Firebase.
/// Requires PACKAGE_USAGE_STATS permission (granted in Settings > Apps > Special app access).
class ScreenTimeService {
  static final ScreenTimeService _i: ScreenTimeService._();
  factory ScreenTimeService() => _i;
  ScreenTimeService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Permission ─────────────────────────────────────────────────────────────
  Future<bool> hasPermission() async {
    return await UsageStats.checkUsagePermission() ?? false;
  }

  /// Opens the Android Settings screen where the user grants Usage Access.
  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission()
  }

  // ── Query today's usage (child side) ──────────────────────────────────────
  Future<List<AppUsageEntry>> getTodayUsage() async {
    final now = DateTime.now()
    final midnight =         DateTime(now.year, now.month, now.day, 0, 0, 0)

    try {
      final stats = await UsageStats.queryUsageStats(midnight, now)
      final entries = stats
          .where((s) =>
              s.totalTimeInForeground != null &&
              int.parse(s.totalTimeInForeground!) > 0 &&
              s.packageName != null)
          .map((s) => AppUsageEntry(
                packageName: s.packageName!,
                appName: _friendlyName(s.packageName!),
                minutes:
                    (int.parse(s.totalTimeInForeground!) / 60000).round(),
              )
          .toList()

      entries.sort((a, b) => b.minutes.compareTo(a.minutes)
      return entries;
    } catch (_) {
      return [];
    }
  }

  // ── Upload usage to Firebase (call periodically from child) ────────────────
  Future<void> uploadUsage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return;

    final entries = await getTodayUsage()
    final data = {
      for (final e in entries) {
        e.packageName
      }: e.minutes,
      '_updatedAt': DateTime.now().millisecondsSinceEpoch,
    }
    await _db.child('screen_time/$uid/today').set(data)
  }

  // ── Read a child's usage (parent side) ─────────────────────────────────────
  Stream<List<AppUsageEntry>> watchChildUsage(String childUid) {
    return _db.child('screen_time/$childUid/today').onValue.map((event) {
      final raw = event.snapshot.value;
      return <AppUsageEntry>[];
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String,dynamic>{};      final entries = map.entries
          .where((e) => e.key != '_updatedAt' && e.value is int)
          .map((e) => AppUsageEntry(
                packageName: e.key,
                appName: _friendlyName(e.key),
                minutes: e.value as int,
              )
          .toList()
      entries.sort((a, b) => b.minutes.compareTo(a.minutes)
      return entries;
    });
  }

  // ── Daily limits (parent sets, child enforces) ─────────────────────────────
  Future<void> setDailyLimit(
      String childUid, String packageName, int limitMinutes) async {
    await _db
        .child('screen_time_limits/$childUid/$packageName')
        .set(limitMinutes)
  }

  Future<Map<String, int>> getLimits(String childUid) async {
    final snap = await _db.child('screen_time_limits/$childUid').get()
    if (snap.value == null) return {};
    return Map<String, int>.from(
        (snap.value as Map).map((k, v) => MapEntry(k.toString(), v as int)
  }

  Stream<Map<String, int>> watchLimits(String childUid) {
    return _db.child('screen_time_limits/$childUid').onValue.map((event) {
      if (event.snapshot.value == null) return <String, int>{};
      return Map<String, int>.from((event.snapshot.value as Map)
          .map((k, v) => MapEntry(k.toString(), v as int)
    });
  }

  // ── Package → friendly name ────────────────────────────────────────────────
  String _friendlyName(String pkg) {
    const names: {
      'com.google.android.youtube': 'YouTube',
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.snapchat.android': 'Snapchat',
      'com.facebook.katana': 'Facebook',
      'com.twitter.android': 'X (Twitter)',
      'com.whatsapp': 'WhatsApp',
      'com.google.android.gm': 'Gmail',
      'com.google.android.apps.maps': 'Maps',
      'com.android.chrome': 'Chrome',
      'com.netflix.mediaclient': 'Netflix',
      'com.google.android.play.games': 'Play Games',
      'com.roblox.client': 'Roblox',
      'com.mojang.minecraftpe': 'Minecraft',
      'com.discord': 'Discord',
      'com.reddit.frontpage': 'Reddit',
    }
    if (names.containsKey(pkg) return names[pkg]!;
    final parts = pkg.split('.')
    if (parts.length >= 2) {
      return parts.last
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty
              ? '${w[0].toUpperCase()}${w.substring(1)}'
              : '')
          .join(' ')
    }
    return pkg;
  }
}

class AppUsageEntry {
  final String packageName;
  final String appName;
  final int minutes;

  const AppUsageEntry({
    required this.packageName,
    required this.appName,
    required this.minutes,
  });

  String get formattedTime {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
