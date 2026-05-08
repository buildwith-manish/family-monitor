import 'package:flutter/material.dart';
class ChildStreamingScreen extends StatelessWidget {
  final String? childUid;
  final String? childName;
  final String? parentUid;
  const ChildStreamingScreen({Key? key, this.childUid, this.childName, this.parentUid}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Streaming coming soon')));
  }
}
