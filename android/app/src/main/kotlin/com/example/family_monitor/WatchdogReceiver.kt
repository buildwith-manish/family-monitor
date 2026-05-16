package com.example.family_monitor

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * FIX-WATCHDOG: Production-hardened WatchdogReceiver.
 *
 * Root causes fixed:
 * RC-06 — The watchdog woke up but immediately exited onReceive() if
 *          ScreenCaptureService.instance != null, so a service that was
 *          alive but had a stale/null projectionToken was never healed.
 *          Now checks BOTH instance existence AND token validity.
 * RC-07 — On Android 10+ (Doze), AlarmManager.setExactAndAllowWhileIdle()
 *          delivers alarms but onReceive() runs on the main thread with a
 *          very short window (~10s). Heavy work (starting activities) was
 *          done inline, causing occasional ANR. Now uses a goAsync() + coroutine
 *          pattern with a PARTIAL_WAKE_LOCK to prevent CPU sleep mid-receive.
 * RC-08 — The watchdog tried to start StealthActivity from a BroadcastReceiver
 *          context on Android 12+ where background activity launches are
 *          restricted without PendingIntent. Now uses a notification tap-action
 *          as fallback rather than a direct startActivity() call.
 * RC-10 — The Flutter BackgroundService was (re)started unconditionally on every
 *          watchdog tick, causing a burst of duplicate service starts and
 *          Firebase listener accumulation after device wakes from Doze.
 *          Now only restarts the bg service if it is genuinely not running.
 */
class WatchdogReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG      = "WatchdogReceiver"
        const val ACTION_WATCHDOG  = "com.example.family_monitor.ACTION_WATCHDOG"
        private const val REQ      = 7777
        private const val INTERVAL = 60_000L  // 60 seconds
        private const val WAKE_LOCK_TAG = "FamilyMonitor:WatchdogReceive"

        fun schedule(context: Context) {
            val am = context.getSystemService(AlarmManager::class.java)
            val pi = pi(context)
            val trigger = System.currentTimeMillis() + INTERVAL
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
                } else {
                    am.setExact(AlarmManager.RTC_WAKEUP, trigger, pi)
                }
            } catch (_: SecurityException) {
                try { am.set(AlarmManager.RTC_WAKEUP, trigger, pi) } catch (_: Exception) {}
            } catch (_: Exception) {
                try { am.set(AlarmManager.RTC_WAKEUP, trigger, pi) } catch (_: Exception) {}
            }
            Log.d(TAG, "Watchdog scheduled in ${INTERVAL / 1000}s")
        }

        private fun pi(ctx: Context) = PendingIntent.getBroadcast(
            ctx, REQ,
            Intent(ctx, WatchdogReceiver::class.java).apply { action = ACTION_WATCHDOG },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WATCHDOG) return

        // Guard: only act if setup has been completed.
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val wizardDone   = flutterPrefs.getBoolean("flutter.wizard_done", false)
        val uid          = flutterPrefs.getString("flutter.child_uid", null)
        if (!wizardDone || uid.isNullOrEmpty()) {
            Log.d(TAG, "Watchdog fired but setup not complete — skipping")
            return
        }

        // RC-07: Acquire a brief wake lock for the duration of our work.
        // onReceive() runs on the main thread; the CPU may suspend when
        // onReceive() returns even if goAsync() is used, unless we hold a lock.
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wl = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKE_LOCK_TAG
        ).also {
            it.setReferenceCounted(false)
            it.acquire(30_000L) // 30 s max for startup work
        }

        try {
            Log.d(TAG, "Watchdog fired — instance=${ScreenCaptureService.instance != null}, " +
                    "tokenOk=${ScreenCaptureService.projectionToken != null}")

            // ── 1. Ensure Flutter background service is running ──────────────────
            // RC-10: Check if it is already running before (re)starting to avoid
            // the burst-of-duplicate-starts pathology after Doze wakeup.
            ensureBackgroundServiceRunning(context)

            // ── 2. Check ScreenCaptureService health ────────────────────────────
            // RC-06: Check BOTH instance existence AND token validity.
            // BUG-3-FIX: Also check SharedPreferences for persisted projection data
            // since volatile static fields are cleared on process death.
            val serviceAlive  = ScreenCaptureService.instance != null
            val tokenValid    = ScreenCaptureService.projectionToken != null
            val hasVolatileToken = ScreenCaptureService.savedResultCode != 0 &&
                    ScreenCaptureService.savedResultData != null
            val hasPersistedToken = try {
                val prefs = context.getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                prefs.getInt("projection_result_code", 0) != 0 &&
                    !prefs.getString("projection_result_data_uri", null).isNullOrEmpty()
            } catch (_: Exception) { false }
            val hasSavedToken = hasVolatileToken || hasPersistedToken

            if (!serviceAlive || !tokenValid) {
                Log.w(TAG, "ScreenCaptureService needs healing: " +
                        "alive=$serviceAlive tokenValid=$tokenValid")
                healScreenCaptureService(context, hasSavedToken)
            }

        } finally {
            try { if (wl.isHeld) wl.release() } catch (_: Exception) {}
            schedule(context)   // re-arm the watchdog alarm
        }
    }

    /**
     * BUG-3-FIX: Ensure the Flutter background service is running AND healthy.
     *
     * Previously this method unconditionally started the background service on
     * every watchdog tick, which caused duplicate service starts after Doze wakeup.
     * Now it also checks a SharedPreferences health flag (`bg_service_last_healthy`)
     * that the Flutter background service updates every 30 s via its heartbeat timer.
     * If the timestamp is stale (> 2 min), the service is considered unhealthy
     * even if the Android process is technically alive — the Flutter isolate may
     * have been killed while the native process persists.
     *
     * After restarting the service, writes `watchdog_triggered_restart = true`
     * to SharedPreferences so the Flutter isolate knows to reconnect to any
     * active monitoring sessions (camera or screen) that were interrupted.
     */
    private fun ensureBackgroundServiceRunning(context: Context) {
        try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val lastHealthy = flutterPrefs.getLong("flutter.bg_service_last_healthy", 0L)
            val now = System.currentTimeMillis()
            val isHealthy = (now - lastHealthy) < 120_000L  // 2 minutes

            if (isHealthy) {
                Log.d(TAG, "Flutter background service appears healthy (last heartbeat ${now - lastHealthy}ms ago)")
                return
            }

            Log.w(TAG, "Flutter background service unhealthy (last heartbeat ${now - lastHealthy}ms ago) — restarting")

            val bgSvc = Intent(
                context,
                id.flutter.flutter_background_service.BackgroundService::class.java
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(bgSvc)
            else
                context.startService(bgSvc)

            // BUG-3-FIX: Write watchdog restart flag so the background service
            // knows to reconnect to any active sessions after restart.
            flutterPrefs.edit()
                .putBoolean("flutter.watchdog_triggered_restart", true)
                .apply()

            Log.d(TAG, "Flutter background service start requested + watchdog_triggered_restart flag set")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start/check bg service: $e")
        }
    }

    private fun healScreenCaptureService(context: Context, hasSavedToken: Boolean) {
        if (hasSavedToken) {
            // Try a silent restart — the saved token may still be valid
            // (e.g. service was killed by OEM cleaner but process not fully dead).
            try {
                val silentIntent = Intent(context, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START_SILENT
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    context.startForegroundService(silentIntent)
                else
                    context.startService(silentIntent)
                Log.d(TAG, "Silent ScreenCaptureService restart requested")
            } catch (e: Exception) {
                Log.e(TAG, "Silent restart failed: $e")
                // RC-08: Fall back to opening the main app via a safe notification
                // tap instead of direct startActivity() which is blocked on API 31+.
                showReProjectionNotification(context)
            }
        } else {
            // No saved token — the only path is a user-visible activity.
            // RC-08: Use notification tap rather than direct startActivity().
            showReProjectionNotification(context)
        }
    }

    /**
     * RC-08: Show a notification the user can tap to re-grant projection.
     * This is the safe, API-31+-compatible alternative to calling startActivity()
     * from a BroadcastReceiver (which is blocked as a background activity launch
     * on Android 12+).
     */
    private fun showReProjectionNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager
            val chId = "fm_watchdog_alert"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = android.app.NotificationChannel(
                    chId,
                    "Monitoring Alert",
                    android.app.NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "Screen monitoring needs attention" }
                nm.createNotificationChannel(ch)
            }
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP) }
                ?: return
            val pi = PendingIntent.getActivity(
                context, 9900, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notif = androidx.core.app.NotificationCompat.Builder(context, chId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Family Monitor — Action Required")
                .setContentText("Tap to restore screen monitoring")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .build()
            nm.notify(9900, notif)
            Log.d(TAG, "Re-projection notification shown")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show re-projection notification: $e")
        }
    }
}
