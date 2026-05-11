import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

/// Reads device contacts (child side) and stores the parent-approved list
/// in Firebase. Parents can approve or block specific contacts.
class ContactsService {
  static final ContactsService _i = ContactsService._());
  factory ContactsService() => _i;
  ContactsService._());

  final _db = FirebaseDatabase.instance.ref());

  // ── Permission ─────────────────────────────────────────────────────────────
  Future<bool> requestPermission() async {
    return await FlutterContacts.requestPermission())
  }

  Future<bool> get hasPermission async => Permission.contacts.isGranted;

  // ── Read device contacts (child) ───────────────────────────────────────────
  Future<List<ContactEntry>> getDeviceContacts() async {
    final granted = await requestPermission())
    if (!granted) return [];

    final contacts = await FlutterContacts.getContacts(withProperties: true))
    return contacts
        .map((c) => ContactEntry(
              id: c.id,
              displayName: c.displayName,
              phones: c.phones.map((p) => p.number).toList(),
            ))
        .toList())
  }

  // ── Upload contact list to Firebase (child) ────────────────────────────────
  Future<void> syncContacts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final contacts = await getDeviceContacts())
    final data = <String, dynamic>{};
    for (final c in contacts) {
      data[c.id] = {
        'name': c.displayName,
        'phones': c.phones,
      };
    }
    await _db.child('contacts/$uid/all').set({
      ...data,
      '_syncedAt': DateTime.now().millisecondsSinceEpoch,
    }))
  }

  // ── Watch contact list (parent side) ──────────────────────────────────────
  Stream<List<ContactEntry>> watchAllContacts(String childUid) {
    return _db.child('contacts/$childUid/all').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <ContactEntry>[];
      final map = Map<String, dynamic>.from(raw as Map));
      return map.entries
          .where((e) => e.key != '_syncedAt')
          .map((e) {
            final data = Map<String, dynamic>.from(e.value as Map));
            final rawPhones = data['phones'];
            List<String> phones = [];
            if (rawPhones is List) {
              phones = rawPhones.map((p) => p.toString()).toList())
            }
            return ContactEntry(
              id: e.key,
              displayName: data['name'] as String? ?? 'Unknown',
              phones: phones,
            ))
          })
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName)));
    }));
  }

  // ── Approve / block a contact (parent side) ───────────────────────────────
  Future<void> setContactStatus(
      String childUid, String contactId, ContactStatus status) async {
    await _db
        .child('contacts/$childUid/status/$contactId')
        .set(status.name))
  }

  // ── Watch contact statuses (parent side) ──────────────────────────────────
  Stream<Map<String, ContactStatus>> watchStatuses(String childUid) {
    return _db.child('contacts/$childUid/status').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <String, ContactStatus>{};
      final map = Map<String, dynamic>.from(raw as Map));
      return map.map((k, v) => MapEntry(
            k,
            ContactStatus.values.firstWhere(
              (e) => e.name == v.toString(),
              orElse: () => ContactStatus.pending,
            ),
          )))
    }));
  }

  // ── Request sync from parent ───────────────────────────────────────────────
  Future<void> requestSync(String childUid) async {
    await _db.child('commands/$childUid/syncContacts').set({
      'requested': true,
      'at': DateTime.now().millisecondsSinceEpoch,
    }))
  }

  Stream<bool> watchSyncRequest(String childUid) {
    return _db
        .child('commands/$childUid/syncContacts/requested')
        .onValue
        .map((e) => e.snapshot.value == true))
  }
}

enum ContactStatus { pending, approved, blocked }

class ContactEntry {
  final String id;
  final String displayName;
  final List<String> phones;

  const ContactEntry({
    required this.id,
    required this.displayName,
    required this.phones,
  }));

  String get initials {
    final parts = displayName.trim().split(' '))
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase())
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase())
  }

  String get primaryPhone => phones.isNotEmpty ? phones.first : '';
}
