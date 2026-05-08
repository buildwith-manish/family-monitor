import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/webrtc_service.dart';

class MonitoringScreen extends StatefulWidget {
  final String childUid;
  final Map<String, dynamic> childData;
  const MonitoringScreen({super.key, required this.childUid, required this.childData});
  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final _webrtc = WebRTCService();

  @override
  void dispose() {
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.childData['name'] ?? 'Monitoring')),
      body: const Center(child: Text('Monitoring — Video coming soon')),
    );
  }
}
