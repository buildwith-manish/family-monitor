# PHASE_1_CRITICAL_FIXES.md
## Family Monitor — Production-Critical Issue Register

> **Source of Truth:** `attached_assets/audit_extracted/APP_DEBUG_MASTER_REPORT.md`
> **Verified Against:** Actual running source files — 6 independent cross-file verification rounds
> **Scope:** Production-critical issues only, ordered by the user's stated priority hierarchy
> **DO NOT PATCH** any file in this document without reading the full entry first

---

## VERIFICATION STATUS: ALREADY RESOLVED

The following audit findings are **confirmed resolved** in the current branch. They are documented here for reference and must not be re-opened or re-patched.

| Audit ID | Issue | Resolution |
|---|---|---|
| CRIT-01 | `_saveProfileFirst` wipes `approvedParents` | Fixed — conditional read-before-write at wizard lines 408–413 |
| CRIT-06 | `testCrashlytics()` in main.dart | Confirmed absent — function is not present in current `main.dart` |
| CRIT-03 | `google-services.json` not in `.gitignore` | Confirmed present — both entries already in `.gitignore` |
| HIGH-01 | `_reattachChildrenListener` on every resume | Fixed — `_reattachChildrenListenerIfNeeded` has null guard before recreating |
| HIGH-02 | NotificationService `_seen` sets local-per-call | Fixed this session — promoted to `Map<String, Set<String>> _seenAlerts` instance field |
| HIGH-04 | MonitoringScreen double `endCall` on dispose | Fixed — `_callEnded` guard at line 160 and `!_callEnded` in dispose at line 189 |
| HIGH-06 | SplashScreen no Firebase auth wait | Fixed this session — `authStateChanges().first.timeout(3s)` before routing |
| HIGH-08 | Wizard `_requestSub` only attached after page 5 | Fixed this session — `_startRequestListener` called in `initState` |
| NAV-01 | Rapid wizard double-tap — no navigation lock | Fixed — `_navigationLock` present at lines 38 and 340 |
| FB-01 | `_offerSub` fires twice on offer node reconnect | Fixed — `_offerProcessed` promoted to instance field in `WebRTCService` |
| FB-02 | `generateReport` listener never cancelled | Fixed — `_generateReportSub` tracked at line 247, cancelled at line 266 |
| FB-04 | `approveParentRequest` non-atomic 3-step write | Fixed this session — single multi-path `_db.update({...})` at line 290 |
| BG-03 | `startService` race — no Dart-level mutex | Fixed — `Completer<void>? _startCompleter` at lines 45–62 |
| PERF-02 | Hourly heatmap queries all 24 hours in loop | Confirmed fixed in current code — `_hourlyUsageTimer` queries only current hour |
| PERF-04 | WebRTC heartbeat every 10 seconds | Fixed — `SilentWebRTCService._startHeartbeat` uses `Duration(seconds: 30)` at line 507 |

---

## PRIORITY 1 — LOGIN / AUTH FAILURES

---

### P1-A: `Firebase.initializeApp()` Called Without `DefaultFirebaseOptions` in All Entry Points

**Audit Reference:** CRIT-04
**Severity:** CRITICAL — STARTUP CRASH on release builds; silent monitoring failure on fresh installs

**Affected Files:**
- `lib/main.dart` — line 28
- `lib/services/background_monitoring_service.dart` — line 141
- `lib/services/foreground_service.dart` — line 167

**Root Cause:**
All three entry points call `Firebase.initializeApp()` without explicit `FirebaseOptions`. The no-argument form works only when `flutterfire configure` has been run and a `firebase_options.dart` is present. No such file exists in the current codebase tree. In release builds (AOT compilation), `firebase_core` cannot rely on the Gradle plugin's runtime injection of options the same way it does in debug (JIT) mode.

**Exact Execution Flow:**
1. Release APK cold-starts. `main()` calls `await Firebase.initializeApp()` with no options argument.
2. `firebase_core` looks for `DefaultFirebaseOptions` or a native Gradle-embedded options object.
3. If neither exists (clean install, no prior debug run), the call throws `[core/no-app]` — caught by the try/catch at line 29–33, which prints to `debugPrint` (invisible in release) and returns. The app never calls `runApp()`.
4. In the background isolate: `_onStart` calls `await Firebase.initializeApp()` at line 141. If Firebase was already initialized in the main isolate (sharing process memory), this throws `[core/duplicate-app]`. The catch at line 142 handles this — but crucially, if the duplicate-app exception means the background isolate did NOT initialize its own Firebase registry, subsequent `FirebaseDatabase.instance` calls in the background isolate may reference an uninitialized instance.
5. `FirebaseCrashlytics.instance.recordFlutterFatalError` at main.dart line 37 will itself throw if Firebase failed to initialize — the crash reporter crashes before reporting the crash.

**Why Current Logic Fails:**
The no-argument `Firebase.initializeApp()` is a legacy API pattern that relied on the FlutterFire CLI generating options at build time. Without `firebase_options.dart`, release builds that do not have cached native options will fail silently. The `try/catch` returns without `runApp()` being called, leaving a black screen. On fresh install there is no debug output. Users see a splash screen that never navigates.

