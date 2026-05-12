package com.example.family_monitor
import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
class FamilyDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        context.getSharedPreferences("fm_prefs",Context.MODE_PRIVATE).edit().putBoolean("admin_active",true).apply()
    }
    override fun onDisabled(context: Context, intent: Intent) {
        context.getSharedPreferences("fm_prefs",Context.MODE_PRIVATE).edit().putBoolean("admin_active",false).apply()
    }
}
