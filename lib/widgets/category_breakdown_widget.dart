import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Donut chart that groups a list of app-usage entries into categories
/// (Social Media, Games, Education, Entertainment, Browser, Other) and
/// shows total screen time per category.
///
/// [apps] — list of maps with keys: packageName (String), totalTimeMs (int).
class CategoryBreakdownWidget extends StatefulWidget {
  final List<Map<String, dynamic>> apps;

  const CategoryBreakdownWidget({super.key, required this.apps});

  @override
  State<CategoryBreakdownWidget> createState() =>
      _CategoryBreakdownWidgetState();
}

class _CategoryBreakdownWidgetState extends State<CategoryBreakdownWidget> {
  int _touchedIndex = -1;

  // ── Category mapping ──────────────────────────────────────────────────────

  static const _categories = <String, List<String>>{
    'Social Media': [
      'instagram', 'facebook', 'tiktok', 'musically', 'snapchat',
      'twitter', 'whatsapp', 'telegram', 'discord', 'reddit',
      'pinterest', 'linkedin', 'viber', 'line', 'wechat', 'signal',
    ],
    'Games': [
      'roblox', 'minecraft', 'fortnite', 'pubg', 'clash', 'garena',
      'freefire', 'brawlstars', 'supercell', 'mobilelegends',
      'pokemongo', 'among', 'candycrush', 'ea.', 'activision',
      'gameloft', 'king.', 'zynga', 'bethesda', 'mojang',
    ],
    'Entertainment': [
      'youtube', 'netflix', 'spotify', 'twitch', 'hulu',
      'disneyplus', 'primevideo', 'tubi', 'crunchyroll',
      'soundcloud', 'deezer', 'apple.music', 'pandora',
    ],
    'Education': [
      'duolingo', 'khanacademy', 'coursera', 'udemy', 'google.classroom',
      'quizlet', 'brainly', 'chegg', 'photomath', 'wolfram',
      'evernote', 'notion', 'anki', 'readera',
    ],
    'Browser': [
      'chrome', 'firefox', 'brave', 'samsung.internet',
      'opera', 'edge', 'uc.browser', 'dolphin',
    ],
  };

  static const _colors = <String, Color>{
    'Social Media':  Color(0xFF1A73E8),
    'Games':         Color(0xFFEA4335),
    'Entertainment': Color(0xFF9334E6),
    'Education':     Color(0xFF34A853),
    'Browser':       Color(0xFFFF6F00),
    'Other':         Color(0xFF607D8B),
  };

  String _categoryFor(String pkg) {
    final lower = pkg.toLowerCase();
    for (final entry in _categories.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return 'Other';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Aggregate by category.
    final totals = <String, int>{};
    for (final app in widget.apps) {
      final pkg = app['packageName'] as String? ?? '';
      final ms  = (app['totalTimeMs'] as num?)?.toInt() ?? 0;
      if (ms <= 0) continue;
      final cat = _categoryFor(pkg);
      totals[cat] = (totals[cat] ?? 0) + ms;
    }

    if (totals.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.donut_large_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No usage data yet',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
        ]),
      );
    }

    final total = totals.values.fold(0, (s, v) => s + v);
    final sections = <PieChartSectionData>[];
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (int i = 0; i < entries.length; i++) {
      final cat   = entries[i].key;
      final ms    = entries[i].value;
      final pct   = ms / total;
      final isTouched = i == _touchedIndex;
      final color = _colors[cat] ?? const Color(0xFF607D8B);

      sections.add(PieChartSectionData(
        value: ms.toDouble(),
        color: color,
        radius: isTouched ? 72 : 60,
        title: pct > 0.06 ? '${(pct * 100).round()}%' : '',
        titleStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        borderSide: isTouched
            ? const BorderSide(color: Colors.white, width: 2)
            : BorderSide.none,
      ));
    }

    final touchedEntry =
        _touchedIndex >= 0 && _touchedIndex < entries.length
            ? entries[_touchedIndex]
            : null;

    return Column(
      children: [
        // Donut chart
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      _touchedIndex = -1;
                    } else {
                      _touchedIndex =
                          response.touchedSection!.touchedSectionIndex;
                    }
                  });
                },
              ),
              sections: sections,
              centerSpaceRadius: 54,
              sectionsSpace: 3,
            ),
          ),
        ),

        // Centre label when touched
        if (touchedEntry != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(children: [
              Text(touchedEntry.key,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              Text(_fmt(touchedEntry.value),
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.grey.shade700)),
            ]),
          ),

        // Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((e) {
              final cat   = e.key;
              final ms    = e.value;
              final color = _colors[cat] ?? const Color(0xFF607D8B);
              final pct   = (ms / total * 100).round();
              return GestureDetector(
                onTap: () => setState(() =>
                    _touchedIndex = entries.indexOf(e) == _touchedIndex
                        ? -1
                        : entries.indexOf(e)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('$cat  $pct%',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
  }
}
