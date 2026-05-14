import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/streak_service.dart';

/// Displays a child's screen-time goal streak.
///
/// Shows current streak, best ever streak, today's usage vs. goal, and
/// a progress bar.  Works on both parent and child sides.
///
/// [childUid]   — the child whose streak to show.
/// [showGoalEditor] — if true (parent side) tapping the goal opens a
///   dialog to change it.  False on the child side (read-only).
class StreakCardWidget extends StatefulWidget {
  final String childUid;
  final bool showGoalEditor;

  const StreakCardWidget({
    super.key,
    required this.childUid,
    this.showGoalEditor = false,
  });

  @override
  State<StreakCardWidget> createState() => _StreakCardWidgetState();
}

class _StreakCardWidgetState extends State<StreakCardWidget> {
  final _db = FirebaseDatabase.instance.ref();
  Map<String, dynamic> _streak = {};
  int? _goalMinutes;
  StreamSubscription? _streakSub;
  StreamSubscription? _goalSub;

  @override
  void initState() {
    super.initState();
    _streakSub = StreakService().watchStreak(widget.childUid).listen((s) {
      if (mounted) setState(() => _streak = s);
    });
    _goalSub = StreakService().watchGoal(widget.childUid).listen((g) {
      if (mounted) setState(() => _goalMinutes = g);
    });
  }

  @override
  void dispose() {
    _streakSub?.cancel();
    _goalSub?.cancel();
    super.dispose();
  }

  Future<void> _editGoal() async {
    final ctrl = TextEditingController(
      text: _goalMinutes != null ? '$_goalMinutes' : '',
    );
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set Daily Screen Time Goal',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Goal (minutes per day)',
            suffixText: 'min',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      await StreakService().setDailyGoal(widget.childUid, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Daily goal set to $result minutes'),
          backgroundColor: const Color(0xFF34A853),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current     = (_streak['current']     as num?)?.toInt() ?? 0;
    final best        = (_streak['best']        as num?)?.toInt() ?? 0;
    final todayMin    = (_streak['todayMinutes'] as num?)?.toInt() ?? 0;
    final underGoal   = _streak['todayUnderGoal'] as bool? ?? false;
    final goal        = _goalMinutes ?? (_streak['goalMinutes'] as num?)?.toInt();

    double progress = goal != null && goal > 0
        ? (todayMin / goal).clamp(0.0, 1.0)
        : 0.0;

    final streakColor = current >= 7
        ? const Color(0xFFFF6F00)
        : current >= 3
            ? const Color(0xFF34A853)
            : const Color(0xFF1A73E8);

    return GestureDetector(
      onTap: widget.showGoalEditor ? _editGoal : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [streakColor, streakColor.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text('Screen Time Streak',
                  style: GoogleFonts.inter(
                      color: Colors.white70, fontSize: 12)),
              const Spacer(),
              if (widget.showGoalEditor)
                Icon(Icons.edit, size: 16, color: Colors.white60),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$current',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(current == 1 ? 'day' : 'days',
                    style: GoogleFonts.inter(
                        color: Colors.white70, fontSize: 14)),
              ),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Best: $best days',
                    style: GoogleFonts.inter(
                        color: Colors.white60, fontSize: 11)),
                if (goal != null)
                  Text(
                    underGoal
                        ? '✓ Under goal today'
                        : 'Over goal today',
                    style: GoogleFonts.inter(
                        color: underGoal
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFFFF8A65),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
              ]),
            ]),

            if (goal != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(
                    underGoal
                        ? const Color(0xFF69F0AE)
                        : const Color(0xFFFF8A65),
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text('${todayMin}m used today · ${goal}m goal',
                  style: GoogleFonts.inter(
                      color: Colors.white60, fontSize: 11)),
            ] else if (widget.showGoalEditor) ...[
              const SizedBox(height: 10),
              Text('Tap to set a daily screen time goal',
                  style: GoogleFonts.inter(
                      color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.05),
    );
  }
}
