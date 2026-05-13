package com.example.family_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object { private const val TAG = "BootReceiver" }

    override fun onReceive(context: Context, intent: Intent) {
        val valid = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            Intent.ACTION_MY_PACKAGE_REPLACED
        )
        if (intent.action !in valid) return

        val prefs      = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val wizardDone = prefs.getBoolean("flutter.wizard_done", false)
        val uid        = prefs.getString("flutter.child_uid", null)
        if (!wizardDone || uid.isNullOrEmpty()) {
            Log.d(TAG, "Setup not complete — skipping auto-start")
            return
        }

        Log.d(TAG, "Boot complete — starting background service")

        // 1. Flutter background service (foreground, user-visible)
        try {
            val bgSvc = Intent(context,
                id.flutter.flutter_background_service.BackgroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(bgSvc)
            else context.startService(bgSvc)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start background service: $e")
        }

        // 2. If a saved MediaProjection token exists, restart capture service.
        //    If not, the app will prompt the user when they next open it.
        if (ScreenCaptureService.savedResultCode != 0 &&
            ScreenCaptureService.savedResultData != null) {
            try {
                val capSvc = Intent(context, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START_SILENT
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    context.startForegroundService(capSvc)
                else context.startService(capSvc)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restart capture service: $e")
            }
        }

        // 3. Arm watchdog
        WatchdogReceiver.schedule(context)
    }
}
