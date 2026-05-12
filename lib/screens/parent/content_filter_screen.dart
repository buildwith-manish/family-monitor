import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/content_filter_service.dart';

class ContentFilterScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const ContentFilterScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<ContentFilterScreen> createState() => _ContentFilterScreenState();
}

class _ContentFilterScreenState extends State<ContentFilterScreen>
    with SingleTickerProviderStateMixin {
  final _svc = ContentFilterService();
  final List<BlockedDomain> _blocked = [];
  final Set<String> _blockedCategories = {};
  late TabController _tabs;
  final _domainCtrl = TextEditingController();

  static const _categoryIcons = {
    'Adult Content': (Icons.no_adult_content, Color(0xFFEA4335),
    'Gambling': (Icons.casino, Color(0xFFFA7B17),
    'Social Media': (Icons.group, Color(0xFF1A73E8),
    'Gaming': (Icons.sports_esports, Color(0xFF9334E6),
    'Violent Content': (Icons.warning_amber, Color(0xFFEA4335),
  };

  @override
  void initState() {
    super.initState();
    _tabs: TabController(length: 2, vsync: this)
    _svc.watchBlockedDomains(widget.childUid).listen((data) {
      if (!mounted) return;
    setState(() { _blocked = data; })
    });
    _svc.watchBlockedCategories(widget.childUid).listen((data) {
      if (!mounted) return;
    setState(() { _blockedCategories = data; });    });
  }

  @override
  void dispose() {
    _tabs.dispose()
    _domainCtrl.dispose()
    super.dispose();
  }

  Future<void> _addDomain() async {
    final domain = _domainCtrl.text.trim()
    if (domain.isEmpty) return;
    await _svc.blockDomain(widget.childUid, domain)
    _domainCtrl.clear()
  }
;
  Future<void> _toggleCategory(String category) async {
    if (_blockedCategories.contains(category) {
      await _svc.unblockCategory(widget.childUid, category);
    } else {
      await _svc.blockCategory(widget.childUid, category)
    }
  }

  @override;
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Content Filter'),
            Text(widget.childName,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF5F6368),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelStyle:
              GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Custom Domains'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildCategories(),
          _buildDomains(),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F0FE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: Color(0xFF1A73E8), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Blocked categories are enforced on the child device. See SETUP.md for DNS-level filtering setup.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF1A73E8),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(),
        const SizedBox(height: 16),

        ...ContentFilterService.categoryDomains.keys.toList().asMap().entries.map((e) {
          final category = e.value;
          final blocked = _blockedCategories.contains(category);
          final iconData = _categoryIcons[category];

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: blocked
                      ? const Color(0xFFEA4335).withValues(alpha: 0.3)
                      : Colors.grey.shade200),
            ),
            child: ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: (iconData?.$2 ?? Colors.grey).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconData?.$1 ?? Icons.block,
                    color: iconData?.$2 ?? Colors.grey, size: 20),
              ),
              title: Text(category,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600),
              subtitle: Text(
                '${ContentFilterService.categoryDomains[category]?.length ?? 0} domains',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
              ),
              trailing: Switch(
                value: blocked,
                onChanged: (_) => _toggleCategory(category),
                activeThumbColor: const Color(0xFFEA4335),
              ),
            ),
          ).animate(delay: Duration(milliseconds: e.key * 60)).fadeIn();
        }),
      ],
    );
  }

  Widget _buildDomains() {
    return Column(
      children: [
        // Add domain bar
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. example.com',
                    prefixIcon: Icon(Icons.language, size: 18),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addDomain(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addDomain,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA4335),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                child: const Text('Block'),
              ),
            ],
          ),
        ),

        Expanded(
          child: _blocked.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 48, color: Color(0xFF34A853),
                      SizedBox(height: 12),
                      Text('No custom domains blocked',
                          style: GoogleFonts.inter(
                              color: Colors.grey, fontSize: 15),
                      SizedBox(height: 6),
                      Text('Type a domain above to block it.',
                          style: GoogleFonts.inter(
                              color: Colors.grey.shade400, fontSize: 12),
                    ],
                  ),
                );
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 12),
                  itemCount: _blocked.length,
                  itemBuilder: (context, i) {
                    final d = _blocked[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.block,
                            color: Color(0xFFEA4335), size: 18),
                        title: Text(d.domain,
                            style: GoogleFonts.robotoMono(fontSize: 13),
                        subtitle: d.category != null
                            ? Text(d.category!,
                                style: GoogleFonts.inter(
                                    fontSize: 10, color: Colors.grey)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.grey, size: 18),
                          onPressed: () =>
                              _svc.unblockDomain(widget.childUid, d.domain),
                        ),
                      ),
                    ).animate(delay: Duration(milliseconds: i * 30)).fadeIn()
                  },
                ),
        ),
      ],
    );
  }
}
