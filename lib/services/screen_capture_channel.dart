import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenCaptureChannel {
  static const _channel = MethodChannel('family_monitor/screen_capture');

  static Future<bool> requestScreenCapture() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('requestScreenCapture');
      if (result is Map) return result['granted'] == true;
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('[ScreenCaptureChannel] requestScreenCapture error: $e');
      return false;
    }
  }

  static Future<void> stopScreenCaptureService() async {
    try {
      await _channel.invokeMethod('stopScreenCaptureService');
    } on PlatformException catch (e) {
      debugPrint('[ScreenCaptureChannel] stopService error: $e');
    }
  }

  static Future<bool> isBatteryOptimizationExempt() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBatteryOptimizationExempt');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } on PlatformException catch (e) {
      debugPrint('[ScreenCaptureChannel] battery opt error: $e');
    }
  }
}
