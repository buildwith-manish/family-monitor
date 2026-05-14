import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

class _DailyReportScreenState extends State<DailyReportScreen>
    with SingleTickerProviderStateMixin {
  final _svc = DailyReportService();
  late TabController _tabs;

  List<Map<String, dynamic>> _reports = [];
  Map<String, dynamic>? _todayUsage;
  bool _loading = true;
  bool _generating = false;
  bool _exportingPdf = false;

  StreamSubscription? _reportsSub;
  StreamSubscription? _todaySub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _reportsSub = _svc.watchReports(widget.childUid).listen((r) {
      if (!mounted) return;
      setState(() {
        _reports = r;
        _loading = false;
      });
    });
    _todaySub = _svc.watchTodayUsage(widget.childUid).listen((u) {
      if (!mounted) return;
      setState(() => _todayUsage = u);
    });
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    _todaySub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
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

  Color _colorFor(String? pkg) {
    const colors = [
      Color(0xFF1A73E8), Color(0xFF34A853),
      Color(0xFFEA4335), Color(0xFF9334E6),
      Color(0xFFFF6F00), Color(0xFF00897B),
    ];
    return colors[(pkg?.hashCode ?? 0).abs() % colors.length];
  }

  String _timeLabel(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  Set<String> get _existingDates =>
      _reports.map((r) => r['date'] as String? ?? '').toSet();

  // ─── Generate Report sheet ───────────────────────────────────────────────

  Future<void> _showGenerateSheet() async {
    // Build list of last 14 days (excluding today — today shows in the Today tab).
    final today = DateTime.now();
    final candidates = List.generate(14, (i) {
      final d = today.subtract(Duration(days: i + 1));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });

    final selectedDates = <String>{};
    final selectedSections = <String>{'App Usage', 'Call Log', 'SMS', 'Location'};

    const allSections = ['App Usage', 'Call Log', 'SMS', 'Location', 'Screenshots'];
    const sectionIcons = {
      'App Usage': Icons.apps_rounded,
      'Call Log': Icons.call_outlined,
      'SMS': Icons.sms_outlined,
      'Location': Icons.location_on_outlined,
      'Screenshots': Icons.camera_alt_outlined,
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_graph,
                            color: Color(0xFF1A73E8), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Generate Reports',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          Text('Pick dates & content sections',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),

                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // ── Section 1: Content to include ──────────────────
                      _SheetSection(
                        icon: Icons.checklist_rounded,
                        title: 'What to include',
                        subtitle:
                            'Select the data sections for these reports',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allSections.map((s) {
                          final selected = selectedSections.contains(s);
                          return FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(sectionIcons[s],
                                    size: 14,
                                    color: selected
                                        ? const Color(0xFF1A73E8)
                                        : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(s),
                              ],
                            ),
                            selected: selected,
                            onSelected: (v) => setSheet(() {
                              if (v) {
                                selectedSections.add(s);
                              } else {
                                selectedSections.remove(s);
                              }
                            }),
                            selectedColor:
                                const Color(0xFFE8F0FE),
                            checkmarkColor: const Color(0xFF1A73E8),
                            labelStyle: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: selected
                                  ? const Color(0xFF1A73E8)
                                  : Colors.grey.shade700,
                            ),
                            backgroundColor: Colors.grey.shade100,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xFF1A73E8)
                                        .withValues(alpha: 0.4)
                                    : Colors.transparent,
                              ),
                            ),
                            showCheckmark: false,
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // ── Section 2: Date selection ──────────────────────
                      Row(children: [
                        _SheetSection(
                          icon: Icons.date_range,
                          title: 'Select dates',
                          subtitle: 'Last 14 days — grey = report exists',
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setSheet(() {
                            final missing = candidates
                                .where((d) =>
                                    !_existingDates.contains(d))
                                .toSet();
                            if (selectedDates.containsAll(missing)) {
                              selectedDates.clear();
                            } else {
                              selectedDates.addAll(missing);
                            }
                          }),
                          child: Text('Select missing',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF1A73E8),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // Date grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2.4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: candidates.length,
                        itemBuilder: (_, i) {
                          final dateStr = candidates[i];
                          final alreadyExists =
                              _existingDates.contains(dateStr);
                          final isSelected =
                              selectedDates.contains(dateStr);

                          // Parse for display
                          final parts = dateStr.split('-');
                          final d = DateTime(
                              int.parse(parts[0]),
                              int.parse(parts[1]),
                              int.parse(parts[2]));
                          final label =
                              '${_weekdayShort(d.weekday)}\n${d.day} ${_monthShort(d.month)}';

                          return GestureDetector(
                            onTap: alreadyExists
                                ? null
                                : () => setSheet(() {
                                      if (isSelected) {
                                        selectedDates.remove(dateStr);
                                      } else {
                                        selectedDates.add(dateStr);
                                      }
                                    }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: alreadyExists
                                    ? Colors.grey.shade100
                                    : isSelected
                                        ? const Color(0xFF1A73E8)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: alreadyExists
                                      ? Colors.grey.shade200
                                      : isSelected
                                          ? const Color(0xFF1A73E8)
                                          : Colors.grey.shade300,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                        color: alreadyExists
                                            ? Colors.grey.shade400
                                            : isSelected
                                                ? Colors.white
                                                : Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                  if (alreadyExists)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(Icons.check_circle,
                                          size: 12,
                                          color: const Color(0xFF34A853)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // ── Bottom action bar ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            selectedDates.isEmpty
                                ? 'Select at least one date to generate'
                                : '${selectedDates.length} date${selectedDates.length > 1 ? 's' : ''} · ${selectedSections.length} section${selectedSections.length > 1 ? 's' : ''} selected',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: selectedDates.isEmpty ||
                                  selectedSections.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _requestGeneration(
                                      selectedDates, selectedSections);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A73E8),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.grey.shade200,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.auto_graph, size: 18),
                          label: Text(
                            'Generate Reports',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestGeneration(
      Set<String> dates, Set<String> sections) async {
    setState(() => _generating = true);
    try {
      await _svc.requestReportGeneration(
          widget.childUid, dates.toList(), sections.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Generating ${dates.length} report${dates.length > 1 ? 's' : ''} — check back in a few seconds',
            ),
            backgroundColor: const Color(0xFF34A853),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ─── PDF export ──────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final pdf = pw.Document();
      for (final r in _reports) {
        final date     = r['date']      as String? ?? 'Unknown';
        final totalMs  = (r['totalMs']  as num?)?.toInt() ?? 0;
        final appCount = (r['appCount'] as num?)?.toInt() ?? 0;
        final topApps  = (r['topApps']  as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        String fmtMs(int ms) {
          final m = ms ~/ 60000;
          if (m < 60) return '${m}m';
          return '${m ~/ 60}h ${m % 60}m';
        }

        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Family Monitor — Daily Report',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Child: ${widget.childName}',
                  style: pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
              pw.Text('Date: $date',
                  style: pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
              pw.Divider(height: 24),
              pw.Row(children: [
                pw.Expanded(child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                  pw.Text('Total Screen Time',
                      style: pw.TextStyle(fontSize: 11, color: PdfColors.grey)),
                  pw.Text(fmtMs(totalMs),
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800)),
                ])),
                pw.Expanded(child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                  pw.Text('Apps Used',
                      style: pw.TextStyle(fontSize: 11, color: PdfColors.grey)),
                  pw.Text('$appCount',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green800)),
                ])),
              ]),
              if (topApps.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Top Apps',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                ...topApps.take(5).map((a) {
                  final pkg  = a['pkg']     as String? ?? '';
                  final ms   = (a['usedMs'] as num?)?.toInt() ?? 0;
                  final name = _appName(pkg);
                  final pct  = totalMs > 0
                      ? (ms / totalMs * 100).round()
                      : 0;
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Row(children: [
                      pw.Expanded(
                        child: pw.Text(name,
                            style: pw.TextStyle(fontSize: 12))),
                      pw.Text(fmtMs(ms),
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue700)),
                      pw.SizedBox(width: 8),
                      pw.Text('$pct%',
                          style: pw.TextStyle(
                              fontSize: 11, color: PdfColors.grey600)),
                    ]),
                  );
                }),
              ],
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                'Generated by Family Monitor on ${DateTime.now().toLocal().toString().substring(0, 16)}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ],
          ),
        ));
      }

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'FamilyMonitor_${widget.childName}_Reports.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF export failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Daily Activity Report',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          ListenableBuilder(
            listenable: _tabs,
            builder: (_, __) => _tabs.index == 1 && _reports.isNotEmpty
                ? IconButton(
                    icon: _exportingPdf
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'Export as PDF',
                    onPressed: _exportingPdf ? null : _exportPdf,
                  )
                : const SizedBox.shrink(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF1A73E8),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1A73E8),
          tabs: const [Tab(text: 'Today'), Tab(text: 'History')],
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabs,
        builder: (_, __) => _tabs.index == 1
            ? FloatingActionButton.extended(
                onPressed: _generating ? null : _showGenerateSheet,
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_graph),
                label: Text(
                  _generating ? 'Generating…' : 'Generate Report',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              )
            : const SizedBox.shrink(),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildToday(), _buildHistory()],
      ),
    );
  }

  // ── Today tab ────────────────────────────────────────────────────────────

  Widget _buildToday() {
    final usage = _todayUsage;
    if (usage == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No data yet today',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Data syncs automatically every 60 seconds',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }

    final entries = usage.entries
        .where((e) => !e.key.startsWith('_') && e.value is Map)
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) =>
          ((b['usedMs'] as num?) ?? 0).compareTo((a['usedMs'] as num?) ?? 0));

    final totalMs = entries.fold<int>(
        0, (sum, e) => sum + ((e['usedMs'] as num?)?.toInt() ?? 0));
    final updatedAt = usage['_updatedAt'] as int?;
    final updatedStr = updatedAt != null
        ? _timeLabel(DateTime.fromMillisecondsSinceEpoch(updatedAt))
        : 'unknown';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(
          totalMs: totalMs,
          appCount: entries.length,
          updatedStr: updatedStr,
          fmt: _fmt,
        ).animate().fadeIn().slideY(begin: 0.1),
        const SizedBox(height: 16),
        Text('App Breakdown',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...entries.asMap().entries.map((e) {
          final i = e.key;
          final app = e.value;
          final pkg = app['pkg'] as String?;
          final ms = (app['usedMs'] as num?)?.toInt() ?? 0;
          final fraction = totalMs > 0 ? ms / totalMs : 0.0;
          final color = _colorFor(pkg);
          return _AppRow(
            name: _appName(pkg),
            pkg: pkg ?? '',
            ms: ms,
            fraction: fraction,
            color: color,
            fmt: _fmt,
          ).animate(delay: (i * 40).ms).fadeIn().slideX(begin: 0.05);
        }),
      ],
    );
  }

  // ── History tab ──────────────────────────────────────────────────────────

  Widget _buildHistory() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No reports yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Reports generate nightly — tap the button below to create one now',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _showGenerateSheet,
            icon: const Icon(Icons.auto_graph),
            label: Text('Generate Report',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) {
        final r = _reports[i];
        final date = r['date'] as String? ?? '';
        final totalMs = (r['totalMs'] as num?)?.toInt() ?? 0;
        final appCount = (r['appCount'] as num?)?.toInt() ?? 0;
        final sections = (r['sections'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            ['App Usage'];
        final topApps = (r['topApps'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Color(0xFF1A73E8)),
                  const SizedBox(width: 8),
                  Text(date,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_fmt(totalMs),
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF1A73E8),
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Text('$appCount apps used',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 4,
                    children: sections.map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s,
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500)),
                    )).toList(),
                  ),
                ]),
                if (topApps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: topApps.map((app) {
                      final pkg = app['pkg'] as String?;
                      final color = _colorFor(pkg);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_appName(pkg)} · ${_fmt((app['usedMs'] as num?)?.toInt() ?? 0)}',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ]),
        ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05);
      },
    );
  }

  // ─── Date helpers ────────────────────────────────────────────────────────

  String _weekdayShort(int wd) =>
      const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][wd];

  String _monthShort(int m) => const [
        '',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ─── Sheet section header ────────────────────────────────────────────────────

class _SheetSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SheetSection({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF1A73E8)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: GoogleFonts.inter(
                  fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ],
    );
  }
}

// ─── Summary card (Today tab) ────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int totalMs;
  final int appCount;
  final String updatedStr;
  final String Function(int) fmt;

  const _SummaryCard({
    required this.totalMs,
    required this.appCount,
    required this.updatedStr,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Today's Screen Time",
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Text(fmt(totalMs),
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          _Stat(label: 'Apps Used', value: '$appCount'),
          const SizedBox(width: 24),
          _Stat(label: 'Updated', value: updatedStr),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
      Text(value,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

// ─── App row (Today tab) ─────────────────────────────────────────────────────

class _AppRow extends StatelessWidget {
  final String name, pkg;
  final int ms;
  final double fraction;
  final Color color;
  final String Function(int) fmt;

  const _AppRow({
    required this.name,
    required this.pkg,
    required this.ms,
    required this.fraction,
    required this.color,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(name.isNotEmpty ? name[0] : '?',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(pkg,
                  style: GoogleFonts.robotoMono(
                      fontSize: 9, color: Colors.grey),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Text(fmt(ms),
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
          ),
        ),
      ]),
    );
  }
}
