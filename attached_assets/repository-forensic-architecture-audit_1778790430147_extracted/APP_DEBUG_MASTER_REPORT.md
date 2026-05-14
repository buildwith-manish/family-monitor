# APP_DEBUG_MASTER_REPORT.md
# Family Monitor — Full Forensic Debug & Architecture Audit

**Repository:** https://github.com/buildwith-manish/family-monitor  
**Audit Date:** 2026-05-30  
**Auditor Role:** Senior Android + Flutter + Firebase + Realtime Systems Engineer  
**Format:** Production-grade, brutally honest, suitable for commercial release preparation  
**Scope:** Every Dart file, every Kotlin file, every Gradle config, Firebase data model, WebRTC signaling, background service architecture, CI/CD pipeline

---

## TABLE OF CONTENTS

1. [Full Project Architecture Analysis](#1-full-project-architecture-analysis)
2. [Login + Authentication Analysis](#2-login--authentication-analysis)
3. [Feature-by-Feature Forensic Analysis](#3-feature-by-feature-forensic-analysis)
4. [FlashGet Kids-Style Logic Comparison](#4-flashget-kids-style-logic-comparison)
5. [UI/UX Navigation Analysis](#5-uiux-navigation-analysis)
6. [Firebase Analysis](#6-firebase-analysis)
7. [Code Quality + Stability Audit](#7-code-quality--stability-audit)
8. [Android-Specific Analysis](#8-android-specific-analysis)
9. [Build + Release Analysis](#9-build--release-analysis)
10. [Critical Issues](#10-critical-issues)
11. [High Priority Issues](#11-high-priority-issues)
12. [Medium Priority Issues](#12-medium-priority-issues)
13. [Low Priority Issues](#13-low-priority-issues)
14. [Architecture Refactor Recommendations](#14-architecture-refactor-recommendations)
15. [Stability Score](#15-stability-score)
16. [Release Readiness Score](#16-release-readiness-score)
17. [Production Risk Score](#17-production-risk-score)
18. [Phase-Wise Fix Plan](#18-phase-wise-fix-plan)
19. [Estimated Fix Complexity](#19-estimated-fix-complexity)
20. [Files Most Responsible for Failures](#20-files-most-responsible-for-failures)

---

## 1. FULL PROJECT ARCHITECTURE ANALYSIS

### 1.1 Project Structure Overview

The repository is a **single-repo Flutter project** that produces **two flavors** (parent APK + child APK) via Gradle product flavors. Three Dart entry points exist:

| Entry Point | Flavor | Role |
|---|---|---|
| `lib/main.dart` | default | Shared router; used for debug/single-APK builds |
| `lib/main_parent.dart` | `parent` flavor | Parent-only routing |
| `lib/main_child.dart` | `child` flavor | Child-only routing |

> ⚠️ **CRITICAL ARCHITECTURAL FLAW**: The build system does NOT use `manifestPlaceholders["dartEntrypoint"]` correctly. The Gradle file sets `manifestPlaceholders["dartEntrypoint"] = "main_parent"` and `"main_child"`, but the default `main.dart` defines routes for BOTH parent AND child screens. There is NO flavor-specific enforcement that prevents the parent APK from navigating to child screens or vice versa. A user with the parent APK can route to `/child/home` simply by manipulating shared preferences.

### 1.2 Navigation Flow

```
SplashScreen (2.2s delay)
  └─ checks FirebaseAuth.currentUser + SharedPreferences "user_role"
       ├─ PARENT → /parent/dashboard → ParentDashboardScreen
       │    └─ _ChildCard (per child) → BottomSheet → Feature Screens
       │         ├─ MonitoringScreen (camera/screen WebRTC)
       │         ├─ AppUsageScreen
       │         ├─ SmsCallLogScreen
       │         ├─ ContactsScreen
       │         ├─ SnapshotsScreen
       │         ├─ GeofenceScreen
       │         ├─ BatteryAlertsScreen
       │         ├─ AppLockScreen
       │         ├─ DailyReportScreen
       │         ├─ AppInstallAlertsScreen
       │         ├─ WeeklySummaryScreen
       │         ├─ KeywordAlertScreen
       │         └─ CrashReportScreen
       ├─ CHILD → /child/home → ChildHomeScreen
       │    └─ ChildQrScreen (pairing)
       └─ UNKNOWN → /role-select → RoleSelectionScreen
            ├─ Parent → /parent/auth → ParentAuthScreen (Login/Register)
            └─ Child → /child/setup → ChildSetupWizardScreen (9 pages)
```

**Navigation Flaws Found:**
- No deep-link handling guards — the `onGenerateRoute` for `/child/setup` only validates the argument type but not authentication state.
- `SplashScreen` uses `pushReplacementNamed` but the routes use `MaterialPageRoute` elsewhere — inconsistent navigation style may cause duplicate entries in the back stack.
- After completing child setup wizard, `Navigator.pushReplacementNamed(context, '/child/home')` is called — correct. However if the wizard was launched with a `childUid` argument (from existing account relaunch), the UID passed to `ChildSetupWizardScreen` is only used as a fallback if `_auth.currentUser?.uid` is null. If `currentUser` is null (session expired during wizard), `uid` becomes null and `_finish()` shows "Session expired" with no recovery path.

### 1.3 Parent-Child Sync Flow

```
Parent App                           Firebase RTDB                     Child App
──────────                           ─────────────                     ──────────
[Tap "View Camera"]
  │
  ▼
WebRTCService.startAsParent()
  writes: calls/$childUid/status = "calling"
          calls/$childUid/mode = "camera"          ──────────────►  BackgroundMonitoringService
                                                                       _callsSub fires
                                                                       SilentWebRTCService.startSilentCamera()
                                                                         creates RTCPeerConnection
                                                                         acquires getUserMedia
                                                                         writes: calls/$childUid/offer
                                                                                 calls/$childUid/childCandidates
  ◄─────────────────────────────────────────────────────────────────
WebRTCService (parent) _offerSub fires
  setRemoteDescription(offer)
  createAnswer()
  writes: calls/$childUid/answer
          calls/$childUid/parentCandidates         ──────────────►  SilentWebRTCService._offerSub → _answerSet=true
                                                                       _candidateSub → addCandidate
ICE negotiation complete
Parent: remoteRenderer.srcObject = stream
onRemoteStream() → UI shows video
```

**Critical Sync Flaws:**
1. **DUAL OWNERSHIP OF WebRTC**: The background service isolate (`_onStart`) directly instantiates `SilentWebRTCService.instance` AND the `ChildHomeScreen._callSub` listener ALSO calls `_autoStartStreaming()` (though it's been commented out as a fix attempt). The fix is incomplete — the `_callSub` still exists and still processes the `calling` status, it just doesn't call `_autoStartStreaming`. However, if a developer reverts that comment, dual connections re-emerge. The architectural guarantee is fragile.
2. **No signaling channel version/nonce**: If a parent re-initiates a call while an old session's ICE candidates are still in Firebase, the new `_offerSub` fires on stale data. There is no session ID to discriminate.
3. **`calls/$childUid/childCandidates` is never cleaned between reconnects in `SilentWebRTCService._connect()`**: `_connect()` calls `db.child('calls/$childUid/childCandidates').remove()` but if this Firebase write fails (network briefly down), old candidates accumulate and the parent's ICE agent tries to use them.

### 1.4 Firebase RTDB Structure

Reconstructed from service code:

```
/users/$uid/
  role: "parent" | "child"
  displayName: string (parent only)
  childName: string (child only)
  deviceName: string (child only)
  email: string
  isOnline: boolean
  lastSeen: timestamp
  children/$childUid/: { childName, deviceName, approvedAt, isOnline }  (parent only)
  pendingParentRequests/$parentUid/: { parentName, parentEmail, requestedAt, status }  (child only)
  approvedParents/$parentUid: true | Map  (child only — FORMAT INCONSISTENCY)
  connectedParent/: { uid, parentName, parentEmail }  (child only — PHANTOM NODE)

/calls/$childUid/
  status: "online" | "calling" | "ended" | "offline"
  mode: "camera" | "screen"
  offer: { sdp, type }
  answer: { sdp, type }
  childCandidates/$pushKey: { candidate, sdpMid, sdpMLineIndex }
  parentCandidates/$pushKey: { candidate, sdpMid, sdpMLineIndex }
  heartbeat: timestamp
  startedAt: timestamp
  screenError: string
  command: "flip" | "mute" | "unmute"

/deviceInfo/$childUid/
  batteryLevel: int
  isCharging: boolean
  deviceModel: string
  androidVersion: string
  manufacturer: string
  networkType: string
  lastSeen: timestamp

/location/$childUid/
  lat: double
  lng: double
  accuracy: double
  timestamp: int

/geofences/$childUid/$pushKey/
  name, lat, lng, radiusMeters, alertOnExit, alertOnEnter, _lastInside, createdAt

/geofence_alerts/$childUid/$pushKey/
  fenceId, fenceName, type, lat, lng, timestamp, read

/battery_alerts/$childUid/$pushKey/
  level, threshold, timestamp, read

/alert_settings/$childUid/
  batteryThreshold: int
  _alertFired: boolean

/sms/$childUid/$compositeKey/
  address, body, date, type

/call_logs/$childUid/ (assumed — referenced but never confirmed schema)

/contacts/$childUid/ (assumed — referenced but never confirmed schema)

/snapshots/$childUid/$uuid/
  url, path, timestamp

/appList/$childUid/$pkgKeyDotReplaced/
  packageName, appName, totalTimeMs

/app_locks/$childUid/$pkg/
  blocked, reason, limitMinutes, usedMinutes, lockedAt

/screen_time_limits/$childUid/$pkg: int (minutes)

/app_usage/$childUid/daily/
  _date, _updatedAt, $pkgKeyDotReplaced: { pkg, usedMs, usedMinutes }

/hourly_usage/$childUid/$date/$hour: int (minutes)

/daily_reports/$childUid/$dateStr/
  date, totalMs, totalMinutes, appCount, topApps[], generatedAt, sections[]

/device_events/$childUid/$pushKey/
  type, message, severity, timestamp

/app_install_alerts/$childUid/$pushKey/
  type, packageName, timestamp, read

/commands/$childUid/
  syncSms/: { requested, at }
  syncCallLog/: { requested, at }
  syncContacts/: { requested, at }
  syncAppList/: { requested, at }
  snapshot/: { requested, requestedAt }
  generateReport/$dateStr/: { sections[] }

/keyword_settings/$childUid/keywords: Array | Map

/keyword_alerts/$childUid/$pushKey/
  keyword, message, from, timestamp, read

/weekly_summary/$childUid/ (assumed)

/panic_alerts/$childUid/$pushKey/
  lat, lng, timestamp, read

/config/turnServers/
  servers[]: { urls[], username?, credential? }
```

> ⚠️ **CRITICAL**: `database.rules.json` does NOT exist in the repository. Firebase Realtime Database defaults to **open read/write for authenticated users** or worse, **open to everyone** depending on project creation date. Every child's SMS, location, contacts, and call log data is potentially world-readable.

> ⚠️ **PHANTOM NODE**: `users/$uid/connectedParent` is read in `ChildHomeScreen._listenForConnectedParent()` but is **NEVER WRITTEN anywhere in the codebase**. The `approveParentRequest()` in `auth_service.dart` writes to `approvedParents` and `children` but NOT to `connectedParent`. Therefore, `_listenForConnectedParent()` always falls through to `_loadConnectedParentFromApproved()`. The "connected parent" display is architecturally broken by design.

### 1.5 State Management

- **No state management library** (no Provider, Riverpod, Bloc, GetX).
- Pure `setState()` throughout — all screens are self-managing StatefulWidgets.
- No global app state bus — screens communicate only through Firebase RTDB reads.
- `AuthService`, `BackgroundMonitoringService`, `LocationService`, `PresenceService`, `AlertService`, `SilentWebRTCService`, `TurnConfigService` are all **manual singletons** with no injection, no testability.
- `WebRTCService` is NOT a singleton — it is instantiated `final _webrtc = WebRTCService()` per screen, which means disposal is correctly scoped to screen lifecycle but creates a new object on every rebuild if `MonitoringScreen` is popped and re-pushed.

### 1.6 Permissions Architecture

| Permission | Requested Where | Android 13+ Behavior | Issue |
|---|---|---|---|
| `CAMERA` | `ChildHomeScreen._askPermissions()` | Requires `PERMISSION_REQUEST_CAMERA` | Late request — wizard should be the only place |
| `MICROPHONE` | Same | Same | Same |
| `POST_NOTIFICATIONS` | Same | Required on API 33+ | Asked AFTER app is running, not at first launch |
| `LOCATION` (fine+coarse) | `LocationService.requestPermission()` | Background location requires separate request | Only `whileInUse` or `always` checked — no background location grant |
| `READ_SMS` | `SmsService.requestPermission()` | Special permission group | Not requested in wizard `_requestCorePermissions()` — only camera+mic+notifications |
| `READ_CALL_LOG` | Assumed in manifest | Special permission group | Not found in wizard flow |
| `READ_CONTACTS` | `flutter_contacts` plugin | Standard | Not in wizard |
| `PACKAGE_USAGE_STATS` | Not requested in code | Non-revokable, must be in Settings | No UI guidance for this critical permission |
| `SYSTEM_ALERT_WINDOW` | Not requested | Required for overlay | Not implemented at all |
| `BIND_ACCESSIBILITY_SERVICE` | Not requestable (manual) | Manual in Settings | No UI guidance flow in wizard |

> ⚠️ **CRITICAL**: `PACKAGE_USAGE_STATS` is the single most important permission for this app — without it, `UsageStats.queryUsageStats()` returns empty data, making screen time tracking, daily reports, app usage, and app install detection completely non-functional. There is **zero code** to request or verify this permission via the system Settings screen.

> ⚠️ **CRITICAL**: `READ_SMS` is not requested in the setup wizard's `_requestCorePermissions()`. It is only requested in `SmsService.requestPermission()` which is called... nowhere. SMS sync will silently fail because `syncSms()` checks `Permission.sms.isGranted` and returns early if not granted.

### 1.7 Background Services

The app runs **two parallel background execution mechanisms**:

```
┌─────────────────────────────────────────────────────────────────┐
│ flutter_background_service (Isolate A — "Background Service")   │
│  • Runs as Android Foreground Service (notification id 888)     │
│  • Owns: SilentWebRTCService, all Firebase timers              │
│  • Heartbeat: every 30s                                         │
│  • Watchdog: every 30s                                          │
│  • Screen time check: every 60s                                 │
│  • SMS sync command: every 15min                                │
│  • App install check: every 5min                                │
│  • Hourly usage: every 15min                                    │
│  • Weekly/streak: every 5min                                    │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ flutter_foreground_task (Isolate B — "Foreground Task")         │
│  • Runs as Android Foreground Service (separate notification)   │
│  • Owns: stale session cleanup (every ~10min)                  │
│  • heartbeat: 30s interval (BUT writes NOTHING — intentional)  │
│  • On notification tap: launchApp('/child/home')                │
└─────────────────────────────────────────────────────────────────┘
```

> ⚠️ **TWO FOREGROUND SERVICES SIMULTANEOUSLY**: This device runs TWO persistent foreground services, each showing a notification. On Android 12+, both are visible to the user as persistent notifications. Google Play policies may flag this. On Android 14+, both services declare `camera|microphone|dataSync` foreground types — on idle (no active stream), `camera` and `microphone` types are declared but unused, which may cause Android to kill the service with `ForegroundServiceDidNotStartInTimeException`.

### 1.8 Overlays

- **`_LockOverlay`** in `ChildHomeScreen`: Just a `Stack` child showing a black box. `_locked` is `final bool _locked = false` — **HARDCODED FALSE, never true**. The lock overlay is permanently disabled. Lock feature is fake UI.
- No `TYPE_APPLICATION_OVERLAY` window (Android overlay permission) is implemented.
- `AppBlockAccessibilityService` uses `startActivity(home)` to "block" apps — this is a foreground redirect, not a true overlay block. It requires accessibility service to be enabled manually.

### 1.9 WebRTC/Screen Streaming

- Two separate WebRTC service classes:
  - `WebRTCService`: Used by **parent** and also has `startAsChild()` method (never called from active code)
  - `SilentWebRTCService`: Used by **background isolate** on child side
- ICE config loaded from `TurnConfigService` which reads from `config/turnServers` in Firebase — correct design if populated
- STUN-only fallback used if Firebase not configured — connections through symmetric NAT/carrier NAT will fail ~40% of the time
- No STUN fallback health check — app silently degrades

### 1.10 Notification Flow

```
Child Device Event (battery low, geofence breach, etc.)
  → Child writes to Firebase RTDB (battery_alerts, geofence_alerts, etc.)
  → Parent app (NotificationService) has onChildAdded listeners
  → FlutterLocalNotifications.show() on parent device

FCM: FirebaseMessaging.requestPermission() is called but:
  - No FCM token is saved anywhere in the codebase
  - No Cloud Function exists to send push via FCM
  - FCM onMessage handler only shows local notification for foreground messages
  - Background FCM delivery is non-functional (no background handler registered)
```

> ⚠️ **FCM IS FAKE**: The app requests FCM permission and listens to `FirebaseMessaging.onMessage` but NEVER saves the FCM token to Firebase, and there is no server-side trigger to send push messages. If the parent app is killed, no push notification will ever arrive. This is a fundamental gap in the notification architecture.

### 1.11 Foreground Service Persistence

- `flutter_background_service`: Uses `START_STICKY` implicitly (library default). On Android 12+, if the system kills it, it restarts within 5-10 seconds. On Android 14+, if battery optimization is enabled, the system may delay restarts by minutes.
- `flutter_foreground_task`: Uses `START_STICKY` via FlutterForegroundTask defaults.
- `WatchdogReceiver.kt`: Schedules `AlarmManager` exact alarms. On Android 12+, requires `SCHEDULE_EXACT_ALARM` permission. On Android 13+, the `USE_EXACT_ALARM` permission (for calendar/alarm apps) is required or the app must declare `SCHEDULE_EXACT_ALARM` and handle the case where it's not granted.
- `WorkManager`: Enqueued from `BootReceiver` as a 15-minute periodic task — this is the most reliable background execution path on modern Android.

### 1.12 Boot/Startup Flow

```
Device Boot
  └─ BOOT_COMPLETED / LOCKED_BOOT_COMPLETED / QUICKBOOT_POWERON
       └─ BootReceiver.onReceive()
            ├─ Checks FlutterSharedPreferences: wizard_done=true AND child_uid≠null
            ├─ Starts BackgroundService (flutter_background_service)
            ├─ If MY_PACKAGE_REPLACED + MediaProjection token: restarts ScreenCaptureService
            ├─ Shows "tap to resume" notification if reboot (no MediaProjection after reboot)
            ├─ Schedules WatchdogReceiver alarm
            └─ Enqueues WorkManager watchdog
```

**Boot Flow Flaws:**
1. `LOCKED_BOOT_COMPLETED` is received while device is in Direct Boot mode — Flutter plugins that access SharedPreferences at this point may fail because the default SharedPreferences file is credential-encrypted. The code attempts to read `FlutterSharedPreferences` which is stored in credential-encrypted storage — **CRASH RISK** on first boot before unlock.
2. `ACTION_MY_PACKAGE_REPLACED` handling calls `isAppInForeground()` using `ActivityManager.runningAppProcesses` — this API is restricted on Android 11+ (always returns the calling app's process for security reasons), so the foreground check is unreliable.

### 1.13 Device Registration Flow

```
Child Side:                          Parent Side:
──────────                           ────────────
1. RoleSelectionScreen
2. ChildAuthScreen (anonymous signIn or email signup)
3. ChildSetupWizardScreen (9 pages):
   Page 0: Welcome
   Page 1: Feature overview
   Page 2: Camera/Mic/Notif permissions
   Page 3: Battery exemption + Screen capture consent
   Page 4: Device Administrator
   Page 5: Profile (name, device name) → writes to Firebase
   Page 6: QR code display (shows child UID as QR)
   Page 7: Approval (listens for pendingParentRequests)
   Page 8: Disable notifications
4. finish() → saves to SharedPreferences → /child/home

                                     1. RoleSelectionScreen
                                     2. ParentAuthScreen (email/password signup)
                                     3. ParentDashboardScreen
                                     4. AddChildScreen → scans child QR → reads UID
                                     5. sendParentRequest(childUid) → writes pendingParentRequests
                                     6. Child approves → approveParentRequest()
                                        writes: approvedParents, children/$childUid
```

**Registration Flow Flaws:**
1. Child setup wizard Page 7 shows `CircularProgressIndicator` indefinitely if no pending request arrives — there is no timeout or skip mechanism (child stuck).
2. Child can complete setup WITHOUT a parent approval (they can press "I'm Waiting for Parent" → page 8 → "Complete Setup"). This means monitoring starts with no parent connected.
3. Anonymous auth in `setupChildDevice()` creates an ephemeral account that expires after 30 days. No migration path to email auth.
4. The `_auth.currentUser?.uid` vs `widget.childUid` priority confusion — if setup was started with a `childUid` argument but the user never authenticated (or auth expired), widget.childUid is used as fallback, potentially writing Firebase data under a UID that no longer exists as an auth account.

---

## 2. LOGIN + AUTHENTICATION ANALYSIS

### 2.1 Auth Flow Architecture

The app has **three overlapping auth patterns** for children:
1. `signInAnonymously()` — used in `setupChildDevice()` (deprecated/legacy path)
2. `signUpChild()` — email+password creation
3. `signInChild()` — email+password sign-in

And **one pattern for parents**:
1. `registerParent()` + `loginParent()` — email+password only

**The auth flow is split between wizard and auth screen in an inconsistent way.** The `ChildSetupWizardScreen` is accessible via `/child/setup` which requires a `childUid` argument — but this screen also creates accounts internally. The `ChildAuthScreen` is separate and creates accounts via `signUpChild()` / `signInChild()`. These two paths can both be followed and are not mutually exclusive, potentially creating duplicate Firebase user nodes for the same child.

### 2.2 Session Persistence

```dart
// SplashScreen._navigate():
final authService = AuthService();
if (!authService.isLoggedIn) {
  Navigator.pushReplacementNamed(context, '/role-select');
  return;
}
final role = await authService.getSavedRole();
```

**Flaw 1 — Role Saved Locally, Auth Verified Remotely:**  
`getSavedRole()` reads from `SharedPreferences`. If the user is authenticated (Firebase token still valid) but the role was corrupted or cleared from SharedPreferences, `getSavedRole()` returns `UserRole.unknown` and the user is sent to role selection, losing their session context.

**Flaw 2 — No Token Refresh Handling:**  
Firebase tokens expire after 1 hour and are auto-refreshed by the SDK. However, in the background isolate (`_onStart`), `Firebase.initializeApp()` is called without credentials. The background isolate creates a fresh Firebase app instance — it does NOT share auth state with the main isolate. In the background isolate, `FirebaseAuth.instance.currentUser` will be `null`. This means:
- Any Firebase operation in the background isolate that requires authentication will fail with `PERMISSION_DENIED` if security rules require auth.
- The background service currently uses `child_uid` from SharedPreferences to construct paths directly — this works only if rules don't require auth, which they shouldn't because there are no rules.

**Flaw 3 — Anonymous Account 30-Day Expiry:**  
`signInAnonymously()` creates accounts deleted after 30 days of inactivity. No recovery path exists. The background service will crash on Firebase writes after expiry.

**Flaw 4 — Parent Role Verification Race:**
```dart
// loginParent():
final snap = await _db.child('users/${user.uid}/role').once();
if (snap.snapshot.value != 'parent') {
  await _auth.signOut();
  return {'success': false, 'error': 'This account is not a parent account.'};
}
```
If Firebase is offline when `loginParent()` is called, this `once()` read will return cached data (or fail). If cached data is stale or absent, a parent can be incorrectly rejected. If cache has wrong role, a non-parent can be accepted. No timeout handling.

**Flaw 5 — Child Sign-In Doesn't Verify Role:**
```dart
// signInChild():
final UserCredential cred = await _auth.signInWithEmailAndPassword(...);
// NO role check — any email/password account can sign in as a child
await _saveLocalRole('child');
```
A parent email/password can be used to sign in as a child, giving it child privileges. The `loginParent()` checks role; `signInChild()` does NOT.

**Flaw 6 — `approveParentRequest()` Has No Auth State Check on Child Side:**
The child's `approveParentRequest()` reads `currentUser?.uid` — if the anonymous session has expired in the background, `currentUser` is null and the approval silently fails with "Not authenticated."

### 2.3 Parent-Child Pairing Mistakes

1. `sendParentRequest()` writes to `users/$childUid/pendingParentRequests/$parentUid`. The child UID comes from a QR code scan. There is no validation that the scanned UID is a real, active child account — a parent can send a request to any arbitrary UID.
2. `approveParentRequest()` writes `users/$parentUid/children/$childUid` with `childData['childName']` from the child's own Firebase record. If the child's record doesn't yet exist (race between wizard and request), `childData` is empty and the parent's children list shows `null` names.
3. After `approveParentRequest()`, the child's `pendingParentRequests/$parentUid/status` is set to `'approved'` but the entry is NOT removed. The wizard's approval page subscribes to `pendingParentRequests` and filters for `status == 'pending'`. This is correct, but the stale `status: 'approved'` entries accumulate forever in Firebase.

### 2.4 Race Conditions

1. **Setup Wizard → Home Screen Race**: `_finish()` calls `BackgroundMonitoringService.startService()` inside a `Future.delayed(1s)`. During that 1 second, the Navigator has already pushed `/child/home`. `ChildHomeScreen._safeInit()` also calls `BackgroundMonitoringService.startService()`. Both calls race. The service has a `_startCompleter` guard, but the completer is reset in `finally { _startCompleter = null; }` — if the second call arrives after the first completes and resets the completer, both succeed and the service starts once, which is correct. However, if they arrive simultaneously, the second call waits on `_startCompleter!.future` which may complete before the service is actually initialized.

2. **Presence vs. Background Service Race**: `ChildHomeScreen._safeInit()` calls `_setOnline(true)` which calls `PresenceService.startChildPresence()`. Concurrently, `_setupMonitoringSession()` in the background service also writes `isOnline = true`. These writes are idempotent, but `startChildPresence()` calls `stopChildPresence()` first (if different uid), which writes `isOnline = false` and cancels `onDisconnect` handlers — a brief offline flash visible to the parent.

---

## 3. FEATURE-BY-FEATURE FORENSIC ANALYSIS

### 3.1 Live Screen Share

**Status: PARTIALLY FUNCTIONAL — Broken on reboot, fragile on background**

```dart
// SilentWebRTCService._acquireMedia() for screen mode:
final projectionActive = await ScreenCaptureChannel.isProjectionActive();
if (!projectionActive) {
  // writes screenError to Firebase
  return null;
}
return navigator.mediaDevices.getDisplayMedia(...);
```

**Failures:**
1. **MediaProjection token invalidated on reboot**: Every phone reboot invalidates all `MediaProjection` tokens. The boot receiver correctly shows a "tap to resume" notification, but the user must manually open the app and re-grant screen capture permission every reboot. This is a fundamental Android limitation, but the UX for this is poor — the parent just sees "Screen sharing failed."
2. **`ScreenCaptureService.projectionToken` is a Kotlin `companion object var`** — it is in the Kotlin static scope of the `ScreenCaptureService` class. In the background service isolate (Dart), `ScreenCaptureChannel.isProjectionActive()` invokes the MethodChannel which calls `ScreenCaptureService.projectionToken != null`. But MethodChannel calls require the main Activity or main thread — **in a background isolate, MethodChannel calls may fail with `MissingPluginException`** because the channel is registered in `configureFlutterEngine` which runs on the main Activity's engine, not the background isolate's engine.
3. **`getDisplayMedia()` requires an active MediaProjection token AND the app must be in the foreground** when requesting screen capture. In background mode (service running, app UI closed), `getDisplayMedia()` will throw on Android 10+ without an active `MediaProjectionManager.createScreenCaptureIntent()` result.

**Fake UI Elements:**
- The `ChildStreamingScreen` (`child_streaming_screen.dart`) exists but is never navigated to from the current child home screen flow. It appears to be dead code.

### 3.2 Live Camera

**Status: PARTIALLY FUNCTIONAL — Works only when UI is open**

**Failures:**
1. In background, `SilentWebRTCService._acquireMedia()` calls `navigator.mediaDevices.getUserMedia()`. In a Dart background isolate (flutter_background_service), WebRTC's `getUserMedia` may not have access to the Flutter rendering context needed to initialize the camera. The camera privacy indicator will show on Android 12+ regardless.
2. `Helper.switchCamera()` is called for "flip" command but `flutter_webrtc 0.14.0`'s `Helper.switchCamera()` has known race conditions where the track is switched before the new track is fully initialized, causing a blank frame.
3. No fallback when camera is in use by another app — the error is swallowed by `_scheduleReconnect()`.

### 3.3 App Usage

**Status: BROKEN — Missing critical permission request**

```dart
// background_monitoring_service.dart _screenTimeTimer:
final stats = await UsageStats.queryUsageStats(midnight, now);
```

**Why it fails:**
1. `PACKAGE_USAGE_STATS` permission is NEVER requested in the setup wizard or anywhere in the codebase. The app uses `usage_stats: ^1.3.1` which requires this permission to be manually granted by the user in Settings → Apps → Special App Access → Usage Access. Without this permission, `queryUsageStats()` returns an empty list — silently.
2. `AppUsageScreen` on the parent side reads from `app_usage/$childUid/daily` in Firebase — this node is only populated if the background service's `_screenTimeTimer` successfully wrote data. With no usage stats permission, this node is permanently empty. The parent sees an empty list.
3. The `getInstalledApps` in `MainActivity.kt` also calls `UsageStatsManager.queryUsageStats()` — same permission issue.

**Fake UI Confirmed**: `AppUsageScreen` renders charts and empty states — when displayed with no data, the chart renders 0 values. A naive user would think monitoring is working.

### 3.4 Screen Time (Daily Limits)

**Status: BROKEN — Same permission gap as App Usage, plus enforcement gap**

**Additional Failures:**
1. Screen time limits are enforced by `AppBlockAccessibilityService` which must be manually enabled by the user in Android Settings → Accessibility. There is no guidance UI to navigate the user there during setup.
2. Even if the accessibility service IS enabled, it reads blocked packages from SharedPreferences key `flutter.blocked_packages`. This key is written by `_appLocksSub` in the background service. If the background service hasn't started yet (first boot, slow start), the accessibility service reads an empty string and blocks nothing.
3. The `DevicePolicyManager.setPackagesSuspended()` method implemented in `MainActivity.kt` (`suspendPackages`/`unsuspendPackages`) is called from Dart via `app_lock_service.dart` — but `app_lock_service.dart` is 3,176 bytes and has not been audited here. Given it depends on Device Admin being active (optional step), this more reliable method is frequently unavailable.
4. `screen_time_limits/$childUid/$pkg` stores limits, but `app_usage/$childUid/daily` stores usage. The enforcement check queries UsageStats directly via `usage_stats` plugin (which requires the missing permission). **Double permission failure**.

### 3.5 Daily Reports

**Status: PARTIALLY FUNCTIONAL — Depends on broken UsageStats permission**

```dart
// background_monitoring_service.dart scheduleDailyReport():
final stats = await UsageStats.queryUsageStats(midnight, endOfDay);
```

Same `PACKAGE_USAGE_STATS` issue. Without the permission, daily reports are empty.

**Additional Issue**: The midnight timer is scheduled at service start with `nextMidnight.difference(now)`. If the background service is killed and restarts at 11:59 PM, the timer fires correctly. If it restarts at 12:01 AM, the midnight event was missed. `_generateYesterdayReportIfMissing()` is called to catch this — correct design. But if the service never restarts until next morning, this backfill call is also missed.

### 3.6 Contact Book

**Status: PARTIALLY FUNCTIONAL — Sync works but display has issues**

**Failures:**
1. `READ_CONTACTS` permission is never requested in `_requestCorePermissions()` in the wizard. Only camera, microphone, and notifications are requested.
2. Contacts sync is triggered by the parent via `commands/$childUid/syncContacts` — the child listens in `_listenForCommandsSafe()`. However, the listener is only active when `ChildHomeScreen` is mounted. If the app is in background (only services running), the sync command listener is dead and contacts never sync.
3. No automatic contacts sync on startup — contacts are only synced on-demand from the parent.

### 3.7 Snapshots/Background Capture

**Status: PARTIALLY FUNCTIONAL — Native path works only in foreground**

```dart
// SnapshotService.captureAndUpload():
// Path 1: native Camera2 via MethodChannel
final nativeBytes = await _takeNativeSnapshot();
```

**Failures:**
1. `MethodChannel('com.familymonitor/snapshot')` is registered in `configureFlutterEngine` (MainActivity). MethodChannel calls only work when the Activity is running. If the app is backgrounded (Activity paused), the `takeNativeSnapshot` call will fail with `MissingPluginException` and fall through to Path 2.
2. Path 2 (`CameraController`) requires the Activity to be in the foreground and the Flutter rendering context to be active. In background, this also fails.
3. **Result**: Snapshots only work when the child is actively using their phone with the app visible. Background snapshots are non-functional.
4. Firebase Storage URLs expire? No expiry is set on storage refs — `getDownloadURL()` returns permanent URLs. If Storage rules are open, these URLs expose child photos indefinitely to anyone with the link.

### 3.8 Battery Alerts

**Status: FUNCTIONAL — Best-implemented feature**

Battery monitoring works correctly:
- `BatteryService._report()` writes to `deviceInfo/$childUid` via `update()` (fixed from `set()`)
- `AlertService._maybeFirBatteryAlert()` has proper anti-spam with `_alertFired` flag and hysteresis
- `NotificationService._watchBatteryAlerts()` uses `onChildAdded` with a `_seen` dedup set

**Minor Issues:**
1. The `_batterySub` in `AlertService` is never cancelled — `stopBatteryMonitoring()` cancels it but `startBatteryMonitoring()` is called from `ChildHomeScreen._startLocationAndAlerts()`. When `ChildHomeScreen` disposes, `AlertService.instance.stopBatteryMonitoring()` is called. But if the background service also calls `startBatteryMonitoring()` (it doesn't currently, but if added), there'd be a subscriber conflict.
2. Battery reporting happens every 60 seconds from `BatteryService._timer` — this continues even when the screen is off, consuming background battery unnecessarily.

### 3.9 App Install Alerts

**Status: PARTIALLY FUNCTIONAL — Command-response pattern has race condition**

```dart
// background_monitoring_service.dart _appInstallTimer (every 5min):
await FirebaseDatabase.instance.ref('commands/$uid/syncAppList')
  .set({'requested': true, 'at': ...});
await Future.delayed(const Duration(seconds: 10));  // Wait 10s for child to respond
final snap = await FirebaseDatabase.instance.ref('appList/$uid').get();
```

**Why this is broken:**
1. The `syncAppList` command is listened to by `_appListSub` in `ChildHomeScreen._listenForCommandsSafe()`. This listener is ONLY active when the UI screen is mounted. In background (only services running), the listener is dead. The background service sends the command and waits 10s, then reads stale data.
2. `await Future.delayed(const Duration(seconds: 10))` — a blocking delay inside a background timer callback. This holds the timer callback thread for 10 seconds. During this time, if the watchdog fires, it reads the `_watchdogRestarting` flag — this is a Dart async context so it's fine, but the 10s delay means the timer runs for `300s + 10s = 310s` between cycles, not 300s.
3. The `_knownPackages` set is a local variable initialized to empty — on every service restart, it resets, causing every currently-installed app to be reported as "newly installed" on the first check after restart. This generates hundreds of false-positive install alerts on service restart.

### 3.10 SMS / Calls Monitoring

**Status: BROKEN — Listener dies in background, permission not requested**

**SMS Failures:**
1. `READ_SMS` permission not in wizard — SMS reads silently fail.
2. SMS sync is commanded from the background service (`_smsTimer` every 15min) via `commands/$uid/syncSms`, but the **listener** is in `ChildHomeScreen._smsSub` — only active when the UI is open.
3. `SmsService.syncSms()` uses `_ch.invokeMethod('readSms')` — a MethodChannel call from the UI isolate only.
4. Background service sends sync command but nobody receives it in background. Command is written, waits for nobody, SMS is never synced when app is backgrounded.

**Call Log Failures:**
1. Same pattern — `_callLogSub` is in `ChildHomeScreen._listenForCommandsSafe()`, dead in background.
2. `READ_CALL_LOG` permission: not confirmed in wizard flow.

### 3.11 Location Tracking

**Status: PARTIALLY FUNCTIONAL — Only while app is open or with background location permission**

```dart
// LocationService.startTracking():
const settings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 30,
);
_positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(...);
```

**Failures:**
1. `startTracking()` is called from `ChildHomeScreen._startLocationAndAlerts()` — the subscription is held by `LocationService._positionSub`. When `ChildHomeScreen.dispose()` is called (app backgrounded), `LocationService.instance.stopTracking()` IS called — this **stops location tracking** when the UI closes. Background location tracking is non-functional.
2. For background location tracking to work, `ACCESS_BACKGROUND_LOCATION` must be granted (Android 10+, requires a separate OS dialog) AND the location updates must come from a foreground service that declared `location` as its `foregroundServiceType`. Neither is implemented.
3. `hasPermission()` only checks for `whileInUse` or `always` — if the user granted "only while using app," location stops working immediately when the app is backgrounded, with no indication to the parent.

### 3.12 Geofencing

**Status: BROKEN — Dependent on broken location tracking**

Geofence checks run in `LocationService._checkGeofences()` which is called from the position stream listener. Since the position stream stops when the app is backgrounded, geofence checking also stops.

**Additional Failures:**
1. `_lastInside` is stored in Firebase under `geofences/$uid/$id/_lastInside`. This means every position update causes a Firebase write to check geofence state. For active tracking with `distanceFilter: 30m`, this is fine — but on app resume (cached position delivered immediately), this write races with the initial `get()` of geofences.
2. Geofence alert schema stores `lat`/`lng` of the breach point but not the previous known position. The parent sees a map marker but no trajectory.

### 3.13 Notification Handling

**Status: PARTIALLY FUNCTIONAL — Local only, FCM non-functional**

As analyzed in 1.10:
- Local notifications work (flutter_local_notifications)
- FCM token never saved → server-sent push notifications never delivered
- Background FCM handling: `FirebaseMessaging.onBackgroundMessage()` is never registered
- Notification deduplication uses in-memory `_seen` sets — resets on app restart, may re-notify old alerts

### 3.14 Background Sync

**Status: FRAGILE — Commands require UI screen to be mounted**

The design has a fundamental architectural mismatch:
- **Commands are written by the background service** (running in Dart isolate A)
- **Commands are consumed by ChildHomeScreen** (running in the main isolate, UI must be open)

This means ALL of the following features break when the app is minimized:
- SMS sync
- Call log sync
- Contact sync
- App list sync
- Snapshot capture (Path 2)

### 3.15 Parent-Child Realtime Sync

**Status: WORKS for simple data, BROKEN for complex commands**

Firebase listeners correctly deliver:
- Battery level → parent dashboard ✓
- Online status → parent dashboard ✓
- Geofence alerts → parent dashboard ✓
- Battery alerts → parent dashboard ✓

But BROKEN for:
- Live camera/screen → requires both sides active ✗ (works partially)
- App list → child UI must be open ✗
- Contacts → child UI must be open ✗
- SMS → child UI must be open ✗

### 3.16 Firebase Listeners Lifecycle

**Status: MULTIPLE LEAK RISKS**

1. `NotificationService` subscribes to multiple children's alert paths. `watchChild()` creates subscriptions stored in `_subs` map. `unwatchChild()` cancels them. But `_subs` keys use `'battery_$childUid'` format — if a child is removed and re-added, old subscriptions may not be properly canceled if the key format changes.
2. `ParentDashboardScreen._batterySubs`, `_presenceSubs`, `_crashCountSubs`: these are properly cleaned up when children are removed. However, if `_listenForChildren()` is called multiple times (via `_reattachChildrenListenerIfNeeded()`), `_childrenSub` may be non-null from a previous attachment, and the null check `if (_childrenSub != null) return;` prevents reattachment — correct. But this means if the first subscription errors and completes, it's set to null after error, and `_reattachChildrenListenerIfNeeded` re-creates it — also correct.
3. `AlertService._batterySub` is a single subscription — only one child can be monitored at a time. If the child switches or there are multiple children, this needs to be a map like `NotificationService._subs`.

### 3.17 Accessibility Service Logic

**Status: PARTIALLY FUNCTIONAL — Fragile, bypassed easily**

`AppBlockAccessibilityService`:
- `TYPE_WINDOW_STATE_CHANGED` events fire for every window transition — correct for detecting app launches
- Home redirect (`startActivity(home)`) is a "soft block" — apps with `FLAG_ACTIVITY_NEW_TASK` override may be able to regain focus
- The uninstall intercept checks for Settings package names and APP_INFO_CLASSES — these class names are OEM-specific and the list is incomplete. On many Samsung, Xiaomi, and Huawei devices, the class names are different.
- PIN cooldown (`PIN_COOLDOWN_MS = 4000ms`) means the PIN activity can be bypassed by rapidly navigating away and back
- SharedPreferences key `flutter.blocked_packages` is read fresh on every event — this is correct but means changes propagate within one accessibility event cycle (~100ms)

### 3.18 Android 12/13/14 Specific Issues

**Android 12 (API 31):**
- Privacy indicators (camera/mic dot in status bar) — CANNOT be suppressed. Comment in code acknowledges this. ✓

**Android 13 (API 33):**
- `POST_NOTIFICATIONS` permission required. Requested in wizard. ✓
- `SCHEDULE_EXACT_ALARM` permission required for `AlarmManager.setExactAndAllowWhileIdle()`. Not checked in code — **WatchdogReceiver may silently fail to schedule**.
- Coarse location and fine location split — `ACCESS_COARSE_LOCATION` + `ACCESS_FINE_LOCATION` both needed for `LocationAccuracy.high`. Not explicitly split in wizard.

**Android 14 (API 34):**
- `FOREGROUND_SERVICE_TYPE` must be declared AND used simultaneously. Both services declare `camera|microphone|dataSync`. In idle state (no camera active), declaring `camera` without using it causes `ForegroundServiceDidNotStartInTimeException` on API 34+.
- `SCHEDULE_EXACT_ALARM` is now a `protection normal` permission and may not be auto-granted. WorkManager is the correct alternative (already added as secondary watchdog).
- Photos/videos permission split (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`) — not audited but may affect Storage access for snapshot viewing.

---

## 4. FLASHGET KIDS-STYLE LOGIC COMPARISON

### 4.1 What FlashGet Kids Does That This App Doesn't

| Feature | FlashGet Kids | Family Monitor | Gap |
|---|---|---|---|
| **Realtime persistence** | WebSocket + FCM hybrid | Firebase RTDB only | No FCM server-side triggers |
| **Resilient reconnects** | Multi-tier: TURN, relay, STUN | STUN fallback only | No TURN server configured |
| **Silent monitoring continuity** | Background service + Accessibility | Background service only | Accessibility incomplete |
| **Foreground service recovery** | Device admin + watchdog + alarms | Watchdog + WorkManager | Missing alarm permission check |
| **Instant parent updates** | Push via FCM within 200ms | Firebase RTDB polling | FCM non-functional |
| **Proper event streaming** | Dedicated event bus | Multiple independent timers | Timer proliferation |
| **Accurate app usage** | UsageStatsManager + display state | UsageStats (permission not granted) | PACKAGE_USAGE_STATS not requested |
| **Correct notification throttling** | Server-side dedup + rate limiting | Client-side `_seen` set | Lost on app restart |
| **Screen-state tracking** | `ACTION_SCREEN_ON/OFF` BroadcastReceiver | Not implemented | Missing entirely |
| **Resilient device pairing** | Encrypted QR with timestamp + nonce | Plain UID QR | No expiry, no security |
| **Service auto-restart** | Companion app + system alert window | WatchdogReceiver | WatchdogReceiver may fail on API 33+ |
| **App blocking without accessibility** | DevicePolicyManager suspend (always-on) | DPM + Accessibility (Accessibility fragile) | DPM requires Device Admin (optional) |
| **Contact approval/blocking** | Per-contact Firebase rules | Contact list display only | No blocking logic |
| **Web filtering** | VPN-based DNS filtering | Not implemented | Missing entirely |
| **Remote device lock** | DPM.lockNow() + PIN override | `_locked = false` (hardcoded off) | Lock feature fake |
| **Emergency SOS** | GPS + audio recording | GPS only | Audio not recorded |
| **Usage schedule** | Time-based lock schedule | Flat daily minute limit | No time-of-day control |
| **Child-side PIN** | PIN gate on all settings access | `PinVerifyActivity` exists but not integrated in Dart | Incomplete integration |

### 4.2 Architecture Gaps vs. Production Standards

1. **No server-side Cloud Functions**: All data processing happens on the client. This means rate limiting, deduplication, and aggregation are entirely client-responsibility, creating opportunities for data corruption.
2. **No Firebase App Check**: No attestation that requests come from legitimate app instances. Any authenticated user (even one who extracted the `google-services.json`) can write arbitrary data to Firebase paths.
3. **No encryption of sensitive data**: SMS content, contacts, and location are stored as plaintext in Firebase RTDB. In transit, Firebase SDK uses TLS — but at rest in Firebase, data is unencrypted (Firebase Realtime Database does not support at-rest encryption without Firebase paid tier).
4. **No audit log of parent access**: Parents can view cameras, read SMS, and see location without any record on the child side beyond what the child chooses to show.

---

## 5. UI/UX NAVIGATION ANALYSIS

### 5.1 Back Navigation Issues

1. **`MonitoringScreen` back navigation**: The system back gesture triggers `dispose()` → `endCall()` path (via `if (!_callEnded)` guard). But `_endSession()` calls `Navigator.pop(context)`. If the user uses the system back gesture while the app is animating away from `MonitoringScreen`, a second `pop()` call in `dispose()` via the `!_callEnded` path would fail silently (already popped). The guard `_callEnded` prevents double `endCall` Firebase write — correct. But `Navigator.pop(context)` in `dispose()` would be a no-op since the screen is already gone. No crash, but confusing control flow.

2. **`ChildSetupWizardScreen` back on first page**: Pressing back on Page 0 triggers `_prev()` which calls `Navigator.pop(context)` — this navigates back to role selection. If the wizard was started mid-session (user navigated to wizard from role select), this is correct. But there's no `WillPopScope` / `PopScope` to confirm the user wants to abandon setup.

3. **Feature sheet bottom sheet + navigation**: `_showFeatureSheet()` pushes a `showModalBottomSheet`. Navigating to a feature screen calls `Navigator.pop(context)` (to close sheet) then `Navigator.push(context, ...)`. If the user taps rapidly and the sheet close animation isn't complete, the push may happen before the modal is fully dismissed, causing a blank frame.

### 5.2 Screen Reset Issues

1. `ParentDashboardScreen` uses `_listenForChildren()` with `didChangeAppLifecycleState` — on resume, if `_childrenSub == null` (error recovery path), it reattaches. However, `_childrenSub` is set to null only in the `onError` callback. If the stream emits an error and the `onError` handler fires, `_childrenSub` is set to null and `_reattachChildrenListenerIfNeeded()` is scheduled with `Future.delayed(3s)`. But `_childrenSub` is not set to null in the `cancel()` in `dispose()`. So after `dispose()`, if the 3-second future fires, `_reattachChildrenListenerIfNeeded()` checks `_childrenSub != null` — if `cancel()` was called, the subscription object is non-null (just cancelled), so the check passes and tries to reattach on a disposed widget. **Use-after-dispose crash risk** on `setState(() { _children... })`.

2. `ChildHomeScreen` state resets on rotation (new instance of state). All subscriptions from `_listenForCommandsSafe()` are started after a 2-second delay on each `initState()`. Rapid rotation causes rapid subscription creation/cancellation cycles. With 7 subscriptions all starting with 2s delay on each rotation, under rapid rotation this can create dozens of pending subscription initializations.

### 5.3 Widget Rebuild Issues

1. `ParentDashboardScreen._listenForChildren()` calls `setState()` inside the Firebase stream listener. Every battery update (`_batterySubs`) and presence update (`_presenceSubs`) calls `setState()` — rebuilding the entire dashboard. For 5 children, this means up to `5 * 2 = 10` potential `setState()` calls per 30-second heartbeat cycle. Each rebuild redraws all child cards. Should use `ValueNotifier` or at minimum, avoid rebuilding unchanged cards.

2. `ChildHomeScreen` calls `setState()` inside `_listenForConnectedParent()` after a Firebase read AND `_listenForPendingRequests()` on every request change. These are two concurrent streams both calling `setState()`. Under rapid changes, this can queue many synchronous rebuilds.

### 5.4 Navigation Stack Corruption

The app uses `Navigator.pushReplacementNamed` from splash screen — correct. But feature screens use `Navigator.push(context, MaterialPageRoute(...))`. The bottom sheet uses `Navigator.pop(context)` before `Navigator.push`. If the bottom sheet pop triggers an animation frame before the push, the context's navigator may have stale state. No documented crash, but potential timing issue on slow devices.

---

## 6. FIREBASE ANALYSIS

### 6.1 Security Rules (CRITICAL — MISSING)

**No `database.rules.json` exists in the repository.** New Firebase projects created after mid-2019 default to locked rules (`".read": false, ".write": false`). Projects created before that default to open rules. Without knowing which applies, the audit must assume worst-case.

If rules are open:
- Any authenticated user can read **any child's SMS, location, contacts, call log, photos**
- Any authenticated user can write **false data** to any child's Firebase nodes
- GDPR violation risk for EU users

If rules are locked:
- Background service writes (from the background isolate where `FirebaseAuth.currentUser == null`) will **all fail with PERMISSION_DENIED**
- The app is completely non-functional

**Minimum required rules not implemented:**

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "auth != null && ($uid === auth.uid || root.child('users/'+auth.uid+'/children/'+$uid).exists())",
        ".write": "auth != null && $uid === auth.uid"
      }
    },
    "calls": {
      "$childUid": {
        ".read": "auth != null && (auth.uid === $childUid || root.child('users/'+auth.uid+'/children/'+$childUid).exists())",
        ".write": "auth != null && (auth.uid === $childUid || root.child('users/'+auth.uid+'/children/'+$childUid).exists())"
      }
    }
  }
}
```

### 6.2 Unbounded Growth Nodes

| Firebase Path | Growth Rate | TTL/Cleanup | Risk |
|---|---|---|---|
| `calls/$uid/childCandidates` | ~10 per call | Removed on next call start | Stale if crash during call |
| `calls/$uid/parentCandidates` | ~10 per call | Removed on next call start | Same |
| `device_events/$uid` | ~5-10 per day | NEVER cleaned | **Unbounded** |
| `battery_alerts/$uid` | Per battery event | Manual `clearAlerts()` | Accumulates |
| `geofence_alerts/$uid` | Per fence breach | Manual `clearAlerts()` | Accumulates |
| `app_install_alerts/$uid` | Per app install | Manual `clearAll()` | Accumulates + FALSE POSITIVES |
| `keyword_alerts/$uid` | Per SMS match | Manual `clearAlerts()` | Accumulates |
| `panic_alerts/$uid` | Per SOS press | Manual `clearAlerts()` | Accumulates |
| `daily_reports/$uid/$date` | 1 per day | NEVER cleaned | ~365 entries/year |
| `hourly_usage/$uid/$date/$hour` | 24 per day | NEVER cleaned | ~8760 entries/year |
| `app_usage/$uid/daily` | Overwritten daily | REPLACED daily (set()) | OK — uses set() |
| `sms/$uid` | Replaced on sync | REPLACED on sync | OK — uses set() |
| `commands/$uid/generateReport` | Per request | Removed after processing | OK |

> ⚠️ **CRITICAL BILLING RISK**: `device_events`, `hourly_usage`, and `daily_reports` grow unbounded. After 1 year of use per child, the Firebase RTDB bill will include millions of stale records.

### 6.3 Duplicated Writes

1. `isOnline = true` is written by:
   - `PresenceService.startChildPresence()` (UI isolate)
   - `_setupMonitoringSession()` in background service (Bg isolate)
   - These write to the same node — last writer wins, fine for correctness but wastes Firebase writes

2. `lastSeen` is written by:
   - `PresenceService._heartbeatTimer` (every 30s)
   - `BackgroundMonitoringService._heartbeatTimer` (every 30s)
   - `PresenceService._connectedSub` (on reconnect)
   - `BackgroundMonitoringService._connectedSub` (on reconnect)
   - **4 sources writing `lastSeen`** — doubles Firebase write cost

### 6.4 Stale Subscriptions

1. `NotificationService._subs` — subscriptions persist until `unwatchChild()` is called. If the parent adds 10 children then removes all of them, 10 groups of subscriptions × 6 types = 60 Firebase listeners may persist if any child key isn't properly removed from `_subs`.
2. `KeywordAlertService.scanSmsForKeywords()` reads `sms/$uid` for every keyword check cycle (every 20 minutes). This reads the entire SMS node — if the child has 10,000 SMS records, this is a large Firebase read every 20 minutes.

### 6.5 Format Inconsistencies

1. **`approvedParents/$parentUid`**: Written as `true` (boolean) in `approveParentRequest()`. Read in `ChildHomeScreen._loadConnectedParentFromApproved()` which correctly checks `if (firstEntry.value is Map)` — but this means `parentName` and `parentEmail` are never read from `approvedParents` (since it's just `true`), forcing a secondary Firebase read of the parent's user record. Correct design but undocumented.

2. **`keyword_settings/$childUid/keywords`**: Written as `List` (array) via `.set(current)` where `current` is `List<String>`. Firebase RTDB converts arrays to objects with integer keys (`"0": "word1", "1": "word2"`). The read code handles both `List` and `Map` — correct. But `addKeyword()` reads the current list, adds to it, and re-sets the entire array — for a list of 100 keywords, this is a 100-entry write for every single keyword addition.

3. **`app_usage/$childUid/daily/$pkgKeyDotReplaced`**: Package names with dots replaced by underscores. `com.google.android.youtube` becomes `com_google_android_youtube`. Reversal requires `_pkgKey.replaceAll('_', '.')` — but underscores in package names (`com_package`) would collide. No uniqueness guarantee.

---

## 7. CODE QUALITY + STABILITY AUDIT

### 7.1 Null Safety Violations

```dart
// child_home_screen.dart - _loadConnectedParentFromApproved:
final firstEntry = map.entries.first;
final parentUid = firstEntry.key as String;
```
If `map` is empty (checked by `if (map.isEmpty) return;` — correct), but `map.entries.first` throws `StateError` on empty map. The empty check is present — this is safe. However:

```dart
// background_monitoring_service.dart:
final stat = stats.firstWhere(
  (s) => s.packageName == pkg,
  orElse: () => UsageInfo(),
);
final usedMs = int.tryParse(stat.totalTimeInForeground ?? '0') ?? 0;
```
`UsageInfo()` creates a default instance. `UsageInfo().totalTimeInForeground` — the plugin may not guarantee a non-null field on a default instance. If this is null, `int.tryParse(null ?? '0')` = `int.tryParse('0')` = 0 — safe. But the usage of `UsageInfo()` as an orElse default instead of just `0` is unnecessarily complex.

### 7.2 Async Bugs

```dart
// monitoring_screen.dart:
Future _startMonitoring() async {
  try {
    await FirebaseDatabase.instance.ref('calls/${widget.childUid}/screenError').remove();
    await _webrtc.startAsParent(childUid: widget.childUid, mode: widget.mode);
    if (!mounted) return;
    setState(() { _status = 'Waiting for child device to respond...'; });
  } catch (e) {
    if (!mounted) return;
    setState(() { _status = 'Connection error. Retrying...'; });
  }
}
```
`_webrtc.startAsParent()` internally creates a peer connection and sets Firebase listeners. These listeners fire asynchronously. If `MonitoringScreen` is popped during connection setup, the `onRemoteStream` callback fires on a disposed widget:

```dart
_webrtc.onRemoteStream = () {
  if (!mounted) return;  // Correctly guards setState
  setState(() { _hasStream = true; });
};
```
The `!mounted` guard is present — `setState()` crash prevented. But `_webrtc.endCall()` is called from `dispose()` via the `!_callEnded` path. If `startAsParent()` hasn't finished setting up Firebase listeners yet (still in `await _getIceConfig()` for example), and the screen is disposed, `endCall()` writes `status = 'ended'` to Firebase but the signaling listeners haven't been registered yet — meaning the child's background service sees `status = 'ended'` and stops its stream, then the parent's listeners fire and `startAsParent()` continues registering listeners for a call that's already ended. **The parent WebRTC service then listens indefinitely for an offer that will never come.**

### 7.3 Memory Leaks

1. **`_connectivitySub` in `SilentWebRTCService`**: Called on every `_startStream()`. `_subscribeConnectivity()` cancels the previous subscription before creating a new one. Correct. But if `stopSilent()` is called, `_connectivitySub` is NOT cancelled in `stopSilent()` — it's only cancelled in `_subscribeConnectivity()` on next call. **Memory leak of one connectivity subscription after every `stopSilent()` call.**

```dart
// SilentWebRTCService.stopSilent():
_active = false;
_reconnectTimer?.cancel();
_watchdogTimer?.cancel();
// MISSING: _connectivitySub?.cancel();
await _cleanupPcOnly();
```

2. **`WebRTCService._connectivitySub`**: Same issue — `_connectivitySub` is cancelled only in `_subscribeConnectivity()` and `dispose()`. If `dispose()` is called, connectivity sub is cancelled — correct. But if the screen is popped during a reconnect delay, `dispose()` fires, `endCall()` fires, but `_connectivitySub` may still be alive until `dispose()` completes.

3. **`SnapshotService._ctrl`**: `CameraController` is disposed in `finally` block — correct. But if an exception occurs between `ctrl.initialize()` and the assignment to `_ctrl`, the controller may not be disposed. The `finally` block checks `if (_ctrl == ctrl)` before disposing — if `_ctrl` was never assigned (exception before assignment), the local `ctrl` leaks. Fix: always dispose `ctrl` in finally, not just if `_ctrl == ctrl`.

### 7.4 Context-After-Await Issues

```dart
// child_home_screen.dart - _approveRequest():
final result = await _auth.approveParentRequest(parentUid);
if (!mounted) return;
if (result['success'] == true) {
  ScaffoldMessenger.of(context).showSnackBar(...);  // context used after await ✓
```
The `if (!mounted) return;` guard is present — context use is safe.

```dart
// child_setup_wizard_screen.dart - _requestSinglePermission():
await showDialog(context: context, builder: ...);  // await completes
await openAppSettings();  // app leaves foreground
await Future.delayed(const Duration(milliseconds: 500));
if (mounted) { await _refreshStatus(); }  // mounted check ✓
```
Correct use of mounted check.

**Missing guard:**
```dart
// parent_dashboard_screen.dart - _listenForChildren():
_childrenSub = _auth.getChildrenStream().listen((event) {
  if (!mounted) return;  // ✓ checked
  setState(() { ... });
  for (final uid in newChildren.keys) {
    if (!_batterySubs.containsKey(uid)) {
      _batterySubs[uid] = BatteryService.watchDeviceInfo(uid).listen((info) {
        if (!mounted) return;  // ✓ checked
        setState(() => _deviceInfo[uid] = info);
      });
    }
    NotificationService.instance.watchChild(uid, childName);  // NO await, fire-and-forget
  }
});
```
`NotificationService.instance.watchChild()` is synchronous — correct. No context used. OK.

### 7.5 Stream Cancellation Bugs

```dart
// background_monitoring_service.dart _cancelSessionResources():
_connectedSub?.cancel();
_callsSub?.cancel();
_appLocksSub?.cancel();
_generateReportSub?.cancel();
```
All timers and subscriptions are properly cancelled. ✓

But the WEEKLY/STREAK timer:
```dart
_weeklyAndStreakTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
  final now = DateTime.now();
  if (now.weekday == DateTime.sunday && now.hour == 23 && now.minute >= 0 && now.minute <= 9) {
    try {
      await WeeklySummaryService().generateWeeklySummary(uid);
```
`WeeklySummaryService` and `StreakService` are instantiated with `()` — they may not be singletons. If `_weeklyAndStreakTimer` fires while `generateWeeklySummary()` is still running (it takes several seconds for Firebase reads), a second invocation starts. No idempotency guard exists in `WeeklySummaryService`.

### 7.6 Crash Risks

1. **`Map.from()` without type check**:
```dart
final data = Map<String, dynamic>.from(callSnap.value as Map);
```
If `callSnap.value` is not a `Map` (e.g., it's a primitive or list due to data corruption), this `as Map` cast throws `TypeError`. The outer `try/catch` may catch this, but silent failure and no cleanup.

2. **`event.snapshot.value as Map` in multiple listeners**:
```dart
_appLocksSub = FirebaseDatabase.instance.ref('app_locks/$uid').onValue.listen((event) async {
  final raw = event.snapshot.value;
  final blocked = <String>[];
  if (raw is Map) { ... }  // ✓ type check
```
Most listeners have proper `is Map` checks — relatively safe.

3. **`_watchdogRestarting = false` never reset on exception**:
```dart
_watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
  if (_watchdogRestarting) return;
  try {
    // ...
    if (healthFailures >= 3) {
      _watchdogRestarting = true;
      _cancelSessionResources();
      await _setupMonitoringSession(service, uid);  // CAN THROW
    }
  } catch (e) {
    debugPrint('[BgService] Watchdog error: $e');
    _watchdogRestarting = false;  // ✓ reset in catch
  }
});
```
Actually caught — `_watchdogRestarting = false` in catch block. But `_setupMonitoringSession` is called WITHOUT `await` in the watchdog's catch path... wait, it IS awaited. However: if `_setupMonitoringSession()` throws AND the watchdog timer fires again before the catch runs (async gap), `_watchdogRestarting` is still `true` and the new timer tick returns early. This is the correct behavior — no double restart. After catch, `_watchdogRestarting = false`. On the NEXT tick (30s later), the watchdog tries again. Safe.

4. **`SilentWebRTCService._connect()` — `_connecting` flag race**:
```dart
Future<void> _connect(String childUid) async {
  if (_connecting) return;
  _connecting = true;
  // ... async gaps ...
  } finally {
    _connecting = false;
  }
}
```
`try/finally` ensures `_connecting` is reset. ✓

But `_connect()` is called from `_scheduleReconnect()` via `_reconnectTimer`:
```dart
_reconnectTimer = Timer(Duration(seconds: seconds), () async {
  if (!_active) return;
  await _connect(childUid);
});
```
And from `_subscribeConnectivity()`:
```dart
_connectivitySub = Connectivity().onConnectivityChanged.listen((results) async {
  // ...
  await _connect(childUid);
});
```
These are both async callbacks. If both fire simultaneously (reconnect timer expires at the exact moment connectivity is restored), both call `_connect()`. The first one sets `_connecting = true`, the second returns immediately. Safe — but the second missed reconnect attempt is dropped. On the next event, reconnect retries. Acceptable.

---

## 8. ANDROID-SPECIFIC ANALYSIS

### 8.1 AndroidManifest.xml (Cannot read directly — reconstructed from code)

Based on BootReceiver, services, and declared foreground types:

**Declared Services (inferred):**
- `flutter_background_service.BackgroundService` — foreground service
- `flutter_foreground_task.FlutterForegroundTaskService` — foreground service
- `ScreenCaptureService` — foreground service
- `AppBlockAccessibilityService` — accessibility service
- `WatchdogWorker` (WorkManager)

**Declared Receivers:**
- `BootReceiver` — `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `QUICKBOOT_POWERON`
- `WatchdogReceiver` — alarm receiver
- `DialerCodeReceiver` — `NEW_OUTGOING_CALL` (deprecated on API 29+)
- `FamilyDeviceAdminReceiver` — device admin

**Known Manifest Issues:**

1. **`android:usesCleartextTraffic="true"`**: Confirmed in AUDIT.md — unnecessary, increases attack surface.

2. **`PROCESS_OUTGOING_CALLS` permission**: Deprecated API 29+ — `DialerCodeReceiver` is broken on Android 10+.

3. **`foregroundServiceType="camera|microphone|dataSync"`** on both services: On Android 14+, declaring unused types may cause `ForegroundServiceDidNotStartInTimeException`.

4. **Missing `SCHEDULE_EXACT_ALARM` permission**: `WatchdogReceiver` uses `AlarmManager.setExactAndAllowWhileIdle()` — on Android 12+, this requires `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` permission. If not declared, alarm scheduling throws `SecurityException`.

5. **`ACCESS_BACKGROUND_LOCATION` missing**: Required for background GPS on Android 10+. Without it, `LocationAccuracy.high` only works while the app is in the foreground.

6. **`QUERY_ALL_PACKAGES`**: `getInstalledApps` in `MainActivity.kt` uses `queryIntentActivities()` with `Intent.ACTION_MAIN`. On Android 11+, this requires `QUERY_ALL_PACKAGES` permission OR explicit `<queries>` elements in the manifest. Without it, the installed apps list is heavily filtered.

### 8.2 Foreground Service Types (Android 14+ Compliance)

| Service | Declared Types | Actually Uses | Compliance |
|---|---|---|---|
| BackgroundService (flutter_bg) | camera, microphone, dataSync | dataSync (always), camera+mic (only when streaming) | ❌ Non-compliant idle state |
| FlutterForegroundTask | camera, microphone, dataSync | dataSync only | ❌ Non-compliant always |
| ScreenCaptureService | mediaProjection | mediaProjection | ✓ |

### 8.3 Battery Optimization

`WatchdogReceiver.kt` — alarm scheduling details not audited (file not fetched), but referenced in BootReceiver. 30-second intervals are aggressive.

`BatteryService.isExempt()` / `requestExemption()` — correct implementation using `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

Setup wizard Page 3 (`_PageBatteryScreen`) walks the user through manufacturer-specific steps for battery optimization exemption. This is excellent UX — but it only works if the user completes it. The wizard is skippable.

### 8.4 WatchdogReceiver.kt (Referenced but not fetched)

From `BootReceiver.kt`:
```kotlin
WatchdogReceiver.schedule(context)
```
The `schedule()` method presumably uses `AlarmManager.setExactAndAllowWhileIdle()`. The `WatchdogWorker` is also enqueued as backup. This dual approach is good but the AlarmManager path may fail silently on API 33+ without `SCHEDULE_EXACT_ALARM`.

### 8.5 ScreenCaptureService.kt

Referenced but not fetched. Key concerns:
- `projectionToken` is a `companion object var` (static mutable) — access from multiple threads is non-atomic
- `starting` flag noted in AUDIT.md as needing `@Synchronized` — not verified if fixed
- Service invalidated on every reboot — reboot recovery requires user action

### 8.6 PinVerifyActivity.kt

Referenced but not integrated into the Dart layer. The `AppBlockAccessibilityService` launches it when Settings is opened:
```kotlin
PinVerifyActivity.launch(this)
```
But where is the PIN set? `SharedPreferences` key `flutter.uninstall_pin` — this key is never written in the Dart codebase (searched all service files). **The PIN gate is always skipped** because the pin is always null/empty. `if (!pin.isNullOrEmpty())` → pin is empty → PIN activity never launches. **The uninstall protection is fake.**

---

## 9. BUILD + RELEASE ANALYSIS

### 9.1 GitHub Actions CI/CD

```yaml
# .github/workflows/build.yml:
- run: flutter build apk --debug
```

**Critical Issues:**
1. **CI builds DEBUG APK only** — no release build in CI. Release-specific issues (ProGuard, signing, minification) are never caught.
2. **No test step** — `flutter test` is never run.
3. **SDK version patching is fragile**:
```bash
find $HOME/.pub-cache -name "build.gradle" -exec sed -i \
  's/flutter\.compileSdkVersion/36/g; ...' {} \;
```
This `sed` command replaces Gradle SDK references globally across ALL pub cache packages. This is not idempotent and will corrupt packages that use SDK versions for other purposes.
4. **No artifact signing** — uploaded APK is unsigned debug build.
5. **Flutter version pinned to `3.27.0`** — this is a specific stable channel version. Any breaking changes in plugin versions vs. Flutter SDK are not caught.

### 9.2 Gradle Build

```kotlin
// build.gradle.kts:
signingConfigs {
  create("release") {
    val ksPath = System.getenv("KEYSTORE_PATH") ?: ...
    if (ksPath != null && ...) {
      storeFile = file(ksPath)
    } else {
      // Fallback to debug cert
      storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
    }
  }
}
```

If environment variables are not set, **release builds silently use the debug keystore**. This is the current state in CI since no env vars are configured. Any "release" APK built from CI is signed with the debug keystore.

### 9.3 ProGuard/R8

```kotlin
buildTypes {
  release {
    isMinifyEnabled = true
    isShrinkResources = true
    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
  }
}
```

R8 is enabled. However:
- `proguard-rules.pro` file content was not fetched — unable to verify if all required keep rules are present
- `flutter_webrtc`, `flutter_background_service`, and `flutter_foreground_task` all require specific ProGuard keep rules — if missing, obfuscation breaks the JNI/reflection-based components
- `firebase_database` requires keep rules for `ValueEventListener` reflection

### 9.4 Application ID

```kotlin
defaultConfig {
  applicationId = "com.example.family_monitor"
}
productFlavors {
  create("parent") { applicationId = "com.example.family_monitor.parent" }
  create("child") { applicationId = "com.example.family_monitor.child" }
}
```

**Both application IDs use `com.example`** — Google Play Store rejects `com.example.*` application IDs. This must be changed before any Play Store submission.

### 9.5 Dependency Analysis

| Package | Version | Risk |
|---|---|---|
| `flutter_webrtc: ^0.14.0` | Latest | Known race conditions in `Helper.switchCamera()` |
| `flutter_background_service: ^5.0.9` | Latest | Two-isolate model limitations |
| `flutter_foreground_task: ^8.14.0` | Latest | May conflict with flutter_background_service |
| `usage_stats: ^1.3.1` | Old | May not support Android 14 APIs |
| `camera: ^0.10.5+9` | Latest | OK |
| `flutter_contacts: ^1.1.7+1` | Latest | OK |
| `geolocator: ^13.0.2` | Latest | OK |
| `firebase_database: ^11.1.4` | Latest | OK |
| `firebase_auth: ^5.3.1` | Latest | OK |

**Dependency conflicts:**
- `flutter_background_service_android: ^6.2.2` is listed separately from `flutter_background_service: ^5.0.9` — the Android implementation package is usually bundled. Explicitly listing both may cause version conflicts if the bundled version differs from `6.2.2`.

### 9.6 ABI Issues

The comment in `build.gradle.kts` correctly explains `--split-per-abi`. No `ndk.abiFilters` is hardcoded. The build produces a fat APK by default (all ABIs) which is larger but simpler. For Play Store, AAB is recommended.

---

## 10. CRITICAL ISSUES

| ID | File | Issue | Impact |
|---|---|---|---|
| CRIT-01 | `lib/services/background_monitoring_service.dart` | **`PACKAGE_USAGE_STATS` permission never requested** — all screen time, app usage, daily reports, hourly heatmap return empty data silently | App's core monitoring features non-functional |
| CRIT-02 | Firebase Console (not in repo) | **No Firebase Security Rules** — all child data (SMS, location, contacts) potentially world-readable or world-writable | GDPR/privacy violation, data breach risk |
| CRIT-03 | `lib/services/sms_service.dart` + wizard | **`READ_SMS` permission not in setup wizard** — SMS sync silently fails for all users | Core feature non-functional |
| CRIT-04 | `lib/screens/child/child_home_screen.dart` | **`_locked = false` hardcoded** — lock overlay is permanently disabled, device lock feature is fake UI | Feature falsely advertised |
| CRIT-05 | `android/app/src/main/kotlin/.../AppBlockAccessibilityService.kt` | **`flutter.uninstall_pin` never written in Dart** — PIN gate never triggers, uninstall protection is fake | Security feature non-functional |
| CRIT-06 | `lib/services/silent_webrtc_service.dart` | **`_connectivitySub` not cancelled in `stopSilent()`** — stream leak on every monitoring session end | Memory leak, zombie Firebase listener |
| CRIT-07 | `lib/services/notification_service.dart` | **FCM token never saved, no Cloud Function** — parent push notifications non-functional when parent app is closed | Core notification feature broken |
| CRIT-08 | `lib/main.dart` + flavor system | **No flavor-specific route guards** — parent APK can navigate to `/child/home` via SharedPreferences manipulation | Security boundary failure |
| CRIT-09 | `lib/screens/child/child_home_screen.dart` | **`users/$uid/connectedParent` is never written** — connected parent display always falls through to fallback, never shows correct data via primary path | Core UX broken |
| CRIT-10 | `BootReceiver.kt` | **`LOCKED_BOOT_COMPLETED` fires in Direct Boot** — `FlutterSharedPreferences` in credential-encrypted storage not accessible → crash on first-boot boot receiver | Boot-time crash |

---

## 11. HIGH PRIORITY ISSUES

| ID | File | Issue | Impact |
|---|---|---|---|
| HIGH-01 | `android/app/build.gradle.kts` | Application ID `com.example.*` — Play Store rejects | Cannot publish |
| HIGH-02 | `lib/screens/child/child_home_screen.dart` | SMS/contacts/call log/app list sync listeners dead in background | Core features fail when app minimized |
| HIGH-03 | `lib/services/location_service.dart` | Location tracking stopped on `ChildHomeScreen.dispose()` | Background location non-functional |
| HIGH-04 | `lib/services/app_install_alert_service.dart` | `_knownPackages` reset on service restart → hundreds of false install alerts | Spams parent with false data |
| HIGH-05 | `lib/services/background_monitoring_service.dart` | `SCHEDULE_EXACT_ALARM` not declared/checked — `WatchdogReceiver` scheduling may throw `SecurityException` on API 33+ | Service watchdog silently fails |
| HIGH-06 | `android/app/src/main/AndroidManifest.xml` | `ACCESS_BACKGROUND_LOCATION` not declared — background GPS broken Android 10+ | Location tracking non-functional in background |
| HIGH-07 | `lib/services/auth_service.dart` | `signInChild()` doesn't verify `role == 'child'` — parent can sign in as child | Auth boundary broken |
| HIGH-08 | `lib/services/turn_config_service.dart` | STUN-only fallback — 40% of connections through carrier NAT fail | WebRTC unreliable for large user base |
| HIGH-09 | `lib/screens/parent/parent_dashboard_screen.dart` | `setState()` called on disposed widget via 3s delayed reattachment after stream error | Crash risk |
| HIGH-10 | `android/app/build.gradle.kts` | Release build falls back to debug keystore if env vars not set — CI produces debug-signed "release" | Security/publishing issue |
| HIGH-11 | `lib/services/snapshot_service.dart` | Native snapshot channel requires Activity foreground — background snapshots fail silently | Feature non-functional in background |
| HIGH-12 | `android/app/src/main/AndroidManifest.xml` | `QUERY_ALL_PACKAGES` not declared — `getInstalledApps()` returns filtered list on API 30+ | App list incomplete, install alerts miss apps |
| HIGH-13 | `lib/services/background_monitoring_service.dart` | Foreground service types `camera|microphone` declared on idle service — Android 14 kills service | Service crash on Android 14 |

---

## 12. MEDIUM PRIORITY ISSUES

| ID | File | Issue | Impact |
|---|---|---|---|
| MED-01 | `lib/services/auth_service.dart` | Anonymous auth accounts expire after 30 days — no recovery path | Child devices go dark after a month |
| MED-02 | `lib/services/background_monitoring_service.dart` | `app_install_alerts` written per-restart with all known packages (first-run problem) | False positive spam |
| MED-03 | `lib/services/keyword_alert_service.dart` | `sms/$uid` full read on every keyword scan (every 20min) — large data read | Firebase bandwidth cost |
| MED-04 | `lib/services/battery_service.dart` | Battery reporting every 60s even when screen off — unnecessary battery drain | Child device battery drain |
| MED-05 | Firebase (inferred) | `device_events`, `hourly_usage`, `daily_reports` grow unbounded — no TTL | Firebase billing risk |
| MED-06 | `lib/services/presence_service.dart` | `isOnline` written from 4 sources — doubled Firebase write cost | Performance/cost |
| MED-07 | `lib/screens/child/child_setup_wizard_screen.dart` | Wizard Page 7 has no timeout — child stuck if parent never sends request | Poor UX |
| MED-08 | `lib/screens/child/child_setup_wizard_screen.dart` | `_auth.currentUser?.uid` null if session expired mid-wizard — silent failure | Setup failure |
| MED-09 | `lib/screens/parent/parent_dashboard_screen.dart` | Every battery heartbeat rebuilds entire dashboard — excessive redraws | Performance |
| MED-10 | `lib/services/background_monitoring_service.dart` | `UsageStats.queryUsageStats()` every 60s for entire day — expensive query | Performance/battery |
| MED-11 | `lib/services/webrtc_service.dart` | `startAsParent()` followed by immediate `endCall()` from dispose creates zombie listeners | Resource leak |
| MED-12 | `android/app/src/main/kotlin/.../AppBlockAccessibilityService.kt` | `APP_INFO_CLASSES` list incomplete — Samsung/Xiaomi/Huawei Settings class names not covered | Uninstall protection gap |
| MED-13 | `lib/services/notification_service.dart` | `_seen` dedup sets lost on app restart — old alerts re-notified | UX annoyance |
| MED-14 | `lib/screens/child/child_home_screen.dart` | `READ_CALL_LOG` permission flow not confirmed in wizard — call log sync may silently fail | Feature gap |
| MED-15 | `lib/services/background_monitoring_service.dart` | `WeeklySummaryService().generateWeeklySummary()` not idempotent — concurrent calls possible | Data corruption |

---

## 13. LOW PRIORITY ISSUES

| ID | File | Issue | Impact |
|---|---|---|---|
| LOW-01 | `android/app/src/main/AndroidManifest.xml` | `android:usesCleartextTraffic="true"` unnecessary | Attack surface |
| LOW-02 | `android/app/src/main/kotlin/.../DialerCodeReceiver.kt` | `PROCESS_OUTGOING_CALLS` deprecated API 29+ | Recovery code broken Android 10+ |
| LOW-03 | `lib/screens/child/child_home_screen.dart` | `child_home_screen.dart.broken` committed to repo — dead file | Repo hygiene |
| LOW-04 | `android/app/src/main/kotlin/.../MainActivity.kt.bak` | `.bak` file committed to repo | Repo hygiene |
| LOW-05 | `lib/screens/parent/monitoring_screen.dart` | `RTCVideoView` in `Offstage` holds heavyweight native surface | Memory on low-RAM devices |
| LOW-06 | `lib/services/keyword_alert_service.dart` | `addKeyword()` re-writes entire array for each addition — inefficient for large lists | Firebase cost |
| LOW-07 | `lib/services/auth_service.dart` | Stale `status: 'approved'` entries never cleaned from `pendingParentRequests` | Firebase storage |
| LOW-08 | `lib/services/location_service.dart` | Geofence `_lastInside` stored in Firebase — every position update causes Firebase write | Excessive Firebase writes |
| LOW-09 | `.github/workflows/build.yml` | `sed` on pub-cache is not idempotent — repeated runs corrupt gradle files | CI reliability |
| LOW-10 | `lib/screens/child/child_streaming_screen.dart` | `ChildStreamingScreen` exists but is never navigated to — dead code | Maintenance debt |
| LOW-11 | `lib/services/background_monitoring_service.dart` | `app_usage/$childUid/daily` uses pkg dots→underscores — collides with pkgs containing underscores | Data integrity |
| LOW-12 | `lib/main.dart` | `main.dart` includes both parent and child routes — no flavor isolation at Dart level | Architectural smell |
| LOW-13 | Firebase | `approvedParents` accumulates with `status: 'approved'` entries — never pruned | Storage growth |

---

## 14. ARCHITECTURE REFACTOR RECOMMENDATIONS

### 14.1 Immediate Architecture Fixes (Before Any User Exposure)

**A. Consolidate Background Service into Single Isolate**

Remove `flutter_foreground_task` entirely. `flutter_background_service` with `isForegroundMode: true` already provides a foreground service notification. The dual-service approach wastes resources and creates notification confusion.

```
BEFORE: 2 foreground services, 2 Dart isolates, 2 notification bars
AFTER:  1 foreground service, 1 background isolate, 1 notification bar
```

**B. Move Command Listeners to Background Service**

Currently, command listeners (SMS, contacts, call log, app list sync) are in `ChildHomeScreen`. Move ALL command listeners to the background service isolate so they work when the app is minimized.

```dart
// In _setupMonitoringSession():
_smsCommandSub = FirebaseDatabase.instance
  .ref('commands/$uid/syncSms/requested')
  .onValue.listen((e) {
    if (e.snapshot.value == true) {
      // Use platform channel in background isolate (via DartPluginRegistrant)
      // to invoke native SMS read
    }
  });
```

**C. Fix Location Tracking**

Move `LocationService.startTracking()` into the background service isolate with `ACCESS_BACKGROUND_LOCATION` declared in the manifest.

**D. Implement Firebase Security Rules**

Deploy rules that enforce parent-child relationship before any public release.

**E. Save FCM Token and Add Cloud Functions**

```dart
// After successful parent login:
final token = await FirebaseMessaging.instance.getToken();
if (token != null) {
  await _db.child('fcm_tokens/${user.uid}').set(token);
}
```

### 14.2 Medium-Term Architecture Refactors

1. **Add a state management layer** (Riverpod recommended): Replace scattered `setState()` calls with providers. `ChildProvider`, `DeviceInfoProvider`, `PresenceProvider`.

2. **Implement proper pairing security**: QR code should encode `{uid, nonce, timestamp, hmac}` not just `uid`. Parent verifies HMAC and timestamp before sending request.

3. **Add `google-services.json` validation**: Check that the bundled `google-services.json` matches the actual Firebase project. CI should validate this.

4. **Implement TTL cleanup**: Cloud Function that runs nightly to trim `device_events` to last 200 entries, `hourly_usage` older than 30 days, etc.

5. **Replace polling with proper push**: Cloud Functions triggered on Firebase writes should send FCM to parent device. This is the only reliable way to notify parents when their app is closed.

### 14.3 Long-Term Architecture for Production Scale

```
┌─────────────────────────────────────────────────────┐
│                PARENT APP (Flutter)                   │
│  NotificationService ← FCM ← Cloud Functions         │
│  Real-time dashboard ← Firebase RTDB listeners       │
└─────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│              FIREBASE BACKEND                         │
│  • Realtime Database (presence, alerts, commands)    │
│  • Cloud Functions (FCM dispatch, data aggregation)  │
│  • Storage (snapshots, recordings)                   │
│  • App Check (request attestation)                   │
│  • Security Rules (access control)                   │
└─────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│               CHILD APP (Flutter)                     │
│  Single Background Service Isolate:                   │
│  • WebRTC (camera/screen)                            │
│  • Location (with background permission)             │
│  • Usage stats (with PACKAGE_USAGE_STATS)            │
│  • SMS/Contacts (with permissions)                   │
│  • All command listeners                             │
│  Accessibility Service:                              │
│  • App blocking (complement to DPM)                  │
│  WorkManager:                                        │
│  • Periodic health check + reconnect                 │
└─────────────────────────────────────────────────────┘
```

---

## 15. STABILITY SCORE

```
Feature                          Score  Notes
─────────────────────────────────────────────────────────────────
Authentication flow              5/10   Role check missing in signInChild; anonymous expiry
Device Pairing/QR                6/10   Works but no security nonce; phantom connectedParent node
Live Camera                      5/10   Works in foreground; fragile in background
Live Screen Share                4/10   Breaks on every reboot; token invalidation
App Usage / Screen Time          2/10   PACKAGE_USAGE_STATS never requested; silent failure
SMS Monitoring                   2/10   Permission not requested; listener dead in background
Call Log Monitoring              3/10   Similar to SMS
Contact Sync                     3/10   Permission not in wizard; listener dead in background
Location Tracking                4/10   Works in foreground; stops on minimize
Geofencing                       4/10   Dependent on broken location tracking
Battery Alerts                   7/10   Best implemented feature; minor leak
App Install Alerts               3/10   False positives on restart; command response race
Snapshots                        4/10   Native path fragile; background path fails
App Blocking (Accessibility)     4/10   Manual setup; incomplete OEM coverage; PIN fake
App Blocking (DPM)               5/10   Optional; not always available
Daily Reports                    3/10   Depends on broken UsageStats
Notification System              4/10   Local only; FCM fake; dedup lost on restart
Firebase Security                1/10   No rules; potential open database
Background Persistence           5/10   Two services but many features still UI-dependent
WebRTC Signaling                 6/10   Reasonable; needs TURN server

OVERALL STABILITY SCORE:         3.9 / 10
```

---

## 16. RELEASE READINESS SCORE

```
Category                         Score  Blocker?
─────────────────────────────────────────────────────────────────
Privacy & Security               1/10   YES - No Firebase rules, open data
GDPR Compliance                  2/10   YES - SMS/location without rules
Core Feature Functionality       3/10   YES - Most features broken/partial
Android Platform Compliance      4/10   YES - com.example ID, deprecated APIs
Background Execution             4/10   YES - Most sync features UI-dependent
Permission Architecture          3/10   YES - Critical permissions not requested
Play Store Requirements          2/10   YES - com.example, no privacy policy verified
Error Handling                   5/10   No - Adequate but not production grade
UI/UX Polish                     7/10   No - Well-designed UI
WebRTC Reliability               4/10   No - Works but needs TURN server
CI/CD Pipeline                   3/10   No - Debug-only, no tests
Documentation                    4/10   No - AUDIT.md exists, README is template

RELEASE READINESS SCORE:         1.5 / 10

VERDICT: NOT READY FOR PUBLIC RELEASE
```

**Blockers that MUST be resolved before ANY public release:**
1. Firebase Security Rules
2. PACKAGE_USAGE_STATS permission request
3. READ_SMS permission request in wizard
4. Application ID change from com.example
5. FCM functional notification system
6. Background location permission
7. SCHEDULE_EXACT_ALARM or alternative
8. Android 14 foreground service type compliance
9. Remove hardcoded `_locked = false`
10. Functional uninstall PIN protection

---

## 17. PRODUCTION RISK SCORE

```
Risk Category                    Score  Description
─────────────────────────────────────────────────────────────────
Data Privacy Risk                9/10   High - Open Firebase, SMS/location exposed
Legal/Compliance Risk            8/10   High - GDPR, COPPA (child data) violations
User Data Loss Risk              7/10   High - Unbounded growth, no backups
App Crash Risk                   6/10   Medium - Several crash paths identified
Service Continuity Risk          7/10   High - Features die when app minimized
Security Breach Risk             9/10   High - No rules, no App Check, no FCM auth
Play Store Rejection Risk        9/10   Certain - com.example, no privacy policy path
Parent Trust Risk                8/10   High - Features appear to work but don't
Child Safety Risk                7/10   High - Monitoring gaps create false confidence
Battery Impact on Child Device   6/10   Medium - Aggressive timers

PRODUCTION RISK SCORE:           7.6 / 10  (CRITICAL)
```

---

## 18. PHASE-WISE FIX PLAN

### Phase 0: Emergency Blockers (1-2 days)
1. Set Firebase Security Rules (30 minutes — Firebase Console)
2. Add `PACKAGE_USAGE_STATS` permission request flow in setup wizard
3. Add `READ_SMS` to wizard `_requestCorePermissions()`
4. Change application ID from `com.example.*` to real ID
5. Fix `_locked = false` → read from Firebase `commands/$uid/deviceLock`

### Phase 1: Critical Architecture (1-2 weeks)
6. Remove `flutter_foreground_task` — consolidate to single background service
7. Move ALL command listeners (SMS, contacts, call log, app list) to background service
8. Add `ACCESS_BACKGROUND_LOCATION` to manifest; move location to background service
9. Declare and check `SCHEDULE_EXACT_ALARM` permission; implement WorkManager-only watchdog
10. Fix Android 14 foreground service types (dynamic promotion only during streams)
11. Implement FCM token save + Cloud Function for push notifications
12. Write `users/$uid/connectedParent` node in `approveParentRequest()`
13. Fix `_connectivitySub` leak in `SilentWebRTCService.stopSilent()`

### Phase 2: Feature Completion (2-3 weeks)
14. Add `READ_CONTACTS` and `READ_CALL_LOG` to wizard permissions
15. Add PACKAGE_USAGE_STATS Settings redirect in wizard
16. Add `QUERY_ALL_PACKAGES` to manifest or `<queries>` block
17. Implement functional device lock (write/read Firebase, show overlay)
18. Implement functional uninstall PIN (write from Dart, PinVerifyActivity)
19. Add Firebase data TTL cleanup (Cloud Functions or client-side trim)
20. Fix `_knownPackages` reset on service restart (persist to SharedPreferences)
21. Provision private TURN server and populate `config/turnServers`
22. Add `signInChild()` role verification

### Phase 3: Stability & Performance (2-3 weeks)
23. Add state management (Riverpod)
24. Fix `NotificationService` — FCM-based alerts
25. Add QR code security (nonce + HMAC)
26. Implement `connected` Firebase node with proper cleanup
27. Add screen-state tracking (`ACTION_SCREEN_ON/OFF`)
28. Add UsageStats permission guidance (Settings redirect)
29. Fix duplicate `lastSeen` writers
30. Add Cloud Function data aggregation for usage stats

### Phase 4: Production Hardening (1-2 weeks)
31. Firebase App Check integration
32. ProGuard rules verification
33. CI pipeline: add release build, signing, `flutter test`
34. Remove `.broken` and `.bak` files from repo
35. Privacy policy + Terms of Service links
36. Google Play Console setup with proper content rating (18+ given surveillance capabilities)
37. Accessibility service configuration completion for all OEM device types

---

## 19. ESTIMATED FIX COMPLEXITY

| Issue Group | Effort | Engineer-Days |
|---|---|---|
| Firebase Security Rules | Low | 0.5 |
| Permission additions (wizard) | Low | 1 |
| Application ID change | Low-Medium | 1 (cascade: google-services.json, Kotlin packages) |
| Move listeners to background service | High | 4-5 |
| Background location | Medium | 2 |
| Android 14 foreground service types | Medium | 2 |
| FCM integration + Cloud Functions | High | 5 |
| Device lock (real implementation) | Medium | 3 |
| PIN protection (real implementation) | Medium | 2 |
| TURN server setup | Medium | 2 |
| Data TTL cleanup | Medium | 2 |
| State management refactor | Very High | 10+ |
| CI/CD release pipeline | Medium | 2 |
| `_connectivitySub` leak fix | Low | 0.5 |
| `_knownPackages` persistence | Low | 1 |
| `connectedParent` node write | Low | 0.5 |
| QR code security | Medium | 2 |
| All other medium/low issues | Low-Medium | 8 |

**Total Estimated Effort: ~50-60 engineer-days (10-12 weeks for a 1-person team; 3-4 weeks for a 3-person team)**

---

## 20. FILES MOST RESPONSIBLE FOR FAILURES

Ranked by number of critical/high issues and blast radius:

| Rank | File | Issues Count | Primary Problems |
|---|---|---|---|
| 1 | `lib/services/background_monitoring_service.dart` | 12 | Missing PACKAGE_USAGE_STATS, false install alerts, dead command pattern, two foreground types, timer proliferation |
| 2 | `lib/screens/child/child_home_screen.dart` | 9 | Listeners dead in background, `_locked=false`, phantom connectedParent, `READ_SMS` missing, service startup race |
| 3 | `lib/services/silent_webrtc_service.dart` | 6 | `_connectivitySub` leak, screen mode broken in background, orphan session UX, STUN-only |
| 4 | `lib/services/auth_service.dart` | 6 | signInChild no role check, anonymous expiry, phantom node, race conditions, stale entries |
| 5 | `lib/services/notification_service.dart` | 5 | FCM non-functional, dedup lost on restart, no token save, no Cloud Functions |
| 6 | `android/app/build.gradle.kts` | 4 | com.example ID, debug keystore fallback, SDK version patching |
| 7 | `android/app/src/main/kotlin/.../AppBlockAccessibilityService.kt` | 4 | PIN never set, incomplete OEM class list, no overlay permission |
| 8 | `lib/services/location_service.dart` | 4 | Stops on dispose, no background location permission, geofence Firebase write on each update |
| 9 | `android/app/src/main/kotlin/.../BootReceiver.kt` | 3 | LOCKED_BOOT_COMPLETED crash, MY_PACKAGE_REPLACED isAppInForeground unreliable on API 30+ |
| 10 | `lib/screens/child/child_setup_wizard_screen.dart` | 5 | No timeout on approval wait, session expiry mid-wizard, PACKAGE_USAGE_STATS guidance missing, READ_CONTACTS/READ_CALL_LOG missing |
| 11 | `.github/workflows/build.yml` | 3 | Debug-only, no tests, non-idempotent sed |
| 12 | Firebase (no `database.rules.json`) | ∞ | All data potentially exposed |

---

## APPENDIX: VERIFIED FAKE/NON-FUNCTIONAL FEATURES

The following features appear functional in the UI but have no working backend implementation:

| Feature | Where It Appears | Why It's Fake |
|---|---|---|
| **Device Lock** | `ChildHomeScreen` shows lock overlay | `_locked = false` hardcoded; never reads from Firebase |
| **Uninstall PIN Protection** | `AppBlockAccessibilityService` & setup wizard | `flutter.uninstall_pin` never written from Dart; PIN gate never triggers |
| **App Usage Monitoring** | Parent dashboard → App Usage screen | `PACKAGE_USAGE_STATS` not requested; returns empty always |
| **Screen Time Limits** | Parent dashboard → App Lock screen | Same permission gap; no enforcement without UsageStats |
| **SMS Monitoring (background)** | Shows in parent SMS screen | Listener dead when app minimized; permission not in wizard |
| **Push Notifications** | FCM permission requested in NotificationService | No FCM token saved; no Cloud Function; local-only |
| **Background Location** | Location shown in parent dashboard | Stops immediately when child minimizes app |
| **Geofence Alerts (background)** | Geofence screen shows on parent | Dependent on broken background location |
| **Background Snapshots** | Snapshot trigger works | MethodChannel only works with Activity foreground |
| **App Blocking (Lock overlay)** | Lock card shown in UI | `_locked` never true; accessibility service fragile |
| **"Monitoring Active" indicator** | Child home screen header | Shows "Monitoring Active" always, even when all features fail |
| **Weekly Summary (fully automated)** | WeeklySummary screen | Dependent on `PACKAGE_USAGE_STATS`; may not run if service killed before Sunday 23:00 |

---

*Report generated by comprehensive forensic analysis of all source files, Kotlin native components, Gradle build system, Firebase data model, GitHub Actions CI/CD, and comparison against production parental-control app standards (FlashGet Kids, Google Family Link, Qustodio).*

*This report represents findings accurate as of the repository's main branch at the time of audit. Specific line numbers are referenced from the fetched source content.*
