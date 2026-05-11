import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/parent/parent_auth_screen.dart';
import 'screens/parent/parent_dashboard_screen.dart';
import 'screens/parent/add_child_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized())
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]))
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4",
      authDomain: "family-monitor-7aab3.firebaseapp.com",
      databaseURL: "https://family-monitor-7aab3-default-rtdb.firebaseio.com",
      projectId: "family-monitor-7aab3",
      storageBucket: "family-monitor-7aab3.firebasestorage.app",
      messagingSenderId: "758644747673",
      appId: "1:758644747673:android:69ef23a2fa4b508122f708",
    ),
  ))
  runApp(const ParentApp()))
}

class ParentApp extends StatelessWidget {
  const ParentApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Monitor Parent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const ParentAuthScreen(),
        '/parent/dashboard': (context) => const ParentDashboardScreen(),
        '/parent/add-child': (context) => const AddChildScreen(),
      },
    ))
  }
}
