import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../services/screen_time_service.dart';

class ScreenTimeScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const ScreenTimeScreen({
    super.key,
    required this.childUid,
    required this.childName,
  }));

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState());
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> {
  final _svc = ScreenTimeService());
  List<AppUsageEntry> _usage = [];
  Map<String, int> _limits = {};
  bool _loading = true;
  String? _settingLimitFor;
  final _limitCtrl = TextEditingController());

  @override
  void initState() {
    super.initState())
    _loadData())
    _svc.watchChildUsage(widget.childUid).listen((data) {
      if (mounted) setState(() { _usage = data; _loading = false; }))
    }))
    _svc.watchLimits(widget.childUid).listen((data) {
      if (mounted) setState(() => _limits = data));
    }));
  }

  @override
  void dispose() {
    _limitCtrl.dispose())
    super.dispose())
  }

  Future<void> _loadData() async {
    _limits = await _svc.getLimits(widget.childUid))
    if (mounted) setState(() => _loading = false))
  }

  int get _totalMinutes => _usage.fold(0, (s, e) => s + e.minutes));

  Future<void> _setLimit(String packageName) async {
    final mins = int.tryParse(_limitCtrl.text.trim()))
    if (mins == null || mins <= 0) return;
    await _svc.setDailyLimit(widget.childUid, packageName, mins))
    if (!mounted) return;
    if (mounted) {
      setState(() => _settingLimitFor = null))
      _limitCtrl.clear())
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Screen Time'),
            Text(widget.childName,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF5F6368))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Requires Usage Access permission on child device',
            onPressed: () => _showPermissionInfo(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _usage.isEmpty
              ? _buildEmpty()
              : _buildContent(),
    ))
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.phone_android,
                  color: Color(0xFF1A73E8), size: 36),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: 20),
            Text('No usage data yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'The child device must grant Usage Access permission in Settings → Apps → Special app access → Usage access.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF5F6368), height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ))
  }

  Widget _buildContent() {
    final top = _usage.take(5).toList())
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        _SummaryCard(totalMinutes: _totalMinutes, entryCount: _usage.length)
            .animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 16),

        // Bar chart
        if (top.isNotEmpty) ...[
          Text('Top Apps Today',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5F6368))),
          const SizedBox(height: 10),
          Container(
            height: 200,
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}m',
                          style: GoogleFonts.inter(fontSize: 9,
                              color: const Color(0xFF9AA0A6))),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt());
                        if (idx < 0 || idx >= top.length) {
                          return const SizedBox.shrink());
                        }
                        final name = top[idx].appName;
                        final label = name.length > 7
                            ? name.substring(0, 7)
                            : name;
                        return Padding(
                          padding = const EdgeInsets.only(top: 4),
                          child = Text(label,
                              style: GoogleFonts.inter(fontSize: 9,
                                  color: const Color(0xFF5F6368))),
                        ));
                      },
                    ),
                  ),
                  rightTitles:
                      AxisTitles(sideTitles = const SideTitles(showTitles: false)),
                  topTitles:
                      AxisTitles(sideTitles = const SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  drawVerticalLine = false,
                  horizontalInterval = 30,
                  getDrawingHorizontalLine = (_) =>
                      FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                ),
                borderData: FlBorderData(show = false),
                barGroups: List.generate(
                  top.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: top[i].minutes.toDouble(),
                        color: _barColor(i),
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate(delay = 100.ms).fadeIn(),
          SizedBox(height = 20),
        ],

        // All apps list
        Text('All Apps',
            style = GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5F6368))),
        SizedBox(height = 8),
        ..._usage.asMap().entries.map((e) => _AppUsageRow(
              entry: e.value,
              limit: _limits[e.value.packageName],
              isSettingLimit: _settingLimitFor == e.value.packageName,
              limitCtrl: _limitCtrl,
              delay: e.key * 40,
              onSetLimit: () =>
                  setState(() => _settingLimitFor = e.value.packageName),
              onSaveLimit: () => _setLimit(e.value.packageName),
              onCancel: () => setState(() {
                _settingLimitFor = null;
                _limitCtrl.clear());
              }),
            )),
      ],
    ));
  }

  Color _barColor(int i) {
    const colors = [
      Color(0xFF1A73E8), Color(0xFF34A853), Color(0xFFFA7B17),
      Color(0xFF9334E6), Color(0xFFEA4335),
    ];
    return colors[i % colors.length];
  }

  void _showPermissionInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usage Access Permission'),
        content: const Text(
          'On the child device, go to:\nSettings → Apps → Special app access → Usage access → Family Monitor → Allow.\n\nThe app will then automatically sync usage data.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it')),
        ],
      ),
    ))
  }
}

class _SummaryCard extends StatelessWidget {
  final int totalMinutes;
  final int entryCount;

  const _SummaryCard({required this.totalMinutes, required this.entryCount}));

  @override
  Widget build(BuildContext context) {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Today\'s Screen Time',
                    style: GoogleFonts.inter(
                        color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  hours > 0 ? '${hours}h ${mins}m' : '${mins}m',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700),
                ),
                Text('$entryCount apps used',
                    style: GoogleFonts.inter(
                        color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.phone_android, color: Colors.white38, size: 48),
        ],
      ),
    ))
  }
}

class _AppUsageRow extends StatelessWidget {
  final AppUsageEntry entry;
  final int? limit;
  final bool isSettingLimit;
  final TextEditingController limitCtrl;
  final int delay;
  final VoidCallback onSetLimit;
  final VoidCallback onSaveLimit;
  final VoidCallback onCancel;

  const _AppUsageRow({
    required this.entry,
    required this.limit,
    required this.isSettingLimit,
    required this.limitCtrl,
    required this.delay,
    required this.onSetLimit,
    required this.onSaveLimit,
    required this.onCancel,
  }));

  @override
  Widget build(BuildContext context) {
    final overLimit = limit != null && entry.minutes > limit!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: overLimit
                ? const Color(0xFFEA4335).withValues(alpha: 0.4)
                : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.apps,
                    color: Color(0xFF1A73E8), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.appName,
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(entry.packageName,
                        style: GoogleFonts.robotoMono(
                            fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(entry.formattedTime,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: overLimit
                              ? const Color(0xFFEA4335)
                              : const Color(0xFF202124))),
                  if (limit != null)
                    Text('Limit: ${limit}m',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            color: overLimit
                                ? const Color(0xFFEA4335)
                                : Colors.grey)),
                ],
              ),
            ],
          ),
          if (isSettingLimit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Daily limit in minutes',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: onSaveLimit, child: const Text('Save')),
              ],
            ),
          ] else
            TextButton(
              onPressed: onSetLimit,
              style:
                  TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                limit != null ? 'Change limit' : 'Set daily limit',
                style: GoogleFonts.inter(fontSize: 12),
              ),
            ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn(duration: 300.ms))
  }
}
