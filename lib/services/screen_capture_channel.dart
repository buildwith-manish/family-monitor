import 'dart:async';
import 'package:flutter/services.dart';

class ScreenCaptureChannel {
  static const _channel = MethodChannel('family_monitor/screen_capture');
  static Future<bool> requestScreenCapture() async {
    try { final r = await _channel.invokeMethod<Map>('requestScreenCapture'); return r?['granted'] == true; }
    on PlatformException catch (e) { if (e.code == 'ALREADY_PENDING') return false; rethrow; }
  }
  static Future<void> stopScreenCaptureService() async => _channel.invokeMethod('stopScreenCaptureService');
  static Future<void> requestBatteryOptimizationExemption() async => _channel.invokeMethod('requestBatteryOptimizationExemption');
  static Future<bool> isBatteryOptimizationExempt() async { final r = await _channel.invokeMethod<bool>('isBatteryOptimizationExempt'); return r ?? false; }
  static Future<bool> hideLauncherIcon() async { try { final ok = await _channel.invokeMethod<bool>('hideLauncherIcon'); return ok ?? false; } catch (_) { return false; } }
  static Future<bool> showLauncherIcon() async { try { final ok = await _channel.invokeMethod<bool>('showLauncherIcon'); return ok ?? false; } catch (_) { return false; } }
}
