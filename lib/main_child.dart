import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/child/child_auth_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'screens/child/child_qr_screen.dart';

final GlobalKey<NavigatorState> childNavKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await Firebase.initializeApp(options: const FirebaseOptions(
    apiKey: "AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4",
    authDomain: "family-monitor-7aab3.firebaseapp.com",
    databaseURL: "https://family-monitor-7aab3-default-rtdb.firebaseio.com",
    projectId: "family-monitor-7aab3",
    storageBucket: "family-monitor-7aab3.firebasestorage.app",
    messagingSenderId: "758644747673",
    appId: "1:758644747673:android:69ef23a2fa4b508122f708",
  ));
  runApp(const ChildApp());
}

class ChildApp extends StatelessWidget {
  const ChildApp({super.key});
  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(child: MaterialApp(
      title: 'Family Monitor Child',
      debugShowCheckedModeBanner: false,
      navigatorKey: childNavKey,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF34A853))),
      initialRoute: '/',
      routes: {
        '/': (_) => const ChildAuthScreen(),
        '/child/home': (_) => const ChildHomeScreen(),
        '/child/qr': (_) => ChildQrScreen(uid: '', childName: ''),
      },
    ));
  }
}
