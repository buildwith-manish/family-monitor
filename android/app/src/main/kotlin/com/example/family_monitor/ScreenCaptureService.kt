package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class ScreenCaptureService : Service() {

    companion object {
        private const val TAG                = "ScreenCaptureService"
        const val ACTION_START               = "START_SCREEN_CAPTURE"
        const val ACTION_STOP                = "STOP_SCREEN_CAPTURE"
        const val ACTION_START_SILENT        = "START_SCREEN_CAPTURE_SILENT"
        const val ACTION_PERMISSION_REQUIRED = "com.example.family_monitor.PROJECTION_PERMISSION_REQUIRED"
        const val EXTRA_RESULT_CODE          = "RESULT_CODE"
        const val EXTRA_RESULT_DATA          = "RESULT_DATA"
        const val CHANNEL_ID                 = "fm_bg_sync"
        const val NOTIFICATION_ID            = 1001

        @Volatile var instance: ScreenCaptureService? = null
        @Volatile var savedResultCode: Int             = 0
        @Volatile var savedResultData: Intent?         = null
        @Volatile var projectionToken: MediaProjection? = null
        @Volatile private var starting: Boolean        = false
    }

    inner class LocalBinder : Binder() { fun getService() = this@ScreenCaptureService }
    private val binder            = LocalBinder()
    private val mainHandler       = Handler(Looper.getMainLooper())
    private var mediaProjection: MediaProjection? = null
    var resultCode: Int     = 0
    var resultData: Intent? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        Log.d(TAG, "onCreate")
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
                startCaptureSafe()
            }
            ACTION_START_SILENT -> {
                resultCode = savedResultCode
                resultData = savedResultData
                if (resultCode != 0 && resultData != null) startCaptureSafe()
                else requestPermissionViaUi()
            }
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            null -> {
                // OS restart via START_STICKY
                if (savedResultCode != 0 && savedResultData != null) {
                    resultCode = savedResultCode
                    resultData = savedResultData
                    startCaptureSafe()
                } else {
                    // Cannot silently re-acquire — notify app so UI can ask user
                    requestPermissionViaUi()
                }
            }
        }
        return START_STICKY
    }

    /** Launch the consent activity so the user explicitly re-grants the token. */
    private fun requestPermissionViaUi() {
        startFgWithoutCapture()
        sendBroadcast(Intent(ACTION_PERMISSION_REQUIRED).apply {
            setPackage(packageName)
        })
        // Also try to surface the main activity
        try {
            startActivity(
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                } ?: return
            )
        } catch (_: Exception) {}
    }

    private fun startCaptureSafe() {
        if (starting) return
        starting = true
        try {
            startFg()
            val pm   = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val data = resultData ?: run { starting = false; return }
            teardownProjection()
            mediaProjection = pm.getMediaProjection(resultCode, data)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        Log.w(TAG, "MediaProjection stopped by system")
                        mainHandler.post { teardownProjection() }
                    }
                }, mainHandler)
            }
            projectionToken = mediaProjection
        } catch (e: Exception) {
            Log.e(TAG, "startCaptureSafe failed: $e")
            requestPermissionViaUi()
        } finally {
            starting = false
        }
    }

    private fun startFg() {
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, n,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } catch (e: Exception) {
                Log.w(TAG, "Typed startForeground failed, falling back: $e")
                try { startForeground(NOTIFICATION_ID, n) } catch (e2: Exception) {
                    Log.e(TAG, "Untyped startForeground also failed: $e2")
                }
            }
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun startFgWithoutCapture() {
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, n,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } catch (e: Exception) {
                Log.w(TAG, "startFgWithoutCapture typed failed: $e")
                try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
            }
        } else {
            try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
        }
    }

    private fun teardownProjection() {
        try { mediaProjection?.stop() }   catch (_: Exception) {}
        projectionToken = null
        mediaProjection = null
    }

    /** Reinitialise the virtual display after a peer reconnect. */
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

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        WatchdogReceiver.schedule(applicationContext)
    }

    override fun onDestroy() {
        teardownProjection()
        instance = null
        WatchdogReceiver.schedule(applicationContext)
        Log.d(TAG, "onDestroy — watchdog rescheduled")
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return   // already exists
            val ch = NotificationChannel(CHANNEL_ID, "Background Services",
                NotificationManager.IMPORTANCE_LOW).apply {
                description    = "Required background service"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Family Monitor — Active")
            .setContentText("Screen monitoring is running.")
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openIntent)
            .build()
    }
}
