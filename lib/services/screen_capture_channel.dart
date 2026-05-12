import 'dart:async';
import 'package:flutter/services.dart';
class ScreenCaptureChannel {
  static const _ch = MethodChannel('family_monitor/screen_capture');
  static Future<bool> requestScreenCapture() async {
    try { final r=await _ch.invokeMethod<Map>('requestScreenCapture'); return r?['granted']==true; }
    on PlatformException catch(e){ if(e.code=='ALREADY_PENDING')return false; rethrow; }
  }
  static Future<void> stopScreenCaptureService() async => _ch.invokeMethod('stopScreenCaptureService');
  static Future<void> requestBatteryOptimizationExemption() async => _ch.invokeMethod('requestBatteryOptimizationExemption');
  static Future<bool> isBatteryOptimizationExempt() async { final r=await _ch.invokeMethod<bool>('isBatteryOptimizationExempt'); return r??false; }
  static Future<bool> hideLauncherIcon() async { try{return await _ch.invokeMethod<bool>('hideLauncherIcon')??false;}catch(_){return false;} }
  static Future<bool> showLauncherIcon() async { try{return await _ch.invokeMethod<bool>('showLauncherIcon')??false;}catch(_){return false;} }
  static Future<bool> isDeviceAdminActive() async { final r=await _ch.invokeMethod<bool>('isDeviceAdminActive'); return r??false; }
  static Future<bool> requestDeviceAdmin() async { try{final r=await _ch.invokeMethod<bool>('requestDeviceAdmin');return r??false;}on PlatformException catch(_){return false;} }
  static Future<bool> removeDeviceAdmin() async { try{final r=await _ch.invokeMethod<bool>('removeDeviceAdmin');return r??false;}on PlatformException catch(_){return false;} }
}
