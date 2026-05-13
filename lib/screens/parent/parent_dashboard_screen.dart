import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import 'add_child_screen.dart';
import '../../services/battery_service.dart';
import 'monitoring_screen.dart';
import '../../services/webrtc_service.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _auth = AuthService();

  final Map<String, dynamic> _children = {};
  final Map<String, Map<String, dynamic>> _deviceInfo = {};
  final Map<String, StreamSubscription> _batterySubs = {};

  @override
  void initState() {
    super.initState();
    _listenForChildren();
  }

  @override
  void dispose() {
    for (final s in _batterySubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  void _listenForChildren() {
    _auth.getChildrenStream().listen((event) {
      if (!mounted) return;
      final newChildren = <String, dynamic>{};
      final raw = event.snapshot.value;
      if (raw is Map) {
        for (final entry in raw.entries) {
          newChildren[entry.key as String] = entry.value;
        }
      }
      setState(() {
        _children.clear();
        _children.addAll(newChildren);
      });
      for (final uid in newChildren.keys) {
        if (_batterySubs.containsKey(uid)) continue;
        _batterySubs[uid] = BatteryService.watchDeviceInfo(uid).listen((info) {
          if (!mounted) return;
          setState(() => _deviceInfo[uid] = info);
        });
      }
    });
  }




  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Family Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add child device',
            // ignore: use_build_context_synchronously
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddChildScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'signout') {
                await _auth.signOut();
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  Navigator.pushReplacementNamed(context, '/role-select');
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'account',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(user?.displayName ?? 'Parent'),
                  subtitle: Text(user?.email ?? ''),
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _children.isEmpty
                ? _buildEmptyState()
                : _buildChildrenList(),
          ),
        ],
      ),
    );
  }

Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.child_care,
                size: 44, color: Color(0xFF1A73E8)),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text('No devices connected yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Add a child device to start monitoring',
              style: GoogleFonts.inter(
                  fontSize: 14, color: const Color(0xFF5F6368))),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            // ignore: use_build_context_synchronously
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddChildScreen())),
            icon: const Icon(Icons.add),
            label: const Text('Add Child Device'),
          ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }

  Widget _buildChildrenList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Monitored Devices',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5F6368),
                  letterSpacing: 0.5)),
        ),
        ..._children.entries.toList().asMap().map((index, entry) {
          final childUid = entry.key;
          final childData = Map<String, dynamic>.from(entry.value as Map);
          return MapEntry(
            index,
            _ChildCard(
              childUid: childUid,
              childData: childData,
              delay: index * 80,
              deviceInfo: _deviceInfo,
            ),
          );
        }).values,
        const SizedBox(height: 16),
        OutlinedButton.icon(
          // ignore: use_build_context_synchronously
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddChildScreen())),
          icon: const Icon(Icons.add),
          label: const Text('Add Another Device'),
        ).animate(delay: 300.ms).fadeIn(),
      ],
    );
  }
}

class _ChildCard extends StatelessWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  final int delay;
  final Map<String, Map<String, dynamic>> deviceInfo;

  const _ChildCard({
    required this.childUid,
    required this.childData,
    required this.delay,
    required this.deviceInfo,
  });

  @override
  Widget build(BuildContext context) {
    final name = childData['childName'] as String? ?? childData['displayName'] as String? ?? 'Child';
    final info = deviceInfo[childUid] ?? {};
    final battery = info['battery'] as int?;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE8F0FE),
          child: Text(name[0].toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A73E8))),
        ),
        title: Text(name,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        subtitle: battery != null
            ? Text('Battery: \$battery%',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))
            : null,
        trailing: const Icon(Icons.videocam),
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            builder: (_) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.videocam),
                          label: const Text('Live Camera'),
                          onPressed: () {
                            // ignore: use_build_context_synchronously
                            Navigator.pop(context);

                            // ignore: use_build_context_synchronously
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MonitoringScreen(
                                  childUid: childUid,
                                  childData: childData,
                                  mode: StreamMode.camera,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 14),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.screen_share),
                          label: const Text('Live Screen'),
                          onPressed: () {
                            // ignore: use_build_context_synchronously
                            Navigator.pop(context);

                            // ignore: use_build_context_synchronously
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MonitoringScreen(
                                  childUid: childUid,
                                  childData: childData,
                                  mode: StreamMode.screen,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ).animate(delay: Duration(milliseconds: delay)).fadeIn();
  }
}


