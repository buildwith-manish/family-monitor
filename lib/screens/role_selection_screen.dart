import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Header
              Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.family_restroom,
                      size: 44,
                      color: Colors.white,
                    ),
                  ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

                  const SizedBox(height: 24),

                  Text(
                    'Family Monitor',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF202124),
                      letterSpacing: -0.5,
                    ),
                  ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2, end: 0),

                  const SizedBox(height: 8),

                  Text(
                    'Choose how you\'re using this app',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF5F6368),
                    ),
                    textAlign: TextAlign.center,
                  ).animate(delay: 300.ms).fadeIn(),
                ],
              ),

              const SizedBox(height: 48),

              // Parent card
              _RoleCard(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF1A73E8),
                iconBg: const Color(0xFFE8F0FE),
                title: 'I\'m a Parent',
                subtitle: 'Monitor your child\'s device remotely',
                features: const [
                  'View live camera feed',
                  'Listen to audio',
                  'See child\'s screen',
                  'Check online status',
                ],
                onTap: () => Navigator.pushNamed(context, '/parent/auth'),
                delay: 400,
              ),

              const SizedBox(height: 16),

              // Child card
              _RoleCard(
                icon: Icons.child_care,
                iconColor: const Color(0xFF34A853),
                iconBg: const Color(0xFFE6F4EA),
                title: 'I\'m a Child',
                subtitle: 'Set up monitoring on this device',
                features: const [
                  'You control who can monitor',
                  'Approve or deny parents',
                  'Always visible notification',
                  'Stop monitoring anytime',
                ],
                onTap: () => Navigator.pushNamed(context, '/child/setup'),
                delay: 500,
              ),

              const Spacer(),

              // Privacy note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCC02), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFFE65100), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This app is designed to be transparent. Children always know they\'re being monitored.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF6D4C41),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate(delay: 700.ms).fadeIn(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final List<String> features;
  final VoidCallback onTap;
  final int delay;

  const _RoleCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF202124),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF5F6368),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...features.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 14, color: iconColor),
                            const SizedBox(width: 6),
                            Text(
                              f,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF5F6368),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.2, end: 0);
  }
}
