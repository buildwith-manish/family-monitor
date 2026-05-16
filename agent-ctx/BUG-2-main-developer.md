# BUG-2 Fix: Live Screen Shows Blank

## Task ID: BUG-2
## Agent: Main Developer

## Summary
Fixed the Live Screen showing blank when parent taps "Screen" to view child's screen.

## Root Causes
1. **Intent serialization issue** (RC-B2-01): `Intent.toUri(0)` in `getProjectionParams()` loses the IBinder extra needed by `getMediaProjection()`. When flutter_webrtc parses it back with `Intent.parseUri()`, the Binder is gone, causing silent failure.

2. **Timing issue** (RC-B2-02): `_startScreenStreamSafe()` only waited 2 seconds for the projection token. If consent hadn't been granted yet, it gave up immediately.

3. **No retry mechanism** (RC-B2-03): Once `_startScreenStreamSafe()` signaled an error, there was no way to retry when the token became available.

## Files Modified

### 1. ScreenCaptureService.kt
- Added `savedResultDataParcelBytes` static field - Parcel-marshaled Intent bytes preserving the Binder extra
- Added `marshalIntentToParcel()` method using `Parcel.marshall()` instead of `Intent.toUri(0)`
- Added native frame capture pipeline: `VirtualDisplay` + `ImageReader`
- Added `startFrameCapture()`, `stopFrameCapture()`, `getLatestFrame()` methods
- Added `latestFrameBytes` and `frameCaptureRunning` static fields for frame data

### 2. MainActivity.kt
- Modified `getProjectionParams` to also return `resultDataParcel` (Parcel bytes)
- Added `getProjectionParamsParcel` method - dedicated Parcel-only endpoint
- Added `startNativeScreenCapture` method - starts VirtualDisplay frame capture
- Added `stopNativeScreenCapture` method - stops frame capture
- Added `getScreenFrame` method - returns latest JPEG frame bytes

### 3. screen_capture_channel.dart
- Added `getProjectionParamsParcel()` method
- Added `startNativeScreenCapture()` method with width/height/fps params
- Added `stopNativeScreenCapture()` method
- Added `getScreenFrame()` method returning Uint8List

### 4. background_monitoring_service.dart
- Replaced 2-second fixed wait with 15-second polling loop (500ms intervals)
- Added `projectionReady` Firebase listener for automatic retry when child grants consent
- Added `needsConsent` Firebase signal to notify child app that consent is needed
- Added `_projectionReadySub` subscription and cleanup

### 5. silent_webrtc_service.dart
- Added `dart:convert` import for base64Encode
- Added 4-attempt strategy in `_acquireMedia()`:
  1. Parcel-marshaled Intent bytes (preserves Binder)
  2. URI-serialized Intent data (fallback for older Android)
  3. No projection params (may work with Activity context)
  4. Native frame capture + Firebase relay fallback
- Added `_acquireMediaNativeCapture()` method for native capture fallback
- Added `_nativeCaptureTimer` for frame relay loop
- Added cleanup in `stopSilent()` for native capture timer and resources

### 6. child_home_screen.dart
- Modified `_checkAndRestoreScreenProjection()` to:
  - Check `needsConsent` signal from background service
  - Write `projectionReady = true` to Firebase after consent granted
  - Clear `screenError` when consent is re-acquired
  - Signal background service automatically

### 7. monitoring_screen.dart
- Added native capture mode detection via `nativeCaptureMode` Firebase listener
- Added `screenFrame` Firebase listener for base64 frame display
- Added `Image.memory` widget for displaying native capture frames
- Added "Frame Mode" indicator in top bar
- Added cleanup for new subscriptions

## Architecture

The fix implements a layered approach:

1. **Primary path**: Try `getDisplayMedia()` with Parcel bytes (preserves Binder)
2. **Fallback 1**: Try `getDisplayMedia()` with URI data (works on Android 10-13)
3. **Fallback 2**: Try `getDisplayMedia()` without params
4. **Fallback 3**: Native VirtualDisplay + ImageReader capture with Firebase RTDB relay

The signaling flow:
1. Background service detects screen mode → writes `needsConsent` to Firebase
2. Child app UI detects `needsConsent` → shows consent dialog
3. User grants consent → child app writes `projectionReady` to Firebase
4. Background service detects `projectionReady` → starts screen stream
5. If WebRTC fails → child falls back to native capture → parent displays frames