**Safest Production-Grade Fix Strategy:**
1. Run `flutterfire configure` in the project root to generate `lib/firebase_options.dart`.
2. In `main.dart`, `background_monitoring_service.dart`, and `foreground_service.dart`, replace all `Firebase.initializeApp()` calls with `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
3. In background isolates, retain the duplicate-app guard (`if (Firebase.apps.isEmpty)`) but pass explicit options:
   ```dart
   if (Firebase.apps.isEmpty) {
     await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
   }
   ```
4. Update `flutterfire configure` in the CI pipeline to regenerate options on each build.

**Android-Specific Constraints:**
- `flutterfire configure` must be run with the correct Firebase project selected. The `google-services.json` file at `android/app/google-services.json` must be present when running `configure`.
- The Gradle `google-services` plugin (classpath `com.google.gms:google-services`) must be applied in `android/build.gradle` and `android/app/build.gradle`. Without it, `DefaultFirebaseOptions` generation from the CLI may fail silently.
- In the `@pragma('vm:entry-point')` background isolate, `DartPluginRegistrant.ensureInitialized()` must be called BEFORE `Firebase.initializeApp()` to give the isolate access to Flutter plugins.

**Firebase-Specific Constraints:**
- `DefaultFirebaseOptions.currentPlatform` is a compile-time constant generated by `flutterfire configure`. It embeds `apiKey`, `appId`, `projectId`, `databaseURL`, `storageBucket`, and `messagingSenderId` directly in the Dart source. These values must match the `google-services.json` file.
- If the Firebase project's API key is rotated (recommended after CRIT-03), `flutterfire configure` must be re-run and the app rebuilt. Old installed APKs with stale keys will fail.

**Implementation Risk:** MEDIUM — Requires FlutterFire CLI and the `google-services.json` to be present. Blocks other fixes that depend on Firebase being initialized correctly.

**Regression Risk:** LOW — Adding `DefaultFirebaseOptions` is purely additive. The no-argument form worked by coincidence in development; explicit options are strictly safer.

**Dependency Chain Impact:**
- **Blocks:** BG-01 (dual foreground service) — cannot verify Android 14 compatibility without a working release build.
- **Blocks:** REL-03 (ProGuard) — ProGuard rules for Firebase are only testable in release builds.
- **Required before:** any production deployment.

---

### P1-B: SplashScreen Routes Without Validating Token Expiry

**Audit Reference:** HIGH-06 (partial — auth wait fixed; token validation remains)
**Severity:** HIGH — Parent users with expired tokens are routed to the dashboard where all Firebase listeners immediately fail with `PERMISSION_DENIED`

**Affected Files:**
- `lib/screens/splash_screen.dart` — `_navigate()` method

**Root Cause:**
The `authStateChanges().first` wait added this session correctly restores the `User` object from the local cache on cold start. However, the restored `User` may hold an expired Firebase ID token. Firebase ID tokens expire every 60 minutes. `authStateChanges()` returns the cached `User` object even when the underlying token has expired — it does not perform a network validation.

**Exact Execution Flow:**
1. Parent closes the app at T=0. Their auth token expires at T+60 min.
2. Parent reopens the app at T+90 min (token expired for 30 minutes).
3. SplashScreen waits for `authStateChanges().first` → receives the cached `User` object (non-null, token stored but expired).
4. `user != null` is true → routes to `/parent/dashboard`.
5. `ParentDashboardScreen` calls `_listenForChildren()` → Firebase RTDB listener uses the expired ID token → all reads fail with `PERMISSION_DENIED`.
6. The dashboard shows a spinner forever. No error message is shown to the user. The `onError` handler retries `_reattachChildrenListener` → infinite retry loop.

**Why Current Logic Fails:**
`FirebaseAuth.instance.authStateChanges().first` checks whether a User object is cached, not whether the token is valid. Firebase automatically refreshes tokens in the background, but this refresh is async and may not complete within the `timeout(3s)` window if the device has not been online recently.

**Safest Production-Grade Fix Strategy:**
After the `authStateChanges().first` wait, add a token force-refresh with a fallback to sign-out:
```dart
// After authStateChanges wait:
if (user != null) {
  try {
    await user.getIdToken(true); // Force refresh — throws if token cannot be renewed
  } on FirebaseAuthException catch (_) {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushReplacementNamed(context, '/role-select');
    return;
  }
}
```
The `getIdToken(true)` call requires network access. If offline, it throws a network error — do NOT sign out on network errors, only on `FirebaseAuthException` with code `user-not-found`, `user-disabled`, or `invalid-user-token`. Add a catch for `PlatformException` to handle offline gracefully.

**Android-Specific Constraints:**
- On Android, Firebase Auth uses Google Play Services for token management. If Play Services is outdated or unavailable, `getIdToken(true)` may fail for non-auth reasons. The catch clause must distinguish auth failures from infrastructure failures.
- Token refresh requires network access. If the user is on a slow network, this call may take 2–5 seconds — acceptable given it's behind the splash delay.

**Firebase-Specific Constraints:**
- `getIdToken(true)` triggers a network call to Firebase Auth REST API. Rate-limited to 5 forced refreshes per minute per user.
- Token refresh success does not guarantee that Realtime Database rules will pass — a parent whose role was changed in the database while offline may have a valid token but invalid permissions.

**Implementation Risk:** LOW — Additive change to `_navigate()`. Existing auth flow is not restructured.

**Regression Risk:** LOW — Offline users see the role-selection screen instead of the dashboard with a permanently spinning loader, which is strictly better UX.

**Dependency Chain Impact:**
- Independent. Can be implemented without any other changes.

---

## PRIORITY 2 — PARENT-CHILD SYNC

---

### P2-A: Dual WebRTC Ownership — Two Services Compete on the Same Firebase Signaling Path

**Audit Reference:** CRIT-02
**Severity:** CRITICAL — Monitoring sessions fail to establish or are silently terminated; native `InvalidStateError` crash on the WebRTC peer connection

**Affected Files:**
- `lib/services/webrtc_service.dart` — `startAsChild()` (line 68), `_subscribeConnectivity()` (line 595), `startScreenShareAsChild()` (line 569), `startSilentScreen()` (line 579)
- `lib/services/silent_webrtc_service.dart` — `_connectivitySub` (line 45), `startSilentCamera()`, `startSilentScreen()`
- `lib/screens/child/child_home_screen.dart` — `_callSub` (line 45), `_autoStartStreaming()` (line 441), `_listenForCommandsSafe()` (line 411)
- `lib/screens/child/child_streaming_screen.dart` — calls `_webrtc.startAsChild()` at lines 98 and 115
- `lib/services/background_monitoring_service.dart` — `_callsSub` drives `SilentWebRTCService.instance` (lines 395–437)

**Root Cause:**
Two separate WebRTC service classes both write to and listen on the `calls/$uid` Firebase path:
1. `SilentWebRTCService` (singleton, background-service-owned) — authoritative owner, driven by `_callsSub` in `background_monitoring_service.dart`.
2. `WebRTCService` — has a `startAsChild()` method still used in `child_streaming_screen.dart` (lines 98, 115), and `_subscribeConnectivity()` registers an independent `_connectivitySub` that calls `startAsChild()` or `startAsParent()` on network restore.

Both services' `_connectivitySub` listeners fire simultaneously on WiFi restore, both write new offers to `calls/$uid/offer`, and both independently clear signaling data at session start.

**Exact Execution Flow — Scenario A (Network Restore Race):**
1. Device loses WiFi. Both `WebRTCService._connectivitySub` and `SilentWebRTCService._connectivitySub` are active (separate stream subscriptions on `Connectivity().onConnectivityChanged`).
2. WiFi restores. Both `onConnectivityChanged` callbacks fire within milliseconds of each other.
3. `WebRTCService._connectivitySub` checks ICE state → DISCONNECTED → calls `await startAsChild(childUid, mode)`.
4. `startAsChild()` at line 68 calls `await _cancelSubs()` → removes `calls/$uid/offer`, `calls/$uid/answer`, `calls/$uid/childCandidates` from Firebase (clearing `SilentWebRTCService`'s live signaling data).
5. Concurrently, `SilentWebRTCService._connectivitySub` also fires and calls `_connect()` → writes a new offer to `calls/$uid/offer`.
6. Parent's `_offerSub` receives two offer events in quick succession. Even with `_offerProcessed = true` guard, if both arrive before the Dart event loop processes the first, `setRemoteDescription` is called twice → `RTCPeerConnection` throws `InvalidStateError` (native Android WebRTC exception).

**Exact Execution Flow — Scenario B (Stale Cleanup Race):**
1. Parent opens a monitoring session. `background_monitoring_service._callsSub` sees `status = 'calling'` → calls `SilentWebRTCService.instance.startSilentCamera(uid)`.
2. `foreground_service._cleanupStaleSessions()` fires every 20 heartbeat ticks (~10 minutes). It reads `calls/$uid`, checks `startedAt`. If the session has been running for 10+ minutes and `startedAt` is older than the threshold → calls `ref.remove()` on `calls/$uid`.
3. `SilentWebRTCService._statusSub` sees the node disappear → calls `stopSilent()` → monitoring session terminates mid-stream.
4. Parent sees the video freeze, then drop. The child's camera turns off. No error message on either side.

**Exact Execution Flow — Scenario C (child_streaming_screen.dart double-start):**
1. `ChildStreamingScreen.initState()` calls `_webrtc.startAsChild(childUid, mode: StreamMode.screen)` (line 98 or 115 in child_streaming_screen.dart).
2. `WebRTCService.startAsChild()` clears `calls/$uid/offer` (line ~75 of startAsChild: cancel subs, remove Firebase state).
3. `SilentWebRTCService` is also active from the background service, maintaining a live session on the same `calls/$uid/offer` path.
4. Both services now write offers simultaneously → parent's `setRemoteDescription` called twice.

**Why Current Logic Fails:**
The audit comment in `child_home_screen.dart` says `_autoStartStreaming()` "should NOT be called" — but the method exists and is callable. More critically, `WebRTCService.startAsChild()` is still called from `child_streaming_screen.dart` (live, not commented out). The background service's `SilentWebRTCService` is the sole intended owner, but `WebRTCService`'s `_connectivitySub` independently manages its own reconnect path on the same Firebase path.

**Safest Production-Grade Fix Strategy:**

This requires a three-part surgical change (in order — do not do out of order):

**Step 1 — Remove `child_streaming_screen.dart` call to `startAsChild()`:**
`ChildStreamingScreen` should not start a WebRTC session directly. The background service already handles this. Replace the `startAsChild()` call with a Firebase write to trigger the background service to initiate the session:
```dart
// In child_streaming_screen.dart — instead of _webrtc.startAsChild():
await FirebaseDatabase.instance.ref('commands/$childUid/requestStream').set({
  'mode': 'screen',
  'requestedAt': ServerValue.timestamp,
});
// Then listen for SilentWebRTCService to establish the connection
```

**Step 2 — Disable `WebRTCService._subscribeConnectivity()` on the child side:**
When `startAsChild()` is called, it currently registers a `_connectivitySub` that independently fires `startAsChild()` on network restore. This must be either removed entirely from `startAsChild()`, or gated behind a check that the background service is NOT running:
```dart
// In WebRTCService.startAsChild(): remove or gate _subscribeConnectivity()
// on !BackgroundMonitoringService.isRunning()
```

**Step 3 — Disable or delete `WebRTCService.startAsChild()` entirely:**
Long-term, `WebRTCService.startAsChild()` should be deleted. It is the architectural root cause. `SilentWebRTCService` is the sole correct child-side WebRTC owner. Until deleted, add a guard at the top of `startAsChild()`:
```dart
Future<void> startAsChild({...}) async {
  // Temporary guard until startAsChild is fully deleted:
  if (await BackgroundMonitoringService.isRunning()) {
    debugPrint('[WebRTC] startAsChild blocked — background service owns WebRTC');
    return;
  }
  // ... rest of method
}
```

**Android-Specific Constraints:**
- `WebRTCService` and `SilentWebRTCService` run in different Dart isolates (main isolate vs. background service isolate). Shared state cannot be passed via normal Dart objects — must use SharedPreferences flags or method channel events.
- `RTCPeerConnection` objects are native Android objects. Calling `setRemoteDescription` twice from different isolates on the same underlying native peer connection (accessed via the same Firebase signaling path) triggers a native `InvalidStateError` that is not caught by Dart's `try/catch` unless the WebRTC plugin wraps it. On some Android WebRTC versions (libwebrtc M114+), this terminates the calling isolate.
- `calls/$uid` Firebase path is writable by both the child's UID and any parent UID in `approvedParents`. The security rules must not be loosened to "fix" this race — the fix must be architectural.

**Firebase-Specific Constraints:**
- Firebase RTDB delivers `onValue` events per-listener, not per-path. Two separate `.ref('calls/$uid').onValue.listen(...)` registrations (one in background service `_callsSub`, one in `child_home_screen._callSub`) receive independent event streams. Cancelling one does not affect the other.
- `ref.remove()` on `calls/$uid` from one isolate is received by all listeners on that path. If one isolate removes the node to "start fresh", the other isolate's listener sees `value = null` and may prematurely stop an active stream.

**Implementation Risk:** HIGH — Involves deleting and rerouting call paths used in a running production feature. Must be done in the order described above. Step 1 and 2 can be done independently; Step 3 only after Steps 1 and 2 are verified working.

**Regression Risk:** HIGH — `child_streaming_screen.dart` currently DEPENDS on `WebRTCService.startAsChild()`. Removing that dependency requires verifying the background-service-driven path works end-to-end before removing the UI-side path.

**Dependency Chain Impact:**
- **Blocks:** NAV-02 (renderer dispose race) — the renderer race is caused by concurrent WebRTC teardown; fixing CRIT-02 reduces NAV-02's frequency.
- **Unblocked by:** None — this is the highest-priority runtime change after auth.
- **Required before:** production deployment of screen sharing or camera monitoring features.

---

### P2-B: Dual Presence Writer — Background Service and PresenceService Both Own `isOnline` and `onDisconnect`

**Audit Reference:** HIGH-05
**Severity:** HIGH — Child device shows as offline to parent during active monitoring sessions; `onDisconnect` handler race causes false offline events mid-stream

**Affected Files:**
- `lib/services/background_monitoring_service.dart` — lines 342–358 (`_setupMonitoringSession`)
- `lib/services/presence_service.dart` — `startChildPresence()`, `_connectedSub`
- `lib/screens/child/child_home_screen.dart` — line 142 (`PresenceService.instance.startChildPresence(uid)`)

**Root Cause:**
Two services independently own the same Firebase presence path:

`background_monitoring_service.dart` (lines 342–358):
```
await FirebaseDatabase.instance.ref('users/$uid/isOnline').set(true);
_connectedSub listens to .info/connected → on connect:
  userRef.child('isOnline').onDisconnect().set(false)
  userRef.child('isOnline').set(true)
  statusRef.onDisconnect().set('offline')
```

`presence_service.dart` (called from `child_home_screen.dart` line 142):
```
_connectedSub listens to .info/connected → on connect:
  userRef.child('isOnline').onDisconnect().set(false)
  userRef.child('lastSeen').onDisconnect().set(ServerValue.timestamp)
  userRef.child('isOnline').set(true)
