import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_install_alert_service.dart';

class AppInstallAlertsScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const AppInstallAlertsScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<AppInstallAlertsScreen> createState() => _AppInstallAlertsScreenState();
}

class _AppInstallAlertsScreenState extends State<AppInstallAlertsScreen> {
  final _svc = AppInstallAlertService();
  List<Map<String, dynamic>> _alerts = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _svc.watchAlerts(widget.childUid).listen((a) {
      if (!mounted) return;
      setState(() => _alerts = a);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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

  String _timeLabel(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Clear all alerts?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _svc.clearAll(widget.childUid);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _alerts.where((a) => a['read'] != true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('App Alerts',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ]),
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
      body: _alerts.isEmpty
          ? Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.app_registration,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('No app alerts yet',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 8),
                Text('You\'ll be notified when apps are installed or removed',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.grey.shade400),
                    textAlign: TextAlign.center),
              ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFF1A73E8), size: 18),
                      const SizedBox(width: 8),
                      Text('$unread unread alert${unread > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF1A73E8),
                              fontWeight: FontWeight.w500)),
                    ]),
                  ).animate().fadeIn(),
                ..._alerts.asMap().entries.map((entry) {
                  final i = entry.key;
                  final a = entry.value;
                  final type = a['type'] as String? ?? 'installed';
                  final pkg = a['packageName'] as String?;
                  final ts = (a['timestamp'] as num?)?.toInt() ?? 0;
                  final read = a['read'] as bool? ?? false;
                  final key = a['_key'] as String;
                  final isInstall = type == 'installed';
                  final color =
                      isInstall ? const Color(0xFF34A853) : Colors.red;
                  final icon =
                      isInstall ? Icons.download_done : Icons.delete_outline;

                  return GestureDetector(
                    onTap: () async {
                      if (!read) await _svc.markRead(widget.childUid, key);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: read
                            ? Colors.white
                            : color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: read
                            ? null
                            : Border.all(
                                color: color.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isInstall ? 'App Installed' : 'App Removed',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                              Text(
                                _appName(pkg),
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                              Text(
                                pkg ?? '',
                                style: GoogleFonts.robotoMono(
                                    fontSize: 10, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_timeLabel(ts),
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: Colors.grey)),
                            if (!read)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle),
                              ),
                          ],
                        ),
                      ]),
                    ).animate(delay: (i * 40).ms).fadeIn().slideY(begin: 0.05),
                  );
                }),
              ],
            ),
    );
  }
}
