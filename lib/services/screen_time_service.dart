// lib/services/screen_time_service.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:usage_stats/usage_stats.dart';

class ScreenTimeService {
  static final ScreenTimeService _i = ScreenTimeService._();
  factory ScreenTimeService() => _i;
  ScreenTimeService._();

  final _db = FirebaseDatabase.instance.ref();

  Future<bool> hasPermission() async {
    return await UsageStats.checkUsagePermission() ?? false;
  }

  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
  }

  Future<List<AppUsageEntry>> getTodayUsage() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    try {
      final stats = await UsageStats.queryUsageStats(midnight, now);

      final entries = stats
          .where((s) =>
              s.totalTimeInForeground != null &&
              int.tryParse(s.totalTimeInForeground ?? '0') != null &&
              int.parse(s.totalTimeInForeground!) > 0 &&
              s.packageName != null)
          .map(
            (s) => AppUsageEntry(
              packageName: s.packageName!,
              appName: _friendlyName(s.packageName!),
              minutes: (int.parse(s.totalTimeInForeground!) / 60000).round(),
            ),
          )
          .toList();

      entries.sort((a, b) => b.minutes.compareTo(a.minutes));

      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> uploadUsage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final entries = await getTodayUsage();

    // BUG-FIX: was set() which wiped the entire node on every sync, causing
    // data loss when two processes both uploaded usage. update() merges fields.
    final data = <String, dynamic>{
      '_updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    for (final e in entries) {
      // Firebase keys cannot contain dots — replace with underscores.
      final key = e.packageName.replaceAll('.', '_');
      data[key] = {
        'pkg':         e.packageName,
        'appName':     e.appName,
        'minutes':     e.minutes,
        'updatedAt':   DateTime.now().millisecondsSinceEpoch,
      };
    }

    await _db.child('screen_time/$uid/today').update(data);
  }

  Stream<List<AppUsageEntry>> watchChildUsage(String childUid) {
    return _db.child('screen_time/$childUid/today').onValue.map((event) {
      final raw = event.snapshot.value;

      if (raw == null) return <AppUsageEntry>[];

      final map =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      final entries = <AppUsageEntry>[];

      for (final entry in map.entries) {
        if (entry.key == '_updatedAt') continue;

        final v = entry.value;
        int minutes = 0;
        String pkg = entry.key;
        String name = _friendlyName(entry.key);

        if (v is Map) {
          // New format: { pkg, appName, minutes, updatedAt }
          final m = Map<String, dynamic>.from(v);
          pkg     = m['pkg']     as String? ?? entry.key;
          name    = m['appName'] as String? ?? _friendlyName(pkg);
          minutes = (m['minutes'] as num?)?.toInt() ?? 0;
        } else if (v is num) {
          // Legacy format: packageName → minutes (int)
          minutes = v.toInt();
          // Keys stored with underscores replacing dots — reverse for display
          pkg = entry.key.replaceAll('_', '.');
          name = _friendlyName(pkg);
        } else {
          continue;
        }

        if (minutes > 0) {
          entries.add(AppUsageEntry(
            packageName: pkg,
            appName:     name,
            minutes:     minutes,
          ));
        }
      }

      entries.sort((a, b) => b.minutes.compareTo(a.minutes));

      return entries;
    });
  }

  Future<void> setDailyLimit(
    String childUid,
    String packageName,
    int limitMinutes,
  ) async {
    await _db
        .child('screen_time_limits/$childUid/$packageName')
        .set(limitMinutes);
  }

  Future<Map<String, int>> getLimits(String childUid) async {
    final snap = await _db.child('screen_time_limits/$childUid').get();

    if (snap.value == null) return {};

    // BUG-FIX: `v as int` threw TypeError when Firebase stored the value as
    // a double (e.g. 30.0). Use (v as num?)?.toInt() ?? 0 for safe casting.
    return Map<String, int>.from(
      (snap.value as Map).map(
        (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
      ),
    );
  }

  Stream<Map<String, int>> watchLimits(String childUid) {
    return _db.child('screen_time_limits/$childUid').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return <String, int>{};

      return Map<String, int>.from(
        raw.map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        ),
      );
    });
  }

  String _friendlyName(String pkg) {
    const names = {
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
    };

    if (names.containsKey(pkg)) {
      return names[pkg]!;
    }

    final parts = pkg.split('.');

    if (parts.length >= 2) {
      return parts.last
          .replaceAll('_', ' ')
          .split(' ')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
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
    if (minutes < 60) {
      return '${minutes}m';
    }

    final h = minutes ~/ 60;
    final m = minutes % 60;

    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
