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
  final svc = RemoteLockService();

  bool lockState = false;
  bool saving = false;

  LockSchedule schedule = LockSchedule.defaultBedtime();

  final dayLabels = const [
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  final dayNames = const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();

    _sub = svc.watchLockState(widget.childUid).listen((state) {
      if (!mounted) return;

      setState(() {
        lockState = state.locked;

        if (state.schedule != null) {
          schedule = state.schedule!;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> toggleLock() async {
    if (lockState) {
      await svc.unlockDevice(widget.childUid);
    } else {
      await svc.lockDevice(widget.childUid);
    }
  }

  Future<void> saveSchedule() async {
    setState(() => saving = true);

    await svc.saveSchedule(
      widget.childUid,
      schedule,
    );

    if (!mounted) return;

    setState(() => saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bedtime schedule saved'),
      ),
    );
  }

  Future<void> pickTime(bool isStart) async {
    final initial = isStart
        ? TimeOfDay(
            hour: schedule.startHour,
            minute: schedule.startMinute,
          )
        : TimeOfDay(
            hour: schedule.endHour,
            minute: schedule.endMinute,
          );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        schedule = LockSchedule(
          startHour: picked.hour,
          startMinute: picked.minute,
          endHour: schedule.endHour,
          endMinute: schedule.endMinute,
          activeDays: schedule.activeDays,
        );
      } else {
        schedule = LockSchedule(
          startHour: schedule.startHour,
          startMinute: schedule.startMinute,
          endHour: picked.hour,
          endMinute: picked.minute,
          activeDays: schedule.activeDays,
        );
      }
    });
  }

  void toggleDay(int index) {
    final days = List<bool>.from(schedule.activeDays);

    days[index] = !days[index];

    setState(() {
      schedule = LockSchedule(
        startHour: schedule.startHour,
        startMinute: schedule.startMinute,
        endHour: schedule.endHour,
        endMinute: schedule.endMinute,
        activeDays: days,
      );
    });
  }

  String formatTime(int h, int m) {
    final tod = TimeOfDay(hour: h, minute: m);
    return tod.format(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Remote Lock & Schedule',
            ),
            Text(
              widget.childName,
              style: const TextStyle(
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _LockCard(
            locked: lockState,
            onToggle: toggleLock,
          ).animate().fadeIn(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bedtime Schedule',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _TimePicker(
                        label: 'Lock From',
                        time: formatTime(
                          schedule.startHour,
                          schedule.startMinute,
                        ),
                        onTap: () => pickTime(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimePicker(
                        label: 'Unlock At',
                        time: formatTime(
                          schedule.endHour,
                          schedule.endMinute,
                        ),
                        onTap: () => pickTime(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(
                    7,
                    (i) {
                      final active = schedule.activeDays[i];

                      return GestureDetector(
                        onTap: () => toggleDay(i),
                        child: AnimatedContainer(
                          duration: const Duration(
                            milliseconds: 200,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(
                                    0xFF1A73E8,
                                  )
                                : Colors.white,
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                            border: Border.all(
                              color: active
                                  ? const Color(
                                      0xFF1A73E8,
                                    )
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            dayLabels[i],
                            style: TextStyle(
                              color: active ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving ? null : saveSchedule,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                      child: Text(
                        saving ? 'Saving...' : 'Save Schedule',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 150.ms),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFFF9A825),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Locking restricts the device to calls and emergency functions only.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF5F3800),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 350.ms),
        ],
      ),
    );
  }
}

class _LockCard extends StatelessWidget {
  final bool locked;
  final VoidCallback onToggle;

  const _LockCard({
    required this.locked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(
        milliseconds: 300,
      ),
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
            width: 52,
            height: 52,
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
                        ? const Color(
                            0xFFEA4335,
                          )
                        : const Color(
                            0xFF202124,
                          ),
                  ),
                ),
                Text(
                  locked ? 'Child cannot use apps' : 'Normal usage allowed',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF5F6368),
                  ),
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
            child: Text(
              locked ? 'Unlock' : 'Lock Now',
            ),
          ),
        ],
      ),
    );
  }
}

class _TimePicker extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimePicker({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF9AA0A6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A73E8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
