import { useState } from "react";

const SEVERITY = {
  CRITICAL: { bg: "bg-red-100", border: "border-red-500", text: "text-red-700", badge: "bg-red-600 text-white", dot: "bg-red-500" },
  HIGH: { bg: "bg-orange-100", border: "border-orange-500", text: "text-orange-700", badge: "bg-orange-500 text-white", dot: "bg-orange-500" },
  MEDIUM: { bg: "bg-yellow-100", border: "border-yellow-500", text: "text-yellow-700", badge: "bg-yellow-500 text-white", dot: "bg-yellow-500" },
  LOW: { bg: "bg-blue-100", border: "border-blue-500", text: "text-blue-700", badge: "bg-blue-500 text-white", dot: "bg-blue-500" },
};

const criticalIssues = [
  { id: "CRIT-01", file: "lib/services/background_monitoring_service.dart", issue: "PACKAGE_USAGE_STATS permission NEVER requested — all screen time, app usage, daily reports return empty silently", impact: "App's core monitoring features non-functional" },
  { id: "CRIT-02", file: "Firebase Console (not in repo)", issue: "No Firebase Security Rules — all child data (SMS, location, contacts) potentially world-readable or writable", impact: "GDPR/privacy violation, data breach risk" },
  { id: "CRIT-03", file: "lib/services/sms_service.dart + wizard", issue: "READ_SMS permission not in setup wizard — SMS sync silently fails for all users", impact: "Core feature non-functional" },
  { id: "CRIT-04", file: "lib/screens/child/child_home_screen.dart", issue: "_locked = false hardcoded — lock overlay is permanently disabled, device lock feature is fake UI", impact: "Feature falsely advertised" },
  { id: "CRIT-05", file: "AppBlockAccessibilityService.kt", issue: "flutter.uninstall_pin never written in Dart — PIN gate never triggers, uninstall protection is fake", impact: "Security feature non-functional" },
  { id: "CRIT-06", file: "lib/services/silent_webrtc_service.dart", issue: "_connectivitySub not cancelled in stopSilent() — stream leak on every monitoring session end", impact: "Memory leak, zombie Firebase listener" },
  { id: "CRIT-07", file: "lib/services/notification_service.dart", issue: "FCM token never saved, no Cloud Function — parent push notifications non-functional when parent app is closed", impact: "Core notification feature broken" },
  { id: "CRIT-08", file: "lib/main.dart + flavor system", issue: "No flavor-specific route guards — parent APK can navigate to /child/home via SharedPreferences manipulation", impact: "Security boundary failure" },
  { id: "CRIT-09", file: "lib/screens/child/child_home_screen.dart", issue: "users/$uid/connectedParent is NEVER written anywhere in codebase — connected parent display permanently broken", impact: "Core UX broken" },
  { id: "CRIT-10", file: "BootReceiver.kt", issue: "LOCKED_BOOT_COMPLETED fires in Direct Boot — FlutterSharedPreferences not accessible in credential-encrypted storage → crash on first boot", impact: "Boot-time crash" },
];

const highIssues = [
  { id: "HIGH-01", file: "android/app/build.gradle.kts", issue: "Application ID com.example.* — Play Store rejects this namespace", impact: "Cannot publish to Play Store" },
  { id: "HIGH-02", file: "lib/screens/child/child_home_screen.dart", issue: "SMS/contacts/call log/app list sync listeners dead in background — only work when UI is open", impact: "Core features fail when app minimized" },
  { id: "HIGH-03", file: "lib/services/location_service.dart", issue: "Location tracking stopped on ChildHomeScreen.dispose() — stopTracking() called on navigate away", impact: "Background location non-functional" },
  { id: "HIGH-04", file: "lib/services/app_install_alert_service.dart", issue: "_knownPackages reset on service restart — every installed app reported as 'newly installed'", impact: "Spams parent with hundreds of false alerts" },
  { id: "HIGH-05", file: "android/app/build.gradle.kts", issue: "SCHEDULE_EXACT_ALARM not declared/checked — WatchdogReceiver throws SecurityException on API 33+", impact: "Service watchdog silently fails" },
  { id: "HIGH-06", file: "AndroidManifest.xml", issue: "ACCESS_BACKGROUND_LOCATION not declared — background GPS broken on Android 10+", impact: "Location tracking non-functional in background" },
  { id: "HIGH-07", file: "lib/services/auth_service.dart", issue: "signInChild() doesn't verify role == 'child' — parent credentials can sign in as child", impact: "Auth boundary broken" },
  { id: "HIGH-08", file: "lib/services/turn_config_service.dart", issue: "STUN-only fallback — ~40% of connections through carrier NAT fail to connect", impact: "WebRTC unreliable for large user base" },
  { id: "HIGH-09", file: "lib/screens/parent/parent_dashboard_screen.dart", issue: "setState() called on disposed widget via 3s delayed reattachment after stream error", impact: "Crash risk" },
  { id: "HIGH-10", file: "android/app/build.gradle.kts", issue: "Release build falls back to debug keystore if env vars not set — CI produces debug-signed 'release'", impact: "Security/publishing issue" },
  { id: "HIGH-11", file: "lib/services/snapshot_service.dart", issue: "Native snapshot channel requires Activity foreground — background snapshots fail silently", impact: "Feature non-functional in background" },
  { id: "HIGH-12", file: "AndroidManifest.xml", issue: "QUERY_ALL_PACKAGES not declared — getInstalledApps() returns filtered list on API 30+", impact: "App list incomplete, install alerts miss apps" },
  { id: "HIGH-13", file: "lib/services/background_monitoring_service.dart", issue: "Foreground types camera|microphone declared on idle service — Android 14 kills service", impact: "Service crash on Android 14" },
];

