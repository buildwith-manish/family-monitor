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

class ScreenCaptureService : Service() {
    companion object {
        const val ACTION_START = "START_SCREEN_CAPTURE"
        const val ACTION_STOP  = "STOP_SCREEN_CAPTURE"
        const val EXTRA_RESULT_CODE = "RESULT_CODE"
        const val EXTRA_RESULT_DATA = "RESULT_DATA"
        const val CHANNEL_ID = "screen_capture_channel"
        const val NOTIFICATION_ID = 1001
        @Volatile var instance: ScreenCaptureService? = null
    }
    inner class LocalBinder : Binder() { fun getService() = this@ScreenCaptureService }
    private val binder = LocalBinder()
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    var resultCode: Int = 0
    var resultData: Intent? = null

    override fun onCreate() { super.onCreate(); instance = this; createNotificationChannel() }
    override fun onBind(intent: Intent?): IBinder = binder
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                else intent.getParcelableExtra(EXTRA_RESULT_DATA)
                startCaptureWithForeground()
            }
            ACTION_STOP -> stopSelf()
        }
        return START_NOT_STICKY
    }
    private fun startCaptureWithForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(NOTIFICATION_ID, notification)
        val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = pm.getMediaProjection(resultCode, resultData!!)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            mediaProjection?.registerCallback(object : MediaProjection.Callback() { override fun onStop() { stopSelf() } }, null)
        }
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val width: Int; val height: Int; val dpi: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds; width = b.width(); height = b.height(); dpi = resources.configuration.densityDpi
        } else {
            val m = DisplayMetrics(); @Suppress("DEPRECATION") wm.defaultDisplay.getMetrics(m); width = m.widthPixels; height = m.heightPixels; dpi = m.densityDpi
        }
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        virtualDisplay = mediaProjection?.createVirtualDisplay("FamilyMonitorCapture", width, height, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, imageReader!!.surface, null, null)
    }
    fun getProjectionParams(): Pair<Int, Intent>? { val d = resultData ?: return null; return Pair(resultCode, d) }
    override fun onDestroy() { virtualDisplay?.release(); imageReader?.close(); mediaProjection?.stop(); instance = null; super.onDestroy() }
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Screen Sharing", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
    private fun buildNotification(): Notification = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Screen sharing active")
        .setContentText("Your screen is visible to your parent")
        .setSmallIcon(android.R.drawable.ic_menu_view)
        .setPriority(NotificationCompat.PRIORITY_LOW).setOngoing(true).build()
}
