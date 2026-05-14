# Family Monitor

## Project Overview

Family Monitor is a Flutter/Android mobile application for transparent parental monitoring. It provides real-time oversight of a child's device including live screen streaming, app usage tracking, content filtering, remote device lock, and background monitoring.

**This is a mobile app — it cannot run in a web browser.** The Replit environment serves a project overview page at port 5000. To build and run the app itself, you need the Flutter SDK, Android SDK, and a connected Android device or emulator on your local machine.

## Tech Stack

- **Framework:** Flutter (Dart SDK >=3.3.0)
- **Backend:** Firebase (Auth, Realtime Database, Cloud Messaging, Storage, Crashlytics)
- **Real-time Streaming:** WebRTC (`flutter_webrtc`)
- **Android Native:** Kotlin (screen capture, device admin, boot persistence)
- **Web Preview:** Node.js server (project overview page)

## Project Structure

```
lib/
├── main.dart                        # Firebase init + routing + theme
├── main_child.dart                  # Child-specific entry point
├── main_parent.dart                 # Parent-specific entry point
├── services/
│   ├── auth_service.dart            # Firebase Auth + DB user management
│   ├── webrtc_service.dart          # WebRTC peer connections
│   ├── silent_webrtc_service.dart   # Hidden camera/screen streaming
│   ├── background_monitoring_service.dart
│   ├── foreground_service.dart      # Android foreground notification
│   └── ...                         # Other services
└── screens/
    ├── parent/                      # Parent dashboard, monitoring, QR scanner
    └── child/                       # Child setup wizard, home, streaming
android/                             # Native Kotlin Android code
assets/images/                       # Images and Lottie animations
server.js                            # Replit web preview (project overview)
```

## Running on Replit

The `server.js` file serves a project overview page at port 5000. This is the expected behavior since Flutter/Android apps require native tooling to build and run.

## Local Development Setup

1. Install Flutter SDK (>=3.3.0) from flutter.dev
2. Create a Firebase project and enable Email/Password + Anonymous Auth
3. Create a Firebase Realtime Database and copy the database URL
4. Add an Android app in Firebase with package name `com.familymonitor.app`
5. Download `google-services.json` and place at `android/app/google-services.json`
6. Update `FirebaseOptions` in `lib/main.dart` with your Firebase credentials
7. Run `flutter pub get` then `flutter run --debug` with a connected device

See `SETUP.md` for the full setup guide.

## User Preferences

- Keep the Node.js overview server as the Replit entry point (Flutter apps can't run in browser)
- Firebase Auth is used for parent (email/password) and child (anonymous) authentication
- No Replit Auth replacement needed — app runs natively on Android devices

## AI Provider Configuration

All AI requests must route through **OpenRouter** — never call OpenAI, Anthropic, or other providers directly.

- **Endpoint:** `https://openrouter.ai/api/v1`
- **API Key:** `OPENROUTER_API_KEY` (stored in Replit Secrets)
- **Model for coding tasks:** `anthropic/claude-opus-4-5` (Claude Opus 4.7)
- **Model for general tasks:** `qwen/qwen3-coder` (Qwen3 Coder Next)
- Any OpenAI-compatible SDK should point base URL to `https://openrouter.ai/api/v1` and use `OPENROUTER_API_KEY`
