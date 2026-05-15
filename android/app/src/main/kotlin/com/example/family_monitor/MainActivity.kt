package com.example.family_monitor

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraCaptureSession
import android.media.ImageReader
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val SCREEN_CAPTURE_CHANNEL = "com.familymonitor/screen_capture"
        private const val SNAPSHOT_CHANNEL       = "com.familymonitor/snapshot"
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var pendingResult: MethodChannel.Result? = null

    private lateinit var projectionManager: MediaProjectionManager

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
                    Log.d(TAG, "Deleted stale channel: $id")
                }
            }
        }

        projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
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
                Intent(this, ScreenCaptureService::class.java).apply {
                    putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Screen-capture control channel ────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_CAPTURE_CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "requestProjection" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "Projection request already running", null)
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
                    result.success(ScreenCaptureService.projectionToken != null)
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
                        intent.data = android.net.Uri.parse("package:$packageName")
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_OPT_ERROR", e.message, null)
                    }
                }

                "isBatteryOptimizationExempt" -> {
                    try {
                        val powerManager =
                            getSystemService(POWER_SERVICE) as android.os.PowerManager
                        result.success(
                            powerManager.isIgnoringBatteryOptimizations(packageName)
                        )
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // ICON-FIX: hideAppIcon / showAppIcon removed.
                // LauncherAlias no longer exists in the manifest; there is no
                // component to toggle. The Dart layer no longer calls these methods.

                "isDeviceAdminActive" -> {
                    try {
                        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val cn = ComponentName(this, FamilyDeviceAdminReceiver::class.java)
                        result.success(dpm.isAdminActive(cn))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // FIX-15: DevicePolicyManager.setPackagesSuspended for reliable
                // app blocking when Device Admin is active (API 24+, minSdk=24).
                // Suspended apps cannot be launched by the user — they see a
                // system dialog explaining the app is unavailable. This is more
                // reliable than AccessibilityService-based home-screen redirect.
                "suspendPackages" -> {
                    try {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val cn = ComponentName(this, FamilyDeviceAdminReceiver::class.java)
                        if (dpm.isAdminActive(cn) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            val failed = dpm.setPackagesSuspended(
                                cn,
                                packages.toTypedArray(),
                                true
                            )
                            result.success(failed?.toList() ?: emptyList<String>())
                        } else {
                            result.success(emptyList<String>())
                        }
                    } catch (e: Exception) {
                        result.error("SUSPEND_ERROR", e.message, null)
                    }
                }

                "unsuspendPackages" -> {
                    try {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val cn = ComponentName(this, FamilyDeviceAdminReceiver::class.java)
                        if (dpm.isAdminActive(cn) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            dpm.setPackagesSuspended(
                                cn,
                                packages.toTypedArray(),
                                false
                            )
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("UNSUSPEND_ERROR", e.message, null)
                    }
                }

                "requestDeviceAdmin" -> {
                    try {
                        val cn = ComponentName(this, FamilyDeviceAdminReceiver::class.java)
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, cn)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Keeps Family Monitor running and prevents it from being " +
                                "removed without your parent's knowledge."
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DA_ERROR", e.message, null)
                    }
                }

                // Returns all user-launchable installed apps as:
                // [{packageName, appName, iconBytes (PNG ByteArray or null)}]
                // Icons are resized to 72×72 px JPEG at 85% quality to keep
                // Firebase Storage upload size small (~2 KB each).
                "getInstalledApps" -> {
                    try {
                        val pm = packageManager
                        val apps = pm.getInstalledApplications(0)
                        val list = mutableListOf<Map<String, Any?>>()
                        for (app in apps) {
                            val launchIntent = pm.getLaunchIntentForPackage(app.packageName)
                                ?: continue
                            val appName = pm.getApplicationLabel(app).toString()
                            val iconBytes: ByteArray? = try {
                                val drawable = pm.getApplicationIcon(app.packageName)
                                val size = 72
                                val bmp = android.graphics.Bitmap.createBitmap(
                                    size, size, android.graphics.Bitmap.Config.ARGB_8888
                                )
                                val canvas = android.graphics.Canvas(bmp)
                                drawable.setBounds(0, 0, size, size)
                                drawable.draw(canvas)
                                val out = java.io.ByteArrayOutputStream()
                                bmp.compress(
                                    android.graphics.Bitmap.CompressFormat.JPEG, 85, out
                                )
                                bmp.recycle()
                                out.toByteArray()
                            } catch (_: Exception) { null }
                            list.add(mapOf(
                                "packageName" to app.packageName,
                                "appName"     to appName,
                                "iconBytes"   to iconBytes
                            ))
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("APP_LIST_ERROR", e.message, null)
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
                                val typeIdx = c.getColumnIndex(android.provider.CallLog.Calls.TYPE)
                                val numIdx  = c.getColumnIndex(android.provider.CallLog.Calls.NUMBER)
                                val nameIdx = c.getColumnIndex(android.provider.CallLog.Calls.CACHED_NAME)
                                val dateIdx = c.getColumnIndex(android.provider.CallLog.Calls.DATE)
                                val durIdx  = c.getColumnIndex(android.provider.CallLog.Calls.DURATION)
                                if (typeIdx < 0 || numIdx < 0 || dateIdx < 0 || durIdx < 0) continue
                                val typeInt = c.getInt(typeIdx)
                                val typeStr = when (typeInt) {
                                    android.provider.CallLog.Calls.INCOMING_TYPE -> "incoming"
                                    android.provider.CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                                    android.provider.CallLog.Calls.MISSED_TYPE   -> "missed"
                                    else -> "unknown"
                                }
                                list.add(mapOf(
                                    "number"   to (c.getString(numIdx) ?: ""),
                                    "name"     to (if (nameIdx >= 0) c.getString(nameIdx) ?: "" else ""),
                                    "type"     to typeStr,
                                    "date"     to c.getLong(dateIdx),
                                    "duration" to c.getLong(durIdx)
                                ))
                                count++
                            }
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("CALL_LOG_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        // ── Native camera snapshot channel ────────────────────────────────────
        // Provides a Camera2-based still capture that works without a visible
        // preview surface, falling back to the Flutter CameraController path on
        // any error. The Dart side catches MissingPluginException and PlatformException
        // gracefully, so this channel only needs to succeed when it can.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SNAPSHOT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takeNativeSnapshot" -> takeNativeSnapshotAsync(result)
                else                 -> result.notImplemented()
            }
        }
    }

    // ── Camera2 snapshot implementation ──────────────────────────────────────
    // Runs entirely on a dedicated HandlerThread so the main thread is never
    // blocked. result.success / result.error are always dispatched back to the
    // main thread via runOnUiThread, as required by Flutter's MethodChannel
    // contract. An AtomicBoolean ensures the result callback is invoked
    // exactly once even if multiple camera callbacks fire (e.g. timeout + error).
    private fun takeNativeSnapshotAsync(result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)

        fun replyOnce(bytes: ByteArray?) {
            if (replied.compareAndSet(false, true)) {
                runOnUiThread { result.success(bytes) }
            }
        }

        val bgThread = HandlerThread("snapshot-camera").also { it.start() }
        val bgHandler = Handler(bgThread.looper)

        val cameraManager = try {
            getSystemService(CameraManager::class.java)
        } catch (_: Exception) { null }

        if (cameraManager == null) {
            bgThread.quit()
            replyOnce(null)
            return
        }

        // Prefer front-facing camera; fall back to first available
        val cameraId: String? = try {
            cameraManager.cameraIdList.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.LENS_FACING) ==
                        CameraCharacteristics.LENS_FACING_FRONT
            } ?: cameraManager.cameraIdList.firstOrNull()
        } catch (_: Exception) { null }

        if (cameraId == null) {
            bgThread.quit()
            replyOnce(null)
            return
        }

        val imageReader = ImageReader.newInstance(640, 480, ImageFormat.JPEG, 1)

        // Shared cleanup — safe to call multiple times (null-checks on each resource)
        var cameraRef: CameraDevice?          = null
        var sessionRef: CameraCaptureSession? = null

        fun cleanup() {
            try { sessionRef?.close() } catch (_: Exception) {}
            try { cameraRef?.close()  } catch (_: Exception) {}
            try { imageReader.close() } catch (_: Exception) {}
            bgThread.quit()
        }

        // Hard 8-second timeout — prevents the MethodChannel call from hanging
        // if the camera never calls back (e.g. locked by another app).
        val timeoutTask = Runnable {
            Log.w(TAG, "Native snapshot timed out")
            cleanup()
            replyOnce(null)
        }
        bgHandler.postDelayed(timeoutTask, 8_000L)

        // Open the camera on the background thread
        try {
            cameraManager.openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {

                    override fun onOpened(camera: CameraDevice) {
                        cameraRef = camera
                        bgHandler.removeCallbacks(timeoutTask)

                        // Re-arm a shorter timeout for the session + capture phase
                        bgHandler.postDelayed(timeoutTask, 6_000L)

                        val surfaces = listOf(imageReader.surface)
                        try {
                            camera.createCaptureSession(
                                surfaces,
                                object : CameraCaptureSession.StateCallback() {

                                    override fun onConfigured(session: CameraCaptureSession) {
                                        sessionRef = session
                                        bgHandler.removeCallbacks(timeoutTask)

                                        imageReader.setOnImageAvailableListener({ reader ->
                                            val image = try {
                                                reader.acquireLatestImage()
                                            } catch (_: Exception) { null }

                                            val bytes = image?.use { img ->
                                                val buf = img.planes[0].buffer
                                                ByteArray(buf.remaining()).also { buf.get(it) }
                                            }

                                            cleanup()
                                            replyOnce(bytes)
                                        }, bgHandler)

                                        try {
                                            val req = camera
                                                .createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                                                .apply { addTarget(imageReader.surface) }
                                                .build()
                                            session.capture(
                                                req,
                                                object : CameraCaptureSession.CaptureCallback() {},
                                                bgHandler
                                            )
                                        } catch (e: Exception) {
                                            Log.e(TAG, "Capture request failed: $e")
                                            cleanup()
                                            replyOnce(null)
                                        }
                                    }

                                    override fun onConfigureFailed(session: CameraCaptureSession) {
                                        Log.e(TAG, "Camera session configure failed")
                                        cleanup()
                                        replyOnce(null)
                                    }
                                },
                                bgHandler
                            )
                        } catch (e: Exception) {
                            Log.e(TAG, "createCaptureSession failed: $e")
                            cleanup()
                            replyOnce(null)
                        }
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        Log.w(TAG, "Camera disconnected")
                        cameraRef = camera
                        cleanup()
                        replyOnce(null)
                    }

                    override fun onError(camera: CameraDevice, error: Int) {
                        Log.e(TAG, "Camera error: $error")
                        cameraRef = camera
                        cleanup()
                        replyOnce(null)
                    }
                },
                bgHandler
            )
        } catch (e: SecurityException) {
            // CAMERA permission not granted at the time of the call
            Log.e(TAG, "Camera permission denied: $e")
            bgHandler.removeCallbacks(timeoutTask)
            cleanup()
            replyOnce(null)
        } catch (e: Exception) {
            Log.e(TAG, "openCamera failed: $e")
            bgHandler.removeCallbacks(timeoutTask)
            cleanup()
            replyOnce(null)
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
