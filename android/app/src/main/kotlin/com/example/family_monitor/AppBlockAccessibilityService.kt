package com.example.family_monitor

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * FIX-02: Accessibility-based app blocking.
 *
 * Intercepts TYPE_WINDOW_STATE_CHANGED events to detect when a blocked app
 * moves to the foreground, then immediately sends the user to the home screen.
 *
 * The list of blocked packages is synced from Firebase by the Flutter background
 * service via SharedPreferences (key: "flutter.blocked_packages"), so this
 * service never needs a network call — it reads a local flat file.
 *
 * The user must grant this service once via:
 *   Settings → Accessibility → Family Monitor App Block → Enable
 */
class AppBlockAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG        = "AppBlockA11y"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PREFS_KEY  = "flutter.blocked_packages"
    }

    private lateinit var flutterPrefs: SharedPreferences

    override fun onServiceConnected() {
        super.onServiceConnected()
        flutterPrefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return

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
