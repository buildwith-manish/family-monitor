import 'package:flutter/services.dart';

class ScreenCaptureChannel {
  static const MethodChannel _channel =
      MethodChannel('family_monitor/screen_capture');

  static Future<bool> requestScreenCapture() async {
    try {
      final result =
          await _channel.invokeMethod('requestScreenCapture');

      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stopScreenCaptureService() async {
    try {
      await _channel.invokeMethod(
        'stopScreenCaptureService',
      );
    } on PlatformException {
      // ignore
    }
  }
}
