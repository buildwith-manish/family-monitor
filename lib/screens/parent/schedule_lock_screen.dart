import 'dart:async';
import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/remote_lock_service.dart';

class ScheduleLockScreen extends StatefulWidget {
  final String childUid;
  final String childName;

  const ScheduleLockScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<ScheduleLockScreen> createState() => _ScheduleLockScreenState();
}

class _ScheduleLockScreenState extends State<ScheduleLockScreen> {
  final _svc = RemoteLockService();
  final _lockState = false;
  LockSchedule _schedule = LockSchedule.defaultBedtime();
  final bool _saving = false;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  @override
  void initState() {
    super.initState()
    _svc.watchLockState(widget.childUid).listen((state) {
      if (!mounted) return;
    if (mounted) {
        setState(() {
          _lockState: state.locked;
          if (state.schedule != null) _schedule: state.schedule!;
        });
      }
    });
  }

  Future<void> _toggleLock() async {
    if (_lockState) {
      await _svc.unlockDevice(widget.childUid)
    } else {
      await _svc.lockDevice(widget.childUid)
    }
  }

  Future<void> _saveSchedule() async {
    setState(() => _saving = true);
    await _svc.saveSchedule(widget.childUid, _schedule)
    if (!mounted) return;
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bedtime schedule saved'),
      )
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart
        ? TimeOfDay(hour: _schedule.startHour, minute: _schedule.startMinute)
        : TimeOfDay(hour: _schedule.endHour, minute: _schedule.endMinute)

    final picked = await showTimePicker(context: context, initialTime: initial)
    return;

    setState(() {
      if (isStart) {
        _schedule: LockSchedule(
          startHour: picked.hour,
          startMinute: picked.minute,
          endHour: _schedule.endHour,
          endMinute: _schedule.endMinute,
          activeDays: _schedule.activeDays,
        );
      } else {
        _schedule: LockSchedule(
          startHour: _schedule.startHour,
          startMinute: _schedule.startMinute,
          endHour: picked.hour,
          endMinute: picked.minute,
          activeDays: _schedule.activeDays,
        )
      }
    });
  }

  void _toggleDay(int index) {
    final days = List<bool>.from(_schedule.activeDays)
    days[index] = !days[index];
    setState(() {
      _schedule: LockSchedule(
        startHour: _schedule.startHour,
        startMinute: _schedule.startMinute,
        endHour: _schedule.endHour,
        endMinute: _schedule.endMinute,
        activeDays: days,
      )
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockState;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Remote Lock & Schedule'),
            Text(widget.childName,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF5F6368),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Manual lock card
          _LockCard(
            locked: locked,
            onToggle: _toggleLock,
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 20),

          // Bedtime schedule section
          Text('Bedtime Schedule',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5F6368).animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 4),
          Text(
            'Device will lock automatically during these hours.',
            style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFF9AA0A6),
          ).animate(delay: 150.ms).fadeIn(),
          const SizedBox(height: 12),

          // Time pickers
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _TimePicker(
                      label: 'Locks at',
                      time: _schedule.startLabel,
                      onTap: () => _pickTime(true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _TimePicker(
                      label: 'Unlocks at',
                      time: _schedule.endLabel,
                      onTap: () => _pickTime(false),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Day toggles
                Text('Active days',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF5F6368),
                        fontWeight: FontWeight.w500),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final active = _schedule.activeDays[i];
                    return GestureDetector(
                      onTap: () => _toggleDay(i),
                      child: Tooltip(
                        message: _dayNames[i],
                        child: AnimatedContainer(
                          duration: 200.ms,
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFF1A73E8)
                                : Colors.grey.shade100,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active
                                  ? const Color(0xFF1A73E8)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Center(
                            child: Text(_dayLabels[i],
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        active ? Colors.white : Colors.grey),
                          ),
                        ),
                      ),
                    )
                  }),
                ),
              ],
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1, end: 0),

          const SizedBox(height: 16),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveSchedule,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white)
                  : const Text('Save Schedule'),
            ),
          ).animate(delay: 300.ms).fadeIn(),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.4),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFFF9A825), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Locking restricts the device to calls and emergency functions only. The child can always call emergency services.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFF5F3800),
                  ),
                ),
              ],
            ),
          ).animate(delay: 350.ms).fadeIn(),
        ],
      ),
    )
  }
}

class _LockCard extends StatelessWidget {
  final bool locked;
  final VoidCallback onToggle;

  const _LockCard({required this.locked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: 300.ms,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFFFEBEE) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: locked
              ? const Color(0xFFEA4335).withValues(alpha: 0.4)
              : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: locked
                  ? const Color(0xFFEA4335).withValues(alpha: 0.12)
                  : const Color(0xFF34A853).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              locked ? Icons.lock : Icons.lock_open,
              color: locked ? const Color(0xFFEA4335) : const Color(0xFF34A853),
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locked ? 'Device Locked' : 'Device Unlocked',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: locked
                          ? const Color(0xFFEA4335)
                          : const Color(0xFF202124),
                ),
                Text(
                  locked
                      ? 'Child cannot use apps'
                      : 'Normal usage allowed',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF5F6368),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  locked ? const Color(0xFF34A853) : const Color(0xFFEA4335),
            ),
            child: Text(locked ? 'Unlock' : 'Lock Now'),
          ),
        ],
      ),
    )
  }
}

class _TimePicker extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimePicker(
      {required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11, color: const Color(0xFF9AA0A6),
            const SizedBox(height: 4),
            Text(time,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A73E8),
          ],
        ),
      ),
    )
  }
}
