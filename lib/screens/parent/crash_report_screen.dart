import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/device_event_service.dart';

class CrashReportScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const CrashReportScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<CrashReportScreen> createState() => _CrashReportScreenState();
}

class _CrashReportScreenState extends State<CrashReportScreen> {
  StreamSubscription? _sub;
  List<DeviceEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = DeviceEventService.watchEvents(widget.childUid).listen(
      (events) {
        if (!mounted) return;
        setState(() {
          _events = events;
          _loading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _markAllRead() async {
    await DeviceEventService.markAllRead(widget.childUid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All events marked as read'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear all events?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete all device health events '
          'for ${widget.childName}.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA4335),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DeviceEventService.clearAll(widget.childUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _events.where((e) => !e.read && e.needsAttention).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Health',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              widget.childName,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          if (_events.isNotEmpty) ...[
            if (unreadCount > 0)
              IconButton(
                tooltip: 'Mark all read',
                icon: const Icon(Icons.mark_email_read_outlined),
                onPressed: _markAllRead,
              ),
            IconButton(
              tooltip: 'Clear all events',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
            )
          : _events.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildSummaryBar(unreadCount),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _events.length,
                        itemBuilder: (context, i) {
                          return _EventCard(event: _events[i])
                              .animate(delay: Duration(milliseconds: i * 40))
                              .fadeIn()
                              .slideY(begin: 0.05, end: 0);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummaryBar(int unreadCount) {
    final errorCount =
        _events.where((e) => e.severity == 'error').length;
    final warnCount =
        _events.where((e) => e.severity == 'warning').length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _StatChip(
            label: 'Total',
            value: _events.length.toString(),
            color: const Color(0xFF1A73E8),
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Errors',
            value: errorCount.toString(),
            color: const Color(0xFFEA4335),
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Warnings',
            value: warnCount.toString(),
            color: const Color(0xFFFF6D00),
          ),
          const Spacer(),
          if (unreadCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEA4335),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$unreadCount unread',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4EA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.verified_outlined,
              size: 44,
              color: Color(0xFF34A853),
            ),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text(
            'All clear',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No health events recorded for\n${widget.childName}\'s device.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF5F6368),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EventCard
// ─────────────────────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final DeviceEvent event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(event.severity);
    final icon  = _typeIcon(event.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.typeLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF202124),
                          ),
                        ),
                      ),
                      if (!event.read && event.needsAttention)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (event.message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.message,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF5F6368),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _relativeTime(event.dateTime),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'error':   return const Color(0xFFEA4335);
      case 'warning': return const Color(0xFFFF6D00);
      default:        return const Color(0xFF1A73E8);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'service_started':  return Icons.play_circle_outline;
      case 'service_stopped':  return Icons.stop_circle_outlined;
      case 'service_crash':    return Icons.error_outline;
      case 'service_restored': return Icons.restart_alt;
      case 'monitoring_error': return Icons.warning_amber_outlined;
      case 'flutter_error':    return Icons.bug_report_outlined;
      default:                 return Icons.info_outline;
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StatChip
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
