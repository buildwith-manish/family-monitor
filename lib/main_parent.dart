import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/parent/add_child_screen.dart';
import 'screens/parent/parent_auth_screen.dart';
import 'screens/parent/parent_dashboard_screen.dart';

// ─── Firebase options for the PARENT flavor ───────────────────────────────────
// appId MUST match the entry for com.example.family_monitor.parent in
// google-services.json (1:758644747673:android:ea45b7a53b3f2f2e22f708).
// Using the base app's ID (69ef23a2fa4b508122f708) here was the root cause of
// the black screen — Firebase detected the package/appId mismatch and threw a
// [core/app-not-authorized] exception before runApp was ever reached.
const FirebaseOptions _parentFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
  authDomain: 'family-monitor-7aab3.firebaseapp.com',
  databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
  projectId: 'family-monitor-7aab3',
  storageBucket: 'family-monitor-7aab3.firebasestorage.app',
  messagingSenderId: '758644747673',
  // FIXED: was 69ef23a2fa4b508122f708 (the base/default app) — now using the
  // correct parent-flavor app ID registered under com.example.family_monitor.parent
  appId: '1:758644747673:android:ea45b7a53b3f2f2e22f708',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire global error handlers FIRST — before any async work — so that crashes
  // during Firebase init are visible in logs rather than producing a black screen.
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrint('[FLUTTER ERROR] ${details.exceptionAsString()}');
    // Crashlytics may not be ready yet if Firebase init failed; guard with a
    // try/catch so the error handler itself never throws.
    try {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (_) {}
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[UNCAUGHT ASYNC ERROR] $error');
    debugPrintStack(stackTrace: stack);
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {}
    return true;
  };

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Firebase initialization ────────────────────────────────────────────────
  // Wrapped in try/catch so that ANY failure (bad appId, duplicate-app,
  // platform-channel error) shows a useful error screen instead of a black
  // screen.  The most common failure mode was a package/appId mismatch that
  // threw [core/app-not-authorized] — previously uncaught, so runApp was
  // never called.
  bool firebaseOk = false;
  String? firebaseError;

  try {
    // Avoid [core/duplicate-app] if a background isolate or FCM handler has
    // already called initializeApp() in this process.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _parentFirebaseOptions);
    } else {
      // Re-use the existing default app — no need to re-init.
      debugPrint('[Firebase] Reusing existing Firebase app.');
    }
    firebaseOk = true;
  } catch (e, st) {
    debugPrint('[FATAL] Firebase.initializeApp failed: $e');
    debugPrintStack(stackTrace: st);
    firebaseError = e.toString();
  }

  if (!firebaseOk) {
    // Show a visible error instead of a black screen.
    runApp(_FirebaseErrorApp(error: firebaseError ?? 'Unknown error'));
    return;
  }

  // Enable RTDB offline persistence so the dashboard works without network.
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (_) {}

  // Replace the red crash screen with a branded error UI.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1A73E8),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                details.exceptionAsString(),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              const Text(
                'Please restart the app',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runApp(const ParentApp());
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
        backgroundColor: const Color(0xFF1A73E8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Firebase Initialization Failed',
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

class ParentApp extends StatelessWidget {
  const ParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Monitor Parent',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const _ParentAuthGate(),
      routes: {
        '/parent/dashboard': (context) => const ParentDashboardScreen(),
        '/parent/auth':      (context) => const ParentAuthScreen(),
        '/parent/add-child': (context) => const AddChildScreen(),
      },
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A73E8),
        brightness: Brightness.light,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF8FAFB),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202124),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF202124),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A73E8),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 2),
        ),
      ),
    );
  }
}

/// AUTH GATE — process-death-safe auth gate for the parent flavor.
///
/// Uses [authStateChanges] so token revocations log the user out automatically.
/// A [_navigated] flag prevents repeated pushes when the stream re-emits
/// (e.g. hourly token refresh), which previously caused navigation-stack
/// corruption manifesting as duplicate dashboard screens.
class _ParentAuthGate extends StatefulWidget {
  const _ParentAuthGate();

  @override
  State<_ParentAuthGate> createState() => _ParentAuthGateState();
}

class _ParentAuthGateState extends State<_ParentAuthGate> {
  // Guard: once we've scheduled navigation to the dashboard, don't schedule it
  // again on the next authStateChanges emission (e.g. token refresh).
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // While the first event is in-flight (typically < 1 frame after init),
        // show the branded loading screen so there is no white/black flash.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A73E8),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          // Session valid — navigate to dashboard exactly once.
          if (!_navigated) {
            _navigated = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Navigator.of(context).pushReplacementNamed('/parent/dashboard');
            });
          }
          // Return the splash-colored scaffold while navigation is pending.
          return const Scaffold(
            backgroundColor: Color(0xFF1A73E8),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // No session (or session was revoked) — reset the guard and show login.
        _navigated = false;
        return const ParentAuthScreen();
      },
    );
  }
}
