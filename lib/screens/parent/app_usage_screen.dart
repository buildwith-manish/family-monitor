import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../services/screen_time_service.dart';

class AppUsageScreen extends StatefulWidget {
  final String childUid;
  final String childName;
  const AppUsageScreen(
      {super.key, required this.childUid, required this.childName});

  @override
  State<AppUsageScreen> createState() => _AppUsageScreenState();
}

class _AppUsageScreenState extends State<AppUsageScreen> {
  final _db = FirebaseDatabase.instance.ref();
  final _screenTimeSvc = ScreenTimeService();

  final List<Map<String, dynamic>> _apps = [];
  Map<String, int> _limits = {};
  bool _loading = true;
  String _sortBy = 'usage';

  StreamSubscription? _limitsSub;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _requestSync();
    _listenLimits();
  }

  @override
  void dispose() {
    _limitsSub?.cancel();
    super.dispose();
  }

  Future<void> _requestSync() async {
    await _db
        .child('commands/${widget.childUid}/syncAppList/requested')
        .set(true);
  }

  void _listenLimits() {
    _limitsSub =
        _screenTimeSvc.watchLimits(widget.childUid).listen((limits) {
      if (mounted) setState(() => _limits = limits);
    });
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final snap = await _db.child('appList/${widget.childUid}').get();
    if (!mounted) return;
    if (snap.value != null) {
      final raw = Map<String, dynamic>.from(snap.value as Map);
      final list = raw.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      _sortList(list);
      setState(() {
        _apps..clear()..addAll(list);
        _loading = false;
      });
    } else {
      setState(() {
        _apps.clear();
        _loading = false;
      });
    }
  }

  void _sortList(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      if (_sortBy == 'usage') {
        final aTime = (a['totalTimeMs'] as num?)?.toInt() ?? 0;
        final bTime = (b['totalTimeMs'] as num?)?.toInt() ?? 0;
        return bTime.compareTo(aTime);
      } else {
        return (a['packageName'] as String? ?? '')
            .compareTo(b['packageName'] as String? ?? '');
      }
    });
  }

  String _formatDuration(int ms) {
    final minutes = ms ~/ 60000;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  String _appName(String pkg) {
    const names = {
      'com.google.android.youtube': 'YouTube',
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.snapchat.android': 'Snapchat',
      'com.facebook.katana': 'Facebook',
      'com.twitter.android': 'X (Twitter)',
      'com.whatsapp': 'WhatsApp',
      'com.discord': 'Discord',
      'com.roblox.client': 'Roblox',
      'com.android.chrome': 'Chrome',
      'com.netflix.mediaclient': 'Netflix',
    };
    if (names.containsKey(pkg)) return names[pkg]!;
    final parts = pkg.split('.');
    return parts.length >= 2
        ? parts.last[0].toUpperCase() + parts.last.substring(1)
        : pkg;
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

  Future<void> _showLimitDialog(String pkg, String appName, int currentMs) async {
    final currentLimit = _limits[pkg];
    final controller = TextEditingController(
      text: currentLimit != null ? '$currentLimit' : '',
    );

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Daily Limit — $appName',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current usage today: ${_formatDuration(currentMs)}',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Limit (minutes per day)',
                hintText: 'e.g. 60',
                suffixText: 'min',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave empty to remove the limit',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: Text('Remove Limit',
                style: TextStyle(color: Colors.red.shade400)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('Set Limit'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result == -1) {
      await _db
          .child('screen_time_limits/${widget.childUid}/$pkg')
          .remove();
    } else if (result > 0) {
      await _screenTimeSvc.setDailyLimit(
          widget.childUid, pkg, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Daily limit set to $result minutes for $appName'),
            backgroundColor: const Color(0xFF34A853),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appsWithLimits =
        _apps.where((a) => _limits.containsKey(a['packageName'])).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('App Usage & Screen Time',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _requestSync();
                _loadApps();
              }),
          PopupMenuButton<String>(
            onSelected: (v) {
              setState(() => _sortBy = v);
              _sortList(_apps);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'usage', child: Text('Sort by Usage')),
              const PopupMenuItem(
                  value: 'name', child: Text('Sort by Name')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _apps.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.apps, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('No app data yet',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text('Data syncs when child device is active',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.grey.shade400)),
                  ]))
              : Column(
                  children: [
                    if (appsWithLimits > 0)
                      Container(
                        color: const Color(0xFFE8F0FE),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined,
                                color: Color(0xFF1A73E8), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '$appsWithLimits app${appsWithLimits > 1 ? 's have' : ' has'} daily limits set',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF1A73E8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _apps.length,
                        itemBuilder: (ctx, i) {
                          final app = _apps[i];
                          final pkg = app['packageName'] as String? ?? '';
                          final ms = (app['totalTimeMs'] as num?)?.toInt() ?? 0;
                          final color = _colorForPkg(pkg);
                          final name = _appName(pkg);
                          final maxMs = _apps.isEmpty
                              ? 1
                              : ((_apps.first['totalTimeMs'] as num?)
                                      ?.toInt() ??
                                  1);
                          final fraction = maxMs > 0 ? ms / maxMs : 0.0;
                          final limitMin = _limits[pkg];
                          final limitMs = limitMin != null ? limitMin * 60000 : null;
                          final overLimit =
                              limitMs != null && ms > limitMs;
                          final limitFraction = limitMs != null && maxMs > 0
                              ? (limitMs / maxMs).clamp(0.0, 1.0)
                              : null;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: overLimit
                                    ? const Color(0xFFEA4335)
                                        .withValues(alpha: 0.4)
                                    : Colors.grey.shade100,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(children: [
                                  _AppIconWidget(
                                    pkg: pkg,
                                    name: name,
                                    color: color,
                                    iconUrl:
                                        app['iconUrl'] as String?,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(name,
                                            style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w600)),
                                        Text(pkg,
                                            style: GoogleFonts.robotoMono(
                                                fontSize: 10,
                                                color: Colors.grey),
                                            overflow:
                                                TextOverflow.ellipsis),
                                        const SizedBox(height: 6),
                                        Stack(
                                          children: [
                                            LinearProgressIndicator(
                                              value: fraction.clamp(0.0, 1.0),
                                              backgroundColor:
                                                  Colors.grey.shade100,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                      overLimit
                                                          ? const Color(0xFFEA4335)
                                                          : color),
                                              minHeight: 5,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            if (limitFraction != null)
                                              Positioned(
                                                left: limitFraction *
                                                    (MediaQuery.of(context)
                                                            .size
                                                            .width -
                                                        160),
                                                top: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 2,
                                                  color: const Color(0xFFFF6D00),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ])),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () => _showLimitDialog(
                                        pkg, name, ms),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                              ms > 0
                                                  ? _formatDuration(ms)
                                                  : 'No data',
                                              style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color: overLimit
                                                      ? const Color(0xFFEA4335)
                                                      : color)),
                                          Text('today',
                                              style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  color: Colors.grey)),
                                          if (limitMin != null) ...[
                                            const SizedBox(height: 2),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: overLimit
                                                    ? const Color(0xFFFCE8E6)
                                                    : const Color(0xFFFFF3E0),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${limitMin}m limit',
                                                style: GoogleFonts.inter(
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: overLimit
                                                      ? const Color(0xFFEA4335)
                                                      : const Color(0xFFE65100),
                                                ),
                                              ),
                                            ),
                                          ] else
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Set limit',
                                                style: GoogleFonts.inter(
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                        ]),
                                  ),
                                ]),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App icon widget — real icon from Firebase Storage when present,
// coloured letter avatar otherwise.
// ─────────────────────────────────────────────────────────────────────────────

class _AppIconWidget extends StatelessWidget {
  final String pkg;
  final String name;
  final Color color;
  final String? iconUrl;

  const _AppIconWidget({
    required this.pkg,
    required this.name,
    required this.color,
    required this.iconUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (iconUrl != null && iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: iconUrl!,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          placeholder: (_, __) => _letterAvatar(),
          errorWidget: (_, __, ___) => _letterAvatar(),
        ),
      );
    }
    return _letterAvatar();
  }

  Widget _letterAvatar() => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      );
}
