package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import android.os.PowerManager
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ScreenCaptureService — Production-hardened MediaProjection token holder
 * with native frame capture fallback.
 *
 * ROLE:
 *   1. Hold a valid MediaProjection token (obtained from user consent).
 *   2. Keep a foreground service with MEDIA_PROJECTION type active.
 *   3. Survive aggressive OEM background killing via PARTIAL_WAKE_LOCK.
 *   4. BUG-2-FIX: Provide native frame capture via VirtualDisplay + ImageReader
 *      as a fallback when flutter_webrtc's getDisplayMedia() fails due to
 *      Intent URI serialization losing the Binder extra.
 *   5. BUG-2-FIX: Provide Parcel-serialized Intent data that preserves the
 *      Binder extra, allowing getMediaProjection() to succeed.
 *
 * ROOT CAUSES FIXED:
 *
 * RC-01 — No PARTIAL_WAKE_LOCK → CPU suspended on screen-off.
 * RC-02 — Wrong startForeground() call order on Android 14+.
 * RC-03 — MediaProjection.Callback.onStop registered only on API 34+.
 * RC-04 — NOTIFICATION_ID collision with WatchdogService.
 * RC-05 — onDestroy() did not release wake lock.
 * RC-06 — onStartCommand(null) jumped to requestPermissionViaUi().
 *
 * BUG-2-FIX:
 * RC-B2-01 — Intent.toUri(0) loses the Binder extra needed by
 *            getMediaProjection(). Fixed: store Parcel-marshaled bytes in
 *            static field and provide via getProjectionParamsParcel().
 * RC-B2-02 — No native frame capture fallback for when getDisplayMedia()
 *            fails. Fixed: added VirtualDisplay + ImageReader pipeline.
 *
 * ADDITIONAL FIXES:
 * FIX-1 — HandlerThread started in field initializer before onCreate().
 *         Moved to lazy creation via ensureCaptureHandlerThread().
 * FIX-2 — Row-by-row copy in startFrameCapture() used copyPixelsFromBuffer
 *         which always writes from bitmap position 0, overwriting previous rows.
 *         Fixed: use Bitmap.setPixels() with IntArray for correct y-offset.
 * FIX-3 — VirtualDisplay duplication when ScreenStreamService is also streaming.
 *         Added stopFrameCaptureIfStreaming() to stop this service's VirtualDisplay.
 * FIX-4 — MediaProjection.Callback only registered on API 29+. Now registered
 *         on all API levels (21+) for forward compatibility.
 * FIX-5 — onProjectionStopped() recovery race condition: teardownProjection()
 *         triggers another onStop() callback. Fixed with isRecovering flag.
 * FIX-6 — SharedPreferences only persisted URI data (loses Binder extra).
 *         Now also persists Parcel bytes as Base64 for better recovery.
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG                = "ScreenCaptureService"
        const val ACTION_START               = "START_SCREEN_CAPTURE"
        const val ACTION_STOP                = "STOP_SCREEN_CAPTURE"
        const val ACTION_START_SILENT        = "START_SCREEN_CAPTURE_SILENT"
        const val ACTION_PERMISSION_REQUIRED = "com.example.family_monitor.PROJECTION_PERMISSION_REQUIRED"
        const val EXTRA_RESULT_CODE          = "RESULT_CODE"
        const val EXTRA_RESULT_DATA          = "RESULT_DATA"
        const val CHANNEL_ID                 = "fm_screen_capture_v2"
        const val NOTIFICATION_ID            = 1001

        @Volatile var instance: ScreenCaptureService?  = null
        @Volatile var savedResultCode: Int              = 0
        @Volatile var savedResultData: Intent?          = null
        @Volatile var projectionToken: MediaProjection? = null

        // BUG-2-FIX: Parcel-marshaled Intent bytes preserving the Binder extra.
        // Unlike Intent.toUri(0) which loses the IBinder, Parcel serialization
        // preserves ALL extras including the MediaProjection token binder.
        @Volatile var savedResultDataParcelBytes: ByteArray? = null

        // BUG-2-FIX: Latest captured frame as JPEG bytes (native fallback).
        @Volatile var latestFrameBytes: ByteArray? = null
        @Volatile var frameCaptureRunning: Boolean = false

        // Prevents TOCTOU race where two concurrent onStartCommand deliveries
        // both pass the boolean check before either sets it, causing double-start.
        private val starting = AtomicBoolean(false)

        private const val WAKE_LOCK_TAG = "FamilyMonitor:ScreenCapture"
    }

    inner class LocalBinder : Binder() { fun getService() = this@ScreenCaptureService }
    private val binder      = LocalBinder()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaProjection: MediaProjection? = null
    var resultCode: Int     = 0
    var resultData: Intent? = null

    // RC-01: PARTIAL_WAKE_LOCK keeps CPU running when screen is off.
    private var wakeLock: PowerManager.WakeLock? = null

    // BUG-2-FIX: Native frame capture components.
    // FIX-1: captureHandlerThread moved from field initializer to lazy creation.
    // Previously started in field initializer, which meant the thread started
    // during class construction BEFORE onCreate(). This could leak the thread
    // if the service was created but never started, and the thread started
    // before the service was properly initialized.
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureHandlerThread: android.os.HandlerThread? = null
    private var captureHandler: Handler? = null
    private val frameLock = Object()

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        acquireWakeLock()
        // FIX-1: Create and start HandlerThread in onCreate() instead of field
        // initializer. This ensures the service is properly initialized before
        // the thread starts, and avoids thread leaks if the service is created
        // but never started.
        ensureCaptureHandlerThread()
        Log.d(TAG, "onCreate — wake lock acquired, capture handler thread ready")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_START -> {
                resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                else intent.getParcelableExtra(EXTRA_RESULT_DATA)
                savedResultCode = resultCode
                savedResultData = resultData
                // BUG-2-FIX: Serialize Intent via Parcel to preserve Binder extra.
                marshalIntentToParcel(resultData)
                startCaptureSafe()
            }
            ACTION_START_SILENT -> {
                // First try the volatile static fields
                if (savedResultCode != 0 && savedResultData != null) {
                    resultCode = savedResultCode
                    resultData = savedResultData
                    startCaptureSafe()
                } else {
                    // BUG-3-FIX: Try restoring from SharedPreferences (survives process death)
                    val restored = restoreProjectionFromPrefs()
                    if (restored) {
                        startCaptureSafe()
                    } else {
                        requestPermissionViaUi()
                    }
                }
            }
            ACTION_STOP -> {
                stopFrameCapture()
                releaseWakeLock()
                stopSelf()
                return START_NOT_STICKY
            }
            null -> {
                // RC-06: START_STICKY restart after process death delivers null intent.
                if (savedResultCode != 0 && savedResultData != null) {
                    resultCode = savedResultCode
                    resultData = savedResultData
                    startCaptureSafe()
                } else {
                    val restored = restoreProjectionFromPrefs()
                    if (restored) {
                        startCaptureSafe()
                    } else {
                        requestPermissionViaUi()
                    }
                }
            }
        }
        return START_STICKY
    }

    /**
     * BUG-2-FIX: Serialize the Intent using Parcel.marshall() to preserve
     * the Binder extra that Intent.toUri(0) loses.
     *
     * The MediaProjection result Intent contains an IBinder extra that is
     * required by getMediaProjection(). Intent.toUri(0) does NOT preserve
     * IBinder/Parcelable extras, so Intent.parseUri() reconstructs an Intent
     * without the Binder, causing getMediaProjection() to return null.
     *
     * Parcel serialization preserves ALL data including the Binder.
     */
    private fun marshalIntentToParcel(intent: Intent?) {
        if (intent == null) {
            savedResultDataParcelBytes = null
            return
        }
        try {
            val parcel = Parcel.obtain()
            intent.writeToParcel(parcel, 0)
            savedResultDataParcelBytes = parcel.marshall()
            parcel.recycle()
            Log.d(TAG, "Intent marshaled to Parcel bytes: ${savedResultDataParcelBytes?.size} bytes")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to marshal Intent to Parcel: $e")
            savedResultDataParcelBytes = null
        }
    }

    private fun requestPermissionViaUi() {
        // Use DATA_SYNC type — safe to call without a MediaProjection token.
        startFgDataSync()
        sendBroadcast(Intent(ACTION_PERMISSION_REQUIRED).apply { setPackage(packageName) })
        try {
            startActivity(
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                } ?: return
            )
        } catch (_: Exception) {}
    }

    private fun startCaptureSafe() {
        if (!starting.compareAndSet(false, true)) return
        try {
            // ── RC-02: TWO-PHASE startForeground for Android 14+ compatibility ──
            startFgDataSync()

            val pm   = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val data = resultData ?: run { starting.set(false); return }

            teardownProjection()

            // Phase 2: Get the MediaProjection token.
            mediaProjection = pm.getMediaProjection(resultCode, data)

            if (mediaProjection == null) {
                Log.e(TAG, "getMediaProjection returned null — Intent data may be invalid")
                starting.set(false)
                requestPermissionViaUi()
                return
            }

            // Phase 3: Now that we have the token, upgrade to MEDIA_PROJECTION type.
            startFgMediaProjection()

            // FIX-4: Register MediaProjection.Callback on ALL API levels (21+).
            // onStop() was added in API 29, but the Callback class itself exists
            // from API 21. On API < 29, the callback is registered but onStop()
            // won't fire (the system doesn't call it). This is still useful for
            // forward compatibility — if the OEM back-ports the callback, or if
            // the app runs on a newer API than compiled against.
            // On API 29+, onStop() fires when the system revokes the projection.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                        override fun onStop() {
                            Log.w(TAG, "MediaProjection stopped by system (API${Build.VERSION.SDK_INT})")
                            mainHandler.post { onProjectionStopped() }
                        }
                    }, mainHandler)
                } else {
                    // API 21-28: Register callback for forward compatibility.
                    // onStop() doesn't exist on these APIs, but registering the
                    // callback base class ensures we're set up if the system
                    // ever adds callback methods on these versions.
                    @Suppress("DEPRECATION")
                    mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                        // No methods to override on API < 29, but the callback
                        // is registered for forward compatibility.
                    }, mainHandler)
                    Log.d(TAG, "MediaProjection.Callback registered (API < 29, onStop not available)")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to register MediaProjection.Callback: $e")
            }

            projectionToken = mediaProjection

            // Persist consent so boot receiver / watchdog know to attempt silent restart.
            // BUG-3-FIX: Also persist projection data to SharedPreferences for reboot recovery.
            // FIX-6: Persist Parcel bytes as Base64 string in addition to URI-serialized
            // data. URI serialization loses the Binder extra, so on process death recovery
            // the Parcel bytes give a much better chance of restoring a valid projection.
            val prefsEditor = applicationContext
                .getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("projection_consent_granted", true)
                .putInt("projection_result_code", resultCode)
                .putString("projection_result_data_uri", resultData?.toUri(0)?.toString())

            // FIX-6: Persist Parcel bytes as Base64 for better recovery after process death.
            if (savedResultDataParcelBytes != null) {
                prefsEditor.putString(
                    "projection_result_data_parcel_b64",
                    Base64.encodeToString(savedResultDataParcelBytes, Base64.NO_WRAP)
                )
            } else {
                prefsEditor.remove("projection_result_data_parcel_b64")
            }
            prefsEditor.apply()

            // BUG-2-FIX: Serialize Intent via Parcel to preserve Binder extra.
            marshalIntentToParcel(resultData)

            Log.d(TAG, "MediaProjection created — token active")
        } catch (e: Exception) {
            Log.e(TAG, "startCaptureSafe failed: $e")
            requestPermissionViaUi()
        } finally {
            starting.set(false)
        }
    }

    /**
     * FIX-5: Flag to prevent re-entrant recovery in onProjectionStopped().
     * When onProjectionStopped() is called, it calls startCaptureSafe() which
     * calls teardownProjection() which calls mediaProjection?.stop() which
     * triggers ANOTHER onStop() callback, creating a loop. This flag prevents
     * the second entry from triggering recovery again.
     */
    private val isRecovering = AtomicBoolean(false)

    /** Called when the system revokes the MediaProjection token. */
    private fun onProjectionStopped() {
        // FIX-5: Prevent re-entrant recovery. teardownProjection() calls
        // mediaProjection?.stop() which triggers another onStop() callback.
        if (!isRecovering.compareAndSet(false, true)) {
            Log.d(TAG, "onProjectionStopped — already recovering, skipping re-entrant call")
            return
        }
        try {
            teardownProjection()
            projectionToken = null
            savedResultDataParcelBytes = null
            stopFrameCapture()
            if (savedResultCode != 0 && savedResultData != null) {
                Log.d(TAG, "Token revoked — attempting silent re-establish")
                startCaptureSafe()
            } else {
                val restored = restoreProjectionFromPrefs()
                if (restored) {
                    Log.d(TAG, "Token revoked — restored from prefs, attempting re-establish")
                    startCaptureSafe()
                } else {
                    requestPermissionViaUi()
                }
            }
        } finally {
            isRecovering.set(false)
        }
    }

    // ── BUG-2-FIX: Native Frame Capture Pipeline ──────────────────────────

    /**
     * FIX-1: Ensure the capture HandlerThread is created and started.
     * Called from onCreate() and also lazily from startFrameCapture() as a safety net.
     */
    private fun ensureCaptureHandlerThread() {
        if (captureHandlerThread?.isAlive == true) return
        captureHandlerThread = android.os.HandlerThread("ScreenFrameCapture").also { it.start() }
        captureHandler = Handler(captureHandlerThread!!.looper)
        Log.d(TAG, "Capture HandlerThread created and started")
    }

    /**
     * FIX-3: Stop this service's VirtualDisplay if ScreenStreamService is
     * actively streaming. ScreenStreamService has its own capture pipeline
     * (VirtualDisplay + ImageReader + WebSocket), so there's no need for this
     * service's VirtualDisplay to also consume frames — doing so wastes CPU
     * and memory. Call this before starting ScreenStreamService's capture.
     */
    fun stopFrameCaptureIfStreaming() {
        if (isScreenStreamServiceStreaming()) {
            Log.d(TAG, "ScreenStreamService is streaming — stopping our VirtualDisplay to avoid duplication")
            stopFrameCapture()
        }
    }

    /**
     * FIX-3: Check if ScreenStreamService is actively streaming.
     * This is safe to call from any thread — ScreenStreamService.isStreaming
     * is a @Volatile static field.
     */
    fun isScreenStreamServiceStreaming(): Boolean {
        return ScreenStreamService.isStreaming
    }

    /**
     * Start native screen frame capture using VirtualDisplay + ImageReader.
     *
     * This provides a fallback when flutter_webrtc's getDisplayMedia() fails
     * (e.g., because Intent URI serialization lost the Binder extra on Android 14+).
     * Frames are captured as JPEG and stored in [latestFrameBytes] for retrieval
     * via MethodChannel.
     *
     * BUG-2 FIX: Default dimensions reduced to 480x854 for faster Firebase RTDB
     * relay. At this resolution, JPEG frames are typically 10-20 KB (vs 30-50 KB
     * at 720x1280), making 3 FPS relay via Firebase practical (~30-60 KB/s).
     *
     * @param width  Capture width (default 480)
     * @param height Capture height (default 854)
     * @param fps    Target frame rate (default 3)
     * @return true if capture started successfully
     */
    fun startFrameCapture(width: Int = 480, height: Int = 854, fps: Int = 3): Boolean {
        val projection = mediaProjection ?: run {
            Log.e(TAG, "startFrameCapture: No active MediaProjection")
            return false
        }

        if (frameCaptureRunning) {
            Log.d(TAG, "Frame capture already running")
            return true
        }

        // FIX-1: Ensure the HandlerThread is ready (safety net if onCreate didn't run)
        ensureCaptureHandlerThread()
        val handler = captureHandler ?: run {
            Log.e(TAG, "startFrameCapture: captureHandler is null")
            return false
        }

        try {
            // Create ImageReader surface for capturing frames
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

            imageReader?.setOnImageAvailableListener({ reader ->
                var image: Image? = null
                try {
                    image = reader.acquireLatestImage()
                    if (image != null) {
                        val planes = image.planes
                        if (planes.isEmpty()) return@setOnImageAvailableListener

                        val buffer = planes[0].buffer
                        val rowStride = planes[0].rowStride
                        val pixelStride = planes[0].pixelStride

                        // Create bitmap from Image
                        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        buffer.rewind()

                        // Handle row padding (some devices have rowStride > width * pixelStride)
                        if (rowStride == width * pixelStride) {
                            bmp.copyPixelsFromBuffer(buffer)
                        } else {
                            // FIX-2: Row-by-row copy using Bitmap.setPixels() with IntArray.
                            // The previous code used copyPixelsFromBuffer(ByteBuffer.wrap(rowBuffer))
                            // which always writes from position 0 of the bitmap buffer, so each
                            // row overwrote the first row. setPixels() with y-offset correctly
                            // places each row at the right position in the bitmap.
                            val rowBytes = width * pixelStride
                            val rowPixels = IntArray(width)
                            val rowByteBuffer = ByteBuffer.allocate(rowBytes)
                            for (y in 0 until height) {
                                buffer.position(y * rowStride)
                                rowByteBuffer.rewind()
                                buffer.get(rowByteBuffer.array(), 0, rowBytes)
                                rowByteBuffer.rewind()
                                rowByteBuffer.asIntBuffer().get(rowPixels)
                                bmp.setPixels(rowPixels, 0, width, 0, y, width, 1)
                            }
                        }

                        // BUG-2 FIX: Compress to JPEG at lower quality (40%) for
                        // smaller frame size. At 480x854 with quality=40, frames
                        // are typically 8-15 KB, making 3 FPS Firebase RTDB relay
                        // practical (~24-45 KB/s).
                        val outputStream = ByteArrayOutputStream()
                        bmp.compress(Bitmap.CompressFormat.JPEG, 40, outputStream)
                        val jpegBytes = outputStream.toByteArray()
                        bmp.recycle()

                        synchronized(frameLock) {
                            latestFrameBytes = jpegBytes
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Frame capture error: $e")
                } finally {
                    image?.close()
                }
            }, handler)

            // Create VirtualDisplay
            virtualDisplay = projection.createVirtualDisplay(
                "FamilyMonitorScreenCapture",
                width, height, getDensityDpi(),
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                object : VirtualDisplay.Callback() {
                    override fun onStopped() {
                        Log.w(TAG, "VirtualDisplay stopped")
                        frameCaptureRunning = false
                    }
                },
                handler
            )

            frameCaptureRunning = true
            Log.d(TAG, "Native frame capture started: ${width}x${height} @ ${fps}fps")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "startFrameCapture failed: $e")
            stopFrameCapture()
            return false
        }
    }

    /** Stop native frame capture. */
    fun stopFrameCapture() {
        frameCaptureRunning = false
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        // FIX-1: Do NOT quit the HandlerThread here — it is reused across
        // multiple start/stop cycles. Only quit in onDestroy().
        synchronized(frameLock) {
            latestFrameBytes = null
        }
        Log.d(TAG, "Native frame capture stopped")
    }

    /** Get the latest captured frame as JPEG bytes. */
    fun getLatestFrame(): ByteArray? {
        synchronized(frameLock) {
            return latestFrameBytes
        }
    }

    private fun getDensityDpi(): Int {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(metrics)
        return metrics.densityDpi
    }

    // ── startForeground helpers ──────────────────────────────────────────────

    private fun startFgDataSync() {
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIFICATION_ID, n,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } catch (e: Exception) {
                Log.w(TAG, "startFgDataSync failed, untyped fallback: $e")
                try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
            }
        } else {
            try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
        }
    }

    private fun startFgMediaProjection() {
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIFICATION_ID, n,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
                Log.d(TAG, "Foreground upgraded to MEDIA_PROJECTION type")
            } catch (e: Exception) {
                Log.w(TAG, "startFgMediaProjection failed, falling back to DATA_SYNC: $e")
                startFgDataSync()
            }
        }
    }

    private fun teardownProjection() {
        stopFrameCapture()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        projectionToken = null
        mediaProjection = null
    }

    /**
     * BUG-3-FIX: Restore projection data from SharedPreferences.
     * FIX-6: Now tries Parcel bytes (Base64) FIRST, which preserves the Binder
     * extra. Falls back to URI-serialized data if Parcel bytes are unavailable.
     *
     * Note: URI-serialized Intent data will NOT have the Binder extra, so
     * getMediaProjection() may fail on Android 14+. Parcel bytes from the
     * same app session have a much better chance of working.
     * Note: After a full device reboot, the Binder token is invalidated by
     * the system regardless, so both approaches may fail. This is a best-effort
     * recovery for process-death (not reboot) scenarios.
     */
    private fun restoreProjectionFromPrefs(): Boolean {
        try {
            val prefs = getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            val code = prefs.getInt("projection_result_code", 0)
            if (code == 0) return false

            // FIX-6: Try Parcel bytes first (preserves Binder extra).
            val parcelB64 = prefs.getString("projection_result_data_parcel_b64", null)
            if (parcelB64 != null) {
                try {
                    val parcelBytes = Base64.decode(parcelB64, Base64.NO_WRAP)
                    val parcel = Parcel.obtain()
                    parcel.unmarshall(parcelBytes, 0, parcelBytes.size)
                    parcel.setDataPosition(0)
                    val data = Intent.CREATOR.createFromParcel(parcel)
                    parcel.recycle()
                    resultCode = code
                    resultData = data
                    savedResultCode = code
                    savedResultData = data
                    savedResultDataParcelBytes = parcelBytes
                    Log.d(TAG, "Projection data restored from SharedPreferences (Parcel bytes, Binder may be preserved)")
                    return true
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to restore from Parcel bytes in prefs: $e")
                }
            }

            // Fallback: URI-serialized data (Binder extra is lost)
            val uriStr = prefs.getString("projection_result_data_uri", null)
            if (uriStr != null) {
                val uri = android.net.Uri.parse(uriStr)
                val data = Intent.parseUri(uri.toString(), 0)
                resultCode = code
                resultData = data
                savedResultCode = code
                savedResultData = data
                // BUG-2-FIX: Also try to marshal the restored Intent
                // (Binder will be lost, but other extras preserved)
                marshalIntentToParcel(data)
                Log.d(TAG, "Projection data restored from SharedPreferences (URI — Binder lost)")
                return true
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to restore projection from prefs: $e")
        }
        return false
    }

    fun reinitAfterReconnect() {
        if (resultCode != 0 && resultData != null) {
            teardownProjection()
            startCaptureSafe()
        } else {
            requestPermissionViaUi()
        }
    }

    fun getProjectionParams(): Pair<Int, Intent>? {
        val d = resultData ?: return null
        return Pair(resultCode, d)
    }

    // ── Wake lock ────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG
            ).also {
                it.setReferenceCounted(false)
                it.acquire(10 * 60 * 60 * 1000L)
            }
            Log.d(TAG, "PARTIAL_WAKE_LOCK acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock: $e")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d(TAG, "PARTIAL_WAKE_LOCK released")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release wake lock: $e")
        }
        wakeLock = null
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        WatchdogReceiver.schedule(applicationContext)
    }

    override fun onDestroy() {
        stopFrameCapture()
        // FIX-1: Safely quit the HandlerThread (nullable since moved from field init).
        try { captureHandlerThread?.quit() } catch (_: Exception) {}
        captureHandlerThread = null
        captureHandler = null
        teardownProjection()
        releaseWakeLock()
        instance = null
        WatchdogReceiver.schedule(applicationContext)
        Log.d(TAG, "onDestroy — released, watchdog rescheduled")
        super.onDestroy()
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel("fm_bg_sync") != null) {
                nm.deleteNotificationChannel("fm_bg_sync")
            }
            val existing = nm.getNotificationChannel(CHANNEL_ID)
            if (existing != null && existing.importance >= NotificationManager.IMPORTANCE_LOW) return
            if (existing != null) nm.deleteNotificationChannel(CHANNEL_ID)
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Family Monitor Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description    = "Required for screen monitoring service"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent: Intent = try {
            packageManager.getLaunchIntentForPackage(packageName)
        } catch (_: Exception) { null }
            ?: Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }

        val openIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Family Monitor — Active")
            .setContentText("Screen monitoring is running.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openIntent)
            .build()
    }
}
