import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 24-hour activity heatmap for a single day.
///
/// Reads from `hourly_usage/$childUid/$dateStr/{0..23}` where each key is an
/// hour (0–23) and the value is the total minutes of screen time in that hour.
/// The background service writes this data every 15 minutes.
class HourlyHeatmapWidget extends StatefulWidget {
  final String childUid;

  const HourlyHeatmapWidget({super.key, required this.childUid});

  @override
  State<HourlyHeatmapWidget> createState() => _HourlyHeatmapWidgetState();
}

class _HourlyHeatmapWidgetState extends State<HourlyHeatmapWidget> {
  final _db = FirebaseDatabase.instance.ref();

  // hourlyData[hour] = minutes of usage in that hour (0–60).
  final List<int> _hourlyData = List.filled(24, 0);
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _listen() {
    _sub?.cancel();
    final dateStr = _dateKey(_selectedDate);
    _sub = _db
        .child('hourly_usage/${widget.childUid}/$dateStr')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final raw = event.snapshot.value;
      final data = List.filled(24, 0);
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        for (int h = 0; h < 24; h++) {
          data[h] = (m['$h'] as num?)?.toInt() ?? 0;
        }
      }
      setState(() {
        for (int i = 0; i < 24; i++) _hourlyData[i] = data[i];
        _loading = false;
      });
    });
  }

  void _changeDay(int delta) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: delta));
      _loading = true;
    });
    _listen();
  }

  Color _cellColor(int minutes) {
    if (minutes == 0) return const Color(0xFFF1F3F4);
    if (minutes < 5)  return const Color(0xFFBBDEFB);
    if (minutes < 15) return const Color(0xFF64B5F6);
    if (minutes < 30) return const Color(0xFF1E88E5);
    if (minutes < 45) return const Color(0xFF1565C0);
    return const Color(0xFF0D47A1);
  }

  String _hourLabel(int h) {
    if (h == 0)  return '12a';
    if (h < 12)  return '${h}a';
    if (h == 12) return '12p';
    return '${h - 12}p';
  }

  String _fmt(int minutes) {
    if (minutes == 0) return 'No use';
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  int get _totalMinutes => _hourlyData.fold(0, (s, v) => s + v);
  int get _peakHour {
    int max = 0, peak = 0;
    for (int i = 0; i < 24; i++) {
      if (_hourlyData[i] > max) { max = _hourlyData[i]; peak = i; }
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _dateKey(_selectedDate) == _dateKey(DateTime.now());
    final canGoForward = !isToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date navigation
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _changeDay(-1),
          ),
          Expanded(
            child: Text(
              isToday ? 'Today' : _dateKey(_selectedDate),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                color: canGoForward ? null : Colors.grey.shade300),
            onPressed: canGoForward ? () => _changeDay(1) : null,
          ),
        ]),

        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          // Summary row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              _StatChip(
                label: 'Total',
                value: _fmt(_totalMinutes),
                color: const Color(0xFF1A73E8),
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Peak hour',
                value: _totalMinutes > 0 ? _hourLabel(_peakHour) : '—',
                color: const Color(0xFF9334E6),
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Active hrs',
                value: '${_hourlyData.where((v) => v > 0).length}',
                color: const Color(0xFF34A853),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // Heatmap grid — 6 columns × 4 rows
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (ctx, constraints) {
              final cellW = (constraints.maxWidth - 5 * 8) / 6;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(24, (h) {
                  final minutes = _hourlyData[h];
                  final color = _cellColor(minutes);
                  return Tooltip(
                    message: '${_hourLabel(h)} — ${_fmt(minutes)}',
                    child: GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                            '${_hourLabel(h)}: ${_fmt(minutes)}',
                          ),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: cellW,
                        height: cellW * 0.8,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            _hourLabel(h),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: minutes >= 15
                                  ? Colors.white
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
                const SizedBox(width: 4),
                ...[ 0, 5, 15, 30, 45].map((m) => Container(
                  width: 14, height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _cellColor(m > 0 ? m : 0),
                    borderRadius: BorderRadius.circular(3),
                    border: m == 0 ? Border.all(color: Colors.grey.shade300) : null,
                  ),
                )),
                const SizedBox(width: 4),
                Text('More', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: GoogleFonts.inter(fontSize: 9, color: Colors.grey.shade600)),
      ]),
    );
  }
}
