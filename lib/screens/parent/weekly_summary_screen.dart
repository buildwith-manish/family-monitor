import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/weekly_summary_service.dart';

class WeeklySummaryScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const WeeklySummaryScreen(
      {super.key, required this.childUid, required this.childName});

  @override
  State<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends State<WeeklySummaryScreen> {
  final _svc = WeeklySummaryService();
  List<Map<String, dynamic>> _summaries = [];
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _svc.watchWeeklySummaries(widget.childUid).listen((list) {
      if (mounted) setState(() { _summaries = list; _loading = false; });
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
  }

  String _appName(String? pkg) {
    if (pkg == null) return 'App';
    const names = {
      'com.google.android.youtube': 'YouTube',
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.snapchat.android': 'Snapchat',
      'com.facebook.katana': 'Facebook',
      'com.twitter.android': 'X',
      'com.whatsapp': 'WhatsApp',
      'com.discord': 'Discord',
      'com.roblox.client': 'Roblox',
    };
    if (names.containsKey(pkg)) return names[pkg]!;
    final parts = pkg.split('.');
    return parts.length >= 2
        ? parts.last[0].toUpperCase() + parts.last.substring(1)
        : pkg;
  }

  Color _colorFor(String? pkg) {
    const colors = [Color(0xFF1A73E8), Color(0xFF34A853), Color(0xFFEA4335),
      Color(0xFF9334E6), Color(0xFFFF6F00), Color(0xFF00897B)];
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
          Text('Weekly Summaries',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.calendar_view_week,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('No weekly summaries yet',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                        'Summaries are generated automatically every Sunday night',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.grey.shade400),
                        textAlign: TextAlign.center),
                  ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _summaries.length,
                  itemBuilder: (_, i) => _SummaryCard(
                    summary: _summaries[i],
                    fmt: _fmt,
                    appName: _appName,
                    colorFor: _colorFor,
                  ).animate(delay: (i * 60).ms).fadeIn().slideY(begin: 0.05),
                ),
    );
  }
}

class _SummaryCard extends StatefulWidget {
  final Map<String, dynamic> summary;
  final String Function(int) fmt;
  final String Function(String?) appName;
  final Color Function(String?) colorFor;

  const _SummaryCard(
      {required this.summary,
      required this.fmt,
      required this.appName,
      required this.colorFor});

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final weekKey   = s['weekKey']            as String? ?? s['_key'] as String? ?? '';
    final totalMs   = (s['totalScreenMs']     as num?)?.toInt() ?? 0;
    final avgMs     = (s['avgDailyMs']        as num?)?.toInt() ?? 0;
    final calls     = (s['totalCalls']        as num?)?.toInt() ?? 0;
    final sms       = (s['totalSms']          as num?)?.toInt() ?? 0;
    final days      = (s['daysWithData']      as num?)?.toInt() ?? 0;
    final topApps   = (s['topApps'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.calendar_view_week, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(weekKey, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              Text('$days days tracked',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            Text(widget.fmt(totalMs),
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
            Text('total screen time',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: [
              _HeaderStat('Avg/day', widget.fmt(avgMs)),
              const SizedBox(width: 20),
              _HeaderStat('Calls', '$calls'),
              const SizedBox(width: 20),
              _HeaderStat('Messages', '$sms'),
            ]),
          ]),
        ),

        // Top apps
        if (topApps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text('Top Apps',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show all',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFF1A73E8))),
              ),
            ]),
          ),
          ...(_expanded ? topApps : topApps.take(3)).map((a) {
            if (a is! Map) return const SizedBox.shrink();
            final m   = Map<String, dynamic>.from(a);
            final pkg = m['pkg'] as String?;
            final ms  = (m['usedMs'] as num?)?.toInt() ?? 0;
            final color = widget.colorFor(pkg);
            return ListTile(
              dense: true,
              leading: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    widget.appName(pkg).isNotEmpty
                        ? widget.appName(pkg)[0]
                        : '?',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ),
              title: Text(widget.appName(pkg),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Text(widget.fmt(ms),
                  style: GoogleFonts.inter(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            );
          }),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label, value;
  const _HeaderStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
      Text(value, style: GoogleFonts.plusJakartaSans(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}
