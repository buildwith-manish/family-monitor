// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_lock_service.dart';

class AppLockScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const AppLockScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _db = FirebaseDatabase.instance.ref();

  List<Map<String, dynamic>> _apps = [];
  Map<String, dynamic> _blockedApps = {};
  bool _loading = true;
  String _search = '';

  StreamSubscription? _blockSub;

  @override
  void initState() {
    super.initState();
    _requestSync();
    _loadApps();
    _listenBlocked();
  }

  Future<void> _requestSync() async {
    await _db
        .child('commands/${widget.childUid}/syncAppList/requested')
        .set(true);
  }

  @override
  void dispose() {
    _blockSub?.cancel();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final snap = await _db.child('appList/${widget.childUid}').get();
    if (!mounted) return;

    final list = <Map<String, dynamic>>[];
    if (snap.value != null) {
      final raw = Map<String, dynamic>.from(snap.value as Map);
      for (final v in raw.values) {
        list.add(Map<String, dynamic>.from(v as Map));
      }
      list.sort((a, b) =>
          (a['packageName'] as String? ?? '')
              .compareTo(b['packageName'] as String? ?? ''));
    }
    setState(() {
      _apps = list;
      _loading = false;
    });
  }

  void _listenBlocked() {
    _blockSub = AppLockService.watchBlockedApps(widget.childUid).listen((data) {
      if (mounted) setState(() => _blockedApps = data);
    });
  }

  Future<void> _toggle(String packageName, String appName, bool block) async {
    if (block) {
      await AppLockService.blockApp(widget.childUid, packageName, appName);
    } else {
      await AppLockService.unblockApp(widget.childUid, packageName);
    }
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
      'com.discord': 'Discord',
      'com.reddit.frontpage': 'Reddit',
      'com.roblox.client': 'Roblox',
      'com.mojang.minecraftpe': 'Minecraft',
      'com.android.chrome': 'Chrome',
      'com.netflix.mediaclient': 'Netflix',
    };
    if (names.containsKey(pkg)) return names[pkg]!;
    final parts = pkg.split('.');
    if (parts.length >= 2) {
      final last = parts.last.replaceAll('_', ' ');
      return last.isNotEmpty
          ? '${last[0].toUpperCase()}${last.substring(1)}'
          : pkg;
    }
    return pkg;
  }

  Color _colorForPkg(String pkg) {
    final colors = [
      const Color(0xFF1A73E8),
      const Color(0xFF34A853),
      const Color(0xFFEA4335),
      const Color(0xFF9334E6),
      const Color(0xFFFF6F00),
      const Color(0xFF00897B),
    ];
    return colors[pkg.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final blockedCount = _blockedApps.length;
    final filtered = _search.isEmpty
        ? _apps
        : _apps.where((a) {
            final pkg = (a['packageName'] as String? ?? '').toLowerCase();
            final name = _friendlyName(pkg).toLowerCase();
            return pkg.contains(_search) || name.contains(_search);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Lock',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          if (blockedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA4335),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$blockedCount blocked',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadApps,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search apps…',
                hintStyle:
                    GoogleFonts.inter(color: Colors.grey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey, size: 20),
                filled: true,
                fillColor: const Color(0xFFF1F3F4),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (blockedCount > 0)
            Container(
              color: const Color(0xFFFFF3E0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.block,
                      color: Color(0xFFE65100), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$blockedCount app${blockedCount > 1 ? 's are' : ' is'} blocked on ${widget.childName}\'s device',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFFE65100),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.apps,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _apps.isEmpty
                                  ? 'No app data yet'
                                  : 'No apps match "$_search"',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16, color: Colors.grey),
                            ),
                            if (_apps.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'App list syncs when child device is active',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey.shade400),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final app = filtered[i];
                          final pkg =
                              app['packageName'] as String? ?? '';
                          final name = _friendlyName(pkg);
                          final color = _colorForPkg(pkg);
                          final isBlocked =
                              _blockedApps.containsKey(pkg);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: isBlocked
                                  ? Border.all(
                                      color: const Color(0xFFEA4335)
                                          .withValues(alpha: 0.4))
                                  : Border.all(
                                      color: Colors.grey.shade100),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color:
                                      color.withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    name.isNotEmpty ? name[0] : '?',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                pkg,
                                style: GoogleFonts.robotoMono(
                                    fontSize: 10,
                                    color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Switch.adaptive(
                                value: isBlocked,
                                activeColor: const Color(0xFFEA4335),
                                onChanged: (v) =>
                                    _toggle(pkg, name, v),
                              ),
                            ),
                          ).animate(
                              delay: Duration(
                                  milliseconds: i * 20)).fadeIn();
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
