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

  Future<bool> isBlocked(
    String childUid,
    String url,
  ) async {
    final Uri? uri = Uri.tryParse(url);

    final String domain = uri?.host ?? '';

    if (domain.isEmpty) {
      return false;
    }

    final DataSnapshot snapshot = await _db
        .child(
          'content_filter/$childUid/blocked',
        )
        .get();

    final dynamic raw = snapshot.value;

    if (raw == null || raw is! Map) {
      return false;
    }

    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);

    for (final dynamic value in map.values) {
      if (value is! Map) {
        continue;
      }

      final String blocked = value['domain'] as String? ?? '';

      if (blocked.isEmpty) {
        continue;
      }

      if (domain.endsWith(
            blocked,
          ) ||
          blocked.endsWith(
            domain,
          )) {
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
