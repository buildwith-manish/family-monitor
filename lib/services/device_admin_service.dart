import 'package:flutter/services.dart';

/// Manages Device Administrator activation from the Flutter layer.
/// When active, the app cannot be uninstalled without first deactivating
/// Device Admin — which requires going through a warning dialog.
class DeviceAdminService {
  static const _ch = MethodChannel('com.familymonitor/screen_capture');

  static Future<bool> isActive() async {
    try {
      final result = await _ch.invokeMethod<bool>('isDeviceAdminActive');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system Device Admin activation dialog.
  /// Returns immediately — the dialog is shown asynchronously.
  static Future<void> requestActivation() async {
    try {
      await _ch.invokeMethod('requestDeviceAdmin');
    } catch (_) {}
  }
}
