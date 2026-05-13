import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenCaptureChannel {
  static const MethodChannel _channel =
      MethodChannel('com.familymonitor/screen_capture');

  /// Request MediaProjection permission from the user.
  /// Returns true if the user grants permission.
  static Future<bool> requestScreenCapture() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('requestProjection');

      return result ?? false;
    } on MissingPluginException catch (e) {
      debugPrint(
        '[ScreenCapture] Missing plugin: $e',
      );

      return false;
    } on PlatformException catch (e) {
      debugPrint(
        '[ScreenCapture] requestProjection error: $e',
      );

      return false;
    } catch (e) {
      debugPrint(
        '[ScreenCapture] Unknown requestProjection error: $e',
      );

      return false;
    }
  }

  /// Returns true if a live MediaProjection token is currently held.
  static Future<bool> isProjectionActive() async {
    try {
      final result =
          await _channel.invokeMethod<bool>(
        'isProjectionActive',
      );

      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Release the current MediaProjection token.
  /// Android 14+ requires requesting a fresh token after release.
  static Future<void> releaseProjection() async {
    try {
      await _channel.invokeMethod(
        'releaseProjection',
      );
    } on MissingPluginException catch (_) {
      // ignore
    } on PlatformException catch (_) {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// Opens Android battery optimization exemption screen.
  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod(
        'requestBatteryOptimizationExemption',
      );
    } on MissingPluginException catch (e) {
      debugPrint(
        '[ScreenCapture] Missing battery optimization plugin: $e',
      );
    } on PlatformException catch (e) {
      debugPrint(
        '[ScreenCapture] Battery optimization error: $e',
      );
    } catch (e) {
      debugPrint(
        '[ScreenCapture] Unknown battery optimization error: $e',
      );
    }
  }

  /// Returns true if battery optimization is already disabled.
  static Future<bool> isBatteryOptimizationExempt() async {
    try {
      final result =
          await _channel.invokeMethod<bool>(
        'isBatteryOptimizationExempt',
      );

      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