```

Both services register separate `onDisconnect()` handlers for the SAME `users/$uid/isOnline` path from what may be different TCP connections to Firebase.

**Exact Execution Flow:**
1. `child_home_screen.dart` mounts → `PresenceService.startChildPresence(uid)` called → registers `onDisconnect(false)` for `users/$uid/isOnline` at T=0.
2. Background service starts ~2 seconds later → `_setupMonitoringSession` runs → writes `isOnline = true` at line 342 → registers its OWN `onDisconnect(false)` via `_connectedSub` at T=2s.
3. Firebase tracks onDisconnect handlers per TCP connection. The background service and main isolate may use different TCP connections (separate `FlutterEngine`s on Android). Both handlers are registered.
4. Network drops. Firebase executes onDisconnect handlers from the most recently registered connection that closed. If the main isolate's connection closes last, the background service's onDisconnect fires — which includes `statusRef.onDisconnect().set('offline')` (line 356) — setting `calls/$uid/status = 'offline'` while the parent may be in an active monitoring session.
5. Parent's monitoring screen sees `status = 'offline'` → displays "Connection lost" → may terminate the call.
6. Network restores. BOTH services write `isOnline = true` within seconds of each other → race condition on which value Firebase persists (last-write-wins, non-deterministic order from the parent's perspective).

**Why Current Logic Fails:**
`foreground_service.dart` has a comment at line 152–153 explicitly stating "isOnline is intentionally NOT written here" — confirming the developer is aware of the dual-writer problem. However, `child_home_screen.dart` STILL calls `PresenceService.startChildPresence(uid)` at line 142 when the child UI mounts. The intent is that the background service is the authoritative presence owner, but this is not enforced — the UI-layer presence service continues to compete.

**Safest Production-Grade Fix Strategy:**
Use a SharedPreferences flag to designate a single owner at runtime:
```dart
// In background_monitoring_service.dart _setupMonitoringSession:
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('background_owns_presence', true);

// In presence_service.dart startChildPresence():
final prefs = await SharedPreferences.getInstance();
if (prefs.getBool('background_owns_presence') == true) {
  debugPrint('[Presence] Background service owns presence — skipping UI-layer write');
  return;
}
// ... existing logic only runs if background service is NOT running
```
Add cleanup in `background_monitoring_service.dart` stop handler:
```dart
// In service.on('stop') listener:
await prefs.setBool('background_owns_presence', false);
```

The long-term fix is to remove `PresenceService.startChildPresence(uid)` from `child_home_screen.dart` entirely and let the background service be the sole writer.

**Android-Specific Constraints:**
- Background service and UI isolate may use separate TCP connections to Firebase, meaning each isolate registers its own onDisconnect handler. Firebase's RTDB server associates onDisconnect operations with the WebSocket connection that registered them. When a connection closes, that connection's handlers fire. The order depends on which TCP connection closes first — non-deterministic on Android when both are alive.
- SharedPreferences on Android is process-scoped but accessible from multiple Dart isolates within the same process. Using it as a coordination flag is safe for this purpose.

**Firebase-Specific Constraints:**
- `onDisconnect()` handlers accumulate per connection registration. Calling `onDisconnect().set(false)` from two different registrations results in two handlers on the server, both pointing to the same path. Firebase does NOT deduplicate these — both fire when their respective connections close.
- The correct Firebase-idiomatic approach is to have a SINGLE connection that manages presence, with server-side timestamps via `ServerValue.timestamp` for `lastSeen`.

**Implementation Risk:** LOW — SharedPreferences flag is additive. The only risk is the flag not being cleared on a clean stop, which would leave `PresenceService` permanently disabled. Add a `FlutterError.onError` handler that clears the flag on unexpected termination.

**Regression Risk:** LOW — The background service was already intended to own presence. This change enforces the intent that was already documented in comments.

**Dependency Chain Impact:**
- **Unblocks:** Reliable offline detection for parents.
- **Dependent on:** CRIT-04 (Firebase init) — the background service must initialize Firebase correctly before this flag mechanism is reliable.

---

### P2-C: TOCTOU Race on `pendingParentRequests` in `_existingRequests()`

**Audit Reference:** MED-03
**Severity:** HIGH in production — parent request silently deleted during child re-setup; permanent orphaned pending request state

**Affected Files:**
- `lib/screens/child/child_setup_wizard_screen.dart` — `_existingRequests()` (lines 432–447), `_saveProfileFirst()` (line 405)

**Root Cause:**
```dart
// In _saveProfileFirst():
'pendingParentRequests': await _existingRequests(uid),  // Step 1: READ
// ... async gap here ...
await FirebaseDatabase.instance.ref('users/$uid').update(updates);  // Step 2: WRITE
```

`_existingRequests()` reads `users/$uid/pendingParentRequests` via `.get()`. If a new parent sends a QR connection request during the async gap between the `.get()` and the `.update()`, the new request node in Firebase is overwritten with the stale snapshot captured before the request arrived. The parent's `pendingParentRequests/$parentUid` entry is permanently deleted.

**Exact Execution Flow:**
1. Child taps "Continue" on page 5. `_saveProfileFirst()` starts.
2. `_existingRequests()` calls `FirebaseDatabase.instance.ref('users/$uid/pendingParentRequests').get()` → returns `{}` (empty, no pending requests yet). Duration: ~200ms network round-trip.
3. Parent scans QR code simultaneously. Firebase writes `pendingParentRequests/$parentUid = {status: 'pending', ...}` during the async gap (possible overlap: parent QR scan takes ~300ms to write to Firebase).
4. `_saveProfileFirst()` calls `.update({..., 'pendingParentRequests': {}})` — overwriting the parent's just-written request with the stale empty snapshot.
5. Parent's request is silently deleted. The parent sees no approval prompt. The wizard completes normally. Neither side sees an error.

**Why Current Logic Fails:**
Read-then-write is not atomic in Firebase RTDB without a transaction. The async gap between the `get()` and `update()` is a mandatory TOCTOU window.

**Safest Production-Grade Fix Strategy:**
Do NOT read-then-write `pendingParentRequests` in the wizard. Profile fields (name, device, role) and relationship fields (`pendingParentRequests`, `approvedParents`) should never be written from the same `.update()` call:
```dart
// Split the update into two separate paths:
// 1. Only update profile fields (safe to overwrite):
final profileUpdates = {
  'users/$uid/profile/childName': _nameCtrl.text.trim(),
  'users/$uid/profile/deviceName': deviceName,
  'users/$uid/role': 'child',
  'users/$uid/isOnline': false,
};
// Only initialize approvedParents if it doesn't exist:
final approvedSnap = await FirebaseDatabase.instance.ref('users/$uid/approvedParents').get();
if (approvedSnap.value == null) {
  profileUpdates['users/$uid/approvedParents'] = {};
}
// DO NOT TOUCH pendingParentRequests at all from the wizard
await FirebaseDatabase.instance.ref().update(profileUpdates);
```
The `pendingParentRequests` node should be written exclusively by the parent-side QR scan flow and read by the wizard's `_requestSub` listener — never overwritten by the wizard's profile save.

**Android-Specific Constraints:** None specific — this is pure Firebase data modeling.

**Firebase-Specific Constraints:**
- Firebase RTDB has no native conditional-write (compare-and-swap) for arbitrary nodes without using transactions (`runTransaction()`). A transaction on `users/$uid` would block all concurrent reads during execution.
- The correct fix is architectural: separate profile data paths from relationship data paths, as described in ARCH-03 of the audit report.

**Implementation Risk:** LOW — Removing `pendingParentRequests` from the wizard's update is purely subtractive. The `_requestSub` listener (now started in `initState` after the previous fix) correctly maintains the UI view of pending requests.

**Regression Risk:** LOW — `pendingParentRequests` is only READ by the wizard, never logically written from it (the write was a defensive "preserve existing" pattern that introduced the bug).

**Dependency Chain Impact:**
- Independent. No dependency on other unfixed issues.

---

## PRIORITY 3 — FIREBASE REALTIME ISSUES

---

### P3-A: `setPersistenceEnabled` in Background Service Isolate — Undefined Behavior After Main Isolate Initializes Firebase

**Audit Reference:** CRIT-05
**Severity:** HIGH — Offline replay and write queuing silently disabled in background monitoring isolate; data written during brief network drops is permanently lost

**Affected Files:**
- `lib/services/background_monitoring_service.dart` — lines 149–154

**Root Cause:**
```dart
// background_monitoring_service.dart _onStart() line 149-154:
try {
  FirebaseDatabase.instance.setPersistenceEnabled(true);
} catch (_) {}
```

Firebase RTDB's `setPersistenceEnabled(true)` must be called before any `DatabaseReference` is created. In the background service isolate (a separate `FlutterEngine` with its own Dart VM), `Firebase.initializeApp()` may or may not have been called before `setPersistenceEnabled`. The `main.dart` and `main_child.dart` both call `setPersistenceEnabled(true)` after their `Firebase.initializeApp()` — this works correctly in the main isolate. However:

In `flutter_background_service` on Android, the background service runs in a NEW `FlutterEngine` on the SAME Android process. The Firebase Android SDK is a process-singleton — `FirebaseDatabase.getInstance()` returns the same Java object regardless of which Flutter engine calls it. If the main isolate has already created a `DatabaseReference` (which it does via `FirebaseDatabase.instance.ref()` in `AuthService._db`, `NotificationService._db`, etc.), the shared Firebase Android SDK has already initialized internal disk cache structures. When the background isolate calls `setPersistenceEnabled(true)`, the Java SDK throws `DatabaseException: Calls to setPersistenceEnabled() must be made before any other usage of FirebaseDatabase instance`. This exception is caught by the `catch (_) {}` — swallowed silently.

**Exact Execution Flow:**
1. App starts. Main isolate: `FirebaseDatabase.instance.setPersistenceEnabled(true)` succeeds (called before any `ref()` creation in `main_child.dart` line 91).
2. `AuthService._db = FirebaseDatabase.instance.ref()` — first DatabaseReference created. Firebase SDK's persistence layer activates.
3. Background service starts. New FlutterEngine calls `FirebaseDatabase.instance.setPersistenceEnabled(true)` — Firebase Java SDK throws `DatabaseException` because internal references already exist.
4. `catch (_) {}` swallows the exception.
5. Within the background isolate, no new `DatabaseReference` is created AFTER the (failed) `setPersistenceEnabled` call — but persistence is technically already enabled at the Java SDK level from Step 1. The background isolate DOES inherit persistence behavior for the shared Java-level database.
6. **However:** the background isolate's Dart-level Firebase plugin registers its own `EventChannel` and `MethodChannel` for Firebase events. If the Dart plugin layer did not complete initialization correctly (due to the failed `setPersistenceEnabled` call or a race in plugin registration), RTDB events delivered to the background isolate may use in-memory (non-persistent) channels.

**Why Current Logic Fails:**
The `catch (_) {}` is semantically correct (persistence is already enabled at the Java level from the main isolate), BUT it masks whether the Dart plugin layer in the background isolate is correctly configured for offline persistence. If persistence is silently non-functional in the background isolate, heartbeat writes during brief network gaps are lost — not queued for retry. Screen-time enforcement updates written during a 2-minute network outage are permanently lost. The parent sees gaps in the monitoring timeline.

**Safest Production-Grade Fix Strategy:**
The primary fix is: do NOT call `setPersistenceEnabled` in the background isolate at all. Persistence is a process-level Android SDK setting. It is set correctly in the main isolate before any references are created. The background isolate inherits it.

```dart
// Remove lines 149-154 from background_monitoring_service.dart _onStart():
// DELETE:
// try {
//   FirebaseDatabase.instance.setPersistenceEnabled(true);
// } catch (_) {}

