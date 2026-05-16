# Screen Monitor Upgrade — Gap Analysis Audit

**Project**: family-monitor  
**Package**: `com.example.family_monitor`  
**Reference**: FlashGet Kids (`com.flashget.kidscontrol` / `com.flashget.parentalcontrol`)  
**Date**: 2026-05-16  
**Auditor**: Automated Gap Analysis  

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Comparison](#2-architecture-comparison)
3. [Current State — family-monitor](#3-current-state--family-monitor)
4. [Reference State — FlashGet Kids](#4-reference-state--flashget-kids)
5. [Gap Register](#5-gap-register)
   - [P0 — Critical](#51-p0--critical-must-fix)
   - [P1 — High](#52-p1--high-should-fix)
   - [P2 — Medium](#53-p2--medium-nice-to-have)
6. [Change Specification Matrix](#6-change-specification-matrix)
7. [Dependency & Layer Map](#7-dependency--layer-map)
8. [Risk Assessment](#8-risk-assessment)
9. [Recommended Implementation Order](#9-recommended-implementation-order)
10. [Appendix — File Inventory](#10-appendix--file-inventory)

---

## 1. Executive Summary

This audit identifies **23 gaps** between the current `family-monitor` screen capture implementation and the reference `FlashGet Kids` production system. Of these:

| Severity | Count | Description |
|----------|-------|-------------|
| **P0 — Critical** | 7 | System will fail or produce unusable output without these |
| **P1 — High** | 10 | Significant reliability, quality, or UX deficiencies |
| **P2 — Medium** | 6 | Improvements for robustness and security hygiene |

The most impactful gaps cluster around three themes:

1. **MediaProjection lifecycle fragility** — The current `StealthActivity` consent flow and scattered `VirtualDisplay` logic break on Android 14+ and under rotation changes.
2. **Frame capture quality** — 480x854 @ JPEG 40% @ 3fps via Firebase RTDB base64 is orders of magnitude below the reference's I420 hardware-encoded pipeline.
3. **Operational resilience** — No directBoot support, no-op watchdog, no stream health monitoring, and no error taxonomy mean the system cannot self-heal or report status accurately.

---

## 2. Architecture Comparison

### 2.1 Current Architecture (family-monitor)

```
┌─────────────────────────────────────────────────────────────────┐
│                        PARENT DEVICE                            │
│  ┌──────────────────┐    ┌────────────────────────────────┐    │
│  │ monitoring_screen │◄───│ Firebase RTDB (base64 frames)  │    │
│  │   (display only)  │    └───────────────┬────────────────┘    │
│  └──────────────────┘                     │                      │
│                                  ┌───────┴───────┐              │
│                                  │  WebRTC P2P   │              │
│                                  │ (flutter_webrtc│              │
│                                  │  direct video) │              │
│                                  └───────┬───────┘              │
└──────────────────────────────────────────┼──────────────────────┘
                                           │
═══════════════════════════════════════════╪═══════════════════════
                          NETWORK BOUNDARY │
═══════════════════════════════════════════╪═══════════════════════
                                           │
┌──────────────────────────────────────────┼──────────────────────┐
│                        CHILD DEVICE      │                      │
│                                  ┌───────┴───────┐              │
│                                  │  WebRTC P2P   │              │
│                                  │  (send track) │              │
│                                  └───────┬───────┘              │
│                                          │                      │
│  ┌──────────────────┐    ┌───────────────┴────────────────┐    │
│  │  StealthActivity │    │    ScreenCaptureService         │    │
│  │  (consent dialog)│    │  ┌─────────────────────────┐   │    │
│  └────────┬─────────┘    │  │ VirtualDisplay (inline) │   │    │
│           │              │  │ ImageReader (inline)    │   │    │
│           └──────────────►  │ Timer.periodic(333ms)   │   │    │
│              MediaProjection│ JPEG 40% → base64       │   │    │
│              result code    │ → Firebase RTDB         │   │    │
│                             └─────────────────────────┘   │    │
│                             ┌─────────────────────────┐   │    │
│                             │ WatchdogWorker (15min)   │   │    │
│                             │ watchdog_entrypoint.dart │   │    │
│                             │ (NO-OP — only logs)      │   │    │
│                             └─────────────────────────┘   │    │
│                             ┌─────────────────────────┐   │    │
│                             │ BootReceiver             │   │    │
│                             │ (NOT directBootAware)    │   │    │
│                             └─────────────────────────┘   │    │
│                             └────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Reference Architecture (FlashGet Kids)

```
┌─────────────────────────────────────────────────────────────────┐
│                        PARENT DEVICE                            │
│  ┌──────────────────────┐                                       │
│  │   monitoring_screen   │  ┌──────────────┐  ┌─────────────┐  │
│  │  + stream health UI   │  │ TRTCCloud    │  │ V2TXLive-   │  │
│  │  + reconnect indicator│  │ (WebRTC recv)│  │ Player      │  │
│  │  + remote controls    │  └──────┬───────┘  │ (RTMP recv) │  │
│  └──────────────────────┘         │          └──────┬──────┘  │
│                                   │                 │          │
└───────────────────────────────────┼─────────────────┼──────────┘
                                    │                 │
════════════════════════════════════╪═════════════════╪═══════════
                    NETWORK BOUNDARY│                 │
════════════════════════════════════╪═════════════════╪═══════════
                                    │                 │
┌───────────────────────────────────┼─────────────────┼──────────┐
│                        CHILD DEVICE│                 │          │
│                    ┌───────────────┴───────┐ ┌──────┴───────┐  │
│                    │ ScreenCapturer-       │ │ V2TXLive-    │  │
│                    │ Android2 (WebRTC)     │ │ Pusher (RTMP)│  │
│                    │ + ImageReader         │ │ /RTC push    │  │
│                    └───────────┬───────────┘ └──────┬───────┘  │
│                                │                    │          │
│  ┌─────────────────────────────┼────────────────────┼───────┐  │
│  │    VirtualDisplayManager    │                    │       │  │
│  │    (SINGLETON)              │                    │       │  │
│  │  ┌──────────────────────────┴────────────────────┐      │  │
│  │  │  MediaProjection (cached via MediaProjection- │      │  │
│  │  │  Cache singleton)                              │      │  │
│  │  │  VirtualDisplay (multi-surface)                │      │  │
│  │  │  Delayed cleanup (1s)                          │      │  │
│  │  └───────────────────────────────────────────────┘      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  TXScreenCaptureAssistantActivity (TRANSPARENT)          │  │
│  │  + Auto-click "Start Now" via AccessibilityService      │  │
│  │  + MediaProjectionConfig.createConfigForDefaultDisplay() │  │
│  │  + Cached projection reuse check                         │  │
│  └──────────────────────────────┬───────────────────────────┘  │
│                                 │                              │
│  ┌──────────────────────────────┼───────────────────────────┐  │
│  │        Keep-Alive Layer      │                           │  │
│  │  ┌────────────┐  ┌──────────┴──┐  ┌──────────────────┐  │  │
│  │  │EventReceiver│  │PushKeepLive-│  │Accessibility-    │  │  │
│  │  │(directBoot) │  │Receiver    │  │LimitService     │  │  │
│  │  │LOCKED_BOOT  │  │(:push proc)│  │(directBootAware)│  │  │
│  │  └────────────┘  └─────────────┘  └──────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

### 2.3 Key Architectural Deltas

| Aspect | family-monitor | FlashGet Kids | Impact |
|--------|---------------|---------------|--------|
| Projection consent | `StealthActivity` (fragile) | `TXScreenCaptureAssistantActivity` (transparent + auto-click) | Reliability |
| Projection caching | `static volatile` fields + `SharedPreferences` | `MediaProjectionCache` singleton | State consistency |
| Display management | Inline in `ScreenCaptureService` | Singleton `VirtualDisplayManager` | Separation of concerns |
| Frame capture | `Timer.periodic(333ms)` polling | MIX_MODE: 10ms poll → `OnImageAvailableListener` | Throughput |
| Frame encoding | RGBA → JPEG 40% → base64 | RGBA → I420 via libyuv → JavaI420Buffer | Quality + compatibility |
| Frame relay | Firebase RTDB base64 | WebRTC video track + RTMP/RTC | Latency + quality |
| Stream protocols | WebRTC P2P only | WebRTC + V2TXLivePusher (RTMP/RTC) | Redundancy |
| Boot recovery | `BootReceiver` (not directBoot) | `EventReceiver` (directBootAware) | Pre-unlock monitoring |
| Watchdog | No-op Dart entrypoint | Multi-process keep-alive | Self-healing |
| Error handling | None (silent failures) | Error code taxonomy | Observability |

---

## 3. Current State — family-monitor

| Component | Location | Notes |
|-----------|----------|-------|
| **Package** | `com.example.family_monitor` | Flutter app with native Android |
| **Screen Capture** | WebRTC P2P + `VirtualDisplay`+`ImageReader` fallback | Base64 relay via Firebase RTDB |
| **Streaming** | `flutter_webrtc` for P2P | No Tencent SDK |
| **Foreground Services** | `ScreenCaptureService` (MEDIA_PROJECTION\|DATA_SYNC), `BackgroundService`, `ForegroundTask`, `WatchdogService` | |
| **Boot Recovery** | `BootReceiver` + `WatchdogReceiver` (60s) + `WatchdogWorker` (15min) | Not directBootAware |
| **MediaProjection Flow** | `MainActivity` → `StealthActivity` → consent → `ScreenCaptureService` → `static volatile` + `SharedPreferences` | Fragile on Android 14+ |

### Key Files (Current)

```
android/app/src/main/kotlin/com/example/family_monitor/
├── MainActivity.kt
├── StealthActivity.kt
├── ScreenCaptureService.kt
├── BootReceiver.kt
├── WatchdogReceiver.kt
├── WatchdogScheduler.kt
├── WatchdogWorker.kt
├── WatchdogService.kt
├── PinVerifyActivity.kt
├── DialerCodeReceiver.kt
├── ScreenNotificationListener.kt
├── FamilyDeviceAdminReceiver.kt
└── AppBlockAccessibilityService.kt

lib/
├── services/
│   ├── silent_webrtc_service.dart
│   ├── webrtc_service.dart
│   ├── presence_service.dart
│   ├── screen_capture_channel.dart
│   ├── background_monitoring_service.dart
│   └── foreground_service.dart
├── background/
│   └── watchdog_entrypoint.dart
└── screens/parent/
    └── monitoring_screen.dart
```

---

## 4. Reference State — FlashGet Kids

| Component | Location | Notes |
|-----------|----------|-------|
| **Package** | `com.flashget.kidscontrol` / `com.flashget.parentalcontrol` | Dual package (child/parent) |
| **Screen Capture** | Dual pipeline: WebRTC (`ScreenCapturerAndroid2` with `ImageReader`) + Tencent LiteAV (`VirtualDisplayManager` with native `Surface`) | |
| **Streaming** | `V2TXLivePusher` (RTMP/RTC) + `TRTCCloud` for WebRTC | |
| **Foreground Services** | `SnapshotScreenService`, `SandWebRTCService_`, `ScreenCaptureService` (bound), `CameraPreviewService` | |
| **Boot Recovery** | `EventReceiver` (directBootAware), `KidNetworkCallbackReceiver`, `PushKeepLiveReceiver` (:push process), `AccessibilityLimitService` (directBootAware) | Multi-layer keep-alive |
| **MediaProjection Flow** | `TXScreenCaptureAssistantActivity` (transparent) → auto-click via Accessibility → `MediaProjectionCache` singleton → `VirtualDisplayManager` | |

---

## 5. Gap Register

### 5.1 P0 — Critical (Must Fix)

#### GAP-01: No TXScreenCaptureAssistantActivity

| Field | Value |
|-------|-------|
| **ID** | GAP-01 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD |
| **Current** | `StealthActivity` — opaque activity requiring manual consent; fragile across OEM customizations |
| **Reference** | `TXScreenCaptureAssistantActivity` — transparent, auto-clicks "Start Now" via accessibility, checks cached projection before showing dialog |
| **Impact** | Projection consent fails silently on many devices; no Android 14+ `MediaProjectionConfig` support; user must manually tap consent each time |

**Missing capabilities:**
- Dedicated transparent permission launcher activity
- Auto-click of "Start Now" button via `AccessibilityService`
- `MediaProjectionConfig.createConfigForDefaultDisplay()` for Android 14+ (API 34)
- Cached projection reuse check before showing consent dialog

**File changes:**
| Action | File |
|--------|------|
| **NEW** | `android/app/src/main/kotlin/com/example/family_monitor/TXScreenCaptureAssistantActivity.kt` |
| **MODIFY** | `android/app/src/main/AndroidManifest.xml` (register activity) |
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` (launch new activity) |

---

#### GAP-02: No Centralized VirtualDisplayManager

| Field | Value |
|-------|-------|
| **ID** | GAP-02 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD |
| **Current** | `VirtualDisplay` + `ImageReader` logic inlined in `ScreenCaptureService`; no separation of concerns |
| **Reference** | Singleton `VirtualDisplayManager` owning all projection/display state |
| **Impact** | State leaks across service restarts; impossible to support multiple surfaces (WebRTC + Tencent simultaneously); rotation changes corrupt display |

**Missing capabilities:**
- Singleton projection/display manager
- Multiple surface support (add/remove surfaces dynamically)
- Delayed cleanup (1s delay) on projection stop to allow final frames
- Listener pattern for capture errors (surface disconnect, projection death)

**File changes:**
| Action | File |
|--------|------|
| **NEW** | `android/app/src/main/kotlin/com/example/family_monitor/VirtualDisplayManager.kt` |
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` (delegate to manager) |

---

#### GAP-03: No MIX_MODE Frame Capture

| Field | Value |
|-------|-------|
| **ID** | GAP-03 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD |
| **Current** | `Timer.periodic(333ms)` polling → ~3fps max |
| **Reference** | 10ms polling for first 360 frames (~3.6s warm-up) then automatic switch to `OnImageAvailableListener` for maximum throughput |
| **Impact** | 3fps is insufficient for real-time monitoring; reference achieves 20-30fps; initial frame delivery is delayed |

**Missing capabilities:**
- Aggressive initial polling (10ms interval, ~100fps attempt rate)
- Automatic switch to listener mode after warm-up (360 frames)
- Last-frame caching for null image fallback (avoid blank frames)
- `ImageReader` error drain (clear stale images on error)

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` |

---

#### GAP-04: No I420/YUV Conversion

| Field | Value |
|-------|-------|
| **ID** | GAP-04 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD |
| **Current** | RGBA → JPEG 40% compression → base64 string → Firebase RTDB |
| **Reference** | RGBA → I420 via libyuv → `JavaI420Buffer` → hardware encoder pipeline |
| **Impact** | JPEG compression destroys frame quality at 40%; base64 encoding adds 33% overhead; incompatible with WebRTC video track; CPU-intensive software JPEG on every frame |

**Missing capabilities:**
- RGB → YUV (I420) conversion (libyuv or manual)
- `JavaI420Buffer` allocation for WebRTC compatibility
- Hardware encoder pipeline (`MediaCodec`) for H.264 output

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` |
| **NEW** | `android/app/src/main/kotlin/com/example/family_monitor/I420Converter.kt` (if extracted) |

---

#### GAP-05: Broken Android 14+ WebRTC Screen Capture

| Field | Value |
|-------|-------|
| **ID** | GAP-05 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD |
| **Current** | `Intent.toUri(0)` serialization loses `IBinder` tokens; no `MediaProjectionConfig` support |
| **Reference** | Proper `MediaProjectionConfig` for API 34+; Parcel-based token passing |
| **Impact** | Screen capture completely broken on Android 14+ devices (API 34+); increasing market share means this is a growing failure |

**Missing capabilities:**
- `MediaProjectionConfig.createConfigForDefaultDisplay()` for API 34+
- Proper Parcel-based token passing instead of `Intent.toUri(0)`
- Graceful degradation path for API < 34

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` |
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/StealthActivity.kt` |

---

#### GAP-06: Watchdog Entrypoint is a No-Op

| Field | Value |
|-------|-------|
| **ID** | GAP-06 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD |
| **Current** | `watchdog_entrypoint.dart` — only logs a message, performs no health check or recovery |
| **Reference** | Multi-layer keep-alive with service restart and projection restoration |
| **Impact** | Service deaths are not detected or recovered; the entire watchdog chain (BootReceiver → WatchdogReceiver → WatchdogWorker → entrypoint) produces no useful work |

**Missing capabilities:**
- Actual health check logic (verify `ScreenCaptureService` is running)
- Service restart logic (re-launch foreground service if dead)
- Projection restoration logic (re-acquire `MediaProjection` if lost)

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `lib/background/watchdog_entrypoint.dart` |

---

#### GAP-07: Low-Quality Frame Relay

| Field | Value |
|-------|-------|
| **ID** | GAP-07 |
| **Severity** | P0 — Critical |
| **Layer** | CHILD + SHARED |
| **Current** | 480x854 @ JPEG 40% @ 3fps via Firebase RTDB base64 relay |
| **Reference** | Hardware-encoded H.264 via `MediaCodec`; direct streaming via WebSocket/RTMP/RTC |
| **Impact** | Unusable video quality; Firebase RTDB is not designed for streaming (high latency, quota exhaustion); base64 adds 33% size overhead |

**Missing capabilities:**
- Hardware encoder (`MediaCodec` H.264)
- Direct streaming transport (WebSocket or RTMP)
- Adaptive quality (resolution/bitrate/frame rate based on network)
- Fallback to current method for degraded mode

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `lib/services/silent_webrtc_service.dart` |
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` |

---

### 5.2 P1 — High (Should Fix)

#### GAP-08: No directBootAware Receivers

| Field | Value |
|-------|-------|
| **ID** | GAP-08 |
| **Severity** | P1 — High |
| **Layer** | CHILD |
| **Current** | `BootReceiver` is not `directBootAware`; requires device unlock before monitoring can start |
| **Reference** | `EventReceiver` with `directBootAware=true` + `LOCKED_BOOT_COMPLETED` handling |
| **Impact** | Monitoring gap between device boot and user unlock; critical for lost/stolen scenarios |

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `android/app/src/main/AndroidManifest.xml` |
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/BootReceiver.kt` |

---

#### GAP-09: No SharedPreferences Key Consistency

| Field | Value |
|-------|-------|
| **ID** | GAP-09 |
| **Severity** | P1 — High |
| **Layer** | CHILD |
| **Current** | Heartbeat key mismatch between Flutter and native layers |
| **Reference** | Unified key namespace across all layers |
| **Impact** | Watchdog cannot detect live services; false-positive service restarts; battery drain |

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/WatchdogReceiver.kt` |
| **MODIFY** | `lib/services/background_monitoring_service.dart` |

---

#### GAP-10: No Rotation Hot-Swap

| Field | Value |
|-------|-------|
| **ID** | GAP-10 |
| **Severity** | P1 — High |
| **Layer** | CHILD |
| **Current** | `VirtualDisplay` not recreated on orientation change; frames are stretched or corrupted after rotation |
| **Reference** | Rotation detection + `VirtualDisplay` teardown/recreate on rotate |
| **Impact** | Corrupted video after any orientation change; requires full service restart to recover |

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `android/app/src/main/kotlin/com/example/family_monitor/ScreenCaptureService.kt` |

---

#### GAP-11: No Screen Blocking/Censoring

| Field | Value |
|-------|-------|
| **ID** | GAP-11 |
| **Severity** | P1 — High |
| **Layer** | CHILD |
| **Current** | No ability to hide sensitive content during capture |
| **Reference** | Block overlay with color + text applied to captured frames |
| **Impact** | Privacy violation when capturing screens with sensitive content (banking, medical, etc.) |

**File changes:**
| Action | File |
|--------|------|
| **NEW** | Block overlay logic in `ScreenCaptureService.kt` |

---

#### GAP-12: No Brightness Boost

| Field | Value |
|-------|-------|
| **ID** | GAP-12 |
| **Severity** | P1 — High |
| **Layer** | CHILD |
| **Current** | Captured screens in dark environments are unreadable |
| **Reference** | Luminance adjustment applied to captured frames |
| **Impact** | Unusable captures in low-light/dark-mode scenarios |

**File changes:**
| Action | File |
|--------|------|
| **NEW** | Luminance adjustment in `ScreenCaptureService.kt` |

---

#### GAP-13: Parent Monitoring UI Lacks Stream Health

| Field | Value |
|-------|-------|
| **ID** | GAP-13 |
| **Severity** | P1 — High |
| **Layer** | PARENT |
| **Current** | `monitoring_screen.dart` has no reconnect indicator, error display, or stream status |
| **Reference** | Full stream health UI with connection state, error reporting, reconnect controls |
| **Impact** | Parent has no visibility into whether monitoring is active; silent failures go unnoticed |

**Missing capabilities:**
- Stream health indicator (green/yellow/red)
- Reconnect indicator with countdown
- Error reporting to user
- Connection state UI (connecting/connected/disconnected/reconnecting)

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `lib/screens/parent/monitoring_screen.dart` |

---

#### GAP-14: No Remote Start/Stop Controls

| Field | Value |
|-------|-------|
| **ID** | GAP-14 |
| **Severity** | P1 — High |
| **Layer** | PARENT + SHARED |
| **Current** | Parent cannot specifically start/stop screen capture on child device |
| **Reference** | Remote capture control commands |
| **Impact** | No way to remotely activate monitoring; requires physical access to child device |

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `lib/screens/parent/monitoring_screen.dart` |
| **MODIFY** | Shared command protocol (Firebase RTDB or signaling) |

---

#### GAP-15: No Session/Stream ID Management

| Field | Value |
|-------|-------|
| **ID** | GAP-15 |
| **Severity** | P1 — High |
| **Layer** | SHARED |
| **Current** | No unique session or stream identifiers |
| **Reference** | Session IDs, stream IDs, reconnect tokens |
| **Impact** | Cannot distinguish between sessions; cannot implement reconnect tokens; cannot correlate frames to sessions |

**File changes:**
| Action | File |
|--------|------|
| **NEW** | `lib/services/session_manager.dart` |

---

#### GAP-16: No Stream Health Heartbeat

| Field | Value |
|-------|-------|
| **ID** | GAP-16 |
| **Severity** | P1 — High |
| **Layer** | SHARED |
| **Current** | No dedicated protocol for stream liveness (device presence exists but not stream-level) |
| **Reference** | Stream-level heartbeat separate from device presence; frame count/bitrate stats; latency measurement |
| **Impact** | Cannot detect stream interruption while device appears "online"; no QoS metrics |

**File changes:**
| Action | File |
|--------|------|
| **MODIFY** | `lib/services/presence_service.dart` |

---

#### GAP-17: No Error Code Taxonomy

| Field | Value |
|-------|-------|
| **ID** | GAP-17 |
| **Severity** | P1 — High |
| **Layer** | SHARED |
| **Current** | No standardized error codes for screen capture failures |
| **Reference** | Error code definitions with mapping to user-facing messages |
| **Impact** | Failures are silent or use generic messages; impossible to triage issues; no actionable error reporting |

**File changes:**
| Action | File |
|--------|------|
| **NEW** | `lib/services/capture_errors.dart` |

---

### 5.3 P2 — Medium (Nice to Have)

| ID | Gap | Layer | Description |
|----|-----|-------|-------------|
| GAP-18 | No multi-process keep-alive | CHILD | Only single process; reference has `:push` process for redundancy |
| GAP-19 | No V2TXLivePusher integration | CHILD | No Tencent SDK (would require commercial license) |
| GAP-20 | No SystemLoopbackRecorder | CHILD | No system audio capture capability |
| GAP-21 | No battery optimization request flow | CHILD | No explicit `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog |
| GAP-22 | No duplicate service start prevention | CHILD | No guard against double-start of `ScreenCaptureService` |
| GAP-23 | Hardcoded Firebase API keys | SHARED | Security exposure in source code |

---

## 6. Change Specification Matrix

### 6.1 New Files

| File | GAP(s) | Language | Description |
|------|--------|----------|-------------|
| `android/.../TXScreenCaptureAssistantActivity.kt` | GAP-01 | Kotlin | Transparent activity for MediaProjection consent with auto-click and Android 14+ config |
| `android/.../VirtualDisplayManager.kt` | GAP-02 | Kotlin | Singleton managing VirtualDisplay lifecycle, multiple surfaces, delayed cleanup |
| `android/.../I420Converter.kt` | GAP-04 | Kotlin | RGBA→I420 conversion utility (libyuv or manual) |
| `lib/services/session_manager.dart` | GAP-15 | Dart | Session/stream ID generation, reconnect tokens |
| `lib/services/capture_errors.dart` | GAP-17 | Dart | Error code taxonomy with user-facing message mapping |

### 2 Modified Files

| File | GAP(s) | Changes |
|------|--------|---------|
| `ScreenCaptureService.kt` | GAP-02, GAP-03, GAP-04, GAP-05, GAP-07, GAP-10, GAP-11, GAP-12, GAP-22 | Delegate to VirtualDisplayManager; MIX_MODE capture; I420 conversion; Android 14+ fix; rotation hot-swap; block overlay; brightness boost; duplicate start guard |
| `StealthActivity.kt` | GAP-05 | Parcel-based token passing for Android 14+ |
| `AndroidManifest.xml` | GAP-01, GAP-08 | Register TXScreenCaptureAssistantActivity; add directBootAware to BootReceiver |
| `BootReceiver.kt` | GAP-08 | Handle LOCKED_BOOT_COMPLETED |
| `WatchdogReceiver.kt` | GAP-09 | Fix SharedPreferences key namespace |
| `watchdog_entrypoint.dart` | GAP-06 | Add health check, service restart, projection restoration |
| `silent_webrtc_service.dart` | GAP-07 | Hardware encoder pipeline, adaptive quality |
| `monitoring_screen.dart` | GAP-13, GAP-14 | Stream health UI, reconnect indicator, remote controls |
| `background_monitoring_service.dart` | GAP-09 | Fix SharedPreferences key namespace |
| `presence_service.dart` | GAP-16 | Stream-level heartbeat, frame stats, latency measurement |

---

## 7. Dependency & Layer Map

```
Layer Legend:
  [C] = CHILD (runs on child device)
  [P] = PARENT (runs on parent device)
  [S] = SHARED (runs on both)
```

### 7.1 GAP Dependency Graph

```
GAP-01 (TXScreenCaptureAssistantActivity) [C]
  │
  ├──► GAP-05 (Android 14+ fix) [C]  ← overlapping: both touch consent flow
  │
  └──► GAP-02 (VirtualDisplayManager) [C]
        │
        ├──► GAP-03 (MIX_MODE capture) [C]
        │
        ├──► GAP-04 (I420/YUV conversion) [C]
        │      │
        │      └──► GAP-07 (Low-quality relay) [C+S]
        │             │
        │             └──► GAP-13 (Stream health UI) [P]
        │             └──► GAP-14 (Remote controls) [P+s]
        │             └──► GAP-16 (Stream heartbeat) [S]
        │
        └──► GAP-10 (Rotation hot-swap) [C]

GAP-06 (Watchdog no-op) [C]
  ├──► GAP-08 (directBootAware) [C]
  └──► GAP-09 (Key consistency) [C]

GAP-15 (Session IDs) [S]  ← independent
GAP-17 (Error codes) [S]  ← feeds into GAP-13
```

### 7.2 Layer Impact Summary

| Layer | P0 Gaps | P1 Gaps | P2 Gaps | Total |
|-------|---------|---------|---------|-------|
| CHILD | 7 | 5 | 4 | 16 |
| PARENT | 0 | 1 | 0 | 1 |
| SHARED | 0 | 3 | 1 | 4 |
| CHILD+SHARED | 0 | 1 | 0 | 1 |
| PARENT+SHARED | 0 | 1 | 0 | 1 |
| **Total** | **7** | **10** | **6** | **23** |

---

## 8. Risk Assessment

### 8.1 Risk Matrix

| GAP | Likelihood of Failure | Impact if Unfixed | Risk Score |
|-----|-----------------------|-------------------|------------|
| GAP-05 | **HIGH** — Android 14+ market share growing rapidly | **CRITICAL** — Screen capture completely broken | **🔴 10/10** |
| GAP-06 | **CERTAIN** — Watchdog is already a no-op | **HIGH** — No self-healing capability | **🔴 9/10** |
| GAP-07 | **CERTAIN** — 3fps JPEG is already inadequate | **HIGH** — Unusable monitoring quality | **🔴 9/10** |
| GAP-01 | **HIGH** — StealthActivity breaks on many OEMs | **HIGH** — Consent flow unreliable | **🔴 8/10** |
| GAP-02 | **MEDIUM** — Works but unmaintainable | **HIGH** — Cannot add features without refactoring | **🟠 7/10** |
| GAP-03 | **HIGH** — 3fps is already below threshold | **MEDIUM** — Quality gap vs. reference | **🟠 7/10** |
| GAP-04 | **MEDIUM** — JPEG works but poorly | **HIGH** — Blocks WebRTC video track integration | **🟠 7/10** |
| GAP-08 | **MEDIUM** — Depends on reboot frequency | **MEDIUM** — Monitoring gap after reboot | **🟡 5/10** |
| GAP-10 | **MEDIUM** — Rotation is common | **MEDIUM** — Corrupted frames | **🟡 5/10** |
| GAP-13 | **HIGH** — Silent failures are invisible | **MEDIUM** — Poor UX | **🟡 5/10** |
| GAP-09 | **HIGH** — Keys are already mismatched | **MEDIUM** — False-positive restarts | **🟡 5/10** |

### 8.2 Android Version Risk

```
Android 14+ (API 34+)
├── GAP-05: MediaProjection completely broken ← CRITICAL
├── GAP-01: MediaProjectionConfig required ← CRITICAL
└── foreground service type enforcement

Android 12+ (API 31+)
├── Exact alarm restrictions affect watchdog scheduling
└── Foreground service launch restrictions from background

Android 10+ (API 29+)
├── MediaProjection consent required (no background consent)
└── Scoped storage may affect SharedPreferences
```

---

## 9. Recommended Implementation Order

### Phase 1: Foundation (P0 — Weeks 1-2)

**Goal**: Fix broken functionality and establish architectural foundations.

```
Week 1: Fix what's broken
┌──────────────────────────────────────────────────────┐
│ 1. GAP-05: Android 14+ MediaProjection fix           │
│    - Modify StealthActivity.kt + ScreenCaptureService │
│    - Test on API 34+ emulator/device                 │
│                                                      │
│ 2. GAP-06: Watchdog entrypoint                       │
│    - Rewrite watchdog_entrypoint.dart                │
│    - Add health check + service restart              │
│    - Test: kill service, verify auto-recovery        │
│                                                      │
│ 3. GAP-01: TXScreenCaptureAssistantActivity          │
│    - New file: TXScreenCaptureAssistantActivity.kt   │
│    - Integrate with ScreenCaptureService             │
│    - Test: consent flow on multiple OEMs             │
└──────────────────────────────────────────────────────┘

Week 2: Architectural refactoring
┌──────────────────────────────────────────────────────┐
│ 4. GAP-02: VirtualDisplayManager singleton           │
│    - New file: VirtualDisplayManager.kt              │
│    - Refactor ScreenCaptureService to delegate       │
│    - Test: service restart preserves state           │
│                                                      │
│ 5. GAP-03: MIX_MODE frame capture                    │
│    - Replace Timer.periodic with MIX_MODE            │
│    - Test: frame rate improvement (3fps → 20+fps)   │
│                                                      │
│ 6. GAP-04: I420/YUV conversion                       │
│    - New file: I420Converter.kt                      │
│    - Replace JPEG pipeline with I420                 │
│    - Test: WebRTC video track compatibility          │
│                                                      │
│ 7. GAP-07: Frame relay upgrade                       │
│    - Add MediaCodec H.264 encoder                    │
│    - Add WebSocket/RTMP transport                    │
│    - Keep Firebase RTDB as fallback                  │
│    - Test: end-to-end streaming quality              │
└──────────────────────────────────────────────────────┘
```

### Phase 2: Resilience (P1 — Weeks 3-4)

**Goal**: Improve reliability, observability, and UX.

```
Week 3: Boot resilience + consistency
┌──────────────────────────────────────────────────────┐
│ 8.  GAP-08: directBootAware receivers                │
│ 9.  GAP-09: SharedPreferences key consistency         │
│ 10. GAP-10: Rotation hot-swap                        │
│ 11. GAP-15: Session/Stream ID management              │
│ 12. GAP-17: Error code taxonomy                       │
└──────────────────────────────────────────────────────┘

Week 4: UX and monitoring
┌──────────────────────────────────────────────────────┐
│ 13. GAP-13: Parent stream health UI                   │
│ 14. GAP-14: Remote start/stop controls                │
│ 15. GAP-16: Stream health heartbeat                   │
│ 16. GAP-11: Screen blocking/censoring                 │
│ 17. GAP-12: Brightness boost                          │
└──────────────────────────────────────────────────────┘
```

### Phase 3: Hardening (P2 — Week 5)

```
┌──────────────────────────────────────────────────────┐
│ 18. GAP-21: Battery optimization request              │
│ 19. GAP-22: Duplicate service start guard             │
│ 20. GAP-23: Remove hardcoded API keys                 │
│ 21. GAP-18: Multi-process keep-alive (evaluate)       │
│ 22. GAP-19: Tencent SDK evaluation (license needed)   │
│ 23. GAP-20: System audio capture (evaluate)           │
└──────────────────────────────────────────────────────┘
```

---

## 10. Appendix — File Inventory

### A. Files to Create (5 new files)

| # | Path | GAP | Estimated LOC |
|---|------|-----|---------------|
| 1 | `android/app/src/main/kotlin/com/example/family_monitor/TXScreenCaptureAssistantActivity.kt` | GAP-01 | ~200 |
| 2 | `android/app/src/main/kotlin/com/example/family_monitor/VirtualDisplayManager.kt` | GAP-02 | ~300 |
| 3 | `android/app/src/main/kotlin/com/example/family_monitor/I420Converter.kt` | GAP-04 | ~150 |
| 4 | `lib/services/session_manager.dart` | GAP-15 | ~120 |
| 5 | `lib/services/capture_errors.dart` | GAP-17 | ~100 |

### B. Files to Modify (10 existing files)

| # | Path | GAP(s) | Scope of Change |
|---|------|--------|-----------------|
| 1 | `android/.../ScreenCaptureService.kt` | 02,03,04,05,07,10,11,12,22 | Major rewrite |
| 2 | `android/.../StealthActivity.kt` | 05 | Moderate |
| 3 | `android/.../AndroidManifest.xml` | 01,08 | Minor |
| 4 | `android/.../BootReceiver.kt` | 08 | Moderate |
| 5 | `android/.../WatchdogReceiver.kt` | 09 | Minor |
| 6 | `lib/background/watchdog_entrypoint.dart` | 06 | Major rewrite |
| 7 | `lib/services/silent_webrtc_service.dart` | 07 | Major |
| 8 | `lib/screens/parent/monitoring_screen.dart` | 13,14 | Major |
| 9 | `lib/services/background_monitoring_service.dart` | 09 | Minor |
| 10 | `lib/services/presence_service.dart` | 16 | Moderate |

### C. Estimated Effort

| Severity | Gaps | New Files | Modified Files | Estimated Person-Days |
|----------|------|-----------|----------------|----------------------|
| P0 | 7 | 3 | 5 | 15-20 |
| P1 | 10 | 2 | 6 | 12-16 |
| P2 | 6 | 0 | 3 | 5-8 |
| **Total** | **23** | **5** | **10** | **32-44** |

---

*End of audit document. For questions, refer to the GAP IDs when filing implementation tickets.*
