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
 * going through the Device Admin removal flow. onDisableRequested launches
 * PinVerifyActivity — the child must enter their 4-digit safety PIN before
 * Device Admin can be removed (and thus the app uninstalled).
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
     * Called when the user tries to deactivate this app as Device Admin.
     * We launch our PIN verification screen immediately so the child must
     * enter their safety PIN before the removal can proceed.
     */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        Log.d(TAG, "onDisableRequested — launching PIN verify")
        PinVerifyActivity.launch(context)
        return "A safety PIN is required to remove device protection. " +
               "Enter it on the screen that just appeared."
    }
}
