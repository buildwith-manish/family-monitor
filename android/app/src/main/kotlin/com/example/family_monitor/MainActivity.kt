package com.example.family_monitor

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val TAG           = "MainActivity"
        const val SMS_CHANNEL   = "family_monitor/sms"
        const val SCREEN_CHANNEL = "family_monitor/screen_capture"
        const val REQ_PROJECTION = 1001
        const val REQ_BATTERY    = 1002
    }

    private var pendingScreen: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── SMS channel ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "readSms")
                    result.success(readSms(call.argument<Int>("limit") ?: 100))
                else result.notImplemented()
            }

        // ── Screen-capture / battery channel ─────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestScreenCapture" -> {
                        if (pendingScreen != null) {
                            result.error("ALREADY_PENDING", "A request is already pending", null)
                            return@setMethodCallHandler
                        }
                        pendingScreen = result
                        val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        @Suppress("DEPRECATION")
                        startActivityForResult(pm.createScreenCaptureIntent(), REQ_PROJECTION)
                    }

                    "stopScreenCaptureService" -> {
                        startService(Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_STOP
                        })
                        result.success(true)
                    }

                    "requestBatteryOptimizationExemption" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(PowerManager::class.java)
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                try {
                                    startActivityForResult(
                                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                            Uri.parse("package:$packageName")), REQ_BATTERY)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Battery opt request failed: $e")
                                }
                            }
                        }
                        result.success(true)
                    }

                    "isBatteryOptimizationExempt" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            result.success(
                                getSystemService(PowerManager::class.java)
                                    .isIgnoringBatteryOptimizations(packageName))
                        else result.success(true)
                    }

                    else -> result.notImplemented()
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
                } else {
                    p?.success(mapOf("granted" to false, "resultCode" to resultCode))
                }
            }
            REQ_BATTERY -> { /* user handled battery opt UI */ }
        }
    }

    private fun readSms(limit: Int): List<Map<String, Any>> {
        val msgs = mutableListOf<Map<String, Any>>()
        try {
            val c = contentResolver.query(
                Uri.parse("content://sms"),
                arrayOf("address", "body", "date", "type"),
                null, null, "date DESC LIMIT $limit")
            c?.use {
                val ai = it.getColumnIndex("address"); val bi = it.getColumnIndex("body")
                val di = it.getColumnIndex("date");    val ti = it.getColumnIndex("type")
                while (it.moveToNext())
                    msgs.add(mapOf(
                        "address" to (it.getString(ai) ?: ""),
                        "body"    to (it.getString(bi) ?: ""),
                        "date"    to it.getLong(di),
                        "type"    to it.getInt(ti)))
            }
        } catch (e: Exception) { Log.e(TAG, "readSms error: $e") }
        return msgs
    }
}
