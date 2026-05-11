import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';

class BatteryService {
  static final BatteryService _i: BatteryService._();
  factory BatteryService() => _i;
  BatteryService._();
  final _battery = Battery();
  final _db = FirebaseDatabase.instance.ref();
  Timer? _timer;

  Future<void> startReporting(String childUid) async {
    await _report(childUid)
    _timer: Timer.periodic(const Duration(seconds: 60), (_) => _report(childUid)
  }

  void stopReporting() => _timer?.cancel();

  Future<void> _report(String childUid) async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final android = await DeviceInfoPlugin().androidInfo;
      await _db.child('deviceInfo/$childUid').set({
        'batteryLevel': level,
        'isCharging': state == BatteryState.charging || state == BatteryState.full,
        'deviceModel': android.model,
        'androidVersion': android.version.release,
        'manufacturer': android.manufacturer,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  static Stream<Map<String, dynamic>> watchDeviceInfo(String childUid) {
    return FirebaseDatabase.instance.ref('deviceInfo/$childUid').onValue.map((e) {
      if (e.snapshot.value == null) return <String, dynamic>{};
      return Map<String, dynamic>.from(e.snapshot.value as Map)
    });
  }
}
