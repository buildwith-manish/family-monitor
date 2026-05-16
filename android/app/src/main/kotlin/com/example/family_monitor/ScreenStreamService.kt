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
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ScreenStreamService — Low-latency screen streaming via WebSocket.
 *
 * Captures screen frames using MediaProjection → VirtualDisplay → ImageReader,
 * compresses them to JPEG, and streams them over a WebSocket connection to a
 * relay server. This replaces the slow Firebase RTDB base64 relay (3 FPS, high
 * latency) with a proper binary streaming pipeline (10+ FPS, low latency).
 *
 * ARCHITECTURE:
 *   ScreenCaptureService holds the MediaProjection token.
 *   This service reuses that token to create its own VirtualDisplay + ImageReader
 *   for frame capture, then pushes JPEG frames over WebSocket.
 *
 * PROTOCOL:
 *   Connects to: ws://SERVER/?role=child&uid=CHILD_UID
 *   Sends binary WebSocket messages (JPEG bytes per frame).
 *   Relay server forwards frames to parent connections for the same UID.
 *
 * LIFECYCLE:
 *   - START_STICKY: Restarted by system if killed.
 *   - onTaskRemoved: Reschedule via WatchdogReceiver (survives app swipe).
 *   - stopWithTask = false: Service continues after task removal.
 *   - PARTIAL_WAKE_LOCK: Prevents CPU sleep during streaming.
 *
 * NOTE: Requires OkHttp dependency in build.gradle.kts:
 *   implementation("com.squareup.okhttp3:okhttp:4.12.0")
 */
class ScreenStreamService : Service() {

    companion object {
        private const val TAG = "ScreenStreamService"

        const val ACTION_START_STREAM = "com.example.family_monitor.START_STREAM"
        const val ACTION_STOP_STREAM  = "com.example.family_monitor.STOP_STREAM"

        const val EXTRA_UID        = "uid"
        const val EXTRA_SERVER_URL = "server_url"

        const val CHANNEL_ID      = "fm_screen_capture_v2"
        const val NOTIFICATION_ID = 1003  // 1001=ScreenCapture, 1002=WatchdogService

        // Frame capture configuration
        private const val CAPTURE_WIDTH   = 480
        private const val CAPTURE_HEIGHT  = 854
        private const val TARGET_FPS      = 10
        private const val JPEG_QUALITY    = 50  // 50% — ~15KB/frame at 480x854
        private const val FRAME_INTERVAL_MS = 1000L / TARGET_FPS  // ~100ms

        // WebSocket reconnect configuration
        private const val RECONNECT_BASE_MS   = 1000L
        private const val RECONNECT_MAX_MS    = 30_000L
        private const val RECONNECT_MULTIPLIER = 2.0

        private const val WAKE_LOCK_TAG = "FamilyMonitor:ScreenStream"

        @Volatile var isStreaming: Boolean       = false
        @Volatile var frameCount: Long           = 0
        @Volatile var lastFrameTimestamp: Long    = 0
        @Volatile var wsConnected: Boolean        = false
        @Volatile var instance: ScreenStreamService? = null
    }

    // ── Instance fields ────────────────────────────────────────────────────

    private var childUid: String = ""
    private var serverUrl: String = ""

    // Frame capture
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureHandlerThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var frameRunnable: Runnable? = null

    // WebSocket
    private var okHttpClient: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var reconnectAttempts: Int = 0
    private val reconnectLock = Object()

    // Wake lock
    private var wakeLock: PowerManager.WakeLock? = null

    // State
    private val streaming = AtomicBoolean(false)
    private val connecting = AtomicBoolean(false)
    private var latestFrameBytes: ByteArray? = null

    // ── Service lifecycle ──────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        acquireWakeLock()

        captureHandlerThread = HandlerThread("ScreenStreamCapture").also { it.start() }
        captureHandler = Handler(captureHandlerThread!!.looper)

