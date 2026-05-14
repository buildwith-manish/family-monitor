package com.example.family_monitor

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * FIX-02: Accessibility-based app blocking.
 *
 * Intercepts TYPE_WINDOW_STATE_CHANGED events to:
 *  1. Block apps that the parent has restricted — sends the user home.
 *  2. Detect when the child navigates to Settings to uninstall this app —
 *     launches PinVerifyActivity so they must enter their safety PIN first.
 *
 * The list of blocked packages is synced from Firebase by the Flutter
 * background service via SharedPreferences (key: "flutter.blocked_packages").
 *
 * The user must grant this service once via:
 *   Settings → Accessibility → Family Monitor App Block → Enable
 */
class AppBlockAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG        = "AppBlockA11y"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PREFS_KEY  = "flutter.blocked_packages"
        private const val PIN_KEY    = "flutter.uninstall_pin"

        // Settings packages that host the App Info / Uninstall screens
        private val SETTINGS_PACKAGES = setOf(
            "com.android.settings",
            "com.samsung.android.settings",
            "com.miui.securitycenter",
            "com.huawei.systemmanager",
            "com.oppo.settings",
            "com.oneplus.settings"
        )

        // Class-name fragments that indicate the App Info detail page
        private val APP_INFO_CLASSES = listOf(
            "AppInfoBase",
            "AppInfoDashboard",
            "AppDetails",
            "InstalledAppDetails",
            "AppDetailSettings",
            "AppInfo",
            "ManageApplicationsActivity"
        )
    }

    private lateinit var flutterPrefs: SharedPreferences

    // Prevent spamming PIN activity if it is already showing
    private var pinLaunchedAt = 0L
    private val PIN_COOLDOWN_MS = 4_000L

    override fun onServiceConnected() {
        super.onServiceConnected()
        flutterPrefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg       = event.packageName?.toString() ?: return
        val className = event.className?.toString()   ?: ""

        // ── 1. Uninstall intercept ───────────────────────────────────────────
        // Trigger when the child opens Settings and lands on the App Info page
        // for THIS app. We require a PIN before they can proceed.
        if (pkg in SETTINGS_PACKAGES && APP_INFO_CLASSES.any { className.contains(it, ignoreCase = true) }) {
            val pin = flutterPrefs.getString(PIN_KEY, null)
            if (!pin.isNullOrEmpty()) {
                val now = System.currentTimeMillis()
                if (now - pinLaunchedAt > PIN_COOLDOWN_MS) {
                    pinLaunchedAt = now
                    Log.d(TAG, "App Info page detected in Settings — launching PIN gate")
                    PinVerifyActivity.launch(this)
                }
            }
        }

        // ── 2. App blocking ──────────────────────────────────────────────────
        // Never block ourselves — that would create an unrecoverable loop.
        if (pkg == packageName) return

        val blockedRaw = flutterPrefs.getString(PREFS_KEY, "") ?: ""
        if (blockedRaw.isBlank()) return

        val blocked = blockedRaw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()

        if (pkg in blocked) {
            Log.d(TAG, "Blocked app detected in foreground: $pkg — sending home")
            val home = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            try {
                startActivity(home)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send home: $e")
            }
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted")
    }
}
