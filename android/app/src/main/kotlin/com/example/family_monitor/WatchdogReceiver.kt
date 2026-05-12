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

        if (ScreenCaptureService.instance == null) {
            val hasSavedToken = ScreenCaptureService.savedResultCode != 0 &&
                                ScreenCaptureService.savedResultData != null
            if (hasSavedToken) {
                // Re-acquire using saved token via the standard consent activity
                try {
                    context.startActivity(
                        Intent(context, StealthActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start StealthActivity: $e")
                }
            } else {
                // No token — open main app so user can re-grant
                try {
                    context.packageManager
                        .getLaunchIntentForPackage(context.packageName)
                        ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        ?.let { context.startActivity(it) }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open main app: $e")
                }
            }
        }
        schedule(context)   // re-arm
    }
}
