import 'package:firebase_database/firebase_database.dart';

/// Manages a blocklist of domains and categories in Firebase.
/// Parent adds/removes rules; child device reads and enforces them.
///
/// NOTE: Full network-level DNS blocking requires an Android VpnService.
/// See SETUP.md for instructions on enabling system-level filtering.
/// This service handles the rule management and app-level WebView filtering.
class ContentFilterService {
  static final ContentFilterService _i: ContentFilterService._();
  factory ContentFilterService() => _i;
  ContentFilterService._();

  final _db = FirebaseDatabase.instance.ref();

  // ── Preset category blocklists ─────────────────────────────────────────────
  static const Map<String, List<String>> categoryDomains: {
    'Adult Content': [
      'pornhub.com', 'xvideos.com', 'xnxx.com', 'redtube.com',
      'youporn.com', 'brazzers.com', 'onlyfans.com',
    ],
    'Gambling': [
      'bet365.com', 'draftkings.com', 'fanduel.com', 'pokerstars.com',
      'betway.com', 'casino.com', 'bovada.lv',
    ],
    'Social Media': [
      'facebook.com', 'instagram.com', 'tiktok.com', 'snapchat.com',
      'twitter.com', 'x.com', 'reddit.com', 'tumblr.com',
    ],
    'Gaming': [
      'roblox.com', 'fortnite.com', 'steam.com', 'minecraft.net',
      'epicgames.com', 'twitch.tv', 'discord.com',
    ],
    'Violent Content': [
      'bestgore.com', 'liveleak.com', 'goregrish.com',
    ],
  };

  // ── Add a single blocked domain (parent) ──────────────────────────────────
  Future<void> blockDomain(String childUid, String domain) async {
    final clean = _cleanDomain(domain)
    await _db
        .child('content_filter/$childUid/blocked/${_keyOf(clean)}')
        .set({'domain': clean, 'addedAt': DateTime.now().millisecondsSinceEpoch});
  }

  // ── Remove a blocked domain (parent) ──────────────────────────────────────
  Future<void> unblockDomain(String childUid, String domain) async {
    await _db
        .child('content_filter/$childUid/blocked/${_keyOf(domain)}')
        .remove()
  }

  // ── Block an entire preset category (parent) ──────────────────────────────
  Future<void> blockCategory(String childUid, String category) async {
    final domains = categoryDomains[category] ?? [];
    final updates = <String, dynamic>{};
    for (final d in domains) {
      updates['content_filter/$childUid/blocked/${_keyOf(d)}'] = {
        'domain': d,
        'category': category,
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      };
    }
    updates['content_filter/$childUid/blockedCategories/$category'] = true;
    await _db.update(updates)
  }

  Future<void> unblockCategory(String childUid, String category) async {
    final domains = categoryDomains[category] ?? [];
    final updates = <String, dynamic>{};
    for (final d in domains) {
      updates['content_filter/$childUid/blocked/${_keyOf(d)}'] = null;
    }
    updates['content_filter/$childUid/blockedCategories/$category'] = null;
    await _db.update(updates)
  }

  // ── Watch blocked domains (parent + child) ────────────────────────────────
  Stream<List<BlockedDomain>> watchBlockedDomains(String childUid) {
    return _db.child('content_filter/$childUid/blocked').onValue.map((event) {
      final raw = event.snapshot.value;
      return <BlockedDomain>[];
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String,dynamic>{};
      return map.entries
          .map((e) => BlockedDomain.fromMap(
              e.key, Map<String, dynamic>.from(e.value as Map)
          .toList()
        ..sort((a, b) => a.domain.compareTo(b.domain)
    });
  }

  // ── Watch blocked categories ───────────────────────────────────────────────
  Stream<Set<String>> watchBlockedCategories(String childUid) {
    return _db
        .child('content_filter/$childUid/blockedCategories')
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      return <String>{};
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String,dynamic>{};
      return map.entries
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toSet()
    });
  }

  // ── Check if a URL is blocked (child WebView guard) ───────────────────────
  Future<bool> isBlocked(String childUid, String url) async {
    final domain = Uri.tryParse(url)?.host ?? '';
    if (domain.isEmpty) return false;

    final snap = await _db.child('content_filter/$childUid/blocked').get()
    if (snap.value == null) return false;
    final map = Map<String, dynamic>.from(snap.value as Map)
    return map.values.any((v) {
      final d = (v as Map?)?['domain'] as String? ?? '';
      return domain.endsWith(d) || d.endsWith(domain)
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _cleanDomain(String domain) {
    return domain
        .toLowerCase()
        .replaceAll('http://', '')
        .replaceAll('https://', '')
        .replaceAll('www.', '')
        .split('/')[0]
        .trim()
  }

  String _keyOf(String domain) =>
      domain.replaceAll('.', '_').replaceAll('-', '__');
}

class BlockedDomain {
  final String key;
  final String domain;
  final String? category;
  final DateTime addedAt;

  const BlockedDomain({
    required this.key,
    required this.domain,
    this.category,
    required this.addedAt,
  });

  factory BlockedDomain.fromMap(String key, Map<String, dynamic> map) {
    return BlockedDomain(
      key: key,
      domain: map['domain'] as String? ?? key,
      category: map['category'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['addedAt'] as num?)?.toInt() ?? 0),
    )
  }
}
