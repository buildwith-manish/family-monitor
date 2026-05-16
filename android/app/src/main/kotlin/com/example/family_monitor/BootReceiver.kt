package com.example.family_monitor

import android.app.ActivityManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * FIX-BOOT: Production-hardened BootReceiver.
 *
 * Root causes fixed:
 * RC-BOOT-01 — On LOCKED_BOOT_COMPLETED (Direct Boot mode, Android 7+),
 *              SharedPreferences may not be accessible because credential-
 *              encrypted storage isn't unlocked yet. The previous code
 *              crashed silently with a FileNotFoundException. Fixed: wrap
 *              prefs access in try/catch; on LOCKED_BOOT_COMPLETED, attempt
 *              a minimal service start without prefs validation.
 * RC-BOOT-02 — On MY_PACKAGE_REPLACED the app is being updated. If the
 *              Flutter background service was running it is killed by the
 *              update. The previous code tried startForegroundService but
 *              the new process had not yet created its notification channel,
 *              causing startForeground() inside BackgroundService to fail
 *              with "startForeground() not called within 5s" ANR on API 26+.
 *              Fixed: add a 500ms delay before starting services on
 *              MY_PACKAGE_REPLACED to let the new process initialize.
 * RC-BOOT-03 — WorkManager.enqueueUniquePeriodicWork was called with
 *              ExistingPeriodicWorkPolicy.KEEP, but after a full reboot
 *              WorkManager's database is intact and the old job may have
 *              drifted in schedule. Use CANCEL_AND_REENQUEUE on boot to
 *              reset the schedule from a known good baseline.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG      = "BootReceiver"
        private const val NOTIF_CH = "fm_resume_ch"
        private const val NOTIF_ID = 9201
    }

    override fun onReceive(context: Context, intent: Intent) {
        val valid = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            Intent.ACTION_MY_PACKAGE_REPLACED
        )
        if (intent.action !in valid) return

        Log.d(TAG, "Boot/install event: ${intent.action}")

        // RC-BOOT-01: LOCKED_BOOT_COMPLETED fires before credentials are
        // unlocked. Just arm the watchdog alarm and return — services will
        // be started when ACTION_BOOT_COMPLETED fires moments later.
        if (intent.action == "android.intent.action.LOCKED_BOOT_COMPLETED") {
            Log.d(TAG, "LOCKED_BOOT_COMPLETED — arming watchdog only")
            WatchdogReceiver.schedule(context)
            return
        }

        val wizardDone: Boolean
        val uid: String?
        val consentBefore: Boolean

        try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            wizardDone   = flutterPrefs.getBoolean("flutter.wizard_done", false)
            uid          = flutterPrefs.getString("flutter.child_uid", null)
            val fmPrefs  = context.getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            consentBefore = fmPrefs.getBoolean("projection_consent_granted", false)
        } catch (e: Exception) {
            Log.e(TAG, "Could not read prefs: $e — arming watchdog only")
            WatchdogReceiver.schedule(context)
            return
        }

        if (!wizardDone || uid.isNullOrEmpty()) {
            Log.d(TAG, "Setup not complete — skipping auto-start")
            return
        }

        // RC-BOOT-02: On MY_PACKAGE_REPLACED, delay slightly so the new
        // process has time to register its notification channels before
        // BackgroundService calls startForeground().
        val startDelayMs = if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) 800L else 0L

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({

            // ── 1. Flutter background service ──────────────────────────────────────
            if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED && isAppInForeground(context)) {
                Log.d(TAG, "MY_PACKAGE_REPLACED + app in foreground — skipping service restart")
            } else {
                try {
                    val bgSvc = Intent(context,
                        id.flutter.flutter_background_service.BackgroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        context.startForegroundService(bgSvc)
                    else context.startService(bgSvc)
                    Log.d(TAG, "Flutter background service started")

                    // BUG-3-FIX: Set watchdog restart flag so the background service
                    // knows to reconnect to any active monitoring sessions after boot
                    // or package update. Without this, the service starts fresh and
                    // won't reconnect to any ongoing screen/camera sessions.
                    try {
                        val fp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        fp.edit().putBoolean("flutter.watchdog_triggered_restart", true).apply()
                    } catch (_: Exception) {}
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start background service: $e")
                }
            }

            // ── 2. Screen-capture service (silent restart if token is saved) ────────
            // BUG-3-FIX: Start ScreenCaptureService on both BOOT_COMPLETED and
            // MY_PACKAGE_REPLACED. On full reboot, MediaProjection tokens are
            // invalidated, but the service still needs to start so it can:
            //   - Hold the foreground notification (required by Android)
            //   - Detect the invalid token and prompt re-consent via notification
            // On MY_PACKAGE_REPLACED, saved tokens may still be valid.
            val shouldStartCapture = when (intent.action) {
                Intent.ACTION_MY_PACKAGE_REPLACED ->
                    ScreenCaptureService.savedResultCode != 0 && ScreenCaptureService.savedResultData != null
                Intent.ACTION_BOOT_COMPLETED, "android.intent.action.QUICKBOOT_POWERON" ->
                    consentBefore  // previously granted consent
                else -> false
            }
            if (shouldStartCapture) {
                try {
                    val capSvc = Intent(context, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_START_SILENT
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        context.startForegroundService(capSvc)
                    else context.startService(capSvc)
                    Log.d(TAG, "ScreenCaptureService silent restart attempted (action=${intent.action})")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to restart capture service: $e")
                }
            }

            // ── 3. Resume notification on reboot ────────────────────────────────────
            val isReboot = intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
            if (consentBefore && isReboot) {
                showResumeNotification(context)
            }

            // ── 4. Arm alarm-based watchdog ──────────────────────────────────────────
            WatchdogReceiver.schedule(context)

            // ── 5. WorkManager periodic watchdog ────────────────────────────────────
            // RC-BOOT-03: CANCEL_AND_REENQUEUE on boot to reset schedule drift.
            try {
                val workRequest = PeriodicWorkRequestBuilder<WatchdogWorker>(
                    15, TimeUnit.MINUTES
                ).build()
                WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                    WatchdogWorker.WORK_NAME,
                    ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
                    workRequest
                )
                Log.d(TAG, "WorkManager watchdog enqueued (CANCEL_AND_REENQUEUE)")
            } catch (e: Exception) {
                Log.e(TAG, "WorkManager enqueue failed: $e")
            }
        }, startDelayMs)
    }

    private fun isAppInForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return try {
            am.runningAppProcesses?.any {
                it.processName == context.packageName &&
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            } == true
        } catch (_: Exception) {
            false
        }
    }

    private fun showResumeNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = android.app.NotificationChannel(
                    NOTIF_CH,
                    "Monitoring Resume",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Prompts to resume monitoring after reboot"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
            }

            val tapIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP) }
                ?: return

            val pi = PendingIntent.getActivity(
                context, 0, tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notif = NotificationCompat.Builder(context, NOTIF_CH)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Family Monitor")
                .setContentText("Tap to resume monitoring after restart")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(false)
                .build()

            nm.notify(NOTIF_ID, notif)
            Log.d(TAG, "Resume notification shown")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show resume notification: $e")
        }
    }
}
