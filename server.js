const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 5000;
const HOST = '0.0.0.0';

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Family Monitor</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      background: #F8FAFB;
      color: #202124;
      min-height: 100vh;
    }
    header {
      background: white;
      border-bottom: 1px solid #e8eaed;
      padding: 20px 40px;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .logo {
      width: 42px; height: 42px;
      background: #1A73E8;
      border-radius: 10px;
      display: flex; align-items: center; justify-content: center;
      color: white; font-size: 22px;
    }
    header h1 { font-size: 22px; font-weight: 700; }
    header p { font-size: 13px; color: #5F6368; margin-top: 2px; }
    .hero {
      background: linear-gradient(135deg, #1A73E8 0%, #0D47A1 100%);
      color: white;
      padding: 60px 40px;
      text-align: center;
    }
    .hero h2 { font-size: 36px; font-weight: 700; margin-bottom: 14px; }
    .hero p { font-size: 18px; opacity: 0.9; max-width: 560px; margin: 0 auto 28px; }
    .badge {
      display: inline-block;
      background: rgba(255,255,255,0.18);
      border: 1px solid rgba(255,255,255,0.35);
      border-radius: 20px;
      padding: 6px 16px;
      font-size: 13px;
      margin: 4px;
    }
    .container { max-width: 1000px; margin: 0 auto; padding: 48px 24px; }
    .section-title {
      font-size: 20px; font-weight: 700;
      margin-bottom: 20px;
      color: #202124;
    }
    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 16px;
      margin-bottom: 48px;
    }
    .card {
      background: white;
      border: 1px solid #e8eaed;
      border-radius: 16px;
      padding: 24px;
    }
    .card-icon {
      width: 44px; height: 44px;
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      font-size: 22px;
      margin-bottom: 14px;
    }
    .card h3 { font-size: 16px; font-weight: 600; margin-bottom: 8px; }
    .card p { font-size: 14px; color: #5F6368; line-height: 1.5; }
    .setup {
      background: white;
      border: 1px solid #e8eaed;
      border-radius: 16px;
      padding: 32px;
      margin-bottom: 48px;
    }
    .step {
      display: flex;
      gap: 16px;
      padding: 16px 0;
      border-bottom: 1px solid #f1f3f4;
    }
    .step:last-child { border-bottom: none; }
    .step-num {
      width: 32px; height: 32px; flex-shrink: 0;
      background: #1A73E8;
      color: white;
      border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      font-size: 14px; font-weight: 700;
    }
    .step-content h4 { font-size: 15px; font-weight: 600; margin-bottom: 4px; }
    .step-content p { font-size: 14px; color: #5F6368; line-height: 1.5; }
    code {
      background: #f1f3f4;
      border-radius: 4px;
      padding: 2px 6px;
      font-size: 13px;
      font-family: 'Courier New', monospace;
    }
    .tech-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
      gap: 12px;
      margin-bottom: 48px;
    }
    .tech-item {
      background: white;
      border: 1px solid #e8eaed;
      border-radius: 12px;
      padding: 16px;
      display: flex; align-items: center; gap: 10px;
    }
    .tech-item span { font-size: 20px; }
    .tech-item div { font-size: 14px; font-weight: 500; }
    .tech-item small { font-size: 12px; color: #5F6368; display: block; }
    .notice {
      background: #FFF8E1;
      border: 1px solid #FFD54F;
      border-radius: 12px;
      padding: 20px 24px;
      margin-bottom: 32px;
      display: flex; gap: 12px; align-items: flex-start;
    }
    .notice .icon { font-size: 22px; flex-shrink: 0; }
    .notice p { font-size: 14px; line-height: 1.6; color: #5F6368; }
    .notice strong { color: #202124; }
    footer {
      text-align: center;
      padding: 32px;
      color: #9AA0A6;
      font-size: 13px;
      border-top: 1px solid #e8eaed;
      background: white;
    }
  </style>
</head>
<body>
  <header>
    <div class="logo">&#128101;</div>
    <div>
      <h1>Family Monitor</h1>
      <p>Transparent parental monitoring app</p>
    </div>
  </header>

  <div class="hero">
    <h2>Family Monitor</h2>
    <p>A Flutter-based parental monitoring application for Android with real-time device oversight and remote management.</p>
    <div>
      <span class="badge">&#128241; Flutter</span>
      <span class="badge">&#128293; Firebase</span>
      <span class="badge">&#128247; WebRTC</span>
      <span class="badge">&#129470; Kotlin</span>
      <span class="badge">&#128272; Android</span>
    </div>
  </div>

  <div class="container">

    <div class="notice">
      <div class="icon">&#9888;&#65039;</div>
      <p><strong>Flutter Mobile App:</strong> This project is a Flutter/Android mobile application and cannot run directly in a web browser. To build and run this app, you need the Flutter SDK, Android SDK, and a connected Android device or emulator. See the setup steps below to get started on your local machine.</p>
    </div>

    <h2 class="section-title">Core Features</h2>
    <div class="cards">
      <div class="card">
        <div class="card-icon" style="background:#E8F0FE">&#128247;</div>
        <h3>Live Screen Streaming</h3>
        <p>Real-time screen capture and streaming from child devices to the parent dashboard via WebRTC.</p>
      </div>
      <div class="card">
        <div class="card-icon" style="background:#E6F4EA">&#128200;</div>
        <h3>App Usage Tracking</h3>
        <p>Monitor which apps are being used, for how long, with detailed usage statistics and charts.</p>
      </div>
      <div class="card">
        <div class="card-icon" style="background:#FCE8E6">&#128683;</div>
        <h3>Content Filtering</h3>
        <p>Block specific apps and set usage schedules to restrict device access during certain hours.</p>
      </div>
      <div class="card">
        <div class="card-icon" style="background:#FEF7E0">&#128274;</div>
        <h3>Remote Device Lock</h3>
        <p>Remotely lock child devices via Firebase Cloud Messaging and Android Device Admin.</p>
      </div>
      <div class="card">
        <div class="card-icon" style="background:#F3E8FD">&#128241;</div>
        <h3>QR Device Pairing</h3>
        <p>Easy device pairing between parent and child devices using QR code scanning.</p>
      </div>
      <div class="card">
        <div class="card-icon" style="background:#E8F5E9">&#128267;</div>
        <h3>Background Monitoring</h3>
        <p>Persistent foreground service keeps monitoring active even when the app is in the background.</p>
      </div>
    </div>

    <h2 class="section-title">Tech Stack</h2>
    <div class="tech-grid">
      <div class="tech-item"><span>&#129654;</span><div>Flutter<small>UI Framework</small></div></div>
      <div class="tech-item"><span>&#128293;</span><div>Firebase Auth<small>Authentication</small></div></div>
      <div class="tech-item"><span>&#128209;</span><div>Realtime DB<small>Firebase Database</small></div></div>
      <div class="tech-item"><span>&#128247;</span><div>WebRTC<small>Live Streaming</small></div></div>
      <div class="tech-item"><span>&#129470;</span><div>Kotlin<small>Android Native</small></div></div>
      <div class="tech-item"><span>&#128172;</span><div>FCM<small>Push Notifications</small></div></div>
      <div class="tech-item"><span>&#128190;</span><div>Firebase Storage<small>Media Storage</small></div></div>
      <div class="tech-item"><span>&#128269;</span><div>Crashlytics<small>Error Reporting</small></div></div>
    </div>

    <h2 class="section-title">Project Structure</h2>
    <div class="setup" style="margin-bottom:32px">
      <div class="step">
        <div class="step-num">&#128193;</div>
        <div class="step-content">
          <h4>lib/</h4>
          <p>Core Dart application code — <code>main.dart</code> (Firebase init + routing), <code>screens/parent/</code> (dashboard, monitoring, QR scanner), <code>screens/child/</code> (setup wizard, home, streaming), <code>services/</code> (auth, WebRTC, background monitoring, SMS, contacts, battery).</p>
        </div>
      </div>
      <div class="step">
        <div class="step-num">&#129470;</div>
        <div class="step-content">
          <h4>android/</h4>
          <p>Native Android implementation — <code>ScreenCaptureService.kt</code>, <code>FamilyDeviceAdminReceiver.kt</code> (remote lock), <code>StealthActivity.kt</code>, Gradle build files with Kotlin DSL.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-num">&#128196;</div>
        <div class="step-content">
          <h4>assets/</h4>
          <p>Images and Lottie animations used throughout the UI.</p>
        </div>
      </div>
    </div>

    <h2 class="section-title">Local Setup Guide</h2>
    <div class="setup">
      <div class="step">
        <div class="step-num">1</div>
        <div class="step-content">
          <h4>Install Flutter</h4>
          <p>Install Flutter SDK (&ge;3.3.0) from <strong>flutter.dev</strong> and ensure <code>flutter doctor</code> passes for Android development.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-num">2</div>
        <div class="step-content">
          <h4>Firebase Setup</h4>
          <p>Create a Firebase project, enable Email/Password + Anonymous Auth, create a Realtime Database, and add an Android app with package name <code>com.familymonitor.app</code>. Download <code>google-services.json</code> and place it at <code>android/app/google-services.json</code>.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-num">3</div>
        <div class="step-content">
          <h4>Configure Firebase in main.dart</h4>
          <p>Open <code>lib/main.dart</code> and update the <code>FirebaseOptions</code> with your real API key, project ID, database URL, and other credentials from the Firebase Console.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-num">4</div>
        <div class="step-content">
          <h4>Install Dependencies &amp; Run</h4>
          <p>Run <code>flutter pub get</code> to install packages, then <code>flutter run --debug</code> with a connected Android device or emulator.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-num">5</div>
        <div class="step-content">
          <h4>Upload Database Rules</h4>
          <p>In the Firebase Console, paste the contents of <code>firebase_database_rules.json</code> into the Realtime Database Rules tab and publish.</p>
        </div>
      </div>
    </div>

  </div>

  <footer>
    <p>Family Monitor &mdash; Flutter + Firebase + WebRTC &mdash; Android Parental Monitoring App</p>
  </footer>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});

server.listen(PORT, HOST, () => {
  console.log(`Family Monitor project overview running at http://${HOST}:${PORT}`);
});
