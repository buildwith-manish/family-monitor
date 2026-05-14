import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/call_log_service.dart';
import '../../services/sms_service.dart';

class SmsCallLogScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const SmsCallLogScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<SmsCallLogScreen> createState() => _SmsCallLogScreenState();
}

class _SmsCallLogScreenState extends State<SmsCallLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<SmsEntry> _sms = [];
  List<CallRecord> _calls = [];

  bool _smsLoading = true;
  bool _callsLoading = true;

  StreamSubscription? _smsSub;
  StreamSubscription? _callSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _listenSms();
    _listenCalls();
    _requestSync();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _smsSub?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  void _listenSms() {
    _smsSub = SmsService.watchMessages(widget.childUid).listen((msgs) {
      if (mounted) setState(() { _sms = msgs; _smsLoading = false; });
    });
  }

  void _listenCalls() {
    final svc = CallLogService();
    _callSub = svc.watchCallLog(widget.childUid).listen((records) {
      if (mounted) setState(() { _calls = records; _callsLoading = false; });
    });
  }

  Future<void> _requestSync() async {
    await SmsService.requestSync(widget.childUid);
    await CallLogService().requestSync(widget.childUid);
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
              'Messages & Calls',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(widget.childName,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: _requestSync,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.sms_outlined, size: 18),
                const SizedBox(width: 6),
                Text('SMS (${_sms.length})'),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.call_outlined, size: 18),
                const SizedBox(width: 6),
                Text('Calls (${_calls.length})'),
              ]),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _SmsTab(
            messages: _sms,
            loading: _smsLoading,
          ),
          _CallsTab(
            calls: _calls,
            loading: _callsLoading,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// SMS Tab
// ─────────────────────────────────────────────────

class _SmsTab extends StatelessWidget {
  final List<SmsEntry> messages;
  final bool loading;

  const _SmsTab({required this.messages, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (messages.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.sms_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No SMS data yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Syncs automatically when child device is active',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final msg = messages[i];
        final isIn = msg.isIncoming;
        final initials = msg.address.isNotEmpty
            ? msg.address.trim()[0].toUpperCase()
            : '?';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isIn
                    ? const Color(0xFFE8F0FE)
                    : const Color(0xFFFCE8E6),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isIn
                        ? const Color(0xFF1A73E8)
                        : const Color(0xFFEA4335),
                    fontSize: 14,
                  ),
                ),
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
                            msg.address,
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF202124)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          msg.timeLabel,
                          style: GoogleFonts.inter(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      msg.body,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: const Color(0xFF5F6368)),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isIn
                      ? const Color(0xFFE8F0FE)
                      : const Color(0xFFFCE8E6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isIn ? 'IN' : 'OUT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isIn
                        ? const Color(0xFF1A73E8)
                        : const Color(0xFFEA4335),
                  ),
                ),
              ),
            ],
          ),
        ).animate(delay: Duration(milliseconds: i * 30)).fadeIn();
      },
    );
  }
}

// ─────────────────────────────────────────────────
// Calls Tab
// ─────────────────────────────────────────────────

class _CallsTab extends StatelessWidget {
  final List<CallRecord> calls;
  final bool loading;

  const _CallsTab({required this.calls, required this.loading});

  Color _typeColor(String type) {
    switch (type) {
      case 'missed': return const Color(0xFFEA4335);
      case 'outgoing': return const Color(0xFF1A73E8);
      default: return const Color(0xFF34A853);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'missed': return Icons.call_missed;
      case 'outgoing': return Icons.call_made;
      default: return Icons.call_received;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (calls.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.call_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No call log data yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Syncs automatically when child device is active',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: calls.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final call = calls[i];
        final color = _typeColor(call.type);
        final icon = _typeIcon(call.type);
        final initials = call.displayName.isNotEmpty
            ? call.displayName[0].toUpperCase()
            : '?';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.displayName,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF202124)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      call.durationLabel,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(height: 4),
                  Text(
                    call.timeLabel,
                    style:
                        GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ).animate(delay: Duration(milliseconds: i * 30)).fadeIn();
      },
    );
  }
}
