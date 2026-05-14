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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // NOTE: Firebase client API keys are intentionally public for Android apps.
  // They identify the project, not authenticate it — security is enforced by
  // Firebase Security Rules (see firebase_database_rules.json). The key is
  // also embedded in the compiled APK binary, so source exposure adds no risk.
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
      authDomain: 'family-monitor-7aab3.firebaseapp.com',
      databaseURL: 'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
      projectId: 'family-monitor-7aab3',
      storageBucket: 'family-monitor-7aab3.firebasestorage.app',
      messagingSenderId: '758644747673',
      appId: '1:758644747673:android:69ef23a2fa4b508122f708',
    ),
  );

  // Enable RTDB offline persistence so the dashboard works without network.
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (_) {}

  // Wire Crashlytics error handlers identical to the child flavor.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Replace the red crash screen with a clean branded error UI.
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

class ParentApp extends StatelessWidget {
  const ParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Monitor Parent',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      // AUTH-FIX: Use _ParentAuthGate as the sole entry point.
      // It checks FirebaseAuth.instance.currentUser (which is synchronously
      // available after Firebase.initializeApp) and routes to the dashboard
      // if the session is still valid. The login screen is only shown when
      // currentUser is genuinely null (logged out, token revoked, or first run).
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

/// AUTH-FIX: Process-death-safe auth gate for the parent flavor.
///
/// After [Firebase.initializeApp] completes, [FirebaseAuth.instance.currentUser]
/// is synchronously available from the locally-cached token. We listen to
/// [authStateChanges] rather than reading [currentUser] once, so that:
///   - Token revocations (password change, account deletion) log the user out.
///   - The dashboard is shown immediately on resume without a login round-trip.
///   - A brief loading indicator covers the ~1 frame before the first event fires.
class _ParentAuthGate extends StatelessWidget {
  const _ParentAuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // While the first event is in-flight (typically < 1 frame after init),
        // show the splash colour so there is no white flash.
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
          // Session valid — go straight to dashboard.
          // Use a post-frame callback so we don't call Navigator during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Navigator.of(context).pushReplacementNamed('/parent/dashboard');
          });
          // Return the splash while navigation is pending.
          return const Scaffold(
            backgroundColor: Color(0xFF1A73E8),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // No session — show login/register.
        return const ParentAuthScreen();
      },
    );
  }
}
