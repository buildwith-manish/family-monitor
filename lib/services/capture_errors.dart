/// Standardized error codes for screen capture and streaming failures.
/// Based on the FlashGet Kids error taxonomy.
class CaptureErrorCode {
  // ── Projection Errors ─────────────────────────────────────────────
  static const String projectionNotActive = 'PROJECTION_NOT_ACTIVE';
  static const String projectionRevoked = 'PROJECTION_REVOKED';
  static const String projectionConsentDenied = 'PROJECTION_CONENT_DENIED';
  static const String projectionTokenInvalid = 'PROJECTION_TOKEN_INVALID';
  static const String projectionTokenExpired = 'PROJECTION_TOKEN_EXPIRED';

  // ── VirtualDisplay Errors ─────────────────────────────────────────
  static const String virtualDisplayFailed = 'VIRTUAL_DISPLAY_FAILED';
  static const String virtualDisplayStopped = 'VIRTUAL_DISPLAY_STOPPED';
  static const String surfaceInvalid = 'SURFACE_INVALID';

  // ── Frame Capture Errors ──────────────────────────────────────────
  static const String frameCaptureFailed = 'FRAME_CAPTURE_FAILED';
  static const String frameCaptureTimeout = 'FRAME_CAPTURE_TIMEOUT';
  static const String imageReaderError = 'IMAGE_READER_ERROR';
  static const String i420ConversionFailed = 'I420_CONVERSION_FAILED';

  // ── WebRTC Errors ─────────────────────────────────────────────────
  static const String webrtcConnectionFailed = 'WEBRTC_CONNECTION_FAILED';
  static const String webrtcIceFailed = 'WEBRTC_ICE_FAILED';
  static const String webrtcSignalingFailed = 'WEBRTC_SIGNALING_FAILED';
  static const String webrtcGetDisplayMediaFailed = 'WEBRTC_GET_DISPLAY_MEDIA_FAILED';

  // ── Service Errors ────────────────────────────────────────────────
  static const String serviceNotRunning = 'SERVICE_NOT_RUNNING';
  static const String serviceCrashed = 'SERVICE_CRASHED';
  static const String foregroundServiceDenied = 'FOREGROUND_SERVICE_DENIED';

  // ── Network Errors ────────────────────────────────────────────────
  static const String networkUnavailable = 'NETWORK_UNAVAILABLE';
  static const String firebaseDisconnected = 'FIREBASE_DISCONNECTED';

  /// Get a user-friendly message for an error code.
  static String getUserMessage(String code) {
    switch (code) {
      case projectionNotActive:
        return 'Screen recording permission is not active. Please grant permission on the child device.';
      case projectionRevoked:
        return 'Screen recording permission was revoked. Please re-grant permission on the child device.';
      case projectionConsentDenied:
        return 'Screen recording permission was denied. The child must accept the permission dialog.';
      case projectionTokenInvalid:
        return 'The screen recording token is invalid. Please restart monitoring.';
      case projectionTokenExpired:
        return 'The screen recording token has expired. Please re-grant permission.';
      case virtualDisplayFailed:
        return 'Failed to create screen capture display. The device may not support this feature.';
      case virtualDisplayStopped:
        return 'Screen capture display was stopped unexpectedly. Attempting to recover...';
      case surfaceInvalid:
        return 'Screen capture surface became invalid. Attempting to recover...';
      case frameCaptureFailed:
        return 'Frame capture failed. The monitoring session may be interrupted.';
      case frameCaptureTimeout:
        return 'Frame capture timed out. The child device may be under heavy load.';
      case imageReaderError:
        return 'Image reader error occurred. Attempting to recover...';
      case i420ConversionFailed:
        return 'Video frame conversion failed. Frame quality may be reduced.';
      case webrtcConnectionFailed:
        return 'WebRTC connection failed. Check network connectivity and try again.';
      case webrtcIceFailed:
        return 'ICE connection failed. The devices may be behind incompatible networks.';
      case webrtcSignalingFailed:
        return 'Signaling failed. Check your internet connection.';
      case webrtcGetDisplayMediaFailed:
        return 'Screen sharing via WebRTC failed. Falling back to native capture.';
      case serviceNotRunning:
        return 'The monitoring service is not running. Attempting to restart...';
      case serviceCrashed:
        return 'The monitoring service crashed. Attempting to recover...';
      case foregroundServiceDenied:
        return 'Foreground service permission was denied. Please enable it in settings.';
      case networkUnavailable:
        return 'Network is unavailable. Check your internet connection.';
      case firebaseDisconnected:
        return 'Disconnected from server. Reconnecting...';
      default:
        return 'An unknown error occurred. Please try again.';
    }
  }

  /// Check if the error is recoverable (automatic retry is appropriate).
  static bool isRecoverable(String code) {
    switch (code) {
      case projectionRevoked:
      case virtualDisplayStopped:
      case surfaceInvalid:
      case frameCaptureFailed:
      case imageReaderError:
      case webrtcConnectionFailed:
      case webrtcIceFailed:
      case serviceNotRunning:
      case serviceCrashed:
      case networkUnavailable:
      case firebaseDisconnected:
        return true;
      case projectionConsentDenied:
      case projectionTokenInvalid:
      case projectionTokenExpired:
      case foregroundServiceDenied:
        return false;
      default:
        return false;
    }
  }

  /// Check if the error requires user action.
  static bool requiresUserAction(String code) {
    switch (code) {
      case projectionNotActive:
      case projectionConsentDenied:
      case projectionTokenExpired:
      case foregroundServiceDenied:
        return true;
      default:
        return false;
    }
  }
}
