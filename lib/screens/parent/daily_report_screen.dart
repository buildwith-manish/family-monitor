// lib/screens/parent/daily_report_screen.dart
//
// Displays the structured daily summaries written by DailyReportService.
// Shows the last 30 days of reports for a specific child, with the most
// recent day expanded by default.

import 'dart:async';

import 'package:flutter/material.dart';
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

class _DailyReportScreenState extends State<DailyReportScreen> {
  final _svc = DailyReportService.instance;

  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _expandedDate;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _svc.watchReports(widget.childUid).listen((reports) {
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        if (_expandedDate == null && reports.isNotEmpty) {
          _expandedDate = reports.first['date'] as String?;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _requestRefresh() async {
    setState(() => _loading = true);
    await _svc.forceGenerate(widget.childUid);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Reports',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh today\'s report',
            onPressed: _requestRefresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  itemBuilder: (ctx, i) => _ReportCard(
                    report: _reports[i],
                    expanded:
                        _reports[i]['date'] == _expandedDate,
                    onTap: () {
                      setState(() {
                        final date = _reports[i]['date'] as String?;
                        _expandedDate =
                            _expandedDate == date ? null : date;
                      });
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.summarize_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No reports yet',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Reports are generated once a day\non the child\'s device.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual report card with collapsible detail
// ─────────────────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool expanded;
  final VoidCallback onTap;

  const _ReportCard({
    required this.report,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date          = report['date'] as String? ?? '—';
    final screenMin     = (report['screenTimeMinutes'] as num?)?.toInt() ?? 0;
    final battLevel     = (report['batteryLevel']      as num?)?.toInt();
    final battAlerts    = (report['batteryAlertCount']  as num?)?.toInt() ?? 0;
    final geoAlerts     = (report['geofenceAlertCount'] as num?)?.toInt() ?? 0;
    final healthEvents  = (report['healthEventCount']   as num?)?.toInt() ?? 0;
    final generatedAt   = (report['generatedAt']        as num?)?.toInt() ?? 0;
    final topAppsRaw    = report['topApps'];
    final lastLoc       = report['lastLocation'];

    final topApps = topAppsRaw is List
        ? topAppsRaw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header (always visible) ────────────────────────────────────
          InkWell(
            borderRadius: expanded
                ? const BorderRadius.vertical(top: Radius.circular(14))
                : BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(Icons.calendar_today,
                          color: Color(0xFF1A73E8), size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(date),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmtMinutes(screenMin)} screen time'
                          '${battLevel != null ? ' · $battLevel% battery' : ''}',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (battAlerts > 0)
                        _Badge(
                            label: '$battAlerts🔋',
                            color: const Color(0xFFEA4335)),
                      if (geoAlerts > 0)
                        _Badge(
                            label: '$geoAlerts📍',
                            color: const Color(0xFFFA7B17)),
                      if (healthEvents > 0)
                        _Badge(
                            label: '$healthEvents⚠',
                            color: const Color(0xFFFF6D00)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded detail ─────────────────────────────────────────────
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top apps
                  if (topApps.isNotEmpty) ...[
                    _SectionHeader('Top Apps'),
                    const SizedBox(height: 8),
                    ...topApps.map((app) {
                      final pkg = app['packageName'] as String? ?? '?';
                      final min = (app['minutes'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _pkgColor(pkg),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _friendlyPkg(pkg),
                                style: GoogleFonts.inter(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _fmtMinutes(min),
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A73E8)),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],

                  // Alert summary
                  _SectionHeader('Alerts'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                          label: 'Battery',
                          value: battAlerts,
                          icon: Icons.battery_alert,
                          color: const Color(0xFFEA4335)),
                      _StatChip(
                          label: 'Geofence',
                          value: geoAlerts,
                          icon: Icons.location_on,
                          color: const Color(0xFFFA7B17)),
                      _StatChip(
                          label: 'Health',
                          value: healthEvents,
                          icon: Icons.warning_amber,
                          color: const Color(0xFFFF6D00)),
                    ],
                  ),

                  // Last location
                  if (lastLoc is Map) ...[
                    const SizedBox(height: 12),
                    _SectionHeader('Last Known Location'),
                    const SizedBox(height: 8),
                    _LocationRow(loc: Map<String, dynamic>.from(lastLoc)),
                  ],

                  // Footer: generation time
                  if (generatedAt > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Generated ${_timeLabel(generatedAt)}',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Formatting helpers ───────────────────────────────────────────────────

  String _formatDate(String iso) {
    try {
      final dt  = DateTime.parse(iso);
      final now = DateTime.now();
      if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day) return 'Today';
      if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day - 1) return 'Yesterday';
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _fmtMinutes(int min) {
    if (min < 60) return '${min}m';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _timeLabel(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h  = dt.hour.toString().padLeft(2, '0');
    final m  = dt.minute.toString().padLeft(2, '0');
    return 'at $h:$m';
  }

  String _friendlyPkg(String pkg) {
    const names = {
      'com.google.android.youtube': 'YouTube',
      'com.instagram.android':      'Instagram',
      'com.zhiliaoapp.musically':   'TikTok',
      'com.snapchat.android':       'Snapchat',
      'com.android.chrome':         'Chrome',
      'com.discord':                'Discord',
      'com.roblox.client':          'Roblox',
      'com.netflix.mediaclient':    'Netflix',
    };
    if (names.containsKey(pkg)) return names[pkg]!;
    final parts = pkg.split('.');
    if (parts.length >= 2) {
      final last = parts.last;
      return last.isNotEmpty
          ? '${last[0].toUpperCase()}${last.substring(1)}'
          : pkg;
    }
    return pkg;
  }

  Color _pkgColor(String pkg) {
    const palette = [
      Color(0xFF1A73E8),
      Color(0xFF34A853),
      Color(0xFFEA4335),
      Color(0xFF9334E6),
      Color(0xFFFF6F00),
      Color(0xFF00897B),
    ];
    return palette[pkg.hashCode.abs() % palette.length];
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          letterSpacing: 0.5),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _StatChip(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value > 0 ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value > 0
              ? color.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: value > 0 ? color : Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: value > 0 ? color : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final Map<String, dynamic> loc;
  const _LocationRow({required this.loc});

  @override
  Widget build(BuildContext context) {
    final lat      = (loc['lat'] as num?)?.toDouble();
    final lng      = (loc['lng'] as num?)?.toDouble();
    final accuracy = (loc['accuracy'] as num?)?.toDouble();
    final ts       = (loc['timestamp'] as num?)?.toInt() ?? 0;

    if (lat == null || lng == null) {
      return Text('No location data',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey));
    }

    return Row(
      children: [
        const Icon(Icons.location_pin, color: Color(0xFFEA4335), size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
            '${accuracy != null ? ' (±${accuracy.toStringAsFixed(0)}m)' : ''}',
            style: GoogleFonts.robotoMono(fontSize: 12),
          ),
        ),
        if (ts > 0)
          Text(
            _timeLabel(ts),
            style:
                GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
          ),
      ],
    );
  }

  String _timeLabel(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1)   return '${d.inMinutes}m ago';
    if (d.inDays < 1)    return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