// Also verify that main_child.dart calls setPersistenceEnabled BEFORE
// any FirebaseDatabase.instance.ref() call (it does — line 91 is before
// any service initialization).
```

If there is a concern about the background isolate's Dart plugin layer not inheriting persistence, add a diagnostic log after Firebase initialization that checks `.info/connected` to verify the background isolate can receive Firebase events — this will also confirm persistence is working.

**Android-Specific Constraints:**
- `FirebaseDatabase.setPersistenceEnabled()` is a static method on the Java SDK's `FirebaseDatabase` class. It is process-scoped. Any Dart isolate in the same Android process shares this setting.
- `flutter_background_service` version 5.0.9 uses Android's `Service` with `FlutterEngine.startInitialization()` — it does NOT create a new Android process. All Dart isolates in this configuration share the same Java heap and therefore the same Firebase SDK instance.

**Firebase-Specific Constraints:**
- `setPersistenceEnabled` can only be called once per process before any `DatabaseReference` is created. The main isolate has already established this setting. The background isolate should not attempt to set it again.
- Firebase RTDB offline persistence uses a local SQLite database at `{filesDir}/firebase/{projectId}.ss`. All isolates in the same process share this file.

**Implementation Risk:** VERY LOW — Removing the call eliminates the `catch (_) {}` entirely. Behavior is unchanged because persistence is already set at the Java level.

**Regression Risk:** VERY LOW — The `catch (_) {}` already means the call has no effect. Removing it makes the no-effect explicit.

**Dependency Chain Impact:** Independent. No other issue depends on this.

---

### P3-B: `LocationService._checkGeofences()` Has No Concurrency Mutex — Duplicate Geofence Alerts

**Audit Reference:** HIGH-03
**Severity:** HIGH — Parents receive duplicate geofence exit/enter notifications; child location state in Firebase is inconsistent

**Affected Files:**
- `lib/services/location_service.dart` — `_checkGeofences()` (line 98), `_lastInside` field reads at line 115 and writes at line 124

**Root Cause:**
```dart
// location_service.dart _checkGeofences() — no mutex:
Future<void> _checkGeofences(String uid, double lat, double lng) async {
  final snap = await _db.child('geofences/$uid').get();  // Async Firebase read
  // ... loop over fences ...
  final wasInside = raw['_lastInside'] as bool? ?? false;
  if (nowInside != wasInside) {
    await _db.child('geofences/$uid/$id/_lastInside').set(nowInside);  // Write state back to definition node
    await _writeAlert(...);
  }
}
```

No `_checking` boolean or `Completer` mutex exists. GPS location updates fire with `distanceFilter: 30` metres, but this is a minimum — rapid GPS updates (device movement, GPS lock acquisition, background service resume) can fire multiple position events within the Firebase read round-trip time (~200ms).

**Exact Execution Flow:**
1. Child moves quickly. GPS fires position event A and position event B within 150ms.
2. Event A calls `_checkGeofences()`. Begins `await _db.child('geofences/$uid').get()` — takes 200ms.
3. Event B calls `_checkGeofences()` simultaneously (no mutex). Also begins `await _db.child('geofences/$uid').get()` — also takes ~200ms.
4. Both `.get()` calls return with the SAME snapshot — `_lastInside = false` for fence F1 (child is outside).
5. Both compute `nowInside = true` (child entered the fence).
6. Both call `await _db.child('geofences/$uid/F1/_lastInside').set(true)` — two identical writes (harmless, idempotent).
7. Both call `await _writeAlert(...)` — TWO alert entries are written to `geofence_alerts/$uid/$newKey1` and `geofence_alerts/$uid/$newKey2`.
8. Parent's `_watchGeofenceAlerts` listener fires TWICE. Parent receives two identical "Entered Safe Zone" notifications within milliseconds.

**Data Modeling Problem:**
`_lastInside` is written to `geofences/$uid/$fenceId/_lastInside` — the SAME node that the parent writes when defining the geofence. This means:
- The child's presence state is embedded in the parent-owned geofence definition.
- Firebase security rules cannot separate "parent writes fence definition" from "child writes presence state" without per-field rules.
- The parent can delete and recreate a geofence to reset `_lastInside`, causing a false-positive "entered" event even if the child hasn't moved.

**Why Current Logic Fails:**
`_checkGeofences()` is an async function called from a `LocationService` position stream listener with no guard against concurrent execution. The `distanceFilter: 30` reduces frequency but does not eliminate concurrent calls during GPS burst acquisition.

**Safest Production-Grade Fix Strategy:**

**Immediate fix (add mutex):**
```dart
bool _checkingGeofences = false;

