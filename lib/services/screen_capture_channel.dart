import 'dart:async';
import 'package:flutter/services.dart';

class ScreenCaptureChannel {
  static const _channel = MethodChannel('family_monitor/screen_capture');

  static Future<bool> requestScreenCapture() async {
    try {
      final result = await _channel.invokeMethod<Map>('requestScreenCapture');
      return result?['granted'] == true;
    } on PlatformException catch (e) {
      if (e.code == 'ALREADY_PENDING') return false;
      rethrow;
    }
  }

  static Future<void> stopScreenCaptureService() async =>
      await _channel.invokeMethod('stopScreenCaptureService');

  static Future<void> requestBatteryOptimizationExemption() async =>
      await _channel.invokeMethod('requestBatteryOptimizationExemption');

  static Future<bool> isBatteryOptimizationExempt() async {
    final result = await _channel.invokeMethod<bool>('isBatteryOptimizationExempt');
    return result ?? false;
  }

  static Future<bool> hideLauncherIcon() async {
    try { return await _channel.invokeMethod<bool>('hideLauncherIcon') ?? false; }
    catch (_) { return false; }
  }

  static Future<bool> showLauncherIcon() async {
    try { return await _channel.invokeMethod<bool>('showLauncherIcon') ?? false; }
    catch (_) { return false; }
  }
}
