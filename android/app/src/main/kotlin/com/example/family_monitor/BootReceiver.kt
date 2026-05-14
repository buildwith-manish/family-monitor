package com.example.family_monitor

import android.app.ActivityManager
import android.app.NotificationChannel
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

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG          = "BootReceiver"
        private const val NOTIF_CH     = "fm_resume_ch"
        private const val NOTIF_ID     = 9201
    }

    override fun onReceive(context: Context, intent: Intent) {
        val valid = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            Intent.ACTION_MY_PACKAGE_REPLACED
        )
        if (intent.action !in valid) return

        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val wizardDone   = flutterPrefs.getBoolean("flutter.wizard_done", false)
        val uid          = flutterPrefs.getString("flutter.child_uid", null)
        if (!wizardDone || uid.isNullOrEmpty()) {
            Log.d(TAG, "Setup not complete — skipping auto-start")
            return
        }

        Log.d(TAG, "Boot complete (${intent.action}) — starting services")

        // AND-03: On MY_PACKAGE_REPLACED (app update via Play Store), the
        // Flutter background service may already be running if the app was in
        // the foreground during the update. Skip the restart to avoid a
        // double-start which can corrupt service state or produce duplicate
        // foreground notifications. Just re-arm the watchdog and exit.
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED && isAppInForeground(context)) {
            Log.d(TAG, "MY_PACKAGE_REPLACED + app in foreground — skipping service restart")
            WatchdogReceiver.schedule(context)
            return
        }

        // ── 1. Flutter background service ────────────────────────────────────────
        try {
            val bgSvc = Intent(context,
                id.flutter.flutter_background_service.BackgroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(bgSvc)
            else context.startService(bgSvc)
            Log.d(TAG, "Flutter background service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start background service: $e")
        }

        // ── 2. Screen-capture service ─────────────────────────────────────────────
        // MediaProjection tokens are invalidated on full reboot — only attempt silent
        // restart on MY_PACKAGE_REPLACED where the process stays alive.
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED &&
            ScreenCaptureService.savedResultCode != 0 &&
            ScreenCaptureService.savedResultData != null) {
            try {
                val capSvc = Intent(context, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START_SILENT
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    context.startForegroundService(capSvc)
                else context.startService(capSvc)
                Log.d(TAG, "ScreenCaptureService silent restart attempted")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restart capture service: $e")
            }
        }

        // ── 3. "Tap to resume" notification on reboot ────────────────────────────
        // When the phone restarts, the MediaProjection token is gone.
        // Show a quiet notification so the parent can trigger the one-tap re-consent.
        // This mimics what FlashGet Kids does — a background notification that stays
        // until the app is opened and monitoring resumes.
        val fmPrefs       = context.getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
        val consentBefore = fmPrefs.getBoolean("projection_consent_granted", false)
        val isReboot      = intent.action != Intent.ACTION_MY_PACKAGE_REPLACED

        if (consentBefore && isReboot) {
            showResumeNotification(context)
        }

        // ── 4. Arm alarm-based watchdog ──────────────────────────────────────────
        WatchdogReceiver.schedule(context)

        // ── 5. FIX-06: Also enqueue WorkManager periodic watchdog ────────────────
        // WorkManager provides a complementary safety net that fires every 15 min
        // even in Doze mode without requiring USE_EXACT_ALARM. KEEP policy ensures
        // only one instance runs at a time.
        try {
            val workRequest = PeriodicWorkRequestBuilder<WatchdogWorker>(
                15, TimeUnit.MINUTES
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WatchdogWorker.WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest
            )
            Log.d(TAG, "WorkManager watchdog enqueued")
        } catch (e: Exception) {
            Log.e(TAG, "WorkManager enqueue failed: $e")
        }
    }

    // AND-03: Check whether the app process is currently in the foreground.
    // Uses RunningAppProcessInfo.importance which is accessible without
    // special permissions. Returns false on any error (safe default).
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
                val ch = NotificationChannel(
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