        okHttpClient = OkHttpClient.Builder()
            .pingInterval(30_000L, java.util.concurrent.TimeUnit.MILLISECONDS)
            .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)  // No read timeout for streaming
            .build()

        Log.d(TAG, "onCreate — wake lock acquired, handler thread started")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_START_STREAM -> {
                childUid = intent.getStringExtra(EXTRA_UID) ?: ""
                serverUrl = intent.getStringExtra(EXTRA_SERVER_URL) ?: ""

                // Fallback: read server URL from SharedPreferences if not in intent
                if (serverUrl.isBlank()) {
                    serverUrl = getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                        .getString("stream_relay_url", "") ?: ""
                }

                if (childUid.isBlank()) {
                    Log.e(TAG, "Missing child UID — cannot start stream")
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (serverUrl.isBlank()) {
                    Log.e(TAG, "Missing relay server URL — cannot start stream. " +
                            "Set 'stream_relay_url' in SharedPreferences or pass EXTRA_SERVER_URL")
                    stopSelf()
                    return START_NOT_STICKY
                }

                startStreaming()
            }
            ACTION_STOP_STREAM -> {
                stopStreaming()
                stopSelf()
                return START_NOT_STICKY
            }
            null -> {
                // START_STICKY restart after process death delivers null intent.
                // Try to resume with persisted values.
                val prefs = getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                childUid = prefs.getString("stream_child_uid", "") ?: ""
                serverUrl = prefs.getString("stream_relay_url", "") ?: ""
                if (childUid.isNotBlank() && serverUrl.isNotBlank()) {
                    startStreaming()
                } else {
                    Log.w(TAG, "Restarted but missing uid/server — stopping")
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.w(TAG, "onTaskRemoved — rescheduling via WatchdogReceiver")
        WatchdogReceiver.schedule(applicationContext)
    }

    override fun onDestroy() {
        stopStreaming()
        releaseWakeLock()
        try { captureHandlerThread?.quit() } catch (_: Exception) {}
        captureHandlerThread = null
        captureHandler = null
        okHttpClient = null
        instance = null
        Log.d(TAG, "onDestroy — all resources released")
        super.onDestroy()
    }

    // ── Streaming control ──────────────────────────────────────────────────

    private fun startStreaming() {
        if (!streaming.compareAndSet(false, true)) {
            Log.d(TAG, "Streaming already in progress")
            return
        }

        // Persist streaming params for START_STICKY restart
        getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            .edit()
            .putString("stream_child_uid", childUid)
            .putString("stream_relay_url", serverUrl)
            .apply()

        // Phase 1: Start foreground with DATA_SYNC (safe before MediaProjection)
        startFgForeground()

        // Phase 2: Obtain MediaProjection
        if (!obtainMediaProjection()) {
            Log.e(TAG, "Cannot obtain MediaProjection — streaming aborted")
            streaming.set(false)
            stopSelf()
            return
        }

        // Phase 2b: Upgrade foreground type now that we have the projection
        upgradeFgToMediaProjection()

        // Phase 3: Start frame capture pipeline
        if (!startFrameCapture()) {
            Log.e(TAG, "Frame capture failed to start — streaming aborted")
            streaming.set(false)
            stopSelf()
            return
        }

        // Phase 4: Connect WebSocket
        connectWebSocket()

        isStreaming = true
        Log.d(TAG, "Streaming started: uid=$childUid, server=$serverUrl")
    }

    private fun stopStreaming() {
        if (!streaming.compareAndSet(true, false)) return

        stopFrameCapture()
        disconnectWebSocket()
        isStreaming = false
        frameCount = 0
        latestFrameBytes = null

        Log.d(TAG, "Streaming stopped")
    }

    // ── MediaProjection acquisition ────────────────────────────────────────

    /**
     * Obtain a MediaProjection instance. Strategy:
     *   1. Reuse the token from ScreenCaptureService if available.
     *   2. Try to create from ScreenCaptureService's saved result code + data.
     *   3. Best-effort restore from SharedPreferences (will likely fail on Android 14+).
     */
    private fun obtainMediaProjection(): Boolean {
        // Strategy 1: Reuse existing projection token
        val existingProjection = ScreenCaptureService.projectionToken
        if (existingProjection != null) {
            mediaProjection = existingProjection
            Log.d(TAG, "Reused MediaProjection from ScreenCaptureService.projectionToken")
            return true
        }

        // Strategy 2: Create from saved result code + data
        val resultCode = ScreenCaptureService.savedResultCode
        val resultData = ScreenCaptureService.savedResultData
        if (resultCode != 0 && resultData != null) {
            try {
                val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val projection = pm.getMediaProjection(resultCode, resultData)
                if (projection != null) {
                    mediaProjection = projection
                    Log.d(TAG, "Created MediaProjection from ScreenCaptureService saved data")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "getMediaProjection from saved data failed: $e")
            }
        }

        // Strategy 2b: Try restoring from Parcel bytes (preserves Binder)
        val parcelBytes = ScreenCaptureService.savedResultDataParcelBytes
        val savedCode = ScreenCaptureService.savedResultCode
        if (parcelBytes != null && savedCode != 0) {
            try {
                val parcel = android.os.Parcel.obtain()
                parcel.unmarshall(parcelBytes, 0, parcelBytes.size)
                parcel.setDataPosition(0)
                val restoredIntent = Intent.CREATOR.createFromParcel(parcel)
                parcel.recycle()

                val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val projection = pm.getMediaProjection(savedCode, restoredIntent)
                if (projection != null) {
                    mediaProjection = projection
                    Log.d(TAG, "Created MediaProjection from Parcel bytes")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "getMediaProjection from Parcel bytes failed: $e")
            }
        }

        // Strategy 3: Best-effort restore from SharedPreferences
        // NOTE: Intent.toUri(0) loses the Binder extra, so this will likely
        // fail on Android 14+. Included for completeness.
        try {
            val prefs = getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            val code = prefs.getInt("projection_result_code", 0)
            val uriStr = prefs.getString("projection_result_data_uri", null)
            if (code != 0 && uriStr != null) {
                val uri = android.net.Uri.parse(uriStr)
                val data = Intent.parseUri(uri.toString(), 0)
                val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val projection = pm.getMediaProjection(code, data)
                if (projection != null) {
                    mediaProjection = projection
                    Log.d(TAG, "Created MediaProjection from SharedPreferences (best-effort)")
                    return true
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Best-effort projection restore from prefs failed: $e")
        }

        Log.e(TAG, "All MediaProjection acquisition strategies failed")
        return false
    }

    // ── Frame capture pipeline ─────────────────────────────────────────────

    /**
     * Start the VirtualDisplay + ImageReader frame capture pipeline.
     * Frames are captured on a background HandlerThread, compressed to JPEG,
     * and pushed to the WebSocket connection.
     */
    private fun startFrameCapture(): Boolean {
        val projection = mediaProjection
        if (projection == null) {
            Log.e(TAG, "startFrameCapture: No MediaProjection available")
            return false
        }

        try {
            imageReader = ImageReader.newInstance(
                CAPTURE_WIDTH, CAPTURE_HEIGHT, PixelFormat.RGBA_8888, 2
            )

            virtualDisplay = projection.createVirtualDisplay(
                "FamilyMonitorStream",
                CAPTURE_WIDTH, CAPTURE_HEIGHT, getDensityDpi(),
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                object : VirtualDisplay.Callback() {
                    override fun onStopped() {
                        Log.w(TAG, "VirtualDisplay stopped")
                        if (streaming.get()) {
                            // Attempt to restart capture
                            captureHandler?.postDelayed({
                                if (streaming.get()) {
                                    stopFrameCapture()
                                    startFrameCapture()
                                }
                            }, 2000L)
                        }
                    }
                },
                captureHandler
            )

            // Start periodic frame polling
            startFramePolling()

            Log.d(TAG, "Frame capture started: ${CAPTURE_WIDTH}x${CAPTURE_HEIGHT} @ ${TARGET_FPS}fps")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "startFrameCapture failed: $e")
            stopFrameCapture()
            return false
        }
    }

    /**
     * Poll ImageReader for new frames at the target FPS.
     * We use polling instead of setOnImageAvailableListener because we want
     * precise control over frame rate and don't want to process every frame
     * the display produces.
     */
    private fun startFramePolling() {
        val handler = captureHandler ?: return
        val reader = imageReader ?: return

        frameRunnable = object : Runnable {
            override fun run() {
                if (!streaming.get()) return

                var image: Image? = null
                try {
                    image = reader.acquireLatestImage()
                    if (image != null) {
                        val jpegBytes = processFrame(image)
                        if (jpegBytes != null) {
                            latestFrameBytes = jpegBytes
                            frameCount++
                            lastFrameTimestamp = System.currentTimeMillis()

                            // Log every 100 frames
                            if (frameCount % 100 == 0L) {
                                Log.d(TAG, "Frame count: $frameCount, " +
                                        "size: ${jpegBytes.size} bytes, " +
                                        "ws=${if (wsConnected) "connected" else "disconnected"}")
                            }

                            // Send frame over WebSocket
                            sendFrame(jpegBytes)
                        }
                    }
                } catch (e: Exception) {
                    // ImageReader can throw if the surface was disconnected
                    Log.w(TAG, "Frame capture error: $e")
                } finally {
                    image?.close()
                }

                // Schedule next frame capture
                if (streaming.get()) {
                    handler.postDelayed(this, FRAME_INTERVAL_MS)
                }
            }
        }

        handler.post(frameRunnable!!)
    }

    /**
     * Process a captured Image into JPEG bytes.
     * Handles row padding on devices where rowStride > width * pixelStride.
     */
    private fun processFrame(image: Image): ByteArray? {
        val planes = image.planes
        if (planes.isEmpty()) return null

        val buffer = planes[0].buffer
        val rowStride = planes[0].rowStride
        val pixelStride = planes[0].pixelStride

        val bmp = Bitmap.createBitmap(CAPTURE_WIDTH, CAPTURE_HEIGHT, Bitmap.Config.ARGB_8888)
        buffer.rewind()

        try {
            // Handle row padding (some devices have rowStride > width * pixelStride)
            if (rowStride == CAPTURE_WIDTH * pixelStride) {
                // No padding — fast path
                bmp.copyPixelsFromBuffer(buffer)
            } else {
                // Row-by-row copy to handle padding
                val rowBytes = CAPTURE_WIDTH * pixelStride
                for (y in 0 until CAPTURE_HEIGHT) {
                    buffer.position(y * rowStride)
                    val rowBuffer = ByteArray(rowBytes)
                    buffer.get(rowBuffer, 0, rowBytes)
                    bmp.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(rowBuffer))
                }
            }

            // Compress to JPEG
            val outputStream = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, outputStream)
            return outputStream.toByteArray()
        } catch (e: Exception) {
            Log.w(TAG, "Frame processing error: $e")
            return null
        } finally {
            bmp.recycle()
        }
    }

    private fun stopFrameCapture() {
        frameRunnable?.let { captureHandler?.removeCallbacks(it) }
        frameRunnable = null
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        Log.d(TAG, "Frame capture stopped")
    }

    private fun getDensityDpi(): Int {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(metrics)
        return metrics.densityDpi
    }

    // ── WebSocket client ───────────────────────────────────────────────────

    private fun connectWebSocket() {
        if (!connecting.compareAndSet(false, true)) {
            Log.d(TAG, "WebSocket connection already in progress")
            return
        }

        try {
            val wsUrl = buildWsUrl()
            Log.d(TAG, "Connecting WebSocket to: $wsUrl")

            val request = Request.Builder()
                .url(wsUrl)
                .build()

            webSocket = okHttpClient?.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    Log.d(TAG, "WebSocket connected: ${response.code}")
                    wsConnected = true
                    connecting.set(false)
                    reconnectAttempts = 0

                    // Send any buffered frame
                    latestFrameBytes?.let { sendFrame(it) }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    // Server may send text messages (e.g., control messages)
                    Log.d(TAG, "WebSocket text message: $text")
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    Log.d(TAG, "WebSocket closing: code=$code reason=$reason")
                    webSocket.close(1000, null)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    Log.d(TAG, "WebSocket closed: code=$code reason=$reason")
                    wsConnected = false
                    connecting.set(false)
                    scheduleReconnect()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Log.e(TAG, "WebSocket failure: ${t.message}")
                    wsConnected = false
                    connecting.set(false)
                    scheduleReconnect()
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "WebSocket connection error: $e")
            connecting.set(false)
            scheduleReconnect()
        }
    }

    private fun buildWsUrl(): String {
        // Normalize: strip trailing slash from server URL
        val base = serverUrl.trimEnd('/')
        // Parse and append query params
        return if (base.contains("?")) {
            "$base&role=child&uid=$childUid"
        } else {
            "$base?role=child&uid=$childUid"
        }
    }

    /**
     * Send a JPEG frame as a binary WebSocket message.
     * Frames are dropped silently if WebSocket is not connected — the relay
     * server delivers the latest frame to parents, so occasional drops are fine.
     */
    private fun sendFrame(jpegBytes: ByteArray) {
        val ws = webSocket
        if (ws == null || !wsConnected) {
            // Frame buffered in latestFrameBytes — will be sent on reconnect
            return
        }
        try {
            ws.send(okio.Buffer().write(jpegBytes))
        } catch (e: Exception) {
            Log.w(TAG, "WebSocket send failed: ${e.message}")
        }
    }

    private fun disconnectWebSocket() {
        try {
            webSocket?.close(1000, "Service stopping")
        } catch (_: Exception) {}
        webSocket = null
        wsConnected = false
        connecting.set(false)
    }

    /**
     * Schedule a WebSocket reconnect with exponential backoff.
     * Backoff: 1s → 2s → 4s → 8s → 16s → 30s (max)
     */
    private fun scheduleReconnect() {
        if (!streaming.get()) return  // Don't reconnect if we're stopping

        synchronized(reconnectLock) {
            val delay = minOf(
                (RECONNECT_BASE_MS * Math.pow(RECONNECT_MULTIPLIER, reconnectAttempts.toDouble())).toLong(),
                RECONNECT_MAX_MS
            )
            reconnectAttempts++

            Log.d(TAG, "Scheduling WebSocket reconnect in ${delay}ms (attempt $reconnectAttempts)")

            captureHandler?.postDelayed({
                if (streaming.get() && !wsConnected) {
                    connectWebSocket()
                }
            }, delay)
        }
    }

    // ── Foreground service ─────────────────────────────────────────────────

    private fun startFgForeground() {
        createChannel()
        val n = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                // Use combined mediaProjection + dataSync type.
                // mediaProjection requires the token to be active; we start with
                // dataSync first, then upgrade once we have the projection.
                val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // API 34+: can combine foreground service types
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                }
                startForeground(NOTIFICATION_ID, n, serviceType)
                Log.d(TAG, "Foreground started with type: $serviceType")
            } catch (e: Exception) {
                Log.w(TAG, "startForeground with type failed, untyped fallback: $e")
                try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
            }
        } else {
            try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
        }
    }

    /**
     * Upgrade foreground service type to include MEDIA_PROJECTION
     * after we successfully obtain the projection token.
     */
    private fun upgradeFgToMediaProjection() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                createChannel()
                val n = buildNotification()
                val serviceType =
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                startForeground(NOTIFICATION_ID, n, serviceType)
                Log.d(TAG, "Foreground upgraded to MEDIA_PROJECTION | DATA_SYNC")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to upgrade foreground to MEDIA_PROJECTION: $e")
            }
        }
    }

    // ── Wake lock ──────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG
            ).also {
                it.setReferenceCounted(false)
                it.acquire(12 * 60 * 60 * 1000L)  // 12 hours max
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

    // ── Notification ───────────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
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

        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, ScreenStreamService::class.java).apply {
                action = ACTION_STOP_STREAM
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Family Monitor — Streaming")
            .setContentText("Screen stream active ($childUid)")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop Stream",
                stopIntent
            )
            .build()
    }
}
