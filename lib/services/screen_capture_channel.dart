import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// FIX-CHANNEL: Production-hardened ScreenCaptureChannel.
///
/// Root causes fixed:
/// RC-CH-01 — Added `openOemAutoStartSettings`, `isAccessibilityServiceEnabled`,
///             and `openAccessibilitySettings` methods to expose the newly added
///             MainActivity platform channel methods to Dart.
/// RC-CH-02 — All methods now handle MissingPluginException, PlatformException,
///             and generic Exception consistently.
class ScreenCaptureChannel {
  static const MethodChannel _channel =
      MethodChannel('com.familymonitor/screen_capture');

  /// Request MediaProjection permission from the user.
  /// Returns true if the user grants permission.
  static Future<bool> requestScreenCapture() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestProjection');
      return result ?? false;
    } on MissingPluginException catch (e) {
      debugPrint('[ScreenCapture] Missing plugin: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] requestProjection error: $e');
      return false;
    } catch (e) {
      debugPrint('[ScreenCapture] Unknown requestProjection error: $e');
      return false;
    }
  }

  /// Returns true if a live MediaProjection token is currently held.
  static Future<bool> isProjectionActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isProjectionActive');
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
  static Future<void> releaseProjection() async {
    try {
      await _channel.invokeMethod('releaseProjection');
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
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } on MissingPluginException catch (e) {
      debugPrint('[ScreenCapture] Missing battery optimization plugin: $e');
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] Battery optimization error: $e');
    } catch (e) {
      debugPrint('[ScreenCapture] Unknown battery optimization error: $e');
    }
  }

  /// Returns true if battery optimization is already disabled.
  static Future<bool> isBatteryOptimizationExempt() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBatteryOptimizationExempt');
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── New methods for RC-CH-01 ─────────────────────────────────────────────

  /// RC-OEM-01: Deep-link to the OEM's battery/autostart settings screen.
  ///
  /// On aggressive OEMs (MIUI, ColorOS, FuntouchOS, EMUI), the app must be
  /// whitelisted in the OEM's proprietary auto-start manager — otherwise the
  /// system kills the background service within minutes even with a foreground
  /// notification. This method opens the correct screen directly.
  ///
  /// Returns true if a matching OEM settings screen was found and opened.
  /// Returns false on stock Android (where battery optimization exemption
  /// via [requestBatteryOptimizationExemption] is sufficient).
  static Future<bool> openOemAutoStartSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openOemAutoStartSettings');
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] openOemAutoStartSettings error: $e');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the AppBlockAccessibilityService is currently enabled.
  static Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android Accessibility Settings page so the user can enable
  /// the AppBlockAccessibilityService.
  static Future<bool> openAccessibilitySettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAccessibilitySettings');
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] openAccessibilitySettings error: $e');
      return false;
    } catch (_) {
      return false;
    }
  }
}
