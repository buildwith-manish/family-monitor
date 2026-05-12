import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/snapshot_service.dart';

class SnapshotsScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const SnapshotsScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends State<SnapshotsScreen> {
  final _svc = SnapshotService();
  final List<SnapshotEntry> _snapshots = [];
  final bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _svc.watchSnapshots(widget.childUid).listen((snaps) {
      if (!mounted) return;
    setState(() { _snapshots = snaps; });    });
  }

  Future<void> _requestSnapshot() async {
    setState(() => _requesting = true);
    await _svc.requestSnapshot(widget.childUid);
    if (!mounted) return;
    if (mounted) {
      setState(() => _requesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Snapshot requested — photo will appear shortly'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteSnapshot(SnapshotEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete snapshot?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFEA4335),
        ],
      ),
    );
    if (confirmed == true) {
      await _svc.deleteSnapshot(widget.childUid, entry)
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
            const Text('Snapshots'),
            Text(widget.childName,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF5F6368),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _requesting ? null : _requestSnapshot,
              icon: _requesting
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)
                  : const Icon(Icons.camera_alt, size: 16),
              label:
                  Text(_requesting ? 'Requesting…' : 'Take Photo'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
      body: _snapshots.isEmpty ? _buildEmpty() : _buildGrid(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF1A73E8), size: 36),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: 20),
            Text('No snapshots yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700),
            const SizedBox(height: 8),
            Text(
              'Tap "Take Photo" to request a photo from the child device. The child\'s front camera will capture an image and upload it here.',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF5F6368),
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _snapshots.length,
      itemBuilder: (context, index) {
        final snap = _snapshots[index];
        return _SnapshotTile(
          entry: snap,
          delay: index * 60,
          onDelete: () => _deleteSnapshot(snap),
          onTap: () => _openFullscreen(snap),
        );
      },
    );
  }

  void _openFullscreen(SnapshotEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenPhoto(entry: entry),
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  final SnapshotEntry entry;
  final int delay;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _SnapshotTile({
    required this.entry,
    required this.delay,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                entry.url,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: const Color(0xFFF1F3F4),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF1F3F4),
                  child: const Icon(Icons.broken_image,
                      color: Colors.grey, size: 40),
                ),
              ),
              // Time label at bottom
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(entry.timeLabel,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                      ),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white70, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate(delay: Duration(milliseconds: delay)).fadeIn().scale(begin: const Offset(0.9, 0.9),
    );
  }
}

class _FullscreenPhoto extends StatelessWidget {
  final SnapshotEntry entry;
  const _FullscreenPhoto({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(entry.timeLabel,
            style: GoogleFonts.inter(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(entry.url),
        ),
      ),
    );
  }
}
