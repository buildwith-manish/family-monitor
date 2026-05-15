import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/keyword_alert_service.dart';

class KeywordAlertScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const KeywordAlertScreen(
      {super.key, required this.childUid, required this.childName});

  @override
  State<KeywordAlertScreen> createState() => _KeywordAlertScreenState();
}

class _KeywordAlertScreenState extends State<KeywordAlertScreen>
    with SingleTickerProviderStateMixin {
  final _svc = KeywordAlertService();
  late TabController _tabs;

  List<String> _keywords = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _loadingAlerts = true;

  StreamSubscription? _kwSub;
  StreamSubscription? _alertSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _kwSub = _svc.watchKeywords(widget.childUid).listen((kw) {
      if (mounted) setState(() => _keywords = kw);
    });
    _alertSub = _svc.watchAlerts(widget.childUid).listen((a) {
      if (mounted) setState(() { _alerts = a; _loadingAlerts = false; });
    });
  }

  @override
  void dispose() {
    _kwSub?.cancel();
    _alertSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  int get _unread => _alerts.where((a) => a['read'] != true).length;

  Future<void> _addKeyword() async {
    final ctrl = TextEditingController();
    final word = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Keyword',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Messages containing this word will trigger an alert.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              hintText: 'e.g. meet me, drugs, fight',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (word != null && word.isNotEmpty) {
      await _svc.addKeyword(widget.childUid, word);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Keyword "$word" added'),
          backgroundColor: const Color(0xFF34A853),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Keyword Alerts',
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
          tabs: [
            const Tab(text: 'Keywords'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Alerts'),
                if (_unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA4335),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$_unread',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabs,
        builder: (_, __) => _tabs.index == 0
            ? FloatingActionButton.extended(
                onPressed: _addKeyword,
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: Text('Add Keyword',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              )
            : const SizedBox.shrink(),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildKeywords(), _buildAlerts()],
      ),
    );
  }

  // ── Keywords tab ──────────────────────────────────────────────────────────

  Widget _buildKeywords() {
    if (_keywords.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.manage_search, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No keywords yet',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Add words or phrases to watch for in SMS messages',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addKeyword,
            icon: const Icon(Icons.add),
            label: const Text('Add Keyword'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The child\'s background service scans incoming and outgoing '
                'SMS for these words after every sync.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text('${_keywords.length} keyword${_keywords.length == 1 ? '' : 's'} active',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: _keywords.length,
            itemBuilder: (_, i) {
              final kw = _keywords[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6, offset: const Offset(0, 2),
                  )],
                ),
                child: ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE8E6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.search,
                        color: Color(0xFFEA4335), size: 18),
                  ),
                  title: Text(kw,
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('Scanning all SMS messages',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () async {
                      await _svc.removeKeyword(widget.childUid, kw);
                    },
                  ),
                ),
              ).animate(delay: (i * 40).ms).fadeIn();
            },
          ),
        ),
      ]),
    );
  }

  // ── Alerts tab ────────────────────────────────────────────────────────────

  Widget _buildAlerts() {
    if (_loadingAlerts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_alerts.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.notifications_none_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No alerts yet',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Alerts appear when a keyword is found in an SMS',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }

    return Column(children: [
      if (_unread > 0)
        Container(
          color: const Color(0xFFFCE8E6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Icon(Icons.notifications_active,
                color: Color(0xFFEA4335), size: 18),
            const SizedBox(width: 8),
            Text('$_unread unread alert${_unread > 1 ? 's' : ''}',
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFFEA4335),
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                for (final a in _alerts) {
                  final key = a['_key'] as String?;
                  if (key != null && a['read'] != true) {
                    await _svc.markRead(widget.childUid, key);
                  }
                }
              },
              child: Text('Mark all read',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF1A73E8))),
            ),
          ]),
        ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _alerts.length,
          itemBuilder: (_, i) {
            final a    = _alerts[i];
            final key  = a['_key'] as String? ?? '';
            final kw   = a['keyword'] as String? ?? '';
            final from = a['from']    as String? ?? 'Unknown';
            final snippet = a['messageSnippet'] as String? ?? '';
            final ts = a['timestamp'] as int?;
            final read = a['read'] as bool? ?? false;

            final time = ts != null
                ? _timeAgo(DateTime.fromMillisecondsSinceEpoch(ts))
                : '';

            return GestureDetector(
              onTap: () => _svc.markRead(widget.childUid, key),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: read ? Colors.white : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: read
                      ? Border.all(color: Colors.grey.shade100)
                      : Border.all(color: Colors.orange.shade200),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6, offset: const Offset(0, 2),
                  )],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA4335),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('"$kw"',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('from $from',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(time,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey)),
                    if (!read) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFFEA4335),
                            shape: BoxShape.circle),
                      ),
                    ],
                  ]),
                  if (snippet.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(snippet,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ),
            ).animate(delay: (i * 40).ms).fadeIn();
          },
        ),
      ),
    ]);
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
