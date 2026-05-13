import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class ContactsService {
  static final ContactsService _instance = ContactsService._internal();

  factory ContactsService() {
    return _instance;
  }

  ContactsService._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<bool> requestPermission() async {
    return FlutterContacts.requestPermission();
  }

  Future<bool> get hasPermission async {
    return Permission.contacts.isGranted;
  }

  Future<List<ContactEntry>> getDeviceContacts() async {
    final bool granted = await requestPermission();

    if (!granted) {
      return <ContactEntry>[];
    }

    final List<Contact> contacts = await FlutterContacts.getContacts(
      withProperties: true,
    );

    return contacts.map((contact) {
      return ContactEntry(
        id: contact.id,
        displayName: contact.displayName,
        phones: contact.phones
            .map(
              (phone) => phone.number,
            )
            .toList(),
      );
    }).toList();
  }

  Future<void> syncContacts() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return;
    }

    final List<ContactEntry> contacts = await getDeviceContacts();

    final Map<String, dynamic> data = <String, dynamic>{};

    for (final contact in contacts) {
      data[contact.id] = {
        'name': contact.displayName,
        'phones': contact.phones,
      };
    }

    await _db
        .child(
      'contacts/$uid/all',
    )
        .set({
      ...data,
      '_syncedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<List<ContactEntry>> watchAllContacts(
    String childUid,
  ) {
    return _db
        .child(
          'contacts/$childUid/all',
        )
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null || raw is! Map) {
        return <ContactEntry>[];
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(
        raw,
      );

      final List<ContactEntry> contacts = map.entries
          .where(
        (entry) => entry.key != '_syncedAt',
      )
          .map((entry) {
        final dynamic value = entry.value;

        final Map<String, dynamic> data = value is Map
            ? Map<String, dynamic>.from(
                value,
              )
            : <String, dynamic>{};

        final dynamic rawPhones = data['phones'];

        List<String> phones = <String>[];

        if (rawPhones is List) {
          phones = rawPhones
              .map(
                (phone) => phone.toString(),
              )
              .toList();
        }

        return ContactEntry(
          id: entry.key,
          displayName: data['name'] as String? ?? 'Unknown',
          phones: phones,
        );
      }).toList();

      contacts.sort(
        (a, b) => a.displayName.compareTo(
          b.displayName,
        ),
      );

      return contacts;
    });
  }

  Future<void> setContactStatus(
    String childUid,
    String contactId,
    ContactStatus status,
  ) async {
    await _db
        .child(
          'contacts/$childUid/status/$contactId',
        )
        .set(status.name);
  }

  Stream<Map<String, ContactStatus>> watchStatuses(
    String childUid,
  ) {
    return _db
        .child(
          'contacts/$childUid/status',
        )
        .onValue
        .map((event) {
      final dynamic raw = event.snapshot.value;

      if (raw == null || raw is! Map) {
        return <String, ContactStatus>{};
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(
        raw,
      );

      return map.map(
        (key, value) {
          return MapEntry(
            key,
            ContactStatus.values.firstWhere(
              (status) => status.name == value.toString(),
              orElse: () => ContactStatus.pending,
            ),
          );
        },
      );
    });
  }

  Future<void> requestSync(
    String childUid,
  ) async {
    await _db
        .child(
      'commands/$childUid/syncContacts',
    )
        .set({
      'requested': true,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<bool> watchSyncRequest(
    String childUid,
  ) {
    return _db
        .child(
          'commands/$childUid/syncContacts/requested',
        )
        .onValue
        .map(
          (event) => event.snapshot.value == true,
        );
  }
}

enum ContactStatus {
  pending,
  approved,
  blocked,
}

class ContactEntry {
  final String id;
  final String displayName;
  final List<String> phones;

  const ContactEntry({
    required this.id,
    required this.displayName,
    required this.phones,
  });

  String get initials {
    final List<String> parts = displayName.trim().split(' ');

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String get primaryPhone {
    if (phones.isEmpty) {
      return '';
    }

    return phones.first;
  }
}
