import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Loads ICE server configuration (STUN + TURN) for WebRTC peer connections.
///
/// ## Production setup (required before release)
/// 1. Provision a private TURN server: coturn on a VPS, or a paid service
///    such as Twilio Network Traversal or Metered.ca paid tier.
/// 2. Write the server config to Firebase at `config/turnServers` using the
///    Firebase console or a one-time admin script. The node is read-only for
///    authenticated clients (see database.rules.json).
///
/// Example Firebase node at `config/turnServers`:
/// ```json
/// {
///   "servers": [
///     { "urls": ["stun:your-turn.example.com:3478"] },
///     {
///       "urls": [
///         "turn:your-turn.example.com:3478",
///         "turn:your-turn.example.com:443?transport=tcp",
///         "turns:your-turn.example.com:443"
///       ],
///       "username": "generated-short-lived-username",
///       "credential": "generated-short-lived-credential"
///     }
///   ]
/// }
/// ```
///
/// ## Fallback behaviour
/// If `config/turnServers` is absent or unreadable (e.g. offline, rules deny),
/// the service falls back to Google's public STUN servers only. This means
/// connections through carrier-grade NAT or strict corporate firewalls may
/// fail to connect. Always configure a private TURN server for production.
class TurnConfigService {
  static TurnConfigService? _instance;
  static TurnConfigService get instance =>
      _instance ??= TurnConfigService._();
  TurnConfigService._();

  List<Map<String, dynamic>>? _cachedServers;
  DateTime? _cacheTime;

  static const Duration _cacheTtl = Duration(hours: 1);

  static const List<Map<String, dynamic>> _stunOnlyFallback = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
        'stun:stun3.l.google.com:19302',
        'stun:stun4.l.google.com:19302',
        'stun:stun.cloudflare.com:3478',
      ],
    },
  ];

  /// Returns the full ICE configuration map ready for [createPeerConnection].
  ///
  /// Fetches TURN config from Firebase and caches it for [_cacheTtl]. Falls
  /// back to STUN-only if Firebase is unavailable or the node is not set up.
  Future<Map<String, dynamic>> getIceConfig() async {
    final servers = await _getServers();
    return {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 0,
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
    };
  }

  Future<List<Map<String, dynamic>>> _getServers() async {
    final now = DateTime.now();
    if (_cachedServers != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheTtl) {
      return _cachedServers!;
    }

    try {
      final snap = await FirebaseDatabase.instance
          .ref('config/turnServers')
          .get()
          .timeout(const Duration(seconds: 5));

      if (snap.value != null && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        final rawList = data['servers'];
        if (rawList is List && rawList.isNotEmpty) {
          final servers = rawList
              .whereType<Map>()
              .map((s) => Map<String, dynamic>.from(s))
              .toList();
          _cachedServers = servers;
          _cacheTime = now;
          debugPrint('[TurnConfig] Loaded ${servers.length} ICE server(s) from Firebase.');
          return servers;
        }
      }
    } catch (e) {
      debugPrint('[TurnConfig] Failed to load TURN config from Firebase: $e');
    }

    debugPrint('[TurnConfig] Using STUN-only fallback. '
        'Set up a private TURN server and write config to Firebase '
        'at config/turnServers for production use.');
    _cachedServers = _stunOnlyFallback;
    _cacheTime = now;
    return _stunOnlyFallback;
  }

  /// Force-clears the cache (e.g. after a credential rotation).
  void clearCache() {
    _cachedServers = null;
    _cacheTime = null;
  }
}
