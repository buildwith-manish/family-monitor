import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../services/screen_time_service.dart';
import '../../widgets/hourly_heatmap_widget.dart';
import '../../widgets/category_breakdown_widget.dart';
import '../../widgets/streak_card_widget.dart';

class AppUsageScreen extends StatefulWidget {
  final String childUid;
  final String childName;
  const AppUsageScreen(
      {super.key, required this.childUid, required this.childName});

  @override
  State<AppUsageScreen> createState() => _AppUsageScreenState();
}

class _AppUsageScreenState extends State<AppUsageScreen>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseDatabase.instance.ref();
  final _screenTimeSvc = ScreenTimeService();

  late TabController _tabs;

  final List<Map<String, dynamic>> _apps = [];
  Map<String, int> _limits = {};
  bool _loading = true;
  String _sortBy = 'usage';

  StreamSubscription? _usageSub;
  StreamSubscription? _limitsSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _listenUsage();
    _requestSync();
    _listenLimits();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _usageSub?.cancel();
    _limitsSub?.cancel();
    super.dispose();
  }

  Future<void> _requestSync() async {
    await _db
        .child('commands/${widget.childUid}/syncAppList/requested')
        .set(true);
  }

  void _listenUsage() {
    _usageSub = _db
        .child('app_usage/${widget.childUid}/daily')
        .onValue
        .listen((event) async {
      if (!mounted) return;
      final raw = event.snapshot.value;
      if (raw != null && raw is Map) {
        final list = <Map<String, dynamic>>[];
        for (final entry in Map<String, dynamic>.from(raw).entries) {
          if (entry.key.startsWith('_')) continue;
          if (entry.value is Map) {
            final m = Map<String, dynamic>.from(entry.value as Map);
            final resolvedPkg = m['pkg'] as String? ??
                entry.key.replaceAll('_', '.');
            list.add({
              'packageName': resolvedPkg,
              'appName':     m['appName'] as String? ??
                  ScreenTimeService.friendlyAppName(resolvedPkg),
              'totalTimeMs': (m['usedMs'] as num?)?.toInt() ?? 0,
            });
          }
        }
        _sortList(list);
        if (mounted) setState(() { _apps..clear()..addAll(list); _loading = false; });
        return;
      }
      // Fallback to appList
      final snap = await _db.child('appList/${widget.childUid}').get();
      if (!mounted) return;
      if (snap.value is Map) {
        final list = Map<String, dynamic>.from(snap.value as Map)
            .values.where((v) => v is Map)
            .map((v) => Map<String, dynamic>.from(v as Map)).toList();
        _sortList(list);
        setState(() { _apps..clear()..addAll(list); _loading = false; });
      } else {
        setState(() { _apps.clear(); _loading = false; });
      }
    });
  }

  void _listenLimits() {
    _limitsSub = _screenTimeSvc.watchLimits(widget.childUid).listen((l) {
      if (mounted) setState(() => _limits = l);
    });
  }

  void _sortList(List<Map<String, dynamic>> list) {
    list.sort((a, b) => _sortBy == 'usage'
        ? (((b['totalTimeMs'] as num?)?.toInt() ?? 0)
            .compareTo((a['totalTimeMs'] as num?)?.toInt() ?? 0))
        : (a['appName'] as String? ?? a['packageName'] as String? ?? '')
            .compareTo(b['appName'] as String? ?? b['packageName'] as String? ?? ''));
  }

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
  }

  String _appName(String pkg) => ScreenTimeService.friendlyAppName(pkg);

  Color _colorFor(String pkg) {
    const c = [Color(0xFF1A73E8), Color(0xFF34A853), Color(0xFFEA4335),
      Color(0xFF9334E6), Color(0xFFFF6F00), Color(0xFF00897B)];
    return c[pkg.hashCode.abs() % c.length];
  }

  Future<void> _showLimitDialog(
      String pkg, String appName, int currentMs) async {
    final controller = TextEditingController(
      text: _limits[pkg] != null ? '${_limits[pkg]}' : '',
    );
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Daily Limit — $appName',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Usage today: ${_fmt(currentMs)}',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Limit (minutes per day)',
              hintText: 'e.g. 60',
              suffixText: 'min',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: Text('Remove Limit',
                style: TextStyle(color: Colors.red.shade400)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('Set'),
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
      await _screenTimeSvc.setDailyLimit(widget.childUid, pkg, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Limit set: $result min/day for $appName'),
          backgroundColor: const Color(0xFF34A853),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Sync requested — updates every 60s'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              setState(() => _sortBy = v);
              _sortList(_apps);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'usage', child: Text('Sort by Usage')),
              const PopupMenuItem(value: 'name', child: Text('Sort by Name')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF1A73E8),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1A73E8),
          tabs: const [
            Tab(icon: Icon(Icons.apps, size: 18), text: 'Apps'),
            Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Hours'),
            Tab(icon: Icon(Icons.donut_large_outlined, size: 18), text: 'Categories'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildAppsTab(),
          _buildHoursTab(),
          _buildCategoriesTab(),
        ],
      ),
    );
  }

  // ── Apps tab ──────────────────────────────────────────────────────────────

  Widget _buildAppsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_apps.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.apps, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No app data yet',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Syncs every 60s when device is active',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _requestSync,
            icon: const Icon(Icons.sync),
            label: const Text('Request Sync'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      );
    }

    final appsWithLimits =
        _apps.where((a) => _limits.containsKey(a['packageName'])).length;
    final maxMs = _apps.isEmpty
        ? 1
        : ((_apps.first['totalTimeMs'] as num?)?.toInt() ?? 1);

    return Column(children: [
      // Streak card
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: StreakCardWidget(
          childUid: widget.childUid,
          showGoalEditor: true,
        ),
      ),
      if (appsWithLimits > 0)
        Container(
          color: const Color(0xFFE8F0FE),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.timer_outlined,
                color: Color(0xFF1A73E8), size: 18),
            const SizedBox(width: 8),
            Text(
              '$appsWithLimits app${appsWithLimits > 1 ? 's have' : ' has'} daily limits',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF1A73E8),
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _apps.length,
          itemBuilder: (ctx, i) {
            final app = _apps[i];
            final pkg = app['packageName'] as String? ?? '';
            final ms = (app['totalTimeMs'] as num?)?.toInt() ?? 0;
            final color = _colorFor(pkg);
            final name = app['appName'] as String? ?? _appName(pkg);
            final fraction = maxMs > 0 ? ms / maxMs : 0.0;
            final limitMin = _limits[pkg];
            final limitMs = limitMin != null ? limitMin * 60000 : null;
            final over = limitMs != null && ms > limitMs;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: over
                        ? const Color(0xFFEA4335).withValues(alpha: 0.4)
                        : Colors.grey.shade100),
              ),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Center(
                      child: Text(name[0],
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      Text(pkg,
                          style: GoogleFonts.robotoMono(
                              fontSize: 10, color: Colors.grey),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: fraction.clamp(0.0, 1.0),
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation(
                            over ? const Color(0xFFEA4335) : color),
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _showLimitDialog(pkg, name, ms),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      Text(ms > 0 ? _fmt(ms) : 'No data',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: over
                                  ? const Color(0xFFEA4335)
                                  : color)),
                      Text('today',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: limitMin != null
                              ? (over
                                  ? const Color(0xFFFCE8E6)
                                  : const Color(0xFFFFF3E0))
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          limitMin != null
                              ? (over
                                  ? '${limitMin}m OVER'
                                  : '${limitMin}m limit')
                              : 'Set limit',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: limitMin != null
                                ? (over
                                    ? const Color(0xFFEA4335)
                                    : const Color(0xFFE65100))
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  // ── Hours tab ─────────────────────────────────────────────────────────────

  Widget _buildHoursTab() {
    return HourlyHeatmapWidget(childUid: widget.childUid);
  }

  // ── Categories tab ────────────────────────────────────────────────────────

  Widget _buildCategoriesTab() {
    return CategoryBreakdownWidget(apps: _apps);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDuration(int ms) => _fmt(ms);
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
