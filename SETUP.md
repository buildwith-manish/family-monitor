# Family Monitor — Setup Guide

## What's included

```
lib/
├── main.dart                           ✅ NEW — Firebase init + routing + theme
├── services/
│   ├── auth_service.dart               ✅ Firebase Auth + DB user management
│   ├── webrtc_service.dart             ✅ WebRTC (bug fixed: useFrontCamera typo)
│   └── foreground_service.dart        ✅ NEW — Android foreground notification
└── screens/
    ├── splash_screen.dart
    ├── role_selection_screen.dart
    ├── parent/
    │   ├── parent_auth_screen.dart
    │   ├── parent_dashboard_screen.dart
    │   ├── add_child_screen.dart
    │   └── monitoring_screen.dart
    └── child/
        ├── child_setup_wizard_screen.dart
        ├── child_home_screen.dart
        └── child_streaming_screen.dart
android/
    app/
        build.gradle                    ✅ NEW
        src/main/AndroidManifest.xml
    build.gradle                        ✅ NEW
    settings.gradle                     ✅ NEW
    gradle/wrapper/
        gradle-wrapper.properties       ✅ NEW
pubspec.yaml
firebase_database_rules.json
```

---

## Step 1 — Create a Flutter project shell

```bash
flutter create family_monitor --org com.familymonitor
cd family_monitor
```

Then **replace** the generated `lib/`, `android/app/build.gradle`,
`android/build.gradle`, `android/settings.gradle`, `pubspec.yaml`,
and `android/app/src/main/AndroidManifest.xml` with the files from this folder.

---

## Step 2 — Firebase setup

1. Go to [Firebase Console](https://console.firebase.google.com) → Add project → `family-monitor`
2. **Authentication** → Get started → enable **Email/Password** + **Anonymous**
3. **Realtime Database** → Create database → Start in test mode → copy the DB URL
4. **Project Settings** → Add app → Android
   - Package name: `com.familymonitor.app`
   - Download `google-services.json` → place at `android/app/google-services.json`
5. **Realtime Database** → Rules tab → paste contents of `firebase_database_rules.json` → Publish

---

## Step 3 — Update Firebase config in main.dart

Open `lib/main.dart` and replace the placeholder values with your real ones
(found in Firebase Console → Project Settings → Your apps → SDK config):

```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: "YOUR_ACTUAL_API_KEY",
    authDomain: "your-project-id.firebaseapp.com",
    databaseURL: "https://your-project-id-default-rtdb.firebaseio.com",
    projectId: "your-project-id",
    storageBucket: "your-project-id.appspot.com",
    messagingSenderId: "YOUR_SENDER_ID",
    appId: "YOUR_APP_ID",
  ),
);
```

---

## Step 4 — Install & run

```bash
flutter pub get
flutter run --debug
```

---

## Bug fixes applied

| File | Bug | Fix |
|------|-----|-----|
| `webrtc_service.dart` line 64 | `usesFrontCamera` (undefined variable) | Renamed to `useFrontCamera` to match the parameter name |

---

## What was added

### `main.dart`
- Firebase initialization with `FirebaseOptions` (fill in your real values)
- Portrait-only orientation lock
- Full named-route map for all screens
- Complete Material 3 theme: cards, buttons, inputs, AppBar, SnackBar all styled

### `foreground_service.dart`
- Singleton `MonitoringForegroundService` wrapping `flutter_foreground_task`
- `startService()` — starts the persistent notification
- `updateNotification()` — updates text as camera/audio/screen toggle
- `stopService()` — stops the notification
- "Stop Monitoring" button in notification → signals main isolate via `sendDataToMain`
- Notification tap → launches app at `/child/home`

---

## Foreground service notification button (optional wiring)

To handle the "Stop Monitoring" button tap in `child_streaming_screen.dart`,
wrap your widget tree in `WithForegroundTask` and listen for data from the task:

```dart
// In child_streaming_screen.dart initState:
FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

void _onReceiveTaskData(Object data) {
  if (data is Map && data['action'] == 'stop_monitoring') {
    _stopMonitoring();
  }
}

// In dispose:
FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
```

---

## TURN server (production)

The app uses the free `openrelay.metered.ca` TURN server. For production,
create a free account at https://www.metered.ca/tools/openrelay/ and
replace the credentials in `lib/services/webrtc_service.dart` under `_iceConfig`.
