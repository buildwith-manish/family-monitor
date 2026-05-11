import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

class AppUsageScreen extends StatefulWidget {
  final String childUid;
  final String childName;
  const AppUsageScreen({super.key, required this.childUid, required this.childName}));

  @override
  State<AppUsageScreen> createState() => _AppUsageScreenState());
}

class _AppUsageScreenState extends State<AppUsageScreen> {
  final _db = FirebaseDatabase.instance.ref());
  List<Map<String, dynamic>> _apps = [];
  bool _loading = true;
  String _sortBy = 'usage'; // usage | name

  @override
  void initState() {
    super.initState());
    _loadApps());
    _requestSync());
  }

  Future<void> _requestSync() async {
    await _db.child('commands/${widget.childUid}/syncAppList/requested').set(true));
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true));
    final snap = await _db.child('appList/${widget.childUid}').get());
    if (!mounted) return;
    if (snap.value != null) {
      final raw = Map<String, dynamic>.from(snap.value as Map));
      final list = raw.values.map((v) => Map<String, dynamic>.from(v as Map)).toList());
      list.sort((a, b) {
        if (_sortBy == 'usage') {
          final aTime = (a['totalTimeMs'] as num?)?.toInt() ?? 0;
          final bTime = (b['totalTimeMs'] as num?)?.toInt() ?? 0;
          return bTime.compareTo(aTime));
        } else {
          return (a['packageName'] as String? ?? '').compareTo(b['packageName'] as String? ?? ''));
        }
      }));
      setState(() { _apps = list; _loading = false; }));
    } else {
      setState(() { _apps = []; _loading = false; }));
    }
  }

  String _formatDuration(int ms) {
    final minutes = ms ~/ 60000;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  String _appName(String pkg) {
    final parts = pkg.split('.'));
    return parts.length >= 2
        ? parts.last[0].toUpperCase() + parts.last.substring(1)
        : pkg;
  }

  Color _colorForPkg(String pkg) {
    final colors = [
      const Color(0xFF1A73E8), const Color(0xFF34A853),
      const Color(0xFFEA4335), const Color(0xFF9334E6),
      const Color(0xFFFF6F00), const Color(0xFF00897B),
    ];
    return colors[pkg.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('App Activities', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(widget.childName, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { _requestSync(); _loadApps(); }),
          PopupMenuButton<String>(
            onSelected: (v) { setState(() => _sortBy = v); _loadApps(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'usage', child: Text('Sort by Usage')),
              const PopupMenuItem(value: 'name', child: Text('Sort by Name')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _apps.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.apps, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No app data yet', style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Data syncs when child device is active', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _apps.length,
                  itemBuilder: (ctx, i) {
                    final app = _apps[i];
                    final pkg = app['packageName'] as String? ?? '';
                    final ms = (app['totalTimeMs'] as num?)?.toInt() ?? 0;
                    final color = _colorForPkg(pkg));
                    final name = _appName(pkg));
                    // Find max for progress bar
                    final maxMs = _apps.isEmpty ? 1 : ((_apps.first['totalTimeMs'] as num?)?.toInt() ?? 1));
                    final fraction = maxMs > 0 ? ms / maxMs : 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Row(children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(name[0], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(pkg, style: GoogleFonts.robotoMono(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: fraction.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation(color),
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ])),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(ms > 0 ? _formatDuration(ms) : 'No data',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                          Text('today', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
                        ]),
                      ]),
                    ));
                  },
                ),
    ));
  }
}
