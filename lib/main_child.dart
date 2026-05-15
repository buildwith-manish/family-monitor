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

import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'services/background_monitoring_service.dart';
import 'services/device_event_service.dart';
import 'services/foreground_service.dart';
import 'package:firebase_database/firebase_database.dart';

final GlobalKey<NavigatorState> childNavKey = GlobalKey<NavigatorState>();

// ─── Firebase options for the CHILD flavor ────────────────────────────────────
// Using explicit options means the child APK is NOT dependent on
// google-services.json having a valid API key at build time.  The Codemagic CI
// script generates google-services.json from $FIREBASE_API_KEY; if that secret
// is unset the file contains a placeholder ("REPLACE_WITH_YOUR_API_KEY") which
// causes every Firebase Auth call to fail with an unhandled error code —
// producing the generic "Authentication failed. Please try again." banner.
//
// appId MUST match google-services.json: com.example.family_monitor.child →
// 1:758644747673:android:32a2141244fb9c3222f708
const FirebaseOptions _childFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain: 'family-monitor-7aab3.firebaseapp.com',
  databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId: 'family-monitor-7aab3',
  storageBucket: 'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  appId: '1:758644747673:android:32a2141244fb9c3222f708',
);

// Write a health event to Firebase so the parent can see it in Device Health.
// Fire-and-forget — errors are silently swallowed to avoid any recursion risk.
Future<void> _writeChildCrashEvent(String type, String message) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('child_uid');
    if (uid == null || uid.isEmpty) return;
    await DeviceEventService.writeEvent(
      childUid: uid,
      type: type,
      message: message,
      severity: 'error',
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(options: _childFirebaseOptions);
      } catch (e, st) {
        debugPrint('Firebase init error in background handler: $e');
        debugPrintStack(stackTrace: st);
        return;
      }
    }
    if (message.data['type'] == 'call') {
      await BackgroundMonitoringService.initialize();
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

  // Wire global error handlers FIRST so crashes during Firebase init are visible
  // in logs rather than silently swallowed.
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrint('[FLUTTER ERROR] ${details.exceptionAsString()}');
    try {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      _writeChildCrashEvent('flutter_error', details.exceptionAsString());
    } catch (_) {}
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[UNCAUGHT ASYNC ERROR] $error');
    debugPrintStack(stackTrace: stack);
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      _writeChildCrashEvent('flutter_error', error.toString());
    } catch (_) {}
    return true;
  };

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Firebase initialization ────────────────────────────────────────────────
  // Using explicit FirebaseOptions so the child APK works even if the
  // google-services.json embedded at build time contained a placeholder API key.
  // Guard against [core/duplicate-app] from the FCM background handler which
  // may have already called initializeApp() in this same process.
  bool firebaseOk = false;
  String? firebaseInitError;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _childFirebaseOptions);
    } else {
      debugPrint('[Firebase] Reusing existing Firebase app (child).');
    }
    firebaseOk = true;
  } catch (e, st) {
    debugPrint('[FATAL] Firebase.initializeApp failed (child): $e');
    debugPrintStack(stackTrace: st);
    firebaseInitError = e.toString();
  }

  if (!firebaseOk) {
    runApp(_FirebaseErrorApp(error: firebaseInitError ?? 'Unknown error'));
    return;
  }

  // Enable RTDB offline persistence before any database reference is created.
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (_) {}

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await BackgroundMonitoringService.initialize();
  await BackgroundMonitoringService.restoreIfNeeded();

  MonitoringForegroundService.initForegroundTask();

  runApp(const ChildApp());
}

// ─── Shown when Firebase.initializeApp() itself fails ─────────────────────────
class _FirebaseErrorApp extends StatelessWidget {
  final String error;
  const _FirebaseErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF34A853),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Startup Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Please check your internet connection and restart the app.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    // No UI-layer WebRTC listeners needed — background isolate owns WebRTC.
  }

  @override
  void dispose() {
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