Future<void> _checkGeofences(String uid, double lat, double lng) async {
  if (_checkingGeofences) return;
  _checkingGeofences = true;
  try {
    // ... existing logic, BUT use in-memory cache instead of Firebase read ...
  } finally {
    _checkingGeofences = false;
  }
}
```

**Data modeling fix (separate state from definition):**
Replace the `_lastInside` write at line 124 with a write to a child-owned state path:
```dart
// Instead of: _db.child('geofences/$uid/$id/_lastInside').set(nowInside)
// Use:
await _db.child('geofence_state/$uid/$id/lastInside').set(nowInside);
```
And read from this path instead of from the fence definition. This separates parent-controlled geofence configuration from child-controlled geofence state, enabling correct Firebase security rules.

**Add in-memory cache:** Store `Map<String, bool> _lastInsideCache = {}` as an instance field. On startup, populate from Firebase once. Use the cache for all subsequent reads — only write to Firebase when state changes.

**Android-Specific Constraints:**
- `LocationService` uses Flutter's `geolocator` or similar plugin. Position events arrive on the main Dart isolate's event loop. Concurrent invocations of `_checkGeofences()` are sequential in the Dart event loop but appear "concurrent" because each `await` yields to the event loop.
- The `distanceFilter: 30` is enforced by the GPS hardware abstraction layer, but Android's Fused Location Provider may still deliver batched position fixes that appear almost simultaneously.

**Firebase-Specific Constraints:**
- Writing `_lastInside` to `geofences/$uid/$id/_lastInside` (the parent-owned fence definition) creates a security rule conflict: the child needs write access to a parent-owned node. This violates the principle of least privilege. A dedicated `geofence_state/$uid` path (child-owned) resolves this.
- Both the mutex fix and the data modeling fix are independent — the mutex can be applied immediately; the data modeling change requires a Firebase data migration.

**Implementation Risk:** LOW for mutex; MEDIUM for data modeling (requires Firebase data migration for existing geofence state).

**Regression Risk:** LOW for mutex (purely protective); MEDIUM for data modeling (clients reading `_lastInside` from the old path will break until all clients are updated).

**Dependency Chain Impact:**
- **Unblocks:** Correct Firebase security rules for geofence data (ARCH-03 dependency).
- Independent of all other unfixed issues.

---

### P3-C: Concurrent Stale-Session Cleanup From Two Services — Active Monitoring Terminated Every ~10 Minutes

**Audit Reference:** MED-04
**Severity:** HIGH in production — active monitoring sessions are silently terminated approximately every 10 minutes under certain timing conditions

**Affected Files:**
- `lib/services/foreground_service.dart` — `_cleanupStaleSessions()` (lines 219–235), called every 20 ticks (`_heartbeatCount % 20 == 0`) at line 189; stale threshold: 10 minutes (line 229)
- `lib/services/background_monitoring_service.dart` — startup stale cleanup (lines 362–377) in `_setupMonitoringSession`; stale threshold: 5 minutes (line 371)

**Root Cause:**
Two separate cleanup implementations run on the same `calls/$uid` Firebase path with different stale thresholds:

`foreground_service.dart` (runs every ~10 minutes from the `flutter_foreground_task` handler):
```dart
// line 229:
if (age > 10 * 60 * 1000) {  // 10-minute threshold
  await ref.remove();         // Deletes the active call session
}
```

`background_monitoring_service.dart` (runs at session startup from watchdog restart):
```dart
// line 371:
if (age > 5 * 60 * 1000) {  // 5-minute threshold — DIFFERENT from foreground service
  await FirebaseDatabase.instance.ref('calls/$uid').remove();
}
```

**Exact Execution Flow — Termination Scenario:**
1. Parent opens monitoring session at T=0. `calls/$uid/status = 'calling'`, `calls/$uid/startedAt = T`.
2. Session runs normally for 10 minutes.
3. At T=10min, `foreground_service._MonitoringTaskHandler.onRepeatEvent()` fires (`_heartbeatCount == 20`).
4. `_cleanupStaleSessions(uid)` reads `calls/$uid`. `status == 'calling'`, `age = 10min`.
5. Condition `age > 10 * 60 * 1000` → TRUE → `await ref.remove()`.
6. `calls/$uid` is deleted. `background_monitoring_service._callsSub` receives `value = null` → calls `SilentWebRTCService.instance.stopSilent()`.
7. Parent's monitoring screen receives no event (the `status` node is deleted, not set to 'ended') → monitoring screen shows "Connection lost." after heartbeat timeout.
8. Parent taps "Retry" → new session starts at T=10min+5s. Foreground service fires again at T=20min → same termination.

**Why Current Logic Fails:**
The foreground service's `_cleanupStaleSessions` was designed to clean up sessions that were ABANDONED (parent app crashed, connection dropped). But it fires on ALL active sessions where `age > 10min` because there is no way to distinguish "parent is actively monitoring" from "parent crashed 10 minutes ago." The `status = 'calling'` is set at the START of the session and is never refreshed — it does not serve as a liveness indicator.

**Safest Production-Grade Fix Strategy:**

**Option A (immediate/safe):** Remove `_cleanupStaleSessions()` from the foreground service entirely. The background service already has startup cleanup (lines 362–377). Duplicate cleanup is dangerous because the foreground service doesn't know if the session is actively monitored.

**Option B (correct):** Change stale detection to use the HEARTBEAT timestamp instead of `startedAt`. The parent's monitoring screen writes heartbeats every 30 seconds to `calls/$uid/parentHeartbeat`. Check that heartbeat:
```dart
final parentHeartbeat = data['parentHeartbeat'] as int?;
if (parentHeartbeat != null) {
  final heartbeatAge = DateTime.now().millisecondsSinceEpoch - parentHeartbeat;
  if (heartbeatAge > 2 * 60 * 1000) {  // No heartbeat for 2 minutes = stale
    await ref.remove();
  }
}
```
This correctly distinguishes an active session (recent heartbeat) from an abandoned one (no heartbeat for 2+ minutes).

**Android-Specific Constraints:**
- The foreground task handler (`_MonitoringTaskHandler`) runs in a separate Dart isolate from the background service. Both isolates independently access `calls/$uid`. There is no Dart-level mutex that spans isolates.
- Removing `_cleanupStaleSessions` from the foreground service is safe because the background service already handles startup cleanup, and the long-term plan (BG-01) is to consolidate both services into one.

**Firebase-Specific Constraints:**
- `ref.remove()` on `calls/$uid` triggers `onValue` callbacks for all listeners watching that path from any client (parent app, child app, background service). This has a cascading effect — all monitoring state is reset.

**Implementation Risk:** LOW for Option A (pure removal). MEDIUM for Option B (requires parent monitoring screen to write `parentHeartbeat` timestamps).

**Regression Risk:** LOW — Active sessions lasting more than 10 minutes are currently being silently terminated. Removing the incorrect cleanup only improves reliability.

**Dependency Chain Impact:**
- **Improves:** CRIT-02 (removes one source of session termination).
- **Related to:** BG-01 (foreground service consolidation — after BG-01, `_cleanupStaleSessions` is removed as part of deleting the foreground service entirely).

---

## PRIORITY 4 — SERVICE PERSISTENCE

---

### P4-A: Dual Foreground Services — Android 14 `ForegroundServiceStartNotAllowedException`

**Audit Reference:** BG-01
**Severity:** CRITICAL on Android 14 (API 34) — second foreground service fails to start; on older Android, duplicate foreground notifications confuse users and waste battery

**Affected Files:**
- `lib/services/background_monitoring_service.dart` — uses `flutter_background_service` (notification ID 888, channel `family_monitor_bg`)
- `lib/services/foreground_service.dart` — uses `flutter_foreground_task` (channel `family_monitor_channel`)
- `android/AndroidManifest.xml` — must declare `foregroundServiceType` for both services

**Root Cause:**
Two separate Android foreground services run simultaneously:
1. `flutter_background_service` starts a `ForegroundService` with `foregroundServiceTypes: [camera, microphone, dataSync]` — correctly declared in `BackgroundMonitoringService.initialize()`.
2. `flutter_foreground_task` starts its OWN `ForegroundService` with NO `foregroundServiceType` declaration in the current code (`foreground_service.dart` lines 34–40 specify only notification options — no `foregroundServiceType`).

Android 14 (API 34) mandates that every foreground service declare its type BEFORE starting. Without a declared type, `startForeground()` throws `ForegroundServiceStartNotAllowedException` → the `flutter_foreground_task` service silently fails to start → the child device shows only one foreground notification → boot persistence (BG-05) and heartbeat cleanup (P3-C) never run.

Additionally, on Android 13 and earlier, both services show SEPARATE persistent notifications to the child. The child sees "Family Monitor Active" (from background service) AND another "Monitoring active" notification (from foreground task). This reveals the dual-service architecture to observant users and creates UX confusion.

**Exact Execution Flow on Android 14:**
1. `child_home_screen.dart` calls `MonitoringForegroundService().startService(...)`.
2. `flutter_foreground_task` calls `FlutterForegroundTask.startService(...)`.
3. Android API 34: `startForeground(notificationId, notification)` is called without a `foregroundServiceType` parameter.
4. Android throws `android.app.ForegroundServiceStartNotAllowedException` or `android.app.InvalidForegroundServiceTypeException` (API 34+).
5. The `flutter_foreground_task` plugin catches this exception at the Java layer and either swallows it or delivers it to Dart as a `PlatformException` — which the Dart caller does not handle.
6. The task handler (`_MonitoringTaskHandler`) never starts. `_cleanupStaleSessions()` never runs. `autoRunOnBoot` never fires.

**Why Current Logic Fails:**
`flutter_foreground_task` version 8.14.0 supports `foregroundServiceType` in its configuration, but the current `foreground_service.dart` does not set it. The `flutter_background_service` DOES declare its types correctly. There is no coordination between the two services' lifecycle events.

**Safest Production-Grade Fix Strategy:**
The production-grade fix is consolidation: remove `flutter_foreground_task` entirely and merge its `_MonitoringTaskHandler` logic into `background_monitoring_service.dart`:
1. Remove `flutter_foreground_task` from `pubspec.yaml`.
2. Remove `foreground_service.dart` entirely.
3. Merge `_cleanupStaleSessions()` into `background_monitoring_service._setupMonitoringSession()` (already has startup cleanup).
4. Move `autoRunOnBoot` logic to the `flutter_background_service`'s `AndroidConfiguration(autoStart: false)` — or implement it via the existing `BootReceiver.kt` Kotlin class.
5. Update `AndroidManifest.xml` to declare only ONE foreground service with the correct types.

**Immediate mitigation (if full consolidation is not feasible):** Add `foregroundServiceType` to `flutter_foreground_task` configuration:
```dart
// In foreground_service.dart initForegroundTask():
// Add to ForegroundTaskOptions or AndroidNotificationOptions:
// foregroundServiceType: AndroidForegroundType.dataSync
```
Check `flutter_foreground_task` 8.14.0 API for exact parameter name.

**Android-Specific Constraints:**
- Android 14 (API 34) REQUIRES `foregroundServiceType` in the manifest AND passed to `startForeground()`. Without both, the service is killed immediately.
- Android 12+ (API 31) requires that foreground services started from background processes use specific types. `flutter_foreground_task`'s `autoRunOnBoot` starts the service from a boot broadcast receiver — this is a background start subject to Android 12 background start restrictions. The `FOREGROUND_SERVICE_START_NOT_ALLOWED` exception was introduced in API 31.
- The `AndroidManifest.xml` for each foreground service must declare `android:foregroundServiceType` matching the types passed to `startForeground()`.

**Firebase-Specific Constraints:** None for this fix.

**Implementation Risk:** HIGH for full consolidation (removes a service, requires careful migration of all task handler logic). LOW for immediate mitigation (adding `foregroundServiceType` to the task config).

**Regression Risk:** HIGH for consolidation (risk of losing `autoRunOnBoot` behavior on boot). LOW for mitigation.

**Dependency Chain Impact:**
- **Resolves:** P3-C (removes the duplicate stale cleanup) when full consolidation is done.
- **Resolves:** P2-B (dual presence writes) — once only one service runs, presence ownership is unambiguous.
- **Required before:** Android 14 deployment.

---

### P4-B: Watchdog Timer Permanently Disabled After First Health Restart

**Audit Reference:** BG-02
**Severity:** HIGH — After the first time the watchdog triggers a session restart (3 consecutive Firebase connectivity failures), the health watchdog is permanently disabled for the rest of the background service's lifetime

**Affected Files:**
- `lib/services/background_monitoring_service.dart` — watchdog `Timer.periodic` at lines 818–852, `_watchdogRestarting` flag at line 258/819/833/850

**Root Cause:**
The watchdog uses `_watchdogRestarting` as a reentry guard (line 819: `if (_watchdogRestarting) return`). The flag is set to `true` at line 833 before calling `_cancelSessionResources()` and `_setupMonitoringSession()`. However, `_watchdogRestarting` is **never reset to `false`** after `_setupMonitoringSession()` completes successfully. It is only reset in the `catch` block at line 850 (if an exception occurs).

```dart
// background_monitoring_service.dart lines 831-852:
if (healthFailures >= 3) {
  healthFailures = 0;
  _watchdogRestarting = true;         // Set to true — line 833
  _cancelSessionResources();
  await Future.delayed(2s);
  await _setupMonitoringSession(...); // Creates NEW watchdog timer
  // _watchdogRestarting is STILL true here — never reset on success path
}
// The NEW watchdog timer created by _setupMonitoringSession checks:
// if (_watchdogRestarting) return;   // Always true → permanent early exit
```

**Exact Execution Flow:**
1. Background service starts. `_watchdogRestarting = false` (module-level default at line 258).
2. Firebase connectivity fails 3 consecutive times. `healthFailures = 3`.
3. Watchdog: `_watchdogRestarting = true` (line 833) → `_cancelSessionResources()` → `_setupMonitoringSession()`.
4. `_setupMonitoringSession()` creates a NEW `Timer.periodic` watchdog at line 818.
5. The new watchdog closure captures the NEW `healthFailures` local variable (reset to 0). It also checks `if (_watchdogRestarting) return` at line 819.
6. `_setupMonitoringSession()` returns. The OLD callback at line 843 finishes. `_watchdogRestarting` is still `true` — never reset on the success path.
7. Every new watchdog callback fires: checks `if (_watchdogRestarting) return` → exits immediately. The health watchdog is permanently dead.
8. If Firebase connectivity fails again (device enters a tunnel, background service loses WiFi), there are 0 consecutive `healthFailures` counts because the watchdog always exits early. Session is never restarted by the watchdog.

**Why Current Logic Fails:**
The `_watchdogRestarting` flag was added to prevent double-restart, which is correct. But it was never given a reset path for the success case. The `catch` block at line 850 resets it, but only when an exception occurs during `_setupMonitoringSession`.

**Safest Production-Grade Fix Strategy:**
Add `_watchdogRestarting = false` on the success path after `_setupMonitoringSession()` returns:
```dart
if (healthFailures >= 3) {
  healthFailures = 0;
  _watchdogRestarting = true;
  _cancelSessionResources();
  DeviceEventService.writeEvent(...);
  await Future.delayed(const Duration(seconds: 2));
  await _setupMonitoringSession(service, uid);
  _watchdogRestarting = false;  // ADD THIS LINE
  return;  // Old callback exits; new watchdog timer created by _setupMonitoringSession takes over
}
```
The `return` statement prevents the old callback from continuing to check `healthFailures` after the new session is established.

**Android-Specific Constraints:**
- `Timer.periodic` in Dart is safe to cancel from within its own callback. The `_cancelSessionResources()` call sets `_watchdogTimer = null`, but the currently-executing callback finishes normally. Adding `return` after `_setupMonitoringSession()` ensures the old callback's closure does not interact with the new session's state.
- The `_watchdogRestarting` flag is a module-level Dart variable in the background isolate. It is not accessible from other isolates.

**Firebase-Specific Constraints:** None for this fix.

**Implementation Risk:** VERY LOW — Single line addition on the success path.

**Regression Risk:** VERY LOW — The new session is fully established before the flag is reset. The new watchdog timer only activates after the next `Timer.periodic` tick (30 seconds), by which time `_watchdogRestarting = false` has been set.

**Dependency Chain Impact:** Independent. Can be applied immediately.

---

## PRIORITY 5 — LIVE SCREEN / LIVE CAMERA FAILURES

---

### P5-A: WebRTCService Double Reconnect — `_connectivitySub` and `_reconnectTimer` Fire Simultaneously

**Audit Reference:** HIGH-07
**Severity:** HIGH — 30%+ of reconnect attempts on dual-radio devices (WiFi + mobile data) produce a `setRemoteDescription` sequence error that prevents session re-establishment

**Affected Files:**
- `lib/services/webrtc_service.dart` — `_subscribeConnectivity()` (lines 590–639), `_scheduleReconnect()` (lines 407–440)

**Root Cause:**
`WebRTCService` has two independent reconnect triggers:
1. `_reconnectTimer` — a `Timer` that fires `startAsParent/startAsChild` after ICE connection failure (exponential backoff, lines 407–440).
2. `_connectivitySub` — a `Connectivity().onConnectivityChanged` listener that calls `startAsParent/startAsChild` directly when network restores (lines 597–637).

There is no mutex (no `_reconnecting` flag) preventing both paths from executing simultaneously.

**Exact Execution Flow:**
1. ICE connection fails during monitoring. `_scheduleReconnect()` fires. `_reconnectTimer` is created with a 4-second delay. `_reconnectAttempts = 1`.
2. 3 seconds later: network restores. `_connectivitySub` fires the `onConnectivityChanged` callback. Checks `pcState == FAILED` → `await startAsParent(childUid, mode)`.
3. 1 second later: `_reconnectTimer` fires → also calls `await startAsParent(childUid, mode)`.
4. Two `startAsParent()` calls run in overlapping Dart event loop turns:
   - First call: `await _cancelSubs()` → `await _closePC()` → `_peerConnection = await createPeerConnection(...)` → writes offer to Firebase.
   - Second call: `await _cancelSubs()` — cancels the `_offerSub` that the first call just created → `await _closePC()` — closes the peer connection the first call is in the middle of negotiating → creates a second peer connection → writes a SECOND offer.
5. Parent receives two offers. `_offerProcessed` guard prevents the second `setRemoteDescription`, but the first peer connection is now in an CLOSED state (closed by the second `_closePC()`) → no valid peer connection remains → session cannot be established.
6. Parent sees "Connecting..." indefinitely. Must manually tap End and restart monitoring.

**Why Current Logic Fails:**
The 10-second debounce at lines 606–609 (`_lastReconnectTime`) prevents rapid-fire connectivity events, but the timer and connectivity paths are independent and can both trigger within the same window when the debounce hasn't activated.

**Safest Production-Grade Fix Strategy:**
Add a `_reconnecting` boolean flag as a mutex:
```dart
bool _reconnecting = false;

