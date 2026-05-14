import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../services/alert_service.dart';

class BatteryAlertsScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const BatteryAlertsScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<BatteryAlertsScreen> createState() => _BatteryAlertsScreenState();
}

class _BatteryAlertsScreenState extends State<BatteryAlertsScreen> {
  int? _threshold;
  List<Map<String, dynamic>> _alerts = [];
  int? _currentBattery;
  bool _isCharging = false;

  StreamSubscription? _thresholdSub;
  StreamSubscription? _alertsSub;
  StreamSubscription? _deviceSub;

  @override
  void initState() {
    super.initState();
    _listenAll();
  }

  @override
  void dispose() {
    _thresholdSub?.cancel();
    _alertsSub?.cancel();
    _deviceSub?.cancel();
    super.dispose();
  }

  void _listenAll() {
    _thresholdSub =
        AlertService.instance.watchThreshold(widget.childUid).listen((t) {
      if (mounted) setState(() => _threshold = t);
    });

    _alertsSub = AlertService.instance
        .watchBatteryAlerts(widget.childUid)
        .listen((a) {
      if (mounted) setState(() => _alerts = a);
    });

    _deviceSub = FirebaseDatabase.instance
        .ref('deviceInfo/${widget.childUid}')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (v == null || v is! Map || !mounted) return;
      final m = Map<String, dynamic>.from(v);
      setState(() {
        _currentBattery = (m['batteryLevel'] as num?)?.toInt();
        _isCharging = m['isCharging'] == true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _alerts.where((a) => a['read'] != true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Battery Alerts',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            Text(widget.childName,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          if (_alerts.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: Text('Clear all',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.red.shade400)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current status card
          _StatusCard(
            battery: _currentBattery,
            isCharging: _isCharging,
            threshold: _threshold,
          ).animate().fadeIn().slideY(begin: 0.1),

          const SizedBox(height: 16),

          // Threshold setting card
          _ThresholdCard(
            threshold: _threshold,
            onSet: _setThreshold,
            onRemove: _removeThreshold,
          ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.1),

          const SizedBox(height: 20),

          Row(
            children: [
              Text('Alert History',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$unread new',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          if (_alerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Icon(Icons.battery_full,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No alerts yet',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('You\'ll be notified when battery is low',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey.shade400)),
                ],
              ),
            )
          else
            ...List.generate(_alerts.length, (i) {
              final a = _alerts[i];
              final level = (a['level'] as num?)?.toInt() ?? 0;
              final ts = a['timestamp'] as int?;
              final read = a['read'] as bool? ?? false;
              final key = a['_key'] as String;
              final time = ts != null
                  ? _fmt(DateTime.fromMillisecondsSinceEpoch(ts))
                  : '';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color:
                      read ? Colors.white : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: read
                      ? null
                      : Border.all(
                          color: Colors.orange.shade200, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _batteryColor(level).withValues(alpha: 0.15),
                    child: Icon(
                      level < 10
                          ? Icons.battery_alert
                          : Icons.battery_1_bar,
                      color: _batteryColor(level),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Battery at $level%',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(time,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey)),
                  trailing: read
                      ? null
                      : TextButton(
                          onPressed: () => _markRead(key),
                          child: Text('Dismiss',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF1A73E8))),
                        ),
                ),
              ).animate(delay: Duration(milliseconds: i * 40)).fadeIn();
            }),
        ],
      ),
    );
  }

  Color _batteryColor(int level) {
    if (level <= 10) return Colors.red;
    if (level <= 20) return Colors.orange;
    return const Color(0xFF34A853);
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _setThreshold(int percent) async {
    await AlertService.instance.setThreshold(widget.childUid, percent);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Alert threshold set to $percent%'),
        backgroundColor: const Color(0xFF34A853),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _removeThreshold() async {
    await AlertService.instance.removeThreshold(widget.childUid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Alert threshold removed'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _markRead(String key) async {
    await AlertService.instance.markAlertRead(widget.childUid, key);
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Clear History',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Delete all battery alerts for ${widget.childName}?',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await AlertService.instance.clearAlerts(widget.childUid);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final int? battery;
  final bool isCharging;
  final int? threshold;

  const _StatusCard({
    required this.battery,
    required this.isCharging,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    final level = battery ?? 0;
    final color = battery == null
        ? Colors.grey
        : level <= 10
            ? Colors.red
            : level <= 20
                ? Colors.orange
                : const Color(0xFF34A853);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCharging
                  ? Icons.battery_charging_full
                  : battery == null
                      ? Icons.battery_unknown
                      : level < 20
                          ? Icons.battery_alert
                          : Icons.battery_std,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  battery == null
                      ? 'No data'
                      : '$level%${isCharging ? ' — Charging' : ''}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
                Text(
                  battery == null
                      ? 'Waiting for device data'
                      : threshold != null
                          ? 'Alert set at $threshold%'
                          : 'No alert threshold set',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdCard extends StatelessWidget {
  final int? threshold;
  final Future<void> Function(int) onSet;
  final Future<void> Function() onRemove;

  const _ThresholdCard({
    required this.threshold,
    required this.onSet,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notifications_active_outlined,
                color: Color(0xFF1A73E8), size: 18),
            const SizedBox(width: 8),
            Text('Alert Threshold',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text(
            threshold != null
                ? 'Currently alerting when battery ≤ $threshold%'
                : 'No threshold set — no alerts will fire',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [10, 15, 20, 30, 50].map((pct) {
              final selected = threshold == pct;
              return GestureDetector(
                onTap: () => onSet(pct),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF1A73E8)
                        : const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$pct%',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : const Color(0xFF1A73E8),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (threshold != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRemove,
              child: Text('Remove threshold',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.red.shade400,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
  }
}
