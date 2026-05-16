import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FIX-CHANNEL: Production-hardened ScreenCaptureChannel.
///
/// Root causes fixed:
/// RC-CH-01 — Added `openOemAutoStartSettings`, `isAccessibilityServiceEnabled`,
///             and `openAccessibilitySettings` methods to expose the newly added
///             MainActivity platform channel methods to Dart.
/// RC-CH-02 — All methods now handle MissingPluginException, PlatformException,
///             and generic Exception consistently.
///
/// BUG-2-FIX: Added methods for Parcel-based Intent serialization and native
/// screen frame capture as fallback when getDisplayMedia() fails.
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

  /// RC-OEM-01: Deep-link to the OEM's battery/autostart settings screen.
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

  /// Returns the saved MediaProjection result code and data URI.
  /// Used by background monitoring service to pass existing projection data to
  /// getDisplayMedia(), avoiding the system consent dialog.
  ///
  /// BUG-2-FIX: Also returns Parcel-marshaled Intent bytes that preserve
  /// the Binder extra needed by getMediaProjection() on Android 14+.
  static Future<Map<String, dynamic>?> getProjectionParams() async {
    try {
      final result = await _channel.invokeMethod<Map>('getProjectionParams');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on MissingPluginException catch (_) {
      return null;
    } on PlatformException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// BUG-2-FIX: Returns the Parcel-marshaled Intent bytes that preserve
  /// the Binder extra. This is the PREFERRED way to pass projection data
  /// to the native side on Android 14+ where Intent.toUri() loses the Binder.
  ///
  /// Returns a map with:
  ///   - 'resultCode': int - The result code from the consent dialog
  ///   - 'resultDataParcel': Uint8List - Parcel-marshaled Intent bytes
  /// Or null if no projection data is available.
  static Future<Map<String, dynamic>?> getProjectionParamsParcel() async {
    try {
      final result = await _channel.invokeMethod<Map>('getProjectionParamsParcel');
      if (result != null) {
        final map = Map<String, dynamic>.from(result);
        // Convert the byte array to Uint8List for Dart consumption
        if (map['resultDataParcel'] != null) {
          final rawBytes = map['resultDataParcel'];
          if (rawBytes is List) {
            map['resultDataParcel'] = Uint8List.fromList(rawBytes.cast<int>());
          }
        }
        return map;
      }
      return null;
    } on MissingPluginException catch (_) {
      return null;
    } on PlatformException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// BUG-3-FIX: Start the ScreenCaptureService with ACTION_START_SILENT.
  /// This can be called from the background service isolate where no
  /// foreground Activity is available. The service will try to reuse the
  /// saved MediaProjection token; if invalid, it will show a notification
  /// prompting the user to re-grant consent.
  static Future<bool> startSilentProjection() async {
    try {
      final result = await _channel.invokeMethod<bool>('startSilentProjection');
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── STREAM-01: WebSocket screen streaming methods ──────────────────────

  /// Start the ScreenStreamService which captures screen frames via
  /// VirtualDisplay + ImageReader and pushes them over WebSocket to the
  /// relay server. This provides much lower latency than the Firebase RTDB
  /// base64 relay approach.
  ///
  /// [uid] - The child's Firebase UID (used as session identifier)
  /// [serverUrl] - The WebSocket relay server URL (e.g., ws://192.168.1.100:3004)
  ///
  /// Returns true if the service was started successfully.
  static Future<bool> startScreenStream({
    required String uid,
    String? serverUrl,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'startScreenStream',
        {'uid': uid, 'serverUrl': serverUrl},
      );
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] startScreenStream error: $e');
      return false;
    } catch (e) {
      debugPrint('[ScreenCapture] startScreenStream error: $e');
      return false;
    }
  }

  /// Stop the ScreenStreamService WebSocket streaming.
  static Future<void> stopScreenStream() async {
    try {
      await _channel.invokeMethod('stopScreenStream');
    } on MissingPluginException catch (_) {
      // ignore
    } on PlatformException catch (_) {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// Returns true if the ScreenStreamService is currently streaming.
  static Future<bool> isScreenStreamRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isScreenStreamRunning');
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get the current status of the ScreenStreamService.
  /// Returns a map with: isStreaming, wsConnected, frameCount, lastFrameTimestamp
  static Future<Map<String, dynamic>?> getStreamStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStreamStatus');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on MissingPluginException catch (_) {
      return null;
    } on PlatformException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── BUG-2-FIX: Native screen frame capture methods ─────────────────────

  /// Start native screen frame capture using VirtualDisplay + ImageReader.
  ///
  /// This is used as a fallback when the native getDisplayMedia()
  /// fails (e.g., due to Intent URI serialization losing the Binder extra
  /// on Android 14+). Frames are captured as JPEG and can be retrieved
  /// via [getScreenFrame] or relayed to the parent via Firebase RTDB.
  ///
  /// Returns true if capture started successfully.
  static Future<bool> startNativeScreenCapture({
    int width = 720,
    int height = 1280,
    int fps = 5,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'startNativeScreenCapture',
        {'width': width, 'height': height, 'fps': fps},
      );
      return result ?? false;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] startNativeScreenCapture error: $e');
      return false;
    } catch (e) {
      debugPrint('[ScreenCapture] startNativeScreenCapture error: $e');
      return false;
    }
  }

  /// Stop native screen frame capture.
  static Future<void> stopNativeScreenCapture() async {
    try {
      await _channel.invokeMethod('stopNativeScreenCapture');
    } on MissingPluginException catch (_) {
      // ignore
    } on PlatformException catch (_) {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  /// STREAM-RELAY-URL: Save the stream relay URL to SharedPreferences.
  /// This is called from the child setup wizard and other places that
  /// configure the WebSocket relay server.
  ///
  /// The URL is saved to BOTH:
  ///   - FlutterSharedPreferences (key: 'stream_relay_url') — used by Dart services
  ///   - fm_prefs (key: 'stream_relay_url') — used by native Kotlin ScreenStreamService
  ///
  /// URL format: ws://SERVER_HOST/?XTransformPort=3004
  static Future<void> configureStreamRelayUrl(String url) async {
    try {
      // Save to FlutterSharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('stream_relay_url', url);
      debugPrint('[ScreenCapture] Saved stream_relay_url to FlutterSharedPreferences: $url');
    } catch (e) {
      debugPrint('[ScreenCapture] Error saving stream_relay_url to FlutterSharedPreferences: $e');
    }

    try {
      // Also save to fm_prefs (native Kotlin side reads this)
      // The native side uses getSharedPreferences("fm_prefs", MODE_PRIVATE)
      await _channel.invokeMethod('saveStreamRelayUrl', {'url': url});
      debugPrint('[ScreenCapture] Saved stream_relay_url to fm_prefs via MethodChannel');
    } on MissingPluginException catch (_) {
      // Method not implemented on native side yet — non-critical
      debugPrint('[ScreenCapture] saveStreamRelayUrl method not available on native side');
    } on PlatformException catch (e) {
      debugPrint('[ScreenCapture] saveStreamRelayUrl error: $e');
    } catch (e) {
      debugPrint('[ScreenCapture] saveStreamRelayUrl unknown error: $e');
    }
  }

  /// Get the latest captured screen frame as JPEG bytes.
  ///
  /// Returns null if frame capture is not running or no frame is available.
  static Future<Uint8List?> getScreenFrame() async {
    try {
      final result = await _channel.invokeMethod('getScreenFrame');
      if (result == null) return null;
      if (result is List) {
        return Uint8List.fromList(result.cast<int>());
      }
      if (result is Uint8List) {
        return result;
      }
      return null;
    } on MissingPluginException catch (_) {
      return null;
    } on PlatformException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }
}
