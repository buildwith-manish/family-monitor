import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/contacts_service.dart';

class ContactsScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const ContactsScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _svc = ContactsService();

  List<ContactEntry> _contacts = [];
  Map<String, ContactStatus> _statuses = {};
  bool _loading = true;
  String _search = '';

  StreamSubscription? _contactsSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _listen();
    _requestSync();
  }

  @override
  void dispose() {
    _contactsSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  void _listen() {
    _contactsSub = _svc.watchAllContacts(widget.childUid).listen((list) {
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
      });
    });

    _statusSub = _svc.watchStatuses(widget.childUid).listen((map) {
      if (!mounted) return;
      setState(() => _statuses = map);
    });
  }

  Future<void> _requestSync() async {
    await _svc.requestSync(widget.childUid);
  }

  List<ContactEntry> get _filtered {
    final q = _search.toLowerCase().trim();
    if (q.isEmpty) return _contacts;
    return _contacts
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.phones.any((p) => p.contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final blocked = _statuses.values.where((s) => s == ContactStatus.blocked).length;
    final approved = _statuses.values.where((s) => s == ContactStatus.approved).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Book',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.childName,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Request sync',
            onPressed: () async {
              await _requestSync();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Sync requested — contacts will update shortly'),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          if (!_loading && _contacts.isNotEmpty)
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _StatChip(
                    label: '${_contacts.length} total',
                    color: const Color(0xFF1A73E8),
                  ),
                  const SizedBox(width: 8),
                  if (approved > 0)
                    _StatChip(
                      label: '$approved approved',
                      color: const Color(0xFF34A853),
                    ),
                  if (approved > 0) const SizedBox(width: 8),
                  if (blocked > 0)
                    _StatChip(
                      label: '$blocked blocked',
                      color: const Color(0xFFEA4335),
                    ),
                ],
              ),
            ),

          // Search bar
          if (!_loading && _contacts.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search contacts…',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 14, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search,
                      size: 20, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                    ? _EmptyState(onSync: _requestSync)
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No contacts match "$_search"',
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.grey),
                            ),
                          )
                        : _ContactList(
                            contacts: filtered,
                            statuses: _statuses,
                            onStatusChanged: _setStatus,
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _setStatus(
      String contactId, ContactStatus status) async {
    await _svc.setContactStatus(
        widget.childUid, contactId, status);
    if (mounted) {
      final label = status == ContactStatus.approved
          ? 'approved'
          : status == ContactStatus.blocked
              ? 'blocked'
              : 'reset';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Contact $label'),
        backgroundColor: status == ContactStatus.approved
            ? const Color(0xFF34A853)
            : status == ContactStatus.blocked
                ? const Color(0xFFEA4335)
                : null,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact list
// ─────────────────────────────────────────────────────────────────────────────

class _ContactList extends StatelessWidget {
  final List<ContactEntry> contacts;
  final Map<String, ContactStatus> statuses;
  final Future<void> Function(String, ContactStatus) onStatusChanged;

  const _ContactList({
    required this.contacts,
    required this.statuses,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Group alphabetically
    final Map<String, List<ContactEntry>> grouped = {};
    for (final c in contacts) {
      final key = c.displayName.isEmpty
          ? '#'
          : c.displayName[0].toUpperCase();
      final letter =
          RegExp(r'[A-Z]').hasMatch(key) ? key : '#';
      grouped.putIfAbsent(letter, () => []).add(c);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8),
      itemCount: sortedKeys.fold<int>(
          0, (sum, k) => sum + 1 + (grouped[k]?.length ?? 0)),
      itemBuilder: (_, globalIdx) {
        // Map global index to section header or contact
        int idx = globalIdx;
        for (final letter in sortedKeys) {
          final items = grouped[letter]!;
          if (idx == 0) {
            // Section header
            return Padding(
              padding: const EdgeInsets.only(
                  top: 12, bottom: 4),
              child: Text(
                letter,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A73E8),
                  letterSpacing: 1,
                ),
              ),
            );
          }
          idx--;
          if (idx < items.length) {
            final contact = items[idx];
            final status = statuses[contact.id] ??
                ContactStatus.pending;
            return _ContactTile(
              contact: contact,
              status: status,
              onStatusChanged: (s) =>
                  onStatusChanged(contact.id, s),
            ).animate(delay: Duration(milliseconds: idx * 20)).fadeIn();
          }
          idx -= items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact tile
// ─────────────────────────────────────────────────────────────────────────────

class _ContactTile extends StatelessWidget {
  final ContactEntry contact;
  final ContactStatus status;
  final Future<void> Function(ContactStatus) onStatusChanged;

  const _ContactTile({
    required this.contact,
    required this.status,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isBlocked = status == ContactStatus.blocked;
    final isApproved = status == ContactStatus.approved;

    Color avatarBg = const Color(0xFFE8F0FE);
    Color avatarFg = const Color(0xFF1A73E8);
    if (isBlocked) {
      avatarBg = Colors.red.shade50;
      avatarFg = Colors.red.shade700;
    } else if (isApproved) {
      avatarBg = Colors.green.shade50;
      avatarFg = Colors.green.shade700;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isBlocked
            ? Border.all(color: Colors.red.shade100)
            : isApproved
                ? Border.all(color: Colors.green.shade100)
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: avatarBg,
          child: Text(
            contact.initials,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: avatarFg,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          contact.displayName,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            decoration: isBlocked
                ? TextDecoration.lineThrough
                : null,
            color:
                isBlocked ? Colors.grey : const Color(0xFF202124),
          ),
        ),
        subtitle: contact.phones.isEmpty
            ? null
            : Text(
                contact.phones.take(2).join('  •  '),
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
        trailing: _StatusMenu(
          status: status,
          onChanged: onStatusChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status pop-up menu
// ─────────────────────────────────────────────────────────────────────────────

class _StatusMenu extends StatelessWidget {
  final ContactStatus status;
  final Future<void> Function(ContactStatus) onChanged;

  const _StatusMenu({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip;
    switch (status) {
      case ContactStatus.approved:
        chip = _tag('Approved', Colors.green.shade100,
            Colors.green.shade700);
        break;
      case ContactStatus.blocked:
        chip = _tag(
            'Blocked', Colors.red.shade100, Colors.red.shade700);
        break;
      default:
        chip = _tag('Pending', Colors.grey.shade100, Colors.grey);
    }

    return PopupMenuButton<ContactStatus>(
      tooltip: 'Set status',
      child: chip,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: ContactStatus.approved,
          child: Row(children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green.shade700, size: 18),
            const SizedBox(width: 8),
            const Text('Approve'),
          ]),
        ),
        PopupMenuItem(
          value: ContactStatus.blocked,
          child: Row(children: [
            Icon(Icons.block, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 8),
            const Text('Block'),
          ]),
        ),
        PopupMenuItem(
          value: ContactStatus.pending,
          child: Row(children: [
            Icon(Icons.help_outline, color: Colors.grey, size: 18),
            const SizedBox(width: 8),
            const Text('Reset'),
          ]),
        ),
      ],
      onSelected: onChanged,
    );
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onSync;
  const _EmptyState({required this.onSync});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No contacts synced yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
            'Contacts will sync when the child device is online',
            style: GoogleFonts.inter(
                fontSize: 13, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onSync,
            icon: const Icon(Icons.sync),
            label: const Text('Request Sync'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat chip
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}