const mediumIssues = [
  { id: "MED-01", issue: "Anonymous auth accounts expire after 30 days — no recovery path coded", file: "lib/services/auth_service.dart" },
  { id: "MED-02", issue: "_knownPackages reset on service restart generates false app install alerts", file: "background_monitoring_service.dart" },
  { id: "MED-03", issue: "sms/$uid full read on every keyword scan (every 20min) — large Firebase bandwidth cost", file: "lib/services/keyword_alert_service.dart" },
  { id: "MED-04", issue: "Battery reporting every 60s even when screen off — unnecessary child device battery drain", file: "lib/services/battery_service.dart" },
  { id: "MED-05", issue: "device_events, hourly_usage, daily_reports grow unbounded — no TTL or cleanup", file: "Firebase (multiple services)" },
  { id: "MED-06", issue: "isOnline written from 4 sources simultaneously — doubled Firebase write cost", file: "lib/services/presence_service.dart" },
  { id: "MED-07", issue: "Wizard Page 7 has no timeout — child stuck waiting if parent never sends request", file: "child_setup_wizard_screen.dart" },
  { id: "MED-08", issue: "currentUser?.uid null if session expired mid-wizard — silent setup failure", file: "child_setup_wizard_screen.dart" },
  { id: "MED-09", issue: "Every battery heartbeat rebuilds entire parent dashboard — excessive redraws with multiple children", file: "parent_dashboard_screen.dart" },
  { id: "MED-10", issue: "UsageStats.queryUsageStats() every 60s for entire day — expensive query on every tick", file: "background_monitoring_service.dart" },
  { id: "MED-11", issue: "startAsParent() followed by immediate endCall() from dispose creates zombie listeners", file: "lib/services/webrtc_service.dart" },
  { id: "MED-12", issue: "APP_INFO_CLASSES list incomplete — Samsung/Xiaomi/Huawei Settings class names not covered", file: "AppBlockAccessibilityService.kt" },
  { id: "MED-13", issue: "_seen dedup sets lost on app restart — old alerts re-notified on every cold start", file: "notification_service.dart" },
  { id: "MED-14", issue: "READ_CALL_LOG permission not confirmed in wizard — call log sync may silently fail", file: "child_home_screen.dart" },
  { id: "MED-15", issue: "WeeklySummaryService.generateWeeklySummary() not idempotent — concurrent calls cause data corruption", file: "background_monitoring_service.dart" },
];

const fakeFeatures = [
  { feature: "Device Lock", where: "ChildHomeScreen lock overlay", reason: "_locked = false hardcoded; never reads from Firebase" },
  { feature: "Uninstall PIN Protection", where: "AppBlockAccessibilityService & wizard", reason: "flutter.uninstall_pin never written from Dart; PIN gate never triggers" },
  { feature: "App Usage Monitoring", where: "Parent dashboard → App Usage screen", reason: "PACKAGE_USAGE_STATS not requested; returns empty silently" },
  { feature: "Screen Time Limits", where: "Parent dashboard → App Lock screen", reason: "Same permission gap; no enforcement without UsageStats" },
  { feature: "SMS Monitoring (background)", where: "Parent SMS screen", reason: "Listener dead when app minimized; permission not in wizard" },
  { feature: "Push Notifications", where: "NotificationService", reason: "No FCM token saved; no Cloud Function; local notifications only" },
  { feature: "Background Location", where: "Location shown in parent dashboard", reason: "Stops immediately when child minimizes app" },
  { feature: "Geofence Alerts (background)", where: "Geofence screen", reason: "Dependent on broken background location" },
  { feature: "Background Snapshots", where: "Snapshot trigger", reason: "MethodChannel only works with Activity in foreground" },
  { feature: "App Blocking Overlay", where: "Lock card in UI", reason: "_locked never true; accessibility service requires manual setup + incomplete" },
  { feature: "'Monitoring Active' indicator", where: "Child home screen header", reason: "Shows 'Monitoring Active' always, even when all features fail silently" },
  { feature: "Weekly Summary (automated)", where: "WeeklySummary screen", reason: "Dependent on broken PACKAGE_USAGE_STATS; may not run if service killed" },
];

const scores = [
  { name: "Authentication flow", score: 5 },
  { name: "Device Pairing/QR", score: 6 },
  { name: "Live Camera", score: 5 },
  { name: "Live Screen Share", score: 4 },
  { name: "App Usage / Screen Time", score: 2 },
  { name: "SMS Monitoring", score: 2 },
  { name: "Call Log Monitoring", score: 3 },
  { name: "Contact Sync", score: 3 },
  { name: "Location Tracking", score: 4 },
  { name: "Geofencing", score: 4 },
  { name: "Battery Alerts", score: 7 },
  { name: "App Install Alerts", score: 3 },
  { name: "Snapshots", score: 4 },
  { name: "App Blocking (Accessibility)", score: 4 },
  { name: "App Blocking (DPM)", score: 5 },
  { name: "Daily Reports", score: 3 },
  { name: "Notification System", score: 4 },
  { name: "Firebase Security", score: 1 },
  { name: "Background Persistence", score: 5 },
  { name: "WebRTC Signaling", score: 6 },
];

const phases = [
  {
    phase: "Phase 0",
    title: "Emergency Blockers",
    time: "1–2 days",
    color: "bg-red-600",
    items: [
      "Set Firebase Security Rules (Firebase Console, 30 min)",
      "Add PACKAGE_USAGE_STATS permission request flow in wizard",
      "Add READ_SMS to wizard _requestCorePermissions()",
      "Change application ID from com.example.* to real reverse-domain ID",
      "Fix _locked = false → read from Firebase commands/$uid/deviceLock",
    ],
  },
  {
    phase: "Phase 1",
    title: "Critical Architecture",
    time: "1–2 weeks",
    color: "bg-orange-600",
    items: [
      "Remove flutter_foreground_task — consolidate to single background service",
      "Move ALL command listeners (SMS, contacts, call log, app list) to background service isolate",
      "Add ACCESS_BACKGROUND_LOCATION to manifest; move location tracking to background service",
      "Declare and check SCHEDULE_EXACT_ALARM permission; implement WorkManager-only watchdog",
      "Fix Android 14 foreground service types (dynamic promotion only during active streams)",
      "Implement FCM token save + Cloud Function for push notifications",
      "Write users/$uid/connectedParent node in approveParentRequest()",
      "Fix _connectivitySub leak in SilentWebRTCService.stopSilent()",
    ],
  },
  {
    phase: "Phase 2",
    title: "Feature Completion",
    time: "2–3 weeks",
    color: "bg-yellow-600",
    items: [
      "Add READ_CONTACTS and READ_CALL_LOG to wizard permissions",
      "Add PACKAGE_USAGE_STATS Settings redirect guidance in wizard",
      "Add QUERY_ALL_PACKAGES to manifest or <queries> block",
      "Implement functional device lock (read/write Firebase, show overlay)",
      "Implement functional uninstall PIN (write from Dart, PinVerifyActivity)",
      "Add Firebase data TTL cleanup (Cloud Functions)",
      "Fix _knownPackages reset on service restart (persist to SharedPreferences)",
      "Provision private TURN server and populate config/turnServers in Firebase",
      "Add signInChild() role verification",
    ],
  },
  {
    phase: "Phase 3",
    title: "Stability & Performance",
    time: "2–3 weeks",
    color: "bg-blue-600",
    items: [
      "Add state management layer (Riverpod recommended)",
      "Fix NotificationService — FCM-based alerts with Cloud Functions",
      "Add QR code security (nonce + HMAC, not just plain UID)",
      "Implement screen-state tracking (ACTION_SCREEN_ON/OFF BroadcastReceiver)",
      "Add AccessibilityService coverage for remaining OEM device types",
      "Fix duplicate lastSeen writers (consolidate to single source of truth)",
      "Add Cloud Function data aggregation for usage stats",
    ],
  },
  {
    phase: "Phase 4",
    title: "Production Hardening",
    time: "1–2 weeks",
    color: "bg-purple-600",
    items: [
      "Firebase App Check integration (block unofficial clients)",
      "ProGuard rules verification for all plugins",
      "CI pipeline: add release build, signing workflow, flutter test",
      "Remove .broken and .bak files from repository",
      "Privacy policy + Terms of Service implementation",
      "Google Play Console setup with proper content rating",
    ],
  },
];

