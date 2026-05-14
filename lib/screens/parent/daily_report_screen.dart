import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/daily_report_service.dart';

class DailyReportScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const DailyReportScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen>
    with SingleTickerProviderStateMixin {
  final _svc = DailyReportService();
  late TabController _tabs;

  List<Map<String, dynamic>> _reports = [];
  Map<String, dynamic>? _todayUsage;
  bool _loading = true;

  StreamSubscription? _reportsSub;
  StreamSubscription? _todaySub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _reportsSub = _svc.watchReports(widget.childUid).listen((r) {
      if (!mounted) return;
      setState(() { _reports = r; _loading = false; });
    });
    _todaySub = _svc.watchTodayUsage(widget.childUid).listen((u) {
      if (!mounted) return;
      setState(() => _todayUsage = u);
    });
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    _todaySub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
  }

  String _appName(String? pkg) {
    if (pkg == null) return 'Unknown';
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

  Color _colorFor(String? pkg) {
    final colors = [
      const Color(0xFF1A73E8), const Color(0xFF34A853),
      const Color(0xFFEA4335), const Color(0xFF9334E6),
      const Color(0xFFFF6F00), const Color(0xFF00897B),
    ];
    return colors[(pkg?.hashCode ?? 0).abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Daily Activity Report',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ]),
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF1A73E8),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1A73E8),
          tabs: const [Tab(text: "Today"), Tab(text: "History")],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildToday(), _buildHistory()],
      ),
    );
  }

  Widget _buildToday() {
    final usage = _todayUsage;
    if (usage == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No data yet today',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Data syncs automatically every 60 seconds',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }

    final entries = usage.entries
        .where((e) => !e.key.startsWith('_') && e.value is Map)
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) =>
          ((b['usedMs'] as num?) ?? 0).compareTo((a['usedMs'] as num?) ?? 0));

    final totalMs = entries.fold<int>(
        0, (sum, e) => sum + ((e['usedMs'] as num?)?.toInt() ?? 0));
    final updatedAt = usage['_updatedAt'] as int?;
    final updatedStr = updatedAt != null
        ? _timeLabel(DateTime.fromMillisecondsSinceEpoch(updatedAt))
        : 'unknown';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(
          totalMs: totalMs,
          appCount: entries.length,
          updatedStr: updatedStr,
          fmt: _fmt,
        ).animate().fadeIn().slideY(begin: 0.1),
        const SizedBox(height: 16),
        Text('App Breakdown',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...entries.asMap().entries.map((e) {
          final i = e.key;
          final app = e.value;
          final pkg = app['pkg'] as String?;
          final ms = (app['usedMs'] as num?)?.toInt() ?? 0;
          final fraction = totalMs > 0 ? ms / totalMs : 0.0;
          final color = _colorFor(pkg);
          return _AppRow(
            name: _appName(pkg),
            pkg: pkg ?? '',
            ms: ms,
            fraction: fraction,
            color: color,
            fmt: _fmt,
          ).animate(delay: (i * 40).ms).fadeIn().slideX(begin: 0.05);
        }),
      ],
    );
  }

  Widget _buildHistory() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reports.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No reports yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Reports are generated nightly at midnight',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) {
        final r = _reports[i];
        final date = r['date'] as String? ?? '';
        final totalMs = (r['totalMs'] as num?)?.toInt() ?? 0;
        final appCount = (r['appCount'] as num?)?.toInt() ?? 0;
        final topApps = (r['topApps'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.calendar_today,
                  size: 16, color: Color(0xFF1A73E8)),
              const SizedBox(width: 8),
              Text(date,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_fmt(totalMs),
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF1A73E8),
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('$appCount apps used',
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey)),
            if (topApps.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: topApps.map((app) {
                  final pkg = app['pkg'] as String?;
                  final color = _colorFor(pkg);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_appName(pkg)} · ${_fmt((app['usedMs'] as num?)?.toInt() ?? 0)}',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
            ],
          ]),
        ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05);
      },
    );
  }

  String _timeLabel(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

class _SummaryCard extends StatelessWidget {
  final int totalMs;
  final int appCount;
  final String updatedStr;
  final String Function(int) fmt;

  const _SummaryCard({
    required this.totalMs,
    required this.appCount,
    required this.updatedStr,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Today's Screen Time",
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Text(fmt(totalMs),
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          _Stat(label: 'Apps Used', value: '$appCount'),
          const SizedBox(width: 24),
          _Stat(label: 'Updated', value: updatedStr),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
      Text(value,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _AppRow extends StatelessWidget {
  final String name, pkg;
  final int ms;
  final double fraction;
  final Color color;
  final String Function(int) fmt;

  const _AppRow({
    required this.name,
    required this.pkg,
    required this.ms,
    required this.fraction,
    required this.color,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(name.isNotEmpty ? name[0] : '?',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(pkg,
                  style: GoogleFonts.robotoMono(
                      fontSize: 9, color: Colors.grey),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Text(fmt(ms),
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
          ),
        ),
      ]),
    );
  }
}