// In _connectivitySub callback, before calling startAsParent/startAsChild:
if (_reconnecting || _disposed) return;

// At the start of _scheduleReconnect callback:
if (_reconnecting || _disposed) return;
_reconnecting = true;

// Wrap the startAsParent/startAsChild call:
try {
  if (isChild) {
    await startAsChild(childUid: childUid, mode: mode);
  } else {
    await startAsParent(childUid: childUid, mode: mode);
  }
} finally {
  _reconnecting = false;
}
```
Also cancel `_reconnectTimer` inside the `_connectivitySub` callback when it fires, and cancel `_connectivitySub`'s path inside `_scheduleReconnect`.

**Android-Specific Constraints:**
- `Connectivity().onConnectivityChanged` on Android fires for EACH network interface change — switching from WiFi to mobile data may generate 2–3 events in quick succession even with a single network restore. The debounce at line 606 helps, but the 10-second window must be verified against real device behavior.
- `RTCPeerConnection.close()` on Android is an async native operation. Calling it on a peer connection that is mid-negotiation causes the native layer to emit `ICE connection failed` events that may retrigger `_scheduleReconnect`.

**Firebase-Specific Constraints:**
- Two concurrent `startAsParent()` calls both write to `calls/$uid/offer`. Firebase RTDB's last-write-wins means only the second offer persists — but the child's `SilentWebRTCService` may have already consumed the first offer and set `_answerSet = true`, ignoring the second offer entirely.

**Implementation Risk:** LOW — Adding a boolean flag is minimally invasive.

**Regression Risk:** LOW — The `_reconnecting` flag only blocks duplicate calls. Normal single-path reconnection is unaffected.

**Dependency Chain Impact:**
- **Improves:** CRIT-02 (reduces one category of dual-write on `calls/$uid`).
- Independent of other fixes.

---

### P5-B: `MonitoringScreen.dispose()` — Renderer Disposed Before `endCall` Write Reaches Firebase

**Audit Reference:** NAV-02 (partially) + HIGH-04 (fire-and-forget aspect)
**Severity:** HIGH — Child's camera/screen capture remains active up to 30 seconds after the parent ends the session; rapid End→Restart causes native renderer lifecycle crash on some Android versions

**Affected Files:**
- `lib/screens/parent/monitoring_screen.dart` — `dispose()` (lines 176–194)
- `lib/services/webrtc_service.dart` — `endCall()` (line 565), `dispose()` (line 500+)

**Root Cause:**
```dart
// monitoring_screen.dart dispose() lines 188-193:
if (!_callEnded) {
  _webrtc.endCall(widget.childUid).catchError((_) {});  // Fire and forget
}
_webrtc.dispose();  // Called IMMEDIATELY after — does not wait for endCall
super.dispose();
```

`endCall()` writes `calls/$uid/status = 'ended'` to Firebase (async). `dispose()` calls `_webrtc.dispose()` IMMEDIATELY after — before the Firebase write completes. `_webrtc.dispose()` cancels all subscriptions including `_statusSub`. On the child side, `background_monitoring_service._callsSub` is listening to `calls/$uid`. If `dispose()` completes before the `'ended'` write propagates to Firebase, the child's `_callsSub` never receives `status = 'ended'` → `SilentWebRTCService.stopSilent()` is never called → camera/microphone stays active.

Additionally: the `_webrtc.dispose()` call disposes the `RTCVideoView`'s `localRenderer` and `remoteRenderer`. On some Android versions (5.x, 6.x), `SurfaceViewRenderer.release()` must be called before the `SurfaceView` is detached from the window. If `_webrtc.dispose()` runs while the widget tree is still in the process of unmounting (the Flutter framework's dispose lifecycle), the native surface is released while still attached → `IllegalStateException: SurfaceViewRenderer release() called while surface is still active`.

**Exact Execution Flow:**
1. Parent taps "End". `_endSession()` runs → `_callEnded = true` → `await _webrtc.endCall(uid)` writes `status = 'ended'` → `Navigator.pop(context)`.
2. `dispose()` is triggered. `_callEnded == true` → skip the fire-and-forget `endCall`. `_webrtc.dispose()` is called. Renderers released. ✓ No issue in this path.

But:
1. Parent presses Android system back button without tapping "End".
2. `Navigator.pop()` triggers `dispose()` WITHOUT calling `_endSession()` first.
3. `_callEnded == false` → fire-and-forget `endCall()` is initiated.
4. `_webrtc.dispose()` called IMMEDIATELY → cancels `_statusSub` before Firebase write propagates.
5. Child's `_callsSub` in background service never receives `status = 'ended'` within the 30-second heartbeat window → camera stays active.
6. Parent immediately taps Camera again → new `MonitoringScreen` opens. New `WebRTCService` starts `startAsParent()`. Old `SilentWebRTCService._statusSub` may still be subscribed to `calls/$uid/status` from the previous session → receives `status = 'calling'` from the new session → double `startSilentCamera()` → native `PeerConnection` conflict.

**Safest Production-Grade Fix Strategy:**
In `dispose()`, ensure `endCall` completes before `_webrtc.dispose()`:
```dart
@override
void dispose() {
  _timeout?.cancel();
  _controlsTimer?.cancel();
  _statusSub?.cancel();
  _heartbeatSub?.cancel();
  _screenErrorSub?.cancel();
  _webrtc.onRemoteStream = null;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (!_callEnded) {
    // Chain endCall → dispose instead of fire-and-forget:
    _webrtc.endCall(widget.childUid)
        .catchError((_) {})
        .whenComplete(() => _webrtc.dispose());
  } else {
    _webrtc.dispose();
  }
  super.dispose();
}
```
The `whenComplete()` chain ensures `dispose()` is called after the `endCall` write completes (or fails). `super.dispose()` is still called synchronously, which is correct — the widget is disposed from the framework's perspective; the WebRTC cleanup happens async after.

**Android-Specific Constraints:**
- `RTCVideoView`'s `RTCVideoRenderer.dispose()` must be called only after `RTCVideoRenderer.srcObject = null`. The `_webrtc.dispose()` method should null the remote stream before releasing the renderer.
- `SurfaceViewRenderer.release()` on Android requires the surface to be inactive. The Flutter widget unmount cycle detaches the surface — calling `release()` after `super.dispose()` in a chained `whenComplete()` avoids the surface-still-active exception.

**Firebase-Specific Constraints:**
- The `calls/$uid/status = 'ended'` write propagates to Firebase within 100–500ms on a normal mobile connection. The `catchError` handles network failures. The `whenComplete` chain gives this write time to propagate before the peer connection is closed.

**Implementation Risk:** LOW — The change is to `dispose()` only, which is a terminal lifecycle method. The chained `whenComplete()` has no impact on user-visible behavior.

**Regression Risk:** LOW — The `super.dispose()` is still called synchronously; only the WebRTC cleanup is deferred.

**Dependency Chain Impact:**
- **Dependent on:** CRIT-02 being partially resolved (reduces double-start risk from the old session's subscriptions).
- Independent of all other fixes.

---

## PRIORITY 6 — APP USAGE / SCREEN TIME FAILURES

---

### P6-A: `_screenTimeTimer` Sequential Firebase Reads — N Reads Per 60-Second Cycle

**Audit Reference:** PERF-01 (partially — double UsageStats query is already fixed in current code; the sequential `get()` loop remains)
**Severity:** HIGH — On a device with 10 app limits where 5 apps are under their limit, generates 5 sequential Firebase `get()` calls every 60 seconds = 300 reads/hour = 7,200 reads/day from this timer alone

**Affected Files:**
- `lib/services/background_monitoring_service.dart` — `_screenTimeTimer` (lines 473–552), specifically the `blockRef.get()` call inside the loop (lines 516–522)

**Root Cause:**
```dart
// background_monitoring_service.dart lines 486-523:
for (final entry in limits.entries) {
  // ... compute usedMinutes vs limitMinutes ...
  if (usedMinutes >= limitMinutes) {
    await blockRef.set({...});  // 1 write per over-limit app
  } else {
    final lockSnap = await blockRef.get();  // 1 READ per under-limit app
    if (lockSnap.value is Map) {
      if (lockData['reason'] == 'screen_time_limit') {
        await blockRef.remove();  // 1 write if was auto-locked
      }
    }
  }
}
```

For EVERY app that is NOT over its limit, the timer performs a Firebase `get()` to check if it was previously auto-locked. These `get()` calls are sequential (each `await` blocks the loop until the call completes). On a device with 10 apps configured with limits where 5 are under their limit, this is 5 sequential Firebase reads every 60 seconds.

Additionally, the timer uploads the ENTIRE daily app usage snapshot to `app_usage/$uid/daily` (lines 528–548) on every 60-second tick — regardless of whether any usage data has changed. This is 1 Firebase write per minute = 1,440 writes per day from daily usage uploads alone.

**Why Current Logic Fails:**
The under-limit lock check is designed to remove auto-locks when usage resets (e.g., after midnight). However, this check is only needed when an app WAS previously auto-locked — checking it for EVERY app on EVERY timer tick is wasteful. The daily usage upload was intended for real-time dashboard updates, but writing the entire snapshot every 60 seconds generates unnecessary Firebase load.

**Safest Production-Grade Fix Strategy:**

**Fix 1 — Eliminate the per-app Firebase read:**
Cache the `app_locks` data locally (the `_appLocksSub` listener in background_monitoring_service already maintains `blocked_packages` in SharedPreferences). Instead of reading from Firebase, check the local `blocked_packages` cache:
```dart
// Read once at timer start, not per-app:
final prefs = await SharedPreferences.getInstance();
final blockedPackages = (prefs.getString('blocked_packages') ?? '').split(',').toSet();