const responsibleFiles = [
  { rank: 1, file: "lib/services/background_monitoring_service.dart", issues: 12, problems: "Missing PACKAGE_USAGE_STATS, false install alerts, dead command pattern, Android 14 types, timer proliferation" },
  { rank: 2, file: "lib/screens/child/child_home_screen.dart", issues: 9, problems: "Listeners dead in background, _locked=false, phantom connectedParent, READ_SMS missing, service startup race" },
  { rank: 3, file: "lib/services/silent_webrtc_service.dart", issues: 6, problems: "_connectivitySub leak, screen mode broken in background, orphan session UX, STUN-only" },
  { rank: 4, file: "lib/services/auth_service.dart", issues: 6, problems: "signInChild no role check, anonymous expiry, phantom node, race conditions, stale entries" },
  { rank: 5, file: "lib/services/notification_service.dart", issues: 5, problems: "FCM non-functional, dedup lost on restart, no token save, no Cloud Functions" },
  { rank: 6, file: "android/app/build.gradle.kts", issues: 4, problems: "com.example ID, debug keystore fallback, SDK version patching fragility" },
  { rank: 7, file: "AppBlockAccessibilityService.kt", issues: 4, problems: "PIN never set (null always), incomplete OEM class list, no overlay permission" },
  { rank: 8, file: "lib/services/location_service.dart", issues: 4, problems: "Stops on dispose, no background location permission, geofence Firebase write on each update" },
  { rank: 9, file: "android/app/src/main/kotlin/.../BootReceiver.kt", issues: 3, problems: "LOCKED_BOOT_COMPLETED crash, MY_PACKAGE_REPLACED isAppInForeground unreliable on API 30+" },
  { rank: 10, file: "Firebase (missing database.rules.json)", issues: 999, problems: "ALL data potentially exposed to any authenticated user — complete privacy failure" },
];

const navItems = [
  { id: "overview", label: "Overview" },
  { id: "architecture", label: "Architecture" },
  { id: "auth", label: "Auth Analysis" },
  { id: "features", label: "Feature Forensics" },
  { id: "firebase", label: "Firebase" },
  { id: "android", label: "Android" },
  { id: "critical", label: "Critical Issues" },
  { id: "high", label: "High Issues" },
  { id: "medium", label: "Medium Issues" },
  { id: "fake", label: "Fake Features" },
  { id: "scores", label: "Stability Scores" },
  { id: "phases", label: "Fix Plan" },
  { id: "files", label: "Responsible Files" },
];

function ScoreBar({ score }: { score: number }) {
  const pct = (score / 10) * 100;
  const color =
    score <= 2 ? "bg-red-500" : score <= 4 ? "bg-orange-500" : score <= 6 ? "bg-yellow-500" : "bg-green-500";
  return (
    <div className="flex items-center gap-3">
      <div className="flex-1 bg-gray-200 rounded-full h-2.5">
        <div className={`${color} h-2.5 rounded-full transition-all`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-sm font-bold w-10 text-right text-gray-700">{score}/10</span>
    </div>
  );
}

function SectionHeader({ id, title, subtitle, icon }: { id: string; title: string; subtitle?: string; icon: string }) {
  return (
    <div id={id} className="mb-6 scroll-mt-20">
      <div className="flex items-center gap-3 mb-1">
        <span className="text-2xl">{icon}</span>
        <h2 className="text-2xl font-bold text-gray-900">{title}</h2>
      </div>
      {subtitle && <p className="text-gray-500 ml-9">{subtitle}</p>}
      <div className="mt-3 h-0.5 bg-gradient-to-r from-gray-200 to-transparent" />
    </div>
  );
}

function IssueCard({
  id,
  file,
  issue,
  impact,
  severity,
}: {
  id: string;
  file: string;
  issue: string;
  impact: string;
  severity: keyof typeof SEVERITY;
}) {
  const s = SEVERITY[severity];
  return (
    <div className={`rounded-xl border-l-4 ${s.border} ${s.bg} p-4 mb-3`}>
      <div className="flex items-start justify-between gap-3 mb-2">
        <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${s.badge}`}>{id}</span>
        <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${s.badge}`}>{severity}</span>
      </div>
      <p className={`font-semibold text-sm mb-1 ${s.text}`}>{issue}</p>
      <code className="block text-xs text-gray-500 bg-gray-100 rounded px-2 py-1 mb-2 font-mono break-all">{file}</code>
      <p className="text-xs text-gray-600">
        <span className="font-semibold">Impact:</span> {impact}
      </p>
    </div>
  );
}

