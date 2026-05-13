import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/child/child_home_screen.dart';
import 'screens/child/child_setup_wizard_screen.dart';
import 'screens/parent/add_child_screen.dart';
import 'screens/parent/parent_auth_screen.dart';
import 'screens/parent/parent_dashboard_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (
    FlutterErrorDetails details,
  ) {
    FlutterError.presentError(details);

    debugPrint(
      'FLUTTER ERROR: ${details.exception}',
    );

    debugPrintStack(
      stackTrace: details.stack,
    );
  };

  await SystemChrome
      .setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase init error: $e');
    debugPrintStack(stackTrace: st);
    return;
  }

  runApp(
    const FamilyMonitorApp(),
  );
}

class FamilyMonitorApp
    extends StatelessWidget {
  const FamilyMonitorApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      title: 'Family Monitor',
      debugShowCheckedModeBanner:
          false,
      theme: _buildTheme(),
      initialRoute: '/',
      routes: {
        '/': (
          BuildContext context,
        ) =>
            const SplashScreen(),

        '/role-select': (
          BuildContext context,
        ) =>
            const RoleSelectionScreen(),

        '/parent/auth': (
          BuildContext context,
        ) =>
            const ParentAuthScreen(),

        '/parent/dashboard': (
          BuildContext context,
        ) =>
            const ParentDashboardScreen(),

        '/parent/add-child': (
          BuildContext context,
        ) =>
            const AddChildScreen(),

        '/child/home': (
          BuildContext context,
        ) =>
            const ChildHomeScreen(),
      },
      onGenerateRoute: (
        RouteSettings settings,
      ) {
        if (settings.name ==
            '/child/setup') {
          final Object? args =
              settings.arguments;

          if (args is String &&
              args.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) =>
                  ChildSetupWizardScreen(
                childUid: args,
              ),
            );
          }

          return MaterialPageRoute(
            builder: (_) =>
                const Scaffold(
              body: Center(
                child: Text(
                  'Invalid child setup data',
                ),
              ),
            ),
          );
        }

        return null;
      },
    );
  }

  ThemeData _buildTheme() {
    final ThemeData base =
        ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
        seedColor:
            const Color(
          0xFF1A73E8,
        ),
        brightness:
            Brightness.light,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor:
          const Color(
        0xFFF8FAFB,
      ),

      textTheme:
          GoogleFonts.interTextTheme(
        base.textTheme,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor:
            Colors.white,
        foregroundColor:
            const Color(
          0xFF202124,
        ),
        elevation: 0,
        scrolledUnderElevation:
            1,
        centerTitle: false,
        systemOverlayStyle:
            SystemUiOverlayStyle
                .dark,
        titleTextStyle:
            GoogleFonts
                .plusJakartaSans(
          fontSize: 18,
          fontWeight:
              FontWeight.w700,
          color:
              const Color(
            0xFF202124,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            16,
          ),
          side: BorderSide(
            color:
                Colors.grey.shade200,
          ),
        ),
      ),

      elevatedButtonTheme:
          ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              const Color(
            0xFF1A73E8,
          ),
          foregroundColor:
              Colors.white,
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
          ),
          textStyle:
              GoogleFonts.inter(
            fontSize: 15,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme:
          OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
          foregroundColor:
              const Color(
            0xFF1A73E8,
          ),
          side: const BorderSide(
            color:
                Color(
              0xFF1A73E8,
            ),
          ),
          padding:
              const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
          ),
          textStyle:
              GoogleFonts.inter(
            fontSize: 15,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme:
          InputDecorationTheme(
        filled: true,
        fillColor:
            Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle:
            GoogleFonts.inter(
          fontSize: 14,
          color:
              const Color(
            0xFF5F6368,
          ),
        ),
        border:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color:
                Colors.grey.shade300,
          ),
        ),
        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color:
                Colors.grey.shade300,
          ),
        ),
        focusedBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          borderSide:
              const BorderSide(
            color:
                Color(
              0xFF1A73E8,
            ),
            width: 2,
          ),
        ),
        errorBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          borderSide:
              const BorderSide(
            color:
                Color(
              0xFFEA4335,
            ),
          ),
        ),
      ),

      snackBarTheme:
          SnackBarThemeData(
        behavior:
            SnackBarBehavior
                .floating,
        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            10,
          ),
        ),
      ),
    );
  }
}
