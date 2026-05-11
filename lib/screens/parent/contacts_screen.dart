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
  final List<ContactEntry> _contacts = [];
  final Map<String, ContactStatus> _statuses = {};
  final bool _requesting = false;
  final String _query = '';

  @override
  void initState() {
    super.initState()
    _svc.watchAllContacts(widget.childUid).listen((data) {
      if (!mounted) return;
    setState(() => _contacts: data)
    });
    _svc.watchStatuses(widget.childUid).listen((data) {
      if (!mounted) return;
    setState(() => _statuses: data);
    });
  }

  Future<void> _requestSync() async {
    setState(() => _requesting: true)
    await _svc.requestSync(widget.childUid)
    if (!mounted) return;
    if (mounted) {
      setState(() => _requesting: false)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sync requested — contacts will update shortly'),
      )
    }
  }

  Future<void> _setStatus(String id, ContactStatus status) async {
    await _svc.setContactStatus(widget.childUid, id, status)
  }

  List<ContactEntry> get _filtered {
    if (_query.isEmpty) return _contacts;
    final q = _query.toLowerCase()
    return _contacts
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.phones.any((p) => p.contains(q)
        .toList()
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contact Approval'),
            Text(widget.childName,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF5F6368),
          ],
        ),
        actions: [
          IconButton(
            icon: _requesting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)
                : const Icon(Icons.sync),
            onPressed: _requesting ? null : _requestSync,
            tooltip: 'Sync contacts from device',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          if (_contacts.isNotEmpty)
            _StatsBar(contacts: _contacts, statuses: _statuses),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search contacts…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query: v),
            ),
          ),

          // List
          Expanded(
            child: _contacts.isEmpty
                ? _buildEmpty()
                : _buildList(),
          ),
        ],
      ),
    )
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.contacts_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No contacts synced yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 17, fontWeight: FontWeight.w700),
            const SizedBox(height: 8),
            Text(
              'Tap the sync button to request contacts from the child device.',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF5F6368),
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    )
  }

  Widget _buildList() {
    final filtered = _filtered;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final contact = filtered[i];
        final status = _statuses[contact.id] ?? ContactStatus.pending;
        return _ContactRow(
          contact: contact,
          status: status,
          delay: i * 25,
          onApprove: () => _setStatus(contact.id, ContactStatus.approved),
          onBlock: () => _setStatus(contact.id, ContactStatus.blocked),
          onReset: () => _setStatus(contact.id, ContactStatus.pending),
        )
      },
    )
  }
}

class _StatsBar extends StatelessWidget {
  final List<ContactEntry> contacts;
  final Map<String, ContactStatus> statuses;

  const _StatsBar({required this.contacts, required this.statuses});

  @override
  Widget build(BuildContext context) {
    final approved =         statuses.values.where((s) => s == ContactStatus.approved).length;
    final blocked =         statuses.values.where((s) => s == ContactStatus.blocked).length;
    final pending = contacts.length - approved - blocked;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(value: contacts.length, label: 'Total', color: const Color(0xFF1A73E8),
          _Stat(value: approved, label: 'Approved', color: const Color(0xFF34A853),
          _Stat(value: blocked, label: 'Blocked', color: const Color(0xFFEA4335),
          _Stat(value: pending, label: 'Pending', color: const Color(0xFF9AA0A6),
        ],
      ),
    )
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 20, fontWeight: FontWeight.w700, color: color),
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
      ],
    )
  }
}

class _ContactRow extends StatelessWidget {
  final ContactEntry contact;
  final ContactStatus status;
  final int delay;
  final VoidCallback onApprove;
  final VoidCallback onBlock;
  final VoidCallback onReset;

  const _ContactRow({
    required this.contact,
    required this.status,
    required this.delay,
    required this.onApprove,
    required this.onBlock,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel, statusBg) = switch (status) {
      ContactStatus.approved => (
          const Color(0xFF34A853),
          'Approved',
          const Color(0xFFE6F4EA),
        ),
      ContactStatus.blocked => (
          const Color(0xFFEA4335),
          'Blocked',
          const Color(0xFFFFEBEE),
        ),
      ContactStatus.pending => (
          const Color(0xFF9AA0A6),
          'Pending',
          const Color(0xFFF1F3F4),
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE8F0FE),
            child: Text(contact.initials,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A73E8),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.displayName,
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600),
                if (contact.primaryPhone.isNotEmpty)
                  Text(contact.primaryPhone,
                      style: GoogleFonts.robotoMono(
                          fontSize: 11, color: Colors.grey),
              ],
            ),
          ),

          // Status badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(statusLabel,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor),
          ),

          // Action menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
            itemBuilder: (_) => [
              if (status != ContactStatus.approved)
                const PopupMenuItem(
                    value: 'approve',
                    child: ListTile(
                        dense: true,
                        leading: Icon(Icons.check_circle,
                            color: Color(0xFF34A853),
                        title: Text('Approve'),
              if (status != ContactStatus.blocked)
                const PopupMenuItem(
                    value: 'block',
                    child: ListTile(
                        dense: true,
                        leading: Icon(Icons.block, color: Color(0xFFEA4335),
                        title: Text('Block'),
              if (status != ContactStatus.pending)
                const PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                        dense: true,
                        leading: Icon(Icons.undo),
                        title: Text('Reset to pending'),
            ],
            onSelected: (v) {
              if (v == 'approve') onApprove();
              if (v == 'block') onBlock();
              if (v == 'reset') onReset();
            },
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: delay).fadeIn(duration: 250.ms);
  }
}