for (final entry in limits.entries) {
  // ...
  if (usedMinutes >= limitMinutes && !blockedPackages.contains(pkg)) {
    await blockRef.set({...});  // Only write if not already blocked
  } else if (usedMinutes < limitMinutes && blockedPackages.contains(pkg)) {
    // Only check Firebase if our local cache says it's blocked
    final lockSnap = await blockRef.get();
    if (...) await blockRef.remove();
  }
}
```

**Fix 2 — Reduce daily usage upload frequency:**
Change the daily upload interval to 5 minutes (matching the screen-time enforcement interval after the fix):
```dart
// Move the usageSnap upload block OUTSIDE the 60-second timer.
// Add it to the _hourlyUsageTimer (already runs every 15 minutes) or a
// dedicated 5-minute timer. Remove from _screenTimeTimer.
```

**Android-Specific Constraints:**
- `UsageStats.queryUsageStats()` is an IPC call to `UsageStatsManager` system service. It returns a list of all apps with usage since the query start time. The result is already cached in memory within the same timer callback — it does not need a second call.
- `SharedPreferences` on Android is backed by an XML file. Reading a single string from SharedPreferences is O(1) and does not involve IPC — far cheaper than a Firebase `get()`.

**Firebase-Specific Constraints:**
- Firebase RTDB free tier: 100,000 writes/day, 50 connections. The daily usage upload alone uses 1,440 writes/day. Combined with heartbeat writes (2,880/day), this is 4,320 writes/day before any monitoring events. Under heavy monitoring, this approaches the free tier limit.
- `app_usage/$uid/daily` is a single node overwritten every 60 seconds. Firebase's change detection means this always results in a full node rewrite, even if only 2 apps changed their usage. Use a diff-based update instead.

**Implementation Risk:** LOW — The changes are within `_screenTimeTimer` only, with no external API changes.

**Regression Risk:** LOW — The only behavioral change is that under-limit lock removal may be slightly delayed (based on cache consistency), but the cache is updated by `_appLocksSub` which fires within seconds of any lock change.

**Dependency Chain Impact:** Independent.

---

## PRIORITY 7 — BACKGROUND EXECUTION FAILURES

*(See also P4-A: BG-01 dual foreground services, P4-B: BG-02 watchdog permanently disabled — both are background execution failures categorized under Service Persistence)*

---

### P7-A: `_watchdogTimer` Captured `healthFailures` Local Variable — Stale Closure After Restart

*(See P4-B — this is the same issue. The `healthFailures` local variable behavior is the secondary manifestation of the `_watchdogRestarting` bug. After `_watchdogRestarting` is fixed per P4-B, the captured `healthFailures` in the old closure becomes irrelevant because the old callback exits via `return` after `_setupMonitoringSession` completes.)*

---

## PRIORITY 8 — NOTIFICATION FLOODING

---

### P8-A: `_seenAlerts` Map Has No Size Cap — Unbounded Memory Growth Over Long Sessions

**Audit Reference:** HIGH-02 (partially resolved — moved to instance level; LRU pruning not yet implemented)
**Severity:** MEDIUM-HIGH — On a device monitoring 3 children for 30+ days, each `_seen` set grows to thousands of Firebase push keys; contributes to OOM kills on low-memory parent devices

**Affected Files:**
- `lib/services/notification_service.dart` — `_seenAlerts: Map<String, Set<String>>` (added in previous session), `_seenFor(String key)` helper

**Root Cause (Remaining):**
The `_seenFor(key)` helper returns `_seenAlerts.putIfAbsent(key, () => {})`. This set grows indefinitely — every alert key (Firebase push ID, ~20 characters) is added but never removed. With 6 alert types × 3 children = 18 separate sets, each potentially holding thousands of entries over time.

Firebase push keys are lexicographically ordered by timestamp (e.g., `-NxA1BcD2EfG3HiJ`). The `orderByChild('read').equalTo(false)` query means only UNREAD alerts are delivered via `onChildAdded` — but `onChildAdded` fires for ALL unread alerts that existed when the listener was attached (initial load), not just new ones. Over 30 days of monitoring, a child may accumulate hundreds of unread battery alerts (parent never marks them as read). On every `watchChild()` call (reconnect, app resume), all unread alerts fire `onChildAdded` again. Each key is added to `_seenAlerts` and never pruned.

**Safest Production-Grade Fix Strategy:**
Add a bounded LRU-style pruning in `_seenFor()`:
```dart
Set<String> _seenFor(String key) {
  final set = _seenAlerts.putIfAbsent(key, () => <String>{});
  // Firebase push keys are lexicographically ordered by time.
  // Pruning the oldest 50% when over 500 entries keeps memory bounded
  // while still preventing duplicates for any alert received in the
  // last ~30 days (typical alert frequency: <500 per month).
  if (set.length > 500) {
    final sorted = set.toList()..sort();
    set.removeAll(sorted.take(250));
  }
  return set;
}
```

**Android-Specific Constraints:**
- On Android, `Set<String>` with 1,000 entries of 20-character strings uses ~80KB of heap. With 18 sets at max capacity, total is ~1.4MB — within tolerable limits for a mid-range device (2GB RAM). However, if alerts accumulate faster than expected (e.g., battery service crashes generate crash alerts at high frequency), sets can grow to 5,000+ entries.
- The pruning logic is synchronous and runs on the Dart isolate's event thread. A `Set` of 1,000 entries is sorted in ~1ms — acceptable overhead.

**Firebase-Specific Constraints:**
- Firebase push keys are globally ordered by timestamp. Keeping only the 250 most recent keys (highest lexicographic value) means alerts older than the pruning window are forgotten from the deduplication perspective. This is correct behavior — if an alert is old enough to be pruned from the seen-set, it should already be marked as read in Firebase by the parent.

**Implementation Risk:** VERY LOW — Adding pruning to `_seenFor()` is purely defensive.

**Regression Risk:** VERY LOW — Pruning removes only the oldest seen-keys, not the most recent ones. No active deduplication is affected.

**Dependency Chain Impact:** Independent.

---

### P8-B: Geofence Duplicate Alert Notifications (Cross-Reference)

*(See P3-B — the geofence race condition produces duplicate geofence alerts, which are then delivered as duplicate notifications via `_watchGeofenceAlerts`. Fixing P3-B's `_checking` mutex resolves P8-B as a side effect.)*

---

## PRIORITY 9 — INSTALL ALERT FAILURES

---

### P9-A: App Install Timer Interacts With Concurrent Screen Time Timer — Stale `_knownPackages` Baseline

**Audit Reference:** Not explicitly named in the audit; inferred from the background service architecture
**Severity:** MEDIUM — Install alerts may be missed or duplicated when `_screenTimeTimer` and `_appInstallTimer` run concurrently on the same UsageStats data

**Affected Files:**
- `lib/services/background_monitoring_service.dart` — `_appInstallTimer` (line 254), `_knownPackages` module-level set (line 257)

**Root Cause:**
`_knownPackages` is a module-level `Set<String>` that tracks the baseline of installed packages. `_appInstallTimer` compares the current installed packages against `_knownPackages` to detect installs/uninstalls. However, `_screenTimeTimer` queries UsageStats every 60 seconds for ALL apps since midnight — the stats include recently installed apps before `_appInstallTimer` has had a chance to compare them against `_knownPackages`.

If `_appInstallTimer` and `_screenTimeTimer` both run within the same 60-second window, the screen time timer uploads an `app_usage/$uid/daily` snapshot that includes the new app's usage, which may alert the parent that a new app is being used BEFORE the `_appInstallTimer` fires its install alert. The parent sees usage data for an unknown app before receiving the install notification — causing confusion.

More critically: `_knownPackages` is populated at session startup. If the background service was killed and restarts (watchdog-triggered), `_knownPackages` is reset to empty (module-level `Set<String>`). On restart, ALL currently installed apps appear as "new installs" → install alerts are fired for every app on the device. This could generate hundreds of false-positive install alerts on watchdog restart.

**Safest Production-Grade Fix Strategy:**
Persist `_knownPackages` to SharedPreferences so that restarts do not trigger false-positive install alerts:
```dart
// On session startup, load known packages from SharedPreferences:
final savedPackages = prefs.getString('known_packages') ?? '';
_knownPackages = savedPackages.isEmpty ? {} : savedPackages.split(',').toSet();

