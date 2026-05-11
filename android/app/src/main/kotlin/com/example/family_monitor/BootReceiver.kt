package com.example.family_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val validActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )
        if (intent.action !in validActions) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val wizardDone = prefs.getBoolean("flutter.wizard_done", false)
        val uid = prefs.getString("flutter.child_uid", null)

        if (!wizardDone || uid.isNullOrEmpty()) return

        // Start the Flutter background service directly — no UI launch needed
        val serviceIntent = Intent(context, id.flutter.flutter_background_service.BackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
