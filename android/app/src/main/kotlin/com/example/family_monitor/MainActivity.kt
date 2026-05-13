package com.example.family_monitor

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SCREEN_CAPTURE_CHANNEL =
            "com.familymonitor/screen_capture"
    }

    private var pendingResult: MethodChannel.Result? = null

    private lateinit var projectionManager:
        MediaProjectionManager

    private val screenCaptureLauncher =
        registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result: ActivityResult ->

            val pending = pendingResult
            pendingResult = null

            if (
                result.resultCode == Activity.RESULT_OK &&
                result.data != null
            ) {

                val serviceIntent =
                    Intent(
                        this,
                        ScreenCaptureService::class.java
                    ).apply {
                        putExtra(
                            ScreenCaptureService.EXTRA_RESULT_CODE,
                            result.resultCode
                        )

                        putExtra(
                            ScreenCaptureService.EXTRA_RESULT_DATA,
                            result.data
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        projectionManager =
            getSystemService(
                MEDIA_PROJECTION_SERVICE
            ) as MediaProjectionManager
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

                    screenCaptureLauncher.launch(
                        projectionManager
                            .createScreenCaptureIntent()
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

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
