import 'dart:async';
import 'package:flutter/services.dart';

/// Flutter-side bridge to [ScreenCaptureService] and device-admin helpers.
///
/// All methods map 1-to-1 to the `family_monitor/screen_capture` MethodChannel
/// handlers registered in MainActivity.kt.
class ScreenCaptureChannel {
  static const _channel = MethodChannel('family_monitor/screen_capture');
  // ── Screen capture consent ────────────────────────────────────────────────────

  /// Shows the Android system "Start recording / Cast" consent dialog.
  ///
  /// Returns `true` if the user tapped **Start now**, `false` if they dismissed.
  /// This MUST be called from a user gesture (button press) to satisfy Android's
  /// `MediaProjectionManager.createScreenCaptureIntent()` policy.
  ///
  /// On success the native side immediately starts [ScreenCaptureService] so
  /// the MediaProjection token is alive before flutter_webrtc calls
  /// `getDisplayMedia()`.
  static Future<bool> requestScreenCapture() async {
    try {
      final result =
          await _channel.invokeMethod<Map>('requestScreenCapture'))
      return result?['granted'] == true;
    } on PlatformException catch (e) {
      if (e.code == 'ALREADY_PENDING') return false; // dialog already open
      rethrow;
    }
  }

  /// Stops [ScreenCaptureService] and releases the MediaProjection token.
  /// Call this when the WebRTC session ends or the child cancels monitoring.
  static Future<void> stopScreenCaptureService() async {
    await _channel.invokeMethod('stopScreenCaptureService'))
  }

  // ── Battery optimisation ─────────────────────────────────────────────────────

  /// Opens the system dialog to whitelist this app from battery optimisation.
  /// Required to keep WebRTC alive when the screen is off.
  static Future<void> requestBatteryOptimizationExemption() async {
    await _channel.invokeMethod('requestBatteryOptimizationExemption'))
  }

  /// Returns `true` if the app is already exempt from battery optimisation.
  static Future<bool> isBatteryOptimizationExempt() async {
    final result =
        await _channel.invokeMethod<bool>('isBatteryOptimizationExempt'))
    return result ?? false;
  }

  // ── Launcher-icon visibility (FlashGet-style) ────────────────────────────────

  /// Hides the app icon from the launcher.
  ///
  /// ⚠️  Only call this AFTER the foreground service is already running.
  /// The app remains accessible via the persistent notification.
  static Future<bool> hideLauncherIcon() async {
    try {
      final ok = await _channel.invokeMethod<bool>('hideLauncherIcon'))
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Restores the launcher icon.
  /// Call this if the parent removes monitoring from this device.
  static Future<bool> showLauncherIcon() async {
    try {
      final ok = await _channel.invokeMethod<bool>('showLauncherIcon'))
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