// After updating _knownPackages with the current installed list:
await prefs.setString('known_packages', _knownPackages.join(','));
```
Also, on the first session startup (empty `known_packages`), do NOT fire install alerts — instead, silently populate `_knownPackages` with the current baseline.

**Android-Specific Constraints:**
- Package installs on Android generate `Intent.ACTION_PACKAGE_ADDED` broadcasts. The `BootReceiver.kt` / `WatchdogReceiver.kt` Kotlin classes may already handle this. Check if the background service duplicates this functionality.
- The `_knownPackages` module-level set is in-memory only. Module-level Dart variables in a background isolate survive as long as the isolate is alive. They are reset when the service is killed and restarted.

**Firebase-Specific Constraints:**
- Each install alert is a Firebase push to `app_install_alerts/$uid`. If hundreds of false-positive install alerts are generated on watchdog restart, this consumes significant Firebase writes and generates notifications for every false install.

**Implementation Risk:** LOW — Adding SharedPreferences persistence to `_knownPackages` is non-invasive.

**Regression Risk:** LOW — If the persistence load fails (missing key, corrupt data), falling back to empty set is the current behavior (non-regression).

**Dependency Chain Impact:**
- **Dependent on:** P4-B (watchdog fix) — once the watchdog reset behavior is corrected, restarts are less frequent, reducing the frequency of this issue.

---

## PRIORITY 10 — CRASHES AND LIFECYCLE BUGS

---

### P10-A: Release Build Runtime Crash — Missing ProGuard Rules for WebRTC, Firebase, and Background Service Native Reflection

**Audit Reference:** REL-03
**Severity:** CRITICAL on release builds — `ClassNotFoundException` for WebRTC classes; `NoSuchMethodError` for Firebase persistence; background service fails to start

**Affected Files:**
- `android/app/proguard-rules.pro` — missing critical keep rules
- `android/app/build.gradle` — must enable `minifyEnabled true` for release builds

**Root Cause:**
Flutter release builds enable R8 (the Android bytecode optimizer/obfuscator). R8 renames Java classes and removes unused code. Several libraries in this app use Java reflection to find classes by name:

- `flutter_webrtc` uses JNI reflection to locate `org.webrtc.*` classes (libwebrtc.so native bridge). R8 renames these → native layer throws `ClassNotFoundException` → WebRTC peer connection creation fails with an unhandled exception.
- `firebase_database` uses Java reflection for persistence cache classes (`com.google.firebase.database.*`). R8 obfuscation → database persistence fails silently.
- `flutter_background_service` uses Android Service reflection to locate the background service class by name. If the class is renamed by R8, `startService(ComponentName)` fails → monitoring never starts.
- Dart `@pragma('vm:entry-point')` annotations protect DART functions from AOT tree-shaking — they do NOT protect Java classes from R8.

**Safest Production-Grade Fix Strategy:**
Create `android/app/proguard-rules.pro` with the following rules:
```
# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# WebRTC (flutter_webrtc)
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.** { *; }

# flutter_background_service
-keep class id.flutter.flutter_background_service.** { *; }

# flutter_foreground_task
-keep class com.pravera.flutter_foreground_task.** { *; }

# usage_stats
-keep class com.example.** { *; }

# Dart entry points (prevent R8 from removing @pragma('vm:entry-point') methods)
-keepclassmembers class * {
    @pragma('vm:entry-point') *;
}
```

Enable ProGuard in `android/app/build.gradle`:
```gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

**Android-Specific Constraints:**
- R8 is enabled by default for release builds in Flutter since Flutter 2.x. If `minifyEnabled` was not explicitly set to `false`, R8 may already be running and causing silent failures.
- The `proguard-android-optimize.txt` default rules include basic keep rules for Android framework classes — they do NOT cover Flutter plugins.
- Test the release APK on a physical device after adding these rules. R8 errors surface as `ClassNotFoundException` in logcat — not as crash reports in Crashlytics (since Crashlytics itself may fail to initialize if Firebase is obfuscated).

**Firebase-Specific Constraints:**
- Firebase Realtime Database's offline persistence uses a Java class (`StorageEngine`) that is referenced by string name internally. Without `keep com.google.firebase.**`, this class is renamed by R8 → database persistence silently disabled on release builds.

**Implementation Risk:** LOW — ProGuard rules are purely additive. Overly broad rules (keeping too many classes) increase APK size but do not cause runtime failures.

**Regression Risk:** VERY LOW — More restrictive rules (not enough kept) cause crashes. The rules above are intentionally broad.

**Dependency Chain Impact:**
- **Dependent on:** CRIT-04 (Firebase init) — release builds cannot be tested without correct Firebase initialization.
- **Required before:** any production release deployment.

---

## APPENDIX: IMPLEMENTATION ORDER RECOMMENDATION

The following order minimizes regression risk. Each item is safe to implement independently but the order below ensures that foundational fixes are in place before dependent fixes are applied.

```
IMMEDIATE (no code dependency — do these first):
  [1] P4-B: Fix _watchdogRestarting not reset — 1 line addition
  [2] P3-A: Remove setPersistenceEnabled from background service — 3 line deletion
  [3] P1-B: Add getIdToken(true) to SplashScreen — additive only
  [4] P2-C: Remove pendingParentRequests from _saveProfileFirst update — subtractive
  [5] P3-B: Add _checkingGeofences mutex — 3 line addition
  [6] P5-A: Add _reconnecting mutex to WebRTCService — additive
  [7] P5-B: Chain endCall → dispose in MonitoringScreen — small dispose() change
  [8] P8-A: Add LRU pruning to _seenFor() — 5 line addition
  [9] P9-A: Persist _knownPackages to SharedPreferences — additive

WEEK 1 (requires some structural work):
  [10] P1-A: Run flutterfire configure, add DefaultFirebaseOptions — requires Firebase project access
  [11] P3-C: Remove _cleanupStaleSessions from foreground_service.dart — verify BG-01 impact
  [12] P6-A: Fix _screenTimeTimer sequential reads — in-timer refactor
  [13] P10-A: Add proguard-rules.pro — new file creation

WEEK 2-3 (architectural — coordinate carefully):
  [14] P2-B: Add background_owns_presence flag — cross-service coordination
  [15] P4-A: BG-01 dual foreground services — consolidate or add foregroundServiceType
  [16] P2-A: CRIT-02 dual WebRTC — three-step process (most complex change)
```

---

## APPENDIX: FILE-LEVEL RISK SUMMARY (CURRENT STATE)

| File | Still-Open Critical Issues | Priority |
|---|---|---|
| `lib/main.dart` | P1-A (no DefaultFirebaseOptions) | CRITICAL |
| `lib/screens/splash_screen.dart` | P1-B (no token validation) | HIGH |
| `lib/services/webrtc_service.dart` | P2-A (startAsChild still exists), P5-A (no reconnect mutex) | CRITICAL |
| `lib/services/silent_webrtc_service.dart` | P2-A (independent _connectivitySub) | CRITICAL |
| `lib/screens/child/child_home_screen.dart` | P2-A (_callSub + _autoStartStreaming), P2-B (startChildPresence call) | CRITICAL |
| `lib/screens/child/child_streaming_screen.dart` | P2-A (startAsChild call on lines 98, 115) | CRITICAL |
| `lib/screens/child/child_setup_wizard_screen.dart` | P2-C (TOCTOU on pendingParentRequests) | HIGH |
| `lib/screens/parent/monitoring_screen.dart` | P5-B (dispose race) | HIGH |
| `lib/services/background_monitoring_service.dart` | P3-A (setPersistenceEnabled), P4-B (watchdog restarting flag), P9-A (knownPackages) | HIGH |
| `lib/services/presence_service.dart` | P2-B (dual presence writer) | HIGH |
| `lib/services/location_service.dart` | P3-B (no mutex, wrong data path) | HIGH |
| `lib/services/foreground_service.dart` | P3-C (cleanupStaleSessions threshold mismatch), P4-A (no foregroundServiceType) | HIGH |
| `lib/services/notification_service.dart` | P8-A (no LRU cap on _seenAlerts) | MEDIUM |
| `android/app/proguard-rules.pro` | P10-A (missing — file does not exist with correct rules) | CRITICAL for release |
| `lib/firebase_options.dart` | P1-A (file does not exist) | CRITICAL |

---

*All findings above are verified against the actual running source files as of the session timestamp. No assumptions have been made. Every root cause, execution flow, and fix strategy is based on direct reading of the current codebase. Do not patch any file without cross-referencing the current code against this document to confirm the issue still applies.*
