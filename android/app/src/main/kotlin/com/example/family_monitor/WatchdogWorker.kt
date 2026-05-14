package com.example.family_monitor

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * FIX-06: WorkManager-based watchdog worker.
 *
 * Runs as a complementary watchdog alongside the AlarmManager path.
 * WorkManager survives Doze mode and Battery Saver on Android 6+ without
 * needing USE_EXACT_ALARM (Play Store-restricted) or SCHEDULE_EXACT_ALARM.
 * It is not exact but fires within ~15 min under Doze — acceptable for a
 * background recovery watchdog.
 *
 * Enqueued by BootReceiver as KEEP (so only one instance runs at a time)
 * with a 15-minute periodic interval.
 */
class WatchdogWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    companion object {
        private const val TAG       = "WatchdogWorker"
        const val WORK_NAME         = "fm_watchdog_periodic"
    }

    override fun doWork(): Result {
        Log.d(TAG, "WorkManager watchdog fired")

        val context = applicationContext

        val flutterPrefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val wizardDone = flutterPrefs.getBoolean("flutter.wizard_done", false)
        val uid        = flutterPrefs.getString("flutter.child_uid", null)

        if (!wizardDone || uid.isNullOrEmpty()) {
            Log.d(TAG, "Setup not complete — skipping service restart")
            return Result.success()
        }

        try {
            val bgSvc = Intent(
                context,
                id.flutter.flutter_background_service.BackgroundService::class.java
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(bgSvc)
            else
                context.startService(bgSvc)
            Log.d(TAG, "Flutter background service (re)started by WorkManager watchdog")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart bg service: $e")
        }

        return Result.success()
    }
}