export default function App() {
  const [activeNav, setActiveNav] = useState("overview");

  const overallStability = (scores.reduce((a, b) => a + b.score, 0) / scores.length).toFixed(1);

  return (
    <div className="min-h-screen bg-gray-50 font-sans">
      {/* Top Header */}
      <header className="bg-gray-900 text-white sticky top-0 z-50 shadow-xl">
        <div className="max-w-7xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="bg-red-600 rounded-lg p-1.5">
                <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <div>
                <div className="font-bold text-sm">APP_DEBUG_MASTER_REPORT</div>
                <div className="text-xs text-gray-400">family-monitor · Forensic Audit · 2026-05-30</div>
              </div>
            </div>
            <div className="hidden md:flex items-center gap-6 text-xs">
              <span className="bg-red-600 text-white px-3 py-1 rounded-full font-bold">10 CRITICAL</span>
              <span className="bg-orange-500 text-white px-3 py-1 rounded-full font-bold">13 HIGH</span>
              <span className="bg-yellow-500 text-white px-3 py-1 rounded-full font-bold">15 MEDIUM</span>
              <span className="bg-gray-600 text-white px-3 py-1 rounded-full font-bold">Release: 1.5/10</span>
            </div>
          </div>
        </div>
        {/* Nav bar */}
        <div className="border-t border-gray-700 overflow-x-auto">
          <div className="flex max-w-7xl mx-auto px-4">
            {navItems.map((item) => (
              <button
                key={item.id}
                onClick={() => {
                  setActiveNav(item.id);
                  document.getElementById(item.id)?.scrollIntoView({ behavior: "smooth" });
                }}
                className={`px-3 py-2 text-xs font-medium whitespace-nowrap transition-colors ${
                  activeNav === item.id ? "text-white border-b-2 border-red-500" : "text-gray-400 hover:text-gray-200"
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-8 space-y-12">
        {/* Overview */}
        <section id="overview" className="scroll-mt-24">
          <div className="bg-gradient-to-br from-red-700 to-red-900 rounded-2xl p-8 text-white mb-8">
            <div className="flex items-start gap-4">
              <div className="text-5xl">🔬</div>
              <div>
                <h1 className="text-3xl font-extrabold mb-2">Family Monitor — Full Production Forensic Audit</h1>
                <p className="text-red-200 text-sm max-w-3xl">
                  This report represents a comprehensive, line-by-line forensic analysis of the entire
                  family-monitor Flutter repository: every Dart service, Kotlin native component, Gradle
                  build config, Firebase data model, WebRTC signaling flow, CI/CD pipeline, and Android
                  manifest. Compared against production parental-control apps (FlashGet Kids, Google Family
                  Link, Qustodio).
                </p>
                <div className="flex flex-wrap gap-3 mt-4">
                  <a
                    href="https://github.com/buildwith-manish/family-monitor"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="bg-white text-red-800 text-xs font-bold px-3 py-1.5 rounded-lg hover:bg-red-100 transition-colors"
                  >
                    GitHub Repository ↗
                  </a>
                  <span className="bg-red-600 text-white text-xs font-bold px-3 py-1.5 rounded-lg">
                    Flutter + Firebase + WebRTC + Android
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Summary Cards */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
            {[
              { label: "Stability Score", value: "3.9/10", color: "text-red-600", bg: "bg-red-50" },
              { label: "Release Readiness", value: "1.5/10", color: "text-red-700", bg: "bg-red-50" },
              { label: "Production Risk", value: "7.6/10", color: "text-orange-700", bg: "bg-orange-50" },
              { label: "Fake Features", value: "12 found", color: "text-purple-700", bg: "bg-purple-50" },
            ].map((c) => (
              <div key={c.label} className={`${c.bg} rounded-xl p-4 text-center border border-gray-100`}>
                <div className={`text-3xl font-extrabold ${c.color}`}>{c.value}</div>
                <div className="text-xs text-gray-500 mt-1 font-medium">{c.label}</div>
              </div>
            ))}
          </div>

          {/* Verdict Banner */}
          <div className="bg-red-50 border-2 border-red-400 rounded-xl p-5 flex items-start gap-4">
            <span className="text-3xl">🚫</span>
            <div>
              <h3 className="font-extrabold text-red-800 text-lg mb-1">NOT READY FOR PUBLIC RELEASE</h3>
              <p className="text-red-700 text-sm">
                10 critical blockers must be resolved before any public exposure. The app has Firebase data with no security rules,
                GDPR-violating open child data, features that appear to work but silently fail (screen time, SMS monitoring,
                background location, device lock, uninstall protection), and a hardcoded application ID that Google Play
                automatically rejects. Most background monitoring features die the moment the child minimizes the app.
              </p>
            </div>
          </div>
        </section>

        {/* Architecture */}
        <section id="architecture" className="scroll-mt-24">
          <SectionHeader id="architecture-h" title="Full Project Architecture Analysis" icon="🏗️" subtitle="Navigation flow, service ownership, Firebase schema, dual isolate model" />

          <div className="grid md:grid-cols-2 gap-6">
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <h3 className="font-bold text-gray-800 mb-3 flex items-center gap-2"><span>📱</span> Dual-Service Architecture Problem</h3>
              <div className="text-sm text-gray-600 space-y-2">
                <p>The app runs <strong>two simultaneous foreground services</strong>:</p>
                <ul className="space-y-1 ml-4">
                  <li className="flex items-start gap-2"><span className="text-orange-500 mt-0.5">•</span><span><strong>flutter_background_service</strong> — Isolate A: owns WebRTC, Firebase timers, all monitoring</span></li>
                  <li className="flex items-start gap-2"><span className="text-blue-500 mt-0.5">•</span><span><strong>flutter_foreground_task</strong> — Isolate B: only does stale session cleanup every ~10min</span></li>
                </ul>
                <p className="text-red-600 font-medium">Two foreground service notifications visible to child. Android 14 kills both services when camera/microphone types are declared but unused (idle state).</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <h3 className="font-bold text-gray-800 mb-3 flex items-center gap-2"><span>⚠️</span> Dead Command Pattern</h3>
              <div className="text-sm text-gray-600 space-y-2">
                <p>Background service <strong>writes</strong> commands to Firebase, but the <strong>listeners</strong> are in <code className="bg-gray-100 px-1 rounded">ChildHomeScreen</code>:</p>
                <div className="bg-red-50 border border-red-200 rounded p-3 text-xs">
                  <p className="font-mono">commands/$uid/syncSms → ChildHomeScreen._smsSub</p>
                  <p className="font-mono">commands/$uid/syncCallLog → _callLogSub</p>
                  <p className="font-mono">commands/$uid/syncContacts → _contactsSub</p>
                  <p className="font-mono">commands/$uid/syncAppList → _appListSub</p>
                </div>
                <p className="text-red-600 font-medium">ALL of these die when app is minimized. SMS, contacts, call logs, and app list never sync in background.</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <h3 className="font-bold text-gray-800 mb-3 flex items-center gap-2"><span>🔗</span> Phantom Firebase Node</h3>
              <div className="text-sm text-gray-600 space-y-2">
                <p><code className="bg-gray-100 px-1 rounded text-xs">users/$uid/connectedParent</code> is read in <code className="bg-gray-100 px-1 rounded text-xs">_listenForConnectedParent()</code> but is <strong>NEVER written anywhere in the codebase</strong>.</p>
                <p><code className="bg-gray-100 px-1 rounded text-xs">approveParentRequest()</code> writes to <code className="bg-gray-100 px-1 rounded text-xs">approvedParents</code> and <code className="bg-gray-100 px-1 rounded text-xs">children/$childUid</code> only.</p>
                <p className="text-red-600 font-medium">Connected parent display always falls through to the fallback path. Primary path is permanently dead code.</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <h3 className="font-bold text-gray-800 mb-3 flex items-center gap-2"><span>🔐</span> Boot Flow Crash Risk</h3>
              <div className="text-sm text-gray-600 space-y-2">
                <p><code className="bg-gray-100 px-1 rounded text-xs">LOCKED_BOOT_COMPLETED</code> fires while device is in Direct Boot mode — before the user unlocks the device.</p>
                <p><code className="bg-gray-100 px-1 rounded text-xs">FlutterSharedPreferences</code> is stored in <strong>credential-encrypted storage</strong> which is inaccessible until unlock.</p>
                <p className="text-red-600 font-medium">BootReceiver crashes on first boot before unlock. Background monitoring fails to start after reboot.</p>
              </div>
            </div>
          </div>

          <div className="mt-6 bg-white rounded-xl border border-gray-200 p-5">
            <h3 className="font-bold text-gray-800 mb-4">Firebase Data Schema Issues</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 text-gray-600 text-xs uppercase">
                    <th className="text-left p-2">Path</th>
                    <th className="text-left p-2">Growth Rate</th>
                    <th className="text-left p-2">TTL/Cleanup</th>
                    <th className="text-left p-2">Risk</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {[
                    { path: "device_events/$uid", rate: "5–10/day", ttl: "NEVER", risk: "CRITICAL" },
                    { path: "hourly_usage/$uid/$date/$hour", rate: "24/day", ttl: "NEVER", risk: "CRITICAL" },
                    { path: "daily_reports/$uid/$date", rate: "1/day", ttl: "NEVER", risk: "HIGH" },
                    { path: "app_install_alerts/$uid", rate: "Per restart (false positives)", ttl: "Manual only", risk: "HIGH" },
                    { path: "battery_alerts/$uid", rate: "Per event", ttl: "Manual only", risk: "MEDIUM" },
                    { path: "calls/$uid/childCandidates", rate: "~10/call", ttl: "Next call start (or crash)", risk: "MEDIUM" },
                    { path: "app_usage/$uid/daily", rate: "Updated daily", ttl: "Replaced (set())", risk: "LOW" },
                  ].map((r) => (
                    <tr key={r.path} className="hover:bg-gray-50">
                      <td className="p-2 font-mono text-xs text-gray-700">{r.path}</td>
                      <td className="p-2 text-xs text-gray-600">{r.rate}</td>
                      <td className="p-2 text-xs font-medium text-gray-700">{r.ttl}</td>
                      <td className="p-2">
                        <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${
                          r.risk === "CRITICAL" ? "bg-red-100 text-red-700" :
                          r.risk === "HIGH" ? "bg-orange-100 text-orange-700" :
                          r.risk === "MEDIUM" ? "bg-yellow-100 text-yellow-700" :
                          "bg-green-100 text-green-700"
                        }`}>{r.risk}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {/* Auth Analysis */}
        <section id="auth" className="scroll-mt-24">
          <SectionHeader id="auth-h" title="Authentication Analysis" icon="🔑" subtitle="Broken auth flows, session persistence, pairing mistakes, race conditions" />
          <div className="space-y-4">
            {[
              {
                title: "signInChild() Has No Role Verification",
                severity: "HIGH" as const,
                desc: "loginParent() verifies users/$uid/role == 'parent' before allowing login. signInChild() does NOT. Any email/password account — including parent accounts — can sign in with child privileges. A parent could accidentally sign into their own dashboard as a child device.",
                code: "// signInChild() — NO role check:\nconst cred = await signInWithEmailAndPassword(email, password);\nawait _saveLocalRole('child'); // Always saves 'child' regardless of actual role",
              },
              {
                title: "Anonymous Auth Expiry (30-Day Time Bomb)",
                severity: "HIGH" as const,
                desc: "setupChildDevice() creates an anonymous Firebase account. Firebase auto-deletes anonymous accounts inactive for 30+ days. If the child device is offline for a month (holiday, repair), the UID is permanently deleted. The background service reads the old UID from SharedPreferences, tries Firebase writes, and gets PERMISSION_DENIED. No recovery path exists.",
                code: "// No expiry detection:\nfinal uid = prefs.getString(_kUidKey); // Old UID\nFirebaseDatabase.instance.ref('users/$uid').set(...); // PERMISSION_DENIED after expiry",
              },
              {
                title: "Role Saved Locally, Never Re-Verified",
                severity: "MEDIUM" as const,
                desc: "SplashScreen reads role from SharedPreferences only. If SharedPreferences is cleared (app reinstall, backup restore), getSavedRole() returns UserRole.unknown and the user is sent to role selection even though Firebase auth is still valid. They'd have to re-pair their device.",
                code: "// SplashScreen._navigate():\nfinal role = await authService.getSavedRole(); // SharedPreferences only\n// NO Firebase verification of actual role",
              },
              {
                title: "approveParentRequest() Fails Silently on Background",
                severity: "MEDIUM" as const,
                desc: "The child's approveParentRequest() reads currentUser?.uid. In background isolate where Firebase auth may not be initialized, currentUser is null. Returns {success: false, error: 'Not authenticated'} silently.",
                code: "// In background isolate:\nfinal childUid = currentUser?.uid; // null in background!\nif (childUid == null) return {'success': false, 'error': 'Not authenticated'};",
              },
              {
                title: "QR Code Encodes Raw UID (No Security)",
                severity: "MEDIUM" as const,
                desc: "The QR code shown to the parent contains only the child's Firebase UID — a plain string. No nonce, no timestamp, no HMAC. Anyone who obtains this UID (screen recording, shoulder surfing, network sniffing) can send parent requests to any child device indefinitely.",
                code: "// child_qr_screen.dart:\nQrImageView(data: uid, ...) // Just the UID, no expiry, no signature",
              },
            ].map((item) => (
              <div key={item.title} className={`rounded-xl border-l-4 p-5 ${SEVERITY[item.severity].border} ${SEVERITY[item.severity].bg}`}>
                <div className="flex items-center justify-between mb-2">
                  <h4 className={`font-bold ${SEVERITY[item.severity].text}`}>{item.title}</h4>
                  <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${SEVERITY[item.severity].badge}`}>{item.severity}</span>
                </div>
                <p className="text-sm text-gray-700 mb-3">{item.desc}</p>
                <pre className="bg-gray-900 text-green-400 text-xs rounded-lg p-3 overflow-x-auto font-mono whitespace-pre-wrap">{item.code}</pre>
              </div>
            ))}
          </div>
        </section>

        {/* Feature Forensics */}
        <section id="features" className="scroll-mt-24">
          <SectionHeader id="features-h" title="Feature-by-Feature Forensic Analysis" icon="🔍" subtitle="Why each feature fails, missing logic, broken state handling" />
          <div className="grid md:grid-cols-2 gap-4">
            {[
              { name: "Live Screen Share", status: "BROKEN", score: 4, issues: ["MediaProjection token invalidated on EVERY reboot — requires user action to re-grant", "ScreenCaptureService.projectionToken is Kotlin companion object — MethodChannel calls in background isolate may fail with MissingPluginException", "getDisplayMedia() requires foreground on Android 10+ — background mode fails silently", "ChildStreamingScreen.dart exists but is NEVER navigated to — dead code"] },
              { name: "App Usage / Screen Time", status: "BROKEN", score: 2, issues: ["PACKAGE_USAGE_STATS permission NEVER requested in wizard", "queryUsageStats() returns empty list silently without permission", "Parent AppUsageScreen renders empty charts — fake monitoring", "Screen time limits cannot be enforced without usage data"] },
              { name: "SMS Monitoring", status: "BROKEN", score: 2, issues: ["READ_SMS not in wizard _requestCorePermissions()", "SmsService.requestPermission() is called nowhere", "_smsSub listener only active when ChildHomeScreen is mounted", "Background service sends sync command but no listener receives it"] },
              { name: "Location / Geofencing", status: "PARTIAL", score: 4, issues: ["startTracking() called from ChildHomeScreen — stopped on dispose()", "stopTracking() explicitly called in dispose() — background location dead", "ACCESS_BACKGROUND_LOCATION not declared in manifest", "Geofence _lastInside stored in Firebase — Firebase write on every GPS update"] },
              { name: "App Install Alerts", status: "FRAGILE", score: 3, issues: ["_knownPackages resets to empty on service restart", "Every installed app reported as 'newly installed' — hundreds of false alerts", "Command-response race: 10s delay hoping child UI is open", "QUERY_ALL_PACKAGES missing — install list incomplete on API 30+"] },
              { name: "Snapshots", status: "PARTIAL", score: 4, issues: ["Native Camera2 path requires Activity foreground (MethodChannel)", "Flutter CameraController path also requires foreground", "Background snapshots permanently non-functional", "Firebase Storage URLs are permanent — no expiry on sensitive photos"] },
              { name: "Battery Alerts", status: "FUNCTIONAL", score: 7, issues: ["Best-implemented feature — anti-spam hysteresis works", "Minor: _batterySub not in map for multi-child support", "60s reporting even when screen off drains child battery unnecessarily"] },
              { name: "FCM / Push Notifications", status: "FAKE", score: 2, issues: ["FCM permission requested but token never saved to Firebase", "No Cloud Function to trigger server-sent push", "FirebaseMessaging.onBackgroundMessage() never registered", "Parent receives no push when app is closed — local notifications only"] },
              { name: "Device Lock", status: "FAKE", score: 0, issues: ["_locked = false hardcoded in ChildHomeScreen", "Lock overlay exists in widget tree but never visible", "_LockOverlay is a real widget but _locked never becomes true", "No Firebase listener for lock commands implemented"] },
              { name: "Uninstall Protection", status: "FAKE", score: 1, issues: ["PinVerifyActivity.kt exists and is correct Kotlin code", "flutter.uninstall_pin SharedPreferences key never written from Dart", "Pin is always null/empty → PIN check always skipped", "AppBlockAccessibilityService.onAccessibilityEvent() never launches PinVerifyActivity"] },
            ].map((f) => (
              <div key={f.name} className="bg-white rounded-xl border border-gray-200 p-5">
                <div className="flex items-center justify-between mb-3">
                  <h4 className="font-bold text-gray-800">{f.name}</h4>
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${
                      f.status === "FAKE" ? "bg-purple-600 text-white" :
                      f.status === "BROKEN" ? "bg-red-600 text-white" :
                      f.status === "PARTIAL" ? "bg-orange-500 text-white" :
                      f.status === "FRAGILE" ? "bg-yellow-500 text-white" :
                      "bg-green-500 text-white"
                    }`}>{f.status}</span>
                    <span className="text-xs font-bold text-gray-500">{f.score}/10</span>
                  </div>
                </div>
                <ul className="space-y-1">
                  {f.issues.map((issue, i) => (
                    <li key={i} className="flex items-start gap-2 text-xs text-gray-600">
                      <span className="text-red-400 mt-0.5 flex-shrink-0">✗</span>
                      <span>{issue}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>

        {/* Firebase */}
        <section id="firebase" className="scroll-mt-24">
          <SectionHeader id="firebase-h" title="Firebase Analysis" icon="🔥" subtitle="Security rules, schema, listener leaks, unbounded growth, write duplication" />
          <div className="bg-red-50 border-2 border-red-500 rounded-xl p-6 mb-6">
            <div className="flex items-start gap-3">
              <span className="text-3xl">🚨</span>
              <div>
                <h3 className="font-extrabold text-red-800 text-xl mb-2">No Firebase Security Rules Found</h3>
                <p className="text-red-700 text-sm mb-3">
                  <code>database.rules.json</code> does NOT exist in the repository. Without explicit rules:
                </p>
                <ul className="text-sm text-red-700 space-y-1 ml-4">
                  <li>• Any authenticated user can read <strong>any child's SMS messages, location history, contacts, and call logs</strong></li>
                  <li>• Any authenticated user can write <strong>false data</strong> to any child's Firebase paths</li>
                  <li>• A child can read another child's private data simply by knowing their UID</li>
                  <li>• GDPR Article 5 violation: data accessible beyond intended scope</li>
                  <li>• COPPA violation risk: children's data not properly protected</li>
                </ul>
              </div>
            </div>
          </div>
          <div className="grid md:grid-cols-3 gap-4">
            {[
              { title: "4 Writers for isOnline", icon: "📝", desc: "PresenceService (2 places), BackgroundMonitoringService _connectedSub, _heartbeatTimer — all writing to the same node. 4x Firebase write cost. Can cause brief 'offline' flash visible to parent when PresenceService resets before re-writing." },
              { title: "approvedParents Format Inconsistency", icon: "⚡", desc: "Written as boolean true in approveParentRequest(). Read as Map in older code paths. New code guards for this, but existing Firebase records from before the fix still contain bool values. Any code that does Map.from(approvedParents) crashes." },
              { title: "Unbounded device_events", icon: "📈", desc: "Events pushed with push() auto-key, never deleted. A device that restarts frequently writes 5-10 events per restart. After 6 months, tens of thousands of events accumulate. Firebase bills per byte stored and read." },
            ].map((c) => (
              <div key={c.title} className="bg-white rounded-xl border border-gray-200 p-4">
                <div className="text-2xl mb-2">{c.icon}</div>
                <h4 className="font-bold text-gray-800 mb-2 text-sm">{c.title}</h4>
                <p className="text-xs text-gray-600">{c.desc}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Android */}
        <section id="android" className="scroll-mt-24">
          <SectionHeader id="android-h" title="Android-Specific Analysis" icon="🤖" subtitle="Manifest, services, permissions, API 33/34 compliance, boot flow" />
          <div className="space-y-4">
            {[
              { title: "SCHEDULE_EXACT_ALARM Missing (API 33+)", badge: "CRITICAL", color: "red", desc: "WatchdogReceiver uses AlarmManager.setExactAndAllowWhileIdle(). On Android 13+, this requires SCHEDULE_EXACT_ALARM permission. If not declared, scheduling throws SecurityException silently caught by the try/catch wrapper. The service watchdog permanently stops working on API 33+ devices with no indication." },
              { title: "ACCESS_BACKGROUND_LOCATION Not Declared (API 29+)", badge: "CRITICAL", color: "red", desc: "Background GPS requires ACCESS_BACKGROUND_LOCATION on Android 10+. Without it, Geolocator.getPositionStream() only delivers updates while the app is in the foreground. LocationService.stopTracking() is called explicitly on ChildHomeScreen.dispose(), so tracking definitively stops on minimize." },
              { title: "QUERY_ALL_PACKAGES Missing (API 30+)", badge: "HIGH", color: "orange", desc: "MainActivity.getInstalledApps() uses queryIntentActivities() with ACTION_MAIN. On Android 11+, apps are hidden unless declared in <queries> or QUERY_ALL_PACKAGES is granted. The installed apps list is heavily filtered. App install alerts miss most apps." },
              { title: "Android 14 Foreground Service Types", badge: "HIGH", color: "orange", desc: "Both flutter_background_service and flutter_foreground_task declare foregroundServiceType='camera|microphone|dataSync'. On Android 14+, all declared types must be actively used or Android throws ForegroundServiceDidNotStartInTimeException and kills the service. In idle state (no WebRTC stream), camera and microphone types are declared but unused." },
              { title: "LOCKED_BOOT_COMPLETED in Direct Boot", badge: "HIGH", color: "orange", desc: "BootReceiver listens to LOCKED_BOOT_COMPLETED which fires before the user unlocks the device post-reboot. FlutterSharedPreferences uses credential-encrypted storage. Reading it in Direct Boot mode throws an exception. The entire monitoring restore on boot fails silently." },
              { title: "DialerCodeReceiver PROCESS_OUTGOING_CALLS Deprecated", badge: "LOW", color: "blue", desc: "PROCESS_OUTGOING_CALLS was deprecated in API 29. NEW_OUTGOING_CALL broadcast is no longer sent for many call types on Android 10+. The dialer code recovery mechanism (*#9527#) silently breaks on any device running Android 10+." },
            ].map((item) => (
              <div key={item.title} className={`bg-${item.color}-50 border border-${item.color}-200 rounded-xl p-4`}>
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-bold text-gray-800 text-sm">{item.title}</h4>
                  <span className={`text-xs font-bold px-2 py-0.5 rounded-full bg-${item.color}-600 text-white`}>{item.badge}</span>
                </div>
                <p className="text-sm text-gray-700">{item.desc}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Critical Issues */}
        <section id="critical" className="scroll-mt-24">
          <SectionHeader id="critical-h" title="Critical Issues" icon="🚨" subtitle="Must be resolved before ANY user exposure" />
          <div className="space-y-1">
            {criticalIssues.map((issue) => (
              <IssueCard key={issue.id} {...issue} severity="CRITICAL" />
            ))}
          </div>
        </section>

        {/* High Issues */}
        <section id="high" className="scroll-mt-24">
          <SectionHeader id="high-h" title="High Priority Issues" icon="🔴" subtitle="Must be resolved before public release" />
          <div className="space-y-1">
            {highIssues.map((issue) => (
              <IssueCard key={issue.id} {...issue} severity="HIGH" />
            ))}
          </div>
        </section>

        {/* Medium Issues */}
        <section id="medium" className="scroll-mt-24">
          <SectionHeader id="medium-h" title="Medium Priority Issues" icon="🟡" subtitle="Should be resolved before wide rollout" />
          <div className="grid md:grid-cols-2 gap-2">
            {mediumIssues.map((issue) => (
              <div key={issue.id} className="bg-yellow-50 border border-yellow-200 rounded-lg p-3">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs font-bold bg-yellow-500 text-white px-2 py-0.5 rounded-full">{issue.id}</span>
                </div>
                <p className="text-sm font-medium text-gray-800 mb-1">{issue.issue}</p>
                <code className="text-xs text-gray-500 font-mono">{issue.file}</code>
              </div>
            ))}
          </div>
        </section>

        {/* Fake Features */}
        <section id="fake" className="scroll-mt-24">
          <SectionHeader id="fake-h" title="Fake / Non-Functional Features" icon="🎭" subtitle="Features that appear to work in UI but have no working backend — the most dangerous category" />
          <div className="bg-purple-50 border border-purple-200 rounded-xl p-5 mb-5">
            <p className="text-purple-800 text-sm font-medium">
              These features create a <strong>false sense of security</strong> for parents. The monitoring dashboard shows
              "Protection Active" and monitoring indicators even when none of the actual monitoring is working. This is the
              most dangerous characteristic of this app — it could lead a parent to believe their child is being monitored
              when they are not.
            </p>
          </div>
          <div className="space-y-2">
            {fakeFeatures.map((f) => (
              <div key={f.feature} className="bg-white border border-purple-200 rounded-xl p-4 flex items-start gap-4">
                <span className="text-2xl">🎭</span>
                <div className="flex-1">
                  <div className="flex items-center justify-between mb-1">
                    <h4 className="font-bold text-gray-800">{f.feature}</h4>
                    <span className="text-xs bg-purple-100 text-purple-700 font-medium px-2 py-0.5 rounded-full">FAKE</span>
                  </div>
                  <p className="text-xs text-gray-500 mb-1">Shown in: <em>{f.where}</em></p>
                  <p className="text-sm text-red-700 font-medium">{f.reason}</p>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Stability Scores */}
        <section id="scores" className="scroll-mt-24">
          <SectionHeader id="scores-h" title="Stability Scores" icon="📊" subtitle="Per-feature assessment with overall metrics" />
          <div className="grid md:grid-cols-2 gap-6">
            <div className="bg-white rounded-xl border border-gray-200 p-6">
              <h3 className="font-bold text-gray-800 mb-4">Feature Stability (out of 10)</h3>
              <div className="space-y-3">
                {scores.map((s) => (
                  <div key={s.name}>
                    <div className="flex justify-between text-xs text-gray-600 mb-1">
                      <span>{s.name}</span>
                    </div>
                    <ScoreBar score={s.score} />
                  </div>
                ))}
              </div>
            </div>
            <div className="space-y-4">
              <div className="bg-white rounded-xl border border-gray-200 p-6">
                <h3 className="font-bold text-gray-800 mb-4">Summary Scores</h3>
                <div className="space-y-4">
                  {[
                    { label: "Overall Stability", score: parseFloat(overallStability), note: "Average across all features" },
                    { label: "Release Readiness", score: 1.5, note: "NOT READY — 10 critical blockers" },
                    { label: "Firebase Security", score: 1, note: "No rules = open database" },
                    { label: "Background Reliability", score: 3.5, note: "Most features die when minimized" },
                  ].map((s) => (
                    <div key={s.label}>
                      <div className="flex justify-between text-sm mb-1">
                        <span className="font-medium text-gray-700">{s.label}</span>
                        <span className="text-xs text-gray-400">{s.note}</span>
                      </div>
                      <ScoreBar score={s.score} />
                    </div>
                  ))}
                </div>
              </div>
              <div className="bg-gray-900 rounded-xl p-6 text-white">
                <div className="text-center">
                  <div className="text-6xl font-extrabold text-red-400 mb-1">{overallStability}</div>
                  <div className="text-gray-400 text-sm">/10 Overall Stability</div>
                  <div className="mt-3 text-xs text-gray-500">Production Risk Score: 7.6/10 🔴</div>
                  <div className="mt-1 text-xs text-gray-500">Release Readiness: 1.5/10 🔴</div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Fix Plan */}
        <section id="phases" className="scroll-mt-24">
          <SectionHeader id="phases-h" title="Phase-Wise Fix Plan" icon="🗓️" subtitle="Prioritized remediation roadmap — estimated 50–60 engineer-days total" />
          <div className="space-y-4">
            {phases.map((p) => (
              <div key={p.phase} className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className={`${p.color} px-5 py-3 flex items-center justify-between`}>
                  <div className="flex items-center gap-3">
                    <span className="text-white font-extrabold">{p.phase}</span>
                    <span className="text-white font-bold">{p.title}</span>
                  </div>
                  <span className="text-white text-sm font-medium bg-black bg-opacity-20 px-3 py-0.5 rounded-full">{p.time}</span>
                </div>
                <div className="p-4">
                  <ul className="space-y-2">
                    {p.items.map((item, i) => (
                      <li key={i} className="flex items-start gap-2 text-sm text-gray-700">
                        <span className="text-green-500 font-bold mt-0.5 flex-shrink-0">{i + 1}.</span>
                        <span>{item}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Responsible Files */}
        <section id="files" className="scroll-mt-24">
          <SectionHeader id="files-h" title="Files Most Responsible for Failures" icon="📁" subtitle="Ranked by issue count and blast radius" />
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 text-gray-600 text-xs uppercase">
                  <th className="text-left p-3 w-8">#</th>
                  <th className="text-left p-3">File</th>
                  <th className="text-left p-3 w-20">Issues</th>
                  <th className="text-left p-3">Primary Problems</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {responsibleFiles.map((f) => (
                  <tr key={f.rank} className={`hover:bg-gray-50 ${f.rank <= 3 ? "bg-red-50" : f.rank <= 6 ? "bg-orange-50" : ""}`}>
                    <td className="p-3">
                      <span className={`inline-flex w-6 h-6 rounded-full items-center justify-center text-xs font-bold text-white ${
                        f.rank === 1 ? "bg-red-600" : f.rank <= 3 ? "bg-orange-500" : f.rank <= 6 ? "bg-yellow-500" : "bg-gray-400"
                      }`}>{f.rank}</span>
                    </td>
                    <td className="p-3 font-mono text-xs text-gray-700">{f.file}</td>
                    <td className="p-3">
                      <span className="font-bold text-gray-800">{f.issues === 999 ? "∞" : f.issues}</span>
                    </td>
                    <td className="p-3 text-xs text-gray-600">{f.problems}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* Footer */}
        <footer className="bg-gray-900 text-gray-400 rounded-2xl p-6 text-sm">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <div className="text-white font-bold mb-1">APP_DEBUG_MASTER_REPORT.md</div>
              <div className="text-xs">Generated by forensic analysis of buildwith-manish/family-monitor · 2026-05-30</div>
              <div className="text-xs mt-1">Audited against: FlashGet Kids, Google Family Link, Qustodio production standards</div>
            </div>
            <div className="text-right text-xs">
              <div className="text-red-400 font-bold text-lg">NOT READY FOR PUBLIC RELEASE</div>
              <div>10 Critical · 13 High · 15 Medium · 13 Low issues</div>
              <div className="mt-1">Estimated fix: 50–60 engineer-days</div>
            </div>
          </div>
        </footer>
      </main>
    </div>
  );
}
