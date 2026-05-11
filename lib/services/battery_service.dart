import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';

class BatteryService {
  static final BatteryService _instance = BatteryService._internal();

  factory BatteryService() {
    return _instance;
  }

  BatteryService._internal();

  final Battery _battery = Battery();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Timer? _timer;

  Future<void> startReporting(
    String childUid,
  ) async {
    _timer?.cancel();

    await _report(childUid);

    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) async {
        await _report(childUid);
      },
    );
  }

  void stopReporting() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _report(
    String childUid,
  ) async {
    try {
      final int level = await _battery.batteryLevel;

      final BatteryState state = await _battery.batteryState;

      final AndroidDeviceInfo android = await DeviceInfoPlugin().androidInfo;

      await _db.child('deviceInfo/$childUid').set({
        'batteryLevel': level,
        'isCharging':
            state == BatteryState.charging || state == BatteryState.full,
        'deviceModel': android.model,
        'androidVersion': android.version.release,
        'manufacturer': android.manufacturer,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  static Stream<Map<String, dynamic>> watchDeviceInfo(
    String childUid,
  ) {
    return FirebaseDatabase.instance
        .ref('deviceInfo/$childUid')
        .onValue
        .map((event) {
      final dynamic value = event.snapshot.value;

      if (value == null || value is! Map) {
        return <String, dynamic>{};
      }

      return Map<String, dynamic>.from(
        value,
      );
    });
  }
}
