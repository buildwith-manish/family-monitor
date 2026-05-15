import 'package:firebase_database/firebase_database.dart';

class ContentFilterService {
  static final ContentFilterService _instance =
      ContentFilterService._internal();

  factory ContentFilterService() {
    return _instance;
  }

  ContentFilterService._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  static const Map<String, List<String>> categoryDomains = {
    'Adult Content': [
      'pornhub.com',
      'xvideos.com',
      'xnxx.com',
      'redtube.com',
      'youporn.com',
      'brazzers.com',
      'onlyfans.com',
    ],
    'Gambling': [
      'bet365.com',
      'draftkings.com',
      'fanduel.com',
      'pokerstars.com',
      'betway.com',
      'casino.com',
      'bovada.lv',
    ],
    'Social Media': [
      'facebook.com',
      'instagram.com',
      'tiktok.com',
      'snapchat.com',
      'twitter.com',
      'x.com',
      'reddit.com',
      'tumblr.com',
    ],
    'Gaming': [
      'roblox.com',
      'fortnite.com',
      'steam.com',
      'minecraft.net',
      'epicgames.com',
      'twitch.tv',
      'discord.com',
    ],
    'Violent Content': [
      'bestgore.com',
      'goregrish.com',
    ],
  };

  Future<void> blockDomain(
    String childUid,
    String domain,
  ) async {
    final String clean = _cleanDomain(domain);

    await _db
        .child(
      'content_filter/$childUid/blocked/${_keyOf(clean)}',
    )
        .set({
      'domain': clean,
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });

    _invalidateCache(childUid);
  }

  Future<void> unblockDomain(
    String childUid,
    String domain,
  ) async {
    await _db
        .child(
          'content_filter/$childUid/blocked/${_keyOf(domain)}',
        )
        .remove();

    _invalidateCache(childUid);
  }

  Future<void> blockCategory(
    String childUid,
    String category,
  ) async {
    final List<String> domains = categoryDomains[category] ?? <String>[];

    final Map<String, dynamic> updates = <String, dynamic>{};

    for (final String domain in domains) {
      updates['content_filter/$childUid/blocked/${_keyOf(domain)}'] = {
        'domain': domain,
        'category': category,
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      };
    }

    updates['content_filter/$childUid/blockedCategories/$category'] = true;

    await _db.update(updates);
    _invalidateCache(childUid);
  }

  Future<void> unblockCategory(
    String childUid,
    String category,
  ) async {
    final List<String> domains = categoryDomains[category] ?? <String>[];

    final Map<String, dynamic> updates = <String, dynamic>{};

    for (final String domain in domains) {
      updates['content_filter/$childUid/blocked/${_keyOf(domain)}'] = null;
    }

    updates['content_filter/$childUid/blockedCategories/$category'] = null;

    await _db.update(updates);
    _invalidateCache(childUid);
  }

  Stream<List<BlockedDomain>> watchBlockedDomains(
    String childUid,
  ) {
    return _db
        .child(
          'content_filter/$childUid/blocked',
        )
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null || raw is! Map) {
        return <BlockedDomain>[];
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(
        raw,
      );

      final List<BlockedDomain> domains = map.entries.map((entry) {
        final dynamic value = entry.value;

        final Map<String, dynamic> data = value is Map
            ? Map<String, dynamic>.from(
                value,
              )
            : <String, dynamic>{};

        return BlockedDomain.fromMap(
          entry.key,
          data,
        );
      }).toList();

      domains.sort(
        (a, b) => a.domain.compareTo(
          b.domain,
        ),
      );

      return domains;
    });
  }

  Stream<Set<String>> watchBlockedCategories(
    String childUid,
  ) {
    return _db
        .child(
          'content_filter/$childUid/blockedCategories',
        )
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null || raw is! Map) {
        return <String>{};
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(
        raw,
      );

      return map.entries
          .where(
            (entry) => entry.value == true,
          )
          .map(
            (entry) => entry.key,
          )
          .toSet();
    });
  }

  // ── In-memory blocklist cache ────────────────────────────────────────────
  //
  // BUG-FIX: isBlocked() was downloading the ENTIRE blocked-domains list from
  // Firebase on EVERY URL check. On a device checking many URLs per session
  // this resulted in hundreds of unnecessary network round-trips, burned
  // battery, and caused visible latency in the blocking decision.
  //
  // Fix: cache the Set<String> of blocked domains per child UID with a 60-
  // second TTL. Writes (blockDomain / blockCategory) invalidate the cache
  // immediately so the blocker picks up new rules within one cache window.

  final Map<String, Set<String>> _domainCache  = {};
  final Map<String, DateTime>    _cacheExpiry  = {};
  static const _cacheTtl = Duration(seconds: 60);

  void _invalidateCache(String childUid) {
    _domainCache.remove(childUid);
    _cacheExpiry.remove(childUid);
  }

  Future<Set<String>> _getBlockedDomainSet(String childUid) async {
    final expiry = _cacheExpiry[childUid];
    if (expiry != null &&
        DateTime.now().isBefore(expiry) &&
        _domainCache.containsKey(childUid)) {
      return _domainCache[childUid]!;
    }

    final snapshot = await _db
        .child('content_filter/$childUid/blocked')
        .get();

    final raw = snapshot.value;
    final domains = <String>{};

    if (raw is Map) {
      for (final value in raw.values) {
        if (value is Map) {
          final d = value['domain'] as String?;
          if (d != null && d.isNotEmpty) domains.add(d);
        }
      }
    }

    _domainCache[childUid] = domains;
    _cacheExpiry[childUid] = DateTime.now().add(_cacheTtl);
    return domains;
  }

  Future<bool> isBlocked(String childUid, String url) async {
    final uri = Uri.tryParse(url);
    final domain = uri?.host ?? '';
    if (domain.isEmpty) return false;

    // Strip leading 'www.' for canonical matching.
    final canonical = domain.startsWith('www.')
        ? domain.substring(4)
        : domain;

    final blocked = await _getBlockedDomainSet(childUid);

    for (final entry in blocked) {
      if (canonical == entry ||
          canonical.endsWith('.$entry') ||
          entry.endsWith('.$canonical')) {
        return true;
      }
    }

    return false;
  }

  String _cleanDomain(
    String domain,
  ) {
    return domain
        .toLowerCase()
        .replaceAll(
          'http://',
          '',
        )
        .replaceAll(
          'https://',
          '',
        )
        .replaceAll(
          'www.',
          '',
        )
        .split('/')
        .first
        .trim();
  }

  String _keyOf(
    String domain,
  ) {
    return domain.replaceAll('.', '_').replaceAll('-', '__');
  }
}

class BlockedDomain {
  final String key;
  final String domain;
  final String? category;
  final DateTime addedAt;

  const BlockedDomain({
    required this.key,
    required this.domain,
    required this.category,
    required this.addedAt,
  });

  factory BlockedDomain.fromMap(
    String key,
    Map<String, dynamic> map,
  ) {
    return BlockedDomain(
      key: key,
      domain: map['domain'] as String? ?? key,
      category: map['category'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['addedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
