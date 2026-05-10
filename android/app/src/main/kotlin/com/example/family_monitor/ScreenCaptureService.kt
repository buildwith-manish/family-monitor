package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat

/**
 * ScreenCaptureService — foreground service that holds a MediaProjection token.
 *
 * Lifecycle:
 *   1. MainActivity receives RESULT_OK from createScreenCaptureIntent() consent dialog.
 *   2. MainActivity calls startForegroundService(intent) with ACTION_START + result code/data.
 *   3. This service calls startForeground() immediately (required within 5 s on Android 8+).
 *   4. flutter_webrtc's getDisplayMedia() uses the MediaProjection token via the plugin bridge.
 *   5. ACTION_STOP releases all resources and calls stopSelf().
 *
 * Android 10+ requires FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION in the manifest.
 * Android 14+ requires FOREGROUND_SERVICE_MEDIA_PROJECTION permission in the manifest.
 */
class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "START_SCREEN_CAPTURE"
        const val ACTION_STOP  = "STOP_SCREEN_CAPTURE"
        const val EXTRA_RESULT_CODE = "RESULT_CODE"
        const val EXTRA_RESULT_DATA = "RESULT_DATA"
        const val CHANNEL_ID = "screen_capture_channel"
        const val NOTIFICATION_ID = 1001

        /** Singleton held by MainActivity so the WebRTC plugin can reach it. */
        @Volatile var instance: ScreenCaptureService? = null
    }

    inner class LocalBinder : Binder() {
        fun getService(): ScreenCaptureService = this@ScreenCaptureService
    }

    private val binder = LocalBinder()

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    // Stored so flutter_webrtc can use them via getProjectionParams()
    var resultCode: Int = 0
    var resultData: Intent? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
                startCaptureWithForeground()
            }
            ACTION_STOP -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startCaptureWithForeground() {
        val notification = buildNotification()

        // Android 10+ requires the correct foreground service type for MediaProjection.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val data = resultData ?: return
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)

        // Register a callback so we know when the user revokes the token.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { stopSelf() }
            }, null)
        }

        // Create a VirtualDisplay so the projection token is valid for flutter_webrtc.
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val width: Int
        val height: Int
        val dpi: Int

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            width  = bounds.width()
            height = bounds.height()
            dpi    = resources.configuration.densityDpi
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getMetrics(metrics)
            width  = metrics.widthPixels
            height = metrics.heightPixels
            dpi    = metrics.densityDpi
        }

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "FamilyMonitorCapture",
            width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null, null
        )
    }

    /**
     * Called from MainActivity's MethodChannel so flutter_webrtc can obtain
     * the MediaProjection token for its internal getDisplayMedia() call.
     */
    fun getProjectionParams(): Pair<Int, Intent>? {
        val data = resultData ?: return null
        return Pair(resultCode, data)
    }

    override fun onDestroy() {
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        instance = null
        super.onDestroy()
    }

    // ── Notification helpers ──────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Sharing",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Visible whenever your screen is shared with the parent"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Screen sharing active")
            .setContentText("Your screen is visible to your parent — tap to open Family Monitor")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
}
