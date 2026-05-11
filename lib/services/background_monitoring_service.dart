import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kUidKey = 'child_uid';
const String _kWizardDone = 'wizard_done';
const String _kPermKey = 'permissions_granted';

class BackgroundMonitoringService {
  static final FlutterBackgroundService _svc =
      FlutterBackgroundService();

  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId:
            'family_monitor_bg',
        initialNotificationTitle:
            'Family Monitor',
        initialNotificationContent:
            'Monitoring service running...',
        foregroundServiceNotificationId:
            888,
        foregroundServiceTypes: [
          AndroidForegroundType.camera,
          AndroidForegroundType.microphone,
        ],
      ),
      iosConfiguration:
          IosConfiguration(
        autoStart: false,
      ),
    );
  }

  static Future<void> startService() async {
    try {
      final bool running =
          await _svc.isRunning();

      if (!running) {
        await _svc.startService();
      }
    } catch (_) {}
  }

  static Future<void> stopService() async {
    _svc.invoke('stop');
  }

  static Future<void> saveChildUid(
    String uid,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setString(
      _kUidKey,
      uid,
    );
  }

  static Future<String?> getChildUid()
      async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getString(
      _kUidKey,
    );
  }

  static Future<void> setWizardDone(
    bool value,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setBool(
      _kWizardDone,
      value,
    );
  }

  static Future<bool> isWizardDone()
      async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getBool(
          _kWizardDone,
        ) ??
        false;
  }

  static Future<void>
      savePermissionsGranted(
    bool value,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setBool(
      _kPermKey,
      value,
    );
  }

  static Future<bool>
      arePermissionsGranted()
      async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getBool(
          _kPermKey,
        ) ??
        false;
  }
}

@pragma('vm:entry-point')
void _onStart(
  ServiceInstance service,
) async {
  DartPluginRegistrant
      .ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options:
          const FirebaseOptions(
        apiKey:
            'AIzaSyAbX2gNNW3iZCIgn2UJjtbZdtQHM3CyjW4',
        authDomain:
            'family-monitor-7aab3.firebaseapp.com',
        databaseURL:
            'https://family-monitor-7aab3-default-rtdb.firebaseio.com',
        projectId:
            'family-monitor-7aab3',
        storageBucket:
            'family-monitor-7aab3.firebasestorage.app',
        messagingSenderId:
            '758644747673',
        appId:
            '1:758644747673:android:69ef23a2fa4b508122f708',
      ),
    );
  }

  final SharedPreferences prefs =
      await SharedPreferences
          .getInstance();

  final String? uid =
      prefs.getString(
    _kUidKey,
  );

  if (uid == null) {
    service.stopSelf();
    return;
  }

  if (service
      is AndroidServiceInstance) {
    service.setAsForegroundService();

    service
        .setForegroundNotificationInfo(
      title:
          'Family Monitor Active',
      content:
          'Monitoring running. Tap to open.',
    );
  }

  service.on('stop').listen((_) {
    service.stopSelf();
  });

  bool streamActive = false;
  String? activeMode;

  Timer.periodic(
    const Duration(seconds: 30),
    (_) async {
      try {
        await FirebaseDatabase
            .instance
            .ref(
              'users/$uid/lastSeen',
            )
            .set(
              ServerValue
                  .timestamp,
            );
      } catch (_) {}
    },
  );

  FirebaseDatabase.instance
      .ref('calls/$uid')
      .onValue
      .listen(
    (event) {
      final dynamic data =
          event.snapshot.value;

      if (data == null ||
          data is! Map) {
        if (streamActive) {
          service.invoke(
            'silent_stop',
          );

          streamActive = false;
          activeMode = null;
        }

        return;
      }

      final Map<String, dynamic>
          map =
          Map<String,
              dynamic>.from(
        data,
      );

      final String? status =
          map['status']
              as String?;

      final String mode =
          map['mode']
                  as String? ??
              'camera';

      if (status == 'calling') {
        if (service
            is AndroidServiceInstance) {
          service
              .setForegroundNotificationInfo(
            title:
                'Family Monitor - Active Session',
            content:
                'Parent is monitoring this device.',
          );
        }

        if (!streamActive ||
            activeMode != mode) {
          if (streamActive) {
            service.invoke(
              'silent_stop',
            );
          }

          streamActive = true;
          activeMode = mode;

          service.invoke(
            'silent_stream',
            {
              'uid': uid,
              'mode': mode,
            },
          );
        }
      } else if (status ==
          'ended') {
        service.invoke(
          'silent_stop',
        );

        streamActive = false;
        activeMode = null;

        if (service
            is AndroidServiceInstance) {
          service
              .setForegroundNotificationInfo(
            title:
                'Family Monitor Active',
            content:
                'Monitoring running. Tap to open.',
          );
        }
      }
    },
  );

  Timer.periodic(
    const Duration(seconds: 20),
    (_) {
      service.invoke(
        'ping',
        {},
      );
    },
  );
}
