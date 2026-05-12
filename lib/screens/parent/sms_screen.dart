import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/sms_service.dart';

class SmsScreen extends StatefulWidget {
  final String childUid, childName;
  const SmsScreen({super.key, required this.childUid, required this.childName});
  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  List<SmsEntry> _msgs = [];
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = SmsService.watchMessages(widget.childUid).listen((m) {
      if (!mounted) return;
    setState(() { _msgs = m; _loading = false; });
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Messages', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          Text(widget.childName, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [IconButton(
          icon: const Icon(Icons.sync),
          onPressed: () async {
            await SmsService.requestSync(widget.childUid);
            if (!mounted) return;
    if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sync requested — child app will upload shortly'))));
          },
        )],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _msgs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.message_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('No messages yet', style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 6),
              Text('Tap ↻ to request sync',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (ctx, i) {
                final m = _msgs[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: m.isIncoming ? const Color(0xFFE8F0FE) : const Color(0xFFE6F4EA),
                      child: Icon(
                        m.isIncoming ? Icons.call_received : Icons.call_made,
                        color: m.isIncoming ? const Color(0xFF1A73E8) : const Color(0xFF34A853),
                        size: 18),
                    ),
                    title: Text(m.address,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700)),
                    trailing: Text(m.timeLabel,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                  ),
                ).animate(delay: Duration(milliseconds: i * 20)).fadeIn(duration: 200.ms)
              }),
    );
  }
}
