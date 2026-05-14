package com.example.family_monitor

import android.app.admin.DeviceAdminReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device Administrator receiver.
 *
 * When active this prevents the app from being uninstalled without first
 * going through the Device Admin removal flow, which shows onDisableRequested
 * and warns the child — while the hidden icon means the parent is unlikely
 * to see or understand what the prompt means.
 *
 * It also arms the watchdog whenever it is enabled, so monitoring restarts
 * automatically after force-stop or battery pull.
 */
class FamilyDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "FamilyDeviceAdmin"

        fun componentName(ctx: Context) =
            ComponentName(ctx, FamilyDeviceAdminReceiver::class.java)
    }

    override fun onEnabled(context: Context, intent: Intent) {
        Log.d(TAG, "Device Admin ENABLED")
        context.getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("admin_active", true)
            .apply()
        WatchdogReceiver.schedule(context)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Log.d(TAG, "Device Admin DISABLED")
        context.getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("admin_active", false)
            .apply()
    }

    /**
     * Android shows this message as a dialog when the user tries to deactivate
     * this app from Device Admin Settings → Security → Device Admin Apps.
     */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Warning: Removing this will stop family safety monitoring on this device. " +
        "Your parent will be notified."
}
